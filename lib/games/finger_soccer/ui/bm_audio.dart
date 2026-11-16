// Sounds of game.js (SFXF table, tone() blips rendered to small wav files, crowd loop, menu music).
import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

const String _dir = 'games/bermuda/sfx/';

/// [file, base volume] exactly as SFXF in game.js, plus the synthesized tone() blips.
const Map<String, List<Object>> _sfxf = <String, List<Object>>{
  'ui': <Object>['select.wav', 1.7],
  'hitb': <Object>['hit_ball.wav', 1.0],
  'hitp': <Object>['hit_piece.mp3', 1.0],
  'goal': <Object>['goal.wav', 2.4],
  'post': <Object>['ballHitsThePost.mp3', 1.2],
  'ann': <Object>['goalAnnounce.mp3', 1.3],
  'crowd': <Object>['crowd-03.mp3', .8],
  'whs': <Object>['startWistle.mp3', 1.0],
  'fin': <Object>['gameIsFinishedWistle.mp3', 1.0],
  'hb1': <Object>['BallHit-01.mp3', 1.0],
  'hb2': <Object>['BallHit-02.mp3', 1.0],
  'hb3': <Object>['BallHit-03.mp3', 1.0],
  't_wall': <Object>['t_wall.wav', 1.0],
  't_launch': <Object>['t_launch.wav', 1.0],
  't_post': <Object>['t_post.wav', 1.0],
  't_goal': <Object>['t_goal.wav', 1.0],
};

class BmAudio {
  BmAudio({required this.enabled});

  final bool enabled;
  final Map<String, AudioPool> _pools = <String, AudioPool>{};
  final Map<String, int> _ts = <String, int>{};
  final math.Random _r = math.Random();
  AudioPlayer? _music;
  AudioPlayer? _crowd;
  bool _crowdOn = false;
  bool _disposed = false;
  bool muted = false;

  Future<void> init() async {
    if (!enabled) return;
    for (final MapEntry<String, List<Object>> e in _sfxf.entries) {
      try {
        final int n = e.key.startsWith('h') || e.key == 't_wall' || e.key == 't_post' ? 4 : 2;
        final AudioPool p = await AudioPool.create(source: AssetSource('$_dir${e.value[0]}'), maxPlayers: n);
        if (_disposed) return;
        _pools[e.key] = p;
      } catch (err) {
        debugPrint('bermuda sfx ${e.key}: $err');
      }
    }
  }

  void _play(String k, double vol) {
    if (!enabled || muted || _disposed) return;
    final AudioPool? p = _pools[k];
    if (p == null) return;
    final double v = vol.clamp(0.0, 1.0).toDouble();
    unawaited(p.start(volume: v).then((_) {}, onError: (Object _) {}));
  }

  /// game.js sfx(k, v)
  void sfx(String k, [double v = 1]) {
    if (!enabled || muted) return;
    final int n = DateTime.now().millisecondsSinceEpoch;
    v = math.min(1.0, v);
    if (k != 'goal' && n - (_ts[k] ?? 0) < 45) return;
    _ts[k] = n;
    double b(String key) => (_sfxf[key]![1] as num).toDouble();
    switch (k) {
      case 'hitb':
        _play(<String>['hb1', 'hb2', 'hb3', 'hitb'][_r.nextInt(4)], (.35 + .65 * v) * b('hitb'));
        break;
      case 'hitp':
        _play('hitp', (.3 + .7 * v) * b('hitp'));
        break;
      case 'wall':
        _play('t_wall', .06 + .16 * v);
        break;
      case 'post':
        _play('post', b('post') * (.5 + .5 * v));
        break;
      case 'whs':
        _play('whs', b('whs'));
        break;
      case 'fin':
        _play('fin', b('fin'));
        break;
      case 'ui':
        _play('ui', b('ui'));
        break;
      case 'goal':
        _play('goal', b('goal'));
        _play('crowd', b('crowd'));
        _play('t_goal', 1);
        _after(.7, () => _play('ann', b('ann')));
        break;
    }
  }

  /// game.js tone() blips that are not covered by samples.
  void tone(String k) {
    if (k == 'launch') _play('t_launch', 1);
    if (k == 'post') _play('t_post', 1);
  }

  // Delays are driven by [frame] so no Timer outlives the widget.
  final List<MapEntry<double, void Function()>> _q = <MapEntry<double, void Function()>>[];
  double _clock = 0;
  void _after(double s, void Function() f) => _q.add(MapEntry<double, void Function()>(_clock + s, f));
  void frame(double dt) {
    _clock += dt;
    if (_q.isEmpty) return;
    final List<MapEntry<double, void Function()>> due = _q.where((MapEntry<double, void Function()> e) => e.key <= _clock).toList();
    _q.removeWhere((MapEntry<double, void Function()> e) => e.key <= _clock);
    for (final MapEntry<double, void Function()> e in due) {
      e.value();
    }
  }

  /// Menu music (game.js musicSync: plays while the menu is open, volume .4).
  Future<void> music(bool on) async {
    if (!enabled || _disposed) return;
    try {
      if (on && !muted) {
        final AudioPlayer m = _music ??= AudioPlayer();
        if (m.state == PlayerState.playing) return;
        await m.setReleaseMode(ReleaseMode.loop);
        await m.setVolume(.4);
        await m.play(AssetSource('${_dir}music.mp3'));
      } else {
        await _music?.pause();
      }
    } catch (e) {
      debugPrint('bermuda music: $e');
    }
  }

  /// Crowd ambience while a match is on (game.js crowdNext: random crowd clips at volume .3).
  Future<void> crowd(bool on) async {
    if (!enabled || _disposed) return;
    if (on == _crowdOn) return;
    _crowdOn = on;
    try {
      if (on && !muted) {
        if (_crowd == null) {
          final AudioPlayer c = AudioPlayer();
          _crowd = c;
          c.onPlayerComplete.listen((_) {
            if (_crowdOn && !_disposed) unawaited(_nextCrowd());
          });
        }
        await _nextCrowd();
      } else {
        await _crowd?.stop();
      }
    } catch (e) {
      debugPrint('bermuda crowd: $e');
    }
  }

  Future<void> _nextCrowd() async {
    final AudioPlayer? c = _crowd;
    if (c == null) return;
    await c.setVolume(.3);
    await c.play(AssetSource('${_dir}crowd-0${2 + _r.nextInt(2)}.mp3'));
  }

  void setMuted(bool m) {
    muted = m;
    if (m) {
      unawaited(music(false));
      unawaited(crowd(false));
    }
  }

  void dispose() {
    _disposed = true;
    _crowdOn = false;
    for (final AudioPool p in _pools.values) {
      unawaited(p.dispose().then((_) {}, onError: (Object _) {}));
    }
    _pools.clear();
    unawaited(_music?.dispose());
    unawaited(_crowd?.dispose());
  }
}
