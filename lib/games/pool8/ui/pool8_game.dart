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
import '../../billiards/core/pool_aim.dart';
import '../../core/game_contract.dart';
import '../core/pool8_core.dart';

/// Sprite keys (assets/games/pool8/skin.json): table (portrait table incl. rails, cloth area = 803x1342 units inside
/// a 70-unit rail), ball_0 .. ball_15 (top view), cue (stick, tip pointing UP).
ArcadeSkin pool8Skin() => ArcadeSkin(
      gameId: 'pool8',
      bgTop: const Color(0xFF0C1B2A),
      bgBottom: const Color(0xFF03070E),
      accent: const Color(0xFF16C784),
      accent2: const Color(0xFFFFC94A),
      glow: const Color(0xFF16C784),
      players: const <Color>[Color(0xFF39C6FF), Color(0xFFFF4F9A)],
    );

const List<Color> kPoolBallColors = <Color>[
  Color(0xFFF7F3E8), // cue
  Color(0xFFF5C518), Color(0xFF1E5BD8), Color(0xFFD7262E), Color(0xFF5B2A9C),
  Color(0xFFF07A1A), Color(0xFF168A4A), Color(0xFF7A1F2B), Color(0xFF111114),
  Color(0xFFF5C518), Color(0xFF1E5BD8), Color(0xFFD7262E), Color(0xFF5B2A9C),
  Color(0xFFF07A1A), Color(0xFF168A4A), Color(0xFF7A1F2B),
];

