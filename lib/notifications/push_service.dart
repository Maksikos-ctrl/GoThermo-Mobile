import 'dart:async';

/// Push messages from the server for when the app is closed (Firebase Cloud
/// Messaging on the phone). The system itself shows the notification; the app
/// only hands its address (token) to the server and hears about taps.
abstract class PushService {
  /// Starts Firebase. False when it is not set up on this build (no
  /// google-services.json, no Play services...): the app then simply has no push.
  Future<bool> init();

  /// This phone's address for the server, once known.
  Future<String?> token();

  /// A new address, when Firebase replaces it.
  Stream<String> get tokenChanges;

  /// The payload of a push the person tapped (also the one that opened the app).
  Stream<String> get taps;
}

/// No push; remembers nothing (tests and unsupported platforms).
class SilentPush implements PushService {
  SilentPush({this.available = true, String? token = 'silent-device-token-0123456789'}) : _token = token;

  final bool available;
  String? _token;
  final StreamController<String> _changes = StreamController<String>.broadcast();
  final StreamController<String> _taps = StreamController<String>.broadcast();

  void refreshTo(String t) {
    _token = t;
    _changes.add(t);
  }

  void tap(String payload) => _taps.add(payload);

  @override
  Future<bool> init() async => available;

  @override
  Future<String?> token() async => available ? _token : null;

  @override
  Stream<String> get tokenChanges => _changes.stream;

  @override
  Stream<String> get taps => _taps.stream;
}
