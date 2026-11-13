// Sound + haptics — port of src/sound.ts (same files, volumes, pools, scenes and voice ducking).
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/services.dart';

enum Sfx { ui, hitb, hitp, goal, post, roar, whistle, finalW, wall, crowd, music, ready, chat, join, leave, win, lose, tick }

const Map<Sfx, (String, double, int)> _MAP = {
  Sfx.ui: ('select.wav', .55, 2), Sfx.hitb: ('hit_ball.wav', .9, 3), Sfx.hitp: ('hit_piece.mp3', .7, 3), Sfx.goal: ('goal.wav', .9, 1),
  Sfx.post: ('ballHitsThePost.mp3', .8, 1), Sfx.roar: ('goalHappened-01.mp3', .7, 1), Sfx.whistle: ('startWistle.mp3', .8, 1),
  Sfx.finalW: ('gameIsFinishedWistle.mp3', .8, 1), Sfx.wall: ('BallHit-01.mp3', .55, 2), Sfx.crowd: ('crowd-03.mp3', .25, 1),
  Sfx.music: ('music.mp3', .35, 1), Sfx.ready: ('nx_ready.mp3', .7, 1), Sfx.chat: ('nx_chat.mp3', .55, 2), Sfx.join: ('nx_join.mp3', .6, 1),
  Sfx.leave: ('nx_leave.mp3', .5, 1), Sfx.win: ('nx_win.mp3', .8, 1), Sfx.lose: ('nx_lose.mp3', .75, 1), Sfx.tick: ('nx_tick.mp3', .45, 2),
};

final Map<Sfx, AudioPool> _pools = {};
final Map<Sfx, int> _last = {};
bool _sound = true, _music = true, _haptics = true;
double _volume = 1;
bool _inited = false;
AudioPlayer? _musicP, _crowdP;

Future<void> initSound() async {
  if (_inited) return;
  _inited = true;
  FlameAudio.updatePrefix('assets/g/sfx/');
  for (final e in _MAP.entries) {
    if (e.key == Sfx.music || e.key == Sfx.crowd) continue;
    try {
      _pools[e.key] = await FlameAudio.createPool(e.value.$1, maxPlayers: e.value.$3, minPlayers: 1);
    } catch (_) {}
  }
}

void setAudioPrefs({required bool sound, required bool music, required bool haptics, double volume = 1}) {
  _sound = sound;
  _music = music;
  _haptics = haptics;
  _volume = volume.clamp(0, 1).toDouble();
  _crowdP?.setVolume(_MAP[Sfx.crowd]!.$2 * _volume);
  _applyMusic();
}

void sfx(Sfx k, [double vol = 1]) {
  if (!_sound || _volume <= 0) return;
  final pool = _pools[k];
  if (pool == null) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (k != Sfx.goal && now - (_last[k] ?? 0) < 45) return;
  _last[k] = now;
  pool.start(volume: (_MAP[k]!.$2 * (vol < .15 ? .15 : vol) * _volume).clamp(0, 1).toDouble());
}

enum AudioScene { menu, room, match }

AudioScene _scene = AudioScene.menu;
final Set<String> _voices = {};

Future<void> _applyMusic() async {
  final want = _sound && _music && _volume > 0 && _scene == AudioScene.menu && _voices.isEmpty;
  try {
    if (!want) {
      await _musicP?.pause();
      return;
    }
    if (_musicP == null) {
      _musicP = await FlameAudio.loopLongAudio('music.mp3', volume: _MAP[Sfx.music]!.$2 * _volume);
    } else {
      await _musicP!.setVolume(_MAP[Sfx.music]!.$2 * _volume);
      await _musicP!.resume();
    }
  } catch (_) {}
}

void setAudioScene(AudioScene s) {
  if (_scene == s) return;
  _scene = s;
  _applyMusic();
}

void setVoiceActive(String id, bool on) {
  final had = _voices.contains(id);
  on ? _voices.add(id) : _voices.remove(id);
  if (had != on) _applyMusic();
}

Future<void> playLoop(Sfx k) async {
  if (k == Sfx.music) return _applyMusic();
  if (!_sound || _volume <= 0) return;
  try {
    _crowdP ??= await FlameAudio.loopLongAudio('crowd-03.mp3', volume: _MAP[Sfx.crowd]!.$2 * _volume);
    await _crowdP!.resume();
  } catch (_) {}
}

void stopLoop(Sfx k) {
  if (k == Sfx.music) {
    _musicP?.pause();
  } else {
    _crowdP?.pause();
  }
}

enum Buzz { light, medium, heavy, success }

void buzz([Buzz kind = Buzz.light]) {
  if (!_haptics) return;
  switch (kind) {
    case Buzz.light:
      HapticFeedback.lightImpact();
    case Buzz.medium:
      HapticFeedback.mediumImpact();
    case Buzz.heavy:
      HapticFeedback.heavyImpact();
    case Buzz.success:
      HapticFeedback.vibrate();
  }
}
