import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notifier.dart';

class PlatformNotifier implements Notifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController<String>.broadcast();
  bool _ready = false;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty && !_taps.isClosed) _taps.add(p);
        },
      );
      _ready = true;
    } on Object {
      _ready = false; // no notifications on this device; the app works without
    }
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? true;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (mac != null) return await mac.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } on Object {
      return false;
    }
    return true;
  }

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            channelDescription: 'New messages and incoming calls',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
          macOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
        payload: payload,
      );
    } on Object {
      // A notification that cannot be shown is not worth a crash.
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id);
    } on Object {
      // nothing to cancel
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } on Object {
      // nothing to cancel
    }
  }
}
