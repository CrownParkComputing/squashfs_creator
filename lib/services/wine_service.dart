import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../models/wine_prefix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_prefix_association.dart';
import '../models/wine_build.dart';
import '../utils/process_manager.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;

final _logger = Logger('WineService');

class WineService {
  static const Map<String, Map<String, String>> availableVersions = {
    'GE-Proton': {
      'GE-Proton9-23': 'GE-Proton9-23.tar.gz',  // Latest GE-Proton release
    },
  };

  static const Map<String, String> dependencyUrls = {
    'vcredist_2022': 'https://aka.ms/vs/17/release/vc_redist.x64.exe',
    'vcredist_2019': 'https://aka.ms/vs/16/release/vc_redist.x64.exe',
    'vcredist_2017': 'https://download.microsoft.com/download/2/B/C/2BC2E7B3-3B11-4C8C-BBC4-F7C92666E1DF/vc_redist.x64.exe',
    'vcredist_2015': 'https://download.microsoft.com/download/6/A/A/6AA4EDFF-645B-48C5-81CC-ED5963AEAD48/vc_redist.x64.exe',
    'dxvk': 'https://github.com/doitsujin/dxvk/releases/download/v2.3.1/dxvk-2.3.1.tar.gz',
    'vkd3d': 'https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v2.11/vkd3d-proton-2.11.tar.zst',
  };

  final void Function(String)? logCallback;
  String? _cachedBaseDir;

  WineService({this.logCallback});

  Future<String> get baseDir async {
    if (_cachedBaseDir != null) return _cachedBaseDir!;
    final prefs = await SharedPreferences.getInstance();
    _cachedBaseDir = prefs.getString('prefix_base_dir') ?? 
                     path.join(Platform.environment['HOME']!, '.wine_prefixes');
    return _cachedBaseDir!;
  }

  // Download and setup methods
  Future<void> downloadAndSetupPrefix(String version, String prefixName) async {
    try {
      onLog('Starting download of $version...');
      
      final downloadDir = Directory(path.join(await baseDir, 'downloads'));
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final downloadPath = path.join(downloadDir.path, version);
      final prefixDir = Directory(path.join(await baseDir, version, prefixName));
      
      // Check if prefix already exists
      if (await prefixDir.exists()) {
        throw Exception('Prefix "$prefixName" already exists');
      }

      // Get download URL based on version
      final url = _getDownloadUrl(version);
      
      // Download and extract Proton
      onLog('Downloading Proton...');
      final response = await HttpClient().getUrl(Uri.parse(url));
      final httpResponse = await response.close();
      
      if (httpResponse.statusCode != 200) {
        throw Exception('Failed to download: ${httpResponse.statusCode}');
      }

      final file = File(downloadPath);
      await httpResponse.pipe(file.openWrite());

      // Extract and setup
      await _extractAndSetupPrefix(downloadPath, version, prefixName);
      
      // Cleanup download
      await file.delete();

      onLog('Prefix setup complete!');

      // Create WinePrefix object
      final prefix = WinePrefix(
        path: path.join(prefixDir.path, 'pfx'),
        version: version,
        name: prefixName,
        created: DateTime.now(),
        is64Bit: true,
      );

      onLog('Prefix setup and initialization complete!');

    } catch (e) {
      onLog('Error during setup: $e');
      rethrow;
    }
  }

  String _getDownloadUrl(String version) {
    // Only handle GE-Proton releases
    return 'https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$version/$version.tar.gz';
  }

