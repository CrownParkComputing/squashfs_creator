import 'package:flutter/material.dart';
import '../models/wine_prefix.dart';
import '../services/prefix_manager.dart';

class WinetricksDialog extends StatelessWidget {
  final WinePrefix prefix;

  const WinetricksDialog({
    super.key,
    required this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Set<String>>(
      future: PrefixManager().loadInstalledDependencies(prefix.path),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final installedDependencies = snapshot.data!;
        final dependencies = {
          'Visual C++ Runtimes': {
            'vcrun2005': 'Visual C++ 2005',
            'vcrun2008': 'Visual C++ 2008',
            'vcrun2010': 'Visual C++ 2010',
            'vcrun2012': 'Visual C++ 2012',
            'vcrun2013': 'Visual C++ 2013',
            'vcrun2015': 'Visual C++ 2015',
            'vcrun2017': 'Visual C++ 2017',
            'vcrun2019': 'Visual C++ 2019',
            // vcrun2022 is installed by default
          },
          'DirectX Components': {
            // dxvk and vkd3d are installed by default
            'd3dx9': 'DirectX 9',
            // d3dx11 is installed by default
            'd3dx10': 'DirectX 10',
          },
          'Common Libraries': {
            'dotnet48': '.NET Framework 4.8',
            'dotnet40': '.NET Framework 4.0',
            'xna40': 'XNA Framework 4.0',
            'msxml6': 'MSXML 6.0',
          },
          'Media Components': {
            'ffdshow': 'FFDshow Video Codecs',
            'quicktime72': 'QuickTime 7.2',
            'wmp11': 'Windows Media Player 11',
          },
          'Gaming Components': {
            // SDL is configured by default
            'xact': 'XACT (Xbox Audio)',
            'xinput': 'XInput (Controller Support)',
            'physx': 'PhysX',
          },
        };

        return AlertDialog(
          title: const Text('Install Dependencies'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (installedDependencies.isNotEmpty) ...[
                  Text(
                    'Installed Components:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Wrap(
                    spacing: 8,
                    children: installedDependencies.map((dep) => Chip(
                      label: Text(dep),
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                    )).toList(),
                  ),
                  const Divider(),
                ],
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: dependencies.length,
                    itemBuilder: (context, index) {
                      final category = dependencies.keys.elementAt(index);
                      final items = dependencies[category]!;
                      
                      // Filter out already installed components
                      final availableItems = Map.fromEntries(
                        items.entries.where((e) => !installedDependencies.contains(e.key))
                      );

                      if (availableItems.isEmpty) return const SizedBox.shrink();
                      
                      return ExpansionTile(
                        title: Text(category),
                        children: availableItems.entries.map((entry) {
                          return ListTile(
                            title: Text(entry.value),
                            subtitle: Text(entry.key),
                            onTap: () {
                              Navigator.of(context).pop(entry.key);
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop('winetricks');
              },
              child: const Text('Launch Winetricks GUI'),
            ),
          ],
        );
      },
    );
  }
} 