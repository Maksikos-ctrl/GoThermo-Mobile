import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/api/gothermo_api.dart';
import 'package:gothermo_mobile/api/rpc_client.dart';
import 'package:gothermo_mobile/cache/local_cache.dart';
import 'package:gothermo_mobile/models/channel.dart';
import 'package:gothermo_mobile/models/message.dart';
import 'package:gothermo_mobile/models/user.dart';
import 'package:gothermo_mobile/state/chat_controller.dart';

import 'support/fakes.dart';

class BrokenCache implements LocalCache {
  @override
  Future<Object?> readValue(String key) => throw StateError('disk');
  @override
  Future<void> writeValue(String key, Object? json) => throw StateError('disk');
  @override
  Future<List<Map<String, dynamic>>> readMessages(String channel, {int limit = 200}) => throw StateError('disk');
  @override
  Future<void> putMessages(String channel, List<CachedMessage> items) => throw StateError('disk');
  @override
  Future<void> deleteMessage(String channel, String id) => throw StateError('disk');
  @override
  Future<void> clear() => throw StateError('disk');
}

ChatController build(FakeServer server, FakeConnector connector, LocalCache? cache, {bool openFails = false}) {
  return ChatController(
    api: GoThermoApi(RpcClient(baseUrl: 'https://x.io', client: server.client)),
    session: const Session(token: 'tok', user: User(username: 'ann')),
    serverUrl: 'https://x.io',
    connector: connector,
    pollEvery: const Duration(seconds: 60),
    clock: () => DateTime.utc(2026, 11, 12, 12),
    openCache: cache == null
        ? null
        : () async {
            if (openFails) throw StateError('cannot open');
            return cache;
          },
  );
}

