import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class ExecutableSelectorDialog extends StatefulWidget {
  final String directoryPath;

  const ExecutableSelectorDialog({
    super.key,
    required this.directoryPath,
  });

  @override
  State<ExecutableSelectorDialog> createState() => _ExecutableSelectorDialogState();
}

class _ExecutableSelectorDialogState extends State<ExecutableSelectorDialog> {
  List<String> _exeFiles = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _findExeFiles();
  }

  Future<void> _findExeFiles() async {
    try {
      print('Searching for exes in: ${widget.directoryPath}');
      final exeFiles = <String>[];
      
      await for (final entity in Directory(widget.directoryPath)
          .list(recursive: true)
          .handleError((e) => print('Error listing directory: $e'))) {
        if (entity is File && path.extension(entity.path).toLowerCase() == '.exe') {
          print('Found exe: ${entity.path}');
          exeFiles.add(entity.path);
        }
      }

      if (mounted) {
        setState(() {
          _exeFiles = exeFiles..sort();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error finding exe files: $e');
      if (mounted) {
        setState(() {
          _error = 'Error scanning directory: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Executable'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? Text(_error, style: const TextStyle(color: Colors.red))
                : _exeFiles.isEmpty
                    ? const Text('No executables found')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _exeFiles.length,
                        itemBuilder: (context, index) {
                          final exePath = _exeFiles[index];
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
    );
  }
} 