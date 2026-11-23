import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/notifications/notification_center.dart';
import 'package:gothermo_mobile/notifications/notifier.dart';
import 'package:gothermo_mobile/state/call_controller.dart';
import 'package:gothermo_mobile/state/chat_controller.dart';

import 'call_controller_test.dart' show Rig;
import 'chat_controller_test.dart' show started;
import 'support/fakes.dart';

class Setup {
  Setup(this.chat, this.conn, this.notifier, this.center, this.rig);
  final ChatController chat;
  final FakeConnector conn;
  final SilentNotifier notifier;
  final NotificationCenter center;
  final Rig rig;
  CallController get call => rig.controller;

  void dispose() {
    center.dispose();
    chat.dispose();
  }
}

Future<Setup> ready() async {
  final (chat, _, conn) = await started();
  final notifier = SilentNotifier();
  final center = NotificationCenter(notifier);
  final rig = Rig();
  center.attach(chat, rig.controller);
  return Setup(chat, conn, notifier, center, rig);
}

void main() {
  group('words', () {
    test('a message is shortened and tidied', () {
      expect(notificationBody(user: 'bob', text: '  hi\n  there '), 'bob: hi there');
      final long = notificationBody(user: 'bob', text: 'x' * 300);
      expect(long.length < 160, isTrue);
      expect(long.endsWith('…'), isTrue);
      expect(notificationBody(user: 'bob', text: '', isFile: true, fileName: 'a.png'), 'bob sent a.png');
      expect(notificationBody(user: 'bob', text: '', isFile: true), 'bob sent a file');
    });

    test('a channel always gets the same id', () {
      expect(notificationIdFor('general'), notificationIdFor('general'));
      expect(notificationIdFor('general') == notificationIdFor('random'), isFalse);
      expect(notificationIdFor('general') == callNotificationId, isFalse);
    });
  });

  group('notifications', () {
    test('nothing is shown while the app is on screen', () async {
      final t = await ready();
      t.conn.current.push('channel_message', {'channel': 'random', 'message': msgJson('n1', 'bob', 'psst', channel: 'random')});
      await settle();
      expect(t.notifier.shown, isEmpty);
      t.dispose();
    });

    test('a message that arrives in the background is shown, then cleared on return', () async {
      final t = await ready();
      t.center.setBackground(true, t.chat);
      t.conn.current.push('channel_message', {'channel': 'random', 'message': msgJson('n1', 'bob', 'psst', channel: 'random')});
      await settle();
      expect(t.notifier.shown, hasLength(1));
      expect(t.notifier.shown.single.body, 'bob: psst');
      expect(t.notifier.shown.single.payload, 'chan:random');
      expect(t.notifier.shown.single.id, notificationIdFor('random'));
      t.center.setBackground(false, t.chat);
      expect(t.notifier.shown, isEmpty);
      t.dispose();
    });

    test('the open channel counts as unread while in the background', () async {
      final t = await ready();
      await t.chat.open('general');
      await settle();
      t.center.setBackground(true, t.chat);
      t.conn.current.push('channel_message', {'channel': 'general', 'message': msgJson('n2', 'bob', 'hey')});
      await settle();
      expect(t.notifier.shown.single.payload, 'chan:general');
      expect(t.chat.unread['general'], 1);
      t.dispose();
    });

    test('my own messages and thread updates stay quiet', () async {
      final t = await ready();
      t.center.setBackground(true, t.chat);
      t.conn.current.push('channel_message', {'channel': 'random', 'message': msgJson('s1', 'ann', 'mine', channel: 'random')});
      t.conn.current.push('channel_message', {
        'channel': 'random',
        'message': {...msgJson('u1', 'bob', 'old', channel: 'random'), 'replyCount': 2},
      });
      await settle();
      expect(t.notifier.shown, isEmpty);
      t.dispose();
    });

    test('a call that rings in the background is shown and cleared when it stops', () async {
      final t = await ready();
      t.center.setBackground(true, t.chat);
      t.rig.signal('call_offer', {'sdp': {'type': 'offer', 'sdp': 'x'}});
      await settle();
      expect(t.notifier.shown.single.id, callNotificationId);
      expect(t.notifier.shown.single.body, contains('bob'));
      t.rig.signal('call_end', {});
      await settle();
      expect(t.notifier.cancelled, contains(callNotificationId));
      t.dispose();
    });

    test('tapping a notification asks to open that channel', () async {
      final t = await ready();
      await t.center.setUp();
      expect(t.notifier.permissionAsked, 1);
      final opened = <String>[];
      t.center.opens.listen(opened.add);
      t.notifier.tap('chan:random');
      t.notifier.tap('something-else');
      await settle();
      expect(opened, ['random']);
      t.dispose();
    });
  });
}