class Pool8Game extends StatefulWidget {
  const Pool8Game({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<Pool8Game> createState() => _Pool8GameState();
}

class _Pool8GameState extends ArcadeLoopState<Pool8Game> {
  late final Pool8Blitz game;
  late final ArcadeSkin skin = pool8Skin();
  late final ArcadeFx fx;
  ArcadeTurnNet? tn;
  final math.Random _rng = math.Random(7);
  double _aim = -math.pi / 2;
  double _power = 0;
  bool _dragPower = false;
  bool _movingCue = false;
  PoolBotPlanner? _bot;
  double _botDelay = 0;
  bool _done = false;
  String _banner = '';
  double _bannerT = 0;
  // table → screen mapping
  double _s = 0.3;
  Offset _o = Offset.zero;
  static const double _rail = 70;

  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  bool get myTurn => game.current == me;
  bool _isBot(int seat) => !l.online && seat != me;

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    final int seed = l.net?.seed ?? l.seed ?? 3;
    game = Pool8Blitz(shotClock: l.daily ? 15 : 20, breaker: seed.isEven ? 0 : 1);
    game.match.world.onImpact = _onImpact;
    game.match.world.onPocket = _onPocket;
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final NetLink? n = l.net;
    if (n != null) {
      tn = ArcadeTurnNet(n, onMove: _onNet, onReplayDone: () {
        tn?.turn = game.current;
        if (game.over) _finish();
      })
        ..start();
    }
    _say(game.current == me ? l.tx('نوبت توست — بزن!', 'Your break!') : l.tx('حریف شروع می‌کند', 'Opponent breaks'));
  }

  @override
  void dispose() {
    tn?.dispose();
    super.dispose();
  }

  void _say(String s) {
    _banner = s;
    _bannerT = 1.8;
  }

  void _onImpact(double x, double y, double strength, bool cushion) {
    if (tn?.replaying ?? false) return;
    if (strength > 900 && !cushion) {
      fx.burst(_px(x, y), Colors.white, count: 5, speed: 90, size: 2, life: 0.25);
      if (strength > 2400) HapticFeedback.selectionClick();
    }
  }

  void _onPocket(int id, int pocket) {
    if (tn?.replaying ?? false) return;
    final List<double> p = PoolConfig.pockets[pocket];
    final Offset at = _px(p[0], p[1]);
    fx.burst(at, kPoolBallColors[id], count: 16, speed: 140, size: 3.5, kind: ParticleKind.orb);
    fx.ring(at, skin.accent2, size: 18);
    HapticFeedback.lightImpact();
  }

  Offset _px(double x, double y) => _o + Offset(x, y) * _s;
  Offset _table(Offset screen) => (screen - _o) / _s;

  // ------------------------------------------------------------------ net
  Future<void> _onNet(NetMove m) async {
    if (!m.replay && m.seat == me) return;
    if (m.isForfeit) {
      final int seat = (m.data['seat'] as num?)?.toInt() ?? m.seat;
      if (!_done) {
        _forfeitWinner = 1 - seat;
        _finish();
      }
      return;
    }
    if (m.isTimeout) {
      while (game.simulating && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      game.timeout();
      tn?.turn = game.current;
      return;
    }
    final String a = '${m.data['a']}';
    if (a == 'snap') {
      while (game.simulating && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      if ((m.data['s'] as Map<dynamic, dynamic>?)?['sc'] == game.match.shotCount) {
        game.match.applySnap(Map<String, dynamic>.from(m.data['s'] as Map<dynamic, dynamic>));
      }
      return;
    }
    while (game.simulating && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (a == 'to') {
      game.timeout();
    } else if (a == 'shot') {
      final Map<String, dynamic> d = m.data;
      final PoolShot s = PoolShot(
        dirX: (d['dx'] as num).toDouble(),
        dirY: (d['dy'] as num).toDouble(),
        power: (d['p'] as num).toDouble(),
        spin: (d['s'] as num?)?.toDouble() ?? 0,
        side: (d['e'] as num?)?.toDouble() ?? 0,
        cueX: (d['cx'] as num?)?.toDouble(),
        cueY: (d['cy'] as num?)?.toDouble(),
      );
      if (m.replay) {
        game.playNow(s);
      } else {
        game.shoot(s);
      }
    }
    tn?.turn = game.current;
  }

  int? _forfeitWinner;

  // ------------------------------------------------------------------ input
  void _shoot(double power) {
    if (!myTurn || !game.aiming || _done) return;
    final PoolShot s = PoolShot(
      dirX: math.cos(_aim),
      dirY: math.sin(_aim),
      power: power.clamp(0.04, 1.0),
      cueX: game.match.ballInHand ? game.match.cue.x : null,
      cueY: game.match.ballInHand ? game.match.cue.y : null,
    );
    if (game.match.validate(s) != null) return;
    if (tn != null) unawaited(tn!.send(<String, dynamic>{'a': 'shot', ...s.toJson()}));
    game.shoot(s);
    fx.shake(power * 4);
    HapticFeedback.mediumImpact();
  }

  void _panStart(DragStartDetails d) {
    if (!myTurn || !game.aiming) return;
    final Offset t = _table(d.localPosition);
    final PoolBall c = game.match.cue;
    _movingCue = game.match.ballInHand && (t - Offset(c.x, c.y)).distance < PoolConfig.ballR * 3;
    _panUpdate(DragUpdateDetails(globalPosition: d.globalPosition, localPosition: d.localPosition));
  }

  void _panUpdate(DragUpdateDetails d) {
    if (!myTurn || !game.aiming) return;
    final Offset t = _table(d.localPosition);
    final PoolBall c = game.match.cue;
    if (_movingCue) {
      final (double, double)? p = game.nearestFreeSpot(t.dx, t.dy);
      if (p != null) {
        c.x = p.$1;
        c.y = p.$2;
      }
      return;
    }
    final Offset v = t - Offset(c.x, c.y);
    if (v.distance > 4) _aim = math.atan2(v.dy, v.dx);
  }

  // ------------------------------------------------------------------ loop
  @override
  void tick(double dt) {
    if (_bannerT > 0) {
      _bannerT -= dt;
      if (_bannerT <= 0) _banner = '';
    }
    if (_done) {
      fx.update(dt);
      return;
    }
    if (game.simulating) {
      final PoolShotReport? r = game.stepShot(2);
      if (r != null) _afterShot(r);
    } else if (game.aiming && !game.over) {
      final int cur = game.current;
      if (_isBot(cur)) {
        _botTurn(dt);
      } else if (tn == null || cur == me) {
        if (game.tickClock(dt)) {
          if (tn != null) unawaited(tn!.send(<String, dynamic>{'a': 'to'}));
          game.timeout();
          tn?.turn = game.current;
          _say(l.tx('وقت تمام شد! خطا', 'SHOT CLOCK! Foul'));
          fx.flashScreen(const Color(0xFFFF2D55), 0.25);
        }
      } else {
        game.clock += dt; // remote shooter's clock (display only)
      }
    }
    if (game.over || _forfeitWinner != null) _finish();
    fx.update(dt);
  }

  void _botTurn(double dt) {
    if (game.match.ballInHand && _bot == null) {
      // bot places the cue ball somewhere sensible before planning
      final (double, double)? p = game.nearestFreeSpot(PoolConfig.breakCueX, PoolConfig.breakCueY);
      if (p != null && game.match.canPlaceCue(p.$1, p.$2)) {
        game.match.cue
          ..x = p.$1
          ..y = p.$2;
      }
    }
    _bot ??= PoolBotPlanner(
        match: game.match, level: Pool8Blitz.levelFor(botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty)), rng: _rng);
    final PoolBotPlanner b = _bot!;
    if (!b.done) {
      b.step(3);
      _botDelay = 0.7;
      return;
    }
    final PoolShot s = b.result();
    // swing the cue toward the planned direction before striking
    final double target = math.atan2(s.dirY, s.dirX);
    double diff = target - _aim;
    while (diff > math.pi) {
      diff -= math.pi * 2;
    }
    while (diff < -math.pi) {
      diff += math.pi * 2;
    }
    _aim += diff * math.min(1, dt * 6);
    _power = s.power;
    _botDelay -= dt;
    if (_botDelay <= 0) {
      _bot = null;
      _aim = target;
      if (game.shoot(s) || game.shoot(PoolShot(dirX: s.dirX, dirY: s.dirY, power: s.power.clamp(0.1, 1.0)))) {
        fx.shake(s.power * 4);
      } else {
        game.timeout(); // never let a bot stall the table
      }
      _power = 0;
    }
  }

  void _afterShot(PoolShotReport r) {
    if (tn != null && r.shooter == me) {
      unawaited(tn!.send(<String, dynamic>{'a': 'snap', 's': game.match.toSnap()}));
    }
    tn?.turn = game.current;
    if (r.isFoul) {
      _say(switch (r.foul) {
        PoolFoul.scratch => l.tx('خطا: توپ سفید افتاد', 'Foul: scratch'),
        PoolFoul.noContact => l.tx('خطا: به هیچ توپی نخورد', 'Foul: no contact'),
        PoolFoul.wrongBallFirst => l.tx('خطا: توپ اشتباه', 'Foul: wrong ball first'),
        PoolFoul.noRail => l.tx('خطا: به دیواره نخورد', 'Foul: no rail'),
        PoolFoul.none => '',
      });
    } else if (r.assigned != PoolGroup.none) {
      final bool solids = r.assigned == PoolGroup.solids;
      _say(r.shooter == me
          ? l.tx(solids ? 'تو: توپ‌های ساده' : 'تو: توپ‌های راه‌راه', solids ? 'You: SOLIDS' : 'You: STRIPES')
          : l.tx(solids ? 'حریف: ساده' : 'حریف: راه‌راه', solids ? 'Rival: SOLIDS' : 'Rival: STRIPES'));
    } else if (r.pocketed.isNotEmpty && r.continues) {
      _say(l.tx('عالی! دوباره بزن', 'Nice! Shoot again'));
    } else if (!game.over) {
      _say(game.current == me ? l.tx('نوبت توست', 'Your turn') : l.tx('نوبت حریف', "Rival's turn"));
    }
    if (r.pocketed.length >= 2) fx.text('x${r.pocketed.length}', _px(PoolConfig.tableW / 2, PoolConfig.tableH / 2), skin.accent2, size: 30);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    final List<int> order = _forfeitWinner != null ? <int>[_forfeitWinner!, 1 - _forfeitWinner!] : game.ranking();
    if (order.first == me) {
      _say(l.tx('برنده شدی!', 'YOU WIN!'));
      fx.confetti(_px(PoolConfig.tableW / 2, PoolConfig.tableH / 2), count: 60);
    } else {
      _say(l.tx('باختی', 'YOU LOSE'));
    }
    Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      l.onFinish(rankedResult(l, order, whatFa: '${game.potted[me]} توپ', whatEn: '${game.potted[me]} balls'));
    });
  }

  // ------------------------------------------------------------------ render
  void _paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, size, skin, time, bokeh: false);
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    const double tw = PoolConfig.tableW + _rail * 2, th = PoolConfig.tableH + _rail * 2;
    final double avH = size.height - pad.top - pad.bottom - 210;
    _s = math.min((size.width - 70) / tw, avH / th);
    _o = Offset((size.width - 50 - tw * _s) / 2 + _rail * _s, pad.top + 120 + _rail * _s);
    final Offset sh = fx.shakeOffset;
    canvas.save();
    canvas.translate(sh.dx, sh.dy);
    canvas.save();
    canvas.translate(_o.dx, _o.dy);
    canvas.scale(_s);
    _paintTable(canvas);
    _paintBalls(canvas);
    if (game.aiming && !game.over && !_done && (myTurn || _isBot(game.current))) _paintAim(canvas);
    canvas.restore();
    fx.paint(canvas);
    canvas.restore();
    fx.paintFlash(canvas, size);
  }

  void _paintTable(Canvas canvas) {
    const Rect cloth = Rect.fromLTWH(0, 0, PoolConfig.tableW, PoolConfig.tableH);
    final Rect outer = cloth.inflate(_rail);
    if (skin.drawSprite(canvas, 'table', outer)) return;
    // drop shadow + wooden rail with bevel
    canvas.drawRRect(RRect.fromRectAndRadius(outer.shift(const Offset(0, 30)), const Radius.circular(60)), Paint()
      ..color = const Color(0x99000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40));
    canvas.drawRRect(
        RRect.fromRectAndRadius(outer, const Radius.circular(60)),
        Paint()
          ..shader = ui.Gradient.linear(outer.topLeft, outer.bottomRight,
              <Color>[const Color(0xFF7A4A24), const Color(0xFF4A2A12), const Color(0xFF6B3D1C)], <double>[0, 0.5, 1]));
    canvas.drawRRect(RRect.fromRectAndRadius(outer.deflate(8), const Radius.circular(52)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0x33FFE2B0));
    // cushions
    canvas.drawRect(cloth.inflate(26), Paint()..color = const Color(0xFF0B6B45));
    // cloth with soft overhead lamp
    canvas.drawRect(
        cloth,
        Paint()
          ..shader = ui.Gradient.radial(cloth.center, cloth.longestSide * 0.62,
              <Color>[const Color(0xFF1FA868), const Color(0xFF0E7A49), const Color(0xFF07502F)], <double>[0, 0.6, 1]));
    // diamonds
    final Paint dia = Paint()..color = const Color(0xFFF2E6C9);
    for (int i = 1; i < 4; i++) {
      canvas.drawCircle(Offset(PoolConfig.tableW * i / 4, -_rail / 2 - 6), 6, dia);
      canvas.drawCircle(Offset(PoolConfig.tableW * i / 4, PoolConfig.tableH + _rail / 2 + 6), 6, dia);
    }
    for (int i = 1; i < 8; i++) {
      if (i == 4) continue;
      canvas.drawCircle(Offset(-_rail / 2 - 6, PoolConfig.tableH * i / 8), 6, dia);
      canvas.drawCircle(Offset(PoolConfig.tableW + _rail / 2 + 6, PoolConfig.tableH * i / 8), 6, dia);
    }
    // head string + foot spot
    canvas.drawLine(const Offset(0, PoolConfig.headStringY), const Offset(PoolConfig.tableW, PoolConfig.headStringY),
        Paint()
          ..color = const Color(0x22FFFFFF)
          ..strokeWidth = 3);
    canvas.drawCircle(const Offset(PoolConfig.footSpotX, PoolConfig.footSpotY), 6, Paint()..color = const Color(0x44FFFFFF));
    // pockets
    for (int i = 0; i < PoolConfig.pockets.length; i++) {
      final Offset c = Offset(PoolConfig.pockets[i][0], PoolConfig.pockets[i][1]);
      canvas.drawCircle(c, 44, Paint()..color = const Color(0xFF2A1A0C));
      canvas.drawCircle(
          c,
          38,
          Paint()
            ..shader = ui.Gradient.radial(c, 38, <Color>[const Color(0xFF000000), const Color(0xFF151515)]));
    }
  }

  void _paintBalls(Canvas canvas) {
    const double r = PoolConfig.ballR;
    for (final PoolBall b in game.match.balls) {
      if (b.pocketed) continue;
      final Offset c = Offset(b.x, b.y);
      canvas.drawOval(Rect.fromCenter(center: c + const Offset(6, 9), width: r * 2.1, height: r * 1.6), Paint()
        ..color = const Color(0x77000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      if (skin.drawSprite(canvas, 'ball_${b.id}', Rect.fromCircle(center: c, radius: r))) continue;
      final Color col = kPoolBallColors[b.id];
      if (b.id >= 9) {
        paintSphere(canvas, c, r, const Color(0xFFF7F3E8), shadow: false);
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
        canvas.drawRect(Rect.fromCenter(center: c, width: r * 2, height: r * 1.05), Paint()..color = col);
        canvas.drawCircle(c - Offset(r * 0.35, r * 0.4), r * 0.55, Paint()
          ..color = const Color(0x40FFFFFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        canvas.restore();
      } else {
        paintSphere(canvas, c, r, col, shadow: false);
      }
      if (b.id > 0) {
        canvas.drawCircle(c, r * 0.45, Paint()..color = const Color(0xFFF7F3E8));
        drawLabel(canvas, '${b.id}', c, size: r * 0.62, color: const Color(0xFF111111));
      }
    }
    // ball-in-hand halo
    if (game.match.ballInHand && game.aiming && myTurn) {
      final PoolBall c = game.match.cue;
      canvas.drawCircle(Offset(c.x, c.y), r * 1.9 + math.sin(time * 5) * 3, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = skin.accent2.withValues(alpha: 0.8));
    }
  }

  void _paintAim(Canvas canvas) {
    final PoolBall c = game.match.cue;
    if (c.pocketed) return;
    final double dx = math.cos(_aim), dy = math.sin(_aim);
    final Offset cp = Offset(c.x, c.y);
    final PoolAimPrediction p = poolPredict(game.match.balls, dx, dy);
    final Offset ghost = Offset(p.ghostX, p.ghostY);
    final Paint line = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 3;
    canvas.drawLine(cp, ghost, line);
    canvas.drawCircle(ghost, PoolConfig.ballR, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.8));
    if (p.hitBall > 0) {
      final bool legal = game.match.isLegalTarget(p.hitBall);
      final PoolBall o = game.match.balls[p.hitBall];
      final Offset op = Offset(o.x, o.y);
      canvas.drawLine(op, op + Offset(p.objDirX, p.objDirY) * 220 * p.cutFactor.clamp(0.25, 1.0), Paint()
        ..color = (legal ? skin.accent : const Color(0xFFFF2D55)).withValues(alpha: 0.9)
        ..strokeWidth = 4);
      canvas.drawLine(ghost, ghost + Offset(p.cueDirX, p.cueDirY) * 120 * (1 - p.cutFactor * 0.7), Paint()
        ..color = Colors.white38
        ..strokeWidth = 2);
    }
    // cue stick, pulled back by the power
    final double pull = 30 + _power * 160;
    final Offset tip = cp - Offset(dx, dy) * (PoolConfig.ballR + pull);
    final Offset butt = tip - Offset(dx, dy) * 760;
    canvas.drawLine(tip + const Offset(8, 12), butt + const Offset(8, 12), Paint()
      ..strokeWidth = 16
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    if (!skin.drawSprite(canvas, 'cue', Rect.fromCenter(center: (tip + butt) / 2, width: 22, height: 760),
        angle: _aim - math.pi / 2)) {
      canvas.drawLine(
          tip,
          butt,
          Paint()
            ..strokeWidth = 14
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(tip, butt,
                <Color>[const Color(0xFFEFE6D2), const Color(0xFFD7B583), const Color(0xFF6B3A18), const Color(0xFF1E1410)],
                <double>[0, 0.05, 0.6, 1]));
      canvas.drawLine(tip, tip - Offset(dx, dy) * 10, Paint()
        ..strokeWidth = 14
        ..color = const Color(0xFF3C7BD6));
    }
  }

  // ------------------------------------------------------------------ widgets
  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return Stack(fit: StackFit.expand, children: <Widget>[
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _panStart,
        onPanUpdate: _panUpdate,
        onPanEnd: (_) => _movingCue = false,
        child: CustomPaint(painter: ArcadePainter(_paint, frame), size: Size.infinite),
      ),
      ValueListenableBuilder<int>(
        valueListenable: frame,
        builder: (_, __, ___) => Stack(children: <Widget>[
          Positioned(
            top: pad.top + 62,
            left: 12,
            right: 12,
            child: Row(children: <Widget>[
              for (int s = 0; s < 2; s++) ...<Widget>[
                Expanded(child: _seatPill(s)),
                if (s == 0) const SizedBox(width: 8),
              ],
            ]),
          ),
          if (_banner.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.sizeOf(context).height * 0.42,
              child: Center(child: ArcadeBanner(_banner, color: skin.accent, size: 30)),
            ),
        ]),
      ),
      // power bar: drag down, release to shoot
      Positioned(
        right: 8,
        top: pad.top + 150,
        bottom: pad.bottom + 90,
        width: 44,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _dragPower = true,
          onVerticalDragUpdate: (DragUpdateDetails d) {
            if (!myTurn || !game.aiming) return;
            _power = (_power + d.delta.dy / 260).clamp(0.0, 1.0);
          },
          onVerticalDragEnd: (_) {
            _dragPower = false;
            if (_power > 0.03) _shoot(_power);
            _power = 0;
          },
          child: ValueListenableBuilder<int>(
            valueListenable: frame,
            builder: (_, __, ___) => CustomPaint(painter: _PowerBar(_power, skin.accent, skin.accent2, _dragPower || _power > 0)),
          ),
        ),
      ),
    ]);
  }

  Widget _seatPill(int s) {
    final bool turn = game.current == s && !game.over;
    final PoolGroup g = game.match.groups[s];
    final String name = l.netName(s) ?? (s == me ? l.playerName : l.tx('ربات', 'Bot'));
    final List<int> left = g == PoolGroup.none ? const <int>[] : game.match.groupBalls(g).where((int id) => !game.match.balls[id].pocketed).toList();
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: turn ? 1 : 0.55,
      child: ArcadeHudPill(
        color: turn ? skin.player(s) : Colors.white24,
        child: Row(children: <Widget>[
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 6),
          if (g == PoolGroup.none)
            Text('—', style: TextStyle(color: Colors.white.withValues(alpha: 0.5)))
          else
            for (final int id in left.take(7))
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(shape: BoxShape.circle, color: kPoolBallColors[id], border: id >= 9 ? Border.all(color: Colors.white, width: 1.5) : null),
              ),
          if (g != PoolGroup.none && left.isEmpty)
            Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF111114))),
          const Spacer(),
          if (turn)
            Text('${game.clockLeft.ceil()}',
                style: TextStyle(fontSize: 13, color: game.clockLeft < 6 ? const Color(0xFFFF2D55) : Colors.white)),
        ]),
      ),
    );
  }
}

class _PowerBar extends CustomPainter {
  _PowerBar(this.v, this.a, this.b, this.active);
  final double v;
  final Color a, b;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Rect.fromLTWH(size.width / 2 - 9, 0, 18, size.height);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(9)), Paint()..color = const Color(0x66000000));
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(9)), Paint()
      ..style = PaintingStyle.stroke
      ..color = a.withValues(alpha: active ? 0.9 : 0.4));
    final Rect f = Rect.fromLTRB(r.left + 3, r.top + 3, r.right - 3, r.top + 3 + (r.height - 6) * v);
    canvas.drawRRect(RRect.fromRectAndRadius(f, const Radius.circular(6)),
        Paint()..shader = ui.Gradient.linear(f.topCenter, f.bottomCenter, <Color>[a, b, const Color(0xFFFF2D55)], <double>[0, 0.5, 1]));
    drawLabel(canvas, 'PULL', Offset(size.width / 2, size.height + 12), size: 10, color: Colors.white70);
  }

  @override
  bool shouldRepaint(covariant _PowerBar o) => true;
}
