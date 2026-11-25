import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/models/channel.dart';
import 'package:gothermo_mobile/util/channel_name.dart';

import 'chat_controller_test.dart' show started;

void main() {
  group('channel names', () {
    test('what is typed becomes a plain name', () {
      expect(channelNameFrom('  #My Team  Room '), 'my-team-room');
      expect(channelNameFrom('x' * 60).length, 40);
    });

    test('bad names say why', () {
      expect(channelNameProblem(''), isNotNull);
      expect(channelNameProblem('dm_ann_bob'), isNotNull);
      expect(channelNameProblem('what?'), isNotNull);
      expect(channelNameProblem('ok-name_1'), isNull);
    });
  });

  group('channel rules', () {
    test('only the maker deletes, and never a built-in channel', () {
      const mine = Channel(id: '1', name: 'plans', createdBy: 'ann');
      expect(mine.canDelete('ann'), isTrue);
      expect(mine.canDelete('bob'), isFalse);
      expect(const Channel(id: '2', name: 'general', createdBy: 'ann').canDelete('ann'), isFalse);
    });

    test('leaving is for private channels with somebody else in them', () {
      const secret = Channel(id: '1', name: 's', isPrivate: true, members: ['ann', 'bob']);
      expect(secret.canLeave('ann'), isTrue);
      expect(const Channel(id: '2', name: 's', isPrivate: true, members: ['ann']).canLeave('ann'), isFalse);
      expect(const Channel(id: '3', name: 'pub').canLeave('ann'), isFalse);
      expect(const Channel(id: '4', name: 'dm_ann_bob', isPrivate: true, members: ['ann', 'bob']).canLeave('ann'), isFalse);
    });

    test('createdBy survives the round trip', () {
      final c = Channel.fromJson(const Channel(id: '1', name: 'x', createdBy: 'ann').toJson());
      expect(c.createdBy, 'ann');
    });
  });

  group('controller', () {
    test('a new channel appears in the list', () async {
      final (c, server, _) = await started();
      final r = await c.createChannel(name: 'plans', description: ' ideas ');
      expect(r.error, isNull);
      expect(r.channel!.createdBy, 'ann');
      expect(c.channels.map((x) => x.name), contains('plans'));
      expect(server.channelCalls, ['create:plans']);
      c.dispose();
    });

    test('a private channel is made with the people picked', () async {
      final (c, server, _) = await started();
      final r = await c.createChannel(name: 'secret', isPrivate: true, members: ['bob']);
      expect(r.channel!.members, ['ann', 'bob']);
      expect(server.channelCalls, ['create:secret']);
      c.dispose();
    });

    test('a refused name comes back as an error', () async {
      final (c, _, _) = await started();
      final r = await c.createChannel(name: 'general');
      expect(r.channel, isNull);
      expect(r.error, 'channel already exists');
      c.dispose();
    });

    test('leaving and deleting take the channel off the list', () async {
      final (c, server, _) = await started();
      await c.createChannel(name: 'a');
      await c.createChannel(name: 'b');
      expect(await c.deleteChannel('a'), isNull);
      expect(await c.leaveChannel('b'), isNull);
      expect(c.channels.map((x) => x.name).toList(), ['general', 'random']);
      expect(server.channelCalls, ['create:a', 'create:b', 'delete:a', 'leave:b']);
      c.dispose();
    });
  });
}
