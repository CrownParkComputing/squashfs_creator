import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import '../services/wine_service.dart';
import '../services/squash_manager.dart';
import '../models/game_config.dart';
import 'dart:io';

class GamePrefixAssignmentDialog extends StatefulWidget {
  final String squashPath;
  final GameConfig? existingConfig;

  const GamePrefixAssignmentDialog({
    super.key,
    required this.squashPath,
    this.existingConfig,
  });

  @override
  State<GamePrefixAssignmentDialog> createState() => _GamePrefixAssignmentDialogState();
}

class _GamePrefixAssignmentDialogState extends State<GamePrefixAssignmentDialog> {
  final WineService _wineService = WineService();
  final SquashManager _squashManager = SquashManager();
  String? _mountPoint;
  String? _selectedExePath;
  WinePrefix? _selectedPrefix;
  bool _isLoading = false;
  String _status = '';
  List<WinePrefix> _prefixes = [];
  Map<String, TextEditingController> _envControllers = {};

  @override
  void initState() {
    super.initState();
    _loadPrefixes();
    _initializeFromExistingConfig();
  }

  void _initializeFromExistingConfig() {
    if (widget.existingConfig != null) {
      setState(() {
        _selectedExePath = widget.existingConfig!.exePath;
        // We'll set the prefix when loaded
        
        // Initialize environment variable controllers
        for (var entry in widget.existingConfig!.environment.entries) {
          _envControllers[entry.key] = TextEditingController(text: entry.value);
        }
      });
    }
  }

  @override
  void dispose() {
    _unmountIfNeeded();
    for (var controller in _envControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPrefixes() async {
    setState(() => _isLoading = true);
    try {
      _prefixes = await _wineService.loadPrefixes();
    } catch (e) {
      print('Error loading prefixes: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unmountIfNeeded() async {
    if (_mountPoint != null) {
      try {
        await _squashManager.unmountSquashFS(_mountPoint!);
      } catch (e) {
        print('Error unmounting: $e');
      }
      _mountPoint = null;
    }
  }

  Future<void> _mountAndFindExes() async {
    setState(() {
      _isLoading = true;
      _status = 'Mounting SquashFS...';
    });

    try {
      _mountPoint = await _squashManager.mountSquashFS(widget.squashPath);
      print('Mounted at: $_mountPoint');

      // Find all .exe files
      final exeFiles = <String>[];
      await for (final entity in Directory(_mountPoint!).list(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
          exeFiles.add(entity.path);
        }
      }

      if (exeFiles.isEmpty) {
        throw Exception('No executable files found in the SquashFS');
      }

      setState(() {
        _status = 'Found ${exeFiles.length} executables';
        _selectedExePath = exeFiles.first; // Default to first exe
      });

    } catch (e) {
      setState(() => _status = 'Error: $e');
      await _unmountIfNeeded();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildEnvironmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Environment Variables:'),
        const SizedBox(height: 8),
        ..._envControllers.entries.map((entry) => _buildEnvRow(entry.key)),
        ElevatedButton(
          onPressed: _addEnvironmentVariable,
          child: const Text('Add Environment Variable'),
        ),
      ],
    );
  }

  Widget _buildEnvRow(String key) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(text: key),
            decoration: const InputDecoration(
              labelText: 'Key',
            ),
            onChanged: (newKey) {
              if (newKey != key) {
                final value = _envControllers[key]!.text;
                _envControllers[newKey] = TextEditingController(text: value);
                _envControllers.remove(key);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _envControllers[key],
            decoration: const InputDecoration(
              labelText: 'Value',
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () {
            setState(() {
              _envControllers.remove(key);
            });
          },
        ),
      ],
    );
  }

  void _addEnvironmentVariable() {
    setState(() {
      final key = 'VAR_${_envControllers.length + 1}';
      _envControllers[key] = TextEditingController();
    });
  }

  Map<String, String> _getEnvironmentVariables() {
    final env = <String, String>{};
    for (var entry in _envControllers.entries) {
      if (entry.key.isNotEmpty && entry.value.text.isNotEmpty) {
        env[entry.key] = entry.value.text;
      }
    }
    return env;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure Game'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_mountPoint == null) ...[
              ElevatedButton(
                onPressed: _isLoading ? null : _mountAndFindExes,
                child: const Text('Mount and Find Executables'),
              ),
            ] else ...[
              const Text('Select Executable:'),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: _selectedExePath,
                isExpanded: true,
                items: Directory(_mountPoint!)
                    .listSync(recursive: true)
                    .where((e) => e is File && e.path.toLowerCase().endsWith('.exe'))
                    .map((e) => DropdownMenuItem(
                          value: e.path,
                          child: Text(e.path.split('/').last),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedExePath = value);
                },
              ),
              const SizedBox(height: 16),
              const Text('Select Wine Prefix:'),
              const SizedBox(height: 8),
              DropdownButton<WinePrefix>(
                value: _selectedPrefix,
                isExpanded: true,
                items: _prefixes
                    .map((prefix) => DropdownMenuItem(
                          value: prefix,
                          child: Text(prefix.version),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedPrefix = value);
                },
              ),
              const SizedBox(height: 16),
              _buildEnvironmentSection(),
            ],
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(_status),
            ],
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _unmountIfNeeded();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        if (_mountPoint != null)
          ElevatedButton(
            onPressed: _selectedExePath != null && _selectedPrefix != null
                ? () {
                    Navigator.of(context).pop({
                      'exePath': _selectedExePath,
                      'prefix': _selectedPrefix,
                      'environment': _getEnvironmentVariables(),
                    });
                  }
                : null,
            child: const Text('Save'),
          ),
      ],
    );
  }
} 