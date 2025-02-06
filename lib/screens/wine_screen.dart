import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import '../services/wine_service.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:logging/logging.dart';
import 'package:wine_app/widgets/dll_override_manager.dart';
// Make sure this is correct

class WineScreen extends StatefulWidget {
  const WineScreen({super.key});

  @override
  State<WineScreen> createState() => _WineScreenState();
}

class _WineScreenState extends State<WineScreen> {
  final WineService _wineService = WineService();
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
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'run',
          child: ListTile(
            leading: Icon(Icons.play_arrow),
            title: Text('Run Executable'),
            subtitle: Text('Run .exe, .bat, or .msi file'),
          ),
        ),
        const PopupMenuItem(
          value: 'winecfg',
          child: ListTile(
            leading: Icon(Icons.settings),
            title: Text('Wine Configuration'),
            subtitle: Text('Configure wine settings'),
          ),
        ),
        const PopupMenuItem(
          value: 'components',
          child: ListTile(
            leading: Icon(Icons.build),
            title: Text('Install Components'),
            subtitle: Text('Install Visual C++, DirectX, etc'),
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text('Delete Prefix'),
            subtitle: Text('Remove this prefix'),
          ),
        ),
      ],
      onSelected: (value) async {
        switch (value) {
          case 'run':
            await _runExecutable(prefix);
            break;
          case 'winecfg':
            await _wineService.launchWinecfg(prefix);
            break;
          case 'components':
            await _showComponentsDialog(prefix);
            break;
          case 'delete':
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Prefix'),
                content: Text('Delete ${prefix.version}?'),
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
            if (confirm == true) {
              await Directory(prefix.path).delete(recursive: true);
              await _loadPrefixes();
            }
            break;
        }
      },
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
          
          // Graphics Section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Graphics', 
              style: TextStyle(fontWeight: FontWeight.bold)
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'dxvk'),
            child: const Text('DXVK (Vulkan for DX9/10/11)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'vkd3d-proton'),
            child: const Text('VKD3D-Proton (Vulkan for DX12)'),
          ),
          const Divider(),
          
          // DirectX Section
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('DirectX', 
              style: TextStyle(fontWeight: FontWeight.bold)
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'd3dx9'),
            child: const Text('DirectX 9'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'd3dx11'),
            child: const Text('DirectX 11'),
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
            onPressed: () => Navigator.pop(context, 'xact'),
            child: const Text('XACT (Audio)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'xinput'),
            child: const Text('XInput (Controllers)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'dotnet48'),
            child: const Text('.NET Framework 4.8'),
          ),
        ],
      ),
    );

    if (result != null) {
      final category = switch (result) {
        String v when v.startsWith('vcrun') => 'Visual C++',
        String v when v.startsWith('d3d') => 'DirectX',
        'dxvk' => 'DXVK',
        'vkd3d-proton' => 'VKD3D-Proton',
        'xact' => 'XACT',
        'xinput' => 'XInput',
        String v when v.startsWith('dotnet') => '.NET Framework',
        _ => 'Component',
      };
      await _installWinetrick(prefix, result, category);
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
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, version.key),
                    child: ListTile(
                      title: Text(version.key),
                      subtitle: Text(version.value),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );

    if (version == null) return;

    setState(() => _isLoading = true);

    try {
      await _wineService.downloadAndSetupPrefix(version);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully created prefix for $version'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      await _loadPrefixes();
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