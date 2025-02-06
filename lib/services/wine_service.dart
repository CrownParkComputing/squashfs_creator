import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../models/wine_prefix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_prefix_association.dart';
import '../models/wine_build.dart';

class WineService {
  static const Map<String, Map<String, String>> AVAILABLE_VERSIONS = {
    'GE-Proton': {
      'GE-Proton9-23': 'GE-Proton9-23.tar.gz',  // Latest GE-Proton release
    },
    'Wine': {
      // Regular Wine 10.0 builds
      'wine-10.0-amd64': 'wine-10.0-amd64.tar.xz',
      'wine-10.0-amd64-wow64': 'wine-10.0-amd64-wow64.tar.xz',
      
      // Staging builds
      'wine-10.0-staging-amd64': 'wine-10.0-staging-amd64.tar.xz',
      'wine-10.0-staging-amd64-wow64': 'wine-10.0-staging-amd64-wow64.tar.xz',
      
      // TKG builds
      'wine-10.0-staging-tkg-amd64': 'wine-10.0-staging-tkg-amd64.tar.xz',
      'wine-10.0-staging-tkg-amd64-wow64': 'wine-10.0-staging-tkg-amd64-wow64.tar.xz',
    },
  };

  // Add these constants for dependency URLs
  static const Map<String, String> DEPENDENCY_URLS = {
    'vcredist_2022': 'https://aka.ms/vs/17/release/vc_redist.x64.exe',
    'vcredist_2019': 'https://aka.ms/vs/16/release/vc_redist.x64.exe',
    'vcredist_2017': 'https://download.microsoft.com/download/2/B/C/2BC2E7B3-3B11-4C8C-BBC4-F7C92666E1DF/vc_redist.x64.exe',
    'vcredist_2015': 'https://download.microsoft.com/download/6/A/A/6AA4EDFF-645B-48C5-81CC-ED5963AEAD48/vc_redist.x64.exe',
    'directx_runtime': 'https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe',
    'dxvk': 'https://github.com/doitsujin/dxvk/releases/download/v2.3.1/dxvk-2.3.1.tar.gz',
    'vkd3d': 'https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v2.11/vkd3d-proton-2.11.tar.zst',
  };

  final void Function(String)? logCallback;
  String? _cachedBaseDir;

  WineService({this.logCallback});

  Future<String> get baseDir async {
    if (_cachedBaseDir != null) return _cachedBaseDir!;
    final prefs = await SharedPreferences.getInstance();
    _cachedBaseDir = prefs.getString('prefix_base_dir') ?? 
                     path.join(Platform.environment['HOME']!, '.wine_prefixes');
    return _cachedBaseDir!;
  }

  // Download and setup methods
  Future<void> downloadAndSetupPrefix(String version) async {
    try {
      onLog('Starting download of $version...');
      
      final downloadDir = Directory(path.join(await baseDir, 'downloads'));
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final downloadPath = path.join(downloadDir.path, version);
      
      // Get download URL based on version
      final url = _getDownloadUrl(version);
      
      // Download the file
      final response = await HttpClient().getUrl(Uri.parse(url));
      final httpResponse = await response.close();
      
      if (httpResponse.statusCode != 200) {
        throw Exception('Failed to download: ${httpResponse.statusCode}');
      }

      // Save to file
      final file = File(downloadPath);
      await httpResponse.pipe(file.openWrite());

      // Extract and setup
      await _extractAndSetupPrefix(downloadPath, version);
      
      // Cleanup download
      await file.delete();

    } catch (e) {
      onLog('Error: $e');
      rethrow;
    }
  }

  String _getDownloadUrl(String version) {
    if (version.startsWith('GE-Proton')) {
      // GE-Proton releases from GloriousEggroll's repo
      return 'https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$version/$version.tar.gz';
    }
    
    // For Kron4ek's Wine builds, the URL structure is:
    // https://github.com/Kron4ek/Wine-Builds/releases/download/10.0/wine-10.0-amd64.tar.xz
    return 'https://github.com/Kron4ek/Wine-Builds/releases/download/10.0/$version.tar.xz';
  }

