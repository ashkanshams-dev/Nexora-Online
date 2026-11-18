import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Offline quiz feedback using the app's bundled arcade SFX.
class QuizAudio {
  QuizAudio({required bool enabled}) : _enabled = enabled;

  static const String _dir = 'games/bermuda/sfx/';
  static const Map<String, String> _files = <String, String>{
    'tap': 'select.wav',
    'correct': 'goal.wav',
    'wrong': 'hit_ball.wav',
    'timeout': 't_wall.wav',
    'finish': 'gameIsFinishedWistle.mp3',
  };

  final List<AudioPlayer> _players = <AudioPlayer>[];
  bool _enabled;
  int _next = 0;
  bool _ready = false;

  Future<void> init() async {
    if (_ready || _isWeb || _isTest) return;
    _ready = true;
    try {
      for (int i = 0; i < 2; i++) {
        final AudioPlayer player = AudioPlayer(playerId: 'nx_quiz_$i');
        await player.setAudioContext(
          AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
              .build(),
        );
        await player.setReleaseMode(ReleaseMode.stop);
        _players.add(player);
      }
    } catch (error) {
      debugPrint('nx quiz audio init: $error');
      await dispose();
    }
  }

  Future<void> play(String event, {double volume = 0.8}) async {
    if (!_enabled || !_ready || _players.isEmpty) return;
    final String? file = _files[event];
    if (file == null) return;
    final AudioPlayer player = _players[_next++ % _players.length];
    try {
      await player.stop();
      await player.play(AssetSource('$_dir$file'),
          volume: volume.clamp(0.0, 1.0).toDouble());
    } catch (error) {
      debugPrint('nx quiz audio play($event): $error');
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

  bool get _isWeb => kIsWeb;
  bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');
}
