import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import '../services/wine_service.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:logging/logging.dart';
import '../widgets/dll_override_manager.dart';
// Make sure this is correct

class WineScreen extends StatefulWidget {
  const WineScreen({super.key});

  @override
  State<WineScreen> createState() => _WineScreenState();
}

class _WineScreenState extends State<WineScreen> {
  final WineService _wineService = WineService();
  final _logger = Logger('WineScreen');
  List<WinePrefix> _prefixes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefixes();
  }

  Future<void> _loadPrefixes() async {
    setState(() => _isLoading = true);
    try {
      _prefixes = await _wineService.loadPrefixes();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _installWinetrick(WinePrefix prefix, String verb, String category) async {
    try {
      setState(() => _isLoading = true);
      await _wineService.installDependencies(prefix, [verb]);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$category: $verb installed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error installing $verb: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _runExecutable(WinePrefix prefix) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe', 'bat', 'msi'],
        dialogTitle: 'Select executable to run',
      );

      if (result != null) {
        final filePath = result.files.single.path;
        if (filePath == null) return;

        setState(() => _isLoading = true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Running ${path.basename(filePath)}...'),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        await _wineService.launchExe(filePath, prefix);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error running executable: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  PopupMenuButton<String> _buildPrefixMenu(WinePrefix prefix) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'More Actions',
      onSelected: (value) async {
        switch (value) {
          case 'run':
            await _runExecutable(prefix);
          case 'winecfg':
            await _wineService.launchWinecfg(prefix);
          case 'dll_overrides':
            if (mounted) {
              await showDialog(
                context: context,
                builder: (context) => Dialog(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: 600,
                      child: DllOverrideManager(prefix: prefix),
                    ),
                  ),
                ),
              );
            }
          case 'winetricks':
            await _showWinetricksDialog(prefix);
          case 'install_component':
            await _showComponentsDialog(prefix);
          case 'delete':
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Prefix'),
                content: Text('Delete prefix "${prefix.name}"?\nThis cannot be undone.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );

            if (confirm == true) {
              setState(() => _isLoading = true);
              try {
                // Get the parent directory (version/prefix_name)
                final prefixDir = Directory(path.dirname(prefix.path));
                await prefixDir.delete(recursive: true);
                await _loadPrefixes();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Prefix "${prefix.name}" deleted'),
                      backgroundColor: Colors.blue,
                    ),
                  );
                }
              } catch (e) {
                _logger.severe('Error deleting prefix: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting prefix: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                setState(() => _isLoading = false);
              }
            }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'run',
          child: Text('Run Executable'),
        ),
        const PopupMenuItem(
          value: 'winecfg',
          child: Text('Wine Configuration'),
        ),
        const PopupMenuItem(
          value: 'dll_overrides',
          child: Text('DLL Overrides'),
        ),
        const PopupMenuItem(
          value: 'winetricks',
          child: Text('Run Winetricks'),
        ),
        const PopupMenuItem(
          value: 'install_component',
          child: Text('Install Component'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: const Text(
            'Delete Prefix',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  Future<void> _showComponentsDialog(WinePrefix prefix) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Install Components'),
        children: [
          // Visual C++ Section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Visual C++ Runtimes', 
              style: TextStyle(fontWeight: FontWeight.bold)
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'vcrun2022'),
            child: const Text('Visual C++ 2022'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'vcrun2019'),
            child: const Text('Visual C++ 2019'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'vcrun2017'),
            child: const Text('Visual C++ 2017'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'vcrun2015'),
            child: const Text('Visual C++ 2015'),
          ),
          const Divider(),
          
          // Other Components Section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Other Components', 
              style: TextStyle(fontWeight: FontWeight.bold)
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'dotnet48'),
            child: const Text('.NET Framework 4.8'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'xact'),
            child: const Text('XACT (Audio)'),
          ),
        ],
      ),
    );

    if (result != null) {
      final category = switch (result) {
        String v when v.startsWith('vcrun') => 'Visual C++',
        'xact' => 'XACT',
        String v when v.startsWith('dotnet') => '.NET Framework',
        _ => 'Component',
      };
      await _installWinetrick(prefix, result, category);
    }
  }

  Future<void> _showWinetricksDialog(WinePrefix prefix) async {
    final controller = TextEditingController();
    final verb = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run Winetricks'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Winetricks Verb',
                hintText: 'e.g., dotnet48, d3dx9, etc',
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            const SizedBox(height: 16),
            const Text(
              'Common verbs:\n'
              '• dotnet48 - .NET Framework 4.8\n'
              '• vcrun2022 - Visual C++ 2022\n'
              '• d3dx9 - DirectX 9\n'
              '• xact - XACT Audio\n'
              '• corefonts - Microsoft Fonts',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Run'),
          ),
        ],
      ),
    );

    if (verb == null || verb.isEmpty) {
      controller.dispose();
      return;
    }
    controller.dispose();

    try {
      setState(() => _isLoading = true);
      await _wineService.installDependencies(prefix, [verb]);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully ran winetricks $verb'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _logger.severe('Error running winetricks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error running winetricks: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadAndSetupPrefix() async {
    // First, get the Proton version
    final version = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Proton Version'),
        children: [
          for (final version in WineService.availableVersions['GE-Proton']!.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, version.key),
              child: ListTile(
                title: Text(version.key),
                subtitle: Text('Latest GE-Proton release'),
              ),
            ),
        ],
      ),
    );

    if (version == null) return;

    // Then get the prefix name
    final controller = TextEditingController();
    final prefixName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Prefix'),
        content: TextField(
          autofocus: true,
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Prefix Name',
            hintText: 'e.g., gaming, dx12, etc',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (prefixName == null || prefixName.isEmpty) {
      controller.dispose();
      return;
    }
    controller.dispose();

    setState(() => _isLoading = true);
    try {
      await _wineService.downloadAndSetupPrefix(version, prefixName);
      await _loadPrefixes();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Prefix "$prefixName" created successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating prefix: $e'),
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
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wine Prefixes'),
        backgroundColor: theme.colorScheme.primaryContainer,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _prefixes.length,
              padding: const EdgeInsets.all(8.0),
              itemBuilder: (context, index) {
                final prefix = _prefixes[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.wine_bar,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      prefix.version,
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      prefix.path,
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: _buildPrefixMenu(prefix),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _downloadAndSetupPrefix,
        tooltip: 'Add Wine Prefix',
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.add,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
} 