import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';

class WinePrefixSelector extends StatelessWidget {
  const WinePrefixSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final availableBuilds = context.watch<Settings>().availableWineBuilds;
    
    if (availableBuilds.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Wine Prefix', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ExpansionTile(
          title: const Text('Proton Builds'),
          initiallyExpanded: true,  // Make it open by default for testing
          children: _buildWinePrefixList(WineType.proton, context),
        ),
        ExpansionTile(
          title: const Text('Staging Builds'),
          children: _buildWinePrefixList(WineType.staging, context),
        ),
        ExpansionTile(
          title: const Text('Vanilla Builds'),
          children: _buildWinePrefixList(WineType.vanilla, context),
        ),
      ],
    );
  }

  List<Widget> _buildWinePrefixList(WineType type, BuildContext context) {
    final settings = context.watch<Settings>();
    
    return settings.availableWineBuilds
        .where((build) => build.type == type)
        .map((build) => RadioListTile<WineBuild>(
              title: Text('${build.name} (${build.version})'),
              subtitle: Text(build.url),
              value: build,
              groupValue: settings.selectedWineBuild,
              onChanged: (value) {
                if (value != null) {
                  settings.updateSelectedWinePrefix(value);
                }
              },
            ))
        .toList();
  }
} 