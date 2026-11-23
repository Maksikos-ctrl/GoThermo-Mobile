import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/calls/call_types.dart';
import 'package:gothermo_mobile/state/call_controller.dart';

import 'support/call_fakes.dart';
import 'support/fakes.dart';

class Rig {
  Rig({Duration? ringTimeout}) {
    controller = CallController(
      me: 'ann',
      engine: engine,
      sendSignal: (type, payload) => sent.add((type, payload)),
      loadIceServers: () async => [
        {'urls': ['stun:x'], 'username': 'u', 'credential': 'c'},
      ],
      logCall: (who, outcome, seconds) async => logs.add((who, outcome, seconds)),
      tones: tones,
      ringTimeout: ringTimeout,
    );
  }

  final engine = FakeEngine();
  final tones = SilentTones();
  final sent = <(String, Map<String, dynamic>)>[];
  final logs = <(String, CallOutcome, int)>[];
  late final CallController controller;

  List<String> get types => sent.map((s) => s.$1).toList();

  Map<String, dynamic> last(String type) => sent.lastWhere((s) => s.$1 == type).$2;

  void signal(String type, Map<String, dynamic> payload) =>
      controller.handleSignal(type, {'to': 'ann', 'from': 'bob', ...payload});

  Future<void> ready() => settle(10);
}

