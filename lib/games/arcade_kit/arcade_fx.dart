import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'arcade_skin.dart';

/// Shared premium rendering helpers + particle FX for the NEXORA arcade games.
/// Everything is resolution independent and respects [ArcadeFx.enabled] (Low quality / Reduced Motion).

enum ParticleKind { spark, orb, confetti, smoke, ring, shard }

class Particle {
  Particle(this.kind, this.x, this.y, this.vx, this.vy, this.life, this.color, this.size,
      {this.gravity = 0, this.drag = 0.9, this.spin = 0})
      : maxLife = life;
  final ParticleKind kind;
  double x, y, vx, vy;
  double life;
  final double maxLife;
  final Color color;
  double size;
  final double gravity;
  final double drag;
  double spin;
  double angle = 0;
}

class FloatText {
  FloatText(this.text, this.x, this.y, this.color, {this.size = 22, this.life = 0.9}) : maxLife = life;
  final String text;
  double x, y;
  final Color color;
  final double size;
  double life;
  final double maxLife;
}

/// Particle system + screen shake + floating score text.
class ArcadeFx {
  ArcadeFx({this.enabled = true, this.skin});
  bool enabled;
  ArcadeSkin? skin;
  final List<Particle> parts = <Particle>[];
  final List<FloatText> texts = <FloatText>[];
  final math.Random _r = math.Random();
  double _shake = 0;
  double flash = 0;
  Color flashColor = const Color(0xFFFFFFFF);

  double get _mul => skin?.fxv('particles') ?? 1;

  void burst(Offset at, Color color,
      {int count = 18,
      double speed = 260,
      double life = 0.6,
      double size = 4,
      ParticleKind kind = ParticleKind.spark,
      double gravity = 0,
      double spread = math.pi * 2,
      double direction = 0}) {
    if (!enabled) return;
    final int n = (count * _mul).round().clamp(0, 200);
    for (int i = 0; i < n; i++) {
      final double a = direction + (spread >= math.pi * 2 ? _r.nextDouble() * math.pi * 2 : (_r.nextDouble() - 0.5) * spread);
      final double sp = speed * (0.35 + _r.nextDouble() * 0.65);
      parts.add(Particle(kind, at.dx, at.dy, math.cos(a) * sp, math.sin(a) * sp, life * (0.6 + _r.nextDouble() * 0.5),
          color, size * (0.6 + _r.nextDouble() * 0.8),
          gravity: gravity, drag: kind == ParticleKind.smoke ? 0.94 : 0.9, spin: (_r.nextDouble() - 0.5) * 12));
    }
    if (parts.length > 600) parts.removeRange(0, parts.length - 600);
  }

  void confetti(Offset at, {int count = 40}) {
    const List<Color> cs = <Color>[
      Color(0xFFFFD34E), Color(0xFF39E1FF), Color(0xFFFF4F9A), Color(0xFF7CFF7A), Color(0xFFB98CFF)
    ];
    for (int i = 0; i < 5; i++) {
      burst(at, cs[i], count: count ~/ 5, speed: 420, life: 1.4, size: 6, kind: ParticleKind.confetti, gravity: 520,
          spread: math.pi * 0.9, direction: -math.pi / 2);
    }
  }

  void ring(Offset at, Color color, {double size = 30, double life = 0.45}) {
    if (!enabled) return;
    parts.add(Particle(ParticleKind.ring, at.dx, at.dy, 0, 0, life, color, size));
  }

  void text(String t, Offset at, Color color, {double size = 22}) => texts.add(FloatText(t, at.dx, at.dy, color, size: size));

  void shake(double amount) {
    if (!enabled) return;
    _shake = math.max(_shake, amount * (skin?.fxv('shake') ?? 1));
  }

  void flashScreen(Color c, [double a = 0.35]) {
    if (!enabled) return;
    flashColor = c;
    flash = math.max(flash, a);
  }

  Offset get shakeOffset =>
      _shake <= 0.01 ? Offset.zero : Offset((_r.nextDouble() - 0.5) * _shake * 2, (_r.nextDouble() - 0.5) * _shake * 2);

  void update(double dt) {
    _shake = math.max(0, _shake - dt * 40);
    flash = math.max(0, flash - dt * 1.6);
    for (int i = parts.length - 1; i >= 0; i--) {
      final Particle p = parts[i];
      p.life -= dt;
      if (p.life <= 0) {
        parts.removeAt(i);
        continue;
      }
      final double d = math.pow(p.drag, dt * 60).toDouble();
      p.vx *= d;
      p.vy = p.vy * d + p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.angle += p.spin * dt;
      if (p.kind == ParticleKind.smoke) p.size += dt * 18;
      if (p.kind == ParticleKind.ring) p.size += dt * 160;
    }
    for (int i = texts.length - 1; i >= 0; i--) {
      final FloatText t = texts[i];
      t.life -= dt;
      t.y -= dt * 60;
      if (t.life <= 0) texts.removeAt(i);
    }
  }

