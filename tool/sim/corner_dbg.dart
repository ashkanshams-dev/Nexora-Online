import 'dart:math' as math;
import 'package:nexora/game/engine.dart';
MatchCfg _cfg() => MatchCfg(field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0, stats: const [DiscStats(7, 7), DiscStats(7, 7)]);
void main() {
  for (var corner = 0; corner < 4; corner++) {
    for (var deg = 10; deg <= 80; deg += 10) {
      for (final v in [900.0, 1800.0, 3500.0]) {
        final e = Engine(_cfg(), rand: math.Random(3).nextDouble);
        e.bodies..clear()..add(e.ball);
        final b = e.ball;
        final sx = corner.isEven ? -1.0 : 1.0, sy = corner < 2 ? -1.0 : 1.0;
        final cx = sx < 0 ? e.Fl : e.Fr, cy = sy < 0 ? e.Ft : e.Fb;
        final a = deg * math.pi / 180;
        final ux = math.cos(a) * sx, uy = math.sin(a) * sy;
        final tx = cx - sx * b.r, ty = cy - sy * b.r;
        b.x = tx - ux * 180; b.y = ty - uy * 180; b.vx = ux * v; b.vy = uy * v;
        var dmin = 1e9; final path = <String>[];
        for (var i = 0; i < 3840; i++) {
          e.update(1 / 480);
          final dc = math.max((b.x - cx).abs(), (b.y - cy).abs());
          dmin = math.min(dmin, dc);
          if (i < 30) path.add('(${(b.x - cx).toStringAsFixed(0)},${(b.y - cy).toStringAsFixed(0)})');
          if (b.vx == 0 && b.vy == 0) break;
        }
        print('c$corner deg $deg v $v dmin/r ${(dmin / b.r).toStringAsFixed(2)} ${dmin < 2 * b.r ? "" : path.take(16).join(" ")}');
      }
    }
  }
}
