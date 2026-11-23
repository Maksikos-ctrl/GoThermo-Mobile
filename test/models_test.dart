import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/models/channel.dart';
import 'package:gothermo_mobile/models/message.dart';
import 'package:gothermo_mobile/models/user.dart';

void main() {
  group('Message.fromJson', () {
    test('reads a plain message', () {
      final m = Message.fromJson({
        'id': 'a1',
        'user': 'ann',
        'text': 'hello',
        'channel': 'general',
        'timestamp': '2026-11-12T10:05:00Z',
        'reactions': {
          '👍': ['bob', 'cy'],
          '🔥': <String>[],
        },
      });
      expect(m.id, 'a1');
      expect(m.user, 'ann');
      expect(m.text, 'hello');
      expect(m.timestamp.toUtc(), DateTime.utc(2026, 11, 12, 10, 5));
      expect(m.reactions.keys.toList(), ['👍']);
      expect(m.reactions['👍'], ['bob', 'cy']);
      expect(m.isFile, isFalse);
      expect(m.sendState, SendState.sent);
    });

    test('reads a file message', () {
      final m = Message.fromJson({
        'id': 'f1',
        'user': 'bob',
        'channel': 'general',
        'timestamp': '2026-11-12T10:05:00Z',
        'isFile': true,
        'fileId': 'abc',
        'fileName': 'cat.png',
        'fileSize': 2048,
        'mimeType': 'image/png',
      });
      expect(m.isFile, isTrue);
      expect(m.isImageFile, isTrue);
      expect(m.fileName, 'cat.png');
      expect(m.fileSize, 2048);
    });

    test('survives missing and wrong-typed fields', () {
      final m = Message.fromJson({'id': 5, 'reactions': 'nope', 'timestamp': 'x'});
      expect(m.id, '');
      expect(m.reactions, isEmpty);
      expect(m.timestamp.millisecondsSinceEpoch, 0);
    });

    test('copyWith changes only what it is told to', () {
      final m = Message.fromJson({'id': 'a', 'user': 'ann', 'text': 'x', 'channel': 'c'});
      final n = m.copyWith(text: 'y', sendState: SendState.failed);
      expect(n.text, 'y');
      expect(n.user, 'ann');
      expect(n.id, 'a');
      expect(n.sendState, SendState.failed);
    });
  });

  group('Channel', () {
    test('a direct message shows the other person', () {
      final c = Channel.fromJson({
        'name': 'dm_ann_bob',
        'isPrivate': true,
        'members': ['ann', 'bob'],
      });
      expect(c.isDm, isTrue);
      expect(c.title('ann'), 'bob');
      expect(c.title('bob'), 'ann');
    });

    test('works out the other person from the name when members are missing', () {
      final c = Channel.fromJson({'name': 'dm_ann_bob', 'isPrivate': true});
      expect(c.title('ann'), 'bob');
    });

    test('a normal channel keeps its name', () {
      final c = Channel.fromJson({'name': 'general'});
      expect(c.isDm, isFalse);
      expect(c.title('ann'), 'general');
    });
  });

  group('User', () {
    test('an empty avatar means no avatar', () {
      expect(User.fromJson({'username': 'a', 'avatar': ''}).avatar, isNull);
      expect(User.fromJson({'username': 'a', 'avatar': 'data:image/png;base64,AA'}).avatar, isNotNull);
    });

    test('copyWith can clear the avatar', () {
      const u = User(username: 'a', avatar: 'data:image/png;base64,AA');
      expect(u.copyWith(clearAvatar: true).avatar, isNull);
      expect(u.copyWith(status: 'away').avatar, u.avatar);
    });
  });
}
