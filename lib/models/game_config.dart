class GameConfig {
  final String squashPath;      // Path to the squashfs file
  final String? exePath;        // Selected exe path inside the squashfs
  final String? prefixPath;     // Path to the wine prefix
  final Map<String, String> environment;  // Custom environment variables
  final DateTime lastPlayed;    // Last time the game was launched

  GameConfig({
    required this.squashPath,
    this.exePath,
    this.prefixPath,
    Map<String, String>? environment,
    DateTime? lastPlayed,
  }) : 
    this.environment = environment ?? {},
    this.lastPlayed = lastPlayed ?? DateTime.now();

  bool get isConfigured => exePath != null && prefixPath != null;

  Map<String, dynamic> toJson() => {
    'squashPath': squashPath,
    'exePath': exePath,
    'prefixPath': prefixPath,
    'environment': environment,
    'lastPlayed': lastPlayed.toIso8601String(),
  };

  factory GameConfig.fromJson(Map<String, dynamic> json) {
    return GameConfig(
      squashPath: json['squashPath'],
      exePath: json['exePath'],
      prefixPath: json['prefixPath'],
      environment: Map<String, String>.from(json['environment'] ?? {}),
      lastPlayed: DateTime.parse(json['lastPlayed']),
    );
  }

  GameConfig copyWith({
    String? exePath,
    String? prefixPath,
    Map<String, String>? environment,
  }) {
    return GameConfig(
      squashPath: squashPath,
      exePath: exePath ?? this.exePath,
      prefixPath: prefixPath ?? this.prefixPath,
      environment: environment ?? Map.from(this.environment),
      lastPlayed: lastPlayed,
    );
  }
} 