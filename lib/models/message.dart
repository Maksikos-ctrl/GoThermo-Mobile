import 'json.dart';

/// Where a message is on its way to the server. Only messages this phone sent
/// are ever anything but [sent].
enum SendState { sent, sending, failed }

class Message {
  const Message({
    required this.id,
    required this.user,
    required this.text,
    required this.channel,
    required this.timestamp,
    this.reactions = const {},
    this.isPost = false,
    this.isEdited = false,
    this.isFile = false,
    this.fileId = '',
    this.fileName = '',
    this.fileSize = 0,
    this.mimeType = '',
    this.isCall = false,
    this.callStatus = '',
    this.callDuration = 0,
    this.sendState = SendState.sent,
    this.clientId = '',
  });

  final String id;
  final String user;
  final String text;
  final String channel;
  final DateTime timestamp;

  /// emoji -> the people who used it
  final Map<String, List<String>> reactions;
  final bool isPost;
  final bool isEdited;
  final bool isFile;
  final String fileId;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final bool isCall;
  final String callStatus;
  final int callDuration;
  final SendState sendState;

  /// Set on messages this phone sent: stays the same when the placeholder is
  /// swapped for the server's copy, so the screen can tell it is the same bubble.
  final String clientId;

  /// Identifies the bubble on screen across the placeholder -> real swap.
  String get stableKey => clientId.isNotEmpty ? clientId : id;

  bool get isImageFile => isFile && mimeType.startsWith('image/');

  factory Message.fromJson(Map<String, dynamic> j) {
    final reactions = <String, List<String>>{};
    final rawReactions = j['reactions'];
    if (rawReactions is Map) {
      rawReactions.forEach((key, value) {
        if (key is String && value is List) {
          final names = value.whereType<String>().toList();
          if (names.isNotEmpty) reactions[key] = names;
        }
      });
    }
    return Message(
      id: str(j['id']),
      user: str(j['user']),
      text: str(j['text']),
      channel: str(j['channel']),
      timestamp: DateTime.tryParse(str(j['timestamp']))?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reactions: reactions,
      isPost: flag(j['isPost']),
      isEdited: flag(j['isEdited']),
      isFile: flag(j['isFile']),
      fileId: str(j['fileId']),
      fileName: str(j['fileName']),
      fileSize: whole(j['fileSize']),
      mimeType: str(j['mimeType']),
      isCall: flag(j['isCall']),
      callStatus: str(j['callStatus']),
      callDuration: whole(j['callDuration']),
    );
  }

  Message copyWith({
    String? id,
    String? text,
    Map<String, List<String>>? reactions,
    bool? isEdited,
    SendState? sendState,
    String? clientId,
  }) =>
      Message(
        id: id ?? this.id,
        user: user,
        text: text ?? this.text,
        channel: channel,
        timestamp: timestamp,
        reactions: reactions ?? this.reactions,
        isPost: isPost,
        isEdited: isEdited ?? this.isEdited,
        isFile: isFile,
        fileId: fileId,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
        isCall: isCall,
        callStatus: callStatus,
        callDuration: callDuration,
        sendState: sendState ?? this.sendState,
        clientId: clientId ?? this.clientId,
      );
}
