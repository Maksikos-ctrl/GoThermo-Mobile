import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoView, RTCVideoViewObjectFit;

import '../calls/webrtc_engine.dart';
import '../state/call_controller.dart';
import '../state/chat_controller.dart';
import '../util/time_format.dart';
import '../widgets/avatar.dart';

/// Full-screen call: ringing, connecting and talking. Closes itself when the
/// call is over.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.call, required this.chat});

  final CallController call;
  final ChatController chat;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _closing = false;

  static const _bg = Color(0xFF0E1320);
  static const _green = Color(0xFF23A55A);
  static const _red = Color(0xFFED4245);

  CallController get call => widget.call;

  @override
  void initState() {
    super.initState();
    call.addListener(_changed);
    _syncPulse();
  }

  @override
  void dispose() {
    call.removeListener(_changed);
    _pulse.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (call.phase == CallPhase.idle && !_closing) {
      _closing = true;
      Navigator.of(context).pop();
      return;
    }
    _syncPulse();
  }

  void _syncPulse() {
    final ringing = call.phase == CallPhase.calling || call.phase == CallPhase.ringing;
    if (ringing && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!ringing && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  String get _status {
    switch (call.phase) {
      case CallPhase.calling:
        return 'Calling...';
      case CallPhase.ringing:
        return call.incomingHasVideo ? 'Incoming video call' : 'Incoming voice call';
      case CallPhase.connecting:
        return 'Connecting...';
      case CallPhase.connected:
        final t = callLength(call.seconds);
        return call.remoteSharingScreen ? '$t  -  sharing their screen' : t;
      case CallPhase.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _bg,
        body: ListenableBuilder(
          listenable: call,
          builder: (context, _) {
            final who = call.remote ?? '';
            final peer = call.peer;
            final remoteView = call.remoteHasVideo && peer is WebRtcPeer
                ? RTCVideoView(peer.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : null;
            final localView = call.cameraOn && peer is WebRtcPeer
                ? RTCVideoView(peer.localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : null;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (remoteView != null) remoteView,
                if (remoteView != null) Container(color: Colors.black.withAlpha(60)),
                SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 28),
                      Text(who, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _status,
                          key: ValueKey<String>(call.phase == CallPhase.connected ? 'timer' : _status),
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                      Expanded(
                        child: remoteView != null
                            ? const SizedBox.shrink()
                            : Center(child: _pulsingAvatar(who)),
                      ),
                      _controls(),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
                if (localView != null)
                  Positioned(
                    right: 16,
                    top: 100,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(width: 104, height: 148, child: localView),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pulsingAvatar(String who) {
    const size = 140.0;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        return SizedBox(
          width: size * 2,
          height: size * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final delay in const [0.0, 0.5])
                Builder(builder: (context) {
                  final p = (t + delay) % 1.0;
                  return Opacity(
                    opacity: _pulse.isAnimating ? (1 - p) * 0.35 : 0,
                    child: Container(
                      width: size * (1 + p * 0.9),
                      height: size * (1 + p * 0.9),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    ),
                  );
                }),
              child!,
            ],
          ),
        );
      },
      child: Avatar(username: who, picture: widget.chat.avatarOf(who), size: size),
    );
  }

  Widget _controls() {
    if (call.phase == CallPhase.ringing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Round(
            key: const Key('call-decline'),
            icon: Icons.call_end,
            label: 'Decline',
            color: _red,
            onTap: call.decline,
          ),
          _Round(
            key: const Key('call-accept'),
            icon: call.incomingHasVideo ? Icons.videocam : Icons.call,
            label: 'Accept',
            color: _green,
            onTap: call.accept,
          ),
        ],
      );
    }
    final working = call.phase == CallPhase.connected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Round(
              key: const Key('call-speaker'),
              icon: call.speakerOn ? Icons.volume_up : Icons.hearing,
              label: call.speakerOn ? 'Speaker' : 'Earpiece',
              active: call.speakerOn,
              onTap: call.toggleSpeaker,
            ),
            _Round(
              key: const Key('call-camera'),
              icon: call.cameraOn ? Icons.videocam : Icons.videocam_off,
              label: 'Camera',
              active: call.cameraOn,
              onTap: working ? call.toggleCamera : null,
            ),
            _Round(
              key: const Key('call-mute'),
              icon: call.muted ? Icons.mic_off : Icons.mic,
              label: call.muted ? 'Unmute' : 'Mute',
              active: call.muted,
              onTap: call.toggleMute,
            ),
            if (call.cameraOn)
              _Round(
                key: const Key('call-flip'),
                icon: Icons.cameraswitch,
                label: 'Flip',
                onTap: call.switchCamera,
              ),
          ],
        ),
        const SizedBox(height: 28),
        _Round(
          key: const Key('call-end'),
          icon: Icons.call_end,
          label: 'End',
          color: _red,
          big: true,
          onTap: call.end,
        ),
      ],
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.active = false,
    this.big = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool active;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final size = big ? 68.0 : 58.0;
    final fill = color ?? (active ? Colors.white : Colors.white.withAlpha(36));
    final ink = color != null || !active ? Colors.white : const Color(0xFF0E1320);
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: fill,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: size, height: size, child: Icon(icon, color: ink, size: big ? 32 : 26)),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
