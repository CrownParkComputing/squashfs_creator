class WinePrefix {
  final String path;
  final String version;
  final String name;
  final DateTime created;
  final bool is64Bit;

  WinePrefix({
    required this.path,
    required this.version,
    required this.name,
    required this.created,
    required this.is64Bit,
  });

  bool get isProton => version.startsWith('GE-Proton');

  String get protonDir => isProton ? path.replaceAll('/pfx', '') : path;

  String get winePath {
    if (isProton) {
      return path.replaceAll('/pfx', '/$version/proton');
    } else {
      final prefixParent = path.substring(0, path.lastIndexOf('/pfx'));
      return '$prefixParent/bin/wine${is64Bit ? '64' : ''}';
    }
  }

  String get protonPath {
    if (!isProton) throw Exception('Not a Proton prefix');
    return path.replaceAll('/pfx', '/$version/proton');
  }

  factory WinePrefix.fromJson(Map<String, dynamic> json) {
    return WinePrefix(
      path: json['path'],
      version: json['version'],
      name: json['name'],
      created: DateTime.parse(json['created']),
      is64Bit: json['is64Bit'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'version': version,
    'name': name,
    'created': created.toIso8601String(),
    'is64Bit': is64Bit,
  };
} 