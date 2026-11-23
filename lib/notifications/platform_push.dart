import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_service.dart';

class PlatformPush implements PushService {
  final StreamController<String> _taps = StreamController<String>.broadcast();
  bool _ready = false;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Stream<String> get tokenChanges {
    if (!_ready) return const Stream<String>.empty();
    return FirebaseMessaging.instance.onTokenRefresh;
  }

  @override
  Future<bool> init() async {
    if (_ready) return true;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      final first = await messaging.getInitialMessage();
      if (first != null) _open(first);
      _ready = true;
    } on Object {
      _ready = false; // Firebase is not set up here; the app works without push
    }
    return _ready;
  }

  void _open(RemoteMessage m) {
    final p = m.data['payload'];
    if (p is String && p.isNotEmpty && !_taps.isClosed) _taps.add(p);
  }

  @override
  Future<String?> token() async {
    if (!_ready) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } on Object {
      return null;
    }
  }
}
