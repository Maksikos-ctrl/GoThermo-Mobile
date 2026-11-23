import 'dart:async';

import 'package:flutter/foundation.dart';

import '../calls/call_types.dart';

enum CallPhase { idle, calling, ringing, connecting, connected }

/// How a call ended, as the server's call log wants it.
enum CallOutcome { completed, declined, cancelled }

/// One-to-one voice / video calls, speaking the same signals as the web and
/// desktop apps (call_offer, call_answer, call_ice_candidate, call_reject,
/// call_end, call_renegotiate_*, call_screen_share_status).
class CallController extends ChangeNotifier {
  CallController({
    required this.me,
    required this.engine,
    required this.sendSignal,
    required this.loadIceServers,
    required this.logCall,
    CallTones? tones,
    Duration? ringTimeout,
    Duration? connectTimeout,
  })  : tones = tones ?? SilentTones(),
        ringTimeout = ringTimeout ?? const Duration(seconds: 45),
        connectTimeout = connectTimeout ?? const Duration(seconds: 25);

  final String me;
  final CallEngine engine;
  final void Function(String type, Map<String, dynamic> payload) sendSignal;
  final Future<List<Map<String, dynamic>>> Function() loadIceServers;

  /// Writes the "call" line into the conversation. Only the caller does it.
  final Future<void> Function(String remote, CallOutcome outcome, int seconds) logCall;
  final CallTones tones;
  final Duration ringTimeout;
  final Duration connectTimeout;

  CallPhase phase = CallPhase.idle;
  String? remote;
  bool incomingHasVideo = false;
  bool muted = false;
  bool cameraOn = false;
  bool speakerOn = false;
  bool remoteHasVideo = false;
  bool remoteSharingScreen = false;

  /// Set when something went wrong; the screen shows it once and clears it.
  String? error;

  CallPeer? peer;
  int seconds = 0;

  Sdp? _pendingOffer;
  final List<Ice> _queuedIce = [];
  bool _initiator = false;
  bool _wantsVideo = false;
  bool _remoteSet = false;
  // Candidates that arrive before their offer (or leave before our offer) must not get lost.
  final Map<String, List<Ice>> _earlyIce = {};
  final List<Ice> _heldOutIce = [];
  bool _offerSent = false;
  int _sentIce = 0;
  int _gotIce = 0;
  bool _disposed = false;
  DateTime? _connectedAt;
  Timer? _clock;
  Timer? _ringTimer;
  Timer? _connectTimer;
  final List<StreamSubscription<dynamic>> _subs = [];

  bool get busy => phase != CallPhase.idle;

  // ---- starting and answering ------------------------------------------------

  Future<void> start(String who, {bool video = false}) async {
    if (busy || _disposed) {
      error = 'You are already in a call';
      _changed();
      return;
    }
    _initiator = true;
    _wantsVideo = video;
    remote = who;
    speakerOn = video;
    phase = CallPhase.calling;
    _changed();
    try {
      final p = await _openPeer();
      final offer = await p.createOffer();
      sendSignal('call_offer', {'to': who, 'from': me, 'sdp': offer.toJson(), 'wantsVideo': video});
      _offerSent = true;
      for (final c in _heldOutIce) {
        _sendIce(who, c);
      }
      _heldOutIce.clear();
      tones.ringback();
      _ringTimer = Timer(ringTimeout, () {
        if (phase == CallPhase.calling) {
          error = 'No answer';
          _end(CallOutcome.cancelled, tell: true);
        }
      });
    } on CallMediaException catch (e) {
      error = e.message;
      _reset();
    } on Object {
      error = 'Could not start the call';
      _reset();
    }
  }

  Future<void> accept() async {
    final from = remote;
    final offer = _pendingOffer;
    if (phase != CallPhase.ringing || from == null || offer == null) return;
    tones.stop();
    _ringTimer?.cancel();
    phase = CallPhase.connecting;
    _wantsVideo = incomingHasVideo;
    speakerOn = incomingHasVideo;
    _changed();
    try {
      final p = await _openPeer();
      final answer = await p.answer(offer);
      _remoteSet = true;
      await _flushIce();
      sendSignal('call_answer', {'to': from, 'from': me, 'sdp': answer.toJson()});
      _armConnectTimer();
    } on CallMediaException catch (e) {
      sendSignal('call_reject', {'to': from, 'from': me});
      error = e.message;
      _reset();
    } on Object {
      sendSignal('call_reject', {'to': from, 'from': me});
      error = 'Could not answer the call';
      _reset();
    }
  }

  void decline() {
    final from = remote;
    if (phase != CallPhase.ringing || from == null) return;
    sendSignal('call_reject', {'to': from, 'from': me});
    _reset();
  }

