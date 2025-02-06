class GamePrefixAssociation {
  final String path;
  final String prefixPath;
  final String prefixVersion;
  final String prefixName;

  GamePrefixAssociation({
    required this.path,
    required this.prefixPath,
    required this.prefixVersion,
    required this.prefixName,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'prefixPath': prefixPath,
    'prefixVersion': prefixVersion,
    'prefixName': prefixName,
  };

  factory GamePrefixAssociation.fromJson(Map<String, dynamic> json) {
    return GamePrefixAssociation(
      path: json['path'],
      prefixPath: json['prefixPath'],
      prefixVersion: json['prefixVersion'],
      prefixName: json['prefixName'],
    );
  }
} 