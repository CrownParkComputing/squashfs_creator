class SquashFileSettings {
  final String path;
  final String? wineExePath;  // Path to exe inside the squash file
  final String? winePrefixPath;  // Path to wine prefix to use
  final DateTime created;

  SquashFileSettings({
    required this.path,
    this.wineExePath,
    this.winePrefixPath,
    required this.created,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'wineExePath': wineExePath,
    'winePrefixPath': winePrefixPath,
    'created': created.toIso8601String(),
  };

  factory SquashFileSettings.fromJson(Map<String, dynamic> json) => SquashFileSettings(
    path: json['path'],
    wineExePath: json['wineExePath'],
    winePrefixPath: json['winePrefixPath'],
    created: DateTime.parse(json['created']),
  );
} 