import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import '../models/game_config.dart';
import '../services/wine_service.dart';
import '../services/squash_manager.dart';
import 'package:path/path.dart' as path;
import 'package:logging/logging.dart';
import 'dart:io';
import 'package:intl/intl.dart';

class PrefixSelectorDialog extends StatefulWidget {
  final List<WinePrefix>? availablePrefixes;
  final WinePrefix? currentPrefix;
  final String? gamePath;
  final GameConfig? existingConfig;

  const PrefixSelectorDialog({
    super.key,
    this.availablePrefixes,
    this.currentPrefix,
    this.gamePath,
    this.existingConfig,
  });

  @override
  State<PrefixSelectorDialog> createState() => _PrefixSelectorDialogState();
}

class _PrefixSelectorDialogState extends State<PrefixSelectorDialog> {
  final _logger = Logger('PrefixSelectorDialog');
  final WineService _wineService = WineService();
  final SquashManager _squashManager = SquashManager();
  List<WinePrefix> _prefixes = [];
  late WinePrefix? selectedPrefix;
  bool _isLoading = false;
  String? _mountPoint;
  String? _selectedExePath;
  final Map<String, TextEditingController> _envControllers = {};

  @override
  void initState() {
    super.initState();
    _prefixes = widget.availablePrefixes ?? [];
    selectedPrefix = widget.currentPrefix;
    if (_prefixes.isEmpty) {
      _loadPrefixes();
    }
    _initializeFromConfig();
  }

  @override
  void dispose() {
    _unmountIfNeeded();
    for (var controller in _envControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _unmountIfNeeded() async {
    if (_mountPoint != null) {
      await _squashManager.unmountSquashFS(_mountPoint!);
      _mountPoint = null;
    }
  }

  void _initializeFromConfig() {
    if (widget.existingConfig != null) {
      _selectedExePath = widget.existingConfig!.exePath;
      if (widget.existingConfig!.prefixPath != null) {
        try {
          selectedPrefix = _prefixes.firstWhere(
            (p) => p.path == widget.existingConfig!.prefixPath,
          );
        } catch (_) {
          selectedPrefix = null;
        }
      }
      for (final entry in widget.existingConfig!.environment.entries) {
        _envControllers[entry.key] = TextEditingController(text: entry.value);
      }
        }
  }

  Future<void> _loadPrefixes() async {
    setState(() => _isLoading = true);
    try {
      _prefixes = await _wineService.loadPrefixes();
      setState(() {});
    } catch (e) {
      _logger.severe('Error loading prefixes: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectExecutable() async {
    setState(() => _isLoading = true);
    try {
      final dir = Directory(widget.gamePath!);
      final exeFiles = <String>[];
      
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
          exeFiles.add(entity.path);
        }
      }

      if (exeFiles.isEmpty) {
        throw Exception('No executable files found');
      }

      if (!mounted) return;
      final exePath = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Executable'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: exeFiles.length,
              itemBuilder: (context, index) {
                final exePath = exeFiles[index];
                return ListTile(
                  title: Text(path.basename(exePath)),
                  subtitle: Text(path.dirname(exePath)),
                  onTap: () => Navigator.of(context).pop(exePath),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (exePath != null) {
        setState(() => _selectedExePath = exePath);
      }
    } catch (e) {
      _logger.severe('Error selecting executable: $e');
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
            decoration: const InputDecoration(labelText: 'Key'),
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
            decoration: const InputDecoration(labelText: 'Value'),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => setState(() => _envControllers.remove(key)),
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
      title: Text(widget.gamePath != null ? 'Configure Game' : 'Select Wine Prefix'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.gamePath != null) ...[
              ElevatedButton(
                onPressed: _isLoading ? null : _selectExecutable,
                child: const Text('Select Executable'),
              ),
              if (_selectedExePath != null) ...[
                const SizedBox(height: 8),
                Text('Selected: ${path.basename(_selectedExePath!)}'),
              ],
              const SizedBox(height: 16),
            ],
            const Text('Select Wine Prefix:'),
            const SizedBox(height: 8),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ..._prefixes.map((prefix) => SimpleDialogOption(
                onPressed: () => setState(() => selectedPrefix = prefix),
                child: ListTile(
                  title: Text(path.basename(prefix.path)),
                  subtitle: Text('${prefix.version} (${prefix.is64Bit ? "64-bit" : "32-bit"})'),
                  trailing: Text(
                    DateFormat('yyyy-MM-dd').format(prefix.created),
                  ),
                ),
              )),
            if (widget.gamePath != null) ...[
              const SizedBox(height: 16),
              _buildEnvironmentSection(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: selectedPrefix == null ? null : () {
            if (widget.gamePath != null) {
              Navigator.pop(context, {
                'exePath': _selectedExePath,
                'prefix': selectedPrefix,
                'environment': _getEnvironmentVariables(),
              });
            } else {
              Navigator.pop(context, selectedPrefix);
            }
          },
          child: const Text('Select'),
        ),
      ],
    );
  }
} 