import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import '../services/wine_service.dart';

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

  // Common dependency groups
  static const Map<String, List<String>> DEPENDENCY_GROUPS = {
    'Visual C++ Runtimes': [
      'vcredist_2022',
      'vcredist_2019',
      'vcredist_2017',
      'vcredist_2015',
    ],
    'DirectX Components': [
      'directx_runtime',
      'dxvk',
      'vkd3d',
    ],
    'Common Libraries': [
      'd3dx9',
      'dotnet48',
      'xact',
    ],
  };

  Future<void> _installDependencyGroup(String group) async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _status = 'Installing $group...';
    });

    try {
      final dependencies = DEPENDENCY_GROUPS[group]!;
      await _wineService.installDependencies(widget.prefix, dependencies);
      setState(() => _status = '$group installed successfully!');
    } catch (e) {
      setState(() => _status = 'Error installing $group: $e');
    } finally {
      setState(() => _isInstalling = false);
    }
  }

  Future<void> _installCustomDependency() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _CustomDependencyDialog(),
    );

    if (result != null) {
      setState(() {
        _isInstalling = true;
        _status = 'Installing $result...';
      });

      try {
        await _wineService.installDependencies(widget.prefix, [result]);
        setState(() => _status = '$result installed successfully!');
      } catch (e) {
        setState(() => _status = 'Error installing $result: $e');
      } finally {
        setState(() => _isInstalling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Common Dependencies',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final group in DEPENDENCY_GROUPS.keys)
              ElevatedButton(
                onPressed: _isInstalling ? null : () => _installDependencyGroup(group),
                child: Text('Install $group'),
              ),
            ElevatedButton(
              onPressed: _isInstalling ? null : _installCustomDependency,
              child: const Text('Install Other (Winetricks)'),
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

class _CustomDependencyDialog extends StatefulWidget {
  @override
  State<_CustomDependencyDialog> createState() => _CustomDependencyDialogState();
}

class _CustomDependencyDialogState extends State<_CustomDependencyDialog> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Install Custom Dependency'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter the Winetricks verb for the dependency:'),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'e.g., dotnet48, d3dx9, etc.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Install'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
} 