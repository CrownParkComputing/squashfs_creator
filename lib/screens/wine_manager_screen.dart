import 'dart:io';
import 'package:flutter/material.dart';
import '../services/wine_service.dart';
import '../models/wine_prefix.dart';
import 'package:path/path.dart' as path;
import 'package:logging/logging.dart';

class WineManagerScreen extends StatefulWidget {
  const WineManagerScreen({super.key});

  @override
  State<WineManagerScreen> createState() => _WineManagerScreenState();
}

class _WineManagerScreenState extends State<WineManagerScreen> {
  final _logger = Logger('WineManagerScreen');
  late final WineService _wineService;
  List<WinePrefix> _prefixes = [];
  bool _isDownloading = false;
  String _selectedVersion = '';
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _wineService = WineService(
      logCallback: (msg) => _logger.info(msg),
    );
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
          for (final category in WineService.availableVersions.entries)
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
      drawer: const Drawer(), // Changed MainDrawer to Drawer since MainDrawer isn't defined
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
        tooltip: 'Add Wine Prefix',
        child: const Icon(Icons.add),
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

class DependencyManagerWidget extends StatefulWidget {
  final WinePrefix prefix;

  const DependencyManagerWidget({
    super.key,
    required this.prefix,
  });

  @override
  State<DependencyManagerWidget> createState() => _DependencyManagerWidgetState();
}

class _DependencyManagerWidgetState extends State<DependencyManagerWidget> {
  final WineService _wineService = WineService();
  bool _isInstalling = false;
  String _status = '';

  Future<void> _installDependency(String dep) async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _status = 'Installing $dep...';
    });

    try {
      await _wineService.installDependencies(widget.prefix, [dep]);
      setState(() => _status = '$dep installed successfully!');
    } catch (e) {
      setState(() => _status = 'Error installing $dep: $e');
    } finally {
      setState(() => _isInstalling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Common Dependencies',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: _isInstalling ? null : () => _installDependency('vcrun2019'),
              child: const Text('Visual C++ 2019'),
            ),
            ElevatedButton(
              onPressed: _isInstalling ? null : () => _installDependency('dxvk'),
              child: const Text('DXVK'),
            ),
            ElevatedButton(
              onPressed: _isInstalling ? null : () => _installDependency('vkd3d-proton'),
              child: const Text('VKD3D-Proton'),
            ),
            ElevatedButton(
              onPressed: _isInstalling ? null : () => _installDependency('d3dx9'),
              child: const Text('DirectX 9'),
            ),
            ElevatedButton(
              onPressed: _isInstalling ? null : () => _installDependency('xact'),
              child: const Text('XACT'),
            ),
          ],
        ),
        if (_isInstalling) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_status),
        ],
      ],
    );
  }
} 