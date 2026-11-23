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
  Map<String, List<Map<String, dynamic>>> messages = {};
  String? sendError;
  String? loginError;
  Future<void> Function()? beforeSendReply;
  int _id = 100;

  /// What the last SendMessage asked for.
  String? lastSentText;

  late final MockClient client = MockClient((req) async {
    final method = req.url.pathSegments.last;
    final args = jsonDecode(req.body) as List<dynamic>;
    calls.add(method);
    argsLog.add(args);
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
        if (list.length > limit) list = list.sublist(list.length - limit);
        return reply(list);
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
