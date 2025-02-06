import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

class ProcessManager {
  static final Map<String, _GameProcess> _runningProcesses = {};
  static final _logger = Logger('ProcessManager');

  static void registerProcess(String id, Process process, {
    required String prefixPath,
    required String exePath,
  }) {
    _logger.info('Registering process for: $id (PID: ${process.pid})');
    _logger.info('Using prefix: $prefixPath');
    _logger.info('Executable: $exePath');
    
    _runningProcesses[id] = _GameProcess(
      process: process,
      prefixPath: prefixPath,
      exePath: exePath,
    );
  }

  static Future<void> killProcess(String id) async {
    _logger.info('Attempting to kill process for: $id');
    final gameProcess = _runningProcesses[id];
    if (gameProcess != null) {
      try {
        // Kill the main process
        gameProcess.process.kill();
        await gameProcess.process.exitCode;
        _logger.info('Killed main process for: $id');

        // Kill wine processes for this specific prefix/exe
        if (Platform.isLinux) {
          await killWineProcess(gameProcess.prefixPath);
        }
      } catch (e) {
        _logger.severe('Error killing process: $e');
      } finally {
        _runningProcesses.remove(id);
      }
    }
  }

  static bool isProcessRunning(String id) {
    return _runningProcesses.containsKey(id);
  }

  static void killAll() {
    _logger.info('Killing all processes');
    for (final gameProcess in _runningProcesses.values) {
      try {
        gameProcess.process.kill();
        if (Platform.isLinux) {
          killWineProcess(gameProcess.prefixPath);
        }
      } catch (e) {
        _logger.severe('Error killing process: $e');
      }
    }
    _runningProcesses.clear();
  }

  static Future<void> killWineProcess(String prefixPath) async {
    if (!Platform.isLinux) return;
    
    _logger.info('Attempting to kill wine processes for prefix: $prefixPath');
    
    try {
      // First try wineserver shutdown
      await Process.run('wineserver', ['-w'], environment: {
        'WINEPREFIX': prefixPath,
      });

      // Kill all wine-related processes forcefully
      var processes = ['wine', 'wine64', 'wineserver', 'services.exe', 'winedevice.exe'];
      
      for (var proc in processes) {
        // Try SIGTERM first
        await Process.run('killall', [proc], environment: {
          'WINEPREFIX': prefixPath,
        });
        
        // Wait a moment
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Then force kill with SIGKILL
        await Process.run('killall', ['-9', proc], environment: {
          'WINEPREFIX': prefixPath,
        });
      }

      // Final aggressive cleanup using pkill
      await Process.run('pkill', ['-9', '-f', 'wine']);
      await Process.run('pkill', ['-9', '-f', 'wineserver']);
      
      _logger.info('Completed wine process cleanup for prefix: $prefixPath');
    } catch (e) {
      _logger.severe('Error killing wine processes: $e');
    }
  }

  static Future<void> killWineWindows() async {
    if (!Platform.isLinux) return;
    
    _logger.info('Attempting to kill Wine windows');
    
    try {
      // Get list of all windows using wmctrl
      final result = await Process.run('wmctrl', ['-l']);
      
      if (result.exitCode == 0) {
        // Parse window IDs for Wine windows
        final windowLines = (result.stdout as String)
            .split('\n')
            .where((line) => line.toLowerCase().contains('wine'));

        for (final line in windowLines) {
          // Extract window ID (hex format at start of line)
          final idMatch = RegExp(r'^0x[0-9a-f]+').firstMatch(line);
          if (idMatch != null) {
            final windowId = idMatch.group(0);
            _logger.info('Killing Wine window: $windowId');
            
            // Close window
            await Process.run('wmctrl', ['-ic', windowId!]);
          }
        }
      }

      // Wait a moment for windows to close
      await Future.delayed(const Duration(seconds: 1));

      // Cleanup any remaining Wine processes
      await Process.run('wineserver', ['-k']);
      
      _logger.info('Completed Wine window cleanup');
    } catch (e) {
      _logger.severe('Error killing Wine windows: $e');
    }
  }

  static Future<bool> checkGraphicsRequirements() async {
    if (!Platform.isLinux) return true;
    
    try {
      // Check for Vulkan support
      final vulkanResult = await Process.run('vulkaninfo', []);
      if (vulkanResult.exitCode != 0) {
        _logger.warning('Vulkan not properly configured on system');
        return false;
      }

      // Check for DXVK
      final dxvkResult = await Process.run('wine', ['--version']);
      if (!dxvkResult.stdout.toString().toLowerCase().contains('dxvk')) {
        _logger.warning('DXVK not detected in Wine installation');
        return false;
      }

      return true;
    } catch (e) {
      _logger.severe('Error checking graphics requirements: $e');
      return false;
    }
  }

