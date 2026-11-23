import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/api/gothermo_api.dart';
import 'package:gothermo_mobile/api/rpc_client.dart';
import 'package:gothermo_mobile/notifications/push_registrar.dart';
import 'package:gothermo_mobile/notifications/push_service.dart';

import 'support/fakes.dart';

void main() {
  (GoThermoApi, FakeServer) rig() {
    final server = FakeServer();
    return (GoThermoApi(RpcClient(baseUrl: 'https://x.io', client: server.client)), server);
  }

  group('push registration', () {
    test('gives the phone to the server, and follows a new token', () async {
      final (api, server) = rig();
      final push = SilentPush();
      final r = PushRegistrar(push);
      await r.register(api, 'tok', 'ann');
      expect(server.devices, ['silent-device-token-0123456789']);
      expect(r.registered, 'silent-device-token-0123456789');
      push.refreshTo('second-token-0123456789abcdef');
      await settle();
      expect(server.devices.contains('second-token-0123456789abcdef'), isTrue);
      expect(r.registered, 'second-token-0123456789abcdef');
      r.dispose();
    });

    test('forgetting takes the phone off the account and stops listening', () async {
      final (api, server) = rig();
      final push = SilentPush();
      final r = PushRegistrar(push);
      await r.register(api, 'tok', 'ann');
      await r.forget(api, 'tok', 'ann');
      expect(server.devices, isEmpty);
      expect(r.registered, isNull);
      push.refreshTo('later-token-0123456789abcdefgh');
      await settle();
      expect(server.devices, isEmpty);
      r.dispose();
    });

    test('no push on this build means no calls at all', () async {
      final (api, server) = rig();
      final r = PushRegistrar(SilentPush(available: false));
      await r.register(api, 'tok', 'ann');
      expect(server.calls.contains('RegisterDevice'), isFalse);
      r.dispose();
    });

    test('a server without push, or no connection, is not an error', () async {
      final (api, server) = rig();
      server.deviceError = true;
      final r = PushRegistrar(SilentPush());
      await r.register(api, 'tok', 'ann');
      expect(r.registered, isNull);
      server.deviceError = false;
      server.down = true;
      await r.register(api, 'tok', 'ann');
      expect(r.registered, isNull);
      r.dispose();
    });

    test('tapping a push opens that channel; other payloads are ignored', () async {
      final (_, _) = rig();
      final push = SilentPush();
      final r = PushRegistrar(push);
      await r.start();
      final opened = <String>[];
      r.opens.listen(opened.add);
      push.tap('chan:random');
      push.tap('call:bob');
      push.tap('chan:');
      await settle();
      expect(opened, ['random']);
      r.dispose();
    });
  });
}
