enum GameFolderType {
  normal,
  squashed,
}

class GameFolder {
  final String path;
  final GameFolderType type;
  final DateTime added;

  GameFolder({
    required this.path,
    required this.type,
    DateTime? added,
  }) : added = added ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'path': path,
    'type': type.name,
    'added': added.toIso8601String(),
  };

  factory GameFolder.fromJson(Map<String, dynamic> json) {
    return GameFolder(
      path: json['path'],
      type: GameFolderType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => GameFolderType.normal,
      ),
      added: DateTime.parse(json['added']),
    );
  }
} 