  Future<void> _extractAndSetupPrefix(String archivePath, String version) async {
    try {
      final prefixDir = Directory(path.join(await baseDir, version));
      if (!await prefixDir.exists()) {
        await prefixDir.create(recursive: true);
      }

      onLog('Extracting archive...');
      if (version.startsWith('GE-Proton')) {
        // GE-Proton extraction
        await Process.run('tar', ['xzf', archivePath, '-C', prefixDir.path]);
        
        // Create the prefix directory
        final pfxDir = Directory(path.join(prefixDir.path, 'pfx'));
        if (!await pfxDir.exists()) {
          await pfxDir.create(recursive: true);
        }

        // Initialize the prefix using Proton's Python script
        onLog('Initializing prefix...');
        final protonPath = path.join(prefixDir.path, version, 'proton');
        
        if (!await File(protonPath).exists()) {
          throw Exception('Proton script not found at: $protonPath');
        }

        final result = await Process.run(
          'python3',
          [protonPath, 'run', 'wineboot', '--init'],
          environment: {
            'STEAM_COMPAT_CLIENT_INSTALL_PATH': prefixDir.path,
            'STEAM_COMPAT_DATA_PATH': pfxDir.path,
            'WINEPREFIX': pfxDir.path,
            'WINEARCH': 'win64',
            'DXVK_ASYNC': '1',
            'PROTON_NO_ESYNC': '0',
            'PROTON_NO_FSYNC': '0',
            'PROTON_HIDE_NVIDIA_GPU': '0',
            'PROTON_ENABLE_NVAPI': '1',
          },
        );

        if (result.exitCode != 0) {
          throw Exception('Failed to initialize prefix: ${result.stderr}');
        }

      } else {
        // Regular Wine extraction
        await Process.run('tar', ['xJf', archivePath, '-C', prefixDir.path]);
        
        // Move files from nested directory if needed
        final extractedDir = Directory(path.join(prefixDir.path, version.replaceAll('.tar.xz', '')));
        if (await extractedDir.exists()) {
          await for (final entity in extractedDir.list()) {
            final newPath = path.join(prefixDir.path, path.basename(entity.path));
            await entity.rename(newPath);
          }
          await extractedDir.delete();
        }

        // Initialize the prefix
        onLog('Initializing prefix...');
        final wine64Path = path.join(prefixDir.path, 'bin', 'wine64');
        if (!await File(wine64Path).exists()) {
          throw Exception('Wine64 binary not found at: $wine64Path');
        }

        final result = await Process.run(
          wine64Path,
          ['wineboot', '--init'],
          environment: {
            'WINEPREFIX': path.join(prefixDir.path, 'pfx'),
            'WINEARCH': 'win64',
          },
        );

        if (result.exitCode != 0) {
          throw Exception('Failed to initialize prefix: ${result.stderr}');
        }
      }

      onLog('Prefix setup complete!');
    } catch (e) {
      onLog('Error during extraction/setup: $e');
      rethrow;
    }
  }

  Future<void> launchExe(
    String exePath,
    WinePrefix prefix, {
    Map<String, String>? environment,
  }) async {
    try {
      onLog('Launching ${path.basename(exePath)} with ${prefix.version}...');
      
      if (prefix.version.startsWith('GE-Proton')) {
        await _launchWithProton(exePath, prefix, environment: environment);
      } else {
        await _launchWithWine(exePath, prefix, environment: environment);
      }
    } catch (e) {
      onLog('Error launching exe: $e');
      rethrow;
    }
  }

  Future<void> _launchWithProton(
    String exePath, 
    WinePrefix prefix, {
    Map<String, String>? environment,
  }) async {
    final versionDir = path.dirname(prefix.path);
    final geProtonDir = path.join(versionDir, prefix.version);
    final protonPath = path.join(geProtonDir, 'proton');

    if (!await File(protonPath).exists()) {
      throw Exception('Proton script not found at: $protonPath');
    }

    if (!await File(exePath).exists()) {
      throw Exception('Executable not found at: $exePath');
    }

    onLog('Using Proton at: $protonPath');
    onLog('Launching: $exePath');

    final env = {
      'STEAM_COMPAT_CLIENT_INSTALL_PATH': geProtonDir,
      'STEAM_COMPAT_DATA_PATH': prefix.path,
      'WINEPREFIX': prefix.path,
      'WINEARCH': 'win64',
      'PROTON_ENABLE_NVAPI': '1',
      'PROTON_ENABLE_FSYNC': '1',
      'PROTON_HIDE_NVIDIA_GPU': '0',
      'DXVK_ASYNC': '1',
      ...?environment,
    };

    final workingDir = path.dirname(exePath);
    
    final process = await Process.start(
      'python3',
      [protonPath, 'run', exePath],
      environment: env,
      workingDirectory: workingDir,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('Process exited with code $exitCode');
    }
  }

