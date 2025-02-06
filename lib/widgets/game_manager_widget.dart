import '../services/wine_service.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/game_config.dart';
import '../services/game_config_service.dart';
import '../services/squash_manager.dart';
import 'package:logging/logging.dart';
import '../utils/process_manager.dart';
import '../models/wine_prefix.dart';
import '../widgets/prefix_selector_dialog.dart';
import 'dart:io';

class GameManagerWidget extends StatefulWidget {
  final List<String> gamePaths;
  final bool isSquashFS;  // Add this flag
  
  const GameManagerWidget({
    super.key,
    required this.gamePaths,
    this.isSquashFS = false,  // Default to regular games
  });

  @override
  State<GameManagerWidget> createState() => _GameManagerWidgetState();
}

class _GameManagerWidgetState extends State<GameManagerWidget> {
  final _logger = Logger('GameManagerWidget');
  final GameConfigService _configService = GameConfigService();
  final WineService _wineService = WineService();
  final SquashManager _squashManager = SquashManager();
  final Map<String, List<String>> _gameFiles = {};
  List<GameConfig> _configs = [];
  String? _mountPoint;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadGameFiles();
  }

  @override
  void dispose() {
    _unmountIfMounted();
    // Kill any processes started by this widget
    for (final files in _gameFiles.values) {
      for (final file in files) {
        if (ProcessManager.isProcessRunning(file)) {
          ProcessManager.killProcess(file);
        }
      }
    }
    super.dispose();
  }

  Future<void> _unmountIfMounted() async {
    if (_mountPoint != null) {
      await _squashManager.unmountSquashFS(_mountPoint!);
      _mountPoint = null;
    }
  }

  Future<void> _loadGameFiles() async {
    setState(() => _isLoading = true);
    try {
      _configs = await _configService.loadConfigs();
      
      for (final parentDir in widget.gamePaths) {
        final dir = Directory(parentDir);
        if (await dir.exists()) {
          final files = await dir
              .list()
              .where((entity) => 
                  widget.isSquashFS 
                    ? (entity is File && entity.path.toLowerCase().endsWith('.squashfs'))
                    : entity is Directory)
              .map((e) => e.path)
              .toList();
          _gameFiles[parentDir] = files;
        }
      }
    } catch (e) {
      _logger.severe('Error loading game files: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _launchGame(GameConfig config) async {
    try {
      String exePath;
      
      if (widget.isSquashFS) {
        _mountPoint = await _squashManager.mountSquashFS(config.squashPath);
        final exeName = path.basename(config.exePath!);
        exePath = path.join(_mountPoint!, exeName);
      } else {
        exePath = config.exePath!;
      }

      _logger.info('Launching exe: $exePath');

      final prefix = await _wineService.loadPrefixByPath(config.prefixPath!);
      if (prefix != null) {
        final process = await _wineService.launchExe(
          exePath,
          prefix,
          environment: config.environment,
        );
        
        // Register the process with ProcessManager
        ProcessManager.registerProcess(
          config.squashPath,
          process,
          prefixPath: config.prefixPath!,
          exePath: exePath,
        );
        
        // Monitor process exit to update UI
        process.exitCode.then((_) {
          if (mounted) {
            setState(() {});  // Refresh UI when process exits
          }
        });

        setState(() {});  // Refresh UI to show running state
      }
    } catch (e) {
      _logger.severe('Error launching game: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error launching game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: widget.gamePaths.length,
      padding: const EdgeInsets.all(8.0),
      itemBuilder: (context, parentIndex) {
        final parentDir = widget.gamePaths[parentIndex];
        final files = _gameFiles[parentDir] ?? [];

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
                child: Text('No games found in this folder'),
              )
            else
              ...files.map((gamePath) {
                final config = _configs.firstWhere(
                  (c) => c.squashPath == gamePath,
                  orElse: () => GameConfig(squashPath: gamePath),
                );
                return _buildGameCard(config);
              }),
            const Divider(),
          ],
        );
      },
    );
  }

  Widget _buildGameCard(GameConfig config) {
    final isRunning = ProcessManager.isProcessRunning(config.squashPath);
    
    return Card(
      child: ListTile(
        leading: Icon(
          config.isConfigured ? Icons.games : Icons.folder,
          color: isRunning ? Colors.green : Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          path.basename(config.squashPath),
          style: TextStyle(
            color: isRunning ? Colors.green : null,
            fontWeight: isRunning ? FontWeight.bold : null,
          ),
        ),
        subtitle: Text(
          config.isConfigured ? config.exePath! : config.squashPath,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (config.isConfigured) ...[
              if (isRunning)
                IconButton(
                  icon: const Icon(Icons.stop_circle, color: Colors.red),
                  onPressed: () => _stopGame(config.squashPath),
                  tooltip: 'Stop Game',
                ),
              IconButton(
                icon: Icon(
                  Icons.play_arrow,
                  color: isRunning ? Colors.green : null,
                ),
                onPressed: isRunning ? null : () => _launchGame(config),
                tooltip: isRunning ? 'Game Running' : 'Launch Game',
              ),
            ],
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => _configureGame(config.squashPath),
              tooltip: 'Configure Game',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _configureGame(String squashPath) async {
    final existingConfig = _configs.firstWhere(
      (c) => c.squashPath == squashPath,
      orElse: () => GameConfig(squashPath: squashPath),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PrefixSelectorDialog(
        gamePath: squashPath,
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
      await _loadGameFiles();
    }
  }

  Future<void> _stopGame(String gamePath) async {
    try {
      _logger.info('Stopping game: $gamePath');
      
      // Kill the main process and any child processes
      await ProcessManager.killProcess(gamePath);
      
      // Also try to kill any wine processes associated with this game
      if (Platform.isLinux) {
        try {
          await Process.run('pkill', ['-f', path.basename(gamePath)]);
          await Process.run('wineserver', ['-k']);  // Kill any remaining wine processes
        } catch (e) {
          _logger.warning('Error killing additional processes: $e');
        }
      }

      if (mounted) {
        setState(() {});  // Refresh UI
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Game stopped'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _logger.severe('Error stopping game: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
} 