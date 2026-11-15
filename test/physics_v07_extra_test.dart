// v0.7 stage-3 headless tests (beyond the 9 acceptance criteria): shots, puck-puck, simultaneous hits, repeatability,
// frame-rate independence, goal detection, natural stopping, prediction vs actual path.
// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

final double W = PHYSICS_CONFIG.wPx;
const double fdt = 1 / 60;

MatchCfg _cfg() => MatchCfg(
    field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0);

Engine _lab(int keep) {
  final e = Engine(_cfg(), rand: math.Random(3).nextDouble);
  final discs = e.bodies.where((b) => !identical(b, e.ball)).take(keep).toList();
  e.bodies
    ..clear()
    ..addAll(discs)
    ..add(e.ball);
  for (final b in e.bodies) {
    b.vx = b.vy = 0;
  }
  _place(e.ball, e.CX, e.Ft - 30, 0, 0); // unused ball waits in the top net
  return e;
}

void _place(Body b, double x, double y, double vx, double vy) {
  b.x = b.px = x;
  b.y = b.py = y;
  b.vx = vx;
  b.vy = vy;
}

double _spd(Body b) => math.sqrt(b.vx * b.vx + b.vy * b.vy);
bool _moving(Engine e) => e.bodies.any((b) => b.vx != 0 || b.vy != 0);

void _rest(Engine e, [double dt = fdt, double maxT = 30]) {
  for (var t = 0.0; t < maxT && _moving(e); t += dt) {
    e.update(dt);
  }
}

List<double> _state(Engine e) => [for (final b in e.bodies) ...[b.x, b.y, b.vx, b.vy]];

