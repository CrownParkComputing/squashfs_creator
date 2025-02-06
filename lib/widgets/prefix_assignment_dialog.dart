import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import 'package:path/path.dart' as path;

class PrefixAssignmentDialog extends StatefulWidget {
  final List<WinePrefix> availablePrefixes;
  final WinePrefix? currentPrefix;

  const PrefixAssignmentDialog({
    super.key,
    required this.availablePrefixes,
    this.currentPrefix,
  });

  @override
  State<PrefixAssignmentDialog> createState() => _PrefixAssignmentDialogState();
}

class _PrefixAssignmentDialogState extends State<PrefixAssignmentDialog> {
  late WinePrefix? selectedPrefix;

  @override
  void initState() {
    super.initState();
    selectedPrefix = widget.currentPrefix;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign Wine Prefix'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select a Wine prefix for this game:'),
            const SizedBox(height: 16),
            ...widget.availablePrefixes.map((prefix) => RadioListTile<WinePrefix>(
              title: Text(path.basename(prefix.path)),
              subtitle: Text('${prefix.version} (${prefix.is64Bit ? "64-bit" : "32-bit"})'),
              value: prefix,
              groupValue: selectedPrefix,
              onChanged: (value) {
                setState(() {
                  selectedPrefix = value;
                });
              },
            )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(selectedPrefix),
          child: const Text('Assign'),
        ),
      ],
    );
  }
} 