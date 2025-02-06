class AppSettings {
  final String prefixBaseDirectory;
  final bool autoManagePrefixes;
  final bool enableLogging;

  AppSettings({
    required this.prefixBaseDirectory,
    this.autoManagePrefixes = true,
    this.enableLogging = true,
  });

  Map<String, dynamic> toJson() => {
    'prefixBaseDirectory': prefixBaseDirectory,
    'autoManagePrefixes': autoManagePrefixes,
    'enableLogging': enableLogging,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    prefixBaseDirectory: json['prefixBaseDirectory'] ?? '',
    autoManagePrefixes: json['autoManagePrefixes'] ?? true,
    enableLogging: json['enableLogging'] ?? true,
  );

  AppSettings copyWith({
    String? prefixBaseDirectory,
    bool? autoManagePrefixes,
    bool? enableLogging,
  }) => AppSettings(
    prefixBaseDirectory: prefixBaseDirectory ?? this.prefixBaseDirectory,
    autoManagePrefixes: autoManagePrefixes ?? this.autoManagePrefixes,
    enableLogging: enableLogging ?? this.enableLogging,
  );
} 