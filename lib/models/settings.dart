import 'package:flutter/foundation.dart';
import '../services/wine_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wine_build.dart';

class Settings extends ChangeNotifier {
  final WineService _wineService = WineService();
  List<WineBuild> availableWineBuilds = [];
  WineBuild? selectedWineBuild;
  String prefixBaseDirectory;
  String defaultWineVersion;
  bool autoInstallDependencies;

  Settings({
    this.prefixBaseDirectory = '',
    this.defaultWineVersion = '',
    this.autoInstallDependencies = true,
  });

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    prefixBaseDirectory = prefs.getString('prefix_base_dir') ?? '';
    defaultWineVersion = prefs.getString('default_wine_version') ?? '';
    autoInstallDependencies = prefs.getBool('auto_install_dependencies') ?? true;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prefix_base_dir', prefixBaseDirectory);
    await prefs.setString('default_wine_version', defaultWineVersion);
    await prefs.setBool('auto_install_dependencies', autoInstallDependencies);
  }

  Future<void> fetchWinePrefixes() async {
    try {
      availableWineBuilds = await _wineService.fetchAvailableBuilds();
      notifyListeners();
    } catch (e) {
      print('Error fetching wine builds: $e');
    }
  }

  void updateSelectedWinePrefix(WineBuild build) {
    selectedWineBuild = build;
    notifyListeners();
  }
} 