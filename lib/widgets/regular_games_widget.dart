import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import '../models/game_config.dart';
import '../services/wine_service.dart';
import '../services/process_manager.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../widgets/executable_selector_dialog.dart';
import '../widgets/prefix_selector_dialog.dart';

class RegularGamesWidget extends StatefulWidget {
  final List<String> gameFolders;
  
  const RegularGamesWidget({
    super.key,
    required this.gameFolders,
  });

  @override
  State<RegularGamesWidget> createState() => _RegularGamesWidgetState();
}

class _RegularGamesWidgetState extends State<RegularGamesWidget> {
  final WineService _wineService = WineService();
  bool _isLoading = false;
  final Map<String, List<String>> _subDirectories = {};
  final Map<String, GameConfig> _gameConfigs = {};

  @override
  void initState() {
    super.initState();
    _loadSubDirectories();
  }

  Future<void> _loadSubDirectories() async {
    setState(() => _isLoading = true);
    try {
      for (final parentFolder in widget.gameFolders) {
        final dir = Directory(parentFolder);
        if (await dir.exists()) {
          final subdirs = await dir
              .list()
              .where((entity) => entity is Directory)
              .map((e) => e.path)
              .toList();
          _subDirectories[parentFolder] = subdirs;
          
          // Load configs for each subdir
          for (final subdir in subdirs) {
            final config = await _loadOrCreateConfig(subdir);
            _gameConfigs[subdir] = config;
          }
        }
      }
    } catch (e) {
      print('Error loading subdirectories: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<GameConfig> _loadOrCreateConfig(String folderPath) async {
    // TODO: Implement config loading from shared preferences
    return GameConfig(
      squashPath: folderPath,  // We'll use this field for the folder path
    );
  }

  Future<void> _configureGame(String folderPath) async {
    // Show executable selector
    final exePath = await showDialog<String>(
      context: context,
      builder: (context) => ExecutableSelectorDialog(
        directoryPath: folderPath,
      ),
    );

    if (exePath == null) return;

    // Show prefix selector
    final prefixes = await _wineService.loadPrefixes();
    if (!mounted) return;

    final prefix = await showDialog<WinePrefix>(
      context: context,
      builder: (context) => PrefixSelectorDialog(
        prefixes: prefixes,
      ),
    );

    if (prefix == null) return;

    // Save configuration
    final config = GameConfig(
      squashPath: folderPath,
      exePath: exePath,
      prefixPath: prefix.path,
    );

    setState(() {
      _gameConfigs[folderPath] = config;
    });
    // TODO: Save config to shared preferences
  }

  Future<void> _launchGame(GameConfig config) async {
    try {
      setState(() => _isLoading = true);

      final prefix = await _wineService.loadPrefixByPath(config.prefixPath!);
      if (prefix == null) throw Exception('Wine prefix not found');

      await _wineService.launchExe(
        config.exePath!,
        prefix,
        environment: config.environment,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error launching game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: widget.gameFolders.length,
      padding: const EdgeInsets.all(8.0),
      itemBuilder: (context, parentIndex) {
        final parentFolder = widget.gameFolders[parentIndex];
        final subdirs = _subDirectories[parentFolder] ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                path.basename(parentFolder),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (subdirs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No games found in this folder'),
              )
            else
              ...subdirs.map((subdir) {
                final config = _gameConfigs[subdir];
                final isConfigured = config?.isConfigured ?? false;

                return Card(
                  child: ListTile(
                    leading: Icon(
                      isConfigured ? Icons.games : Icons.folder,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(path.basename(subdir)),
                    subtitle: Text(
                      isConfigured ? config!.exePath! : subdir,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isConfigured)
                          IconButton(
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () => _launchGame(config!),
                            tooltip: 'Launch Game',
                          ),
                        IconButton(
                          icon: const Icon(Icons.settings),
                          onPressed: () => _configureGame(subdir),
                          tooltip: 'Configure Game',
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const Divider(),
          ],
        );
      },
    );
  }
} 