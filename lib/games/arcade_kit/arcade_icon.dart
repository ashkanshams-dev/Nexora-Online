import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/assets/app_assets.dart';

/// Visual identity of the 20 arcade games for lists/hubs: accent pair + glyph.
class ArcadeIconSpec {
  const ArcadeIconSpec(this.icon, this.a, this.b);
  final IconData icon;
  final Color a;
  final Color b;
}

const Map<String, ArcadeIconSpec> kArcadeIcons = <String, ArcadeIconSpec>{
  'kart_racing': ArcadeIconSpec(Icons.sports_motorsports_rounded, Color(0xFFFF7A1A), Color(0xFFFFD34E)),
  'obstacle_race': ArcadeIconSpec(Icons.directions_run_rounded, Color(0xFFFF4FA3), Color(0xFF8C5BFF)),
  'bomb_arena': ArcadeIconSpec(Icons.local_fire_department_rounded, Color(0xFFFF4D3D), Color(0xFFFFB13D)),
  'pool8': ArcadeIconSpec(Icons.sports_baseball_rounded, Color(0xFF16C784), Color(0xFF0E5B3A)),
  'mini_golf': ArcadeIconSpec(Icons.golf_course_rounded, Color(0xFF7CFF7A), Color(0xFF1C9C5A)),
  'basketball_battle': ArcadeIconSpec(Icons.sports_basketball_rounded, Color(0xFFFF8A2A), Color(0xFFB4410E)),
  'spy_mafia': ArcadeIconSpec(Icons.person_search_rounded, Color(0xFFB98CFF), Color(0xFF3B1E7A)),
  'stickman_arena': ArcadeIconSpec(Icons.sports_martial_arts_rounded, Color(0xFF39E1FF), Color(0xFF1B4DFF)),
  'ludo_battle': ArcadeIconSpec(Icons.casino_rounded, Color(0xFFFF4F9A), Color(0xFFFFC94A)),
  'chess_blitz': ArcadeIconSpec(Icons.timer_rounded, Color(0xFFE9E3D4), Color(0xFF8A6A3A)),
  'endless_runner': ArcadeIconSpec(Icons.directions_run_rounded, Color(0xFF39E1FF), Color(0xFF7CFF7A)),
  'tetris_rush': ArcadeIconSpec(Icons.grid_view_rounded, Color(0xFFB98CFF), Color(0xFFFF4FA3)),
  'helix_jump': ArcadeIconSpec(Icons.cyclone_rounded, Color(0xFFFF5E8A), Color(0xFF39E1FF)),
  'fruit_ninja': ArcadeIconSpec(Icons.content_cut_rounded, Color(0xFF7CFF7A), Color(0xFFFF4D3D)),
  'geo_dash': ArcadeIconSpec(Icons.change_history_rounded, Color(0xFFFFD34E), Color(0xFF00C2FF)),
  'traffic_racer': ArcadeIconSpec(Icons.directions_car_filled_rounded, Color(0xFFFF4D3D), Color(0xFF39E1FF)),
  'stack_tower': ArcadeIconSpec(Icons.stacked_bar_chart_rounded, Color(0xFF39E1FF), Color(0xFFB98CFF)),
  'bubble_shooter': ArcadeIconSpec(Icons.bubble_chart_rounded, Color(0xFF39E1FF), Color(0xFFFF4FA3)),
  'knife_hit': ArcadeIconSpec(Icons.gps_fixed_rounded, Color(0xFFFFC94A), Color(0xFF8A4B1E)),
  'game_2048': ArcadeIconSpec(Icons.filter_9_plus_rounded, Color(0xFFFFB13D), Color(0xFFFF4F9A)),
};

/// The game's pedestal art (assets/arcade/pedestals/<id>.webp) — or, when the art is not there yet, a premium
/// procedural medallion. Dropping a webp with the game's id into that folder replaces the medallion everywhere.
class GamePedestal extends StatelessWidget {
  const GamePedestal(this.gameId, {super.key, this.size, this.cacheWidth = 360, this.fit = BoxFit.contain});
  final String gameId;
  final double? size;
  final int cacheWidth;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.pedestal(gameId),
      width: size,
      height: size,
      cacheWidth: cacheWidth,
      fit: fit,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child: ArcadeMedallion(gameId),
      ),
    );
  }
}