  static Map<String, String> getWineEnvironment(String prefixPath, String exePath) {
    return {
      'WINEPREFIX': prefixPath,
      // Enable VKD3D for DX12
      'ENABLE_VKD3D_SHADER_CACHE': '1',
      'VKD3D_CONFIG': 'dxr',  // Enable DXR (DirectX Raytracing) if available
      'VKD3D_FEATURE_LEVEL': '12_0',
      'VKD3D_SHADER_CACHE_PATH': path.join(prefixPath, 'vkd3d-cache'),
      // DXVK settings for DX11
      'DXVK_STATE_CACHE': '1',
      'DXVK_STATE_CACHE_PATH': path.dirname(exePath),
      'DXVK_ASYNC': '1',
      'DXVK_SHADER_DUMP_PATH': path.join(prefixPath, 'shaders'),
      // General Wine settings
      'WINE_LARGE_ADDRESS_AWARE': '1',
      'STAGING_SHARED_MEMORY': '1',
      'WINE_ENABLE_PIPE_SYNC_FOR_APP': '1',
      'PROTON_FORCE_LARGE_ADDRESS_AWARE': '1',
      // Debug info
      'DXVK_LOG_LEVEL': 'info',
      'DXVK_HUD': '1',
      'VKD3D_DEBUG': 'warn',
    };
  }

  static Future<bool> cleanupPrefix(String prefixPath) async {
    _logger.info('Cleaning up prefix at: $prefixPath');
    
    try {
      final directory = Directory(prefixPath);
      
      // Check if directory exists
      if (await directory.exists()) {
        // Kill any wine processes using this prefix
        await killWineProcess(prefixPath);
        
        // Wait a moment for processes to clean up
        await Future.delayed(const Duration(seconds: 2));

        // List all contents before deletion
        await for (final entity in directory.list(recursive: true)) {
          try {
            await entity.delete(recursive: true);
            _logger.info('Deleted: ${entity.path}');
          } catch (e) {
            _logger.warning('Failed to delete ${entity.path}: $e');
          }
        }
        
        // Try to delete the main directory
        try {
          await directory.delete(recursive: true);
        } catch (e) {
          _logger.warning('Failed to delete main directory: $e');
          // If deletion fails, try to clear contents
          await Process.run('rm', ['-rf', path.join(prefixPath, '*')]);
        }
        
        // Create fresh directory
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        
        _logger.info('Successfully cleaned up prefix directory');
        return true;
      } else {
        // Directory doesn't exist, create it
        await directory.create(recursive: true);
        return true;
      }
    } catch (e) {
      _logger.severe('Error cleaning up prefix: $e');
      
      // Last resort: use system commands to force cleanup
      try {
        await Process.run('rm', ['-rf', prefixPath]);
        await Directory(prefixPath).create(recursive: true);
        return true;
      } catch (e2) {
        _logger.severe('Failed even with force cleanup: $e2');
        return false;
      }
    }
  }

  static Future<bool> verifyPrefixPath(String prefixPath) async {
    try {
      final directory = Directory(prefixPath);
      
      // Check if path exists and is writable
      if (await directory.exists()) {
        // Try to create a test file
        final testFile = File(path.join(prefixPath, '.test_write'));
        await testFile.writeAsString('test');
        await testFile.delete();
        return true;
      } else {
        // Try to create the directory
        await directory.create(recursive: true);
        return true;
      }
    } catch (e) {
      _logger.severe('Error verifying prefix path: $e');
      return false;
    }
  }

  static Future<bool> prepareWineInstallation(String prefixPath) async {
    _logger.info('Preparing Wine installation at: $prefixPath');
    
    try {
      // First kill any wine processes
      await killWineProcess(prefixPath);
      await Future.delayed(const Duration(seconds: 2));

      // Handle the nested wine directory case
      final wineDir = Directory(prefixPath);
      final nestedWineDir = Directory(path.join(prefixPath, path.basename(prefixPath)));
      
      // Remove both directories if they exist
      for (var dir in [nestedWineDir, wineDir]) {
        if (await dir.exists()) {
          _logger.info('Removing existing directory: ${dir.path}');
          
          // First try Dart's delete
          try {
            await dir.delete(recursive: true);
          } catch (e) {
            _logger.warning('Failed to delete using Dart: $e');
            
            // If that fails, use rm -rf
            final result = await Process.run('rm', ['-rf', dir.path]);
            if (result.exitCode != 0) {
              _logger.severe('Failed to remove directory using rm -rf: ${result.stderr}');
              return false;
            }
          }
          
          // Wait until directory is actually gone
          while (await dir.exists()) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }

      // Create fresh directory
      await wineDir.create(recursive: true);
      
      _logger.info('Successfully prepared Wine installation directory');
      return true;
    } catch (e) {
      _logger.severe('Error preparing Wine installation: $e');
      return false;
    }
  }
}

class _GameProcess {
  final Process process;
  final String prefixPath;
  final String exePath;

  _GameProcess({
    required this.process,
    required this.prefixPath,
    required this.exePath,
  });
} 