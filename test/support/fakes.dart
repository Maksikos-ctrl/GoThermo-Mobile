import 'dart:async';
import 'dart:convert';

import 'package:gothermo_mobile/api/socket.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response reply(Object? result) => http.Response(jsonEncode({'result': result}), 200);
http.Response failure(String message) => http.Response(jsonEncode({'error': message}), 200);

Map<String, dynamic> msgJson(
  String id,
  String user,
  String text, {
  String channel = 'general',
  int minute = 0,
  Map<String, List<String>> reactions = const {},
}) =>
    {
      'id': id,
      'user': user,
      'text': text,
      'channel': channel,
      'timestamp': DateTime.utc(2026, 11, 12, 10, minute).toIso8601String(),
      'reactions': reactions,
    };

/// A tiny GoThermo server in memory. [calls] records every method asked.
class FakeServer {
  final List<String> calls = [];
  final List<List<dynamic>> argsLog = [];

  List<Map<String, dynamic>> channels = [
    {'id': '1', 'name': 'general', 'description': 'General discussions', 'isPrivate': false},
    {'id': '2', 'name': 'random', 'description': '', 'isPrivate': false},
  ];
  List<Map<String, dynamic>> dms = [
    {
      'id': '3',
      'name': 'dm_ann_bob',
      'isPrivate': true,
      'members': ['ann', 'bob'],
    },
  ];
  List<Map<String, dynamic>> users = [
    {'username': 'ann', 'status': 'online'},
    {'username': 'bob', 'status': 'away'},
    {'username': 'cy', 'status': 'offline'},
  ];
  Map<String, int> unread = {};
  final Set<String> pinned = {};
  final Map<String, List<Map<String, dynamic>>> replies = {};
  final List<Map<String, dynamic>> decisions = [];
  Map<String, List<Map<String, dynamic>>> messages = {};
  String? sendError;

  /// True = the network is gone: every call fails to reach the server.
  bool down = false;
  String? loginError;
  Future<void> Function()? beforeSendReply;
  int _id = 100;

  /// Replies reacted to (`replyId:emoji`), reports received (`messageId:reason`).
  final List<String> reactedReplies = [];
  final List<String> reports = [];
  String? reportError;

  /// Push addresses the server was given, and whether it refuses them.
  final List<String> devices = [];
  bool deviceError = false;

  /// What the last SendMessage asked for.
  String? lastSentText;