  void paint(Canvas canvas) {
    final Paint p = Paint();
    for (final Particle q in parts) {
      final double k = (q.life / q.maxLife).clamp(0.0, 1.0);
      switch (q.kind) {
        case ParticleKind.spark:
          p
            ..color = q.color.withValues(alpha: k)
            ..strokeWidth = q.size * 0.7
            ..strokeCap = StrokeCap.round
            ..blendMode = BlendMode.plus;
          canvas.drawLine(Offset(q.x, q.y), Offset(q.x - q.vx * 0.03, q.y - q.vy * 0.03), p);
          p.blendMode = BlendMode.srcOver;
        case ParticleKind.orb:
          p
            ..color = q.color.withValues(alpha: k)
            ..blendMode = BlendMode.plus
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
          canvas.drawCircle(Offset(q.x, q.y), q.size * (0.5 + k * 0.5), p);
          p
            ..maskFilter = null
            ..blendMode = BlendMode.srcOver;
        case ParticleKind.confetti:
          canvas.save();
          canvas.translate(q.x, q.y);
          canvas.rotate(q.angle);
          p.color = q.color.withValues(alpha: math.min(1, k * 2));
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: q.size, height: q.size * 0.5 * (1 + math.sin(q.angle * 3).abs())), p);
          canvas.restore();
        case ParticleKind.smoke:
          p.color = q.color.withValues(alpha: k * 0.35);
          p.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
          canvas.drawCircle(Offset(q.x, q.y), q.size, p);
          p.maskFilter = null;
        case ParticleKind.ring:
          p
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * k + 0.5
            ..color = q.color.withValues(alpha: k);
          canvas.drawCircle(Offset(q.x, q.y), q.size, p);
          p.style = PaintingStyle.fill;
        case ParticleKind.shard:
          canvas.save();
          canvas.translate(q.x, q.y);
          canvas.rotate(q.angle);
          p.color = q.color.withValues(alpha: k);
          final Path tri = Path()
            ..moveTo(0, -q.size)
            ..lineTo(q.size * 0.7, q.size * 0.6)
            ..lineTo(-q.size * 0.6, q.size * 0.5)
            ..close();
          canvas.drawPath(tri, p);
          canvas.restore();
      }
    }
    for (final FloatText t in texts) {
      final double k = (t.life / t.maxLife).clamp(0.0, 1.0);
      final double sc = 1 + (1 - k) * 0.25;
      drawLabel(canvas, t.text, Offset(t.x, t.y), size: t.size * sc, color: t.color.withValues(alpha: math.min(1, k * 1.6)),
          glow: t.color);
    }
  }

  void paintFlash(Canvas canvas, Size size) {
    if (flash <= 0) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = flashColor.withValues(alpha: flash));
  }
}

// ---------------------------------------------------------------- drawing helpers

/// Text with soft outer glow + drop shadow, centred on [at].
void drawLabel(Canvas canvas, String text, Offset at,
    {double size = 18, Color color = const Color(0xFFFFFFFF), Color? glow, FontWeight weight = FontWeight.w900, bool center = true}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFamily: 'ChakraPetch',
        letterSpacing: 0.5,
        shadows: <Shadow>[
          Shadow(color: const Color(0xAA000000), offset: Offset(0, size * 0.08), blurRadius: size * 0.15),
          if (glow != null) Shadow(color: glow.withValues(alpha: 0.8), blurRadius: size * 0.6),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
}

/// Full-screen premium backdrop: vertical gradient, radial light, vignette and slow drifting bokeh.
void paintBackdrop(Canvas canvas, Size size, ArcadeSkin skin, double t, {bool bokeh = true}) {
  final Rect r = Offset.zero & size;
  canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), <Color>[skin.bgTop, skin.bgBottom]));
  canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(Offset(size.width * 0.5, size.height * 0.28), size.longestSide * 0.6,
            <Color>[skin.glow.withValues(alpha: 0.22), skin.glow.withValues(alpha: 0)]));
  if (bokeh) {
    final math.Random rnd = math.Random(skin.gameId.hashCode);
    final Paint bp = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    for (int i = 0; i < 14; i++) {
      final double bx = (rnd.nextDouble() * size.width + math.sin(t * 0.2 + i) * 20) % size.width;
      final double by = (rnd.nextDouble() * size.height - t * (6 + i)) % size.height;
      final double br = 6 + rnd.nextDouble() * 22;
      bp.color = (i.isEven ? skin.accent : skin.accent2).withValues(alpha: 0.05 + rnd.nextDouble() * 0.06);
      canvas.drawCircle(Offset(bx, by < 0 ? by + size.height : by), br, bp);
    }
  }
  paintVignette(canvas, size);
}

