import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../arcade_kit/arcade_controls.dart';
import '../../arcade_kit/arcade_fx.dart';
import '../../arcade_kit/arcade_joystick.dart';
import '../../arcade_kit/arcade_loop.dart';
import '../../arcade_kit/arcade_net.dart';
import '../../arcade_kit/arcade_result.dart';
import '../../arcade_kit/arcade_skin.dart';
import '../../core/game_contract.dart';
import '../core/bomb_core.dart';

/// Sprite keys: player_0..3, bomb, crate, wall, floor, pu_range, pu_bomb, pu_speed.
ArcadeSkin bombSkin() => ArcadeSkin(
      gameId: 'bomb_arena',
      bgTop: const Color(0xFF1A1030),
      bgBottom: const Color(0xFF07040F),
      accent: const Color(0xFFFF4D3D),
      accent2: const Color(0xFFFFB13D),
      glow: const Color(0xFFFF7A3D),
      players: const <Color>[Color(0xFFF5F7FF), Color(0xFF39C6FF), Color(0xFFFF4F9A), Color(0xFF7CFF7A)],
    );

class BombGame extends StatefulWidget {
  const BombGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<BombGame> createState() => _BombGameState();
}

class _BombGameState extends ArcadeLoopState<BombGame> {
  late final BombArena arena;
  late final ArcadeSkin skin = bombSkin();
  late final ArcadeFx fx;
  ArcadeRt? rt;
  double _jx = 0, _jy = 0;
  bool _bombTap = false, _trapTap = false;
  int _bombSeq = 0, _trapSeq = 0;
  final Map<int, int> _seenBomb = <int, int>{}, _seenTrap = <int, int>{};
  bool _done = false;
  String _banner = '';
  double _endIn = -1;
  double _tile = 28, _ox = 0, _oy = 120;
  Offset _px(double x, double y) => Offset(_ox + x * _tile, _oy + y * _tile);

  GameLaunch get l => widget.launch;
  int get me => l.mySeat;
  int get seats => l.net?.seatCount ?? l.playerCount.clamp(2, 4);
  bool get host => rt == null || rt!.isHost;