  /// Hang up (or cancel while it is still ringing).
  void end() {
    if (!busy) return;
    if (phase == CallPhase.ringing) {
      decline();
      return;
    }
    _end(_connectedAt != null ? CallOutcome.completed : CallOutcome.cancelled, tell: true);
  }

  // ---- controls ------------------------------------------------------------------

  void toggleMute() {
    muted = !muted;
    peer?.setMuted(muted);
    _changed();
  }

  Future<void> toggleCamera() async {
    final p = peer;
    if (p == null) return;
    try {
      await p.setCamera(!cameraOn);
      cameraOn = !cameraOn;
      if (cameraOn && !speakerOn) await toggleSpeaker();
    } on CallMediaException catch (e) {
      error = e.message;
    }
    _changed();
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await peer?.setSpeaker(speakerOn);
    _changed();
  }

  Future<void> switchCamera() async => peer?.switchCamera();

  void clearError() {
    if (error == null) return;
    error = null;
    _changed();
  }

  // ---- signals from the server ---------------------------------------------------

  void handleSignal(String type, Object? payload) {
    if (_disposed || payload is! Map) return;
    if (payload['to'] != me) return;
    final from = payload['from'] is String ? payload['from'] as String : '';
    switch (type) {
      case 'call_offer':
        _onOffer(from, payload);
      case 'call_answer':
        _onAnswer(from, payload);
      case 'call_ice_candidate':
        _onIce(from, payload);
      case 'call_renegotiate_offer':
        _onRenegotiateOffer(from, payload);
      case 'call_renegotiate_answer':
        _onRenegotiateAnswer(from, payload);
      case 'call_screen_share_status':
        if (from == remote) {
          remoteSharingScreen = payload['sharing'] == true;
          _changed();
        }
      case 'call_reject':
        if (from == remote && busy) _end(CallOutcome.declined, tell: false);
      case 'call_end':
        if (from == remote && busy) {
          _end(_connectedAt != null ? CallOutcome.completed : CallOutcome.cancelled, tell: false);
        }
    }
  }

  void _onOffer(String from, Map<dynamic, dynamic> payload) {
    final offer = Sdp.fromJson(payload['sdp']);
    if (offer == null || from.isEmpty) return;
    if (busy) {
      sendSignal('call_reject', {'to': from, 'from': me});
      return;
    }
    _pendingOffer = offer;
    remote = from;
    _queuedIce.addAll(_earlyIce.remove(from) ?? const <Ice>[]);
    _earlyIce.clear();
    incomingHasVideo = payload['wantsVideo'] == true;
    _initiator = false;
    phase = CallPhase.ringing;
    tones.ringing();
    // Stop ringing by itself if the caller gave up without telling us.
    _ringTimer = Timer(ringTimeout + const Duration(seconds: 15), () {
      if (phase == CallPhase.ringing) _reset();
    });
    _changed();
  }

  void _onAnswer(String from, Map<dynamic, dynamic> payload) {
    final p = peer;
    final answer = Sdp.fromJson(payload['sdp']);
    if (p == null || answer == null || from != remote || phase != CallPhase.calling) return;
    tones.stop();
    _ringTimer?.cancel();
    phase = CallPhase.connecting;
    _changed();
    unawaited(() async {
      try {
        await p.setAnswer(answer);
        _remoteSet = true;
        await _flushIce();
        _armConnectTimer();
      } on Object {
        await _fail('The call could not connect');
      }
    }());
  }

  void _onIce(String from, Map<dynamic, dynamic> payload) {
    final c = Ice.fromJson(payload['candidate']);
    if (c == null || from.isEmpty) return;
    if (phase == CallPhase.idle) {
      (_earlyIce[from] ??= []).add(c);
      return;
    }
    if (from != remote) return;
    _gotIce++;
    final p = peer;
    if (p != null && _remoteSet) {
      unawaited(p.addIce(c).catchError((Object _) {}));
    } else {
      _queuedIce.add(c);
    }
  }

  void _onRenegotiateOffer(String from, Map<dynamic, dynamic> payload) {
    final p = peer;
    final offer = Sdp.fromJson(payload['sdp']);
    if (p == null || offer == null || from != remote) return;
    unawaited(() async {
      try {
        final answer = await p.answer(offer);
        sendSignal('call_renegotiate_answer', {'to': from, 'from': me, 'sdp': answer.toJson()});
      } on Object {
        // The call goes on without the change.
      }
    }());
  }

  void _onRenegotiateAnswer(String from, Map<dynamic, dynamic> payload) {
    final p = peer;
    final answer = Sdp.fromJson(payload['sdp']);
    if (p == null || answer == null || from != remote) return;
    unawaited(p.setAnswer(answer).catchError((Object _) {}));
  }

  // ---- plumbing ------------------------------------------------------------------

