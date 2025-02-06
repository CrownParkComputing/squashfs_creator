import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import 'package:path/path.dart' as path;

class PrefixSelectorDialog extends StatelessWidget {
  final List<WinePrefix> prefixes;

  const PrefixSelectorDialog({
    super.key,
    required this.prefixes,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Wine Prefix'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: prefixes.length,
          itemBuilder: (context, index) {
            final prefix = prefixes[index];
            return ListTile(
              title: Text(prefix.version),
              subtitle: Text(path.basename(prefix.path)),
              onTap: () => Navigator.of(context).pop(prefix),
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