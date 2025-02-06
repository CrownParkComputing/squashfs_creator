import 'dart:convert';
import 'dart:io';
import '../models/squash_file_settings.dart';
import '../services/wine_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';

class SquashManager {
  final WineService _wineService = WineService();
  static const String _settingsKey = 'squash_settings';
  final Map<String, Process> _mountProcesses = {};
  final _logger = Logger('SquashManager');

  Future<String> mountSquashFS(String squashPath) async {
    try {
      // Verify file exists and is readable
      final file = File(squashPath);
      if (!await file.exists()) {
        throw Exception('SquashFS file not found: $squashPath');
      }

      // Create mount point in home directory
      final homeDir = Platform.environment['HOME'];
      if (homeDir == null) {
        throw Exception('Could not determine home directory');
      }

      final mountPoint = '$homeDir/.local/share/squashfs_${DateTime.now().millisecondsSinceEpoch}';
      _logger.info('Creating mount point at: $mountPoint');

      // Create mount directory
      final mountDir = Directory(mountPoint);
      await mountDir.create(recursive: true);

      // Start squashfuse process and keep it running
      _logger.info('Starting squashfuse for: $squashPath');
      final process = await Process.start('squashfuse', [
        squashPath,
        mountPoint
      ]);

      // Store the process for later cleanup
      _mountProcesses[mountPoint] = process;

      // Wait a moment for the mount to complete
      await Future.delayed(const Duration(seconds: 1));

      // Verify mount worked
      if (!await Directory(mountPoint).exists()) {
        throw Exception('Mount point does not exist after mounting');
      }

      final contents = await Directory(mountPoint).list().toList();
      if (contents.isEmpty) {
        _logger.warning('Mount point is empty after mounting');
        await unmountSquashFS(mountPoint);
        throw Exception('Mount verification failed - directory is empty');
      }

      _logger.info('Mount successful at: $mountPoint');
      return mountPoint;

    } catch (e) {
      _logger.severe('Error in mountSquashFS: $e');
      rethrow;
    }
  }

  Future<void> unmountSquashFS(String mountPoint) async {
    try {
      _logger.info('Unmounting $mountPoint');
      
      // Kill the squashfuse process if it exists
      final process = _mountProcesses.remove(mountPoint);
      if (process != null) {
        process.kill();
        await process.exitCode; // Wait for process to exit
      }

      // Unmount using fusermount for cleanup
      await Process.run('fusermount', ['-u', mountPoint]);

      // Remove mount point
      await Directory(mountPoint).delete(recursive: true);
      _logger.info('Unmount complete');
    } catch (e) {
      _logger.severe('Error in unmountSquashFS: $e');
      rethrow;
    }
  }

  Future<void> launchSquashGame(SquashFileSettings settings) async {
    try {
      final prefix = await _wineService.loadPrefixByPath(settings.winePrefixPath!);
      if (prefix == null) {
        throw Exception('Wine prefix not found');
      }

      await _wineService.launchExe(
        settings.wineExePath!,
        prefix,
      );
    } catch (e) {
      _logger.severe('Error launching squashfs game: $e');
      rethrow;
    }
  }

  // Save settings for all squash files
  Future<void> saveSettings(List<SquashFileSettings> settings) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = settings.map((s) => s.toJson()).toList();
    await prefs.setString(_settingsKey, json.encode(jsonList));
  }

  // Load settings for all squash files
  Future<List<SquashFileSettings>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_settingsKey);
    if (jsonString == null) return [];

    final jsonList = json.decode(jsonString) as List;
    return jsonList.map((json) => SquashFileSettings.fromJson(json)).toList();
  }

  // Save settings for a single squash file
  Future<void> saveSettingsForFile(SquashFileSettings settings) async {
    final allSettings = await loadSettings();
    final index = allSettings.indexWhere((s) => s.path == settings.path);
    if (index >= 0) {
      allSettings[index] = settings;
    } else {
      allSettings.add(settings);
    }
    await saveSettings(allSettings);
  }

  // Get settings for a single squash file
  Future<SquashFileSettings?> getSettingsForFile(String path) async {
    final allSettings = await loadSettings();
    return allSettings.firstWhere(
      (s) => s.path == path,
      orElse: () => SquashFileSettings(
        path: path,
        created: DateTime.now(),
      ),
    );
  }

  Future<void> unsquashFile(String sourcePath, String destinationPath) async {
    try {
      final result = await Process.run('unsquashfs', [
        '-d', destinationPath,
        sourcePath,
      ]);

      if (result.exitCode != 0) {
        throw Exception('Failed to extract squashfs: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Error extracting squashfs: $e');
    }
  }

  // Test mount method
  Future<bool> testMount(String squashPath) async {
    String? mountPoint;
    try {
      _logger.info('=== Testing mount of: $squashPath ===');
      mountPoint = await mountSquashFS(squashPath);
      
      // List contents
      final lsResult = await Process.run('ls', ['-la', mountPoint]);
      _logger.info('Mount contents:\n${lsResult.stdout}');
      
      return lsResult.exitCode == 0;
    } catch (e) {
      _logger.severe('Mount test failed: $e');
      return false;
    } finally {
      if (mountPoint != null) {
        await unmountSquashFS(mountPoint);
      }
      _logger.info('=== Mount test complete ===');
    }
  }

  void dispose() {
    // Clean up any remaining mount processes
    for (final process in _mountProcesses.values) {
      process.kill();
    }
    _mountProcesses.clear();
  }
} 