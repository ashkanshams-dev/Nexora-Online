// headless match simulator: AI vs AI + random flicks into crowds; prints anomaly stats
import 'dart:math' as math;
import 'package:nexora/game/engine.dart';
import 'package:nexora/game/data.dart';

final W = PHYSICS_CONFIG.wPx;
MatchCfg cfgOf(int seed) => MatchCfg(field: seed % 3, ball: 0, forms: [seed % 4, (seed ~/ 4) % 4], ai: true, aiLvl: seed % 3,
    limit: 99, matchTime: 0, turnTime: 0, vip: [false, false], first: seed % 2,
    stats: [DiscStats(1.0 + seed % 10, 1.0 + (seed * 7) % 10), DiscStats(10.0 - seed % 10, 5)]);
double spd(Body b) => math.sqrt(b.vx * b.vx + b.vy * b.vy);

void main(List<String> args) {
  final nMatch = args.isNotEmpty ? int.parse(args[0]) : 20;
  final turnsPer = args.length > 1 ? int.parse(args[1]) : 40;
  final randomFlicks = args.length > 2 && args[2] == 'rand';
  const fdt = 1 / 60;
  var turns = 0, longTurns = 0, maxTurn = 0.0, sumTurn = 0.0;
  var outFrames = 0, worstOut = 0.0, overlapLong = 0, worstOverlap = 0.0, creepLong = 0, worstCreep = 0.0;
  var jitter = 0, energyGain = 0, worstGain = 0.0, goals = 0, maxBall = 0.0, maxPuck = 0.0, puckInNet = 0;
  final gainCtx = <String>[];
  final ballPath = <double>[], puckPath = <double>[];
  final hist = <String, int>{};
  for (var m = 0; m < nMatch; m++) {
    final e = Engine(cfgOf(m), rand: math.Random(m).nextDouble);
    e.aiTeams[0] = true;
    e.aiTeams[1] = true;
    final rnd = math.Random(1000 + m);
    for (var tn = 0; tn < turnsPer; tn++) {
      // wait for aim phase
      var guard = 0;
      while (e.phase != Phase.aim && guard++ < 3000) {
        e.update(fdt);
      }
      if (e.phase == Phase.over) break;
      if (randomFlicks) {
        final mine = e.bodies.where((b) => b.team == e.turn).toList();
        final p = mine[rnd.nextInt(mine.length)];
        // aim at the ball or at the nearest crowd with random power
        final tgt = rnd.nextBool() ? e.ball : e.bodies[rnd.nextInt(e.bodies.length)];
        var dx = tgt.x - p.x, dy = tgt.y - p.y;
        final l = math.sqrt(dx * dx + dy * dy);
        if (l < 1) { dx = 0; dy = -1; } else { dx /= l; dy /= l; }
        final a = math.atan2(dy, dx) + (rnd.nextDouble() - .5) * .3;
        final pull = (.15 + rnd.nextDouble() * .85) * LMAX;
        e.fire(p, math.cos(a) * pull, math.sin(a) * pull, pull, true);
      } else {
        // let AI decide and fire
        guard = 0;
        while (e.phase == Phase.aim && guard++ < 600) {
          e.update(fdt);
        }
      }
      if (e.phase != Phase.move) continue;
      final shooter = e.lastShot!;
      final n = e.bodies.length;
      final ov = List.filled(n, 0.0), cr = List.filled(n, 0.0);
      final lastSign = List.filled(n, 0), flips = List.filled(n, 0);
      final start = [for (final b in e.bodies) [b.x, b.y]];
      var bp = 0.0, pp = 0.0;
      var t = 0.0;
      double ke() => e.bodies.fold(0.0, (s, b) => s + (b.vx * b.vx + b.vy * b.vy) / b.im);
      var k0 = ke();
      var firstContact = false;
      while (e.phase == Phase.move && t < 30) {
        final bx = e.ball.x, by = e.ball.y, sx0 = shooter.x, sy0 = shooter.y;
        final hadFly = shooter.striker;
        final gout0 = e.bodies.any((b) => b.gout != null);
        e.update(fdt);
        t += fdt * PHYSICS_CONFIG.playbackSpeed;
        bp += math.sqrt((e.ball.x - bx) * (e.ball.x - bx) + (e.ball.y - by) * (e.ball.y - by));
        pp += math.sqrt((shooter.x - sx0) * (shooter.x - sx0) + (shooter.y - sy0) * (shooter.y - sy0));
        final k1 = ke();
        if (k1 > k0 * 1.02 + 1) {
          final g = k1 / math.max(k0, 1);
          // gain not due to the kick (shooter hitting ball)?
          final ctx = hadFly ? 'flick' : (gout0 || e.bodies.any((b) => b.gout != null) ? 'gout' : 'other');
          if (!hadFly) {
            energyGain++;
            worstGain = math.max(worstGain, g);
            if (gainCtx.length < 8) gainCtx.add('m$m t$tn ${t.toStringAsFixed(2)}s x${g.toStringAsFixed(2)} $ctx ball ${(spd(e.ball) / W).toStringAsFixed(2)}');
          }
        }
        if (!shooter.fly) firstContact = true;
        k0 = k1;
        maxBall = math.max(maxBall, spd(e.ball) / W);
        for (var i = 0; i < n; i++) {
          final b = e.bodies[i];
          if (!identical(b, e.ball)) maxPuck = math.max(maxPuck, spd(b) / W);
          final r = b.r;
          final mouth = b.x > e.goals[0].x1 && b.x < e.goals[0].x2;
          var o = math.max(e.Fl + r - b.x, b.x - (e.Fr - r));
          if (!mouth) o = math.max(o, math.max(e.Ft + r - b.y, b.y - (e.Fb - r)));
          if (mouth) o = math.max(o, math.max(e.Ft - kGoalDepth + r - b.y, b.y - (e.Fb + kGoalDepth - r)));
          if (o > .5) { outFrames++; worstOut = math.max(worstOut, o); hist['out ${identical(b, e.ball) ? "ball" : "puck"}'] = (hist['out ${identical(b, e.ball) ? "ball" : "puck"}'] ?? 0) + 1; }
          var over = false;
          for (final c in e.bodies) {
            if (!identical(b, c) && math.sqrt((b.x - c.x) * (b.x - c.x) + (b.y - c.y) * (b.y - c.y)) < b.r + c.r - 1) over = true;
          }
          ov[i] = over ? ov[i] + fdt : 0;
          worstOverlap = math.max(worstOverlap, ov[i]);
          final s = spd(b);
          cr[i] = (s > 0 && s < .05 * W) ? cr[i] + fdt : 0;
          worstCreep = math.max(worstCreep, cr[i]);
          // jitter: velocity x-sign flips while slow
          final sg = b.vx > 1 ? 1 : (b.vx < -1 ? -1 : 0);
          if (s < .3 * W && sg != 0 && lastSign[i] != 0 && sg != lastSign[i]) flips[i]++;
          if (sg != 0) lastSign[i] = sg;
          if (!identical(b, e.ball) && b.gout != null) puckInNet++;
        }
      }
      for (var i = 0; i < n; i++) {
        if (ov.any((x) => x > 1)) {}
        if (flips[i] > 6) { jitter++; if (gainCtx.length < 16) gainCtx.add('jitter m$m t$tn body ${e.bodies[i].id} flips ${flips[i]}'); }
      }
      if (ov.any((x) => x > 1)) overlapLong++;
      if (cr.any((x) => x > 1)) creepLong++;
      turns++;
      sumTurn += t;
      maxTurn = math.max(maxTurn, t);
      if (t > 8) longTurns++;
      final k = '${(t).floor()}s';
      hist[k] = (hist[k] ?? 0) + 1;
      ballPath.add(bp / W);
      puckPath.add(pp / W);
      if (e.phase == Phase.goal) goals++;
      start.clear();
    }
  }
  ballPath.sort();
  puckPath.sort();
  double pct(List<double> l, double q) => l.isEmpty ? 0 : l[(q * (l.length - 1)).round()];
  print('mode ${randomFlicks ? "random flicks" : "AI vs AI"}: $nMatch matches, $turns turns, goals $goals');
  print('turn length (sim s): mean ${(sumTurn / turns).toStringAsFixed(2)} max ${maxTurn.toStringAsFixed(2)}  >8s: $longTurns');
  print('ball path/turn W: p50 ${pct(ballPath, .5).toStringAsFixed(2)} p90 ${pct(ballPath, .9).toStringAsFixed(2)} max ${pct(ballPath, 1).toStringAsFixed(2)}; '
      'shooter path p50 ${pct(puckPath, .5).toStringAsFixed(2)} p90 ${pct(puckPath, .9).toStringAsFixed(2)} max ${pct(puckPath, 1).toStringAsFixed(2)}');
  print('max ball ${maxBall.toStringAsFixed(2)} W/s, max puck ${maxPuck.toStringAsFixed(2)} W/s');
  print('out-of-pitch frames $outFrames (worst ${worstOut.toStringAsFixed(1)} px); overlap>1s turns $overlapLong (worst ${worstOverlap.toStringAsFixed(2)}s); '
      'creep>1s turns $creepLong (worst ${worstCreep.toStringAsFixed(2)}s); jitter bodies $jitter; energy gains (non-flick) $energyGain worst x${worstGain.toStringAsFixed(2)}; puck-in-net frames $puckInNet');
  print(hist);
  for (final s in gainCtx) print('  $s');
}
