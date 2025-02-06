import 'package:flutter/material.dart';
import '../widgets/squashed_games_widget.dart';
import '../widgets/regular_games_widget.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/game_folder.dart';

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  List<String> _squashedPaths = [];
  List<String> _normalPaths = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGameFolders();
  }

  Future<void> _loadGameFolders() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList('game_folders') ?? [];
      final folders = jsonList
          .map((json) => GameFolder.fromJson(jsonDecode(json)))
          .toList();

      setState(() {
        _squashedPaths = folders
            .where((f) => f.type == GameFolderType.squashed)
            .map((f) => f.path)
            .toList();
        _normalPaths = folders
            .where((f) => f.type == GameFolderType.normal)
            .map((f) => f.path)
            .toList();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Games'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Regular Games'),
              Tab(text: 'Squashed Games'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  RegularGamesWidget(gameFolders: _normalPaths),
                  SquashedGamesWidget(squashPaths: _squashedPaths),
                ],
              ),
      ),
    );
  }
} 