void paintVignette(Canvas canvas, Size size, [double strength = 0.55]) {
  canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(size.center(Offset.zero), size.longestSide * 0.75,
            <Color>[const Color(0x00000000), Color.fromRGBO(0, 0, 0, strength)], <double>[0.55, 1]));
}

/// Glossy shaded sphere (ball, bubble, orb) with key light top-left, rim light and contact shadow.
void paintSphere(Canvas canvas, Offset c, double r, Color base, {bool shadow = true, double gloss = 1, Color? rim}) {
  if (shadow) {
    canvas.drawOval(Rect.fromCenter(center: c + Offset(r * 0.25, r * 0.9), width: r * 1.9, height: r * 0.7),
        Paint()
          ..color = const Color(0x55000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25));
  }
  final HSLColor h = HSLColor.fromColor(base);
  final Color hi = h.withLightness((h.lightness + 0.28).clamp(0.0, 0.95)).toColor();
  final Color lo = h.withLightness((h.lightness - 0.28).clamp(0.03, 1.0)).toColor();
  canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c + Offset(-r * 0.35, -r * 0.4), r * 1.5, <Color>[hi, base, lo], <double>[0, 0.45, 1]));
  if (rim != null) {
    canvas.drawCircle(c, r * 0.96,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.08
          ..color = rim.withValues(alpha: 0.7));
  }
  if (gloss > 0) {
    canvas.drawOval(
        Rect.fromCenter(center: c + Offset(-r * 0.3, -r * 0.42), width: r * 0.9, height: r * 0.5),
        Paint()
          ..shader = ui.Gradient.linear(c + Offset(0, -r * 0.7), c + Offset(0, -r * 0.1),
              <Color>[Color.fromRGBO(255, 255, 255, 0.75 * gloss), const Color(0x00FFFFFF)]));
  }
}

/// Bevelled 3D block: top-face gradient, darker side, inner highlight and soft drop shadow.
void paintBlock(Canvas canvas, Rect r, Color base, {double radius = 6, double depth = 4, bool shadow = true, double glow = 0}) {
  final HSLColor h = HSLColor.fromColor(base);
  final Color hi = h.withLightness((h.lightness + 0.18).clamp(0.0, 0.92)).toColor();
  final Color lo = h.withLightness((h.lightness - 0.22).clamp(0.02, 1.0)).toColor();
  if (shadow) {
    canvas.drawRRect(RRect.fromRectAndRadius(r.shift(Offset(0, depth * 1.4)), Radius.circular(radius)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, depth.abs() + math.min(1, r.shortestSide * 0.05)));
  }
  if (glow > 0) {
    canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(math.min(2, r.shortestSide * 0.06)), Radius.circular(radius)),
        Paint()
          ..color = base.withValues(alpha: 0.6 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.min(10, r.shortestSide * 0.3) * glow));
  }
  canvas.drawRRect(RRect.fromRectAndRadius(r.shift(Offset(0, depth)), Radius.circular(radius)), Paint()..color = lo);
  canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(radius)),
      Paint()..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, depth < 0 ? <Color>[base, hi] : <Color>[hi, base]));
  final double hw = math.min(1.2, r.shortestSide * 0.04);
  canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(hw), Radius.circular(math.max(0, radius - hw))),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hw
        ..shader = ui.Gradient.linear(depth < 0 ? r.bottomCenter : r.topCenter, depth < 0 ? r.topCenter : r.bottomCenter,
            <Color>[const Color(0x88FFFFFF), const Color(0x00FFFFFF)]));
}

/// Soft neon glow line / path.
void paintNeonPath(Canvas canvas, Path path, Color color, {double width = 3, double glow = 10}) {
  canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + glow * 0.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow * 0.5));
  canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.35)!);
}

/// Soft radial glow blob.
void paintGlow(Canvas canvas, Offset c, double r, Color color, [double alpha = 0.5]) {
  canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, r, <Color>[color.withValues(alpha: alpha), color.withValues(alpha: 0)]));
}

/// Contact shadow ellipse.
void paintShadow(Canvas canvas, Offset c, double w, double h, [double a = 0.4]) {
  canvas.drawOval(Rect.fromCenter(center: c, width: w, height: h),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.4));
}

Color shade(Color c, double dl) {
  final HSLColor h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness + dl).clamp(0.0, 1.0)).toColor();
}
