import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/gothermo_api.dart';
import '../api/rpc_client.dart';
import '../api/socket.dart';
import '../models/user.dart';
import 'chat_controller.dart';
import 'google_auth.dart';
import 'session_store.dart';

enum AuthState { starting, signedOut, signedIn }

/// Holds who is signed in and which server we talk to. While someone is signed
/// in (and is not the admin) it also owns the [ChatController].
class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    http.Client? httpClient,
    SocketConnector? connector,
    GoogleAuth? google,
  })  : _http = httpClient,
        _connector = connector,
        _google = google;

  final SessionStore store;
  final http.Client? _http;
  final SocketConnector? _connector;
  GoogleAuth? _google;

  AuthState state = AuthState.starting;
  String serverUrl = defaultServerUrl;
  Session? session;
  ChatController? chat;
  late GoThermoApi api = _buildApi();

  GoogleAuth get google => _google ??= PlatformGoogleAuth();

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
        _begin(Session(token: token, user: user));
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

  /// Returns false when the person closed the Google window.
  Future<bool> signInWithGoogle({required bool signUp}) async {
    final token = await google.accessToken();
    if (token == null) return false;
    final s = await api.loginWithGoogleToken(token, signUp: signUp);
    await _accept(s);
    return true;
  }

  Future<void> _accept(Session s) async {
    await store.writeToken(s.token);
    _begin(s);
    notifyListeners();
  }

  void _begin(Session s) {
    chat?.dispose();
    chat = null;
    session = s;
    state = AuthState.signedIn;
    if (!s.user.isAdmin) {
      final c = ChatController(api: api, session: s, serverUrl: serverUrl, connector: _connector);
      chat = c;
      c.start();
    }
  }

  /// The app came back to the front.
  void resumed() => chat?.resumed();

  Future<void> signOut() async {
    final s = session;
    chat?.dispose();
    chat = null;
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
      await google.signOut();
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

  @override
  void dispose() {
    chat?.dispose();
    super.dispose();
  }
}
