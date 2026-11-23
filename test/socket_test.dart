import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/api/socket.dart';

void main() {
  group('parseSocketFrame', () {
    test('reads one message', () {
      final events = parseSocketFrame('{"type":"pong"}');
      expect(events.length, 1);
      expect(events.first.type, 'pong');
      expect(events.first.payload, isNull);
    });

    test('reads several messages in one frame', () {
      final events = parseSocketFrame('{"type":"a","payload":1}\n{"type":"b","payload":{"x":2}}\n');
      expect(events.map((e) => e.type).toList(), ['a', 'b']);
      expect(events.last.payload, {'x': 2});
    });

    test('skips junk', () {
      final events = parseSocketFrame('nonsense\n{"type":5}\n[]\n{"type":"ok"}');
      expect(events.map((e) => e.type).toList(), ['ok']);
    });
  });

  group('socketUri', () {
    test('https becomes wss with the token', () {
      expect(socketUri('https://chat.example.com', 'tok').toString(), 'wss://chat.example.com/ws?token=tok');
    });

    test('http becomes ws, a trailing slash is ignored, the token is escaped', () {
      expect(socketUri('http://10.0.0.5:8080/', 'a b&c').toString(), 'ws://10.0.0.5:8080/ws?token=a+b%26c');
    });
  });
}
