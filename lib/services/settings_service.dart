import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/app_settings.dart';

class SettingsService {
  static const String _settingsFile = 'settings.json';
  late final String _configDir;
  AppSettings? _cachedSettings;

  SettingsService() {
    _configDir = path.join(
      Platform.environment['HOME'] ?? Directory.current.path,
      '.config',
      'squashfs_creator',
    );
  }

  Future<void> init() async {
    final dir = Directory(_configDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<AppSettings> loadSettings() async {
    if (_cachedSettings != null) {
      return _cachedSettings!;
    }

    await init();
    try {
      final file = File(path.join(_configDir, _settingsFile));
      if (!await file.exists()) {
        // Create default settings
        final defaultSettings = AppSettings(
          prefixBaseDirectory: path.join(
            Platform.environment['HOME'] ?? Directory.current.path,
            '.wine_prefixes',
          ),
        );
        await saveSettings(defaultSettings);
        return defaultSettings;
      }
      
      final content = await file.readAsString();
      _cachedSettings = AppSettings.fromJson(json.decode(content));
      return _cachedSettings!;
    } catch (e) {
      print('Error loading settings: $e');
      // Return default settings on error
      return AppSettings(
        prefixBaseDirectory: path.join(
          Platform.environment['HOME'] ?? Directory.current.path,
          '.wine_prefixes',
        ),
      );
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await init();
    final file = File(path.join(_configDir, _settingsFile));
    await file.writeAsString(json.encode(settings.toJson()));
    _cachedSettings = settings;
  }
} 