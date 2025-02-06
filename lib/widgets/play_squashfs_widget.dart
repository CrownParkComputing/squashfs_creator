import 'package:flutter/material.dart';
import '../services/squash_manager.dart';
import '../services/wine_service.dart';
import '../models/wine_prefix.dart';
import 'executable_selector_dialog.dart';
import 'prefix_selector_dialog.dart';
import 'dart:io';

class PlaySquashFSWidget extends StatefulWidget {
  final String squashPath;

  const PlaySquashFSWidget({
    super.key,
    required this.squashPath,
  });

  @override
  State<PlaySquashFSWidget> createState() => _PlaySquashFSWidgetState();
}

class _PlaySquashFSWidgetState extends State<PlaySquashFSWidget> {
  final SquashManager _squashManager = SquashManager();
  final WineService _wineService = WineService();
  String? _mountPoint;
  bool _isMounting = false;
  String _status = '';

  @override
  void dispose() {
    _unmountIfNeeded();
    super.dispose();
  }

  Future<void> _unmountIfNeeded() async {
    if (_mountPoint != null) {
      try {
        await _squashManager.unmountSquashFS(_mountPoint!);
      } catch (e) {
        print('Error unmounting: $e');
      }
      _mountPoint = null;
    }
  }

  Future<void> _mountAndPlay() async {
    if (_isMounting) return;

    setState(() {
      _isMounting = true;
      _status = 'Mounting SquashFS...';
    });

    try {
      print('Attempting to mount: ${widget.squashPath}');
      
      // Test mount first
      final mountSuccess = await _squashManager.testMount(widget.squashPath);
      if (!mountSuccess) {
        throw Exception('Failed to mount SquashFS file. Please check if the file is valid and you have the required permissions.');
      }
      
      // Now do the actual mount for use
      _mountPoint = await _squashManager.mountSquashFS(widget.squashPath);
      print('Mounted at: $_mountPoint');

      // Verify mount point exists and is accessible
      final mountDir = Directory(_mountPoint!);
      if (!await mountDir.exists()) {
        throw Exception('Mount point does not exist after mounting');
      }

      // List files in mount point for debugging
      print('Listing files in mount point:');
      await for (final entity in mountDir.list(recursive: true)) {
        print('Found: ${entity.path}');
        if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
          print('Found executable: ${entity.path}');
        }
      }

      // Show executable selector
      final exePath = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => ExecutableSelectorDialog(
          directoryPath: _mountPoint!,
        ),
      );

      print('Selected exe path: $exePath');

      if (exePath == null) {
        print('No exe selected, unmounting...');
        await _unmountIfNeeded();
        return;
      }

      // Show prefix selector
      final prefixes = await _wineService.loadPrefixes();
      print('Available prefixes: ${prefixes.length}');
      
      if (!mounted) return;

      final prefix = await showDialog<WinePrefix>(
        context: context,
        barrierDismissible: false, // Prevent accidental dismissal
        builder: (context) => PrefixSelectorDialog(
          prefixes: prefixes,
        ),
      );

      print('Selected prefix: ${prefix?.path}');

      if (prefix == null) {
        print('No prefix selected, unmounting...');
        await _unmountIfNeeded();
        return;
      }

      // Launch the executable
      setState(() => _status = 'Launching game...');
      print('Launching exe: $exePath with prefix: ${prefix.path}');
      await _wineService.launchExe(exePath, prefix);

    } catch (e) {
      print('Error in _mountAndPlay: $e');
      setState(() => _status = 'Error: $e');
      await _unmountIfNeeded();
    } finally {
      if (!mounted) return;
      setState(() => _isMounting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(  // Changed from Column to Row for better layout
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(  // Changed to ElevatedButton.icon for better UX
          onPressed: _isMounting ? null : _mountAndPlay,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Play'),
        ),
        if (_isMounting) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
        if (_status.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(child: Text(_status, overflow: TextOverflow.ellipsis)),
        ],
      ],
    );
  }
} 