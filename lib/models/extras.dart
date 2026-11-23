import 'json.dart';
import 'message.dart';

/// A pinned message with who pinned it.
class Pin {
  const Pin({required this.message, this.pinnedBy = '', required this.pinnedAt});

  final Message message;
  final String pinnedBy;
  final DateTime pinnedAt;

  factory Pin.fromJson(Map<String, dynamic> j) {
    final raw = j['message'];
    return Pin(
      message: Message.fromJson(raw is Map<String, dynamic> ? raw : const {}),
      pinnedBy: str(j['pinnedBy']),
      pinnedAt: DateTime.tryParse(str(j['pinnedAt']))?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// A message marked as a decision or a task.
class Decision {
  const Decision({
    required this.messageId,
    required this.channel,
    required this.kind,
    this.text = '',
    this.author = '',
    this.markedBy = '',
    this.assignee = '',
    this.done = false,
    this.doneBy = '',
    required this.at,
  });

  final String messageId;
  final String channel;

  /// `decision` or `task`.
  final String kind;
  final String text;
  final String author;
  final String markedBy;
  final String assignee;
  final bool done;
  final String doneBy;
  final DateTime at;

  bool get isTask => kind == 'task';

  Decision copyWith({bool? done, String? doneBy}) => Decision(
        messageId: messageId,
        channel: channel,
        kind: kind,
        text: text,
        author: author,
        markedBy: markedBy,
        assignee: assignee,
        done: done ?? this.done,
        doneBy: doneBy ?? this.doneBy,
        at: at,
      );

  factory Decision.fromJson(Map<String, dynamic> j) => Decision(
        messageId: str(j['messageId']),
        channel: str(j['channel']),
        kind: str(j['kind']),
        text: str(j['text']),
        author: str(j['author']),
        markedBy: str(j['markedBy']),
        assignee: str(j['assignee']),
        done: flag(j['done']),
        doneBy: str(j['doneBy']),
        at: DateTime.tryParse(str(j['at']))?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// The replies under one message.
class ThreadData {
  const ThreadData({required this.parent, this.replies = const []});

  final Message parent;
  final List<Message> replies;

  factory ThreadData.fromJson(Map<String, dynamic> j) {
    final parent = j['parent'];
    final replies = j['replies'];
    return ThreadData(
      parent: Message.fromJson(parent is Map<String, dynamic> ? parent : const {}),
      replies: replies is List ? replies.whereType<Map<String, dynamic>>().map(Message.fromJson).toList() : const [],
    );
  }
}