void main() {
  group('outgoing call', () {
    test('offers, rings, connects, then hangs up and is logged', () async {
      final r = Rig();
      await r.controller.start('bob');
      await r.ready();

      expect(r.controller.phase, CallPhase.calling);
      expect(r.tones.last, 'ringback');
      expect(r.types, ['call_offer']);
      final offer = r.last('call_offer');
      expect(offer['to'], 'bob');
      expect(offer['from'], 'ann');
      expect(offer['wantsVideo'], false);
      expect((offer['sdp'] as Map)['type'], 'offer');
      expect(r.engine.lastServers, isNotEmpty);

      r.signal('call_answer', {'sdp': {'type': 'answer', 'sdp': 'v=0 answer'}});
      await r.ready();
      expect(r.controller.phase, CallPhase.connecting);
      expect(r.tones.last, isNull);
      expect(r.engine.peer.log, contains('setAnswer:v=0 answer'));

      r.engine.peer.states.add(PeerState.connected);
      await r.ready();
      expect(r.controller.phase, CallPhase.connected);

      r.controller.end();
      await r.ready();
      expect(r.types.last, 'call_end');
      expect(r.controller.phase, CallPhase.idle);
      expect(r.engine.peer.closed, isTrue);
      expect(r.logs.length, 1);
      expect(r.logs.first.$1, 'bob');
      expect(r.logs.first.$2, CallOutcome.completed);
      r.controller.dispose();
    });

    test('local network candidates go to the other person', () async {
      final r = Rig();
      await r.controller.start('bob');
      r.engine.peer.ice.add(const Ice('cand1', '0', 0));
      await r.ready();
      final c = r.last('call_ice_candidate');
      expect(c['to'], 'bob');
      expect((c['candidate'] as Map)['candidate'], 'cand1');
      r.controller.dispose();
    });

    test('candidates that arrive before the answer wait for it', () async {
      final r = Rig();
      await r.controller.start('bob');
      r.signal('call_ice_candidate', {
        'candidate': {'candidate': 'early', 'sdpMid': '0', 'sdpMLineIndex': 0},
      });
      await r.ready();
      expect(r.engine.peer.log.contains('ice:early'), isFalse);

      r.signal('call_answer', {'sdp': {'type': 'answer', 'sdp': 'a'}});
      await r.ready();
      expect(r.engine.peer.log, contains('ice:early'));
      r.controller.dispose();
    });

    test('declined by the other side is logged as declined', () async {
      final r = Rig();
      await r.controller.start('bob');
      r.signal('call_reject', {});
      await r.ready();
      expect(r.controller.phase, CallPhase.idle);
      expect(r.logs.single.$2, CallOutcome.declined);
      r.controller.dispose();
    });

    test('cancelling before an answer is logged as cancelled', () async {
      final r = Rig();
      await r.controller.start('bob');
      r.controller.end();
      await r.ready();
      expect(r.types, ['call_offer', 'call_end']);
      expect(r.logs.single.$2, CallOutcome.cancelled);
      r.controller.dispose();
    });

    test('nobody answers: gives up and tells them', () async {
      final r = Rig(ringTimeout: const Duration(milliseconds: 40));
      await r.controller.start('bob');
      await settle(120);
      expect(r.controller.phase, CallPhase.idle);
      expect(r.types.last, 'call_end');
      expect(r.controller.error, 'No answer');
      expect(r.logs.single.$2, CallOutcome.cancelled);
      r.controller.dispose();
    });

    test('a blocked microphone stops the call before anything is sent or logged', () async {
      final r = Rig();
      r.engine.openError = CallMediaException('Microphone is blocked.');
      await r.controller.start('bob');
      await r.ready();
      expect(r.controller.phase, CallPhase.idle);
      expect(r.controller.error, 'Microphone is blocked.');
      expect(r.sent, isEmpty);
      expect(r.logs, isEmpty);
      r.controller.dispose();
    });

    test('a video call asks for video and turns the camera on once connected', () async {
      final r = Rig();
      await r.controller.start('bob', video: true);
      expect(r.last('call_offer')['wantsVideo'], true);
      r.signal('call_answer', {'sdp': {'type': 'answer', 'sdp': 'a'}});
      await r.ready();
      expect(r.engine.peer.camera, isFalse);
      r.engine.peer.states.add(PeerState.connected);
      await r.ready();
      expect(r.engine.peer.camera, isTrue);
      expect(r.controller.cameraOn, isTrue);
      r.controller.dispose();
    });

    test('a second call cannot be started while one is going', () async {
      final r = Rig();
      await r.controller.start('bob');
      await r.controller.start('cy');
      expect(r.controller.remote, 'bob');
      expect(r.controller.error, 'You are already in a call');
      expect(r.engine.peers.length, 1);
      r.controller.dispose();
    });
  });

  group('incoming call', () {
    test('rings, answers, connects; the caller hanging up ends it without a log', () async {
      final r = Rig();
      r.signal('call_offer', {'sdp': {'type': 'offer', 'sdp': 'theirs'}, 'wantsVideo': true});
      await r.ready();
      expect(r.controller.phase, CallPhase.ringing);
      expect(r.controller.remote, 'bob');
      expect(r.controller.incomingHasVideo, isTrue);
      expect(r.tones.last, 'ringing');

      await r.controller.accept();
      await r.ready();
      expect(r.controller.phase, CallPhase.connecting);
      expect(r.tones.last, isNull);
      expect(r.engine.peer.log, contains('answer:theirs'));
      final a = r.last('call_answer');
      expect(a['to'], 'bob');
      expect((a['sdp'] as Map)['type'], 'answer');

      r.engine.peer.states.add(PeerState.connected);
      await r.ready();
      expect(r.controller.phase, CallPhase.connected);

      r.signal('call_end', {});
      await r.ready();
      expect(r.controller.phase, CallPhase.idle);
      expect(r.logs, isEmpty);
      r.controller.dispose();
    });

    test('candidates that beat the offer are kept for the call', () async {
      final r = Rig();
      r.signal('call_ice_candidate', {
        'candidate': {'candidate': 'first', 'sdpMid': '0', 'sdpMLineIndex': 0},
      });
      r.signal('call_offer', {'sdp': {'type': 'offer', 'sdp': 'theirs'}});
      await r.ready();
      await r.controller.accept();
      await r.ready();
      final log = r.engine.peer.log;
      expect(log, contains('ice:first'));
      expect(log.indexOf('answer:theirs') < log.indexOf('ice:first'), isTrue);
      r.controller.dispose();
    });

    test('our candidates wait until the offer is out', () async {
      final r = Rig();
      final started = r.controller.start('bob');
      await settle(1);
      r.engine.peer.ice.add(const Ice('c', '0', 0));
      await started;
      await r.ready();
      expect(r.types.contains('call_ice_candidate'), isTrue);
      expect(r.types.indexOf('call_offer') < r.types.indexOf('call_ice_candidate'), isTrue);
      r.controller.dispose();
    });

    test('declining tells the caller', () async {
      final r = Rig();
      r.signal('call_offer', {'sdp': {'type': 'offer', 'sdp': 'theirs'}});
      r.controller.decline();
      await r.ready();
      expect(r.types, ['call_reject']);
      expect(r.last('call_reject')['to'], 'bob');
      expect(r.controller.phase, CallPhase.idle);
      expect(r.tones.last, isNull);
      expect(r.logs, isEmpty);
      r.controller.dispose();
    });

    test('the caller giving up while it rings clears the screen', () async {
      final r = Rig();
      r.signal('call_offer', {'sdp': {'type': 'offer', 'sdp': 'theirs'}});
      r.signal('call_end', {});
      await r.ready();
      expect(r.controller.phase, CallPhase.idle);
      r.controller.dispose();
    });

    test('a call while busy is turned away', () async {
      final r = Rig();
      await r.controller.start('bob');
      r.controller.handleSignal('call_offer', {
        'to': 'ann',
        'from': 'cy',
        'sdp': {'type': 'offer', 'sdp': 'x'},
      });
      await r.ready();
      final reject = r.sent.lastWhere((s) => s.$1 == 'call_reject').$2;
      expect(reject['to'], 'cy');
      expect(r.controller.remote, 'bob');
      r.controller.dispose();
    });

    test('a blocked microphone on answering rejects the call', () async {
      final r = Rig();
      r.engine.openError = CallMediaException('No microphone found.');
      r.signal('call_offer', {'sdp': {'type': 'offer', 'sdp': 'theirs'}});
      await r.controller.accept();
      await r.ready();
      expect(r.types.contains('call_reject'), isTrue);
      expect(r.controller.phase, CallPhase.idle);
      expect(r.controller.error, 'No microphone found.');
      r.controller.dispose();
    });

    test('signals meant for someone else, or broken ones, are ignored', () async {
      final r = Rig();
      r.controller.handleSignal('call_offer', {
        'to': 'zed',
        'from': 'bob',
        'sdp': {'type': 'offer', 'sdp': 'x'},
      });
      r.controller.handleSignal('call_offer', {'to': 'ann', 'from': 'bob', 'sdp': 'nonsense'});
      r.controller.handleSignal('call_offer', 'nonsense');
      await r.ready();
      expect(r.controller.phase, CallPhase.idle);
      expect(r.sent, isEmpty);
      r.controller.dispose();
    });
  });

  group('during a call', () {
    Future<Rig> connected() async {
      final r = Rig();
      await r.controller.start('bob');
      r.signal('call_answer', {'sdp': {'type': 'answer', 'sdp': 'a'}});
      await r.ready();
      r.engine.peer.states.add(PeerState.connected);
      await r.ready();
      return r;
    }

    test('mute and speaker toggles reach the connection', () async {
      final r = await connected();
      r.controller.toggleMute();
      expect(r.engine.peer.muted, isTrue);
      await r.controller.toggleSpeaker();
      expect(r.engine.peer.log, contains('speaker:true'));
      r.controller.dispose();
    });

    test('turning the camera on mid-call makes a new offer; theirs is answered', () async {
      final r = await connected();
      await r.controller.toggleCamera();
      r.engine.peer.negotiation.add(null);
      await r.ready();
      expect(r.last('call_renegotiate_offer')['to'], 'bob');

      r.signal('call_renegotiate_answer', {'sdp': {'type': 'answer', 'sdp': 'b'}});
      await r.ready();
      expect(r.engine.peer.log, contains('setAnswer:b'));

      r.signal('call_renegotiate_offer', {'sdp': {'type': 'offer', 'sdp': 'c'}});
      await r.ready();
      expect(r.engine.peer.log, contains('answer:c'));
      expect(r.last('call_renegotiate_answer')['to'], 'bob');
      r.controller.dispose();
    });

    test('a blocked camera is reported and the call goes on', () async {
      final r = await connected();
      r.engine.peer.cameraError = CallMediaException('Camera is blocked.');
      await r.controller.toggleCamera();
      expect(r.controller.error, 'Camera is blocked.');
      expect(r.controller.cameraOn, isFalse);
      expect(r.controller.phase, CallPhase.connected);
      r.controller.dispose();
    });

    test('the other side\'s video and screen sharing show up', () async {
      final r = await connected();
      r.engine.peer.remoteVideo.add(true);
      r.signal('call_screen_share_status', {'sharing': true});
      await r.ready();
      expect(r.controller.remoteHasVideo, isTrue);
      expect(r.controller.remoteSharingScreen, isTrue);
      r.signal('call_screen_share_status', {'sharing': false});
      expect(r.controller.remoteSharingScreen, isFalse);
      r.controller.dispose();
    });

    test('a failed connection ends the call with a message', () async {
      final r = await connected();
      r.engine.peer.states.add(PeerState.failed);
      await r.ready();
      expect(r.controller.phase, CallPhase.idle);
      expect(r.controller.error, contains('could not connect'));
      expect(r.logs.single.$2, CallOutcome.completed);
      r.controller.dispose();
    });
  });
}