  late final MockClient client = MockClient((req) async {
    final method = req.url.pathSegments.last;
    final args = jsonDecode(req.body) as List<dynamic>;
    calls.add(method);
    argsLog.add(args);
    if (down) throw Exception('offline');
    switch (method) {
      case 'LoginWithGoogleToken':
        if (loginError != null) return failure(loginError!);
        return reply({'username': 'ann', 'email': 'ann@x.io', 'token': 'tok', 'status': 'online'});
      case 'Login':
        if (loginError != null) return failure(loginError!);
        return reply({'username': 'ann', 'email': 'ann@x.io', 'token': 'tok', 'status': 'online'});
      case 'CheckAuth':
        return reply(args[0] == 'saved' || args[0] == 'tok' ? jsonEncode({'username': 'ann'}) : '');
      case 'GetChannels':
        return reply(channels);
      case 'GetDMChannels':
        return reply(dms);
      case 'GetUsers':
        return reply(users);
      case 'GetUnreadCounts':
        return reply(unread);
      case 'GetIceServers':
        return reply('[{"urls":["stun:stun.example.org"]}]');
      case 'LogCall':
        return reply(null);
      case 'RegisterDevice':
        if (deviceError) return failure('unknown method');
        devices.add(args[2] as String);
        return reply(null);
      case 'UnregisterDevice':
        devices.remove(args[2] as String);
        return reply(null);
      case 'GifsEnabled':
        return reply(false);
      case 'MarkChannelRead':
        return reply(null);
      case 'GetMessagesPage':
        final channel = args[1] as String;
        final before = args[2] as String;
        final limit = args[3] as int;
        var list = List.of(messages[channel] ?? const <Map<String, dynamic>>[]);
        if (before.isNotEmpty) {
          final i = list.indexWhere((m) => m['id'] == before);
          list = i < 0 ? const [] : list.sublist(0, i);
        }
        final more = list.length > limit;
        if (more) list = list.sublist(list.length - limit);
        // Same shape as the real server.
        return reply({'messages': list, 'hasMore': more});
      case 'SendMessage':
        if (sendError != null) return failure(sendError!);
        lastSentText = args[2] as String;
        final id = 'srv-${_id++}';
        final wait = beforeSendReply;
        if (wait != null) await wait();
        return reply(id);
      case 'AddReaction':
        if (sendError != null) return failure(sendError!);
        return reply(null);
      case 'GetFileData':
        return reply('data:image/png;base64,AAEC');
      case 'DeleteMessage':
        return reply(null);
      case 'GetOrCreateDMChannel':
        return reply({
          'id': '9',
          'name': 'dm_ann_cy',
          'isPrivate': true,
          'members': ['ann', 'cy'],
        });
      case 'Logout':
        return reply(true);
      case 'PinMessage':
        pinned.add(args[2] as String);
        return reply(null);
      case 'UnpinMessage':
        pinned.remove(args[2] as String);
        return reply(null);
      case 'GetPinnedMessages':
        final ch = args[1] as String;
        return reply([
          for (final id in pinned)
            for (final m in messages[ch] ?? const <Map<String, dynamic>>[])
              if (m['id'] == id) {'message': m, 'pinnedBy': 'bob', 'pinnedAt': '2026-11-12T10:30:00Z'},
        ]);
      case 'GetThread':
        final ch = args[1] as String;
        final parent = (messages[ch] ?? const <Map<String, dynamic>>[]).firstWhere((m) => m['id'] == args[2]);
        return reply({'parent': parent, 'replies': replies[args[2]] ?? const []});
      case 'SendReply':
        if (sendError != null) return failure(sendError!);
        final r = {
          ...msgJson('r${_id++}', args[1] as String, args[4] as String, channel: args[2] as String, minute: 30),
          'threadId': args[3],
        };
        (replies[args[3] as String] ??= []).add(r);
        return reply(r);
      case 'EditReply':
        final list = replies[args[2] as String] ?? [];
        final i = list.indexWhere((r) => r['id'] == args[3]);
        if (i < 0) return failure('message not found');
        list[i] = {...list[i], 'text': args[5], 'isEdited': true};
        return reply(list[i]);
      case 'AddReplyReaction':
        reactedReplies.add('${args[3]}:${args[4]}');
        return reply(null);
      case 'ReportMessage':
        if (reportError != null) return failure(reportError!);
        reports.add('${args[3]}:${args[4]}');
        return reply(null);
      case 'DeleteReply':
        replies[args[2] as String]?.removeWhere((r) => r['id'] == args[3]);
        return reply(null);
      case 'GetDecisions':
        return reply(decisions);
      case 'MarkDecision':
        decisions.add({
          'messageId': args[3],
          'channel': args[2],
          'kind': args[4],
          'text': 'marked',
          'author': 'bob',
          'markedBy': args[1],
          'done': false,
          'at': '2026-11-12T11:00:00Z',
        });
        return reply(null);
      case 'SetDecisionDone':
        if (sendError != null) return failure(sendError!);
        for (final d in decisions) {
          if (d['messageId'] == args[3]) d['done'] = args[4];
        }
        return reply(null);
      case 'RemoveDecision':
        decisions.removeWhere((d) => d['messageId'] == args[3]);
        return reply(null);
    }
    return http.Response(jsonEncode({'error': 'unknown method $method'}), 404);
  });
}

class FakeConnection implements SocketConnection {
  final StreamController<String> _frames = StreamController<String>();
  final List<Map<String, dynamic>> sent = [];
  bool closed = false;

  @override
  Stream<String> get frames => _frames.stream;

  @override
  void send(String text) => sent.add(jsonDecode(text) as Map<String, dynamic>);

  @override
  Future<void> close() async {
    closed = true;
    if (!_frames.isClosed) await _frames.close();
  }

  /// The server pushes one event.
  void push(String type, Object? payload) => _frames.add(jsonEncode({'type': type, 'payload': payload}));

  /// The connection drops.
  Future<void> drop() => _frames.close();
}

class FakeConnector implements SocketConnector {
  final List<FakeConnection> connections = [];
  final List<Uri> uris = [];
  bool refuse = false;

  FakeConnection get current => connections.last;

  @override
  Future<SocketConnection> connect(Uri uri) async {
    uris.add(uri);
    if (refuse) throw Exception('server is down');
    final c = FakeConnection();
    connections.add(c);
    return c;
  }
}

/// Lets queued work (timers, microtasks) run.
Future<void> settle([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));