  Future<void> _extractAndSetupPrefix(String archivePath, String version, String prefixName) async {
    try {
      final prefixDir = Directory(path.join(await baseDir, version, prefixName));
      
      // Clean up existing prefix if it exists
      if (await prefixDir.exists()) {
        onLog('Cleaning up existing prefix...');
        if (!await ProcessManager.cleanupPrefix(prefixDir.path)) {
          throw Exception('Failed to clean up existing prefix');
        }
      }

      // Create fresh directory
      await prefixDir.create(recursive: true);

      onLog('Extracting archive...');
      await Process.run('tar', ['xzf', archivePath, '-C', prefixDir.path]);
      
      // Create the prefix directory
      final pfxDir = Directory(path.join(prefixDir.path, 'pfx'));
      if (!await pfxDir.exists()) {
        await pfxDir.create(recursive: true);
      }

      // Initialize the prefix using Proton's Python script
      onLog('Initializing prefix...');
      final protonPath = path.join(prefixDir.path, version, 'proton');
      
      if (!await File(protonPath).exists()) {
        throw Exception('Proton script not found at: $protonPath');
      }

      final result = await Process.run(
        'python3',
        [protonPath, 'run', 'wineboot', '--init'],
        environment: {
          'STEAM_COMPAT_CLIENT_INSTALL_PATH': prefixDir.path,
          'STEAM_COMPAT_DATA_PATH': pfxDir.path,
          'WINEPREFIX': pfxDir.path,
          'WINEARCH': 'win64',
          'DXVK_ASYNC': '1',
          'PROTON_NO_ESYNC': '0',
          'PROTON_NO_FSYNC': '0',
          'PROTON_HIDE_NVIDIA_GPU': '0',
          'PROTON_ENABLE_NVAPI': '1',
        },
      );

      if (result.exitCode != 0) {
        throw Exception('Failed to initialize prefix: ${result.stderr}');
      }

      onLog('Prefix setup complete!');
    } catch (e) {
      onLog('Error during extraction/setup: $e');
      rethrow;
    }
  }

  Future<Process> launchExe(String exePath, WinePrefix prefix, {Map<String, String>? environment}) async {
    final baseEnv = {
      'WINEPREFIX': prefix.path,
      'WINEARCH': prefix.is64Bit ? 'win64' : 'win32',
      // VKD3D settings
      'VKD3D_CONFIG': 'dxr',
      'VKD3D_FEATURE_LEVEL': '12_1',
      'VKD3D_SHADER_CACHE': '1',
      'VKD3D_DEBUG': 'warn',
      // DXVK settings
      'DXVK_ASYNC': '1',
      'DXVK_STATE_CACHE': '1',
      // General settings
      'WINE_LARGE_ADDRESS_AWARE': '1',
      'STAGING_SHARED_MEMORY': '1',
      ...?environment,
    };

    if (prefix.isProton) {
      baseEnv.addAll({
        'STEAM_COMPAT_CLIENT_INSTALL_PATH': prefix.protonDir,
        'STEAM_COMPAT_DATA_PATH': prefix.path,
        'PROTON_ENABLE_NVAPI': '1',
        'PROTON_HIDE_NVIDIA_GPU': '0',
      });

      return Process.start(
        'python3',
        [prefix.winePath, 'run', exePath],
        environment: baseEnv,
        workingDirectory: path.dirname(exePath),
      );
    } else {
      return Process.start(
        prefix.winePath,
        [exePath],
        environment: baseEnv,
        workingDirectory: path.dirname(exePath),
      );
    }
  }

  Future<void> _launchWithProton(
    String exePath, 
    WinePrefix prefix, {
    Map<String, String>? environment,
  }) async {
    final versionDir = path.dirname(prefix.path);
    final geProtonDir = path.join(versionDir, prefix.version);
    final protonPath = path.join(geProtonDir, 'proton');

    if (!await File(protonPath).exists()) {
      throw Exception('Proton script not found at: $protonPath');
    }

    if (!await File(exePath).exists()) {
      throw Exception('Executable not found at: $exePath');
    }

    onLog('Using Proton at: $protonPath');
    onLog('Launching: $exePath');

    final env = {
      'STEAM_COMPAT_CLIENT_INSTALL_PATH': geProtonDir,
      'STEAM_COMPAT_DATA_PATH': prefix.path,
      'WINEPREFIX': prefix.path,
      'WINEARCH': 'win64',
      'PROTON_ENABLE_NVAPI': '1',
      'PROTON_ENABLE_FSYNC': '1',
      'PROTON_HIDE_NVIDIA_GPU': '0',
      'DXVK_ASYNC': '1',
      ...?environment,
    };

    final workingDir = path.dirname(exePath);
    
    final process = await Process.start(
      'python3',
      [protonPath, 'run', exePath],
      environment: env,
      workingDirectory: workingDir,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('Process exited with code $exitCode');
    }
  }

