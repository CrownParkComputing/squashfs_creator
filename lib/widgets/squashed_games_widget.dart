import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import '../models/game_config.dart';
import '../services/process_manager.dart';
import 'package:path/path.dart' as path;
import '../services/game_config_service.dart';
import '../services/squash_manager.dart';
import '../services/wine_service.dart';
import '../widgets/executable_selector_dialog.dart';
import '../widgets/prefix_selector_dialog.dart';
import 'dart:io';

class SquashedGamesWidget extends StatefulWidget {
  final List<String> squashPaths;
  
  const SquashedGamesWidget({
    super.key,
    required this.squashPaths,
  });

  @override
  State<SquashedGamesWidget> createState() => _SquashedGamesWidgetState();
}

class _SquashedGamesWidgetState extends State<SquashedGamesWidget> {
  final GameConfigService _configService = GameConfigService();
  final WineService _wineService = WineService();
  final SquashManager _squashManager = SquashManager();
  Map<String, List<String>> _squashFiles = {};
  List<GameConfig> _configs = [];
  String? _mountPoint;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSquashFiles();
  }

  @override
  void dispose() {
    _unmountIfMounted();
    super.dispose();
  }

  Future<void> _unmountIfMounted() async {
    if (_mountPoint != null) {
      await _squashManager.unmountSquashFS(_mountPoint!);
      _mountPoint = null;
    }
  }

  Future<void> _loadSquashFiles() async {
    setState(() => _isLoading = true);
    try {
      _configs = await _configService.loadConfigs();
      
      for (final parentDir in widget.squashPaths) {
        final dir = Directory(parentDir);
        if (await dir.exists()) {
          final files = await dir
              .list()
              .where((entity) => 
                  entity is File && 
                  entity.path.toLowerCase().endsWith('.squashfs'))
              .map((e) => e.path)
              .toList();
          _squashFiles[parentDir] = files;
        }
      }
    } catch (e) {
      print('Error loading squash files: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _launchGame(GameConfig config) async {
    try {
      setState(() => _isLoading = true);
      
      // First mount the squashfs
      _mountPoint = await _squashManager.mountSquashFS(config.squashPath);
      
      // Get the relative path from the original mount point
      final originalMountPoint = path.dirname(config.exePath!);
      final exeName = path.basename(config.exePath!);
      
      // Construct the new path using the current mount point
      final mountedExePath = path.join(_mountPoint!, exeName);

      final prefix = await _wineService.loadPrefixByPath(config.prefixPath!);
      if (prefix != null) {
        await _wineService.launchExe(
          mountedExePath,
          prefix,
          environment: config.environment,
        );
      }
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
      await _unmountIfMounted();
      setState(() => _isLoading = false);
    }
  }

  Future<void> _configureGame(String squashPath) async {
    try {
      setState(() => _isLoading = true);
      
      // Mount the squashfs
      _mountPoint = await _squashManager.mountSquashFS(squashPath);

      // Show executable selector
      final exePath = await showDialog<String>(
        context: context,
        builder: (context) => ExecutableSelectorDialog(
          directoryPath: _mountPoint!,
        ),
      );

      if (exePath == null) {
        await _unmountIfMounted();
        return;
      }

      // Show prefix selector
      final prefixes = await _wineService.loadPrefixes();
      if (!mounted) return;

      final prefix = await showDialog<WinePrefix>(
        context: context,
        builder: (context) => PrefixSelectorDialog(
          prefixes: prefixes,
        ),
      );

      if (prefix == null) {
        await _unmountIfMounted();
        return;
      }

      // Create and save config
      final config = GameConfig(
        squashPath: squashPath,
        exePath: exePath,
        prefixPath: prefix.path,
      );

      await _configService.saveConfig(config);
      await _loadSquashFiles();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error configuring game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await _unmountIfMounted();
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: widget.squashPaths.length,
      padding: const EdgeInsets.all(8.0),
      itemBuilder: (context, parentIndex) {
        final parentDir = widget.squashPaths[parentIndex];
        final files = _squashFiles[parentDir] ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                path.basename(parentDir),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (files.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No squashed games found in this folder'),
              )
            else
              ...files.map((squashPath) {
                final config = _configs.firstWhere(
                  (c) => c.squashPath == squashPath,
                  orElse: () => GameConfig(squashPath: squashPath),
                );

                return Card(
                  child: ListTile(
                    leading: Icon(
                      config.isConfigured ? Icons.games : Icons.folder_zip,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(path.basename(squashPath)),
                    subtitle: Text(
                      config.isConfigured ? config.exePath! : squashPath,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (config.isConfigured)
                          IconButton(
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () => _launchGame(config),
                            tooltip: 'Launch Game',
                          ),
                        IconButton(
                          icon: const Icon(Icons.settings),
                          onPressed: () => _configureGame(squashPath),
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