class ArcadeMedallion extends StatelessWidget {
  const ArcadeMedallion(this.gameId, {super.key});
  final String gameId;

  @override
  Widget build(BuildContext context) {
    final ArcadeIconSpec s =
        kArcadeIcons[gameId] ?? const ArcadeIconSpec(Icons.sports_esports_rounded, Color(0xFF39E1FF), Color(0xFF8C5BFF));
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final double d = math.min(c.maxWidth, c.maxHeight.isFinite ? c.maxHeight : c.maxWidth);
        return Stack(alignment: Alignment.center, children: <Widget>[
          CustomPaint(size: Size.square(d), painter: _MedallionPainter(s)),
          ShaderMask(
            shaderCallback: (Rect r) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Colors.white, Color.lerp(s.a, Colors.white, 0.55)!],
            ).createShader(r),
            child: Icon(s.icon, size: d * 0.42, color: Colors.white, shadows: <Shadow>[
              Shadow(color: s.a.withValues(alpha: 0.9), blurRadius: d * 0.08),
              Shadow(color: Colors.black.withValues(alpha: 0.5), offset: Offset(0, d * 0.02), blurRadius: d * 0.03),
            ]),
          ),
        ]);
      }),
    );
  }
}

class _MedallionPainter extends CustomPainter {
  _MedallionPainter(this.s);
  final ArcadeIconSpec s;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width * 0.42;
    final Offset c = size.center(Offset(0, -size.width * 0.02));
    // pedestal shadow + glow
    canvas.drawOval(Rect.fromCenter(center: c + Offset(0, r * 1.02), width: r * 1.9, height: r * 0.36),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.1));
    canvas.drawCircle(c, r * 1.15,
        Paint()..shader = ui.Gradient.radial(c, r * 1.15, <Color>[s.a.withValues(alpha: 0.45), s.a.withValues(alpha: 0)]));
    // metal ring
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.sweep(c, <Color>[
            const Color(0xFFFFF1C9),
            const Color(0xFFB98A3A),
            const Color(0xFFFFE7A8),
            const Color(0xFF7A5420),
            const Color(0xFFFFF1C9),
          ], const <double>[0, 0.25, 0.5, 0.75, 1]));
    // inner disc
    final double ir = r * 0.86;
    canvas.drawCircle(
        c,
        ir,
        Paint()
          ..shader = ui.Gradient.radial(c + Offset(-ir * 0.3, -ir * 0.4), ir * 1.5,
              <Color>[Color.lerp(s.a, Colors.white, 0.25)!, s.a, s.b], <double>[0, 0.45, 1]));
    // rays
    final Paint ray = Paint()..color = Colors.white.withValues(alpha: 0.06);
    for (int i = 0; i < 12; i++) {
      final double a = i * math.pi / 6;
      final Path p = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - 0.12) * ir, c.dy + math.sin(a - 0.12) * ir)
        ..lineTo(c.dx + math.cos(a + 0.12) * ir, c.dy + math.sin(a + 0.12) * ir)
        ..close();
      canvas.drawPath(p, ray);
    }
    // inner shadow + gloss
    canvas.drawCircle(
        c,
        ir,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ir * 0.08
          ..color = Colors.black.withValues(alpha: 0.25));
    canvas.drawOval(
        Rect.fromCenter(center: c + Offset(0, -ir * 0.52), width: ir * 1.4, height: ir * 0.7),
        Paint()
          ..shader = ui.Gradient.linear(c + Offset(0, -ir), c + Offset(0, -ir * 0.15),
              <Color>[Colors.white.withValues(alpha: 0.5), Colors.white.withValues(alpha: 0)]));
  }

  @override
  bool shouldRepaint(covariant _MedallionPainter old) => old.s != s;
}
