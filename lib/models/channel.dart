import 'json.dart';

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

  /// Direct and group messages are private channels named `dm_<a>_<b>`.
  bool get isDm => isPrivate && name.startsWith('dm_');

  /// The other people in a direct message (everyone but [me]).
  List<String> others(String me) {
    final fromMembers = members.where((m) => m != me).toList();
    if (fromMembers.isNotEmpty) return fromMembers;
    return name.split('_').skip(1).where((p) => p.isNotEmpty && p != me).toList();
  }

  /// What to show as the title: `#general` style names stay as they are, a
  /// direct message shows who it is with.
  String title(String me) => isDm ? others(me).join(', ') : name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'members': members,
        'isPrivate': isPrivate,
      };

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: str(json['id']),
        name: str(json['name']),
        description: str(json['description']),
        members: ((json['members'] as List<dynamic>?) ?? const []).whereType<String>().toList(),
        isPrivate: flag(json['isPrivate']),
      );
}
