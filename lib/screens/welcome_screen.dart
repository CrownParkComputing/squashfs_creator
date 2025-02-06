import 'package:flutter/material.dart';
import '../widgets/main_drawer.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wine Manager'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            Scaffold.of(context).openDrawer();
          },
        ),
      ),
      drawer: const MainDrawer(),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wine_bar, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Welcome to Wine Manager',
              style: TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.games),
              label: const Text('Games'),
              onPressed: () {
                Navigator.pushNamed(context, '/games');
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.wine_bar),
              label: const Text('Wine Prefixes'),
              onPressed: () {
                Navigator.pushNamed(context, '/wine');
              },
            ),
          ],
        ),
      ),
    );
  }
} 