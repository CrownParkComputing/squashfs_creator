import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:logging/logging.dart';

class DllOverrideManager extends StatefulWidget {
  final WinePrefix prefix;

  const DllOverrideManager({
    super.key,
    required this.prefix,
  });

  @override
  State<DllOverrideManager> createState() => _DllOverrideManagerState();
}

class _DllOverrideManagerState extends State<DllOverrideManager> {
  final _logger = Logger('DllOverrideManager');
  final _dllController = TextEditingController();
  String _selectedOverride = 'native';
  bool _isLoading = false;
  Map<String, String> _currentOverrides = {};

  static const overrideOptions = {
    'native': 'Native (Windows)',
    'builtin': 'Built-in (Wine)',
    'native,builtin': 'Native then Built-in',
    'builtin,native': 'Built-in then Native',
    'disabled': 'Disabled',
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentOverrides();
  }

  Future<void> _loadCurrentOverrides() async {
    setState(() => _isLoading = true);
    try {
      final result = await _getDllOverrides();
      setState(() => _currentOverrides = result);
    } catch (e) {
      _logger.severe('Error loading DLL overrides: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading DLL overrides: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, String>> _getDllOverrides() async {
    final overrides = <String, String>{};
    
    if (widget.prefix.isProton) {
      final result = await Process.run('python3', [
        widget.prefix.protonPath,
        'run',
        'wine',
        'reg',
        'query',
        'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides',
      ], environment: {
        'WINEPREFIX': widget.prefix.path,
        'STEAM_COMPAT_CLIENT_INSTALL_PATH': widget.prefix.protonDir,
        'STEAM_COMPAT_DATA_PATH': widget.prefix.path,
      });

      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.trim().isNotEmpty && !line.contains('REG_SZ')) continue;
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            overrides[parts[0]] = parts[2];
          }
        }
      }
    }
    
    return overrides;
  }

  Future<void> _setDllOverride(String dll, String override) async {
    setState(() => _isLoading = true);
    try {
      final regContent = '''Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]
"$dll"="$override"
''';

      final tempDir = await Directory.systemTemp.createTemp('dll_override');
      try {
        final regFile = File(path.join(tempDir.path, 'override.reg'));
        await regFile.writeAsString(regContent);

        if (widget.prefix.isProton) {
          final result = await Process.run('python3', [
            widget.prefix.protonPath,
            'run',
            'regedit',
            regFile.path,
          ], environment: {
            'WINEPREFIX': widget.prefix.path,
            'STEAM_COMPAT_CLIENT_INSTALL_PATH': widget.prefix.protonDir,
            'STEAM_COMPAT_DATA_PATH': widget.prefix.path,
          });

          if (result.exitCode != 0) {
            throw Exception('Failed to set DLL override: ${result.stderr}');
          }
        }

        await _loadCurrentOverrides();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully set override for $dll')),
          );
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    } catch (e) {
      _logger.severe('Error setting DLL override: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error setting DLL override: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DLL Overrides',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dllController,
                    decoration: const InputDecoration(
                      labelText: 'DLL Name',
                      hintText: 'e.g., d3d11',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedOverride,
                  items: overrideOptions.entries.map((e) {
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedOverride = value);
                    }
                  },
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : () {
                    final dll = _dllController.text.trim();
                    if (dll.isNotEmpty) {
                      _setDllOverride(dll, _selectedOverride);
                      _dllController.clear();
                    }
                  },
                  child: const Text('Add Override'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const LinearProgressIndicator()
            else if (_currentOverrides.isEmpty)
              const Text('No DLL overrides set')
            else
              ListView.builder(
                shrinkWrap: true,
                itemCount: _currentOverrides.length,
                itemBuilder: (context, index) {
                  final entry = _currentOverrides.entries.elementAt(index);
                  return ListTile(
                    title: Text(entry.key),
                    subtitle: Text(overrideOptions[entry.value] ?? entry.value),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _setDllOverride(entry.key, 'builtin'),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dllController.dispose();
    super.dispose();
  }
} 