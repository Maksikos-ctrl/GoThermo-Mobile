import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/api/rpc_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('posts the arguments as a JSON array to /rpc/<Method>', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return json({'result': 'hi'});
    });
    final rpc = RpcClient(baseUrl: 'https://chat.example.com/', client: client);

    final out = await rpc.call('Greet', ['a', 2, true]);

    expect(out, 'hi');
    expect(seen.method, 'POST');
    expect(seen.url.toString(), 'https://chat.example.com/rpc/Greet');
    expect(jsonDecode(seen.body), ['a', 2, true]);
    expect(seen.headers['Content-Type'], contains('application/json'));
  });

  test('sends extra headers', () async {
    late http.Request seen;
    final rpc = RpcClient(
      baseUrl: 'https://x.io',
      client: MockClient((req) async {
        seen = req;
        return json({'result': null});
      }),
    );
    await rpc.call('Register', ['a', 'b'], headers: {'X-Invite-Code': 'abc'});
    expect(seen.headers['X-Invite-Code'], 'abc');
  });

  test('an error field becomes an RpcException with the server text', () async {
    final rpc = RpcClient(
      baseUrl: 'https://x.io',
      client: MockClient((_) async => json({'error': 'incorrect email or password'})),
    );
    expect(
      rpc.call('Login', ['a', 'b']),
      throwsA(isA<RpcException>().having((e) => e.message, 'message', 'incorrect email or password')),
    );
  });

  test('an answer that is not JSON is reported, not crashed on', () async {
    final rpc = RpcClient(
      baseUrl: 'https://x.io',
      client: MockClient((_) async => http.Response('<html>bad gateway</html>', 502)),
    );
    expect(
      rpc.call('Login', const []),
      throwsA(isA<RpcException>().having((e) => e.message, 'message', contains('502'))),
    );
  });

  test('a failing status without an error field is an error', () async {
    final rpc = RpcClient(
      baseUrl: 'https://x.io',
      client: MockClient((_) async => json({'result': 1}, 500)),
    );
    expect(rpc.call('X', const []), throwsA(isA<RpcException>()));
  });

  test('an unreachable server says where it tried', () async {
    final rpc = RpcClient(
      baseUrl: 'https://down.example',
      client: MockClient((_) async => throw http.ClientException('no route')),
    );
    expect(
      rpc.call('X', const []),
      throwsA(isA<RpcException>().having((e) => e.message, 'message', contains('https://down.example'))),
    );
  });

  test('unicode survives the round trip', () async {
    final rpc = RpcClient(
      baseUrl: 'https://x.io',
      client: MockClient((req) async => json({'result': jsonDecode(req.body)[0]})),
    );
    expect(await rpc.call('Echo', ['привет 👋']), 'привет 👋');
  });
}
