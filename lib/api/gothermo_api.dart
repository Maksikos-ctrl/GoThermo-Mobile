import 'dart:convert';

import '../models/channel.dart';
import '../models/user.dart';
import 'rpc_client.dart';

/// Typed calls to the server. Every method here is one the web app uses too.
class GoThermoApi {
  GoThermoApi(this._rpc);

  final RpcClient _rpc;

  Map<String, dynamic> _map(Object? v) {
    if (v is Map<String, dynamic>) return v;
    throw RpcException('Unexpected answer from the server');
  }

  /// [identifier] is an email, or `admin` for the admin account.
  Future<Session> login(String identifier, String password) async {
    final raw = await _rpc.call('Login', [identifier.trim(), password]);
    return _sessionFrom(raw, User.fromJson(_map(raw)));
  }

  Session _sessionFrom(Object? raw, User user) {
    final token = _map(raw)['token'];
    if (token is! String || token.isEmpty) {
      throw RpcException('The server did not return a session');
    }
    return Session(token: token, user: user);
  }

  Future<Session> register(String email, String password, {String invite = ''}) async {
    final raw = await _rpc.call(
      'Register',
      [email.trim(), password],
      headers: invite.trim().isEmpty ? const {} : {'X-Invite-Code': invite.trim()},
    );
    return _sessionFrom(raw, User.fromJson(_map(raw)));
  }

  /// The signed-in person for a saved token, or null when it no longer works.
  Future<User?> check(String token) async {
    final raw = await _rpc.call('CheckAuth', [token]);
    if (raw is! String || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return User.fromJson(decoded);
  }

  Future<void> logout(String token) async {
    await _rpc.call('Logout', [token]);
  }

  Future<List<Channel>> channels(String token) async {
    final raw = await _rpc.call('GetChannels', [token]);
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(Channel.fromJson).toList();
  }
}
