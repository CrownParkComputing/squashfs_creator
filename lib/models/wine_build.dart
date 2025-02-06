
enum WineType {
  staging,
  proton,
  vanilla,
}

class WineBuild {
  final String name;
  final String url;
  final WineType type;
  final String version;

  WineBuild({
    required this.name,
    required this.url,
    required this.type,
    required this.version,
  });
} 