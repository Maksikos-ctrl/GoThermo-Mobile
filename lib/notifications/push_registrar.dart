import 'dart:async';

import '../api/gothermo_api.dart';
import 'push_service.dart';

/// Keeps the server's idea of "which phone belongs to this account" right:
/// registers on sign-in and whenever Firebase changes the token, forgets it on
/// sign-out. Every failure is quiet: push is a bonus, never a reason to break.
class PushRegistrar {
  PushRegistrar(this.push);

  final PushService push;

  StreamSubscription<String>? _refresh;
  StreamSubscription<String>? _tapSub;
  final StreamController<String> _opens = StreamController<String>.broadcast();
  String? _current;
  bool _started = false;
  bool _ok = false;

  /// Channels to open because the person tapped a push.
  Stream<String> get opens => _opens.stream;

  /// The token last given to the server.
  String? get registered => _current;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _ok = await push.init();
    if (!_ok) return;
    _tapSub = push.taps.listen((p) {
      if (p.startsWith('chan:') && p.length > 5) _opens.add(p.substring(5));
    });
  }

  /// Gives this phone to the server for [user].
  Future<void> register(GoThermoApi api, String authToken, String user) async {
    await start();
    if (!_ok) return;
    await _refresh?.cancel();
    final t = await push.token();
    if (t != null) await _send(api, authToken, user, t);
    _refresh = push.tokenChanges.listen((n) => unawaited(_send(api, authToken, user, n)));
  }

  Future<void> _send(GoThermoApi api, String authToken, String user, String deviceToken) async {
    try {
      await api.registerDevice(authToken, user, deviceToken);
      _current = deviceToken;
    } on Object {
      // Offline or an old server without push: try again at the next start.
    }
  }

  /// Takes this phone off the account (call before the session token is gone).
  Future<void> forget(GoThermoApi api, String authToken, String user) async {
    await _refresh?.cancel();
    _refresh = null;
    final t = _current;
    _current = null;
    if (t == null) return;
    try {
      await api.unregisterDevice(authToken, user, t);
    } on Object {
      // The server drops dead tokens by itself.
    }
  }

  void dispose() {
    _refresh?.cancel();
    _tapSub?.cancel();
    _opens.close();
  }
}
