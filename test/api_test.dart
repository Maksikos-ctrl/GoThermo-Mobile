import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/api/gothermo_api.dart';
import 'package:gothermo_mobile/api/rpc_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response ok(Object? result) => http.Response(jsonEncode({'result': result}), 200);

GoThermoApi apiWith(Future<http.Response> Function(http.Request) handler) =>
    GoThermoApi(RpcClient(baseUrl: 'https://x.io', client: MockClient(handler)));

void main() {
  test('login returns the token and the person', () async {
    late List<dynamic> sent;
    final api = apiWith((req) async {
      expect(req.url.path, '/rpc/Login');
      sent = jsonDecode(req.body) as List<dynamic>;
      return ok({'id': 'u1', 'username': 'ann', 'email': 'ann@x.io', 'token': 'tok123', 'status': 'online'});
    });
    final s = await api.login('  ann@x.io ', 'pw');
    expect(sent, ['ann@x.io', 'pw']);
    expect(s.token, 'tok123');
    expect(s.user.username, 'ann');
    expect(s.user.isAdmin, isFalse);
  });

  test('the admin sign-in is recognised', () async {
    final api = apiWith((_) async => ok({'username': 'admin', 'token': 't', 'isAdmin': true}));
    final s = await api.login('admin', 'pw');
    expect(s.user.isAdmin, isTrue);
  });

  test('a reply without a token is refused', () async {
    final api = apiWith((_) async => ok({'username': 'ann'}));
    expect(api.login('a@b.io', 'pw'), throwsA(isA<RpcException>()));
  });

  test('register passes the invite code as a header', () async {
    late http.Request seen;
    final api = apiWith((req) async {
      seen = req;
      return ok({'username': 'new', 'token': 't'});
    });
    final s = await api.register('new@x.io', 'pw12345678', invite: ' CODE ');
    expect(seen.url.path, '/rpc/Register');
    expect(seen.headers['X-Invite-Code'], 'CODE');
    expect(s.user.username, 'new');
  });

  test('check understands the JSON text the server returns', () async {
    final api = apiWith((_) async => ok(jsonEncode({'username': 'ann', 'avatar': 'data:image/jpeg;base64,AAAA'})));
    final u = await api.check('tok');
    expect(u?.username, 'ann');
    expect(u?.avatar, startsWith('data:image/'));
  });

  test('check returns null for a token the server does not know', () async {
    final api = apiWith((_) async => ok(''));
    expect(await api.check('old'), isNull);
  });

  test('channels are parsed, odd entries skipped', () async {
    final api = apiWith((req) async {
      expect(jsonDecode(req.body), ['tok']);
      return ok([
        {'id': '1', 'name': 'general', 'description': 'Everyone', 'members': ['ann', 'bob'], 'isPrivate': false},
        {'id': '2', 'name': 'secret', 'isPrivate': true},
        'garbage',
      ]);
    });
    final list = await api.channels('tok');
    expect(list.map((c) => c.name), ['general', 'secret']);
    expect(list[0].members, ['ann', 'bob']);
    expect(list[1].isPrivate, isTrue);
    expect(list[1].members, isEmpty);
  });

  test('no channels (null result) is an empty list', () async {
    final api = apiWith((_) async => ok(null));
    expect(await api.channels('tok'), isEmpty);
  });
}
