// v0.7 PHYSICS_CONFIG acceptance tests (owner spec, 9 criteria). Headless: Engine only, no widgets.
// Every number is in W (PHYSICS_CONFIG.wPx world px). Run: flutter test test/physics_v07_acceptance_test.dart
// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

final double W = PHYSICS_CONFIG.wPx;
const double fdt = 1 / 60;

MatchCfg _cfg() => MatchCfg(
    field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0);

/// stars engine with [keep] pucks plus the ball; everything at rest, ball parked at the centre.
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
  // unused ball waits inside the top goal net (no scoring outside Phase.move); pucks are always placed
  _place(e.ball, e.CX, e.Ft - 30, 0, 0);
  return e;
}

void _place(Body b, double x, double y, double vx, double vy) {
  b.x = b.px = x;
  b.y = b.py = y;
  b.vx = vx;
  b.vy = vy;
}

double _spd(Body b) => math.sqrt(b.vx * b.vx + b.vy * b.vy);
double _dist(Body a, Body b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

/// time for [b] (launched at v0 W/s) to fall to v0/e, interpolated between frames
double _tau(Engine e, Body b, double v0) {
  final target = v0 * W * math.exp(-1);
  var t = 0.0, prev = _spd(b);
  for (var i = 0; i < 600; i++) {
    e.update(fdt);
    final s = _spd(b);
    if (s <= target) return t + fdt * PHYSICS_CONFIG.playbackSpeed * (prev - target) / (prev - s);
    prev = s;
    t += fdt * PHYSICS_CONFIG.playbackSpeed; // simulated seconds (update() scales time by playbackSpeed)
  }
  return double.nan;
}

void main() {
  test('config: sizes in W, collision radius == drawn radius (render draws b.r)', () {
    final e = _lab(1);
    print('W=${W}px  puck r=${e.bodies[0].r.toStringAsFixed(2)}px (${(2 * e.bodies[0].r / W).toStringAsFixed(4)} W)'
        '  ball r=${e.ball.r.toStringAsFixed(2)}px (${(2 * e.ball.r / W).toStringAsFixed(4)} W)');
    expect(2 * e.bodies[0].r / W, closeTo(.134, 1e-9));
    expect(2 * e.ball.r / W, closeTo(.058, 1e-9));
    expect(1 / e.ball.im, closeTo(3 / e.bodies[0].im, 1e-9)); // m_ball = 3 m_puck
  });

  test('1. ball decay: released at 1 W/s, tau = 0.5 +- 0.1 s', () {
    final e = _lab(0);
    _place(e.ball, e.CX, e.Fb - 150, 0, -1 * W);
    final t = _tau(e, e.ball, 1);
    print('1. ball tau = ${t.toStringAsFixed(3)} s');
    expect(t, inInclusiveRange(.4, .6));
  });

  test('2. puck decay: released at 1 W/s, tau = 0.35 +- 0.07 s', () {
    final e = _lab(1), p = e.bodies[0];
    _place(p, e.CX, e.Fb - 150, 0, -1 * W);
    final t = _tau(e, p, 1);
    print('2. puck tau = ${t.toStringAsFixed(3)} s');
    expect(t, inInclusiveRange(.28, .42));
  });

  test('stop threshold: a slow body stops dead below 0.02 W/s', () {
    final e = _lab(0), b = e.ball;
    _place(b, e.CX, e.CY, .03 * W, 0);
    var t = 0.0;
    while (_spd(b) > 0 && t < 5) {
      e.update(fdt);
      final s = _spd(b);
      if (s > 0) expect(s, greaterThanOrEqualTo(.02 * W - 1e-9));
      t += fdt;
    }
    print('stop: .03 W/s -> rest after ${t.toStringAsFixed(3)} s');
    expect(_spd(b), 0);
  });

  test('3. no tunnelling: ball at 6.5 W/s into a still puck from 16 directions x 5 offsets', () {
    var cases = 0, hits = 0, worst = 1e9;
    for (var k = 0; k < 16; k++) {
      final a = k * math.pi / 8;
      for (final off in [-.9, -.5, 0.0, .5, .9]) {
        for (final frame in [1 / 60, 1 / 30]) {
          final e = _lab(1), p = e.bodies[0], b = e.ball;
          final m = p.r + b.r;
          final dx = math.cos(a), dy = math.sin(a); // ball travels along (dx,dy)
          final sx = e.CX - dx * .45 * W - dy * off * m, sy = e.CY - dy * .45 * W + dx * off * m;
          _place(p, e.CX, e.CY, 0, 0);
          _place(b, sx, sy, dx * 6.5 * W, dy * 6.5 * W);
          var hit = false;
          for (var i = 0; i < 30; i++) {
            e.update(frame);
            final d = _dist(p, b);
            worst = math.min(worst, d / m);
            expect(d, greaterThan(m - .5), reason: 'overlap at a=$k off=$off');
            hit |= _spd(p) > 0;
          }
          // the ball never ends up beyond the puck along its line without having touched it
          final along = (b.x - p.x) * dx + (b.y - p.y) * dy;
          if (!hit) expect(along, lessThan(0), reason: 'passed through a=$k off=$off');
          cases++;
          if (hit) hits++;
        }
      }
    }
    print('3. tunnelling: $hits/$cases contacts detected, min centre distance / (r_b + r_p) = ${worst.toStringAsFixed(4)}');
    expect(hits, cases);
  });

  test('4. gap: ball at 3 W/s through two pucks spaced 2 Dp + Db + 0.02 W passes straight', () {
    final e = _lab(2), p1 = e.bodies[0], p2 = e.bodies[1], b = e.ball;
    final gap = 2 * .134 * W + .058 * W + .02 * W;
    _place(p1, e.CX - gap / 2, e.CY, 0, 0);
    _place(p2, e.CX + gap / 2, e.CY, 0, 0);
    _place(b, e.CX, e.CY + .4 * W, 0, -3 * W);
    for (var i = 0; i < 40; i++) {
      e.update(fdt);
    }
    final dev = math.atan2(b.vx, -b.vy).abs() * 180 / math.pi;
    print('4. gap: ball y ${(b.y - e.CY).toStringAsFixed(1)} px (past the pair), deviation ${dev.toStringAsFixed(3)} deg, '
        'pucks moved ${_spd(p1)} / ${_spd(p2)}');
    expect(b.y, lessThan(e.CY - p1.r));
    expect(dev, lessThan(1));
    expect(_spd(p1) + _spd(p2), 0);
  });

  test('5. head-on: ball 4 W/s into a still puck keeps going (~60% normal speed), puck faster', () {
    final e = _lab(1), p = e.bodies[0], b = e.ball;
    _place(p, e.CX, e.CY, 0, 0);
    _place(b, e.CX, e.CY + .3 * W, 0, -4 * W);
    var pre = 0.0;
    for (var i = 0; i < 60 && _spd(p) == 0; i++) {
      pre = -b.vy;
      e.update(fdt);
    }
    // undo the friction of the contact frame so we compare velocities at the instant of impact
    final ratio = (-b.vy) / pre * math.exp(PHYSICS_CONFIG.ballK * fdt * PHYSICS_CONFIG.playbackSpeed);
    print('5. head-on: ball ${(pre / W).toStringAsFixed(3)} -> ${(-b.vy / W).toStringAsFixed(3)} W/s '
        '(ratio ${ratio.toStringAsFixed(3)}), puck ${(-p.vy / W).toStringAsFixed(3)} W/s');
    expect(-b.vy, greaterThan(0), reason: 'ball keeps its direction');
    expect(ratio, inInclusiveRange(.45, .75));
    expect(-p.vy, greaterThan(-b.vy), reason: 'puck leaves faster than the ball');
    expect(b.vx.abs() + p.vx.abs(), lessThan(1e-6));
  });

  test('6. oblique 30 deg: ball deflects < 20 deg, puck moves along the normal', () {
    final e = _lab(1), p = e.bodies[0], b = e.ball;
    final m = p.r + b.r, off = m * math.sin(30 * math.pi / 180);
    _place(p, e.CX, e.CY, 0, 0);
    _place(b, e.CX - off, e.CY + .3 * W, 0, -4 * W);
    for (var i = 0; i < 60 && _spd(p) == 0; i++) {
      e.update(fdt);
    }
    final defl = math.atan2(b.vx, -b.vy).abs() * 180 / math.pi;
    // normal at impact: from ball to puck. Rebuild it from the contact geometry (ball centre at x = CX - off).
    final nx = off / m, ny = -math.sqrt(1 - nx * nx);
    final pAng = math.acos(((p.vx * nx + p.vy * ny) / _spd(p)).clamp(-1.0, 1.0)) * 180 / math.pi;
    print('6. oblique: ball deflection ${defl.toStringAsFixed(2)} deg, puck off-normal ${pAng.toStringAsFixed(3)} deg, '
        'puck ${(_spd(p) / W).toStringAsFixed(2)} W/s, ball ${(_spd(b) / W).toStringAsFixed(2)} W/s');
    expect(defl, lessThan(20));
    expect(pAng, lessThan(1));
  });

  test('kick: a flicked puck at 2 W/s sends a still ball off at ~5 W/s (config ballKickSpeed)', () {
    final e = _lab(1), p = e.bodies[0], b = e.ball;
    _place(b, e.CX, e.CY, 0, 0);
    _place(p, e.CX, e.CY + p.r + b.r + 2, 0, 0);
    e.fireRaw(p, 0, -1, 2 * W, .5);
    var peak = 0.0;
    for (var i = 0; i < 30; i++) {
      e.update(fdt);
      peak = math.max(peak, _spd(b));
    }
    print('kick: ball peak ${(peak / W).toStringAsFixed(3)} W/s, puck after ${(p.vy / W).toStringAsFixed(3)} W/s');
    expect(peak / W, closeTo(PHYSICS_CONFIG.ballKickSpeed, .25));
  });

  test('7. never stuck: 300 random full-team scenes settle; nothing overlaps or creeps > 2 s', () {
    final rnd = math.Random(7);
    var worstOverlap = 0.0, worstCreep = 0.0, worstRest = 0.0;
    for (var s = 0; s < 300; s++) {
      final e = Engine(_cfg(), rand: math.Random(s).nextDouble);
      for (final b in e.bodies) {
        final a = rnd.nextDouble() * 2 * math.pi, v = rnd.nextDouble() * (identical(b, e.ball) ? 6.5 : 4.2) * W;
        b.vx = math.cos(a) * v;
        b.vy = math.sin(a) * v;
      }
      if (s % 10 == 0) {
        // pinned in a corner: a puck in the corner, the ball and a puck driven into it
        final p = e.bodies[0], q = e.bodies[1];
        _place(p, e.Fl + p.r, e.Ft + p.r, 0, 0);
        _place(e.ball, e.Fl + 2 * p.r + e.ball.r + 5, e.Ft + p.r, -5 * W, -1 * W);
        _place(q, e.Fl + p.r, e.Ft + 3 * p.r + 10, -.5 * W, -3 * W);
      }
      final ov = List.filled(e.bodies.length, 0.0), cr = List.filled(e.bodies.length, 0.0);
      var t = 0.0;
      while (t < 20) {
        e.update(fdt);
        t += fdt;
        var moving = false;
        for (var i = 0; i < e.bodies.length; i++) {
          final b = e.bodies[i];
          var o = false;
          for (final c in e.bodies) {
            if (!identical(b, c) && _dist(b, c) < b.r + c.r - 1) o = true;
          }
          ov[i] = o ? ov[i] + fdt : 0;
          final sp = _spd(b);
          cr[i] = (sp > 0 && sp < .05 * W) ? cr[i] + fdt : 0;
          worstOverlap = math.max(worstOverlap, ov[i]);
          worstCreep = math.max(worstCreep, cr[i]);
          moving |= sp > 0;
        }
        if (!moving && e.phase != Phase.goal) break;
      }
      worstRest = math.max(worstRest, t);
    }
    print('7. stuck: longest overlap ${worstOverlap.toStringAsFixed(3)} s, longest creep (<.05 W/s) '
        '${worstCreep.toStringAsFixed(3)} s, slowest scene at rest after ${worstRest.toStringAsFixed(2)} s');
    expect(worstOverlap, lessThan(2));
    expect(worstCreep, lessThan(2));
    expect(worstRest, lessThan(20));
  });

  test('8. corners: ball and puck into all 4 corners at many speeds/angles never leave the pitch or stick', () {
    var cases = 0, out = 0, stuck = 0, badBounce = 0;
    var worstOut = 0.0;
    for (final ball in [true, false]) {
      for (var c = 0; c < 4; c++) {
        final sx = c % 2 == 0 ? -1.0 : 1.0, sy = c < 2 ? -1.0 : 1.0; // corner direction
        for (final v in [.5, 1.0, 2.0, 4.0, 6.5]) {
          for (final deg in [45.0, 30.0, 60.0, 10.0, 80.0, 44.0, 46.0]) {
            for (final d0 in [.12, .3]) {
              final e = _lab(1), b = ball ? e.ball : e.bodies[0];
              final r = b.r;
              final cxp = sx < 0 ? e.Fl + r : e.Fr - r, cyp = sy < 0 ? e.Ft + r : e.Fb - r; // centre at the corner
              final a = deg * math.pi / 180;
              final ux = sx * math.cos(a), uy = sy * math.sin(a);
              // start d0 W back from the corner along the incoming ray (aimed exactly at the corner)
              _place(b, cxp - ux * d0 * W, cyp - uy * d0 * W, ux * v * W, uy * v * W);
              var t = 0.0, fx = false, fy = false;
              while (t < 6 && _spd(b) > 0) {
                e.update(fdt);
                t += fdt;
                // the goal mouths (between the posts) are open: only the side walls and the goal lines count there
                final mouth = b.x > e.goals[0].x1 && b.x < e.goals[0].x2;
                final o = math.max(math.max(e.Fl + r - b.x, b.x - (e.Fr - r)),
                    mouth ? -1.0 : math.max(e.Ft + r - b.y, b.y - (e.Fb - r)));
                if (o > .5) {
                  if (out < 3) print('  out: ball=$ball corner=$c v=$v deg=$deg d0=$d0 t=${t.toStringAsFixed(2)} x=${b.x.toStringAsFixed(1)} y=${b.y.toStringAsFixed(1)} o=${o.toStringAsFixed(1)}');
                  out++;
                  worstOut = math.max(worstOut, o);
                }
                fx |= b.vx * sx < 0;
                fy |= b.vy * sy < 0;
              }
              cases++;
              if (_spd(b) > 0) stuck++;
              // a body that reaches the corner region with speed must come back off both walls
              if (v >= 2 && !(fx && fy)) badBounce++;
            }
          }
        }
      }
    }
    print('8. corners: $cases runs, frames outside ${out} (worst ${worstOut.toStringAsFixed(2)} px), '
        'not at rest after 6 s: $stuck, missing a double bounce: $badBounce');
    expect(out, 0);
    expect(stuck, 0);
    expect(badBounce, 0);
  });

  test('8b. corner: a still body jammed in a corner is left alone (no nudge, no endless jiggle)', () {
    final e = _lab(1), p = e.bodies[0], b = e.ball;
    _place(p, e.Fl + p.r, e.Ft + p.r, 0, 0);
    _place(b, e.Fl + b.r, e.Ft + 2 * p.r + b.r, 0, 0);
    for (var i = 0; i < 60; i++) {
      e.update(fdt);
    }
    expect(_spd(p) + _spd(b), 0);
    expect(p.x, closeTo(e.Fl + p.r, 1e-9));
    expect(p.y, closeTo(e.Ft + p.r, 1e-9));
  });

  test('9. deterministic: same input -> bit-identical result', () {
    List<double> run() {
      final e = Engine(_cfg(), rand: math.Random(11).nextDouble);
      final rnd = math.Random(5);
      for (final b in e.bodies) {
        final a = rnd.nextDouble() * 2 * math.pi, v = rnd.nextDouble() * 5 * W;
        b.vx = math.cos(a) * v;
        b.vy = math.sin(a) * v;
      }
      final out = <double>[];
      for (var f = 0; f < 600; f++) {
        e.update(f % 3 == 0 ? 1 / 50 : fdt);
        for (final b in e.bodies) {
          out..add(b.x)..add(b.y)..add(b.vx)..add(b.vy);
        }
      }
      return out;
    }

    final a = run(), b = run();
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i], b[i]);
    }
    print('9. determinism: ${a.length} values bit-identical');
  });
}