void main() {
  test('shots: min / medium / max pull -> monotonic launch speed and glide, all come to rest', () {
    final res = <double>[];
    for (final p in [.12, .5, 1.0]) {
      final e = _lab(1), d = e.bodies[0];
      _place(e.ball, e.Fr - 40, e.CY, 0, 0); // ball out of the way (a goal would reset the bodies)
      _place(d, e.Fl + 120, e.Fb - d.r - 5, 0, 0);
      e.fireVec(d, 0, -1, p);
      final v0 = _spd(d);
      var path = 0.0, t = 0.0;
      while (_moving(e) && t < 30) {
        final x0 = d.x, y0 = d.y;
        e.update(fdt);
        t += fdt;
        path += math.sqrt((d.x - x0) * (d.x - x0) + (d.y - y0) * (d.y - y0));
      }
      res.add(path);
      print('shot p=$p: launch ${(v0 / W).toStringAsFixed(2)} W/s, path ${(path / W).toStringAsFixed(3)} W, rest after ${t.toStringAsFixed(2)} s');
      expect(_spd(d), 0);
    }
    expect(res[0], lessThan(res[1]));
    expect(res[1], lessThan(res[2]));
  });

  test('puck-puck direct: e = .8, equal mass -> striker keeps 10%, target gets 90%', () {
    final e = _lab(2), a = e.bodies[0], c = e.bodies[1];
    _place(a, e.CX, e.CY + .3 * W, 0, -3 * W);
    _place(c, e.CX, e.CY, 0, 0);
    var pre = 0.0;
    for (var i = 0; i < 60 && c.vy == 0; i++) {
      pre = -a.vy;
      e.update(fdt);
    }
    final ka = math.exp(PHYSICS_CONFIG.puckFlightK * fdt); // friction in the contact frame (no flight flag here)
    final ra = -a.vy / pre, rc = -c.vy / pre;
    print('puck-puck direct: striker ${ra.toStringAsFixed(3)}, target ${rc.toStringAsFixed(3)} of ${(pre / W).toStringAsFixed(2)} W/s ($ka)');
    expect(ra, closeTo(.1, .04));
    expect(rc, closeTo(.9, .06));
    expect(a.vx.abs() + c.vx.abs(), lessThan(1e-9));
  });

  test('puck-puck angled: target leaves along the line of centres, striker at ~90 deg to it', () {
    final e = _lab(2), a = e.bodies[0], c = e.bodies[1];
    final m = a.r + c.r, off = m * .5; // 30 degree cut
    _place(a, e.CX - off, e.CY + .3 * W, 0, -3 * W);
    _place(c, e.CX, e.CY, 0, 0);
    for (var i = 0; i < 60 && c.vy == 0; i++) {
      e.update(fdt);
    }
    final nx = off / m, ny = -math.sqrt(1 - nx * nx);
    final cAng = math.acos(((c.vx * nx + c.vy * ny) / _spd(c)).clamp(-1.0, 1.0)) * 180 / math.pi;
    final sep = math.acos(((a.vx * c.vx + a.vy * c.vy) / (_spd(a) * _spd(c))).clamp(-1.0, 1.0)) * 180 / math.pi;
    print('puck-puck angled: target off-normal ${cAng.toStringAsFixed(3)} deg, separation angle ${sep.toStringAsFixed(1)} deg');
    expect(cAng, lessThan(1));
    expect(sep, inInclusiveRange(70, 95)); // 90 for e = 1, a little less for e = .8
  });

  test('puck-puck multi: a row of 3 (cradle) passes the hit down the line', () {
    final e = _lab(3), a = e.bodies[0], b = e.bodies[1], c = e.bodies[2];
    final d = 2 * a.r + .5;
    _place(a, e.CX, e.CY + .35 * W, 0, -3 * W);
    _place(b, e.CX, e.CY, 0, 0);
    _place(c, e.CX, e.CY - d, 0, 0);
    _rest(e);
    print('multi: travel a ${((e.CY + .35 * W - a.y) / W).toStringAsFixed(3)} W, b ${((e.CY - b.y) / W).toStringAsFixed(3)} W, '
        'c ${((e.CY - d - c.y) / W).toStringAsFixed(3)} W');
    expect(e.CY - d - c.y, greaterThan(e.CY - b.y));
    expect(e.CY - b.y, greaterThan(0));
    for (final p in [a, b, c]) {
      expect(p.x, closeTo(e.CX, 1e-6));
    }
  });

  test('simultaneous: ball into two touching-distance pucks symmetric -> straight on, mirrored pucks', () {
    final e = _lab(2), p1 = e.bodies[0], p2 = e.bodies[1], b = e.ball;
    final h = p1.r + b.r * .6; // the ball meets both pucks at the same instant
    _place(p1, e.CX - h, e.CY, 0, 0);
    _place(p2, e.CX + h, e.CY, 0, 0);
    _place(b, e.CX, e.CY + .35 * W, 0, -4 * W);
    for (var i = 0; i < 60 && (_spd(p1) == 0 || _spd(p2) == 0); i++) {
      e.update(fdt);
    }
    e.update(fdt);
    print('simultaneous: ball vx ${b.vx.toStringAsExponential(2)}, vy ${(b.vy / W).toStringAsFixed(3)} W/s; '
        'p1 (${p1.vx.toStringAsFixed(1)}, ${p1.vy.toStringAsFixed(1)}) p2 (${p2.vx.toStringAsFixed(1)}, ${p2.vy.toStringAsFixed(1)})');
    // contacts are solved pair by pair (sequential impulses), so a perfectly simultaneous double hit is only
    // near-symmetric: the ball must keep its line within a few degrees and both pucks must be pushed out to the sides.
    final dev = math.atan2(b.vx.abs(), -b.vy) * 180 / math.pi;
    final s1 = _spd(p1), s2 = _spd(p2);
    print('simultaneous: ball deviation ${dev.toStringAsFixed(2)} deg, puck speeds ${(s1 / W).toStringAsFixed(3)} / ${(s2 / W).toStringAsFixed(3)} W/s');
    expect(-b.vy, greaterThan(0));
    expect(dev, lessThan(5));
    expect(p1.vx, lessThan(0));
    expect(p2.vx, greaterThan(0));
    expect((s1 - s2).abs() / math.max(s1, s2), lessThan(.3));
  });

  test('repeated identical shots from the same state give identical results', () {
    List<double> once() {
      final e = Engine(_cfg(), rand: math.Random(1).nextDouble);
      e.fireVec(e.bodies[2], .3, -.954, .8);
      _rest(e);
      return _state(e);
    }

    final r0 = once();
    for (var k = 0; k < 4; k++) {
      expect(once(), r0);
    }
    print('repeat: 5 identical runs');
  });

  test('frame-rate independence: 30 fps and 144 fps end in the bit-identical rest state', () {
    List<double> run(double dt) {
      final e = Engine(_cfg(), rand: math.Random(1).nextDouble);
      final rnd = math.Random(9);
      for (final b in e.bodies) {
        final a = rnd.nextDouble() * 2 * math.pi, v = rnd.nextDouble() * 4 * W;
        b.vx = math.cos(a) * v;
        b.vy = math.sin(a) * v;
      }
      _rest(e, dt);
      return _state(e);
    }

    final lo = run(1 / 30), hi = run(1 / 144), mid = run(1 / 60);
    var maxd = 0.0;
    for (var i = 0; i < lo.length; i++) {
      maxd = math.max(maxd, (lo[i] - hi[i]).abs());
    }
    print('fps: max |30fps - 144fps| over all bodies = $maxd px');
    expect(lo, hi);
    expect(mid, hi);
  });

  test('goal detection: whole ball over the line counts, part of it does not; fast shots never missed', () {
    for (final (k, want) in [(.95, false), (1.02, true)]) {
      final e = _lab(0), b = e.ball, g = e.goals[0];
      e.phase = Phase.move;
      e.shots = 2;
      _place(b, e.CX, g.y - b.r * k, 0, 0);
      e.update(fdt);
      print('goal: centre ${k}r past the line -> ${e.phase == Phase.goal ? 'GOAL' : 'no goal'}');
      expect(e.phase == Phase.goal, want);
    }
    for (final v in [1.5, 3.0, 6.5]) {
      final e = _lab(0), b = e.ball, g = e.goals[0];
      e.phase = Phase.move;
      e.shots = 2;
      _place(b, e.CX + 40, g.y + .3 * W, 0, -v * W);
      for (var i = 0; i < 120 && e.phase == Phase.move; i++) {
        e.update(fdt);
      }
      print('goal: ball at ${v} W/s into the mouth -> ${e.phase == Phase.goal ? 'GOAL' : 'missed'}');
      expect(e.phase, Phase.goal);
    }
    // just wide of the post: never a goal, and it stays on the pitch
    final e = _lab(0), b = e.ball, g = e.goals[0];
    e.phase = Phase.move;
    e.shots = 2;
    _place(b, g.x1 - b.r - 6, g.y + .4 * W, 0, -5 * W);
    for (var i = 0; i < 120; i++) {
      e.update(fdt);
    }
    expect(e.phase == Phase.goal, isFalse);
    expect(b.y, greaterThanOrEqualTo(e.Ft + b.r - .5));
  });

  test('natural stopping: speed falls monotonically (free roll) and reaches exactly 0', () {
    for (final ball in [true, false]) {
      for (final v in [.1, 1.0, 3.0]) {
        final e = _lab(1), b = ball ? e.ball : e.bodies[0];
        _place(b, e.CX, e.Fb - b.r - 2, 0, -v * W);
        var prev = _spd(b), t = 0.0;
        while (_spd(b) > 0 && t < 10) {
          e.update(fdt);
          t += fdt;
          expect(_spd(b), lessThanOrEqualTo(prev));
          prev = _spd(b);
        }
        print('stop: ${ball ? 'ball' : 'puck'} ${v} W/s -> rest after ${t.toStringAsFixed(2)} s, ${((e.Fb - b.r - 2 - b.y) / W).toStringAsFixed(3)} W');
        expect(_spd(b), 0);
      }
    }
  });

  test('prediction == actual path, and predicting never touches the live state', () {
    final e = Engine(_cfg(), rand: math.Random(4).nextDouble);
    final shooter = e.bodies.indexWhere((b) => b.team == e.turn);
    final before = _state(e);
    final path = e.predictShot(shooter, .2, -.98, 3000);
    expect(_state(e), before, reason: 'prediction modified the game');
    e.fireRaw(e.bodies[shooter], .2, -.98, 3000, .8);
    final s = e.bodies[shooter];
    var maxd = 0.0, n = 0;
    // compared while the shot is live (a goal hands the live engine to its goal pause; the prediction is pure physics)
    for (var i = 0; i + 3 < path.length && _moving(e) && e.phase == Phase.move; i += 4) {
      e.acc = e.step; // exactly one physics step per update
      e.update(0);
      maxd = math.max(maxd, math.max((s.x - path[i]).abs() + (s.y - path[i + 1]).abs(),
          (e.ball.x - path[i + 2]).abs() + (e.ball.y - path[i + 3]).abs()));
      n++;
    }
    print('predict: $n steps compared, max deviation $maxd px');
    expect(n, greaterThan(50));
    expect(maxd, 0);
  });
}
