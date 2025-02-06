import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/settings_service.dart';
import '../models/app_settings.dart';
import '../models/wine_prefix.dart';
import '../services/wine_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../services/theme_manager.dart';
import '../models/game_folder.dart';
import 'dart:convert';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  AppSettings? _currentSettings;
  bool _isLoading = true;
  List<String> squashDirectories = [];
  final String _prefsKey = 'squash_directories';
  final WineService _wineService = WineService();
  static const String _gameFoldersKey = 'game_folders';
  List<GameFolder> _gameFolders = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadSquashDirectories();
    _loadGameFolders();
    // Fetch wine prefixes when screen loads
    Future.microtask(() => 
      context.read<Settings>().fetchWinePrefixes()
    );
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final settings = await _settings.loadSettings();
      setState(() {
        _currentSettings = settings;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSquashDirectories() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      squashDirectories = prefs.getStringList(_prefsKey) ?? [];
    });
  }

  Future<void> _saveSquashDirectories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, squashDirectories);
  }

  Future<void> _addSquashDirectory() async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Squash File Storage Directory',
    );
    
    if (selectedDirectory != null && !squashDirectories.contains(selectedDirectory)) {
      setState(() {
        squashDirectories.add(selectedDirectory);
      });
      await _saveSquashDirectories();
    }
  }

  Future<void> _removeSquashDirectory(int index) async {
    setState(() {
      squashDirectories.removeAt(index);
    });
    await _saveSquashDirectories();
  }

  Future<void> _selectPrefixDirectory() async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Wine Prefixes Directory',
    );
    
    if (selectedDirectory != null && _currentSettings != null) {
      final newSettings = _currentSettings!.copyWith(
        prefixBaseDirectory: selectedDirectory,
      );
      await _settings.saveSettings(newSettings);
      setState(() {
        _currentSettings = newSettings;
      });
    }
  }

  Future<void> _loadGameFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_gameFoldersKey) ?? [];
    setState(() {
      _gameFolders = jsonList
          .map((json) => GameFolder.fromJson(jsonDecode(json)))
          .toList();
    });
  }

  Future<void> _saveGameFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _gameFolders
        .map((folder) => jsonEncode(folder.toJson()))
        .toList();
    await prefs.setStringList(_gameFoldersKey, jsonList);
  }

  Future<void> _addGameFolder({required GameFolderType type}) async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select ${type == GameFolderType.squashed ? 'Squashed' : 'Regular'} Games Directory',
    );
    
    if (selectedDirectory != null && 
        !_gameFolders.any((f) => f.path == selectedDirectory)) {
      setState(() {
        _gameFolders.add(GameFolder(
          path: selectedDirectory,
          type: type,
        ));
      });
      await _saveGameFolders();
    }
  }

  Future<void> _removeGameFolder(int index) async {
    setState(() {
      _gameFolders.removeAt(index);
    });
    await _saveGameFolders();
  }

  Widget _buildThemeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Theme',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Consumer<ThemeManager>(
              builder: (context, themeManager, _) => Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: const Text('System'),
                    value: ThemeMode.system,
                    groupValue: themeManager.themeMode,
                    onChanged: (value) => 
                      themeManager.setThemeMode(value ?? ThemeMode.system),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Light'),
                    value: ThemeMode.light,
                    groupValue: themeManager.themeMode,
                    onChanged: (value) => 
                      themeManager.setThemeMode(value ?? ThemeMode.light),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Dark'),
                    value: ThemeMode.dark,
                    groupValue: themeManager.themeMode,
                    onChanged: (value) => 
                      themeManager.setThemeMode(value ?? ThemeMode.dark),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameFoldersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Game Folders',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _addGameFolder(type: GameFolderType.normal),
                  icon: const Icon(Icons.create_new_folder),
                  label: const Text('Add Regular Folder'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _addGameFolder(type: GameFolderType.squashed),
                  icon: const Icon(Icons.folder_zip),
                  label: const Text('Add Squashed Folder'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._gameFolders.asMap().entries.map((entry) {
              final index = entry.key;
              final folder = entry.value;
              return ListTile(
                leading: Icon(
                  folder.type == GameFolderType.squashed 
                      ? Icons.folder_zip 
                      : Icons.folder,
                ),
                title: Text(path.basename(folder.path)),
                subtitle: Text(folder.path),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _removeGameFolder(index),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildThemeSelector(),
          const SizedBox(height: 16),
          _buildGameFoldersCard(),
          // SquashFS Settings Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SquashFS Settings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Storage Directories',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      TextButton.icon(
                        onPressed: _addSquashDirectory,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (squashDirectories.isEmpty)
                    const Text('No storage directories added')
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: squashDirectories.length,
                      itemBuilder: (context, index) {
                        final dir = squashDirectories[index];
                        return ListTile(
                          title: Text(path.basename(dir)),
                          subtitle: Text(dir),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _removeSquashDirectory(index),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Wine Settings Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wine Settings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Wine Prefixes Directory:',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _currentSettings?.prefixBaseDirectory ?? '',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _selectPrefixDirectory,
                        icon: const Icon(Icons.folder),
                        label: const Text('Change'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Auto-manage prefixes'),
                    subtitle: const Text('Automatically organize wine prefixes by version'),
                    value: _currentSettings?.autoManagePrefixes ?? true,
                    onChanged: (value) async {
                      if (_currentSettings != null) {
                        final newSettings = _currentSettings!.copyWith(
                          autoManagePrefixes: value,
                        );
                        await _settings.saveSettings(newSettings);
                        setState(() {
                          _currentSettings = newSettings;
                        });
                      }
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Enable Wine logging'),
                    subtitle: const Text('Save Wine debug output to logs'),
                    value: _currentSettings?.enableLogging ?? true,
                    onChanged: (value) async {
                      if (_currentSettings != null) {
                        final newSettings = _currentSettings!.copyWith(
                          enableLogging: value,
                        );
                        await _settings.saveSettings(newSettings);
                        setState(() {
                          _currentSettings = newSettings;
                        });
                      }
                    },
                  ),
                  const Divider(),
                  Text(
                    'Current Prefixes:',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  _buildPrefixList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  FutureBuilder<List<WinePrefix>> _buildPrefixList() {
    return FutureBuilder<List<WinePrefix>>(
      future: _wineService.loadPrefixes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Text('No Wine prefixes found');
        }
        return Column(
          children: snapshot.data!.map((prefix) => ListTile(
            title: Text(path.basename(prefix.path)),
            subtitle: Text('${prefix.version} (${prefix.is64Bit ? "64-bit" : "32-bit"})'),
            trailing: Text(prefix.created.toLocal().toString().split('.')[0]),
          )).toList(),
        );
      },
    );
  }
} 