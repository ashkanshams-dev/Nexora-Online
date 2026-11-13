// Compares the Box2D offline backend against the classic engine on identical shots (feel check, not parity).
import 'dart:math' as math;
import 'package:nexora/game/engine.dart';
import 'package:nexora/game/forge_engine.dart';

Future<void> main() async {
  await initForge2d();
  print('forge2d ready: $forge2dReady');
  for (final mk in [(c) => Engine(c), (c) => ForgeEngine(c)]) {
    final e = mk(MatchCfg(field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0, vip: [false, false], first: 0));
    final res = <String>[];
    for (var shot = 0; shot < 6; shot++) {
      final mine = e.bodies.where((b) => b.team == shot % 2).toList();
      final b = mine[shot % mine.length];
      final dx = e.ball.x - b.x, dy = e.ball.y - b.y, l = math.sqrt(dx * dx + dy * dy), k = (80 + shot * 25) / l;
      e.phase = Phase.aim;
      e.fire(b, dx * k, dy * k, l * k);
      var n = 0, maxBall = 0.0;
      while (n++ < 4000) {
        e.simStep();
        maxBall = math.max(maxBall, hyp(e.ball.vx, e.ball.vy));
        if (e.atRest() || e.phase == Phase.goal) break;
      }
      res.add('t=${(n / 240).toStringAsFixed(2)}s vmax=${maxBall.round()} ball=(${e.ball.x.round()},${e.ball.y.round()}) ${e.phase.name}');
      if (e.phase == Phase.goal) e.reset(0);
    }
    print('${e.runtimeType}:\n  ${res.join('\n  ')}');
  }
}