void main() {
  group('models survive the round trip', () {
    test('message', () {
      final m = Message.fromJson({
        ...msgJson('m1', 'bob', 'hi', minute: 5, reactions: {'👍': ['ann']}),
        'isFile': true,
        'fileId': 'f1',
        'fileName': 'a.png',
        'fileSize': 12,
        'mimeType': 'image/png',
        'isEdited': true,
      });
      final back = Message.fromJson(m.toJson());
      expect(back.id, 'm1');
      expect(back.timestamp.toUtc(), m.timestamp.toUtc());
      expect(back.reactions['👍'], ['ann']);
      expect(back.isImageFile, isTrue);
      expect(back.isEdited, isTrue);
      expect(back.fileName, 'a.png');
    });

    test('channel and user', () {
      final c = Channel.fromJson({'id': '3', 'name': 'dm_ann_bob', 'isPrivate': true, 'members': ['ann', 'bob']});
      final c2 = Channel.fromJson(c.toJson());
      expect(c2.isDm, isTrue);
      expect(c2.members, ['ann', 'bob']);
      final u = User.fromJson({'username': 'bob', 'status': 'away', 'avatar': 'data:x', 'isAdmin': true});
      final u2 = User.fromJson(u.toJson());
      expect(u2.avatar, 'data:x');
      expect(u2.isAdmin, isTrue);
      expect(User.fromJson(const User(username: 'z').toJson()).avatar, isNull);
    });
  });

  group('MemoryCache', () {
    test('keeps the newest messages in order and replaces by id', () async {
      final c = MemoryCache();
      await c.putMessages('g', [
        for (var i = 0; i < cacheKeepPerChannel + 5; i++) CachedMessage('m$i', i, {'id': 'm$i', 'n': i}),
      ]);
      final all = await c.readMessages('g');
      expect(all.length, cacheKeepPerChannel);
      expect(all.first['n'], 5);
      expect(all.last['n'], cacheKeepPerChannel + 4);
      await c.putMessages('g', [CachedMessage('m10', 10, {'id': 'm10', 'n': 'edited'})]);
      expect((await c.readMessages('g')).where((m) => m['id'] == 'm10').single['n'], 'edited');
      expect((await c.readMessages('g', limit: 2)).map((m) => m['id']).toList(), ['m${cacheKeepPerChannel + 3}', 'm${cacheKeepPerChannel + 4}']);
      await c.deleteMessage('g', 'm10');
      expect((await c.readMessages('g')).any((m) => m['id'] == 'm10'), isFalse);
      await c.clear();
      expect(await c.readMessages('g'), isEmpty);
    });
  });

  group('offline copy in the controller', () {
    test('what was seen last time shows at once, even with no server', () async {
      final cache = MemoryCache();
      final server = FakeServer()
        ..messages['general'] = [msgJson('m1', 'bob', 'first', minute: 1), msgJson('m2', 'cy', 'second', minute: 2)];
      final first = build(server, FakeConnector(), cache);
      await first.start();
      await settle();
      await first.open('general');
      await settle();
      expect(first.messagesOf('general').length, 2);
      first.dispose();

      // A new run with the server unreachable.
      final dead = FakeServer()..down = true;
      final offline = build(dead, FakeConnector()..refuse = true, cache);
      await offline.start();
      await settle();
      expect(offline.channels.map((c) => c.name).toList(), ['general', 'random']);
      expect(offline.dms.single.title('ann'), 'bob');
      expect(offline.people.map((u) => u.username), contains('bob'));
      expect(offline.lastMessage['general']?.text, 'second');
      await offline.open('general');
      await settle();
      expect(offline.messagesOf('general').map((m) => m.text).toList(), ['first', 'second']);
      offline.dispose();
    });

    test('new, edited and deleted messages are kept in step', () async {
      final cache = MemoryCache();
      final server = FakeServer()..messages['general'] = [msgJson('m1', 'bob', 'one', minute: 1)];
      final conn = FakeConnector();
      final c = build(server, conn, cache);
      await c.start();
      await settle();
      await c.open('general');
      await settle();
      conn.current.push('channel_message', {'channel': 'general', 'message': msgJson('m2', 'bob', 'two', minute: 2)});
      await settle();
      expect((await cache.readMessages('general')).map((m) => m['id']).toList(), ['m1', 'm2']);

      final m2 = c.messagesOf('general').last;
      await c.react(m2, '👍');
      await settle();
      final saved = (await cache.readMessages('general')).last;
      expect((saved['reactions'] as Map)['👍'], ['ann']);

      conn.current.push('message_deleted', {'channel': 'general', 'messageId': 'm1'});
      await settle();
      expect((await cache.readMessages('general')).map((m) => m['id']).toList(), ['m2']);
      c.dispose();
    });

    test('a message deleted while the phone was away disappears after the refresh', () async {
      final cache = MemoryCache();
      await cache.putMessages('general', [
        CachedMessage('m1', DateTime.utc(2026, 11, 12, 10, 1).millisecondsSinceEpoch, msgJson('m1', 'bob', 'old', minute: 1)),
        CachedMessage('m2', DateTime.utc(2026, 11, 12, 10, 2).millisecondsSinceEpoch, msgJson('m2', 'bob', 'gone', minute: 2)),
      ]);
      await cache.writeValue('channels', [
        {'id': '1', 'name': 'general', 'isPrivate': false}
      ]);
      final server = FakeServer()..messages['general'] = [msgJson('m1', 'bob', 'old', minute: 1)];
      final c = build(server, FakeConnector(), cache);
      await c.start();
      await settle();
      await c.open('general');
      await settle();
      expect(c.messagesOf('general').map((m) => m.id).toList(), ['m1']);
      expect((await cache.readMessages('general')).map((m) => m['id']).toList(), ['m1']);
      c.dispose();
    });

    test('signing out wipes it', () async {
      final cache = MemoryCache();
      final server = FakeServer()..messages['general'] = [msgJson('m1', 'bob', 'one', minute: 1)];
      final c = build(server, FakeConnector(), cache);
      await c.start();
      await settle();
      await c.open('general');
      await settle();
      expect(await cache.readMessages('general'), isNotEmpty);
      await c.wipeCache();
      expect(await cache.readMessages('general'), isEmpty);
      expect(await cache.readValue('channels'), isNull);
      c.dispose();
    });

    test('a broken or unopenable cache changes nothing for the app', () async {
      for (final failing in [true, false]) {
        final server = FakeServer()..messages['general'] = [msgJson('m1', 'bob', 'one', minute: 1)];
        final c = failing
            ? build(server, FakeConnector(), BrokenCache())
            : build(server, FakeConnector(), MemoryCache(), openFails: true);
        await c.start();
        await settle();
        await c.open('general');
        await settle();
        expect(c.channels, isNotEmpty);
        expect(c.messagesOf('general').single.text, 'one');
        c.dispose();
      }
    });
  });

  group('writing with no connection', () {
    test('the message waits, and goes out when the server is back', () async {
      final server = FakeServer();
      final c = build(server, FakeConnector(), MemoryCache());
      await c.start();
      await settle();
      server.down = true;
      await c.send('general', 'first');
      await c.send('general', 'second');
      expect(c.error, isNull);
      expect(c.messagesOf('general').every((m) => m.sendState == SendState.sending), isTrue);
      expect(c.waitingCount, 2);

      server.down = false;
      await c.flushOutbox();
      await settle();
      final sent = c.messagesOf('general');
      expect(sent.map((m) => m.text).toList(), ['first', 'second']);
      expect(sent.every((m) => m.sendState == SendState.sent), isTrue);
      expect(c.waitingCount, 0);
      c.dispose();
    });

    test('still offline: flushing stops at the first message and keeps the order', () async {
      final server = FakeServer();
      final c = build(server, FakeConnector(), MemoryCache());
      await c.start();
      await settle();
      server.down = true;
      await c.send('general', 'a');
      await c.send('general', 'b');
      final before = server.calls.where((x) => x == 'SendMessage').length;
      await c.flushOutbox();
      expect(c.waitingCount, 2);
      expect(server.calls.where((x) => x == 'SendMessage').length, before + 1);
      c.dispose();
    });

    test('a message written offline survives closing the app', () async {
      final cache = MemoryCache();
      final server = FakeServer();
      final first = build(server, FakeConnector(), cache);
      await first.start();
      await settle();
      server.down = true;
      await first.send('general', 'for later');
      first.dispose();

      final back = FakeServer();
      final c = build(back, FakeConnector(), cache);
      await c.start();
      await settle();
      await settle(50);
      final m = c.messagesOf('general').single;
      expect(m.text, 'for later');
      expect(m.sendState, SendState.sent);
      expect(back.lastSentText, 'for later');
      c.dispose();
    });

    test('an answer from the server that says no is a failure, not a wait', () async {
      final server = FakeServer()..sendError = 'slow down';
      final c = build(server, FakeConnector(), MemoryCache());
      await c.start();
      await settle();
      await c.send('general', 'hi');
      expect(c.messagesOf('general').single.sendState, SendState.failed);
      expect(c.waitingCount, 0);
      c.dispose();
    });
  });
}
