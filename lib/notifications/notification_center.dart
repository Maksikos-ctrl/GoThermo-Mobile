import 'dart:async';

import '../calls/call_types.dart';
import '../state/call_controller.dart';
import '../state/chat_controller.dart';
import 'notifier.dart';

/// Decides when the phone shows a notification: a message that arrives (or a
/// call that rings) while the app is in the background.
class NotificationCenter {
  NotificationCenter(this.notifier);

  final Notifier notifier;
  bool inBackground = false;

  StreamSubscription<Notice>? _noticeSub;
  StreamSubscription<String>? _tapSub;
  final StreamController<String> _opens = StreamController<String>.broadcast();
  CallController? _call;
  bool _ringing = false;

  /// Channels the person asked to open by tapping a notification.
  Stream<String> get opens => _opens.stream;

  /// Starts listening for taps and asks for permission (once per launch).
  Future<void> setUp() async {
    await notifier.init();
    _tapSub ??= notifier.taps.listen((p) {
      if (p.startsWith('chan:') && p.length > 5) _opens.add(p.substring(5));
    });
    await notifier.requestPermission();
  }

  /// Follows one signed-in session.
  void attach(ChatController chat, CallController call) {
    detach();
    chat.foreground = !inBackground;
    _noticeSub = chat.notices.listen(_onNotice);
    _call = call..addListener(_onCall);
  }

  void detach() {
    _noticeSub?.cancel();
    _noticeSub = null;
    _call?.removeListener(_onCall);
    _call = null;
    _ringing = false;
    unawaited(notifier.cancelAll());
  }

  /// The app went to the background / came back to the front.
  void setBackground(bool background, ChatController? chat) {
    inBackground = background;
    chat?.foreground = !background;
    if (!background) unawaited(notifier.cancelAll());
  }

  void dispose() {
    detach();
    _tapSub?.cancel();
    _opens.close();
  }

  void _onNotice(Notice n) {
    if (!inBackground) return;
    final m = n.message;
    unawaited(notifier.show(
      id: notificationIdFor(m.channel),
      title: n.title,
      body: notificationBody(user: m.user, text: m.text, isFile: m.isFile),
      payload: 'chan:${m.channel}',
    ));
  }

  void _onCall() {
    final k = _call;
    if (k == null) return;
    final ringing = k.phase == CallPhase.ringing;
    if (ringing && !_ringing && inBackground) {
      unawaited(notifier.show(
        id: callNotificationId,
        title: 'Incoming call',
        body: '${k.remote ?? 'Someone'} is calling you',
      ));
    }
    if (!ringing && _ringing) unawaited(notifier.cancel(callNotificationId));
    _ringing = ringing;
  }
}
