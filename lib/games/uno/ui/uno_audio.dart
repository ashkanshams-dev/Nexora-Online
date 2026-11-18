import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// NX Cards SFX, independent from haptics and global music.
class UnoAudio {
  UnoAudio({required bool enabled}) : _enabled = enabled;

  static const String assetDir = 'games/bermuda/sfx/';
  static const Map<String, String> eventFiles = <String, String>{
    'deal': 'select.wav',
    'play': 'hit_piece.mp3',
    'draw': 't_launch.wav',
    'action': 't_wall.wav',
    'nx': 'goalAnnounce.mp3',
    'caught': 'ballHitsThePost.mp3',
    'reshuffle': 'startWistle.mp3',
    'win': 'gameIsFinishedWistle.mp3',
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
        final AudioPlayer player = AudioPlayer(playerId: 'nx_uno_$i');
        await player.setAudioContext(
          AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
              .build(),
        );
        await player.setReleaseMode(ReleaseMode.stop);
        _players.add(player);
      }
    } catch (error) {
      debugPrint('nx uno audio init: $error');
      await dispose();
    }
  }

  void setEnabled(bool value) => _enabled = value;

  Future<void> play(String event, {double volume = 0.8}) async {
    if (!_enabled || !_ready || _players.isEmpty) return;
    final String? file = eventFiles[event];
    if (file == null) return;
    final AudioPlayer player = _players[_next++ % _players.length];
    try {
      await player.stop();
      await player.play(AssetSource('$assetDir$file'),
          volume: volume.clamp(0.0, 1.0).toDouble());
    } catch (error) {
      debugPrint('nx uno audio play($event): $error');
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
