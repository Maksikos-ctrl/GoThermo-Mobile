import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_types.dart';

/// Makes real WebRTC connections.
class WebRtcEngine implements CallEngine {
  @override
  CallPeer create(List<Map<String, dynamic>> iceServers) => WebRtcPeer(iceServers);
}

/// One WebRTC connection with the microphone (and later the camera) attached.
class WebRtcPeer implements CallPeer {
  WebRtcPeer(this.iceServers);

  final List<Map<String, dynamic>> iceServers;

  /// The screens draw these.
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _mic;
  MediaStream? _cam;
  bool _closed = false;

  final StreamController<Ice> _ice = StreamController<Ice>.broadcast();
  final StreamController<PeerState> _state = StreamController<PeerState>.broadcast();
  final StreamController<void> _negotiation = StreamController<void>.broadcast();
  final StreamController<bool> _remoteVideo = StreamController<bool>.broadcast();

  @override
  Stream<Ice> get onIce => _ice.stream;
  @override
  Stream<PeerState> get onState => _state.stream;
  @override
  Stream<void> get onNegotiationNeeded => _negotiation.stream;
  @override
  Stream<bool> get onRemoteVideo => _remoteVideo.stream;

  @override
  Future<void> open() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    try {
      _mic = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    } on Object catch (e) {
      throw CallMediaException(_micMessage(e));
    }
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;

    pc.onIceCandidate = (RTCIceCandidate c) {
      final text = c.candidate;
      if (text != null && text.isNotEmpty && !_ice.isClosed) {
        _ice.add(Ice(text, c.sdpMid, c.sdpMLineIndex));
      }
    };
    pc.onConnectionState = (RTCPeerConnectionState s) {
      if (_state.isClosed) return;
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _state.add(PeerState.connected);
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _state.add(PeerState.failed);
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _state.add(PeerState.closed);
        default:
          _state.add(PeerState.connecting);
      }
    };
    // Some Android builds report only the ICE state, so listen to both.
    pc.onIceConnectionState = (RTCIceConnectionState s) {
      if (_state.isClosed) return;
      switch (s) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _state.add(PeerState.connected);
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _state.add(PeerState.failed);
        default:
          break;
      }
    };
    pc.onTrack = (RTCTrackEvent e) {
      if (e.track.kind != 'video') return; // sound plays by itself
      final stream = e.streams.isNotEmpty ? e.streams.first : null;
      if (stream == null) return;
      remoteRenderer.srcObject = stream;
      if (!_remoteVideo.isClosed) _remoteVideo.add(true);
      e.track.onEnded = () {
        if (!_remoteVideo.isClosed) _remoteVideo.add(false);
      };
    };
    pc.onRenegotiationNeeded = () {
      if (!_negotiation.isClosed) _negotiation.add(null);
    };

    final mic = _mic!;
    for (final track in mic.getAudioTracks()) {
      await pc.addTrack(track, mic);
    }
  }

  RTCPeerConnection get _conn {
    final pc = _pc;
    if (pc == null) throw StateError('The call is not open');
    return pc;
  }

  @override
  Future<Sdp> createOffer() async {
    final pc = _conn;
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    return Sdp(offer.type ?? 'offer', offer.sdp ?? '');
  }

  @override
  Future<Sdp> answer(Sdp offer) async {
    final pc = _conn;
    await pc.setRemoteDescription(RTCSessionDescription(offer.sdp, offer.type));
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return Sdp(answer.type ?? 'answer', answer.sdp ?? '');
  }

  @override
  Future<void> setAnswer(Sdp answer) async {
    await _conn.setRemoteDescription(RTCSessionDescription(answer.sdp, answer.type));
  }

  @override
  Future<void> addIce(Ice candidate) async {
    await _conn.addCandidate(RTCIceCandidate(candidate.candidate, candidate.sdpMid, candidate.sdpMLineIndex));
  }

  @override
  void setMuted(bool muted) {
    for (final t in _mic?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
  }

  @override
  Future<void> setCamera(bool on) async {
    final existing = _cam;
    if (existing != null) {
      for (final t in existing.getVideoTracks()) {
        t.enabled = on;
      }
      return;
    }
    if (!on) return;
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': 'user'},
      });
      _cam = stream;
      localRenderer.srcObject = stream;
      final pc = _conn;
      for (final t in stream.getVideoTracks()) {
        await pc.addTrack(t, stream);
      }
    } on Object catch (e) {
      throw CallMediaException(_cameraMessage(e));
    }
  }

  @override
  Future<void> setSpeaker(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } on Object {
      // Not every device lets the app choose.
    }
  }

  @override
  Future<void> switchCamera() async {
    final tracks = _cam?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } on Object {
      // Single-camera device.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final stream in [_mic, _cam]) {
      if (stream == null) continue;
      for (final t in stream.getTracks()) {
        await t.stop();
      }
      await stream.dispose();
    }
    _mic = null;
    _cam = null;
    final pc = _pc;
    _pc = null;
    if (pc != null) {
      await pc.close();
      await pc.dispose();
    }
    await _ice.close();
    await _state.close();
    await _negotiation.close();
    await _remoteVideo.close();
    // The call screen may still be drawing for a moment.
    Timer(const Duration(seconds: 1), () {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
      localRenderer.dispose();
      remoteRenderer.dispose();
    });
  }

  static String _micMessage(Object e) {
    final text = '$e'.toLowerCase();
    if (text.contains('notallowed') || text.contains('permission') || text.contains('denied')) {
      return 'Microphone is blocked. Allow it for GoThermo in the phone settings.';
    }
    if (text.contains('notfound')) return 'No microphone found.';
    if (text.contains('notreadable') || text.contains('busy')) return 'The microphone is busy in another app.';
    return 'Could not use the microphone.';
  }

  static String _cameraMessage(Object e) {
    final text = '$e'.toLowerCase();
    if (text.contains('notallowed') || text.contains('permission') || text.contains('denied')) {
      return 'Camera is blocked. Allow it for GoThermo in the phone settings.';
    }
    return 'The camera is not available.';
  }
}
