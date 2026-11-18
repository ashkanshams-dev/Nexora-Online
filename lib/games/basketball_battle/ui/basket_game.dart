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
import '../core/basket_core.dart';

/// Sprite keys: ball (round), hoop (backboard + rim, front view, rim centred at 50% x / 78% y), court (portrait bg).
ArcadeSkin basketSkin() => ArcadeSkin(
      gameId: 'basketball_battle',
      bgTop: const Color(0xFF1B0F2E),
      bgBottom: const Color(0xFF07040F),
      accent: const Color(0xFFFF8A2A),
      accent2: const Color(0xFFFFD34E),
      glow: const Color(0xFFFF6A1D),
    );

class BasketGame extends StatefulWidget {
  const BasketGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<BasketGame> createState() => _BasketGameState();
}

class _BasketGameState extends ArcadeLoopState<BasketGame> {
  late final BasketCourt court;
  late final ArcadeSkin skin = basketSkin();
  late final ArcadeFx fx;
  final List<BasketBot> bots = <BasketBot>[];
  ArcadeRt? rt;
  final Map<int, int> _fin = <int, int>{};
  double _endWait = -1;
  bool _done = false;
  bool _sentFin = false;
  String _banner = '';
  double _bannerT = 0;
  double _netSway = 0;
  Offset? _swipeA;
  final List<Offset> _swipe = <Offset>[];
  final List<Offset> _trail = <Offset>[];
  double _s = 1;
  Offset _o = Offset.zero;

  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  int get seats => l.net?.seatCount ?? l.playerCount.clamp(2, 4);

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    final int seed = l.net?.seed ?? l.seed ?? 9;
    court = BasketCourt(seed: seed + me * 101, duration: 60);
    if (!l.online) {
      final double sk = botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty);
      for (int i = 1; i < seats; i++) {
        bots.add(BasketBot(seed: seed + i * 7, skill: (sk + (i - 1) * 0.04).clamp(0.0, 1.0)));
      }
    }
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final NetLink? n = l.net;
    if (n != null) {
      rt = ArcadeRt(n, hz: 6)
        ..onMove = (NetMove m) {
          if (m.data['t'] == 'fin') _fin[(m.data['s'] as num).toInt()] = (m.data['sc'] as num).toInt();
        }
        ..start();
    }
  }

  @override
  void dispose() {
    rt?.dispose();
    super.dispose();
  }

  void _say(String s, [double t = 1.1]) {
    _banner = s;
    _bannerT = t;
  }

  Offset _px(double x, double y) => _o + Offset(x, y) * _s;

  int scoreOf(int seat) {
    if (seat == me) return court.score;
    if (!l.online) return bots[seat - 1].score;
    return _fin[seat] ?? (rt?.states[seat]?['sc'] as num?)?.toInt() ?? 0;
  }

  @override
  void tick(double dt) {
    if (_bannerT > 0) {
      _bannerT -= dt;
      if (_bannerT <= 0) _banner = '';
    }
    final bool wasCount = court.countdown > 0;
    court.step(dt);
    if (court.countdown > 0) {
      _banner = '${court.countdown.ceil()}';
    } else if (wasCount) {
      _say('GO!', 0.7);
    }
    if (court.countdown <= 0) {
      for (int i = 0; i < bots.length; i++) {
        final int pts = bots[i].step(dt, court.duration);
        if (pts > 0) fx.text('+$pts', Offset(60.0 + i * 90, MediaQuery.paddingOf(context).top + 110), skin.player(i + 1), size: 16);
      }
    }
    for (final BEvent e in court.events) {
      final Offset at = _px(e.x, e.y);
      switch (e.kind) {
        case 'swish':
        case 'score':
          _netSway = 1;
          fx.burst(at + Offset(0, 20 * _s), court.onFire ? const Color(0xFFFF6A1D) : skin.accent2, count: 26, speed: 220, size: 3.5, kind: ParticleKind.orb, gravity: 300);
          fx.text('+${e.value}', at - Offset(0, 40 * _s), e.kind == 'swish' ? const Color(0xFF7CFF7A) : Colors.white, size: 30);
          if (e.kind == 'swish') _say(l.tx('سوییش!', 'SWISH!'));
          HapticFeedback.mediumImpact();
        case 'fire':
          _say(l.tx('آتشین! امتیاز دوبرابر', 'ON FIRE! x2'), 1.4);
          fx.flashScreen(const Color(0xFFFF6A1D), 0.25);
        case 'rim':
          fx.burst(at, Colors.white, count: 6, speed: 100, size: 2);
          HapticFeedback.selectionClick();
        case 'miss':
          break;
      }
    }
    court.events.clear();
    _netSway = math.max(0, _netSway - dt * 2.2);
    if (court.flying) {
      _trail.add(Offset(court.x, court.y));
      if (_trail.length > 14) _trail.removeAt(0);
    } else if (_trail.isNotEmpty) {
      _trail.removeAt(0);
    }
    final ArcadeRt? r = rt;
    if (r != null) {
      r.pump(dt, () => <String, dynamic>{'sc': court.score, 'st': court.streak});
    }
    if (court.over && !_done) {
      if (!_sentFin) {
        _sentFin = true;
        _fin[me] = court.score;
        _say(l.tx('پایان وقت!', "TIME'S UP!"), 2);
        if (r != null) unawaited(r.log(<String, dynamic>{'t': 'fin', 's': me, 'sc': court.score}));
        _endWait = 0;
      }
      _endWait += dt;
      final bool all = r == null || r.activeSeats.every((int s) => _fin.containsKey(s));
      if (all || _endWait > 5) _finish();
    }
    fx.update(dt);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    final List<int> order = List<int>.generate(seats, (int i) => i)
      ..sort((int a, int b) => scoreOf(a) != scoreOf(b) ? scoreOf(b).compareTo(scoreOf(a)) : a.compareTo(b));
    if (rt != null) {
      for (final int s in rt!.net.forfeitedSeats) {
        order
          ..remove(s)
          ..add(s);
      }
    }
    if (order.first == me) fx.confetti(_px(kBW / 2, 200), count: 70);
    Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      l.onFinish(rankedResult(l, order,
          whatFa: '${court.score} امتیاز · ${court.made}/${court.shots}', whatEn: '${court.score} pts · ${court.made}/${court.shots}'));
    });
  }

  // ------------------------------------------------------------------ input
  void _panStart(DragStartDetails d) {
    _swipeA = d.localPosition;
    _swipe
      ..clear()
      ..add(d.localPosition);
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_swipeA == null) return;
    _swipe.add(d.localPosition);
    if (_swipe.length > 12) _swipe.removeAt(0);
  }

  void _panEnd(DragEndDetails d) {
    final Offset? a = _swipeA;
    _swipeA = null;
    if (a == null || _swipe.isEmpty) return;
    final Offset v = (_swipe.last - a) / _s;
    if (court.throwBall(v.dx, v.dy)) HapticFeedback.lightImpact();
    _swipe.clear();
  }

  // ------------------------------------------------------------------ render
  void _paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, size, skin, time);
    _s = math.min(size.width / kBW, (size.height - 40) / kBH);
    _o = Offset((size.width - kBW * _s) / 2, size.height - kBH * _s - 10);
    final Offset sh = fx.shakeOffset;
    canvas.save();
    canvas.translate(_o.dx + sh.dx, _o.dy + sh.dy);
    canvas.scale(_s);
    if (!skin.drawSprite(canvas, 'court', const Rect.fromLTWH(0, 0, kBW, kBH))) _paintArena(canvas);
    _paintHoop(canvas, back: true);
    _paintBall(canvas);
    _paintHoop(canvas, back: false);
    canvas.restore();
    // swipe trail
    if (_swipe.length > 1) {
      final Path p = Path()..moveTo(_swipe.first.dx, _swipe.first.dy);
      for (final Offset o in _swipe.skip(1)) {
        p.lineTo(o.dx, o.dy);
      }
      paintNeonPath(canvas, p, skin.accent2, width: 3, glow: 8);
    }
    fx.paint(canvas);
    fx.paintFlash(canvas, size);
  }

  void _paintArena(Canvas canvas) {
    // spotlights
    for (int i = 0; i < 3; i++) {
      final double x = 60.0 + i * 120;
      canvas.drawPath(
          Path()
            ..moveTo(x - 8, 0)
            ..lineTo(x + 8, 0)
            ..lineTo(x + 70, 520)
            ..lineTo(x - 70, 520)
            ..close(),
          Paint()
            ..shader = ui.Gradient.linear(Offset(x, 0), Offset(x, 520),
                <Color>[Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0)]));
    }
    // wooden floor with perspective planks
    const Rect floor = Rect.fromLTWH(0, kBH - 120, kBW, 120);
    canvas.drawRect(floor, Paint()..shader = ui.Gradient.linear(floor.topCenter, floor.bottomCenter, <Color>[const Color(0xFFB8743A), const Color(0xFF7A4520)]));
    final Paint plank = Paint()
      ..color = const Color(0x33000000)
      ..strokeWidth = 1;
    for (int i = -6; i <= 6; i++) {
      canvas.drawLine(Offset(kBW / 2 + i * 18, kBH - 120), Offset(kBW / 2 + i * 60, kBH), plank);
    }
    canvas.drawLine(const Offset(0, kBH - 120), const Offset(kBW, kBH - 120), Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 2);
    // key arc
    canvas.drawArc(Rect.fromCenter(center: const Offset(kBW / 2, kBH - 120), width: 220, height: 60), 0, math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x88FFFFFF));
  }

  void _paintHoop(Canvas canvas, {required bool back}) {
    final double hx = court.hoopX, hy = court.hoopY;
    if (back) {
      // pole + backboard
      canvas.drawRect(Rect.fromLTWH(hx - 5, hy - 100, 10, 24), Paint()..color = const Color(0xFF5A6070));
      final Rect board = Rect.fromCenter(center: Offset(hx, hy - 62), width: 132, height: 86);
      if (skin.drawSprite(canvas, 'hoop', Rect.fromCenter(center: Offset(hx, hy - 50), width: 140, height: 150))) return;
      canvas.drawRRect(RRect.fromRectAndRadius(board.shift(const Offset(4, 6)), const Radius.circular(6)), Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawRRect(RRect.fromRectAndRadius(board, const Radius.circular(6)), Paint()..color = const Color(0x55DDEEFF));
      canvas.drawRRect(RRect.fromRectAndRadius(board, const Radius.circular(6)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white);
      canvas.drawRect(Rect.fromCenter(center: Offset(hx, hy - 40), width: 50, height: 36), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFF4D3D));
      if (court.onFire) paintGlow(canvas, Offset(hx, hy - 62), 90, const Color(0xFFFF6A1D), 0.35);
      // back half of the rim
      canvas.drawArc(Rect.fromCenter(center: Offset(hx, hy), width: kRimHalf * 2, height: 14), math.pi, math.pi, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFFB8361E));
      return;
    }
    if (skin.has('hoop')) return;
    // net
    final double sway = math.sin(time * 18) * _netSway * 6;
    final Paint net = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    const int n = 6;
    for (int i = 0; i <= n; i++) {
      final double t = i / n;
      final Offset top = Offset(hx - kRimHalf + t * kRimHalf * 2, hy + 2);
      final Offset bot = Offset(hx - kRimHalf * 0.55 + t * kRimHalf * 1.1 + sway, hy + 52 + _netSway * 8);
      canvas.drawLine(top, bot, net);
    }
    for (int k = 1; k <= 3; k++) {
      final double y = hy + 2 + k * 16 + _netSway * k * 2;
      final double w = kRimHalf * (1 - k * 0.15);
      canvas.drawLine(Offset(hx - w + sway * k / 3, y), Offset(hx + w + sway * k / 3, y), net);
    }
    // front rim
    canvas.drawArc(Rect.fromCenter(center: Offset(hx, hy), width: kRimHalf * 2, height: 14), 0, math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFF5A2A));
  }

  void _paintBall(Canvas canvas) {
    final Offset c = Offset(court.x, court.y);
    // trail / fire
    for (int i = 0; i < _trail.length; i++) {
      final double k = i / _trail.length;
      canvas.drawCircle(_trail[i], kBallR * k * 0.9,
          Paint()..color = (court.onFire ? const Color(0xFFFF6A1D) : Colors.white).withValues(alpha: 0.18 * k));
    }
    if (court.onFire) paintGlow(canvas, c, kBallR * 2.4, const Color(0xFFFF6A1D), 0.6);
    final double floorY = kBH - 70;
    final double hgt = (floorY - c.dy).clamp(0.0, 600.0);
    paintShadow(canvas, Offset(c.dx, floorY + 8), kBallR * 2.2 * (1 - hgt / 900), kBallR * 0.6, 0.45 * (1 - hgt / 700));
    if (skin.drawSprite(canvas, 'ball', Rect.fromCircle(center: c, radius: kBallR), angle: court.angle)) return;
    paintSphere(canvas, c, kBallR, const Color(0xFFE8731E), shadow: false);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(court.angle);
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: kBallR)));
    final Paint seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF2A140A);
    canvas.drawLine(const Offset(-kBallR, 0), const Offset(kBallR, 0), seam);
    canvas.drawLine(const Offset(0, -kBallR), const Offset(0, kBallR), seam);
    canvas.drawArc(Rect.fromCircle(center: const Offset(-kBallR * 1.25, 0), radius: kBallR), -0.9, 1.8, false, seam);
    canvas.drawArc(Rect.fromCircle(center: const Offset(kBallR * 1.25, 0), radius: kBallR), math.pi - 0.9, 1.8, false, seam);
    canvas.restore();
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return Stack(fit: StackFit.expand, children: <Widget>[
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _panStart,
        onPanUpdate: _panUpdate,
        onPanEnd: _panEnd,
        child: CustomPaint(painter: ArcadePainter(_paint, frame), size: Size.infinite),
      ),
      ValueListenableBuilder<int>(
        valueListenable: frame,
        builder: (_, __, ___) {
          final int left = court.left.ceil();
          return Stack(children: <Widget>[
            Positioned(
              top: pad.top + 62,
              left: 12,
              right: 12,
              child: Row(children: <Widget>[
                Expanded(
                  child: Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                    for (int s = 0; s < seats; s++)
                      ArcadeHudPill(
                        color: s == me ? skin.accent : skin.player(s),
                        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                          Icon(s == me ? Icons.person_rounded : Icons.smart_toy_rounded, size: 13, color: skin.player(s)),
                          const SizedBox(width: 4),
                          Text('${scoreOf(s)}', style: const TextStyle(fontSize: 14)),
                        ]),
                      ),
                  ]),
                ),
                ArcadeHudPill(
                  color: left <= 10 ? const Color(0xFFFF2D55) : skin.accent2,
                  child: Text('0:${left.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 16)),
                ),
              ]),
            ),
            if (court.onFire)
              Positioned(
                top: pad.top + 104,
                left: 0,
                right: 0,
                child: Center(
                    child: ArcadeHudPill(
                        color: const Color(0xFFFF6A1D),
                        child: Text(l.tx('آتشین x2', 'ON FIRE x2'), style: const TextStyle(fontSize: 12)))),
              ),
            if (_banner.isNotEmpty)
              Positioned(
                  left: 0,
                  right: 0,
                  top: MediaQuery.sizeOf(context).height * 0.45,
                  child: Center(child: ArcadeBanner(_banner, color: skin.accent, size: _banner.length > 3 ? 36 : 64))),
            if (court.countdown <= 0 && court.shots == 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: pad.bottom + 20,
                child: Center(
                  child: Text(l.tx('توپ را رو به بالا پرتاب کن', 'Swipe up to shoot'),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w800)),
                ),
              ),
          ]);
        },
      ),
    ]);
  }
}
