class GamePrefixAssociation {
  final String path; // Path to the squashfs file
  final String? exePath; // Path to the exe inside squashfs
  final String? prefixPath; // Path to the wine prefix

  GamePrefixAssociation({
    required this.path,
    this.exePath,
    this.prefixPath,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'exePath': exePath,
    'prefixPath': prefixPath,
  };

  factory GamePrefixAssociation.fromJson(Map<String, dynamic> json) {
    return GamePrefixAssociation(
      path: json['path'],
      exePath: json['exePath'],
      prefixPath: json['prefixPath'],
    );
  }
} 