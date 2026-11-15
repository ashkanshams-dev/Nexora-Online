import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/body.dart';
import '../core/config.dart';
import '../core/fs_match.dart';
import '../core/physics.dart';
import 'fs_controller.dart';

/// Decoded artwork (any may be null -> procedural fallback).
class FsImages {
  ui.Image? pitch;
  ui.Image? ball;
  ui.Image? puck0;
  ui.Image? puck1;
}

class FsPainter extends CustomPainter {
  FsPainter(this.c, this.images) : super(repaint: c);

  final FsController c;
  final FsImages images;

  static final Paint _imgPaint = Paint()..filterQuality = FilterQuality.medium;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const vr = FsController.viewRect;
    final s = math.min(size.width / vr.width, size.height / vr.height);
    final ox = (size.width - vr.width * s) / 2 - vr.left * s;
    final oy = (size.height - vr.height * s) / 2 - vr.top * s;
    final fancy = c.fx.enabled;

    canvas.save();
    canvas.translate(ox + c.fx.shakeOffset.dx * s, oy + c.fx.shakeOffset.dy * s);
    canvas.scale(s, s);
    _drawPitch(canvas, vr);
    _drawGoals(canvas);
    if (fancy) _drawTrail(canvas);
    _drawAim(canvas);
    final m = c.match;
    for (final b in m.bodies) {
      if (!b.isBall) _drawDisc(canvas, b, fancy);
    }
    _drawBall(canvas, m.ball, fancy);
    c.fx.paintParticles(canvas);
    canvas.restore();

