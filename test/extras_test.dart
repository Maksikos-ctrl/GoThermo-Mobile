import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/models/extras.dart';
import 'package:gothermo_mobile/models/message.dart';

import 'chat_controller_test.dart' show started;
import 'support/fakes.dart';

void main() {
  group('models', () {
    test('a message keeps its thread summary through the round trip', () {
      final m = Message.fromJson({...msgJson('m1', 'bob', 'hi'), 'replyCount': 3, 'replyUsers': ['ann', 'cy']});
      expect(m.replyCount, 3);
      final back = Message.fromJson(m.toJson());
      expect(back.replyCount, 3);
      expect(back.replyUsers, ['ann', 'cy']);
      expect(Message.fromJson({...msgJson('r1', 'ann', 'x'), 'threadId': 'm1'}).threadId, 'm1');
    });

    test('pins, decisions and threads read the server shape', () {
      final pin = Pin.fromJson({'message': msgJson('m1', 'bob', 'hi'), 'pinnedBy': 'ann', 'pinnedAt': '2026-11-12T10:00:00Z'});
      expect(pin.message.id, 'm1');
      expect(pin.pinnedBy, 'ann');
      final d = Decision.fromJson({'messageId': 'm1', 'channel': 'general', 'kind': 'task', 'done': true, 'at': '2026-11-12T10:00:00Z'});
      expect(d.isTask, isTrue);
      expect(d.copyWith(done: false).done, isFalse);
      final t = ThreadData.fromJson({'parent': msgJson('m1', 'bob', 'hi'), 'replies': [msgJson('r1', 'ann', 'yo')]});
      expect(t.replies.single.text, 'yo');
    });
  });

  group('pins', () {
    test('pin and unpin go to the server and the list follows', () async {
      final (c, server, conn) = await started(prepare: (s) => s.messages['general'] = [msgJson('m1', 'bob', 'one', minute: 1)]);
      await c.open('general');
      await settle();
      final m = c.messagesOf('general').single;
      expect(c.isPinned('general', 'm1'), isFalse);
      expect(await c.pin(m), isNull);
      expect(c.isPinned('general', 'm1'), isTrue);
      expect(c.pinsOf('general').single.message.text, 'one');

      // The server tells everybody when the pins change.
      conn.current.push('pins_changed', {'channel': 'general', 'pins': <Object>[]});
      await settle();
      expect(c.isPinned('general', 'm1'), isFalse);

      server.pinned.clear();
      await c.pin(m);
      expect(await c.unpin(m), isNull);
      expect(c.pinsOf('general'), isEmpty);
      c.dispose();
    });
  });

  group('threads', () {
    test('opening, replying, live replies and deleting', () async {
      final (c, server, conn) = await started(prepare: (s) => s.messages['general'] = [msgJson('m1', 'bob', 'one', minute: 1)]);
      await c.open('general');
      await settle();
      final parent = c.messagesOf('general').single;
      expect(await c.loadThread('general', 'm1'), isNull);
      expect(c.threadOf('general', 'm1')!.replies, isEmpty);

      expect(await c.reply(parent, '  hello  '), isNull);
      expect(c.threadOf('general', 'm1')!.replies.single.text, 'hello');
      expect(server.replies['m1']!.length, 1);

      // The live copy of our own reply must not show twice.
      final mine = server.replies['m1']!.single;
      conn.current.push('thread_reply', {'channel': 'general', 'threadId': 'm1', 'message': mine});
      conn.current.push('thread_reply', {
        'channel': 'general',
        'threadId': 'm1',
        'message': {...msgJson('rx', 'bob', 'from bob', minute: 31), 'threadId': 'm1'},
      });
      await settle();
      expect(c.threadOf('general', 'm1')!.replies.map((r) => r.text).toList(), ['hello', 'from bob']);

      conn.current.push('thread_reply_deleted', {'channel': 'general', 'threadId': 'm1', 'messageId': 'rx'});
      await settle();
      expect(c.threadOf('general', 'm1')!.replies.length, 1);

      expect(await c.deleteReply(c.threadOf('general', 'm1')!.replies.single), isNull);
      expect(c.threadOf('general', 'm1')!.replies, isEmpty);

      expect(await c.reply(parent, '   '), isNull);
      expect(server.replies['m1'], isEmpty);
      c.dispose();
    });

    test('editing and reacting to a reply, here and live', () async {
      final (c, server, conn) = await started(prepare: (s) => s.messages['general'] = [msgJson('m1', 'bob', 'one', minute: 1)]);
      await c.open('general');
      await settle();
      final parent = c.messagesOf('general').single;
      await c.loadThread('general', 'm1');
      await c.reply(parent, 'first draft');
      var mine = c.threadOf('general', 'm1')!.replies.single;

      expect(await c.editReply(mine, '  second draft '), isNull);
      mine = c.threadOf('general', 'm1')!.replies.single;
      expect(mine.text, 'second draft');
      expect(mine.isEdited, isTrue);
      expect(await c.editReply(mine, 'second draft'), isNull); // no change, no call
      expect(await c.editReply(mine, '   '), isNull);
      expect(server.calls.where((x) => x == 'EditReply').length, 1);

      expect(await c.reactToReply(mine, '👍'), isNull);
      mine = c.threadOf('general', 'm1')!.replies.single;
      expect(mine.reactions['👍'], ['ann']);
      expect(server.reactedReplies, ['${mine.id}:👍']);
      expect(await c.reactToReply(mine, '👍'), isNull); // toggles back
      expect(c.threadOf('general', 'm1')!.replies.single.reactions['👍'], isNull);

      // Somebody else edits their reply: the live copy replaces ours in place.
      conn.current.push('thread_reply', {
        'channel': 'general',
        'threadId': 'm1',
        'message': {...msgJson('rx', 'bob', 'hi', minute: 31), 'threadId': 'm1'},
      });
      await settle();
      conn.current.push('thread_reply', {
        'channel': 'general',
        'threadId': 'm1',
        'message': {...msgJson('rx', 'bob', 'hi (edited)', minute: 31), 'threadId': 'm1', 'isEdited': true},
      });
      await settle();
      final texts = c.threadOf('general', 'm1')!.replies.map((r) => r.text).toList();
      expect(texts, ['second draft', 'hi (edited)']);
      c.dispose();
    });

    test('a refused reaction on a reply is put back', () async {
      final (c, server, _) = await started(prepare: (s) => s.messages['general'] = [msgJson('m1', 'bob', 'one', minute: 1)]);
      await c.open('general');
      await settle();
      await c.loadThread('general', 'm1');
      await c.reply(c.messagesOf('general').single, 'mine');
      final mine = c.threadOf('general', 'm1')!.replies.single;
      server.down = true;
      expect(await c.reactToReply(mine, '🎉'), isNotNull);
      expect(c.threadOf('general', 'm1')!.replies.single.reactions['🎉'], isNull);
      c.dispose();
    });

    test('a parent that gained a reply is an update, not an unread message', () async {
      final (c, _, conn) = await started();
      conn.current.push('channel_message', {
        'channel': 'random',
        'message': {...msgJson('m5', 'bob', 'old news', channel: 'random'), 'replyCount': 2},
      });
      await settle();
      expect(c.unread['random'] ?? 0, 0);
      conn.current.push('channel_message', {'channel': 'random', 'message': msgJson('m6', 'bob', 'new', channel: 'random')});
      await settle();
      expect(c.unread['random'], 1);
      c.dispose();
    });
  });

  group('decisions', () {
    test('mark, finish, take back', () async {
      final (c, server, _) = await started(prepare: (s) => s.messages['general'] = [msgJson('m1', 'bob', 'one', minute: 1)]);
      await c.open('general');
      await settle();
      final m = c.messagesOf('general').single;
      expect(await c.markDecision(m, 'task'), isNull);
      final d = c.decisionFor('general', 'm1')!;
      expect(d.isTask, isTrue);
      expect(d.done, isFalse);

      expect(await c.setDecisionDone(d, true), isNull);
      expect(c.decisionFor('general', 'm1')!.done, isTrue);

      server.sendError = 'no';
      expect(await c.setDecisionDone(c.decisionFor('general', 'm1')!, false), 'no');
      expect(c.decisionFor('general', 'm1')!.done, isTrue); // rolled back
      server.sendError = null;

      expect(await c.removeDecision(c.decisionFor('general', 'm1')!), isNull);
      expect(c.decisionsOf('general'), isEmpty);
      c.dispose();
    });
  });

  group('reports', () {
    test('a report goes to the server with its reason', () async {
      final (c, server, _) = await started(prepare: (s) => s.messages['general'] = [msgJson('m1', 'bob', 'buy now', minute: 1)]);
      await c.open('general');
      await settle();
      final m = c.messagesOf('general').single;
      expect(await c.report(m, 'spam'), isNull);
      expect(server.reports, ['m1:spam']);
      server.reportError = 'too many reports, try again later';
      expect(await c.report(m, 'other'), 'too many reports, try again later');
      c.dispose();
    });
  });
}
