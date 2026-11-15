// v0.7b headless tests: findings of the match play-simulation (striker kick only, gout walk-out), goal geometry
// (deeper / wider net, posts for every body), cushion glide, corners, disc stats, and a match-level regression sweep.
// Every number in W (PHYSICS_CONFIG.wPx world px), every time in simulated seconds.
// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

final double W = PHYSICS_CONFIG.wPx;
const double fdt = 1 / 60;
final double simDt = fdt * PHYSICS_CONFIG.playbackSpeed;

MatchCfg _cfg({List<DiscStats>? stats}) => MatchCfg(
    field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0, stats: stats);

Engine _lab(int keep, {List<DiscStats>? stats}) {
  final e = Engine(_cfg(stats: stats), rand: math.Random(3).nextDouble);
  final discs = e.bodies.where((b) => !identical(b, e.ball)).take(keep).toList();
  e.bodies
    ..clear()
    ..addAll(discs)
    ..add(e.ball);
  for (final b in e.bodies) {
    b.vx = b.vy = 0;
  }
  _place(e.ball, e.CX, e.CY, 0, 0);
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

/// how far [b] is outside the legal area (pitch rectangle, plus the net box behind each goal mouth), px
double _outside(Engine e, Body b) {
  final r = b.r;
  var o = math.max(e.Fl + r - b.x, b.x - (e.Fr - r));
  final g = e.goals[0];
  final inMouthX = b.x >= g.x1 + r - .5 && b.x <= g.x2 - r + .5;
  final mouth = b.x > g.x1 && b.x < g.x2;
  if (!mouth) {
    o = math.max(o, math.max(e.Ft + r - b.y, b.y - (e.Fb - r)));
  } else {
    o = math.max(o, math.max(e.Ft - e.DEPTH + r - b.y, b.y - (e.Fb + e.DEPTH - r)));
    // inside the net (centre behind the line by more than the post can hold): side nets
    final deep = math.max(e.Ft - b.y, b.y - e.Fb) > r;
    if (deep && !inMouthX) o = math.max(o, math.max(g.x1 + r - b.x, b.x - (g.x2 - r)));
  }
  return o;
}

double _ke(Engine e) => e.bodies.fold(0.0, (s, b) => s + (b.vx * b.vx + b.vy * b.vy) / b.im);

void main() {
  // ------------------------------------------------------------------------------------------------ striker kick
  test('kick only from the flicked puck: a knocked-on puck hitting the ball is a plain impulse (no energy pump)', () {
    // puck A (not flicked: just moving, e.g. knocked on by another puck) runs into a still ball
    final e = _lab(1), p = e.bodies[0], b = e.ball;
    _place(b, e.CX, e.CY, 0, 0);
    _place(p, e.CX, e.CY + .3 * W, 0, -2 * W);
    final k0 = _ke(e);
    var peak = 0.0, kMax = 0.0;
    for (var i = 0; i < 40; i++) {
      e.update(fdt);
      peak = math.max(peak, _spd(b));
      kMax = math.max(kMax, _ke(e));
    }
    // impulse rule: ball gets (1 + e) m_p / (m_p + m_b) of the closing speed = 1.5 / 4 = .375 x
    print('knocked-on puck 2 W/s -> ball peak ${(peak / W).toStringAsFixed(3)} W/s, KE max / start ${(kMax / k0).toStringAsFixed(3)}');
    expect(peak / W, lessThan(2 * .4));
    expect(kMax, lessThanOrEqualTo(k0 * 1.0001));
    // the same puck FLICKED (striker) kicks: kickGain x closing speed
    final f = _lab(1), q = f.bodies[0], c = f.ball;
    _place(c, f.CX, f.CY, 0, 0);
    _place(q, f.CX, f.CY + .3 * W, 0, 0);
    f.fireRaw(q, 0, -1, 2 * W, .5);
    var pk = 0.0;
    for (var i = 0; i < 40; i++) {
      f.update(fdt);
      pk = math.max(pk, _spd(c));
    }
    print('flicked puck 2 W/s -> ball peak ${(pk / W).toStringAsFixed(3)} W/s');
    expect(pk / W, greaterThan(4));
  });

  test('striker status: kept through a cushion touch (bank shot), lost at the first puck contact (no chain kicks)', () {
    // bank shot: puck flicked into the left cushion rebounds into a ball -> still a striker kick
    final e = _lab(1), p = e.bodies[0], b = e.ball;
    _place(p, e.Fl + p.r + 60, e.CY, 0, 0);
    _place(b, e.Fl + p.r + 230, e.CY, 0, 0);
    e.fireRaw(p, -1, 0, 2 * W, .5);
    var peak = 0.0;
    for (var i = 0; i < 120; i++) {
      e.update(fdt);
      peak = math.max(peak, _spd(b));
    }
    // puck A flicked into puck B, B runs on into the ball -> B is no striker: plain impulse
    final f = _lab(2), a1 = f.bodies[0], a2 = f.bodies[1], c = f.ball;
    _place(a1, f.CX, f.CY + .5 * W, 0, 0);
    _place(a2, f.CX, f.CY + .2 * W, 0, 0);
    _place(c, f.CX, f.CY - .1 * W, 0, 0);
    f.fireRaw(a1, 0, -1, 2 * W, .5);
    var chain = 0.0;
    for (var i = 0; i < 120; i++) {
      f.update(fdt);
      chain = math.max(chain, _spd(c));
    }
    print('bank shot -> ball peak ${(peak / W).toStringAsFixed(3)} W/s; puck->puck->ball chain -> ball peak ${(chain / W).toStringAsFixed(3)} W/s');
    expect(peak / W, greaterThan(1.5));
    expect(chain / W, lessThan(1.0));
  });

  // ------------------------------------------------------------------------------------------------ goals
  test('goal geometry = PHYSICS_CONFIG (W units): wider mouth, deeper net, posts drawn = collision', () {
    final e = _lab(0);
    final g = e.goals[0];
    print('goal mouth ${((g.x2 - g.x1) / W).toStringAsFixed(4)} W, depth ${(e.DEPTH / W).toStringAsFixed(4)} W, '
        'post r ${(e.tu.postR / W).toStringAsFixed(4)} W');
    expect((g.x2 - g.x1) / W, closeTo(PHYSICS_CONFIG.goalWidth, 1e-9));
    expect(e.DEPTH / W, closeTo(PHYSICS_CONFIG.goalDepth, 1e-9));
    expect(e.tu.postR / W, closeTo(PHYSICS_CONFIG.postR, 1e-9));
    expect(PHYSICS_CONFIG.goalWidth, greaterThan(.301)); // wider than v0.7 (248 px)
    expect(PHYSICS_CONFIG.goalDepth, greaterThan(.0873)); // deeper than v0.7 (72 px)
    expect(e.DEPTH, greaterThan(2 * e.ball.r)); // a whole ball (= a goal) fits in the net with room to spare
  });

  test('goal mouth sweep: ball and puck at both goals, posts / mouth / net corners, many speeds and angles', () {
    var cases = 0, out = 0, stuck = 0, postOverlap = 0;
    var worstOut = 0.0;
    for (final isBall in [true, false]) {
      for (var gi = 0; gi < 2; gi++) {
        for (final ax in [-1.25, -1.05, -1.0, -.97, -.8, -.5, 0.0, .5, .8, .97, 1.0, 1.05, 1.25]) {
          for (final deg in [-60.0, -35.0, -15.0, 0.0, 15.0, 35.0, 60.0]) {
            for (final v in [.5, 1.5, 3.0, 5.0, 6.5]) {
              final e = _lab(1), b = isBall ? e.ball : e.bodies[0];
              final other = isBall ? e.bodies[0] : e.ball;
              _place(other, e.CX + 3 * W, e.CY, 0, 0); // parked far away (off the pitch, never touched)
              e.bodies.remove(other);
              final g = e.goals[gi];
              final half = (g.x2 - g.x1) / 2;
              final tx = e.CX + ax * half, ty = g.y; // aim point on the goal line (ax = +-1: exactly at a post)
              final a = deg * math.pi / 180;
              final ux = math.sin(a), uy = g.d * math.cos(a);
              final d0 = .35 * W;
              _place(b, (tx - ux * d0).clamp(e.Fl + b.r, e.Fr - b.r).toDouble(), ty - uy * d0, ux * v * W, uy * v * W);
              var t = 0.0;
              while (t < 8 && _spd(b) > 0) {
                e.update(fdt);
                t += simDt;
                final o = _outside(e, b);
                if (o > .5) {
                  if (out < 4) print('  out: ball=$isBall goal=$gi ax=$ax deg=$deg v=$v o=${o.toStringAsFixed(2)} x=${b.x.toStringAsFixed(1)} y=${b.y.toStringAsFixed(1)}');
                  out++;
                  worstOut = math.max(worstOut, o);
                }
                for (final px in [g.x1, g.x2]) {
                  final dd = math.sqrt((b.x - px) * (b.x - px) + (b.y - g.y) * (b.y - g.y));
                  if (dd < b.r + e.tu.postR - .5) postOverlap++;
                }
              }
              cases++;
              if (_spd(b) > 0) stuck++;
            }
          }
        }
      }
    }
    print('goal mouth: $cases runs, frames outside pitch+net $out (worst ${worstOut.toStringAsFixed(2)} px), '
        'post overlaps $postOverlap, still moving after 8 s: $stuck');
    expect(out, 0);
    expect(postOverlap, 0);
    expect(stuck, 0);
  });

  test('inside the net: balls fired into the back corners and along the side nets settle, never leave, no jitter', () {
    var runs = 0, out = 0, slowCreep = 0;
    for (var gi = 0; gi < 2; gi++) {
      final g0 = _lab(0).goals[gi];
      for (final sx in [-1.0, 1.0]) {
        for (final deg in [5.0, 20.0, 45.0, 70.0, 88.0]) {
          for (final v in [.5, 2.0, 4.0, 6.5]) {
            final e = _lab(0), b = e.ball, g = e.goals[gi];
            final a = deg * math.pi / 180;
            _place(b, e.CX, g.y + g.d * b.r * 1.5, sx * math.cos(a) * v * W, g.d * math.sin(a) * v * W);
            var t = 0.0, cr = 0.0;
            while (t < 8 && _spd(b) > 0) {
              e.update(fdt);
              t += simDt;
              if (_outside(e, b) > .5) out++;
              final s = _spd(b);
              cr = (s > 0 && s < .05 * W) ? cr + simDt : 0;
              if (cr > 2) slowCreep++;
            }
            if (_spd(b) > 0) slowCreep++;
            runs++;
            expect(g0.x1, g.x1);
          }
        }
      }
    }
    print('net: $runs runs, frames outside $out, creeping/stuck $slowCreep');
    expect(out, 0);
    expect(slowCreep, 0);
  });

  test('puck parked in a goal net walks out and stops in front of the line; it pushes a ball gently, not bulldozes', () {
    final e = _lab(1), p = e.bodies[0], b = e.ball, g = e.goals[1];
    e.phase = Phase.move; // walk-out is a play-time rule
    e.shots = 2;
    _place(p, e.CX, g.y + p.r * .6, 0, .05 * W); // slow puck sliding into the bottom net
    _place(b, e.CX, g.y - p.r * 1.3 - b.r, 0, 0); // ball right in front of the mouth
    var t = 0.0, maxBall = 0.0, maxPuck = 0.0;
    while (t < 6 && (_spd(p) > 0 || _spd(b) > 0 || p.gout != null)) {
      e.update(fdt);
      t += simDt;
      maxBall = math.max(maxBall, _spd(b));
      maxPuck = math.max(maxPuck, _spd(p));
      expect(_dist(p, b), greaterThan(p.r + b.r - 1));
    }
    print('gout: puck out after ${t.toStringAsFixed(2)} s, at ${((g.y - p.y) / p.r).toStringAsFixed(2)} r in front of the line, '
        'max puck ${(maxPuck / W).toStringAsFixed(3)} W/s, ball pushed to ${(maxBall / W).toStringAsFixed(3)} W/s');
    expect(p.gout, isNull);
    expect(g.y - p.y, greaterThan(p.r)); // whole puck back on the pitch
    expect(maxPuck / W, lessThanOrEqualTo(PHYSICS_CONFIG.puckEjectSpeed + 1e-6));
    expect(maxBall / W, lessThan(PHYSICS_CONFIG.puckEjectSpeed * 1.5 + .01));
  });

  // ------------------------------------------------------------------------------------------------ cushions / corners
  test('cushion glide: ball and puck grazing a side line keep >= 99% of their free-roll speed (clean glance)', () {
    for (final isBall in [true, false]) {
      for (final deg in [1.0, 3.0, 5.0, 10.0]) {
        final e = _lab(1), b = isBall ? e.ball : e.bodies[0];
        e.bodies.removeWhere((x) => !identical(x, b));
        final a = deg * math.pi / 180, v = 2.0 * W;
        _place(b, e.Fl + b.r + 2, e.Fb - 150, -v * math.sin(a), -v * math.cos(a));
        var t = 0.0;
        for (var i = 0; i < 30; i++) {
          e.update(fdt);
          t += simDt;
        }
        final k = isBall ? PHYSICS_CONFIG.ballK : PHYSICS_CONFIG.puckK;
        final free = 2.0 * math.exp(-k * t);
        final kept = _spd(b) / W / free;
        print('glide ${isBall ? 'ball' : 'puck'} ${deg.toStringAsFixed(0)} deg: kept ${(kept * 100).toStringAsFixed(2)}% of free roll');
        expect(kept, greaterThan(deg <= 5 ? .99 : .98));
        expect(b.x, greaterThanOrEqualTo(e.Fl + b.r - 1e-6));
      }
    }
  });

  test('corner: a ball resting in each corner is always played out by a flicked puck (never stuck)', () {
    var runs = 0, stuck = 0;
    for (var c = 0; c < 4; c++) {
      final sx = c % 2 == 0 ? -1.0 : 1.0, sy = c < 2 ? -1.0 : 1.0;
      for (final deg in [15.0, 30.0, 45.0, 60.0, 75.0]) {
        for (final pull in [.3, .6, 1.0]) {
          final e = _lab(1), p = e.bodies[0], b = e.ball;
          final cx = sx < 0 ? e.Fl + b.r : e.Fr - b.r, cy = sy < 0 ? e.Ft + b.r : e.Fb - b.r;
          _place(b, cx, cy, 0, 0);
          final a = deg * math.pi / 180, ux = sx * math.cos(a), uy = sy * math.sin(a);
          // puck placed .3 W back along the ray that hits the ball centre
          final px = (cx - ux * .3 * W).clamp(e.Fl + p.r, e.Fr - p.r).toDouble();
          final py = (cy - uy * .3 * W).clamp(e.Ft + p.r, e.Fb - p.r).toDouble();
          _place(p, px, py, 0, 0);
          var dx = cx - px, dy = cy - py;
          final l = math.sqrt(dx * dx + dy * dy);
          dx /= l;
          dy /= l;
          e.fireRaw(p, dx, dy, PHYSICS_CONFIG.shotMax * W * shotCurve(pull), pull);
          var moved = 0.0, t = 0.0;
          while (t < 6 && (_spd(p) > 0 || _spd(b) > 0)) {
            e.update(fdt);
            t += simDt;
            moved = math.max(moved, math.sqrt((b.x - cx) * (b.x - cx) + (b.y - cy) * (b.y - cy)));
            expect(_outside(e, b), lessThan(.5));
          }
          runs++;
          // a soft pull (.3) may legitimately just nudge the ball; a medium or full flick must play it out of the corner
          if ((pull >= .6 && moved < 2 * b.r) || _spd(b) > 0) {
            stuck++;
            print('  stuck: corner $c deg $deg pull $pull moved ${(moved / b.r).toStringAsFixed(2)} r');
          }
        }
      }
    }
    print('corner play-out: $runs flicks at a ball in the corner, ball left the corner in ${runs - stuck}');
    expect(stuck, 0);
  });

  test('corner crowd: ball + 3 pucks jammed in each corner and hit hard settle with no overlap, escape or creep', () {
    var worstOverlap = 0.0, out = 0, slow = 0.0;
    for (var c = 0; c < 4; c++) {
      for (final v in [2.0, 4.0, 6.5]) {
        final e = _lab(4);
        final sx = c % 2 == 0 ? -1.0 : 1.0, sy = c < 2 ? -1.0 : 1.0;
        final ox = sx < 0 ? e.Fl : e.Fr, oy = sy < 0 ? e.Ft : e.Fb;
        final P = e.bodies.where((b) => !identical(b, e.ball)).toList(), b = e.ball;
        final pr = P[0].r;
        _place(b, ox - sx * b.r, oy - sy * b.r, 0, 0);
        _place(P[0], ox - sx * (2 * b.r + pr + 1), oy - sy * pr, 0, 0);
        _place(P[1], ox - sx * pr, oy - sy * (2 * b.r + pr + 1), 0, 0);
        _place(P[2], ox - sx * (2 * b.r + 3 * pr + 3), oy - sy * pr, 0, 0);
        _place(P[3], ox - sx * .5 * W, oy - sy * .5 * W, sx * v * W * .7071, sy * v * W * .7071);
        final ov = List.filled(e.bodies.length, 0.0), cr = List.filled(e.bodies.length, 0.0);
        var t = 0.0;
        while (t < 10 && e.bodies.any((x) => _spd(x) > 0)) {
          e.update(fdt);
          t += simDt;
          for (var i = 0; i < e.bodies.length; i++) {
            final x = e.bodies[i];
            var o = false;
            for (final y in e.bodies) {
              if (!identical(x, y) && _dist(x, y) < x.r + y.r - 1) o = true;
            }
            ov[i] = o ? ov[i] + simDt : 0;
            worstOverlap = math.max(worstOverlap, ov[i]);
            final s = _spd(x);
            cr[i] = (s > 0 && s < .05 * W) ? cr[i] + simDt : 0;
            slow = math.max(slow, cr[i]);
            if (_outside(e, x) > .5) out++;
          }
        }
        expect(e.bodies.any((x) => _spd(x) > 0), isFalse);
      }
    }
    print('corner crowd: longest overlap ${worstOverlap.toStringAsFixed(3)} s, longest creep ${slow.toStringAsFixed(3)} s, frames outside $out');
    expect(worstOverlap, lessThan(.2));
    expect(slow, lessThan(2));
    expect(out, 0);
  });

  // ------------------------------------------------------------------------------------------------ shots / stats
  test('pull -> glide distance is smooth and monotonic (no kink at the end of the flight phase)', () {
    final d = <double>[];
    for (var i = 1; i <= 20; i++) {
      final pull = i / 20;
      final e = _lab(1), p = e.bodies[0];
      _place(e.ball, e.CX + 3 * W, e.CY, 0, 0);
      e.bodies.remove(e.ball);
      _place(p, e.Fl + p.r + 5, e.CY, 0, 0);
      // fire along a long diagonal path that stays clear of cushions for the short pulls
      e.fireRaw(p, 1, 0, PHYSICS_CONFIG.shotMax * W * shotCurve(pull), pull);
      var path = 0.0;
      for (var t = 0.0; t < 10 && _spd(p) > 0; t += simDt) {
        final x0 = p.x, y0 = p.y;
        e.update(fdt);
        path += math.sqrt((p.x - x0) * (p.x - x0) + (p.y - y0) * (p.y - y0));
      }
      d.add(path / W);
    }
    var worstJump = 0.0;
    for (var i = 2; i < d.length; i++) {
      expect(d[i], greaterThan(d[i - 1]));
      final inc0 = d[i - 1] - d[i - 2], inc1 = d[i] - d[i - 1];
      if (d[i] < .8) worstJump = math.max(worstJump, inc1 / inc0); // before the first cushion
    }
    print('pull 5%..100% -> path ${d.map((x) => x.toStringAsFixed(2)).join(' ')} W; worst increment ratio ${worstJump.toStringAsFixed(2)}');
    expect(worstJump, lessThan(2.2));
  });

  test('power stat: power 10 vs power 1 -> clearly faster launch, longer glide and harder kick; within calm caps', () {
    (double, double, double) shot(double power) {
      final e = _lab(1, stats: [DiscStats(power, 10), DiscStats.def]);
      final p = e.bodies[0], b = e.ball;
      // up the left lane (clear of the goal mouth): the ball runs to the far cushion and back
      _place(b, e.Fl + .2 * W, e.CY + .2 * W, 0, 0);
      _place(p, e.Fl + .2 * W, e.CY + .45 * W, 0, 0);
      e.fire(p, 0, -1e6, 1e6, true); // full pull straight at the ball
      final v0 = _spd(p);
      var peak = 0.0, path = 0.0;
      for (var t = 0.0; t < 10 && (_spd(p) > 0 || _spd(b) > 0); t += simDt) {
        final x0 = b.x, y0 = b.y;
        e.update(fdt);
        peak = math.max(peak, _spd(b));
        path += math.sqrt((b.x - x0) * (b.x - x0) + (b.y - y0) * (b.y - y0));
      }
      return (v0 / W, peak / W, path / W);
    }

    final lo = shot(1), mid = shot(5.5), hi = shot(10);
    print('power 1 / 5.5 / 10: launch ${lo.$1.toStringAsFixed(2)} / ${mid.$1.toStringAsFixed(2)} / ${hi.$1.toStringAsFixed(2)} W/s, '
        'ball kick ${lo.$2.toStringAsFixed(2)} / ${mid.$2.toStringAsFixed(2)} / ${hi.$2.toStringAsFixed(2)} W/s, '
        'ball path ${lo.$3.toStringAsFixed(2)} / ${mid.$3.toStringAsFixed(2)} / ${hi.$3.toStringAsFixed(2)} W');
    expect(hi.$1 / lo.$1, greaterThan(1.7));
    expect(hi.$2 / lo.$2, greaterThan(2.0));
    expect(hi.$3 / lo.$3, greaterThan(1.8));
    expect(mid.$2, inExclusiveRange(lo.$2, hi.$2));
    expect(hi.$1, lessThanOrEqualTo(PHYSICS_CONFIG.shotMax + 1e-9));
    expect(hi.$2, lessThanOrEqualTo(PHYSICS_CONFIG.ballMaxSpeed + 1e-6));
  });

  test('accuracy stat: accuracy 10 is exact, accuracy 1 spreads several degrees (human and AI shots alike)', () {
    (double, double) spread(double acc, bool human) {
      final e = Engine(_cfg(stats: [DiscStats(5, acc), DiscStats(5, acc)]), rand: math.Random(42).nextDouble);
      final p = e.bodies.firstWhere((b) => b.team == 0);
      var s2 = 0.0, mx = 0.0;
      const n = 300;
      for (var i = 0; i < n; i++) {
        e.phase = Phase.aim;
        e.turn = 0;
        e.fire(p, 0, -100, 100, human);
        final dev = math.atan2(e.lastUx, -e.lastUy) * 180 / math.pi;
        s2 += dev * dev;
        mx = math.max(mx, dev.abs());
        p.vx = p.vy = 0;
      }
      return (math.sqrt(s2 / n), mx);
    }

    final a10 = spread(10, true), a5 = spread(5, true), a1 = spread(1, true), ai1 = spread(1, false);
    print('accuracy 10 / 5 / 1: rms ${a10.$1.toStringAsFixed(2)} / ${a5.$1.toStringAsFixed(2)} / ${a1.$1.toStringAsFixed(2)} deg, '
        'max ${a10.$2.toStringAsFixed(2)} / ${a5.$2.toStringAsFixed(2)} / ${a1.$2.toStringAsFixed(2)} deg; AI accuracy 1 rms ${ai1.$1.toStringAsFixed(2)} deg');
    expect(a10.$2, 0);
    expect(a1.$1, greaterThan(2.5));
    expect(a5.$1, inExclusiveRange(a10.$1, a1.$1));
    expect(a1.$2, lessThanOrEqualTo(PHYSICS_CONFIG.accDevAt1Deg + 1e-9)); // bounded: still a precise game
    expect(ai1.$1, greaterThan(2.5));
  });

  // ------------------------------------------------------------------------------------------------ match sweep
  test('match play-simulation: AI vs AI and random flicks into crowds - no escape, overlap, creep, endless turn or energy pump', () {
    var turns = 0, out = 0, pump = 0, longest = 0.0, worstOverlap = 0.0, worstCreep = 0.0, maxBall = 0.0, maxPuck = 0.0;
    for (var m = 0; m < 12; m++) {
      final cfg = MatchCfg(
          field: m % 3, ball: 0, forms: [m % 4, (m ~/ 4) % 4], ai: true, aiLvl: m % 3, limit: 99, matchTime: 0,
          turnTime: 0, vip: [false, false], first: m % 2, stats: [DiscStats(1.0 + m % 10, 1.0 + (m * 7) % 10), DiscStats(10.0 - m % 10, 5)]);
      final e = Engine(cfg, rand: math.Random(m).nextDouble);
      e.aiTeams[0] = e.aiTeams[1] = true;
      final rnd = math.Random(100 + m);
      final randomFlicks = m.isOdd;
      for (var tn = 0; tn < 25; tn++) {
        for (var g = 0; g < 3000 && e.phase != Phase.aim; g++) {
          e.update(fdt);
        }
        if (randomFlicks) {
          final mine = e.bodies.where((b) => b.team == e.turn).toList();
          final p = mine[rnd.nextInt(mine.length)];
          final tgt = rnd.nextBool() ? e.ball : e.bodies[rnd.nextInt(e.bodies.length)];
          var dx = tgt.x - p.x, dy = tgt.y - p.y;
          var l = math.sqrt(dx * dx + dy * dy);
          if (l < 1) {
            dx = 0;
            dy = -1;
            l = 1;
          }
          final pull = (.15 + rnd.nextDouble() * .85) * LMAX;
          e.fire(p, dx / l * pull, dy / l * pull, pull, true);
        } else {
          for (var g = 0; g < 600 && e.phase == Phase.aim; g++) {
            e.update(fdt);
          }
        }
        if (e.phase != Phase.move) continue;
        final n = e.bodies.length;
        final ov = List.filled(n, 0.0), cr = List.filled(n, 0.0);
        var t = 0.0, k0 = _ke(e);
        while (e.phase == Phase.move && t < 20) {
          final striker = e.bodies.any((b) => b.striker), gout = e.bodies.any((b) => b.gout != null);
          e.update(fdt);
          t += simDt;
          final k1 = _ke(e);
          if (!striker && !gout && !e.bodies.any((b) => b.gout != null) && k1 > k0 * 1.001 + 1) pump++;
          k0 = k1;
          for (var i = 0; i < n; i++) {
            final b = e.bodies[i];
            if (_outside(e, b) > .5) out++;
            var o = false;
            for (final c in e.bodies) {
              if (!identical(b, c) && _dist(b, c) < b.r + c.r - 1) o = true;
            }
            ov[i] = o ? ov[i] + simDt : 0;
            worstOverlap = math.max(worstOverlap, ov[i]);
            final s = _spd(b);
            cr[i] = (s > 0 && s < .05 * W) ? cr[i] + simDt : 0;
            worstCreep = math.max(worstCreep, cr[i]);
            if (identical(b, e.ball)) {
              maxBall = math.max(maxBall, s / W);
            } else {
              maxPuck = math.max(maxPuck, s / W);
            }
          }
        }
        turns++;
        longest = math.max(longest, t);
      }
    }
    print('matches: $turns turns, longest turn ${longest.toStringAsFixed(2)} s, frames outside $out, energy pumps $pump, '
        'longest overlap ${worstOverlap.toStringAsFixed(3)} s, longest creep ${worstCreep.toStringAsFixed(3)} s, '
        'max ball ${maxBall.toStringAsFixed(2)} W/s, max puck ${maxPuck.toStringAsFixed(2)} W/s');
    expect(out, 0);
    expect(pump, 0);
    expect(longest, lessThan(8));
    expect(worstOverlap, lessThan(.5));
    expect(worstCreep, lessThan(2));
    expect(maxBall, lessThanOrEqualTo(PHYSICS_CONFIG.ballMaxSpeed + 1e-6));
  });
}
