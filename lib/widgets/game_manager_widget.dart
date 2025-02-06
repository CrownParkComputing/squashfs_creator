import '../services/wine_service.dart';
import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import '../models/game_prefix_association.dart';
import '../services/process_manager.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import './game_prefix_assignment_dialog.dart';
import 'dart:io';
import '../models/game_config.dart';
import '../services/game_config_service.dart';
import '../services/squash_manager.dart';

class GameManagerWidget extends StatefulWidget {
  final List<String> squashPaths;
  
  const GameManagerWidget({
    super.key,
    required this.squashPaths,
  });

  @override
  State<GameManagerWidget> createState() => _GameManagerWidgetState();
}

class _GameManagerWidgetState extends State<GameManagerWidget> {
  final GameConfigService _configService = GameConfigService();
  final WineService _wineService = WineService();
  final SquashManager _squashManager = SquashManager();
  List<GameConfig> _configs = [];
  String? _mountPoint;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
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

  Future<void> _loadConfigs() async {
    try {
      _configs = await _configService.loadConfigs();
      setState(() {});
    } catch (e) {
      print('Error loading configs: $e');
    }
  }

  Future<void> _launchGame(GameConfig config) async {
    try {
      // First mount the squashfs
      _mountPoint = await _squashManager.mountSquashFS(config.squashPath);
      
      // Get the relative path from the original mount point
      final originalMountPoint = path.dirname(config.exePath!);
      final exeName = path.basename(config.exePath!);
      
      // Construct the new path using the current mount point
      final mountedExePath = path.join(_mountPoint!, exeName);

      print('Original exe path: ${config.exePath}');
      print('New mounted exe path: $mountedExePath');

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
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: widget.squashPaths.length,
      padding: const EdgeInsets.all(8.0),
      itemBuilder: (context, index) {
        final squashPath = widget.squashPaths[index];
        final config = _configs.firstWhere(
          (c) => c.squashPath == squashPath,
          orElse: () => GameConfig(squashPath: squashPath),
        );

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ListTile(
            leading: const Icon(Icons.folder),
            title: Text(path.basename(squashPath)),
            subtitle: Text(squashPath),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: config.isConfigured ? () => _launchGame(config) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () => _configureGame(squashPath),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _configureGame(String squashPath) async {
    final existingConfig = _configs.firstWhere(
      (c) => c.squashPath == squashPath,
      orElse: () => GameConfig(squashPath: squashPath),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => GamePrefixAssignmentDialog(
        squashPath: squashPath,
        existingConfig: existingConfig,
      ),
    );

    if (result != null) {
      final config = GameConfig(
        squashPath: squashPath,
        exePath: result['exePath'],
        prefixPath: result['prefix'].path,
        environment: Map<String, String>.from(result['environment']),
      );
      await _configService.saveConfig(config);
      await _loadConfigs();
    }
  }
} 