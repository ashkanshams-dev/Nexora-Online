import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Lightweight Ludo SFX adapter. Music remains owned by MusicService; this
/// adapter only plays game effects and follows GameLaunch.soundOn.
class LudoAudio {
  LudoAudio({required bool enabled}) : _enabled = enabled;

  static const String _dir = 'games/bermuda/sfx/';
  static const Map<String, String> _files = <String, String>{
    'ui': 'select.wav',
    'roll': 't_launch.wav',
    'step': 'hit_piece.mp3',
    'capture': 'hit_ball.wav',
    'home': 'goal.wav',
    'finish': 'gameIsFinishedWistle.mp3',
  };

  final List<AudioPlayer> _players = <AudioPlayer>[];
  bool _enabled;
  int _next = 0;
  bool _ready = false;
  bool get enabled => _enabled;

  Future<void> init() async {
    if (_ready || !_audioSupported) return;
    _ready = true;
    try {
      for (int i = 0; i < 3; i++) {
        final AudioPlayer player = AudioPlayer(playerId: 'nx_ludo_$i');
        await player.setAudioContext(
            AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
                .build());
        await player.setReleaseMode(ReleaseMode.stop);
        _players.add(player);
      }
    } catch (e) {
      debugPrint('nx ludo audio init: $e');
      await dispose();
    }
  }

  void setEnabled(bool value) => _enabled = value;

  Future<void> play(String event, {double volume = 0.8}) async {
    if (!_enabled || !_ready || _players.isEmpty) return;
    final String? file = _files[event];
    if (file == null) return;
    final AudioPlayer player = _players[_next++ % _players.length];
    try {
      await player.stop();
      await player.play(AssetSource('$_dir$file'),
          volume: volume.clamp(0.0, 1.0).toDouble());
    } catch (e) {
      debugPrint('nx ludo audio play($event): $e');
    }
  }

  Future<void> dispose() async {
    final List<AudioPlayer> players = List<AudioPlayer>.from(_players);
    _players.clear();
    _ready = false;
    for (final AudioPlayer player in players) {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  bool get _audioSupported =>
      !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');
}
