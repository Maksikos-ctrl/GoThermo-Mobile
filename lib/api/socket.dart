import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// One thing the server pushed: `{"type": ..., "payload": ...}`.
class SocketEvent {
  const SocketEvent(this.type, this.payload);

  final String type;
  final dynamic payload;
}

/// The server may put several JSON messages in one frame, separated by
/// newlines. Anything that is not a valid message is skipped.
List<SocketEvent> parseSocketFrame(String frame) {
  final out = <SocketEvent>[];
  for (final line in frame.split('\n')) {
    final text = line.trim();
    if (text.isEmpty) continue;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic> && decoded['type'] is String) {
        out.add(SocketEvent(decoded['type'] as String, decoded['payload']));
      }
    } on FormatException {
      continue;
    }
  }
  return out;
}

/// `https://chat.example.com` -> `wss://chat.example.com/ws?token=...`
Uri socketUri(String baseUrl, String token) {
  var base = baseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  final ws = base.startsWith('https://')
      ? 'wss://${base.substring(8)}'
      : base.startsWith('http://')
          ? 'ws://${base.substring(7)}'
          : base;
  return Uri.parse('$ws/ws').replace(queryParameters: {'token': token});
}

/// An open connection to the server's live channel.
abstract class SocketConnection {
  Stream<String> get frames;
  void send(String text);
  Future<void> close();
}

/// Opens [SocketConnection]s. A seam so tests can use a fake.
abstract class SocketConnector {
  Future<SocketConnection> connect(Uri uri);
}

class WebSocketConnector implements SocketConnector {
  const WebSocketConnector();

  @override
  Future<SocketConnection> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready.timeout(const Duration(seconds: 12));
    return _WebSocketConnection(channel);
  }
}

class _WebSocketConnection implements SocketConnection {
  _WebSocketConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<String> get frames =>
      _channel.stream.map((event) => event is String ? event : utf8.decode(event as List<int>));

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close() async {
    try {
      await _channel.sink.close();
    } on Object {
      // already closed
    }
  }
}
