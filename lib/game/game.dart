// Flame host for a match: owns the frame loop (Flame's ticker) and paints the
// MatchRenderer. The simulation step itself is injected (offline: Engine.update; online: the net controller).
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import 'engine.dart';
import 'render.dart';

class MatchGame extends FlameGame {
  final Engine e;
  MatchRenderer? r;
  final void Function(double dt) onTick;
  double _t = 0;
  bool paused = false;

  // perf probes for the debug overlay
  double frameMs = 0, stepMs = 0;
  final Stopwatch _sw = Stopwatch();

  MatchGame({required this.e, required this.onTick});

  MatchView? get view => r?.v;

  @override
  ui.Color backgroundColor() => const ui.Color(0xff02040c);

  // v5 smoother motion: vsync deltas jitter by a few ms on Android, which makes the fixed-step interpolation stutter.
  // A light low-pass on dt evens the frame pacing; real hitches (> 2x the average) pass through unfiltered so the
  // simulation never drifts from wall-clock time for more than a frame.
  // v6: the time the filter holds back (or runs ahead) is carried and paid back a little each frame, so the
  // simulation stays locked to wall-clock time (no slow drift) while the per-frame step stays even.
  double _dtAvg = 1 / 60, _carry = 0;
  double _smooth(double dt) {
    if (dt <= 0) return dt;
    if (dt > _dtAvg * 2 || dt < _dtAvg * .5) {
      _dtAvg = _dtAvg * .7 + dt.clamp(1 / 240, 1 / 20) * .3;
      _carry = 0;
      return dt;
    }
    _dtAvg = _dtAvg * .85 + dt * .15;
    _carry += dt - _dtAvg;
    final pay = _carry.clamp(-_dtAvg * .1, _dtAvg * .1);
    _carry -= pay;
    return _dtAvg + pay;
  }

  @override
  void update(double rawDt) {
    super.update(rawDt);
    final dt = _smooth(rawDt);
    _t += dt;
    if (!paused) {
      _sw
        ..reset()
        ..start();
      onTick(dt);
      _sw.stop();
      stepMs = stepMs * .9 + _sw.elapsedMicroseconds / 1000 * .1;
    }
    frameMs = frameMs * .9 + rawDt * 1000 * .1;
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    r?.render(canvas, _t);
  }

  /// screen (logical px) -> world units
  Offset? toWorld(Offset p) => r?.v.toWorld(p.dx, p.dy);
}
