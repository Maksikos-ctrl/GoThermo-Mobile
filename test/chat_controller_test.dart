import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/api/gothermo_api.dart';
import 'package:gothermo_mobile/api/rpc_client.dart';
import 'package:gothermo_mobile/models/message.dart';
import 'package:gothermo_mobile/models/user.dart';
import 'package:gothermo_mobile/state/chat_controller.dart';

import 'support/fakes.dart';

Future<(ChatController, FakeServer, FakeConnector)> started({
  Duration pollEvery = const Duration(seconds: 60),
  void Function(FakeServer)? prepare,
  bool refuse = false,
}) async {
  final server = FakeServer();
  prepare?.call(server);
  final connector = FakeConnector()..refuse = refuse;
  final controller = ChatController(
    api: GoThermoApi(RpcClient(baseUrl: 'https://x.io', client: server.client)),
    session: const Session(token: 'tok', user: User(username: 'ann')),
    serverUrl: 'https://x.io',
    connector: connector,
    pollEvery: pollEvery,
    clock: () => DateTime.utc(2026, 11, 12, 12),
  );
  await controller.start();
  await settle();
  return (controller, server, connector);
}

void main() {
  group('toggledReactions', () {
    test('adds, then removes, and never touches the original', () {
      const original = <String, List<String>>{
        '👍': ['bob']
      };
      final added = toggledReactions(original, '👍', 'ann');
      expect(added['👍'], ['bob', 'ann']);
      expect(original['👍'], ['bob']);
      final removed = toggledReactions(added, '👍', 'ann');
      expect(removed['👍'], ['bob']);
      expect(toggledReactions(removed, '👍', 'bob').containsKey('👍'), isFalse);
      expect(toggledReactions(const {}, '🔥', 'ann')['🔥'], ['ann']);
    });
  });

  group('starting', () {
    test('loads the lists and opens the live connection', () async {
      final (c, server, conn) = await started(prepare: (s) => s.unread = {'general': 2});
      expect(c.channels.map((x) => x.name).toList(), ['general', 'random']);
      expect(c.dms.single.title('ann'), 'bob');
      expect(c.people.map((u) => u.username).toList(), ['bob', 'cy']);
      expect(c.unread['general'], 2);
      expect(c.connected, isTrue);
      expect(conn.uris.single.toString(), 'wss://x.io/ws?token=tok');
      expect(server.calls, contains('GifsEnabled'));
      c.dispose();
    });

    test('a list that fails to load shows the error but does not stop the others', () async {
      final (c, _, _) = await started(prepare: (s) => s.channels = []);
      expect(c.channels, isEmpty);
      expect(c.dms, isNotEmpty);
      c.dispose();
    });
  });

  group('opening a channel', () {
    test('loads the newest page oldest-first, marks it read, subscribes', () async {
      final (c, server, conn) = await started(prepare: (s) {
        s.unread = {'general': 3};
        s.messages['general'] = [
          msgJson('m1', 'bob', 'first', minute: 1),
          msgJson('m2', 'ann', 'second', minute: 2),
        ];
      });
      await c.open('general');
      expect(c.messagesOf('general').map((m) => m.text).toList(), ['first', 'second']);
      expect(c.unread['general'], 0);
      await settle();
      expect(server.calls, contains('MarkChannelRead'));
      expect(conn.current.sent.any((f) => f['type'] == 'subscribe_channel' && f['payload'] == 'general'), isTrue);
      expect(c.lastMessage['general']?.text, 'second');
      c.dispose();
    });

    test('older pages come in before the first one and stop when short', () async {
      final (c, server, _) = await started(prepare: (s) {
        s.messages['general'] = [
          for (var i = 0; i < 50; i++) msgJson('m$i', 'bob', 'msg $i', minute: i),
        ];
      });
      await c.open('general');
      expect(c.messagesOf('general').length, pageSize);
      expect(c.feed('general').hasMore, isTrue);
      await c.loadOlder('general');
      expect(c.messagesOf('general').length, 50);
      expect(c.messagesOf('general').first.id, 'm0');
      expect(c.feed('general').hasMore, isFalse);
      // The "before" argument was the oldest message on screen.
      final before = server.argsLog.where((a) => a.length == 4 && a[2] != '').last;
      expect(before[2], 'm10');
      c.dispose();
    });
  });

  group('live messages', () {
    test('a message in another channel counts as unread and raises a notice', () async {
      final (c, _, conn) = await started();
      final notices = <Notice>[];
      c.notices.listen(notices.add);
      conn.current.push('channel_message', {'channel': 'random', 'message': msgJson('n1', 'bob', 'psst', channel: 'random')});
      await settle();
      expect(c.unread['random'], 1);
      expect(notices.single.title, '#random');
      expect(notices.single.message.text, 'psst');
      c.dispose();
    });

    test('a message in the open channel is read at once', () async {
      final (c, server, conn) = await started();
      await c.open('general');
      server.calls.clear();
      conn.current.push('channel_message', {'channel': 'general', 'message': msgJson('n2', 'bob', 'hey')});
      await settle();
      expect(c.messagesOf('general').map((m) => m.text).toList(), ['hey']);
      expect(c.unread['general'], 0);
      expect(server.calls, contains('MarkChannelRead'));
      c.dispose();
    });

    test('a reaction update to a known message is not a new message', () async {
      final (c, _, conn) = await started(prepare: (s) => s.messages['random'] = [msgJson('r1', 'bob', 'hi', channel: 'random')]);
      await c.open('random');
      c.close('random');
      conn.current.push('channel_message', {
        'channel': 'random',
        'message': msgJson('r1', 'bob', 'hi', channel: 'random', reactions: {'👍': ['cy']}),
      });
      await settle();
      expect(c.unread['random'], 0);
      expect(c.messagesOf('random').single.reactions['👍'], ['cy']);
      c.dispose();
    });

    test('a message from myself is never unread', () async {
      final (c, _, conn) = await started();
      conn.current.push('channel_message', {'channel': 'random', 'message': msgJson('s1', 'ann', 'mine', channel: 'random')});
      await settle();
      expect(c.unread['random'] ?? 0, 0);
      c.dispose();
    });

    test('a deleted message disappears', () async {
      final (c, _, conn) = await started(prepare: (s) => s.messages['general'] = [msgJson('d1', 'bob', 'oops')]);
      await c.open('general');
      conn.current.push('message_deleted', {'channel': 'general', 'messageId': 'd1'});
      await settle();
      expect(c.messagesOf('general'), isEmpty);
      c.dispose();
    });

    test('status changes and new pictures reach the people list', () async {
      final (c, _, conn) = await started();
      conn.current.push('status_update', {'username': 'cy', 'status': 'online'});
      conn.current.push('avatar_changed', {'username': 'bob', 'avatar': 'data:image/jpeg;base64,AAAA'});
      await settle();
      expect(c.statusOf('cy'), 'online');
      expect(c.avatarOf('bob'), startsWith('data:image/'));
      conn.current.push('avatar_changed', {'username': 'bob', 'avatar': ''});
      await settle();
      expect(c.avatarOf('bob'), isNull);
      c.dispose();
    });

    test('a channel created or deleted elsewhere shows up here', () async {
      final (c, _, conn) = await started();
      conn.current.push('channel_created', {'id': '7', 'name': 'ideas', 'isPrivate': false});
      await settle();
      expect(c.channels.map((x) => x.name).toList(), ['general', 'ideas', 'random']);
      conn.current.push('channel_deleted', {'channel': 'ideas'});
      await settle();
      expect(c.channels.map((x) => x.name).toList(), ['general', 'random']);
      c.dispose();
    });

    test('someone else\'s private channel is ignored', () async {
      final (c, _, conn) = await started();
      conn.current.push('channel_created', {'name': 'secret', 'isPrivate': true, 'members': ['bob', 'cy']});
      await settle();
      expect(c.channels.any((x) => x.name == 'secret'), isFalse);
      c.dispose();
    });
  });

  group('sending', () {
    test('shows the message at once and keeps one copy when the server echoes it', () async {
      final gate = Completer<void>();
      final (c, server, conn) = await started(prepare: (s) => s.beforeSendReply = () => gate.future);
      await c.open('general');
      final sending = c.send('general', '  hello  ');
      await settle();
      expect(c.messagesOf('general').single.sendState, SendState.sending);
      expect(c.messagesOf('general').single.text, 'hello');
      final bubble = c.messagesOf('general').single.stableKey;

      // The live copy arrives before the RPC answer does.
      conn.current.push('channel_message', {'channel': 'general', 'message': msgJson('srv-100', 'ann', 'hello')});
      await settle();
      expect(c.messagesOf('general').length, 1);
      expect(c.messagesOf('general').single.id, 'srv-100');
      expect(c.messagesOf('general').single.stableKey, bubble);

      gate.complete();
      await sending;
      expect(c.messagesOf('general').length, 1);
      expect(c.messagesOf('general').single.stableKey, bubble);
      expect(c.messagesOf('general').single.sendState, SendState.sent);
      expect(server.lastSentText, 'hello');
      c.dispose();
    });

    test('without the live copy the sent message stays, with the real id', () async {
      final (c, _, _) = await started();
      await c.send('general', 'hi');
      final m = c.messagesOf('general').single;
      expect(m.id, startsWith('srv-'));
      expect(m.stableKey, startsWith('local-'));
      expect(m.sendState, SendState.sent);
      c.dispose();
    });

    test('empty messages are not sent', () async {
      final (c, server, _) = await started();
      await c.send('general', '   ');
      expect(server.calls.contains('SendMessage'), isFalse);
      c.dispose();
    });

    test('a failed send can be retried or dropped', () async {
      final (c, server, _) = await started(prepare: (s) => s.sendError = 'slow down');
      await c.send('general', 'hi');
      final failed = c.messagesOf('general').single;
      expect(failed.sendState, SendState.failed);
      expect(c.error, 'slow down');

      server.sendError = null;
      await c.retry(failed);
      expect(c.messagesOf('general').single.sendState, SendState.sent);

      server.sendError = 'no';
      await c.send('general', 'again');
      final second = c.messagesOf('general').firstWhere((m) => m.sendState == SendState.failed);
      c.discard(second);
      expect(c.messagesOf('general').every((m) => m.sendState == SendState.sent), isTrue);
      c.dispose();
    });
  });

  group('reactions', () {
    test('toggle at once and keep it when the server agrees', () async {
      final (c, server, _) = await started(prepare: (s) => s.messages['general'] = [msgJson('m1', 'bob', 'hi')]);
      await c.open('general');
      final m = c.messagesOf('general').single;
      final err = await c.react(m, '🎉');
      expect(err, isNull);
      expect(c.messagesOf('general').single.reactions['🎉'], ['ann']);
      expect(server.calls, contains('AddReaction'));
      c.dispose();
    });

    test('go back when the server refuses', () async {
      final (c, server, _) = await started(prepare: (s) => s.messages['general'] = [msgJson('m1', 'bob', 'hi')]);
      await c.open('general');
      server.sendError = 'not allowed';
      final err = await c.react(c.messagesOf('general').single, '🎉');
      expect(err, 'not allowed');
      expect(c.messagesOf('general').single.reactions, isEmpty);
      c.dispose();
    });
  });

  group('files', () {
    test('are fetched once and then remembered', () async {
      final (c, server, _) = await started();
      final a = await c.fileBytes('f1');
      final b = await c.fileBytes('f1');
      expect(a.toList(), [0, 1, 2]);
      expect(b.length, 3);
      expect(server.calls.where((m) => m == 'GetFileData').length, 1);
      c.dispose();
    });
  });

  group('direct messages', () {
    test('opening one adds it to the list once', () async {
      final (c, _, _) = await started();
      final ch = await c.directMessageWith('cy');
      expect(ch.title('ann'), 'cy');
      await c.directMessageWith('cy');
      expect(c.dms.where((x) => x.name == 'dm_ann_cy').length, 1);
      c.dispose();
    });
  });

  group('connection', () {
    test('reconnects after a drop and catches up', () async {
      final (c, server, conn) = await started();
      server.calls.clear();
      await conn.current.drop();
      await settle();
      expect(c.connected, isFalse);
      await settle(1300);
      expect(c.connected, isTrue);
      expect(conn.connections.length, 2);
      expect(server.calls, contains('GetChannels'));
      c.dispose();
    });

    test('while the connection is down it polls for unread counts', () async {
      final (c, server, conn) = await started(pollEvery: const Duration(milliseconds: 40), refuse: true);
      expect(c.connected, isFalse);
      server.unread = {'random': 4};
      await settle(150);
      expect(c.unread['random'], 4);
      expect(conn.uris, isNotEmpty);
      c.dispose();
    });
  });
}