  Future<void> _launchWithWine(
    String exePath, 
    WinePrefix prefix, {
    Map<String, String>? environment,
  }) async {
    final prefixParent = path.dirname(prefix.path);
    final winePath = path.join(prefixParent, 'bin', 'wine64');

    if (!await File(winePath).exists()) {
      throw Exception('Wine64 binary not found at: $winePath');
    }

    if (!await File(exePath).exists()) {
      throw Exception('Executable not found at: $exePath');
    }

    onLog('Using Wine at: $winePath');
    onLog('Launching: $exePath');

    final env = {
      'WINEPREFIX': prefix.path,
      'WINEARCH': 'win64',
      'DXVK_ASYNC': '1',
      ...?environment,
    };

    final workingDir = path.dirname(exePath);

    final process = await Process.start(
      winePath,
      [exePath],
      environment: env,
      workingDirectory: workingDir,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('Process exited with code $exitCode');
    }
  }

  // Prefix management methods
  Future<List<WinePrefix>> loadPrefixes() async {
    try {
      final dir = Directory(await baseDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        return [];
      }

      final prefixes = <WinePrefix>[];
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final pfxPath = path.join(entity.path, 'pfx');
          if (await Directory(pfxPath).exists()) {
            prefixes.add(WinePrefix(
              path: pfxPath,
              version: path.basename(entity.path),
              created: (await entity.stat()).modified,
              is64Bit: true,
            ));
          }
        }
      }
      return prefixes;
    } catch (e) {
      onLog('Error loading prefixes: $e');
      return [];
    }
  }

  Future<List<WineBuild>> fetchAvailableBuilds() async {
    final builds = <WineBuild>[];
    
    for (final category in AVAILABLE_VERSIONS.entries) {
      for (final version in category.value.entries) {
        builds.add(WineBuild(
          name: version.value,
          url: _getDownloadUrl(version.key),
          type: _getWineType(category.key),
          version: version.key,
        ));
      }
    }
    
    return builds;
  }

  WineType _getWineType(String category) {
    switch (category) {
      case 'GE-Proton':
        return WineType.proton;
      case 'Wine':
        return WineType.vanilla;
      default:
        return WineType.vanilla;
    }
  }

  void onLog(String message) {
    print(message);
    logCallback?.call(message);
  }

  Future<List<GamePrefixAssociation>> loadGameAssociations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('game_associations');
    if (jsonString == null) return [];
    
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => GamePrefixAssociation.fromJson(json)).toList();
  }

  Future<void> saveGameAssociation(GamePrefixAssociation association) async {
    final prefs = await SharedPreferences.getInstance();
    final associations = await loadGameAssociations();
    
    // Remove any existing association for this game
    associations.removeWhere((a) => a.path == association.path);
    
    // Add the new association
    associations.add(association);
    
    // Save to storage
    final jsonList = associations.map((a) => a.toJson()).toList();
    await prefs.setString('game_associations', jsonEncode(jsonList));
  }

  Future<GamePrefixAssociation?> getGameAssociation(String path) async {
    final associations = await loadGameAssociations();
    try {
      return associations.firstWhere((a) => a.path == path);
    } catch (e) {
      return null;
    }
  }

  Future<void> removeGameAssociation(String path) async {
    final associations = await loadGameAssociations();
    associations.removeWhere((a) => a.path == path);
    
    final prefs = await SharedPreferences.getInstance();
    final jsonList = associations.map((a) => a.toJson()).toList();
    await prefs.setString('game_associations', jsonEncode(jsonList));
  }

  Future<void> cleanupAllSquashfsMounts(WinePrefix prefix) async {
    try {
      final mountPoint = path.join(prefix.path, 'drive_c', 'squashfs_games');
      if (await Directory(mountPoint).exists()) {
        await Process.run('fusermount', ['-uz', mountPoint]);
        await Directory(mountPoint).delete(recursive: true);
      }
    } catch (e) {
      print('Error cleaning up squashfs mounts: $e');
      rethrow;
    }
  }

  Future<List<String>> mountSquashfsGame(WinePrefix prefix, String squashPath) async {
    try {
      final mountPoint = path.join(prefix.path, 'drive_c', 'squashfs_games');
      await Directory(mountPoint).create(recursive: true);

      final result = await Process.run('squashfuse', [
        squashPath,
        mountPoint,
      ]);

      if (result.exitCode != 0) {
        throw Exception('Failed to mount squashfs: ${result.stderr}');
      }

      // Find all .exe files in the mounted directory
      final exeFiles = <String>[];
      await for (final entity in Directory(mountPoint).list(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
          exeFiles.add(entity.path);
        }
      }

      return exeFiles;
    } catch (e) {
      print('Error mounting squashfs game: $e');
      rethrow;
    }
  }

  Future<WinePrefix?> loadPrefixByPath(String prefixPath) async {
    try {
      final dir = Directory(prefixPath);
      if (!await dir.exists()) return null;

      final stat = await dir.stat();
      return WinePrefix(
        path: prefixPath,
        version: path.basename(path.dirname(prefixPath)),
        created: stat.modified,
        is64Bit: true,
      );
    } catch (e) {
      onLog('Error loading prefix by path: $e');
      return null;
    }
  }

  // Add method to install dependencies
  Future<void> installDependencies(WinePrefix prefix, List<String> dependencies) async {
    final winetricks = await _findWinetricks();
    
    for (final dep in dependencies) {
      onLog('Installing $dep...');
      
      // Use winetricks directly for vcrun installations
      if (dep.startsWith('vcrun')) {
        await _installWithWinetricks(prefix, dep, winetricks);
      } else if (DEPENDENCY_URLS.containsKey(dep)) {
        // Download and install specific version
        await _installSpecificDependency(prefix, dep);
      } else {
        // Use winetricks for other dependencies
        await _installWithWinetricks(prefix, dep, winetricks);
      }
    }
  }

  Future<String> _findWinetricks() async {
    // First check if winetricks is in PATH
    try {
      final result = await Process.run('which', ['winetricks']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (_) {}

    // If not found, download it
    final winetricksPath = path.join(await baseDir, 'winetricks');
    if (!await File(winetricksPath).exists()) {
      onLog('Downloading winetricks...');
      final response = await HttpClient().getUrl(
        Uri.parse('https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks'),
      );
      final httpResponse = await response.close();
      await httpResponse.pipe(File(winetricksPath).openWrite());
      await Process.run('chmod', ['+x', winetricksPath]);
    }
    return winetricksPath;
  }

  Future<void> _installSpecificDependency(WinePrefix prefix, String dep) async {
    final url = DEPENDENCY_URLS[dep]!;
    final fileName = path.basename(url);
    final downloadPath = path.join(await baseDir, 'downloads', fileName);

    // Download the dependency
    onLog('Downloading $fileName...');
    final response = await HttpClient().getUrl(Uri.parse(url));
    final httpResponse = await response.close();
    await httpResponse.pipe(File(downloadPath).openWrite());

    if (dep.startsWith('vcredist')) {
      // Install Visual C++ Redistributable
      await _launchWithWine(downloadPath, prefix);
    } else if (dep == 'directx_runtime') {
      // Extract and install DirectX
      await _extractAndInstallDirectX(downloadPath, prefix);
    } else if (dep == 'dxvk') {
      // Install DXVK
      await _installDXVK(downloadPath, prefix);
    } else if (dep == 'vkd3d') {
      // Install VKD3D
      await _installVKD3D(downloadPath, prefix);
    }

    // Cleanup
    await File(downloadPath).delete();
  }

  Future<void> _installWithWinetricks(WinePrefix prefix, String verb, String winetricksPath) async {
    onLog('Running winetricks $verb...');
    
    if (prefix.version.startsWith('GE-Proton')) {
      // For Proton prefixes, we need to use Proton's wine command
      final versionDir = path.dirname(prefix.path);
      final geProtonDir = path.join(versionDir, prefix.version);
      final protonPath = path.join(geProtonDir, 'proton');

      final process = await Process.start(
        'python3',
        [protonPath, 'run', winetricksPath, '--unattended', verb],
        environment: {
          'STEAM_COMPAT_CLIENT_INSTALL_PATH': geProtonDir,
          'STEAM_COMPAT_DATA_PATH': prefix.path,
          'WINEPREFIX': prefix.path,
          'WINEARCH': 'win64',
          'WINETRICKS_LATEST_VERSION_CHECK': 'disabled',
          'PROTON_NO_ESYNC': '1',  // Disable esync for installation
          'PROTON_NO_FSYNC': '1',  // Disable fsync for installation
        },
        mode: ProcessStartMode.inheritStdio,
      );

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw Exception('Winetricks failed with exit code $exitCode');
      }
    } else {
      // Regular Wine prefix installation
      final process = await Process.start(
        'bash',
        [winetricksPath, '--unattended', verb],
        environment: {
          'WINEPREFIX': prefix.path,
          'WINEARCH': 'win64',
          'WINETRICKS_LATEST_VERSION_CHECK': 'disabled',
        },
        mode: ProcessStartMode.inheritStdio,
      );

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw Exception('Winetricks failed with exit code $exitCode');
      }
    }

    // Add a small delay to ensure installation completes
    await Future.delayed(const Duration(seconds: 2));
  }

  Future<void> _extractAndInstallDirectX(String downloadPath, WinePrefix prefix) async {
    // Create temp directory for extraction
    final extractDir = path.join(await baseDir, 'tmp', 'directx');
    await Directory(extractDir).create(recursive: true);

    // Extract DirectX
    await Process.run('7z', ['x', downloadPath, '-o${extractDir}']);

    // Run DXSETUP.exe
    await _launchWithWine(
      path.join(extractDir, 'DXSETUP.exe'),
      prefix,
    );

    // Cleanup
    await Directory(extractDir).delete(recursive: true);
  }

  Future<void> _installDXVK(String downloadPath, WinePrefix prefix) async {
    // Extract DXVK
    final extractDir = path.join(await baseDir, 'tmp', 'dxvk');
    await Directory(extractDir).create(recursive: true);
    await Process.run('tar', ['xzf', downloadPath, '-C', extractDir]);

    // Run setup script
    final setupScript = path.join(extractDir, 'dxvk-2.3.1', 'setup_dxvk.sh');
    await Process.run(
      'bash',
      [setupScript, 'install'],
      environment: {'WINEPREFIX': prefix.path},
    );

    // Cleanup
    await Directory(extractDir).delete(recursive: true);
  }

  Future<void> _installVKD3D(String downloadPath, WinePrefix prefix) async {
    // Extract VKD3D
    final extractDir = path.join(await baseDir, 'tmp', 'vkd3d');
    await Directory(extractDir).create(recursive: true);
    await Process.run('tar', ['xf', downloadPath, '-C', extractDir]);

    // Run setup script
    final setupScript = path.join(extractDir, 'setup_vkd3d_proton.sh');
    await Process.run(
      'bash',
      [setupScript, 'install'],
      environment: {'WINEPREFIX': prefix.path},
    );

    // Cleanup
    await Directory(extractDir).delete(recursive: true);
  }

  Future<void> launchWinecfg(WinePrefix prefix) async {
    if (prefix.version.startsWith('GE-Proton')) {
      final versionDir = path.dirname(prefix.path);
      final geProtonDir = path.join(versionDir, prefix.version);
      final protonPath = path.join(geProtonDir, 'proton');

      final process = await Process.start(
        'python3',
        [protonPath, 'run', 'winecfg'],
        environment: {
          'STEAM_COMPAT_CLIENT_INSTALL_PATH': geProtonDir,
          'STEAM_COMPAT_DATA_PATH': prefix.path,
          'WINEPREFIX': prefix.path,
          'WINEARCH': 'win64',
        },
        mode: ProcessStartMode.inheritStdio,
      );

      await process.exitCode;
    } else {
      // For Kron4ek's builds, wine64 is in the prefix parent directory
      final prefixParent = path.dirname(prefix.path);
      final winePath = path.join(prefixParent, 'bin', 'wine64');

      if (!await File(winePath).exists()) {
        throw Exception('Wine64 binary not found at: $winePath');
      }

      final process = await Process.start(
        winePath,
        ['winecfg'],
        environment: {
          'WINEPREFIX': prefix.path,
          'WINEARCH': 'win64',
        },
        mode: ProcessStartMode.inheritStdio,
      );

      await process.exitCode;
    }
  }
} 