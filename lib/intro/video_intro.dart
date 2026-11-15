// v4 launch intro (owner request 2026-11-14): the owner videos, complete and in order:
//   assets/video/intro1.mp4 (544x960, 12.25 s: spaceship through the portal to the NeXora logo)
//   assets/video/intro2.mp4 (512x768, 10.04 s: a character walks the tunnel into the NEXORA base)
//   assets/video/intro3.mp4 (720x720, 5.7 s, owner's third clip added for v0.6.1; re-encoded H.264 main)
// Full-screen BoxFit.cover centred on a black background (no stretch on any aspect). Each next clip is initialised while
// the current one plays and all stay stacked, so the hand-over is just a visibility swap (no black gap). Skip appears
// after ~1 s and goes straight home. If a video can't initialise, [onFail] runs (the Flutter cinematic fallback).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/sound.dart';

class VideoIntro extends StatefulWidget {
  final VoidCallback onDone, onFail;
  const VideoIntro({super.key, required this.onDone, required this.onFail});
  static const clips = ['assets/video/intro1.mp4', 'assets/video/intro2.mp4', 'assets/video/intro3.mp4'];
  @override
  State<VideoIntro> createState() => _VideoIntroState();
}

class _VideoIntroState extends State<VideoIntro> {
  final List<VideoPlayerController> _c = [for (final p in VideoIntro.clips) VideoPlayerController.asset(p)];
  final List<bool> _ready = [for (final _ in VideoIntro.clips) false];
  int _cur = 0;
  bool _skip = false, _done = false;
  Timer? _skipT, _guard;

  @override
  void initState() {
    super.initState();
    Sound.scene(AudioScene.match); // the menu music waits until the intro is over
    _skipT = Timer(const Duration(milliseconds: 1000), () => mounted ? setState(() => _skip = true) : null);
    // if the first clip hasn't started within 6 s, use the fallback cinematic
    _guard = Timer(const Duration(seconds: 6), () {
      if (!_ready[0]) _fail();
    });
    _init(0).then((ok) {
      if (!ok) return _fail();
      _c[0].play();
      _init(1); // pre-initialise the next clip while this one plays
    });
    for (var i = 0; i < _c.length; i++) {
      _c[i].addListener(() => _watch(i));
    }
  }

  Future<bool> _init(int i) async {
    try {
      await _c[i].initialize();
      await _c[i].setLooping(false);
      if (mounted) setState(() => _ready[i] = true);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _watch(int i) {
    if (_done || i != _cur) return;
    final v = _c[i].value;
    if (v.hasError) return i == 0 ? _fail() : _finish();
    final end = v.isInitialized && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 40) && !v.isPlaying;
    if (!end) return;
    final n = i + 1;
    if (n >= _c.length) return _finish();
    void go() {
      _c[n].play();
      setState(() => _cur = n);
      if (n + 1 < _c.length) _init(n + 1); // pre-initialise the clip after it
    }

    if (_ready[n]) {
      go();
    } else {
      // next clip still initialising: wait for it (rare), else finish
      _init(n).then((ok) {
        if (_done) return;
        if (!ok) return _finish();
        go();
      });
    }
  }

  void _fail() {
    if (_done) return;
    _done = true;
    Sound.scene(AudioScene.menu);
    widget.onFail();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    for (final c in _c) {
      c.pause();
    }
    Sound.scene(AudioScene.menu);
    widget.onDone();
  }

  @override
  void dispose() {
    _skipT?.cancel();
    _guard?.cancel();
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _clip(int i) {
    final c = _c[i];
    if (!_ready[i]) return const SizedBox.shrink();
    final s = c.value.size;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: s.width, height: s.height, child: VideoPlayer(c)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        // both clips stay in the tree; only the current one is visible (seamless swap)
        for (var i = _c.length - 1; i >= 0; i--) Offstage(offstage: _cur != i, child: _clip(i)),
        Positioned(
          top: pad.top + 12,
          left: 14,
          child: AnimatedOpacity(
            opacity: _skip ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_skip,
              child: GestureDetector(
                onTap: _finish,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0x8c000000), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x66ffffff))),
                  child: const Text('رد کردن  ›', textDirection: TextDirection.rtl, style: TextStyle(color: Colors.white, fontFamily: 'Vazirmatn', fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
