import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultServerUrl = 'https://gothermo-team.duckdns.org';

/// Where the app keeps the signed-in token and the server address.
abstract class SessionStore {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> clearToken();
  Future<String> readServer();
  Future<void> writeServer(String url);
}

/// The real thing: the token in the system keychain / keystore.
class PlatformSessionStore implements SessionStore {
  PlatformSessionStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;
  static const _tokenKey = 'gothermo.token';
  static const _serverKey = 'gothermo.server';

  @override
  Future<String?> readToken() => _secure.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) => _secure.write(key: _tokenKey, value: token);

  @override
  Future<void> clearToken() => _secure.delete(key: _tokenKey);

  @override
  Future<String> readServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverKey) ?? defaultServerUrl;
  }

  @override
  Future<void> writeServer(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, url);
  }
}

/// For tests.
class MemorySessionStore implements SessionStore {
  MemorySessionStore({this.token, this.server = defaultServerUrl});

  String? token;
  String server;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String t) async => token = t;

  @override
  Future<void> clearToken() async => token = null;

  @override
  Future<String> readServer() async => server;

  @override
  Future<void> writeServer(String url) async => server = url;
}