  @override
  void initState() {
    super.initState();
    fx = ArcadeFx(enabled: l.fancyEffects && !l.reducedMotion, skin: skin);
    final double sk = botSkillFor(l.daily ? BotDifficulty.hard : l.difficulty);
    arena = BombArena(
      seed: l.net?.seed ?? l.seed ?? 5,
      count: seats,
      botSkill: l.online ? const <double>[] : <double>[for (int i = 0; i < seats; i++) i == 0 ? 0 : sk],
    );
    unawaited(skin.load().then((_) => mounted ? setState(() {}) : null));
    final NetLink? n = l.net;
    if (n != null) {
      rt = ArcadeRt(n, hz: 14)
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
    if (m.data['t'] == 'end') {
      final List<int> order = (m.data['o'] as List<dynamic>).map((dynamic e) => (e as num).toInt()).toList();
      _finish(order);
    }
  }

  @override
  void tick(double dt) {
    final (double dx, double dy) = dpad4(_jx, _jy);
    final ArcadeRt? r = rt;
    if (host) {
      arena.input(me, dx, dy);
      if (_bombTap) arena.placeBomb(me);
      if (_trapTap) arena.placeTrap(me);
      if (r != null) {
        // remote inputs
        r.states.forEach((int seat, Map<String, dynamic> st) {
          if (seat == me || seat >= arena.players.length) return;
          arena.input(seat, (st['x'] as num).toDouble(), (st['y'] as num).toDouble());
          final int b = (st['b'] as num).toInt(), t = (st['t'] as num).toInt();
          if (b > (_seenBomb[seat] ?? 0)) {
            _seenBomb[seat] = b;
            arena.placeBomb(seat);
          }
          if (t > (_seenTrap[seat] ?? 0)) {
            _seenTrap[seat] = t;
            arena.placeTrap(seat);
          }
        });
        for (final int s in r.net.forfeitedSeats) {
          if (s < arena.players.length) arena.eliminate(s);
        }
        for (final int s in r.activeSeats) {
          if (s != me && r.isStale(s, const Duration(seconds: 20)) && arena.countdown <= 0) arena.players[s].dx = 0;
        }
      }
      if (!_done) arena.step(dt);
      if (r != null) r.pumpSnapshot(dt, arena.snapshot);
      if (!_done && arena.over) {
        final List<int> order = arena.ranking();
        if (r != null) unawaited(r.log(<String, dynamic>{'t': 'end', 'o': order}));
        _finish(order);
      } else if (!_done && r == null && !arena.players[me].alive) {
        _endIn = _endIn < 0 ? 1.5 : _endIn - dt;
        if (_endIn <= 0) {
          int guard = 0;
          while (!arena.over && guard++ < 30 * 300) {
            arena.step(1 / 30);
          }
          _finish(arena.ranking());
        }
      }
    } else if (r != null) {
      if (_bombTap) _bombSeq++;
      if (_trapTap) _trapSeq++;
      r.pump(dt, () => <String, dynamic>{'x': dx, 'y': dy, 'b': _bombSeq, 't': _trapSeq}, event: 'in');
      final Map<String, dynamic>? s = r.snapshot;
      if (s != null) {
        arena.applySnapshot(s);
        r.snapshot = null;
      }
      // countdown runs locally until the first snapshot
      if (arena.time == 0 && arena.countdown > 0) arena.countdown -= dt;
    }
    _bombTap = false;
    _trapTap = false;
    if (arena.countdown > 0) {
      _banner = '${arena.countdown.ceil()}';
    } else if (arena.time < 0.8) {
      _banner = 'GO!';
    } else if (_banner == 'GO!') {
      _banner = '';
    }
    for (final BEvent e in arena.events) {
      final Offset at = _px(e.x, e.y);
      final double t = _tile;
      switch (e.kind) {
        case 'boom':
          fx.burst(at, const Color(0xFFFFB13D), count: 26, speed: t * 6, size: t * 0.12, life: 0.5, kind: ParticleKind.orb);
          fx.burst(at, const Color(0xFF555566), count: 8, speed: t * 1.6, size: t * 0.3, life: 1.0, kind: ParticleKind.smoke);
          fx.shake(7);
          HapticFeedback.mediumImpact();
        case 'crate':
          fx.burst(at, const Color(0xFFB07A3E), count: 12, speed: t * 4, size: t * 0.14, life: 0.6, kind: ParticleKind.shard, gravity: t * 6);
        case 'pickup':
          fx.ring(at, skin.accent2, size: t * 0.4, life: 0.4);
          if (e.seat == me) HapticFeedback.lightImpact();
        case 'stun':
          fx.burst(at, const Color(0xFFFFE14D), count: 14, speed: t * 3, size: t * 0.1);
        case 'out':
          fx.burst(at, skin.player(e.seat), count: 30, speed: t * 5, size: t * 0.12, kind: ParticleKind.orb);
          if (e.seat == me) {
            _banner = l.tx('حذف شدی!', 'KNOCKED OUT!');
            fx.flashScreen(const Color(0xFFFF2D55));
            HapticFeedback.heavyImpact();
          }
      }
    }
    arena.events.clear();
    fx.update(dt);
  }

  void _finish(List<int> order) {
    if (_done) return;
    _done = true;
    if (order.isNotEmpty && order.first == me) {
      _banner = l.tx('برنده!', 'WINNER!');
      fx.confetti(_px(arena.players[me].x, arena.players[me].y), count: 50);
    }
    l.onFinish(rankedResult(l, order, whatFa: '${arena.players[me].kills} حذف', whatEn: '${arena.players[me].kills} KOs'));
  }

  // ------------------------------------------------------------------ render
  void _paint(Canvas canvas, Size size) {
    paintBackdrop(canvas, size, skin, time);
    final double tile = math.min((size.width - 16) / BombArena.w, (size.height - 300) / BombArena.h);
    final double ox = (size.width - tile * BombArena.w) / 2;
    final double oy = math.max(MediaQuery.paddingOf(context).top + 116, (size.height - tile * BombArena.h) / 2 - 60);
    _tile = tile;
    _ox = ox;
    _oy = oy;
    final Offset sh = fx.shakeOffset;
    canvas.save();
    canvas.translate(ox + sh.dx * 0.6, oy + sh.dy * 0.6);
    canvas.scale(tile);
    // arena frame
    paintBlock(canvas, Rect.fromLTWH(-0.2, -0.2, BombArena.w + 0.4, BombArena.h + 0.4), const Color(0xFF2B1F4A), radius: 0.4, depth: 0.25);
    for (int y = 0; y < BombArena.h; y++) {
      for (int x = 0; x < BombArena.w; x++) {
        final Rect r = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
        final String c = arena.grid[y][x];
        if (c != '#') {
          if (!skin.drawSprite(canvas, 'floor', r)) {
            canvas.drawRect(r, Paint()..color = (x + y).isEven ? const Color(0xFF3A6B4E) : const Color(0xFF336147));
          }
        }
      }
    }
    // soft shadows under walls/crates
    for (int y = 0; y < BombArena.h; y++) {
      for (int x = 0; x < BombArena.w; x++) {
        if (arena.grid[y][x] != '.') {
          canvas.drawRect(Rect.fromLTWH(x + 0.1, y + 0.25, 1, 1), Paint()
            ..color = const Color(0x55000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.08));
        }
      }
    }
    // traps (own traps visible, enemy traps faint)
    for (final Trap t in arena.traps) {
      final Offset c = Offset(t.tx + 0.5, t.ty + 0.5);
      final double a = t.owner == me ? 0.9 : 0.18;
      for (int i = 0; i < 4; i++) {
        final double ang = i * math.pi / 2 + math.pi / 4;
        canvas.drawLine(c, c + Offset(math.cos(ang), math.sin(ang)) * 0.3, Paint()
          ..strokeWidth = 0.07
          ..color = Color.fromRGBO(255, 225, 77, a));
      }
      canvas.drawCircle(c, 0.12, Paint()..color = Color.fromRGBO(180, 180, 200, a));
    }
    // power-ups
    arena.powerups.forEach((int k, Pu p) {
      final Offset c = Offset(k % BombArena.w + 0.5, k ~/ BombArena.w + 0.5 + math.sin(time * 4 + k) * 0.05);
      final (Color col, IconData icon, String key) = switch (p) {
        Pu.range => (const Color(0xFFFF7A3D), Icons.local_fire_department_rounded, 'pu_range'),
        Pu.bomb => (const Color(0xFF39C6FF), Icons.add_circle_rounded, 'pu_bomb'),
        Pu.speed => (const Color(0xFF7CFF7A), Icons.bolt_rounded, 'pu_speed'),
        Pu.trap => (const Color(0xFFFFE14D), Icons.warning_amber_rounded, 'pu_trap'),
      };
      paintGlow(canvas, c, 0.6, col, 0.5);
      if (!skin.drawSprite(canvas, key, Rect.fromCenter(center: c, width: 0.75, height: 0.75))) {
        paintBlock(canvas, Rect.fromCenter(center: c, width: 0.66, height: 0.66), col, radius: 0.16, depth: 0.08, shadow: false);
        _icon(canvas, icon, c, 0.46);
      }
    });
    // walls + crates (drawn back to front for depth)
    for (int y = 0; y < BombArena.h; y++) {
      for (int x = 0; x < BombArena.w; x++) {
        final String c = arena.grid[y][x];
        final Rect r = Rect.fromLTWH(x + 0.03, y - 0.12, 0.94, 0.94);
        if (c == '#') {
          if (!skin.drawSprite(canvas, 'wall', r)) {
            paintBlock(canvas, r, const Color(0xFF5E6B8C), radius: 0.12, depth: 0.16, shadow: false);
            canvas.drawRect(Rect.fromLTWH(x + 0.18, y + 0.02, 0.64, 0.08), Paint()..color = const Color(0x33FFFFFF));
          }
        } else if (c == 'c') {
          if (!skin.drawSprite(canvas, 'crate', r)) {
            paintBlock(canvas, r, const Color(0xFFB9803F), radius: 0.08, depth: 0.14, shadow: false);
            final Paint plank = Paint()
              ..color = const Color(0xFF7A4E22)
              ..strokeWidth = 0.05;
            canvas.drawLine(Offset(r.left + 0.1, r.top + 0.1), Offset(r.right - 0.1, r.bottom - 0.1), plank);
            canvas.drawLine(Offset(r.right - 0.1, r.top + 0.1), Offset(r.left + 0.1, r.bottom - 0.1), plank);
            canvas.drawRect(r.deflate(0.07), Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.05
              ..color = const Color(0xFF8C5A2A));
          }
        }
      }
    }
    // bombs
    for (final Bomb b in arena.bombs) {
      final Offset c = Offset(b.tx + 0.5, b.ty + 0.45);
      final double pulse = 1 + 0.08 * math.sin(time * (8 + (2.4 - b.fuse) * 10));
      paintShadow(canvas, c + const Offset(0.05, 0.3), 0.7, 0.25, 0.5);
      if (!skin.drawSprite(canvas, 'bomb', Rect.fromCenter(center: c, width: 0.8 * pulse, height: 0.8 * pulse))) {
        paintSphere(canvas, c, 0.34 * pulse, b.fuse < 0.6 ? const Color(0xFF6B1A1A) : const Color(0xFF22222E), shadow: false);
        canvas.drawLine(c + const Offset(0.12, -0.28), c + const Offset(0.24, -0.44), Paint()
          ..strokeWidth = 0.06
          ..color = const Color(0xFFCDB38A));
        paintGlow(canvas, c + const Offset(0.25, -0.46), 0.22, const Color(0xFFFFD34E), 0.9);
      }
    }
    // players
    final List<BPlayer> ps = List<BPlayer>.of(arena.players)..sort((BPlayer a, BPlayer b) => a.y.compareTo(b.y));
    for (final BPlayer p in ps) {
      _paintPlayer(canvas, p);
    }
    // flames
    for (final Flame f in arena.flames) {
      final Offset c = Offset(f.tx + 0.5, f.ty + 0.5);
      final double k = (f.life / 0.55).clamp(0.0, 1.0);
      final Rect r = f.dir == 0
          ? Rect.fromCenter(center: c, width: 0.95, height: 0.95)
          : f.dir == 1
              ? Rect.fromCenter(center: c, width: 1.02, height: 0.7 * k + 0.2)
              : Rect.fromCenter(center: c, width: 0.7 * k + 0.2, height: 1.02);
      canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(0.12), const Radius.circular(0.35)), Paint()
        ..color = const Color(0xFFFF4D1D).withValues(alpha: 0.55 * k)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.18));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(0.3)), Paint()
        ..shader = ui.Gradient.radial(c, 0.6, <Color>[
          Colors.white.withValues(alpha: k),
          const Color(0xFFFFE14D).withValues(alpha: k),
          const Color(0xFFFF6A1D).withValues(alpha: 0.8 * k),
        ], const <double>[0, 0.4, 1]));
    }
    canvas.restore();
    canvas.save();
    canvas.translate(sh.dx * 0.6, sh.dy * 0.6);
    fx.paint(canvas);
    canvas.restore();
    fx.paintFlash(canvas, size);
  }

  void _icon(Canvas canvas, IconData i, Offset c, double s) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(i.codePoint), style: TextStyle(fontFamily: i.fontFamily, package: i.fontPackage, fontSize: s, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintPlayer(Canvas canvas, BPlayer p) {
    if (!p.alive && time - p.outAt > 0.6 && arena.time - p.outAt > 0.6) return;
    final Color c = skin.player(p.seat);
    final Offset at = Offset(p.x, p.y);
    final double bob = (p.dx != 0 || p.dy != 0) ? math.sin(time * 16) * 0.04 : 0;
    paintShadow(canvas, at + const Offset(0.05, 0.32), 0.62, 0.22, 0.5);
    canvas.save();
    canvas.translate(at.dx, at.dy - 0.18 + bob);
    if (!p.alive) canvas.scale(0.6);
    if (!skin.drawSprite(canvas, 'player_${p.seat % 4}', const Rect.fromLTWH(-0.42, -0.5, 0.84, 0.95))) {
      // body
      final Rect body = Rect.fromCenter(center: const Offset(0, 0.1), width: 0.66, height: 0.6);
      canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(0.24)), Paint()
        ..shader = ui.Gradient.linear(body.topCenter, body.bottomCenter, <Color>[shade(c, 0.1), shade(c, -0.25)]));
      // head
      paintSphere(canvas, const Offset(0, -0.22), 0.3, c, shadow: false);
      // visor
      final Rect v = Rect.fromCenter(center: const Offset(0, -0.2), width: 0.4, height: 0.17);
      canvas.drawRRect(RRect.fromRectAndRadius(v, const Radius.circular(0.08)), Paint()..color = const Color(0xFF16182A));
      canvas.drawCircle(const Offset(-0.08, -0.2), 0.035, Paint()..color = const Color(0xFF7FF3FF));
      canvas.drawCircle(const Offset(0.08, -0.2), 0.035, Paint()..color = const Color(0xFF7FF3FF));
      // antenna
      canvas.drawLine(const Offset(0, -0.5), const Offset(0, -0.62), Paint()
        ..strokeWidth = 0.04
        ..color = Colors.white70);
      paintGlow(canvas, const Offset(0, -0.64), 0.1, c, 0.9);
    }
    if (p.stun > 0) {
      for (int i = 0; i < 3; i++) {
        final double a = time * 6 + i * 2.1;
        canvas.drawCircle(Offset(math.cos(a) * 0.3, -0.62 + math.sin(a) * 0.08), 0.05, Paint()..color = const Color(0xFFFFE14D));
      }
    }
    canvas.restore();
    if (p.seat == me && p.alive) {
      canvas.drawPath(
          Path()
            ..moveTo(p.x - 0.1, p.y - 0.95)
            ..lineTo(p.x + 0.1, p.y - 0.95)
            ..lineTo(p.x, p.y - 0.8)
            ..close(),
          Paint()..color = Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return Stack(fit: StackFit.expand, children: <Widget>[
      CustomPaint(painter: ArcadePainter(_paint, frame), size: Size.infinite),
      ValueListenableBuilder<int>(
        valueListenable: frame,
        builder: (_, __, ___) {
          final BPlayer mine = arena.players[me];
          final int left = math.max(0, (BombArena.timeLimit - arena.time).ceil());
          return Stack(children: <Widget>[
            Positioned(
              top: pad.top + 62,
              left: 12,
              right: 12,
              child: Row(children: <Widget>[
                for (final BPlayer p in arena.players)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Opacity(
                      opacity: p.alive ? 1 : 0.35,
                      child: ArcadeHudPill(
                        color: skin.player(p.seat),
                        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                          Icon(p.alive ? Icons.smart_toy_rounded : Icons.close_rounded, size: 14, color: skin.player(p.seat)),
                          const SizedBox(width: 3),
                          Text('${p.kills}', style: const TextStyle(fontSize: 13)),
                        ]),
                      ),
                    ),
                  ),
                const Spacer(),
                ArcadeHudPill(
                  color: left < 20 ? const Color(0xFFFF2D55) : skin.accent2,
                  child: Text('${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 15)),
                ),
              ]),
            ),
            Positioned(
              bottom: pad.bottom + 132,
              right: 22,
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                _stat(Icons.local_fire_department_rounded, mine.range),
                _stat(Icons.circle, mine.maxBombs),
                _stat(Icons.bolt_rounded, ((mine.speed - 3.4) / 0.45).round() + 1),
              ]),
            ),
            if (_banner.isNotEmpty) Center(child: ArcadeBanner(_banner, color: skin.accent, size: _banner.length > 4 ? 44 : 64)),
          ]);
        },
      ),
      Positioned(
        left: 0,
        bottom: 0,
        width: MediaQuery.sizeOf(context).width * 0.55,
        height: 230 + pad.bottom,
        child: ArcadeJoystick(color: skin.accent2, onChanged: (double x, double y) {
          _jx = x;
          _jy = y;
        }),
      ),
      Positioned(
        right: 18,
        bottom: pad.bottom + 24,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
          ValueListenableBuilder<int>(
            valueListenable: frame,
            builder: (_, __, ___) => ArcadePadButton(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFE0B21A),
              size: 56,
              enabled: arena.players[me].traps > 0,
              badge: arena.players[me].traps > 0
                  ? CircleAvatar(radius: 10, backgroundColor: Colors.white, child: Text('${arena.players[me].traps}',
                      style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.w900)))
                  : null,
              onDown: () => _trapTap = true,
            ),
          ),
          const SizedBox(width: 12),
          ArcadePadButton(icon: Icons.brightness_7_rounded, label: l.tx('بمب', 'BOMB'), color: skin.accent, size: 96,
              onDown: () => _bombTap = true),
        ]),
      ),
    ]);
  }

  Widget _stat(IconData i, int v) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: ArcadeHudPill(
          color: Colors.white38,
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(i, size: 13, color: Colors.white70),
            const SizedBox(width: 3),
            Text('$v', style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
}
