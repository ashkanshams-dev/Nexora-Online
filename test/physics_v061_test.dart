// v0.6.1 gameplay contract (owner phone feedback 2026-11-14) + the measured sweep printed for the release notes.
//  * shots: powerful, proportional to the pull, smooth decay; full-power disc crosses most of the pitch
//  * ball: slows smoothly and comes to rest within a sensible distance (v0.6 rolled ~8 s)
//  * cushions: little energy lost, tangential speed kept
//  * corners: the ball never sticks in a corner; it leaves on straight mirrored lines
// Set NX_SWEEP=/path/file.md to also write the table.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

MatchCfg _cfg() => MatchCfg(
    field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0, stats: const [DiscStats(7, 7), DiscStats(7, 7)]);

Engine _lab(int keep, {int field = 0}) {
  final c = _cfg()..field = field;
  final e = Engine(c, rand: math.Random(3).nextDouble);
  final discs = e.bodies.where((b) => !identical(b, e.ball)).take(keep).toList();
  e.bodies
    ..clear()
    ..addAll(discs)
    ..add(e.ball);
  for (final b in e.bodies) {
    b.vx = b.vy = 0;
  }
  return e;
}

void _place(Body b, double x, double y, [double vx = 0, double vy = 0]) {
  b.x = b.px = x;
  b.y = b.py = y;
  b.vx = vx;
  b.vy = vy;
}

double _spd(Body b) => math.sqrt(b.vx * b.vx + b.vy * b.vy);

/// run until [b] rests: (path length, time to rest, top speed seen after start)
(double, double) _run(Engine e, Body b, {double maxT = 20}) {
  var t = 0.0, path = 0.0;
  while (t < maxT && (b.vx != 0 || b.vy != 0)) {
    final x0 = b.x, y0 = b.y;
    e.update(1 / 60);
    t += 1 / 60;
    path += math.sqrt((b.x - x0) * (b.x - x0) + (b.y - y0) * (b.y - y0));
  }
  return (path, t);
}

final _out = StringBuffer();
void _log(String s) {
  // ignore: avoid_print
  print(s);
  _out.writeln(s);
}

