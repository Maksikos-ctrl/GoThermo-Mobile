import 'dart:async';

import 'package:gothermo_mobile/calls/call_types.dart';

class FakePeer implements CallPeer {
  final ice = StreamController<Ice>.broadcast();
  final states = StreamController<PeerState>.broadcast();
  final negotiation = StreamController<void>.broadcast();
  final remoteVideo = StreamController<bool>.broadcast();

  final List<String> log = [];
  CallMediaException? openError;
  CallMediaException? cameraError;
  bool closed = false;
  bool muted = false;
  bool camera = false;

  @override
  Stream<Ice> get onIce => ice.stream;
  @override
  Stream<PeerState> get onState => states.stream;
  @override
  Stream<void> get onNegotiationNeeded => negotiation.stream;
  @override
  Stream<bool> get onRemoteVideo => remoteVideo.stream;

  @override
  Future<void> open() async {
    log.add('open');
    final e = openError;
    if (e != null) throw e;
  }

  @override
  Future<Sdp> createOffer() async => const Sdp('offer', 'v=0 offer');

  @override
  Future<Sdp> answer(Sdp offer) async {
    log.add('answer:${offer.sdp}');
    return const Sdp('answer', 'v=0 answer');
  }

  @override
  Future<void> setAnswer(Sdp answer) async => log.add('setAnswer:${answer.sdp}');

  @override
  Future<void> addIce(Ice candidate) async => log.add('ice:${candidate.candidate}');

  @override
  void setMuted(bool value) => muted = value;

  @override
  Future<void> setCamera(bool on) async {
    final e = cameraError;
    if (e != null) throw e;
    camera = on;
    log.add('camera:$on');
  }

  @override
  Future<void> setSpeaker(bool on) async => log.add('speaker:$on');

  @override
  Future<void> switchCamera() async => log.add('switch');

  @override
  Future<void> close() async => closed = true;
}

class FakeEngine implements CallEngine {
  final peers = <FakePeer>[];
  CallMediaException? openError;
  List<Map<String, dynamic>>? lastServers;

  @override
  CallPeer create(List<Map<String, dynamic>> iceServers) {
    lastServers = iceServers;
    final p = FakePeer()..openError = openError;
    peers.add(p);
    return p;
  }

  FakePeer get peer => peers.last;
}
