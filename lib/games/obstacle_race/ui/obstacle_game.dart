import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../arcade_kit/arcade_controls.dart';
import '../../arcade_kit/arcade_fx.dart';
import '../../arcade_kit/arcade_loop.dart';
import '../../arcade_kit/arcade_net.dart';
import '../../arcade_kit/arcade_result.dart';
import '../../arcade_kit/arcade_skin.dart';
import '../../core/game_contract.dart';
import '../core/obstacle_core.dart';

/// Sprite keys: runner_0..runner_3, sweeper, block (see docs/ARCADE_ASSETS.md).
ArcadeSkin obstacleSkin() => ArcadeSkin(
      gameId: 'obstacle_race',
      bgTop: const Color(0xFF241046),
      bgBottom: const Color(0xFF0B0620),
      accent: const Color(0xFFFF4FA3),
      accent2: const Color(0xFF8C5BFF),
      glow: const Color(0xFFFF8AD8),
      players: const <Color>[Color(0xFFFF5C93), Color(0xFF39C6FF), Color(0xFFFFC83D), Color(0xFF6CF06C)],
    );

class ObstacleGame extends StatefulWidget {
  const ObstacleGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<ObstacleGame> createState() => _ObstacleGameState();
}

class _ObstacleGameState extends ArcadeLoopState<ObstacleGame> {
  late final ObstacleRace race;
  late final ArcadeSkin skin = obstacleSkin();
  late final ArcadeFx fx;
  ArcadeRt? rt;
  double? _touchX;
  bool _jump = false;
  bool _done = false;
  String _banner = '';
  double _scale = 1;
  double _endIn = -1;

  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  int get seats => l.net?.seatCount ?? l.playerCount.clamp(2, 4);

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    final double sk = botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty);
    race = ObstacleRace(
      seed: l.net?.seed ?? l.seed ?? 3,
      count: seats,
      botSkill: l.online ? const <double>[] : <double>[for (int i = 0; i < seats; i++) i == 0 ? 0 : sk],
    );
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final NetLink? n = l.net;
    if (n != null) {
      rt = ArcadeRt(n, hz: 12)
        ..onMove = _onMove
        ..start();
    }
  }

  @override
  void dispose() {
    rt?.dispose();
    super.dispose();
  }

  void _onMove(NetMove m) {
    if (m.data['t'] == 'out') {
      race.eliminate((m.data['s'] as num).toInt(), ((m.data['ms'] as num).toInt()) / 1000);
    }
  }

  @override
  void tick(double dt) {
    final double before = race.countdown;
    if (!_done) {
      double steer = 0;
      final Runner mine = race.runners[me];
      if (_touchX != null && mine.alive) {
        final double rx = mine.x * _scale;
        steer = ((_touchX! - rx) / 50).clamp(-1.0, 1.0);
      }
      race.input(me, steer, _jump);
      _jump = false;
      final bool wasAlive = mine.alive;
      race.step(dt, simulate: rt == null ? null : <int>{me});
      if (wasAlive && !mine.alive && rt != null) {
        unawaited(rt!.log(<String, dynamic>{'t': 'out', 's': me, 'ms': (mine.outAt * 1000).round()}));
      }
    }
    if (before > 0) {
      _banner = race.countdown <= 0 ? 'GO!' : '${race.countdown.ceil()}';
      if (before.ceil() != race.countdown.ceil()) HapticFeedback.selectionClick();
    } else if (race.time > 0.8 && _banner == 'GO!') {
      _banner = '';
    }
    final ArcadeRt? r = rt;
    if (r != null) {
      r.pump(dt, () {
        final Runner k = race.runners[me];
        return <String, dynamic>{'x': k.x.round(), 'y': k.y.round(), 'z': k.z.round(), 'a': k.alive ? 1 : 0};
      });
      r.states.forEach((int seat, Map<String, dynamic> st) {
        if (seat == me || seat >= race.runners.length) return;
        final Runner k = race.runners[seat];
        k.x = rtLerp(k.x, (st['x'] as num).toDouble(), dt);
        k.y = rtLerp(k.y, (st['y'] as num).toDouble(), dt);
        k.z = (st['z'] as num).toDouble();
      });
      for (final int s in r.net.forfeitedSeats) {
        if (s < race.runners.length && race.runners[s].alive) race.eliminate(s, race.time);
      }
      final List<int> active = r.activeSeats;
      final int alive = active.where((int s) => race.runners[s].alive).length;
      if (!_done && race.countdown <= 0 && (alive <= 1 || active.length <= 1)) _finish();
    } else if (!_done) {
      if (!race.runners[me].alive) {
        _endIn = _endIn < 0 ? 1.4 : _endIn - dt;
        if (_endIn <= 0) {
          // fast-forward the bots to a final ranking
          int guard = 0;
          while (!race.over && guard++ < 30 * 600) {
            race.step(1 / 30);
          }
          _finish();
        }
      } else if (race.over) {
        _finish();
      }
    }
    for (final ObEvent e in race.events) {
      final Offset at = Offset(e.x, e.y);
      switch (e.kind) {
        case 'jump':
          fx.burst(at, Colors.white70, count: 6, speed: 90, kind: ParticleKind.smoke, size: 6, life: 0.5);
        case 'knock':
          fx.burst(at, const Color(0xFFFFD34E), count: 18, speed: 260);
          if (e.seat == me) {
            fx.shake(8);
            HapticFeedback.mediumImpact();
          }
        case 'bump':
          fx.ring(at, skin.accent2, size: 26, life: 0.3);
        case 'out':
          fx.burst(at, skin.player(e.seat), count: 34, speed: 300, kind: ParticleKind.orb, size: 5);
          if (e.seat == me) {
            _banner = l.tx('حذف شدی!', 'ELIMINATED!');
            fx.flashScreen(const Color(0xFFFF2D55), 0.35);
            HapticFeedback.heavyImpact();
          } else {
            HapticFeedback.lightImpact();
          }
      }
    }
    race.events.clear();
    fx.update(dt);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    final List<int> order = race.ranking();
    if (order.first == me) {
      _banner = l.tx('آخرین بازمانده!', 'LAST ONE STANDING!');
      fx.confetti(Offset(race.runners[me].x, race.runners[me].y), count: 70);
    }
    l.onFinish(rankedResult(l, order, whatFa: '${race.time.toStringAsFixed(0)} ثانیه', whatEn: '${race.time.toStringAsFixed(0)} s'));
  }

  // ------------------------------------------------------------------ render
  void _paint(Canvas canvas, Size size) {
    _scale = size.width / ObstacleRace.width;
    paintBackdrop(canvas, size, skin, time);
    final Offset sh = fx.shakeOffset;
    canvas.save();
    canvas.translate(sh.dx, sh.dy);
    // world → screen: y up, camera bottom = screen bottom
    canvas.translate(0, size.height);
    canvas.scale(_scale, -_scale);
    canvas.translate(0, -race.cam);
    final double top = race.cam + size.height / _scale;
    _paintFloor(canvas, race.cam - 40, top + 40);
    for (final Obstacle o in race.near(race.cam - 120, top + 120)) {
      _paintObstacleBase(canvas, o);
    }
    final List<Runner> rs = List<Runner>.of(race.runners)..sort((Runner a, Runner b) => b.y.compareTo(a.y));
    for (final Runner r in rs) {
      _paintRunner(canvas, r);
    }
    for (final Obstacle o in race.near(race.cam - 120, top + 120)) {
      _paintObstacleTop(canvas, o);
    }
    canvas.save();
    // particles are authored in world space with y up: flip text back
    fx.paint(canvas);
    canvas.restore();
    canvas.restore();
    // danger gradient at the bottom (the camera edge)
    canvas.drawRect(Rect.fromLTWH(0, size.height - 90, size.width, 90),
        Paint()..shader = ui.Gradient.linear(Offset(0, size.height - 90), Offset(0, size.height),
            <Color>[const Color(0x00FF2D55), const Color(0x88FF2D55)]));
    fx.paintFlash(canvas, size);
  }

  void _paintFloor(Canvas canvas, double y0, double y1) {
    const double w = ObstacleRace.width;
    final int a = (y0 / 120).floor(), b = (y1 / 120).ceil();
    for (int i = a; i <= b; i++) {
      final Rect r = Rect.fromLTWH(0, i * 120.0, w, 120);
      final Color c = i.isEven ? const Color(0xFF5B3FD0) : const Color(0xFF6A4BE6);
      canvas.drawRect(r, Paint()..shader = ui.Gradient.linear(r.centerLeft, r.centerRight,
          <Color>[shade(c, -0.12), c, shade(c, -0.12)], <double>[0, 0.5, 1]));
      // tile seams + chevrons
      canvas.drawLine(Offset(0, r.top), Offset(w, r.top), Paint()
        ..color = const Color(0x55FFFFFF)
        ..strokeWidth = 2);
      if (i % 3 == 0) {
        final Path chev = Path()
          ..moveTo(w / 2 - 30, r.top + 40)
          ..lineTo(w / 2, r.top + 70)
          ..lineTo(w / 2 + 30, r.top + 40);
        canvas.drawPath(chev, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x22FFFFFF));
      }
    }
    // neon side rails
    for (final double x in <double>[3, w - 3]) {
      final Path p = Path()
        ..moveTo(x, y0)
        ..lineTo(x, y1);
      paintNeonPath(canvas, p, skin.accent, width: 5, glow: 14);
    }
  }

  void _paintObstacleBase(Canvas canvas, Obstacle o) {
    switch (o.kind) {
      case ObKind.pit:
        final Rect r = Rect.fromLTWH(o.x, o.y, o.w, o.h);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), Paint()..color = const Color(0xFF05020D));
        canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(4), const Radius.circular(8)), Paint()
          ..shader = ui.Gradient.radial(r.center, r.longestSide * 0.6, <Color>[const Color(0xFF000000), const Color(0xFF2A0E4A)]));
        final Path edge = Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)));
        paintNeonPath(canvas, edge, const Color(0xFFFF2D55), width: 3, glow: 10);
      case ObKind.drop:
        final double c = o.dropCycle(race.time);
        if (c > 0.35 && c < 0.75) {
          final double k = (c - 0.35) / 0.4;
          canvas.drawCircle(Offset(o.x, o.y), o.w * 0.25 + o.w * 0.35 * k, Paint()
            ..color = Color.fromRGBO(255, 45, 85, 0.15 + 0.35 * k));
          canvas.drawCircle(Offset(o.x, o.y), o.w * 0.6, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Color.fromRGBO(255, 45, 85, 0.6 * k));
        }
      default:
        break;
    }
  }

  void _paintObstacleTop(Canvas canvas, Obstacle o) {
    switch (o.kind) {
      case ObKind.sweeper:
        final double a = o.angle(race.time);
        final Offset p0 = Offset(o.x, o.y);
        final Offset p1 = Offset(o.x + math.cos(a) * o.w, o.y + math.sin(a) * o.w);
        canvas.drawLine(p0 + const Offset(6, -8), p1 + const Offset(6, -8), Paint()
          ..strokeWidth = 18
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x44000000));
        canvas.drawLine(p0, p1, Paint()
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(p0, p1, const <Color>[Color(0xFFFF3B3B), Color(0xFFFF8A3D)]));
        for (int i = 1; i < 6; i++) {
          final Offset q = Offset.lerp(p0, p1, i / 6)!;
          canvas.drawCircle(q, 4, Paint()..color = Colors.white.withValues(alpha: 0.85));
        }
        paintSphere(canvas, p0, 15, const Color(0xFFB0B8C8));
      case ObKind.gate:
        final double g = o.gateGap(race.time, ObstacleRace.width);
        final double gl = g - o.w / 2, gr = g + o.w / 2;
        paintBlock(canvas, Rect.fromLTWH(0, o.y, math.max(0, gl), o.h), const Color(0xFF39C6FF), radius: 6, depth: -6);
        paintBlock(canvas, Rect.fromLTWH(gr, o.y, math.max(0, ObstacleRace.width - gr), o.h), const Color(0xFF39C6FF), radius: 6, depth: -6);
        paintGlow(canvas, Offset(g, o.y + o.h / 2), o.w * 0.6, const Color(0xFF7CFF7A), 0.25);
      case ObKind.drop:
        final double c = o.dropCycle(race.time);
        if (c > 0.55 && c < 0.95) {
          final double fall = c < 0.75 ? (0.75 - c) / 0.2 : 0;
          final double s = 1 + fall * 0.9;
          final Rect r = Rect.fromCenter(center: Offset(o.x, o.y), width: o.w * s, height: o.h * s);
          if (!skin.drawSprite(canvas, 'block', r, opacity: c > 0.85 ? (0.95 - c) * 10 : 1)) {
            paintBlock(canvas, r, const Color(0xFFFFC83D), radius: 8, depth: -6 * s, glow: fall > 0 ? 0 : 0.4);
          }
          if (c > 0.75 && c < 0.78) fx.shake(2);
        }
      case ObKind.bumper:
        final double pulse = 1 + 0.06 * math.sin(race.time * 6 + o.x);
        paintShadow(canvas, Offset(o.x + 4, o.y - 6), o.w * 2.2, o.w * 1.2, 0.35);
        paintSphere(canvas, Offset(o.x, o.y), o.w * pulse, const Color(0xFFFF4FA3), rim: Colors.white, shadow: false);
      case ObKind.pit:
        break;
    }
  }

  void _paintRunner(Canvas canvas, Runner r) {
    final Color c = skin.player(r.seat);
    final double alpha = r.alive ? 1 : math.max(0, 1 - (race.time - r.outAt) * 2);
    if (alpha <= 0) return;
    const double rad = ObstacleRace.runnerR;
    paintShadow(canvas, Offset(r.x + 3, r.y - 5), rad * 2.2 * (1 - r.z / 260), rad * 1.1, 0.4 * alpha);
    canvas.save();
    canvas.translate(r.x, r.y + r.z * 0.6);
    final double s = 1 + r.z / 220;
    canvas.scale(s, -s); // text/eyes upright
    if (!skin.drawSprite(canvas, 'runner_${r.seat % 4}', const Rect.fromLTWH(-rad * 1.3, -rad * 1.6, rad * 2.6, rad * 3), opacity: alpha)) {
      final Rect body = Rect.fromCenter(center: const Offset(0, -2), width: rad * 2, height: rad * 2.5);
      canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(rad)), Paint()
        ..shader = ui.Gradient.radial(body.center + const Offset(-5, -8), rad * 2,
            <Color>[shade(c, 0.25).withValues(alpha: alpha), c.withValues(alpha: alpha), shade(c, -0.3).withValues(alpha: alpha)], <double>[0, 0.5, 1]));
      // visor
      final Rect visor = Rect.fromCenter(center: const Offset(0, -8), width: rad * 1.5, height: rad * 0.8);
      canvas.drawRRect(RRect.fromRectAndRadius(visor, const Radius.circular(8)), Paint()..color = const Color(0xFF14102A).withValues(alpha: alpha));
      canvas.drawCircle(const Offset(-5, -8), 3, Paint()..color = Colors.white.withValues(alpha: alpha));
      canvas.drawCircle(const Offset(5, -8), 3, Paint()..color = Colors.white.withValues(alpha: alpha));
      canvas.drawOval(Rect.fromCenter(center: const Offset(-5, -14), width: 10, height: 5), Paint()..color = Colors.white.withValues(alpha: 0.4 * alpha));
    }
    if (r.seat == me) {
      canvas.drawCircle(const Offset(0, 22), 5, Paint()..color = Colors.white.withValues(alpha: alpha));
      drawLabel(canvas, l.tx('تو', 'YOU'), const Offset(0, 34), size: 10, color: Colors.white, glow: c);
    }
    canvas.restore();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return Stack(fit: StackFit.expand, children: <Widget>[
      Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (PointerDownEvent e) => _touchX = e.localPosition.dx,
        onPointerMove: (PointerMoveEvent e) => _touchX = e.localPosition.dx,
        onPointerUp: (_) => _touchX = null,
        onPointerCancel: (_) => _touchX = null,
        child: CustomPaint(painter: ArcadePainter(_paint, frame), size: Size.infinite),
      ),
      ValueListenableBuilder<int>(
        valueListenable: frame,
        builder: (_, __, ___) => Stack(children: <Widget>[
          Positioned(
            top: pad.top + 64,
            left: 12,
            child: ArcadeHudPill(
              color: skin.accent,
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                const Icon(Icons.groups_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text('${race.aliveCount}/${race.count}', style: const TextStyle(fontSize: 18)),
              ]),
            ),
          ),
          Positioned(
            top: pad.top + 64,
            right: 12,
            child: ArcadeHudPill(
              color: skin.accent2,
              child: Text('${(race.runners[me].y / 10).round()} m', style: const TextStyle(fontSize: 16)),
            ),
          ),
          if (_banner.isNotEmpty) Center(child: ArcadeBanner(_banner, color: skin.accent, size: _banner.length > 6 ? 40 : 64)),
        ]),
      ),
      Positioned(
        right: 18,
        bottom: pad.bottom + 22,
        child: ArcadePadButton(
          icon: Icons.keyboard_double_arrow_up_rounded,
          label: l.tx('پرش', 'JUMP'),
          color: skin.accent,
          size: 92,
          onDown: () => _jump = true,
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: pad.bottom + 8,
        child: IgnorePointer(
          child: Text(l.tx('انگشتت را بکش تا حرکت کنی', 'Drag anywhere to steer'),
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
      ),
    ]);
  }
}
