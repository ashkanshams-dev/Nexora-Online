// "Flight to Nexora" — port of src/screens/Intro.tsx: hyperspace warp (240 streaking stars, same speed curve),
// ringed planet growing out of the warp, NX logo slams in with a white flash; tap to enter.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/match_game.dart' show loadUiImage;
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

const _N = 240;
double _travel(double t) {
  if (t < .5) return .12 * t + 2.38 * t * t * t / .75;
  const s05 = .12 * .5 + 2.38 * .125 / .75;
  if (t < 2.2) return s05 + 2.5 * (t - .5);
  const s22 = s05 + 2.5 * 1.7;
  final u = math.min(1.0, (t - 2.2) / 1.4);
  return s22 + .09 * (t - 2.2) + 2.41 * 1.4 * (1 - math.pow(1 - u, 4)) / 4;
}

double _speed(double t) {
  if (t < .5) return .12 + 2.38 * (t / .5) * (t / .5);
  if (t < 2.2) return 2.5;
  final u = math.min(1.0, (t - 2.2) / 1.4);
  return .09 + 2.41 * math.pow(1 - u, 3);
}

class Intro extends StatefulWidget {
  final VoidCallback onDone;
  const Intro({super.key, required this.onDone});
  @override
  State<Intro> createState() => _IntroState();
}

class _IntroState extends State<Intro> with TickerProviderStateMixin {
  late final Ticker _tk;
  final _t = ValueNotifier(0.0);
  final _stars = [for (var i = 0; i < _N; i++) ...[(math.Random().nextDouble() - .5) * 2, (math.Random().nextDouble() - .5) * 2, math.Random().nextDouble()]];
  ui.Image? planet;
  late final AnimationController logo = AnimationController.unbounded(vsync: this, value: 0);
  late final AnimationController out = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  bool ready = false, done = false;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _tk = createTicker((d) => _t.value = d.inMicroseconds / 1e6)..start();
    loadUiImage(UI['planet']).then((i) => mounted ? setState(() => planet = i) : null);
    _timers.add(Timer(const Duration(milliseconds: 3600), () {
      logo.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 120, damping: 9), 0, 1, 0));
      sfx(Sfx.whistle);
      buzz(Buzz.medium);
    }));
    _timers.add(Timer(const Duration(milliseconds: 4600), () => mounted ? setState(() => ready = true) : null));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _tk.dispose();
    logo.dispose();
    out.dispose();
    super.dispose();
  }

  void enter() {
    if (done) return;
    done = true;
    buzz(Buzz.medium);
    out.animateTo(1, curve: Curves.easeOutCubic).then((_) => widget.onDone());
  }

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.sizeOf(context);
    final W = sz.width, H = sz.height, cy = H * .44, LS = math.min(W * .7, 340.0);
    return AnimatedBuilder(
      animation: out,
      builder: (_, child) => Opacity(opacity: 1 - out.value, child: Transform.scale(scale: 1 + out.value * .5, child: child)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ready ? enter() : null,
        child: Container(
          color: hex('#02030b'),
          child: Stack(children: [
            Positioned.fill(child: ValueListenableBuilder<double>(valueListenable: _t, builder: (_, t, _) => CustomPaint(painter: _Warp(t, _stars, planet, cy)))),
            AnimatedBuilder(
              animation: logo,
              builder: (_, _) {
                final l = logo.value;
                return Stack(children: [
                  Positioned(
                    left: W / 2 - LS / 2, top: cy - LS / 2, width: LS, height: LS,
                    child: Opacity(opacity: (l * 1.5).clamp(0, 1), child: Transform.scale(scale: .4 + .6 * l, child: Image.asset(UI['nx_logo']!, fit: BoxFit.contain))),
                  ),
                  Positioned(
                    left: 0, right: 0, top: cy + LS * .42,
                    child: Opacity(opacity: (l * .9).clamp(0, .9), child: Center(child: T('NEXORA · FINGER SOCCER', style: fs(F.head, 12, ls: 6, color: hex('#5ce1ff'))))),
                  ),
                  if (l > 0 && l < .6) Positioned.fill(child: IgnorePointer(child: ColoredBox(color: hex('#dff6ff').withValues(alpha: (.6 - l).clamp(0, 1))))),
                ]);
              },
            ),
            if (ready)
              Positioned(
                bottom: H * .13, left: 0, right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: enter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: hex('#5ce1ff')),
                        color: rgba(12, 20, 48, .8),
                        boxShadow: [BoxShadow(color: hex('#5ce1ff').withValues(alpha: .7), blurRadius: 18)],
                      ),
                      child: T('برای ورود لمس کنید', style: fs(F.bold, 15)),
                    ).animate(onPlay: (c) => c.repeat(reverse: true)).custom(duration: 900.ms, builder: (_, p, c) => Opacity(opacity: .55 + p * .45, child: Transform.scale(scale: 1 + p * .04, child: c))),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12, left: 16,
              child: GestureDetector(
                onTap: enter,
                child: Container(
                  height: 44, padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: hex('#141a30'), border: Border.all(color: const Color(0x33FFFFFF))),
                  child: T('رد کردن ‹', style: fs(F.body, 13)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Warp extends CustomPainter {
  final double t, cy;
  final List<double> st;
  final ui.Image? planet;
  _Warp(this.t, this.st, this.planet, this.cy);
  @override
  void paint(Canvas c, Size s) {
    final W = s.width, H = s.height, cx = W / 2, f = math.max(W, H) * .3;
    final S = _travel(t), v = _speed(t);
    final g = .14 + math.min(.3, v * .1);
    c.drawRect(Offset.zero & s, Paint()..shader = ui.Gradient.radial(Offset(cx, cy), math.max(W, H) * .7, [const Color(0xFF3C28A0).withValues(alpha: g), const Color(0x00000000)]));
    final far = Path(), near = Path();
    for (var i = 0; i < _N; i++) {
      var z = st[i * 3 + 2] - S * .55;
      z = z - z.floorToDouble();
      z = .02 + z * .98;
      final pz = z + v * .07;
      final x1 = cx + st[i * 3] / z * f, y1 = cy + st[i * 3 + 1] / z * f;
      final x0 = cx + st[i * 3] / pz * f, y0 = cy + st[i * 3 + 1] / pz * f;
      final p = z < .45 ? near : far;
      p
        ..moveTo(x0, y0)
        ..lineTo(x1 + .1, y1);
    }
    c.drawPath(far, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.1..strokeCap = StrokeCap.round..color = const Color.fromRGBO(150, 200, 255, .55));
    c.drawPath(near, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeCap = StrokeCap.round..color = const Color.fromRGBO(200, 180, 255, .95)..blendMode = BlendMode.plus);
    final pl = planet;
    if (pl != null) {
      final p = ((t - 1.8) / 2.4).clamp(0.0, 1.0), e = 1 - math.pow(1 - p, 3);
      final sz = math.min(W, H) * 1.1 * e;
      final pop = ((t - 1.8) * .6).clamp(0.0, 1.0);
      if (sz > 1) {
        c.save();
        c.translate(cx, cy);
        c.rotate((t - 4) * .02);
        c.drawImageRect(pl, Rect.fromLTWH(0, 0, pl.width.toDouble(), pl.height.toDouble()), Rect.fromCenter(center: Offset.zero, width: sz, height: sz), Paint()..color = Color.fromRGBO(255, 255, 255, pop)..filterQuality = FilterQuality.medium);
        c.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_Warp o) => o.t != t || o.planet != planet;
}