  Future<CallPeer> _openPeer() async {
    List<Map<String, dynamic>> servers;
    try {
      servers = await loadIceServers();
    } on Object {
      servers = const [];
    }
    if (servers.isEmpty) {
      servers = [
        {'urls': ['stun:stun.l.google.com:19302']},
      ];
    }
    final p = engine.create(servers);
    peer = p;
    _subs
      ..add(p.onIce.listen((c) {
        final to = remote;
        if (to == null) return;
        if (_initiator && !_offerSent) {
          _heldOutIce.add(c);
        } else {
          _sendIce(to, c);
        }
      }))
      ..add(p.onState.listen(_onPeerState))
      ..add(p.onRemoteVideo.listen((has) {
        remoteHasVideo = has;
        _changed();
      }))
      ..add(p.onNegotiationNeeded.listen((_) => _renegotiate()));
    await p.open();
    return p;
  }

  void _sendIce(String to, Ice c) {
    _sentIce++;
    sendSignal('call_ice_candidate', {'to': to, 'from': me, 'candidate': c.toJson()});
  }

  String get _netInfo => ' (sent $_sentIce, received $_gotIce candidates)';

  Future<void> _renegotiate() async {
    final p = peer;
    final to = remote;
    // Before the call is up the first offer / answer does the job.
    if (p == null || to == null || phase != CallPhase.connected) return;
    try {
      final offer = await p.createOffer();
      sendSignal('call_renegotiate_offer', {'to': to, 'from': me, 'sdp': offer.toJson()});
    } on Object {
      // Ignore; the next change tries again.
    }
  }

  Future<void> _flushIce() async {
    final p = peer;
    if (p == null) return;
    final queued = List<Ice>.of(_queuedIce);
    _queuedIce.clear();
    for (final c in queued) {
      try {
        await p.addIce(c);
      } on Object {
        // A stale candidate is harmless.
      }
    }
  }

  void _armConnectTimer() {
    _connectTimer?.cancel();
    _connectTimer = Timer(connectTimeout, () {
      if (phase == CallPhase.connecting) {
        unawaited(_fail('The call could not connect. Your networks may block direct calls.$_netInfo'));
      }
    });
  }

  void _onPeerState(PeerState s) {
    switch (s) {
      case PeerState.connected:
        if (phase == CallPhase.connected || !busy) return;
        _connectTimer?.cancel();
        tones.stop();
        _ringTimer?.cancel();
        phase = CallPhase.connected;
        _connectedAt = DateTime.now();
        seconds = 0;
        _clock = Timer.periodic(const Duration(seconds: 1), (_) {
          seconds = DateTime.now().difference(_connectedAt!).inSeconds;
          _changed();
        });
        // A video call starts with the microphone; the camera comes on now,
        // the same way the web app does it.
        if (_wantsVideo) {
          _wantsVideo = false;
          unawaited(toggleCamera());
        }
        _changed();
      case PeerState.failed:
        if (busy) unawaited(_fail('The call could not connect. Your networks may block direct calls.$_netInfo'));
      case PeerState.closed:
      case PeerState.connecting:
        break;
    }
  }

  Future<void> _fail(String message, {bool tell = true}) async {
    error = message;
    _end(_connectedAt != null ? CallOutcome.completed : CallOutcome.cancelled, tell: tell);
  }

  void _end(CallOutcome outcome, {required bool tell}) {
    final who = remote;
    final wasInitiator = _initiator;
    final length = _connectedAt == null ? 0 : DateTime.now().difference(_connectedAt!).inSeconds;
    if (tell && who != null) sendSignal('call_end', {'to': who, 'from': me});
    _reset();
    if (wasInitiator && who != null) {
      unawaited(logCall(who, outcome, length).catchError((Object _) {}));
    }
  }

  void _reset() {
    tones.stop();
    _ringTimer?.cancel();
    _connectTimer?.cancel();
    _clock?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final p = peer;
    peer = null;
    if (p != null) unawaited(p.close().catchError((Object _) {}));
    phase = CallPhase.idle;
    remote = null;
    _pendingOffer = null;
    _queuedIce.clear();
    _initiator = false;
    _wantsVideo = false;
    _remoteSet = false;
    _offerSent = false;
    _heldOutIce.clear();
    _sentIce = 0;
    _gotIce = 0;
    _connectedAt = null;
    incomingHasVideo = false;
    muted = false;
    cameraOn = false;
    speakerOn = false;
    remoteHasVideo = false;
    remoteSharingScreen = false;
    seconds = 0;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (busy) {
      final who = remote;
      if (who != null && phase != CallPhase.ringing) sendSignal('call_end', {'to': who, 'from': me});
      tones.stop();
    }
    _ringTimer?.cancel();
    _connectTimer?.cancel();
    _clock?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    final p = peer;
    peer = null;
    if (p != null) unawaited(p.close().catchError((Object _) {}));
    super.dispose();
  }
}
