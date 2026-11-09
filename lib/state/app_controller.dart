import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/gothermo_api.dart';
import '../api/rpc_client.dart';
import '../models/user.dart';
import 'session_store.dart';

enum AuthState { starting, signedOut, signedIn }

/// Holds who is signed in and which server we talk to.
class AppController extends ChangeNotifier {
  AppController({required this.store, http.Client? httpClient}) : _http = httpClient;

  final SessionStore store;
  final http.Client? _http;

  AuthState state = AuthState.starting;
  String serverUrl = defaultServerUrl;
  Session? session;
  late GoThermoApi api = _buildApi();

  GoThermoApi _buildApi() => GoThermoApi(RpcClient(baseUrl: serverUrl, client: _http));

  /// Reads what was saved and checks the saved token with the server.
  Future<void> start() async {
    serverUrl = await store.readServer();
    api = _buildApi();
    final token = await store.readToken();
    if (token == null || token.isEmpty) {
      state = AuthState.signedOut;
      notifyListeners();
      return;
    }
    try {
      final user = await api.check(token);
      if (user != null) {
        session = Session(token: token, user: user);
        state = AuthState.signedIn;
      } else {
        await store.clearToken();
        state = AuthState.signedOut;
      }
    } on RpcException {
      // Offline or the server is down: show the sign-in screen, but keep the
      // saved token so it still works next time the server answers.
      state = AuthState.signedOut;
    }
    notifyListeners();
  }

  Future<void> signIn(String identifier, String password) async {
    final s = await api.login(identifier, password);
    await _accept(s);
  }

  Future<void> register(String email, String password, String invite) async {
    final s = await api.register(email, password, invite: invite);
    await _accept(s);
  }

  Future<void> _accept(Session s) async {
    await store.writeToken(s.token);
    session = s;
    state = AuthState.signedIn;
    notifyListeners();
  }

  Future<void> signOut() async {
    final s = session;
    session = null;
    state = AuthState.signedOut;
    await store.clearToken();
    notifyListeners();
    if (s != null) {
      try {
        await api.logout(s.token);
      } on RpcException {
        // The token is gone on this phone either way.
      }
    }
  }

  Future<void> setServer(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) return;
    serverUrl = clean;
    await store.writeServer(clean);
    api = _buildApi();
    notifyListeners();
  }
}
