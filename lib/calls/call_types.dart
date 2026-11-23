import 'dart:async';

/// A session description (offer or answer) as the web app sends it:
/// `{"type": "offer", "sdp": "..."}`.
class Sdp {
  const Sdp(this.type, this.sdp);

  final String type;
  final String sdp;

  Map<String, dynamic> toJson() => {'type': type, 'sdp': sdp};

  static Sdp? fromJson(Object? v) {
    if (v is! Map) return null;
    final type = v['type'];
    final sdp = v['sdp'];
    if (type is! String || sdp is! String || sdp.isEmpty) return null;
    return Sdp(type, sdp);
  }
}

/// A network candidate found while connecting.
class Ice {
  const Ice(this.candidate, this.sdpMid, this.sdpMLineIndex);

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  Map<String, dynamic> toJson() => {
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      };

  static Ice? fromJson(Object? v) {
    if (v is! Map) return null;
    final c = v['candidate'];
    if (c is! String || c.isEmpty) return null;
    final mid = v['sdpMid'];
    final index = v['sdpMLineIndex'];
    return Ice(c, mid is String ? mid : null, index is num ? index.toInt() : null);
  }
}

enum PeerState { connecting, connected, failed, closed }

/// One peer-to-peer connection plus the microphone / camera feeding it.
/// The real one wraps WebRTC; tests use a fake.
abstract class CallPeer {
  Stream<Ice> get onIce;
  Stream<PeerState> get onState;

  /// The camera was turned on or off mid-call, so the offer must be redone.
  Stream<void> get onNegotiationNeeded;

  /// The other side's video appeared (true) or went away (false).
  Stream<bool> get onRemoteVideo;

  /// Turns the microphone on and creates the connection. Throws
  /// [CallMediaException] when the microphone cannot be used.
  Future<void> open();

  Future<Sdp> createOffer();

  /// Takes the other side's offer and returns the answer.
  Future<Sdp> answer(Sdp offer);

  Future<void> setAnswer(Sdp answer);
  Future<void> addIce(Ice candidate);
  void setMuted(bool muted);

  /// Starts (or resumes) the camera. Throws [CallMediaException] if blocked.
  Future<void> setCamera(bool on);
  Future<void> setSpeaker(bool on);
  Future<void> switchCamera();
  Future<void> close();
}

/// Makes [CallPeer]s. [iceServers] is the list from the server (STUN / TURN).
abstract class CallEngine {
  CallPeer create(List<Map<String, dynamic>> iceServers);
}

/// The microphone or camera cannot be used; [message] says what to do.
class CallMediaException implements Exception {
  CallMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Ringing sounds. Tests use a silent one.
abstract class CallTones {
  void ringing(); // incoming call
  void ringback(); // calling someone
  void stop();
}

class SilentTones implements CallTones {
  String? last;

  @override
  void ringing() => last = 'ringing';

  @override
  void ringback() => last = 'ringback';

  @override
  void stop() => last = null;
}
