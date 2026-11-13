// Flame host for the match: fixed-step engine + Canvas/FragmentShader renderer on the Flame game loop.
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'assets.dart';
import 'data.dart';
import 'engine.dart';
import 'render.dart';
import 'util.dart';

Future<ui.Image?> loadUiImage(String? path) async {
  if (path == null) return null;
  try {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

ui.FragmentProgram? _ballProg, _postProg;
Future<void> warmShaders() async {
  try {
    _ballProg ??= await ui.FragmentProgram.fromAsset('shaders/ball.frag');
    _postProg ??= await ui.FragmentProgram.fromAsset('shaders/post.frag');
  } catch (_) {}
}

class MatchGame extends FlameGame {
  final Engine eng;
  final List<Team> teams;
  final int ballIdx;
  final bool hq;
  /// per-frame hook (events, HUD, netcode) — runs right after the engine stepped
  final void Function(double dt)? onTick;
  /// whether the local engine should be advanced (false = an external driver steps it, e.g. online follower)
  bool Function() shouldStep;
  /// override for the step itself (online follower uses stepFollower)
  void Function(double dt)? stepper;
  late MatchRenderer r;
  GView? view;
  double topInset = 86, bottomInset = 22;
  double _t = 0;
  bool _ready = false;
  /// optional disc-art overrides (online discs / avatars)
  final String? t0Asset, t1Asset;

  MatchGame({required this.eng, required this.teams, required this.ballIdx, this.hq = true, this.onTick, bool Function()? shouldStep, this.stepper, this.t0Asset, this.t1Asset})
      : shouldStep = shouldStep ?? (() => true);

  @override
  Color backgroundColor() => const Color(0xFF02040C);

  @override
  Future<void> onLoad() async {
    await warmShaders();
    final f = eng.f;
    final im = MatchImages();
    final res = await Future.wait([
      loadUiImage(FIELD_IMG[f.id]),
      loadUiImage(GOAL_IMG[f.gs]),
      loadUiImage(BALL_IMG['b$ballIdx']),
      loadUiImage(t0Asset ?? teamImg(teamKey(teams[0]))),
      loadUiImage(t1Asset ?? teamImg(teamKey(teams[1]))),
      loadUiImage(ARROW_IMG['head_e']),
      loadUiImage(ARROW_IMG['head_s']),
      loadUiImage(ARROW_IMG['shaft_e']),
      loadUiImage(ARROW_IMG['shaft_s']),
    ]);
    im
      ..field = res[0]
      ..goal = res[1]
      ..ball = res[2]
      ..t0 = res[3]
      ..t1 = res[4]
      ..arrow = ArrowImages(headE: res[5], headS: res[6], shaftE: res[7], shaftS: res[8]);
    r = MatchRenderer(eng, im, ballIdx, hq: hq)
      ..ballShader = _ballProg?.fragmentShader()
      ..postShader = _postProg?.fragmentShader();
    await r.prepare();
    _ready = true;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    view = computeView(eng, size.x, size.y, topInset, bottomInset);
  }

  void setInsets(double top, double bottom) {
    topInset = top;
    bottomInset = bottom;
    if (hasLayout) view = computeView(eng, size.x, size.y, top, bottom);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (shouldStep()) (stepper ?? eng.update)(dt);
    onTick?.call(dt);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final v = view;
    if (!_ready || v == null) return;
    r.render(canvas, v, _t, 1);
  }

  Offset? worldAt(Offset local) => view == null ? null : toWorld(view!, local.dx, local.dy);

  @override
  void onRemove() {
    if (_ready) r.dispose();
    super.onRemove();
  }
}