    if (c.fx.flash > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = c.fx.flashColor.withOpacity((c.fx.flash * 0.45).clamp(0.0, 1.0).toDouble()));
    }
    if (c.bannerTime > 0 && c.bannerFa.isNotEmpty) _drawBanner(canvas, size);
  }

  void _drawPitch(Canvas canvas, Rect vr) {
    final img = images.pitch;
    if (img != null) {
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), vr, _imgPaint);
      return;
    }
    const w = FsConfig.fieldW, h = FsConfig.fieldH;
    canvas.drawRRect(RRect.fromRectAndRadius(vr, const Radius.circular(22)), Paint()..color = const Color(0xFF0A1030));
    final g1 = Paint()..color = const Color(0xFF1E7A3C);
    final g2 = Paint()..color = const Color(0xFF238A45);
    for (var i = 0; i < 10; i++) {
      canvas.drawRect(Rect.fromLTWH(0, i * h / 10, w, h / 10), i.isEven ? g1 : g2);
    }
    final line = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), line);
    canvas.drawLine(const Offset(0, h / 2), const Offset(w, h / 2), line);
    canvas.drawCircle(const Offset(w / 2, h / 2), 90, line);
    canvas.drawRect(const Rect.fromLTRB(170, 0, 510, 170), line);
    canvas.drawRect(const Rect.fromLTRB(170, h - 170, 510, h), line);
  }

  void _drawGoals(Canvas canvas) {
    const mL = FsConfig.mouthL, mR = FsConfig.mouthR, gd = FsConfig.goalDepth, h = FsConfig.fieldH;
    final pulse = 0.5 + 0.5 * math.sin(c.clock * 2.4);
    final top = Paint()..color = kFsTeam1.withOpacity(0.10 + 0.06 * pulse);
    final bottom = Paint()..color = kFsTeam0.withOpacity(0.10 + 0.06 * pulse);
    canvas.drawRect(const Rect.fromLTRB(mL, -gd, mR, 0), top);
    canvas.drawRect(const Rect.fromLTRB(mL, h, mR, h + gd), bottom);
    final glow = Paint()
      ..color = const Color(0xAA9FE8FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final post = Paint()..color = const Color(0xFFEAF6FF);
    for (final p in fsPosts) {
      if (c.fx.enabled) canvas.drawCircle(Offset(p[0], p[1]), FsConfig.postR + 5, glow);
      canvas.drawCircle(Offset(p[0], p[1]), FsConfig.postR, post);
    }
  }

  void _drawDisc(Canvas canvas, FsBody b, bool fancy) {
    final team = b.team;
    final m = c.match;
    final active = m.phase == FsPhase.aiming && team == m.turnTeam && c.bannerTime <= 0;
    final base = team == 0 ? kFsTeam0 : kFsTeam1;
    final center = Offset(b.x, b.y);
    if (fancy) {
      canvas.drawOval(Rect.fromCenter(center: Offset(b.x + 4, b.y + 7), width: b.r * 2.1, height: b.r * 1.8),
          Paint()
            ..color = const Color(0x66000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    } else {
      canvas.drawOval(Rect.fromCenter(center: Offset(b.x + 3, b.y + 5), width: b.r * 2, height: b.r * 1.8), Paint()..color = const Color(0x44000000));
    }
    if (active) {
      final pulse = 0.5 + 0.5 * math.sin(c.clock * 5);
      final glow = Paint()
        ..color = base.withOpacity(0.25 + 0.25 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;
      if (fancy) glow.maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, b.r + 7 + 2 * pulse, glow);
    }
    final ringW = (b.id == c.aimId) ? 7.0 : 4.0;
    canvas.drawCircle(
        center,
        b.r + 2,
        Paint()
          ..color = active ? base : base.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringW);
    final img = team == 0 ? images.puck0 : images.puck1;
    if (img != null) {
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Rect.fromCircle(center: center, radius: b.r), _imgPaint);
    } else {
      canvas.drawCircle(center, b.r, Paint()..color = base.withOpacity(0.85));
      canvas.drawCircle(center, b.r * 0.55, Paint()..color = const Color(0x33FFFFFF));
    }
  }

  void _drawBall(Canvas canvas, FsBody b, bool fancy) {
    final center = Offset(b.x, b.y);
    canvas.drawOval(Rect.fromCenter(center: Offset(b.x + 3, b.y + 5), width: b.r * 2, height: b.r * 1.6), Paint()..color = const Color(0x55000000));
    final img = images.ball;
    if (img != null) {
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Rect.fromCircle(center: center, radius: b.r), _imgPaint);
    } else {
      canvas.drawCircle(center, b.r, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(center, b.r * 0.45, Paint()..color = const Color(0xFF222222));
    }
  }

  void _drawTrail(Canvas canvas) {
    final t = c.trail;
    for (var i = 1; i < t.length; i++) {
      final a = i / t.length;
      canvas.drawLine(
          t[i - 1],
          t[i],
          Paint()
            ..color = Color.fromRGBO(200, 245, 255, 0.4 * a)
            ..strokeWidth = 12 * a
            ..strokeCap = StrokeCap.round);
    }
  }

  void _drawAim(Canvas canvas) {
    final id = c.aimId;
    final pull = c.pull;
    if (id == null || pull == Offset.zero) return;
    final b = c.match.bodies[id];
    final len = pull.distance;
    if (len <= 0) return;
    final power = math.min(1.0, len / FsConfig.maxPull);
    final dir = Offset(-pull.dx / len, -pull.dy / len);
    final start = Offset(b.x, b.y);
    final col = Color.lerp(const Color(0xFF7CFFB2), const Color(0xFFFF5252), power) ?? const Color(0xFFFFFFFF);
    canvas.drawLine(
        start,
        start + pull,
        Paint()
          ..color = col.withOpacity(0.55)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(start + pull, 9, Paint()..color = col.withOpacity(0.8));
    final guideLen = 90 + 280 * power;
    final dot = Paint();
    for (var d = 44.0; d < guideLen; d += 24) {
      dot.color = col.withOpacity((1 - d / (guideLen + 40)).clamp(0.0, 1.0).toDouble());
      canvas.drawCircle(start + dir * d, 4, dot);
    }
    canvas.drawArc(
        Rect.fromCircle(center: start, radius: b.r + 13),
        -math.pi / 2,
        2 * math.pi * power,
        false,
        Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round);
  }

  void _drawBanner(Canvas canvas, Size size) {
    final text = c.launch.tx(c.bannerFa, c.bannerEn);
    final t = c.bannerTime;
    // Pop-in during the first 0.25s, fade during the last 0.4s.
    final grow = math.min(1.0, c.bannerAge / 0.25);
    final scale = c.launch.reducedMotion ? 1.0 : (0.6 + 0.4 * grow + 0.08 * math.sin(grow * math.pi));
    final alpha = math.min(1.0, t / 0.4);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withOpacity(alpha),
          fontSize: math.min(72.0, size.width * 0.15),
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          shadows: <Shadow>[
            Shadow(color: c.bannerColor.withOpacity(alpha), blurRadius: 24),
            Shadow(color: Colors.black.withOpacity(0.6 * alpha), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
      ),
      textDirection: c.launch.isFa ? TextDirection.rtl : TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width);
    canvas.save();
    canvas.translate(size.width / 2, size.height * (c.flipped ? 0.55 : 0.45));
    if (c.flipped) canvas.rotate(math.pi); // keep text upright on the rotated pitch
    canvas.scale(scale, scale);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FsPainter oldDelegate) => true;
}
