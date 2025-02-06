import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_config.dart';
import 'package:logging/logging.dart';

class GameConfigService {
  final _logger = Logger('GameConfigService');
  static const String _configKey = 'game_configs';

  Future<List<GameConfig>> loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_configKey);
    if (jsonString == null) return [];

    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => GameConfig.fromJson(json)).toList();
  }

  Future<GameConfig?> getConfigForGame(String squashPath) async {
    final configs = await loadConfigs();
    try {
      return configs.firstWhere((c) => c.squashPath == squashPath);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveConfig(GameConfig config) async {
    _logger.info('Saving config for: ${config.squashPath}');
    final prefs = await SharedPreferences.getInstance();
    final configs = await loadConfigs();
    
    final index = configs.indexWhere((c) => c.squashPath == config.squashPath);
    if (index >= 0) {
      configs[index] = config;
    } else {
      configs.add(config);
    }

    final jsonList = configs.map((c) => c.toJson()).toList();
    await prefs.setString(_configKey, jsonEncode(jsonList));
  }

  Future<void> removeConfig(String squashPath) async {
    _logger.info('Removing config for: $squashPath');
    final prefs = await SharedPreferences.getInstance();
    final configs = await loadConfigs();
    
    configs.removeWhere((c) => c.squashPath == squashPath);
    
    final jsonList = configs.map((c) => c.toJson()).toList();
    await prefs.setString(_configKey, jsonEncode(jsonList));
  }
} 