import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../arcade_kit/arcade_controls.dart';
import '../../arcade_kit/arcade_fx.dart';
import '../../arcade_kit/arcade_loop.dart';
import '../../arcade_kit/arcade_result.dart';
import '../../arcade_kit/arcade_skin.dart';
import '../../arcade_kit/arcade_turns.dart';
import '../../core/game_contract.dart';
import '../core/golf_core.dart';

/// Sprite keys: ball_0..3 (or ball), hole, turf (seamless tile), wall, flag, bumper, windmill.
ArcadeSkin golfSkin() => ArcadeSkin(
      gameId: 'mini_golf',
      bgTop: const Color(0xFF0E2A1E),
      bgBottom: const Color(0xFF04120B),
      accent: const Color(0xFF7CFF7A),
      accent2: const Color(0xFFFFD34E),
      glow: const Color(0xFF3DDC84),
      players: const <Color>[Color(0xFFF7F7F7), Color(0xFFFF4F9A), Color(0xFF39C6FF), Color(0xFFFFC94A)],
    );

class GolfGame extends StatefulWidget {
  const GolfGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<GolfGame> createState() => _GolfGameState();
}

class _GolfGameState extends ArcadeLoopState<GolfGame> {
  late final GolfMatch g;
  late final ArcadeSkin skin = golfSkin();
  late final ArcadeFx fx;
  ArcadeTurnNet? tn;
  final math.Random _rng = math.Random(11);
  Offset? _dragFrom, _dragTo;
  double _botWait = 0;
  int _shownHole = -1;
  String _banner = '';
  double _bannerT = 0;
  bool _done = false;
  double _s = 1;
  Offset _o = Offset.zero;
  final List<Offset> _trail = <Offset>[];

  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  int get seats => l.net?.seatCount ?? l.playerCount.clamp(2, 4);
  bool _isBot(int s) => !l.online && s != me;

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    g = GolfMatch(players: seats, seed: l.net?.seed ?? l.seed ?? 1);
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final NetLink? n = l.net;
    if (n != null) {
      tn = ArcadeTurnNet(n, onMove: _onNet, onReplayDone: () => tn?.turn = g.current)..start();
      for (final int s in n.forfeitedSeats) {
        g.forfeit(s);
      }
    }
  }

  @override
  void dispose() {
    tn?.dispose();
    super.dispose();
  }

  void _say(String s, [double t = 1.6]) {
    _banner = s;
    _bannerT = t;
  }

  Offset _px(double x, double y) => _o + Offset(x, y) * _s;

  Future<void> _onNet(NetMove m) async {
    if (!m.replay && m.seat == me) return;
    while (g.simulating && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (m.isForfeit) {
      g.forfeit((m.data['seat'] as num?)?.toInt() ?? m.seat);
    } else if (m.isTimeout) {
      // absent player: a gentle default putt toward the cup keeps the round moving
      final GBall b = g.balls[g.current];
      g.shoot(math.atan2(g.h.cup.y - b.y, g.h.cup.x - b.x), 0.35);
      if (m.replay) g.runToEnd();
    } else if (m.data['a'] == 'shot' && m.seat == g.current) {
      g.shoot((m.data['ang'] as num).toDouble(), (m.data['p'] as num).toDouble());
      if (m.replay) g.runToEnd();
    } else if (m.data['a'] == 'sync' && !m.replay) {
      final List<dynamic> ps = m.data['b'] as List<dynamic>;
      if ((m.data['h'] as num).toInt() == g.hole) {
        for (int i = 0; i < ps.length && i < g.balls.length; i++) {
          final List<dynamic> e = ps[i] as List<dynamic>;
          g.balls[i]
            ..x = (e[0] as num).toDouble()
            ..y = (e[1] as num).toDouble();
        }
      }
    }
    if (m.replay) g.events.clear();
    tn?.turn = g.current;
  }

  void _shoot(double ang, double p) {
    if (g.simulating || g.current != me || g.over) return;
    if (tn != null) unawaited(tn!.send(<String, dynamic>{'a': 'shot', 'ang': ang, 'p': p}));
    g.shoot(ang, p);
    HapticFeedback.mediumImpact();
    _trail.clear();
  }

  @override
  void tick(double dt) {
    if (_bannerT > 0) {
      _bannerT -= dt;
      if (_bannerT <= 0) _banner = '';
    }
    if (g.over) {
      _finish();
      fx.update(dt);
      return;
    }
    if (_shownHole != g.hole) {
      _shownHole = g.hole;
      _say(l.tx('حفره‌ی ${g.hole + 1} · پار ${g.h.par}', 'HOLE ${g.hole + 1} · PAR ${g.h.par}'), 1.8);
      _trail.clear();
    }
    if (g.simulating) {
      final int shooter = g.current, holeAt = g.hole;
      final bool done = g.step(2);
      final GBall b = g.balls[shooter];
      _trail.add(Offset(b.x, b.y));
      if (_trail.length > 24) _trail.removeAt(0);
      _events(shooter, holeAt);
      if (done) {
        _trail.clear();
        if (tn != null && shooter == me) {
          unawaited(tn!.send(<String, dynamic>{
            'a': 'sync',
            'h': g.hole,
            'b': <List<double>>[for (final GBall x in g.balls) <double>[x.x, x.y]],
          }));
        }
        tn?.turn = g.current;
      }
    } else if (_isBot(g.current) && _bannerT <= 0.6) {
      _botWait += dt;
      if (_botWait > 0.7) {
        _botWait = 0;
        final (double a, double p) = g.botShot(_rng, botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty), samples: 36);
        g.shoot(a, p);
      }
    }
    fx.update(dt);
  }

  void _events(int shooter, int holeAt) {
    for (final GEvent e in g.events) {
      final Offset at = _px(e.x, e.y);
      switch (e.kind) {
        case 'cup':
          fx.confetti(at, count: 30);
          fx.ring(at, skin.accent2, size: 16);
          final int strokes = g.hole == holeAt ? g.balls[shooter].strokes : g.cards[shooter].last;
          final int par = g.course[holeAt].par;
          _say(strokes == 1
              ? l.tx('هول این وان!', 'HOLE IN ONE!')
              : strokes < par
                  ? l.tx('بردی! زیر پار', 'BIRDIE!')
                  : strokes == par
                      ? l.tx('پار', 'PAR')
                      : l.tx('داخل شد', 'IN THE HOLE'));
          HapticFeedback.heavyImpact();
        case 'water':
          fx.burst(at, const Color(0xFF39C6FF), count: 20, speed: 120, size: 3, kind: ParticleKind.orb, gravity: 200);
          _say(l.tx('آب! +۱ ضربه', 'SPLASH! +1'));
        case 'bumper':
          fx.burst(at, skin.accent, count: 8, speed: 90, size: 2.5);
          fx.shake(2);
        case 'wall':
        case 'mill':
          if (e.strength > 200) fx.burst(at, Colors.white, count: 5, speed: 60, size: 2, life: 0.3);
      }
    }
    g.events.clear();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    final List<int> order = g.ranking();
    if (order.first == me) fx.confetti(MediaQuery.sizeOf(context).center(Offset.zero), count: 60);
    _say(order.first == me ? l.tx('قهرمان!', 'CHAMPION!') : l.tx('پایان مسابقه', 'ROUND OVER'), 3);
    Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final int tot = g.total(me);
      final int diff = tot - g.parSoFar();
      l.onFinish(rankedResult(l, order,
          whatFa: '$tot ضربه (${diff >= 0 ? '+' : ''}$diff)', whatEn: '$tot strokes (${diff >= 0 ? '+' : ''}$diff)'));
    });
  }

  // ------------------------------------------------------------------ render
  void _paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, size, skin, time);
    if (g.over) return;
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final double avH = size.height - pad.top - pad.bottom - 170;
    _s = math.min((size.width - 16) / kGolfW, avH / kGolfH);
    _o = Offset((size.width - kGolfW * _s) / 2, pad.top + 112 + (avH - kGolfH * _s) / 2);
    final Offset sh = fx.shakeOffset;
    canvas.save();
    canvas.translate(_o.dx + sh.dx, _o.dy + sh.dy);
    canvas.scale(_s);
    _paintCourse(canvas);
    canvas.restore();
    canvas.save();
    canvas.translate(sh.dx, sh.dy);
    fx.paint(canvas);
    canvas.restore();
    fx.paintFlash(canvas, size);
  }

  void _paintCourse(Canvas canvas) {
    final GHole h = g.h;
    // turf: bounding box of the walls, mowed stripes
    double l = kGolfW, t = kGolfH, r = 0, b = 0;
    for (final GWall w in h.walls) {
      l = math.min(l, math.min(w.x1, w.x2));
      r = math.max(r, math.max(w.x1, w.x2));
      t = math.min(t, math.min(w.y1, w.y2));
      b = math.max(b, math.max(w.y1, w.y2));
    }
    final Rect turf = Rect.fromLTRB(l, t, r, b);
    canvas.drawRRect(RRect.fromRectAndRadius(turf.inflate(10).shift(const Offset(0, 10)), const Radius.circular(14)), Paint()
      ..color = const Color(0x88000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    if (!skin.drawSprite(canvas, 'turf', turf)) {
      canvas.drawRect(turf, Paint()..color = const Color(0xFF2FA34F));
      final Paint stripe = Paint()..color = const Color(0xFF38B65A);
      for (double y = t; y < b; y += 40) {
        canvas.drawRect(Rect.fromLTRB(l, y, r, math.min(b, y + 20)), stripe);
      }
      canvas.drawRect(turf, Paint()
        ..shader = ui.Gradient.radial(turf.center, turf.longestSide * 0.7,
            <Color>[const Color(0x22FFFFFF), const Color(0x33000000)]));
    }
    // tee box
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(h.start.x, h.start.y), width: 34, height: 18), const Radius.circular(4)),
        Paint()..color = const Color(0x33FFFFFF));
    // sand
    for (final GRect s in h.sand) {
      final Rect rr = Rect.fromLTRB(s.l, s.t, s.r, s.b);
      canvas.drawRRect(RRect.fromRectAndRadius(rr, const Radius.circular(14)), Paint()..color = const Color(0xFFE9D39A));
      final math.Random rnd = math.Random(s.l.toInt() * 7 + s.t.toInt());
      final Paint dot = Paint()..color = const Color(0x55B08A44);
      for (int i = 0; i < 40; i++) {
        canvas.drawCircle(Offset(s.l + rnd.nextDouble() * (s.r - s.l), s.t + rnd.nextDouble() * (s.b - s.t)), 1.2, dot);
      }
    }
    // water
    for (final GRect w in h.water) {
      final Rect rr = Rect.fromLTRB(w.l, w.t, w.r, w.b);
      canvas.drawRRect(RRect.fromRectAndRadius(rr, const Radius.circular(8)),
          Paint()..shader = ui.Gradient.linear(rr.topCenter, rr.bottomCenter, <Color>[const Color(0xFF1F8FE0), const Color(0xFF0B4FA0)]));
      final Paint wave = Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (double y = w.t + 8; y < w.b - 4; y += 12) {
        final Path p = Path()..moveTo(w.l + 4, y);
        for (double x = w.l + 4; x < w.r - 4; x += 6) {
          p.lineTo(x, y + math.sin(x * 0.2 + time * 3 + y) * 1.6);
        }
        canvas.drawPath(p, wave);
      }
    }
    // cup + flag
    final Offset cup = Offset(h.cup.x, h.cup.y);
    if (!skin.drawSprite(canvas, 'hole', Rect.fromCircle(center: cup, radius: kCupR + 2))) {
      canvas.drawCircle(cup, kCupR + 2, Paint()..color = const Color(0x55FFFFFF));
      canvas.drawCircle(cup, kCupR, Paint()..shader = ui.Gradient.radial(cup + const Offset(0, -2), kCupR, <Color>[const Color(0xFF000000), const Color(0xFF1D2B1F)]));
    }
    paintGlow(canvas, cup, 26, skin.accent2, 0.25 + 0.1 * math.sin(time * 3));
    if (!skin.drawSprite(canvas, 'flag', Rect.fromLTWH(cup.dx - 2, cup.dy - 46, 26, 46))) {
      canvas.drawLine(cup, cup - const Offset(0, 44), Paint()
        ..color = Colors.white
        ..strokeWidth = 2);
      final double wv = math.sin(time * 4) * 2;
      canvas.drawPath(
          Path()
            ..moveTo(cup.dx, cup.dy - 44)
            ..quadraticBezierTo(cup.dx + 11, cup.dy - 42 + wv, cup.dx + 22, cup.dy - 38)
            ..lineTo(cup.dx, cup.dy - 32)
            ..close(),
          Paint()..color = const Color(0xFFFF3D5A));
    }
    // bumpers
    for (final GBumper p in h.bumpers) {
      final Offset c = Offset(p.x, p.y);
      if (!skin.drawSprite(canvas, 'bumper', Rect.fromCircle(center: c, radius: p.r))) {
        paintGlow(canvas, c, p.r * 1.8, skin.accent, 0.35);
        paintSphere(canvas, c, p.r, const Color(0xFFE23D8B));
        canvas.drawCircle(c, p.r * 0.55, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white70);
      }
    }
    // walls as raised rails
    for (final GWall w in h.walls) {
      final Offset a = Offset(w.x1, w.y1), c = Offset(w.x2, w.y2);
      canvas.drawLine(a + const Offset(2, 4), c + const Offset(2, 4), Paint()
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x66000000));
      canvas.drawLine(a, c, Paint()
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF8B5A2B));
      canvas.drawLine(a + const Offset(0, -1.5), c + const Offset(0, -1.5), Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFD9A066));
    }
    // windmills
    for (final GWindmill m in h.mills) {
      final double a = g.millAngle(m);
      final Offset c = Offset(m.x, m.y);
      for (int k = 0; k < 2; k++) {
        final double aa = a + k * math.pi / 2;
        final Offset d = Offset(math.cos(aa), math.sin(aa)) * m.len;
        canvas.drawLine(c - d + const Offset(2, 4), c + d + const Offset(2, 4), Paint()
          ..strokeWidth = 8
          ..color = const Color(0x55000000));
        canvas.drawLine(c - d, c + d, Paint()
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(c - d, c + d, <Color>[const Color(0xFFF2F2F2), const Color(0xFFB0B8C8)]));
      }
      paintSphere(canvas, c, 8, const Color(0xFFFF7A1A));
    }
    // trail
    for (int i = 0; i < _trail.length; i++) {
      canvas.drawCircle(_trail[i], kBallR * (i / _trail.length) * 0.8, Paint()..color = Colors.white.withValues(alpha: 0.25 * i / _trail.length));
    }
    // balls
    for (int i = 0; i < g.balls.length; i++) {
      final GBall b = g.balls[i];
      if (b.holed || g.out.contains(i)) continue;
      final Offset c = Offset(b.x, b.y);
      paintShadow(canvas, c + const Offset(2, 4), kBallR * 2.2, kBallR * 1.2, 0.5);
      if (!skin.drawSprite(canvas, 'ball_$i', Rect.fromCircle(center: c, radius: kBallR)) &&
          !skin.drawSprite(canvas, 'ball', Rect.fromCircle(center: c, radius: kBallR))) {
        paintSphere(canvas, c, kBallR, skin.player(i), shadow: false);
      }
      if (i == g.current && !g.simulating) {
        canvas.drawCircle(c, kBallR + 5 + math.sin(time * 6) * 1.5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = skin.player(i).withValues(alpha: 0.9));
      }
    }
    // aim
    if (_dragFrom != null && _dragTo != null && g.current == me && !g.simulating) {
      final GBall b = g.balls[me];
      final Offset v = (_dragFrom! - _dragTo!) / _s;
      final double p = (v.distance / 140).clamp(0.0, 1.0);
      if (p > 0.03) {
        final Offset dir = v / v.distance;
        final Offset c = Offset(b.x, b.y);
        final Color col = Color.lerp(skin.accent, const Color(0xFFFF2D55), p)!;
        for (int i = 1; i <= 10; i++) {
          canvas.drawCircle(c + dir * (i * 9.0 * (0.4 + p)), 1.8, Paint()..color = col.withValues(alpha: 1 - i / 12));
        }
        canvas.drawArc(Rect.fromCircle(center: c, radius: 16), -math.pi / 2, math.pi * 2 * p, false, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = col);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return Stack(fit: StackFit.expand, children: <Widget>[
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (DragStartDetails d) {
          if (g.current == me && !g.simulating && !g.over) {
            _dragFrom = d.localPosition;
            _dragTo = d.localPosition;
          }
        },
        onPanUpdate: (DragUpdateDetails d) => _dragTo = _dragFrom == null ? null : d.localPosition,
        onPanEnd: (_) {
          if (_dragFrom != null && _dragTo != null) {
            final Offset v = (_dragFrom! - _dragTo!) / _s;
            final double p = (v.distance / 140).clamp(0.0, 1.0);
            if (p > 0.03) _shoot(math.atan2(v.dy, v.dx), p);
          }
          _dragFrom = null;
          _dragTo = null;
        },
        child: CustomPaint(painter: ArcadePainter(_paint, frame), size: Size.infinite),
      ),
      ValueListenableBuilder<int>(
        valueListenable: frame,
        builder: (_, __, ___) => Stack(children: <Widget>[
          Positioned(
            top: pad.top + 62,
            left: 12,
            right: 12,
            child: Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
              ArcadeHudPill(
                color: skin.accent2,
                child: Text(g.over ? '—' : '${g.hole + 1}/${g.course.length} · P${g.h.par}', style: const TextStyle(fontSize: 13)),
              ),
              for (int i = 0; i < g.players; i++)
                Opacity(
                  opacity: g.out.contains(i) ? 0.35 : (i == g.current ? 1 : 0.7),
                  child: ArcadeHudPill(
                    color: i == g.current ? skin.player(i) : Colors.white24,
                    child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: skin.player(i))),
                      const SizedBox(width: 5),
                      Text(
                          '${_short(i)} ${g.total(i)}${g.over ? '' : '+${g.balls[i].strokes}'}',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
            ]),
          ),
          if (_banner.isNotEmpty)
            Positioned(left: 0, right: 0, top: MediaQuery.sizeOf(context).height * 0.4, child: Center(child: ArcadeBanner(_banner, color: skin.accent, size: 34))),
          if (!g.over && g.current == me && !g.simulating && _dragFrom == null && _bannerT <= 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: pad.bottom + 26,
              child: Center(
                child: Text(l.tx('بکش و رها کن تا ضربه بزنی', 'Pull back & release to putt'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    ]);
  }

  String _short(int i) {
    final String n = l.netName(i) ?? (i == me ? l.playerName : '${l.tx('ربات', 'Bot')} $i');
    return n.length > 7 ? '${n.substring(0, 7)}…' : n;
  }
}
