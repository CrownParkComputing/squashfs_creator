import 'dart:io';
import 'package:flutter/material.dart';
import '../services/wine_service.dart';
import '../models/wine_prefix.dart';
import '../widgets/main_drawer.dart';
import 'package:path/path.dart' as path;
import '../widgets/dependency_manager_widget.dart';

class WineManagerScreen extends StatefulWidget {
  const WineManagerScreen({super.key});

  @override
  State<WineManagerScreen> createState() => _WineManagerScreenState();
}

class _WineManagerScreenState extends State<WineManagerScreen> {
  final WineService _wineService = WineService(
    logCallback: (msg) => print(msg),
  );
  List<WinePrefix> _prefixes = [];
  bool _isDownloading = false;
  String _selectedVersion = '';
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadPrefixes();
  }

  Future<void> _loadPrefixes() async {
    setState(() => _isDownloading = true);
    try {
      final prefixes = await _wineService.loadPrefixes();
      setState(() => _prefixes = prefixes);
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _downloadAndSetupPrefix() async {
    final version = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Wine Version'),
        children: [
          for (final category in WineService.AVAILABLE_VERSIONS.entries)
            ExpansionTile(
              title: Text(category.key),
              children: [
                for (final version in category.value.entries)
                  ListTile(
                    title: Text(version.value),
                    subtitle: Text(version.key),
                    onTap: () => Navigator.pop(context, version.key),
                  ),
              ],
            ),
        ],
      ),
    );

    if (version == null) return;

    setState(() {
      _isDownloading = true;
      _selectedVersion = version;
      _logs.clear();
    });

    try {
      await _wineService.downloadAndSetupPrefix(
        version,
      );
      await _loadPrefixes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wine Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPrefixes,
            tooltip: 'Refresh',
          ),
        ],
      ),
      drawer: const MainDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Download Progress
            if (_isDownloading) ...[
              LinearProgressIndicator(
                value: _selectedVersion.isEmpty ? null : null,
              ),
              const SizedBox(height: 16),
              Text('Downloading $_selectedVersion...'),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Text(_logs[index]),
                    ),
                  ),
                ),
              ),
            ] else ...[
              // Prefixes List
              Expanded(
                child: ListView.builder(
                  itemCount: _prefixes.length,
                  itemBuilder: (context, index) {
                    final prefix = _prefixes[index];
                    return Card(
                      child: ListTile(
                        title: Text(prefix.version),
                        subtitle: Text(
                          'Created: ${prefix.created.toLocal()}\n'
                          'Path: ${path.basename(prefix.path)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.settings),
                              onPressed: () => _launchWinecfg(prefix),
                              tooltip: 'Wine Configuration',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deletePrefix(prefix),
                              tooltip: 'Delete Prefix',
                            ),
                            IconButton(
                              icon: const Icon(Icons.extension),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Manage Dependencies'),
                                    content: SizedBox(
                                      width: double.maxFinite,
                                      child: DependencyManagerWidget(prefix: prefix),
                                    ),
                                  ),
                                );
                              },
                              tooltip: 'Manage Dependencies',
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isDownloading ? null : _downloadAndSetupPrefix,
        child: const Icon(Icons.add),
        tooltip: 'Add Wine Prefix',
      ),
    );
  }

  Future<void> _launchWinecfg(WinePrefix prefix) async {
    try {
      await _wineService.launchExe('winecfg', prefix);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _deletePrefix(WinePrefix prefix) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Prefix'),
        content: Text('Are you sure you want to delete ${prefix.version}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Directory(path.dirname(prefix.path)).delete(recursive: true);
      await _loadPrefixes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
} 