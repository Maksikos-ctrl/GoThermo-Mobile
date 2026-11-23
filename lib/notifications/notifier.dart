import 'dart:async';

/// Shows a notification on the phone when something happens while the app is
/// not on screen.
abstract class Notifier {
  Future<void> init();

  /// Asks the person for permission (Android 13+ and iOS); true when allowed.
  Future<bool> requestPermission();

  Future<void> show({required int id, required String title, required String body, String? payload});

  Future<void> cancel(int id);

  Future<void> cancelAll();

  /// The payload of a notification the person tapped.
  Stream<String> get taps;
}

/// Shows nothing; remembers what it was asked to show (tests).
class SilentNotifier implements Notifier {
  final List<({int id, String title, String body, String? payload})> shown = [];
  final List<int> cancelled = [];
  bool allowed = true;
  int permissionAsked = 0;
  final StreamController<String> _taps = StreamController<String>.broadcast();

  void tap(String payload) => _taps.add(payload);

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async {
    permissionAsked++;
    return allowed;
  }

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) async {
    shown.add((id: id, title: title, body: body, payload: payload));
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => shown.clear();

  @override
  Stream<String> get taps => _taps.stream;
}

/// The words of a notification for a new message.
String notificationBody({required String user, required String text, bool isFile = false, String fileName = ''}) {
  if (isFile) return '$user sent ${fileName.isEmpty ? 'a file' : fileName}';
  final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  final short = clean.length > 140 ? '${clean.substring(0, 140)}…' : clean;
  return '$user: $short';
}

/// A stable notification id for a channel, so a channel's notifications
/// replace each other instead of piling up.
int notificationIdFor(String channel) => 100 + (channel.hashCode & 0x3fffffff);

/// The id used for an incoming call.
const int callNotificationId = 1;