void main() {
  tearDownAll(() {
    final p = Platform.environment['NX_SWEEP'];
    if (p != null) File(p).writeAsStringSync(_out.toString());
  });

  test('uniform pitch: every pitch art plays on one identical rectangle fitted to the art (v0.7)', () {
    final a = _lab(0, field: 0), b = _lab(0, field: 7);
    for (final (x, y) in [(a.Fl, b.Fl), (a.Fr, b.Fr), (a.Ft, b.Ft), (a.Fb, b.Fb), (a.KY, b.KY), (a.goals[0].x1, b.goals[0].x1), (a.DEPTH, b.DEPTH)]) {
      expect(x, y);
    }
    final aspect = (a.Fb - a.Ft) / (a.Fr - a.Fl), old = (1432 - 101 - 8) / (805 - 30 - 8);
    _log('## Pitch\nplay area ${(a.Fr - a.Fl).toStringAsFixed(0)} x ${(a.Fb - a.Ft).toStringAsFixed(0)} px, aspect ${aspect.toStringAsFixed(3)} '
        '(v0.6 pitch ${old.toStringAsFixed(3)}, +${((aspect / old - 1) * 100).toStringAsFixed(1)}%), goal mouth ${(a.goals[0].x2 - a.goals[0].x1).toStringAsFixed(0)} px '
        '(${((a.goals[0].x2 - a.goals[0].x1) / (a.Fr - a.Fl) * 100).toStringAsFixed(0)}% of width), depth ${a.DEPTH.toStringAsFixed(0)} px\n');
    // v0.7: play area fitted to the pitch art (median drawn width/length of the 40 arts = .583): 825 x 1416
    expect((a.Fr - a.Fl) / (a.Fb - a.Ft), closeTo(.583, .003));
    expect(a.Fr - a.Fl, PHYSICS_CONFIG.wPx);
  });

  test('shots: full / medium / short pulls (power-7 disc, accuracy 10 so it flies straight)', () {
    _log('## Disc shots (power 7, alone, fired up the long axis from the bottom)');
    _log('| pull | launch px/s | path px | path / pitch length | time to rest s |');
    _log('|---|---|---|---|---|');
    final res = <double>[], vs = <double>[];
    for (final (name, pull) in [('full', 1.0), ('medium', .6), ('short', .25)]) {
      final e = _lab(1), d = e.bodies.first;
      e.cfg.stats = const [DiscStats(7, 10), DiscStats(7, 10)];
      _place(e.ball, e.Fr - 60, e.CY);
      _place(d, e.CX - 200, e.Fb - 80);
      e.fire(d, 0, -LMAX * pull, LMAX * pull, true);
      final v0 = _spd(d);
      vs.add(v0);
      final (path, t) = _run(e, d);
      res.add(path);
      _log('| $name (${(pull * 100).round()}%) | ${v0.round()} | ${path.round()} | ${(path / (e.Fb - e.Ft)).toStringAsFixed(2)} | ${t.toStringAsFixed(2)} |');
    }
    expect(res[0], greaterThan(1000), reason: 'a full-power flick crosses most of the pitch');
    // v0.7: launch speed stays proportional to the pull; the glide is no longer (a flicked puck flies on low friction
    // until its first contact, then stops on puckK), so path lengths are only required to be ordered.
    expect(vs[0] / vs[1], greaterThan(1.8), reason: 'proportional: full pull clearly harder than medium');
    expect(vs[1] / vs[2], greaterThan(2.5), reason: 'short pull is a soft touch');
    expect(res[0], greaterThan(res[1]));
    expect(res[1] / res[2], greaterThan(2.5));
    // power stat range and cap
    expect(statMul(10), 1);
    expect(statMul(14), 1, reason: 'no tier exceeds the game max');
    expect(shotCurve(0), closeTo(.06, 1e-12));
    for (var i = 1; i <= 100; i++) {
      expect(shotCurve(i / 100), greaterThan(shotCurve((i - 1) / 100))); // monotonic
    }
    _log('');
  });

  test('ball: hit by a full-power disc, and free rolls; always comes to rest', () {
    _log('## Ball');
    _log('| case | ball start px/s | path px | time to rest s |');
    _log('|---|---|---|---|');
    {
      final e = _lab(1), d = e.bodies.first;
      e.cfg.stats = const [DiscStats(7, 10), DiscStats(7, 10)];
      _place(e.ball, e.CX - 250, e.Fb - 330);
      _place(d, e.CX - 250, e.Fb - 120);
      e.fire(d, 0, -LMAX, LMAX, true);
      var vb = 0.0;
      for (var i = 0; i < 30 && vb == 0; i++) {
        e.update(1 / 60);
        vb = _spd(e.ball);
      }
      final (path, t) = _run(e, e.ball);
      _log('| full-power disc strikes the ball (head-on, up the pitch beside the goal) | ${vb.round()} | ${path.round()} | ${t.toStringAsFixed(2)} |');
      expect(vb, greaterThan(3500), reason: 'hits the ball hard');
      // v0.7: striker kick (ballKickSpeed 5 W/s for a 2 W/s flick), capped at ballMaxSpeed 6.5 W/s
      expect(vb, lessThanOrEqualTo(PHYSICS_CONFIG.ballMaxSpeed * PHYSICS_CONFIG.wPx + 1e-6));
      expect(t, lessThan(4.5));
    }
    for (final v in [3000.0, 1500.0, 600.0]) {
      final e = _lab(0);
      _place(e.ball, e.Fl + 120, e.Fb - 120, v * .6, -v * .8); // diagonal, bounces off the cushions
      final (path, t) = _run(e, e.ball);
      _log('| free roll, diagonal | ${v.round()} | ${path.round()} | ${t.toStringAsFixed(2)} |');
      expect(t, lessThan(4.5), reason: 'the ball must come to rest');
    }
    _log('');
  });

  test('cushions at 15 / 45 / 90 degrees keep most of the speed', () {
    _log('## Cushions (ball 1500 px/s into the left wall; angle between path and wall)');
    _log('| angle | speed kept | normal kept | along-wall kept | angle out |');
    _log('|---|---|---|---|---|');
    for (final deg in [15.0, 45.0, 90.0]) {
      for (final disc in [false, true]) {
        final e = _lab(disc ? 1 : 0), b = disc ? e.bodies.first : e.ball;
        if (disc) _place(e.ball, e.Fr - 60, e.Fb - 60);
        final a = deg * math.pi / 180;
        final vx = -1500 * math.sin(a), vy = 1500 * math.cos(a);
        _place(b, e.Fl + b.r + 12, e.CY - 200, vx, vy);
        // step physics in tiny slices so friction between "before" and "after" is negligible
        var pre = (vx, vy);
        for (var i = 0; i < 600; i++) {
          final before = (b.vx, b.vy);
          e.update(1 / 600);
          if (before.$1 < 0 && b.vx > 0) {
            pre = before;
            break;
          }
        }
        final sp0 = math.sqrt(pre.$1 * pre.$1 + pre.$2 * pre.$2), sp1 = _spd(b);
        final kn = b.vx / -pre.$1, kt = deg == 90 ? double.nan : b.vy / pre.$2;
        final aout = math.atan2(b.vx.abs(), b.vy.abs()) * 180 / math.pi;
        _log('| ${deg.round()}° ${disc ? 'disc' : 'ball'} | ${(sp1 / sp0 * 100).toStringAsFixed(1)}% | ${(kn * 100).toStringAsFixed(1)}% | ${kt.isNaN ? '-' : '${(kt * 100).toStringAsFixed(1)}%'} | ${deg == 90 ? '90°' : '${aout.toStringAsFixed(1)}°'} |');
        if (!disc) {
          // v0.7: e_ball_wall .8 (guess, PHYSICS_CONFIG), tangential .96 kept
          expect(sp1 / sp0, inInclusiveRange(.78, .97));
          if (!kt.isNaN) expect(kt, greaterThan(.93), reason: 'a ball along the wall keeps its tangential speed');
        }
      }
    }
    _log('');
  });

  test('corners: the ball fired into every corner at many angles always leaves it', () {
    _log('## Corner escapes (ball into each of the 4 corners, angles 10..80°, speeds 900 / 1800 / 3500)');
    var cases = 0, stuck = 0, reached = 0, escaped = 0;
    final ex = <String>[];
    for (var corner = 0; corner < 4; corner++) {
      for (var deg = 10; deg <= 80; deg += 10) {
        for (final v in [900.0, 1800.0, 3500.0]) {
          final e = _lab(0), b = e.ball;
          final sx = corner.isEven ? -1.0 : 1.0, sy = corner < 2 ? -1.0 : 1.0; // direction towards the corner
          final cx = sx < 0 ? e.Fl : e.Fr, cy = sy < 0 ? e.Ft : e.Fb;
          final a = deg * math.pi / 180;
          final ux = math.cos(a) * sx, uy = math.sin(a) * sy;
          // start 180 px back along the ray that ends in the corner (minus the radius on both walls)
          final tx = cx - sx * b.r, ty = cy - sy * b.r;
          _place(b, tx - ux * 180, ty - uy * 180, ux * v, uy * v);
          var left = false, t = 0.0, dmin = 1e9;
          for (var i = 0; i < 480 * 8; i++) {
            e.update(1 / 480);
            t += 1 / 480;
            final dc = math.max((b.x - cx).abs(), (b.y - cy).abs());
            dmin = math.min(dmin, dc);
            if (t > .15 && dc > b.r * 4) {
              left = true;
              break;
            }
            if (b.vx == 0 && b.vy == 0) break;
          }
          // a slow ball may legitimately stop before reaching the corner: only count it as stuck when it rests
          // jammed against both walls
          final jam = (b.x - b.r - e.Fl).abs() < 3 || (e.Fr - b.x - b.r).abs() < 3;
          final jamY = (b.y - b.r - e.Ft).abs() < 3 || (e.Fb - b.y - b.r).abs() < 3;
          cases++;
          // v0.7: positions are sampled once per 1/120 s physics step (a 3500 px/s ball moves 29 px = 1.2 r per step),
          // so "reached the pocket" is judged within 2 r (was 1.3 r at 1/240 s)
          if (dmin < b.r * 2) reached++;
          if (dmin < b.r * 2 && left) escaped++;
          if (!left && jam && jamY) {
            stuck++;
            ex.add('corner $corner, $deg°, ${v.round()} px/s');
          }
        }
      }
    }
    // v0.7: the corner nudge is gone - a ball resting in a corner stays at rest (it used to be shoved out at 90 px/s,
    // overriding real velocities near the corner). A ball rolling gently into the corner still comes back off both walls.
    var nudged = 0;
    for (var corner = 0; corner < 4; corner++) {
      final e = _lab(0), b = e.ball;
      final x = corner.isEven ? e.Fl + b.r : e.Fr - b.r, y = corner < 2 ? e.Ft + b.r : e.Fb - b.r;
      _place(b, x, y, 0, 0); // v0.7: parked at rest (was 30 px/s into the corner)
      for (var i = 0; i < 60; i++) {
        e.update(1 / 60);
      }
      if ((b.x - x).abs() > 3 && (b.y - y).abs() > 3) nudged++;
    }
    _log('$cases shots, $reached reached the corner pocket, $escaped of those left it (> 4 radii away), $stuck stuck${ex.isEmpty ? '' : ': ${ex.join(', ')}'}; parked-in-corner ball pushed out in $nudged / 4 corners\n');
    expect(stuck, 0);
    expect(escaped, reached);
    expect(reached, greaterThan(cases * .9));
    expect(nudged, 0);
  });

  test('45° corner run leaves on the mirrored diagonal (straight lines)', () {
    final e = _lab(0), b = e.ball;
    _place(b, e.Fl + 260, e.Ft + 260, -1200, -1200);
    var fx = false, fy = false;
    for (var i = 0; i < 90 && !(fx && fy); i++) {
      e.update(1 / 60);
      fx |= b.vx > 0;
      fy |= b.vy > 0;
    }
    expect(fx && fy, isTrue);
    final ang = math.atan2(b.vy, b.vx) * 180 / math.pi;
    expect(ang, inInclusiveRange(40, 50));
  });
}
