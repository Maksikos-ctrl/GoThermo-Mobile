import 'json.dart';

class Channel {
  const Channel({
    required this.name,
    this.id = '',
    this.description = '',
    this.members = const [],
    this.isPrivate = false,
    this.createdBy = '',
  });

  final String id;
  final String name;
  final String description;
  final List<String> members;
  final bool isPrivate;
  final String createdBy;

  /// Direct and group messages are private channels named `dm_<a>_<b>`.
  bool get isDm => isPrivate && name.startsWith('dm_');

  /// The other people in a direct message (everyone but [me]).
  List<String> others(String me) {
    final fromMembers = members.where((m) => m != me).toList();
    if (fromMembers.isNotEmpty) return fromMembers;
    return name.split('_').skip(1).where((p) => p.isNotEmpty && p != me).toList();
  }

  /// The channels every server starts with; they cannot be deleted.
  static const systemNames = {'general', 'random', 'dev-team'};

  /// Only the person who made a channel can delete it (not the built-in ones).
  bool canDelete(String me) => !isDm && !systemNames.contains(name) && createdBy == me;

  /// A private channel (not a direct message) with someone else still in it.
  bool canLeave(String me) => isPrivate && !isDm && members.contains(me) && members.length > 1;

  /// What to show as the title: `#general` style names stay as they are, a
  /// direct message shows who it is with.
  String title(String me) => isDm ? others(me).join(', ') : name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'members': members,
        'isPrivate': isPrivate,
        'createdBy': createdBy,
      };

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: str(json['id']),
        name: str(json['name']),
        description: str(json['description']),
        members: ((json['members'] as List<dynamic>?) ?? const []).whereType<String>().toList(),
        isPrivate: flag(json['isPrivate']),
        createdBy: str(json['createdBy']),
      );
}
