class Channel {
  const Channel({
    required this.name,
    this.id = '',
    this.description = '',
    this.members = const [],
    this.isPrivate = false,
  });

  final String id;
  final String name;
  final String description;
  final List<String> members;
  final bool isPrivate;

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        members: ((json['members'] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .toList(),
        isPrivate: (json['isPrivate'] as bool?) ?? false,
      );
}
