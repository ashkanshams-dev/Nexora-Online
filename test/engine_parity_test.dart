// Lockstep parity: the Dart engine must reproduce the original TypeScript engine bit-for-bit.
// test/fixtures/engine_parity_ts.txt is produced by tool/engine_parity_ref.ts run against the RN engine
// (node --experimental-strip-types tool/engine_parity_ref.ts > test/fixtures/engine_parity_ts.txt).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

List<String> runScenario() {
  final out = <String>[];
  for (final field in [0, 3, 15, 27]) {
    final e = Engine(MatchCfg(
      field: field, ball: 0, forms: [field % 6, (field + 2) % 6], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
      vip: [false, true], first: 0,
      stats: field % 2 == 1 ? const [DiscStats(7, 3), DiscStats(4, 9)] : null));
    e.seed = 0x5eed ^ field;
    var s = 12345 + field;
    double r() { s = (s * 48271) % 2147483647; return s / 2147483647; }
    for (var shot = 0; shot < 120; shot++) {
      final team = shot % 2;
      final mine = e.bodies.where((b) => b.team == team).toList();
      final b = mine[(r() * mine.length).floor()];
      var dx = e.ball.x - b.x + (r() - .5) * 120, dy = e.ball.y - b.y + (r() - .5) * 120;
      final l = math.sqrt(dx * dx + dy * dy), k = (40 + r() * 200) / l;
      dx *= k; dy *= k;
      e.phase = Phase.aim;
      e.fire(b, dx, dy, math.sqrt(dx * dx + dy * dy), human: true);
      var guard = 0;
      while (guard++ < 6000) {
        e.simStep();
        if (e.tick % 60 == 0) out.add('$field:$shot:${e.tick}:${e.packState().join(',')}');
        if (e.atRest() || e.phase == Phase.goal) break;
      }
      out.add('$field:$shot:end:${e.tick}:${e.phase.name}:${e.packState().join(',')}');
      if (e.phase == Phase.goal) e.reset(team);
      for (final q in e.bodies) { q.x = q.px = jsRound(q.x * 64) / 64; q.y = q.py = jsRound(q.y * 64) / 64; q.vx = q.vy = 0; }
    }
  }
  return out;
}

void main() {
  test('Dart engine matches the TypeScript engine bit-for-bit', () {
    final ref = File('test/fixtures/engine_parity_ts.txt').readAsLinesSync().where((l) => l.isNotEmpty).toList();
    final got = runScenario();
    for (var i = 0; i < math.min(ref.length, got.length); i++) {
      expect(got[i], ref[i], reason: 'first divergence at line $i');
    }
    expect(got.length, ref.length);
  });
  test('JS rounding + imul helpers', () {
    expect(jsRound(-2.5), -2); expect(jsRound(2.5), 3); expect(jsRound(-0.5), -0.0);
    expect(imul32(0x9E3779B1, 7), (0x9E3779B1 * 7) & 0xFFFFFFFF);
  });
}
