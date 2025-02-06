class WinePrefix {
  final String path;
  final String version;
  final DateTime created;
  final bool is64Bit;

  WinePrefix({
    required this.path,
    required this.version,
    required this.created,
    required this.is64Bit,
  });

  factory WinePrefix.fromJson(Map<String, dynamic> json) {
    return WinePrefix(
      path: json['path'],
      version: json['version'],
      created: DateTime.parse(json['created']),
      is64Bit: json['is64Bit'] ?? true,  // Default to 64-bit
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'version': version,
    'created': created.toIso8601String(),
    'is64Bit': is64Bit,
  };
} 