  Future<void> _launchWithWine(
    String exePath, 
    WinePrefix prefix, {
    Map<String, String>? environment,
  }) async {
    try {
      // First check if DXVK is installed
      if (!await _isDXVKInstalled(prefix)) {
        onLog('DXVK not found, installing...');
        await installDependencies(prefix, ['dxvk']);
      }

      // Check for common dependencies
      if (!await _hasCommonDependencies(prefix)) {
        onLog('Installing common dependencies...');
        await installDependencies(prefix, [
          'vcrun2019',
          'vcrun2017',
          'd3dx9',
          'xact',
        ]);
      }

      final prefixParent = path.dirname(prefix.path);
      final winePath = path.join(prefixParent, 'bin', 'wine64');

      if (!await File(winePath).exists()) {
        throw Exception('Wine64 binary not found at: $winePath');
      }

      if (!await File(exePath).exists()) {
        throw Exception('Executable not found at: $exePath');
      }

      onLog('Using Wine at: $winePath');
      onLog('Launching: $exePath');

      final env = {
        'WINEPREFIX': prefix.path,
        'WINEARCH': 'win64',
        'DXVK_ASYNC': '1',
        'WINEESYNC': '1',
        'WINEFSYNC': '1',
        'WINE_LARGE_ADDRESS_AWARE': '1',
        'STAGING_SHARED_MEMORY': '1',
        'DXVK_STATE_CACHE': '1',
        ...?environment,
      };

      final workingDir = path.dirname(exePath);

      final process = await Process.start(
        winePath,
        [exePath],
        environment: env,
        workingDirectory: workingDir,
        mode: ProcessStartMode.inheritStdio,
      );

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw Exception('Process exited with code $exitCode. This might indicate missing dependencies.');
      }
    } catch (e) {
      onLog('Error launching game: $e');
      rethrow;
    }
  }

  Future<bool> _isDXVKInstalled(WinePrefix prefix) async {
    final dxvkPath = path.join(prefix.path, 'drive_c', 'windows', 'system32', 'd3d11.dll');
    return await File(dxvkPath).exists();
  }

  Future<bool> _hasCommonDependencies(WinePrefix prefix) async {
    final system32 = path.join(prefix.path, 'drive_c', 'windows', 'system32');
    final files = [
      'msvcr120.dll',
      'msvcp120.dll',
      'd3dx9_43.dll',
      'xactengine3_7.dll',
    ];

    for (final file in files) {
      if (!await File(path.join(system32, file)).exists()) {
        return false;
      }
    }
    return true;
  }

  // Prefix management methods
  Future<List<WinePrefix>> loadPrefixes() async {
    final prefixes = <WinePrefix>[];
    final baseDirectory = Directory(await baseDir);
    
    if (!await baseDirectory.exists()) {
      return prefixes;
    }

    try {
      await for (final versionDir in baseDirectory.list()) {
        if (versionDir is! Directory) continue;
        final version = path.basename(versionDir.path);
        
        // Skip non-Proton directories
        if (!version.startsWith('GE-Proton')) continue;

        await for (final prefixDir in versionDir.list()) {
          if (prefixDir is! Directory) continue;
          final prefixName = path.basename(prefixDir.path);
          final pfxPath = path.join(prefixDir.path, 'pfx');
          
          if (!await Directory(pfxPath).exists()) continue;

          try {
            final prefix = WinePrefix(
              path: pfxPath,
              version: version,
              name: prefixName,
              created: (await Directory(pfxPath).stat()).changed,
              is64Bit: true,
            );
            prefixes.add(prefix);
          } catch (e) {
            _logger.warning('Error loading prefix at $pfxPath: $e');
          }
        }
      }
    } catch (e) {
      _logger.severe('Error loading prefixes: $e');
    }

    return prefixes;
  }

  Future<WinePrefix?> getPrefixByPath(String prefixPath) async {
    try {
      final dir = Directory(prefixPath);
      if (!await dir.exists()) return null;

      // Parse the path to get version and name
      final parts = path.split(prefixPath);
      final versionIndex = parts.indexWhere((p) => p.startsWith('GE-Proton'));
      if (versionIndex == -1) return null;

      final version = parts[versionIndex];
      final prefixName = parts[versionIndex + 1];

      // Create the prefix object
      return WinePrefix(
        path: prefixPath,
        version: version,
        name: prefixName,
        created: (await dir.stat()).changed,
        is64Bit: true,
      );
    } catch (e) {
      _logger.warning('Error getting prefix by path: $e');
      return null;
    }
  }

  Future<WinePrefix?> _getOrCreatePrefix(String prefixPath) async {
    try {
      // Try to get existing prefix
      final prefix = await getPrefixByPath(prefixPath);
      if (prefix != null) return prefix;

      // If not found, parse path to create new prefix
      final parts = path.split(prefixPath);
      final versionIndex = parts.indexWhere((p) => p.startsWith('GE-Proton'));
      if (versionIndex == -1) throw Exception('Invalid prefix path');

      final version = parts[versionIndex];
      final prefixName = parts[versionIndex + 1];

      // Create new prefix
      return WinePrefix(
        path: prefixPath,
        version: version,
        name: prefixName,
        created: DateTime.now(),
        is64Bit: true,
      );
    } catch (e) {
      _logger.severe('Error getting/creating prefix: $e');
      return null;
    }
  }

  Future<List<WineBuild>> fetchAvailableBuilds() async {
    final builds = <WineBuild>[];
    
    for (final category in availableVersions.entries) {
      for (final version in category.value.entries) {
        builds.add(WineBuild(
          name: version.value,
          url: _getDownloadUrl(version.key),
          type: _getWineType(category.key),
          version: version.key,
        ));
      }
    }
    
    return builds;
  }

  WineType _getWineType(String category) {
    switch (category) {
      case 'GE-Proton':
        return WineType.proton;
      case 'Wine':
        return WineType.vanilla;
      default:
        return WineType.vanilla;
    }
  }

  void onLog(String message) {
    _logger.info(message);
    logCallback?.call(message);
  }

  Future<List<GamePrefixAssociation>> loadGameAssociations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('game_associations');
    if (jsonString == null) return [];
    
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => GamePrefixAssociation.fromJson(json)).toList();
  }

  Future<void> saveGameAssociation(String gamePath, WinePrefix prefix) async {
    final prefs = await SharedPreferences.getInstance();
    final associations = await loadGameAssociations();
    
    associations.add(GamePrefixAssociation(
      path: gamePath,
      prefixPath: prefix.path,
      prefixVersion: prefix.version,
      prefixName: prefix.name,
    ));
    
    await prefs.setString('game_associations', jsonEncode(associations.map((a) => a.toJson()).toList()));
  }

  Future<WinePrefix?> getAssociatedPrefix(String gamePath) async {
    final associations = await loadGameAssociations();
    final association = associations.firstWhere(
      (a) => a.path == gamePath,
      orElse: () => throw Exception('No prefix associated with game'),
    );
    
    if (association.prefixPath == null) return null;
    return getPrefixByPath(association.prefixPath);
  }

  Future<void> removeGameAssociation(String path) async {
    final associations = await loadGameAssociations();
    associations.removeWhere((a) => a.path == path);
    
    final prefs = await SharedPreferences.getInstance();
    final jsonList = associations.map((a) => a.toJson()).toList();
    await prefs.setString('game_associations', jsonEncode(jsonList));
  }

  Future<void> cleanupAllSquashfsMounts(WinePrefix prefix) async {
    try {
      final mountPoint = path.join(prefix.path, 'drive_c', 'squashfs_games');
      if (await Directory(mountPoint).exists()) {
        await Process.run('fusermount', ['-uz', mountPoint]);
        await Directory(mountPoint).delete(recursive: true);
      }
    } catch (e) {
      _logger.severe('Error cleaning up squashfs mounts: $e');
      rethrow;
    }
  }

  Future<List<String>> mountSquashfsGame(WinePrefix prefix, String squashPath) async {
    try {
      final mountPoint = path.join(prefix.path, 'drive_c', 'squashfs_games');
      await Directory(mountPoint).create(recursive: true);

      final result = await Process.run('squashfuse', [
        squashPath,
        mountPoint,
      ]);

      if (result.exitCode != 0) {
        throw Exception('Failed to mount squashfs: ${result.stderr}');
      }

      // Find all .exe files in the mounted directory
      final exeFiles = <String>[];
      await for (final entity in Directory(mountPoint).list(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
          exeFiles.add(entity.path);
        }
      }

      return exeFiles;
    } catch (e) {
      _logger.severe('Error mounting squashfs game: $e');
      rethrow;
    }
  }

  Future<WinePrefix?> loadPrefixByPath(String prefixPath) async {
    try {
      final dir = Directory(prefixPath);
      if (!await dir.exists()) return null;

      final parts = path.split(prefixPath);
      final versionIndex = parts.indexWhere((p) => p.startsWith('GE-Proton'));
      if (versionIndex == -1) return null;

      final version = parts[versionIndex];
      final prefixName = parts[versionIndex + 1];

      final stat = await dir.stat();
      return WinePrefix(
        path: prefixPath,
        version: version,
        name: prefixName,
        created: stat.modified,
        is64Bit: true,
      );
    } catch (e) {
      _logger.warning('Error loading prefix by path: $e');
      return null;
    }
  }

  // Add method to install dependencies
  Future<void> installDependencies(WinePrefix prefix, List<String> dependencies) async {
    for (final dep in dependencies) {
      if (dep == 'vkd3d-proton') {
        await _installVkd3dProton(prefix);
      } else {
        // Regular winetricks installation
        await _runWinetricks(prefix, [dep]);
      }
    }
  }

  Future<void> _installVkd3dProton(WinePrefix prefix) async {
    final tempDir = await Directory.systemTemp.createTemp('vkd3d-proton');
    try {
      // Download latest VKD3D-Proton
      final version = '2.11';
      final url = 'https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v$version/vkd3d-proton-$version.tar.zst';
      
      _logger.info('Downloading VKD3D-Proton $version...');
      final response = await http.get(Uri.parse(url));
      final archivePath = path.join(tempDir.path, 'vkd3d-proton.tar.zst');
      await File(archivePath).writeAsBytes(response.bodyBytes);

      // First decompress zstd
      _logger.info('Decompressing zstd archive...');
      final tarPath = path.join(tempDir.path, 'vkd3d-proton.tar');
      final decompressResult = await Process.run('zstd', ['-d', archivePath, '-o', tarPath]);
      
      if (decompressResult.exitCode != 0) {
        throw Exception('Failed to decompress zstd: ${decompressResult.stderr}');
      }

      // Then extract tar
      _logger.info('Extracting tar archive...');
      final extractResult = await Process.run('tar', ['xf', tarPath], workingDirectory: tempDir.path);
      
      if (extractResult.exitCode != 0) {
        throw Exception('Failed to extract tar: ${extractResult.stderr}');
      }

      // List contents to debug
      final contents = await Process.run('ls', ['-la'], workingDirectory: tempDir.path);
      _logger.info('Directory contents: ${contents.stdout}');

      // Find the setup script
      final setupScript = await _findFile(tempDir, 'setup_vkd3d_proton.sh');
      if (setupScript == null) {
        throw Exception('Could not find setup_vkd3d_proton.sh in extracted files');
      }

      _logger.info('Found setup script at: $setupScript');
      await Process.run('chmod', ['+x', setupScript]);
      
      // Set up environment for VKD3D installation
      final env = {
        'WINEPREFIX': prefix.path,
        'WINEARCH': 'win64',
        'PATH': Platform.environment['PATH']!, // Include system PATH
        'VKD3D_CONFIG': 'dxr',
        'VKD3D_FEATURE_LEVEL': '12_1',
        'VKD3D_SHADER_CACHE': '1',
      };

      // Add WINE path based on prefix type
      if (prefix.isProton) {
        env['WINE'] = prefix.protonPath;
      } else {
        env['WINE'] = path.join(path.dirname(prefix.path), 'bin', 'wine64');
      }

      // Run setup script with install argument
      _logger.info('Running setup script...');
      final result = await Process.run(setupScript, ['install'], 
        environment: env,
        workingDirectory: path.dirname(setupScript),
      );

      _logger.info('Setup script output: ${result.stdout}');
      if (result.stderr.isNotEmpty) {
        _logger.warning('Setup script errors: ${result.stderr}');
      }

      if (result.exitCode != 0) {
        throw Exception('Failed to install VKD3D-Proton: ${result.stderr}');
      }

      // Enable DX12 in the registry
      _logger.info('Configuring registry for DX12...');
      final regFile = File(path.join(tempDir.path, 'dx12.reg'));
      await regFile.writeAsString('''
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]
"d3d12"="native"
"d3d12core"="native"
"vkd3d-proton"="native"

[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Setup\\DX12]
"Available"=dword:00000001
"FeatureLevel"=dword:0000c100
''');

      // Import registry file
      if (prefix.isProton) {
        await Process.run('python3', [
          prefix.protonPath,
          'run',
          'regedit',
          path.join(tempDir.path, 'dx12.reg'),
        ], environment: {
          'WINEPREFIX': prefix.path,
          'STEAM_COMPAT_CLIENT_INSTALL_PATH': prefix.protonDir,
          'STEAM_COMPAT_DATA_PATH': prefix.path,
        });
      } else {
        // For regular Wine, use the wine64 binary directly
        final wine64Path = path.join(path.dirname(prefix.path), 'bin', 'wine64');
        await Process.run(wine64Path, [
          'regedit',
          path.join(tempDir.path, 'dx12.reg'),
        ], environment: {
          'WINEPREFIX': prefix.path,
        });
      }

      _logger.info('VKD3D-Proton installation complete');
    } catch (e, stack) {
      _logger.severe('Error installing VKD3D-Proton: $e\n$stack');
      rethrow;
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  Future<String?> _findFile(Directory dir, String filename) async {
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && path.basename(entity.path) == filename) {
          return entity.path;
        }
      }
    } catch (e) {
      _logger.warning('Error searching for file: $e');
    }
    return null;
  }

  Future<void> _runWinetricks(WinePrefix prefix, List<String> verbs) async {
    final winetricks = await _findWinetricks();
    
    for (final verb in verbs) {
      onLog('Installing $verb...');
      
      if (prefix.version.startsWith('GE-Proton')) {
        // For Proton prefixes, we need to use Proton's wine command
        final versionDir = path.dirname(prefix.path);
        final geProtonDir = path.join(versionDir, prefix.version);
        final protonPath = path.join(geProtonDir, 'proton');

        final process = await Process.start(
          'python3',
          [protonPath, 'run', winetricks, '--unattended', verb],
          environment: {
            'STEAM_COMPAT_CLIENT_INSTALL_PATH': geProtonDir,
            'STEAM_COMPAT_DATA_PATH': prefix.path,
            'WINEPREFIX': prefix.path,
            'WINEARCH': 'win64',
            'WINETRICKS_LATEST_VERSION_CHECK': 'disabled',
            'PROTON_NO_ESYNC': '1',  // Disable esync for installation
            'PROTON_NO_FSYNC': '1',  // Disable fsync for installation
          },
          mode: ProcessStartMode.inheritStdio,
        );

        final exitCode = await process.exitCode;
        if (exitCode != 0) {
          throw Exception('Winetricks failed with exit code $exitCode');
        }
      } else {
        // Regular Wine prefix installation
        final process = await Process.start(
          'bash',
          [winetricks, '--unattended', verb],
          environment: {
            'WINEPREFIX': prefix.path,
            'WINEARCH': 'win64',
            'WINETRICKS_LATEST_VERSION_CHECK': 'disabled',
          },
          mode: ProcessStartMode.inheritStdio,
        );

        final exitCode = await process.exitCode;
        if (exitCode != 0) {
          throw Exception('Winetricks failed with exit code $exitCode');
        }
      }

      // Add a small delay to ensure installation completes
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<String> _findWinetricks() async {
    // First check if winetricks is in PATH
    try {
      final result = await Process.run('which', ['winetricks']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (_) {}

    // If not found, download it
    final winetricksPath = path.join(await baseDir, 'winetricks');
    if (!await File(winetricksPath).exists()) {
      onLog('Downloading winetricks...');
      final response = await http.get(
        Uri.parse('https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks'),
      );
      await File(winetricksPath).writeAsBytes(response.bodyBytes);
      await Process.run('chmod', ['+x', winetricksPath]);
    }
    return winetricksPath;
  }

  Future<void> _installSpecificDependency(WinePrefix prefix, String dep) async {
    final url = dependencyUrls[dep]!;
    final fileName = path.basename(url);
    final downloadPath = path.join(await baseDir, 'downloads', fileName);

    // Download the dependency
    onLog('Downloading $fileName...');
    final response = await HttpClient().getUrl(Uri.parse(url));
    final httpResponse = await response.close();
    await httpResponse.pipe(File(downloadPath).openWrite());

    if (dep.startsWith('vcredist')) {
      // Install Visual C++ Redistributable
      await _launchWithWine(downloadPath, prefix);
    } else if (dep == 'directx_runtime') {
      // Extract and install DirectX
      await _extractAndInstallDirectX(downloadPath, prefix);
    } else if (dep == 'dxvk') {
      // Install DXVK
      await _installDXVK(downloadPath, prefix);
    } else if (dep == 'vkd3d') {
      // Install VKD3D
      await _installVKD3D(downloadPath, prefix);
    }

    // Cleanup
    await File(downloadPath).delete();
  }

  Future<void> _extractAndInstallDirectX(String downloadPath, WinePrefix prefix) async {
    // Create temp directory for extraction
    final extractDir = path.join(await baseDir, 'tmp', 'directx');
    await Directory(extractDir).create(recursive: true);

    // Extract DirectX
    await Process.run('7z', ['x', downloadPath, '-o$extractDir']);

    // Run DXSETUP.exe
    await _launchWithWine(
      path.join(extractDir, 'DXSETUP.exe'),
      prefix,
    );

    // Cleanup
    await Directory(extractDir).delete(recursive: true);
  }

  Future<void> _installDXVK(String downloadPath, WinePrefix prefix) async {
    // Extract DXVK
    final extractDir = path.join(await baseDir, 'tmp', 'dxvk');
    await Directory(extractDir).create(recursive: true);
    await Process.run('tar', ['xzf', downloadPath, '-C', extractDir]);

    // Run setup script
    final setupScript = path.join(extractDir, 'dxvk-2.3.1', 'setup_dxvk.sh');
    await Process.run(
      'bash',
      [setupScript, 'install'],
      environment: {'WINEPREFIX': prefix.path},
    );

    // Cleanup
    await Directory(extractDir).delete(recursive: true);
  }

  Future<void> _installVKD3D(String downloadPath, WinePrefix prefix) async {
    // Extract VKD3D
    final extractDir = path.join(await baseDir, 'tmp', 'vkd3d');
    await Directory(extractDir).create(recursive: true);
    await Process.run('tar', ['xf', downloadPath, '-C', extractDir]);

    // Run setup script
    final setupScript = path.join(extractDir, 'setup_vkd3d_proton.sh');
    await Process.run(
      'bash',
      [setupScript, 'install'],
      environment: {'WINEPREFIX': prefix.path},
    );

    // Cleanup
    await Directory(extractDir).delete(recursive: true);
  }

  Future<void> launchWinecfg(WinePrefix prefix) async {
    if (prefix.version.startsWith('GE-Proton')) {
      final versionDir = path.dirname(prefix.path);
      final geProtonDir = path.join(versionDir, prefix.version);
      final protonPath = path.join(geProtonDir, 'proton');

      final process = await Process.start(
        'python3',
        [protonPath, 'run', 'winecfg'],
        environment: {
          'STEAM_COMPAT_CLIENT_INSTALL_PATH': geProtonDir,
          'STEAM_COMPAT_DATA_PATH': prefix.path,
          'WINEPREFIX': prefix.path,
          'WINEARCH': 'win64',
        },
        mode: ProcessStartMode.inheritStdio,
      );

      await process.exitCode;
    } else {
      // For Kron4ek's builds, wine64 is in the prefix parent directory
      final prefixParent = path.dirname(prefix.path);
      final winePath = path.join(prefixParent, 'bin', 'wine64');

      if (!await File(winePath).exists()) {
        throw Exception('Wine64 binary not found at: $winePath');
      }

      final process = await Process.start(
        winePath,
        ['winecfg'],
        environment: {
          'WINEPREFIX': prefix.path,
          'WINEARCH': 'win64',
        },
        mode: ProcessStartMode.inheritStdio,
      );

      await process.exitCode;
    }
  }

  /// Installs essential dependencies for a new prefix
  Future<void> installEssentialDependencies(WinePrefix prefix) async {
    // Skip for Proton prefixes as they already include all dependencies
    if (prefix.isProton) {
      _logger.info('Skipping dependency installation for Proton prefix: ${prefix.path}');
      return;
    }

    _logger.info('Installing essential dependencies for prefix: ${prefix.path}');

    final dependencies = [
      // Visual C++ Runtimes (newest to oldest)
      'vcrun2022',
      'vcrun2019',
      'vcrun2017',
      'vcrun2015',
      
      // DirectX Components
      'dxvk',       // DX9/10/11 to Vulkan
      'vkd3d-proton', // DX12 to Vulkan
      'd3dx9',     // DirectX 9
      'd3dx11',    // DirectX 11
      
      // Additional essentials
      'xact',      // Audio
      'faudio',    // Audio
    ];

    try {
      for (final dep in dependencies) {
        _logger.info('Installing $dep...');
        try {
          if (dep == 'vkd3d-proton') {
            await _installVkd3dProton(prefix);
          } else {
            await _runWinetricks(prefix, [dep]);
          }
          _logger.info('Successfully installed $dep');
        } catch (e) {
          _logger.warning('Failed to install $dep: $e');
          // Continue with other dependencies even if one fails
        }
        // Add a small delay between installations
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (e) {
      _logger.severe('Error installing essential dependencies: $e');
      rethrow;
    }
  }
} 