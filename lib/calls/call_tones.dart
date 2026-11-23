import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'call_types.dart';

/// Ringtone and ringback: a looping sound, plus vibration for incoming calls.
class PlatformCallTones implements CallTones {
  AudioPlayer? _player;
  Timer? _buzz;

  Future<void> _play(String asset, {required bool vibrate}) async {
    stop();
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource(asset));
    } on Object {
      // No sound is better than a failed call.
    }
    if (vibrate) {
      HapticFeedback.vibrate();
      _buzz = Timer.periodic(const Duration(milliseconds: 1600), (_) => HapticFeedback.vibrate());
    }
  }

  @override
  void ringing() => unawaited(_play('sounds/ring.wav', vibrate: true));

  @override
  void ringback() => unawaited(_play('sounds/ringback.wav', vibrate: false));

  @override
  void stop() {
    _buzz?.cancel();
    _buzz = null;
    final player = _player;
    if (player != null) unawaited(player.stop().catchError((Object _) {}));
  }
}
