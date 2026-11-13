// Box2D v3 (Forge2D) physics backend for OFFLINE matches.
//
// Decision (see README "Physics"): online lockstep keeps the bit-exact custom engine ([Engine]) as the
// authoritative simulation, because (a) RN and Flutter clients must replay the same shots bit-identically and
// the existing clients run the TS engine, and (b) Box2D's results depend on the native build (compiler,
// FMA contraction, SIMD width) so cross-device bit-identity can't be guaranteed from Dart.
// Offline (vs bot / local 2P) can opt into this backend from Settings → Physics.
//
// Everything above the integrator is shared with [Engine]: phases, turns, goal detection, AI, shot quantisation,
// timers, FX. Only [physicsStep] is replaced: Box2D does integration + contacts (circle discs/ball, static
// segment walls with rounded corners, goal boxes, round posts) at the same fixed 240 Hz step with a fixed
// sub-step count, and the original damping model (exponential decay + low-speed rolling resistance, stop
// thresholds, speed caps) is applied on top so the glide/roll feel matches engine.ts.
import 'dart:math' as math;

import 'package:forge2d/forge2d.dart' as b2;
import 'package:vector_math/vector_math.dart' show Vector2;

import 'engine.dart';

/// world units per Box2D metre (Box2D is tuned for 0.1–10 m objects; a disc is r=49 units → 0.49 m)
const double _S = 100;
bool forge2dReady = false;

Future<void> initForge2d() async {
  if (forge2dReady) return;
  try {
    await b2.initializeForge2D();
    forge2dReady = true;
  } catch (_) {
    forge2dReady = false;
  }
}

class ForgeEngine extends Engine {
  b2.World? _w;
  final Map<Body, b2.Body> _map = {};
  bool _epochBuilt = false;
  int _builtEpoch = -1;

  ForgeEngine(super.cfg);

  b2.World _world() {
    if (_w != null) return _w!;
    final w = b2.World(definition: b2.WorldDef(gravity: Vector2.zero(), enableSleep: false, restitutionThreshold: .3, hitEventThreshold: .6, maximumLinearSpeed: 60));
    final ground = w.createBody(b2.BodyDef());
    final wall = b2.ShapeDef(material: b2.SurfaceMaterial(friction: 0, restitution: 0), enableHitEvents: true, userData: 'wall');
    void seg(double x1, double y1, double x2, double y2) => ground.createShape(b2.Segment(point1: Vector2(x1 / _S, y1 / _S), point2: Vector2(x2 / _S, y2 / _S)), wall);
    final Fr = F;
    // rounded rectangle with goal mouths cut out, corner arcs as 8 segments each
    final g0 = goals[0], g1 = goals[1];
    seg(Fr.l + RC, Fr.t, g0.x1, Fr.t);
    seg(g0.x2, Fr.t, Fr.r - RC, Fr.t);
    seg(Fr.l + RC, Fr.b, g1.x1, Fr.b);
    seg(g1.x2, Fr.b, Fr.r - RC, Fr.b);
    seg(Fr.l, Fr.t + RC, Fr.l, Fr.b - RC);
    seg(Fr.r, Fr.t + RC, Fr.r, Fr.b - RC);
    for (final c in [(Fr.l + RC, Fr.t + RC, math.pi, 1.5 * math.pi), (Fr.r - RC, Fr.t + RC, 1.5 * math.pi, 2 * math.pi), (Fr.r - RC, Fr.b - RC, 0.0, .5 * math.pi), (Fr.l + RC, Fr.b - RC, .5 * math.pi, math.pi)]) {
      const n = 8;
      for (var i = 0; i < n; i++) {
        final a0 = c.$3 + (c.$4 - c.$3) * i / n, a1 = c.$3 + (c.$4 - c.$3) * (i + 1) / n;
        seg(c.$1 + math.cos(a0) * RC, c.$2 + math.sin(a0) * RC, c.$1 + math.cos(a1) * RC, c.$2 + math.sin(a1) * RC);
      }
    }
    // goal boxes (back + sides) and round posts
    for (final g in goals) {
      final back = g.y + g.d * DEPTH;
      seg(g.x1, g.y, g.x1, back);
      seg(g.x2, g.y, g.x2, back);
      seg(g.x1, back, g.x2, back);
      for (final px in [g.x1, g.x2]) {
        ground.createShape(b2.Circle(radius: POST_R / _S, center: Vector2(px / _S, g.y / _S)),
            b2.ShapeDef(material: b2.SurfaceMaterial(friction: 0, restitution: .55), enableHitEvents: true, userData: 'post'));
      }
    }
    return _w = w;
  }

  /// (re)create dynamic bodies after every kick-off reset (Engine.reset rebuilds the Body list)
  void _sync() {
    if (_epochBuilt && _builtEpoch == epoch && _map.length == bodies.length && _map.keys.every(bodies.contains)) return;
    final w = _world();
    for (final b in _map.values) {
      b.destroy();
    }
    _map.clear();
    for (final b in bodies) {
      final isBall = b == ball;
      final body = w.createBody(b2.BodyDef(type: b2.BodyType.dynamic, position: Vector2(b.x / _S, b.y / _S), isBullet: isBall, fixedRotation: true, enableSleep: false));
      // effective masses tuned so a disc→ball hit transfers ~0.9× like the HV-weighted impulse of engine.ts
      final area = math.pi * (b.r / _S) * (b.r / _S);
      body.createShape(
        b2.Circle(radius: b.r / _S),
        b2.ShapeDef(
          density: (isBall ? 1.5 : 7) / area,
          material: b2.SurfaceMaterial(friction: 0, restitution: isBall ? .6 : .62),
          enableHitEvents: true,
          userData: isBall ? 'ball' : 'disc',
        ),
      );
      _map[b] = body;
    }
    _epochBuilt = true;
    _builtEpoch = epoch;
  }

  @override
  void physicsStep(double dt) {
    if (!forge2dReady) {
      super.physicsStep(dt); // native lib unavailable → classic engine
      return;
    }
    _sync();
    final w = _world();
    // shot ramp, re-sync offsets and the original damping model, then hand velocities to Box2D
    for (final b in bodies) {
      if (b.ramp > 0) {
        final k = math.min(1.0, dt / b.ramp);
        b.vx += (b.tvx - b.vx) * k;
        b.vy += (b.tvy - b.vy) * k;
        b.ramp -= dt;
        if (b.ramp <= 0) b.ramp = 0;
      }
      final sp = hyp(b.vx, b.vy);
      if (sp > 0) {
        if (b == ball) {
          var ns = sp * STEP_BK - BF * K * math.min(1.0, sp / (BFV * K)) * dt;
          if (ns < BSTOP * K) {
            b.vx = b.vy = 0;
          } else {
            ns = math.min(ns, BVMAX * K);
            b.vx *= ns / sp;
            b.vy *= ns / sp;
          }
        } else {
          final double fb = b.boost > 0 ? .35 : 1;
          if (b.boost > 0) b.boost -= dt;
          var ns = sp * (fb == 1 ? STEP_PK : STEP_PK_BOOST) - PFL * K * math.min(1.0, sp / (PFV * K)) * fb * dt;
          if (ns < PSTOP * K && b.ramp <= 0) {
            b.vx = b.vy = 0;
          } else {
            ns = math.max(0.0, math.min(ns, 2800 * K));
            b.vx *= ns / sp;
            b.vy *= ns / sp;
          }
        }
      }
      final body = _map[b]!;
      body.setTransform(Vector2(b.x / _S, b.y / _S), const b2.Rot.identity());
      body.linearVelocity = Vector2(b.vx / _S, b.vy / _S);
    }
    w.step(dt, subStepCount: 4);
    for (final b in bodies) {
      final body = _map[b]!;
      final p = body.position, v = body.linearVelocity;
      b.x = p.x * _S;
      b.y = p.y * _S;
      b.vx = v.x * _S;
      b.vy = v.y * _S;
      if (b != ball) {
        b.spin *= 1 - 2.6 * dt;
        b.ang += b.spin * dt;
      }
      b.sq *= 1 - 9 * dt;
    }
    rollBall(dt);
    // impacts → the same engine events (sound, haptics, camera kick, sparks)
    for (final h in w.contactEvents.hit) {
      final a = h.shapeA.userData, c = h.shapeB.userData, v = h.approachSpeed * _S;
      final hasBall = a == 'ball' || c == 'ball';
      if (a == 'wall' || c == 'wall') {
        if (hasBall && v > 200) events.add(EvWall(v / 1800));
      } else if (a == 'post' || c == 'post') {
        if (hasBall) {
          events.add(EvPost(v / 1800));
          if (v > 900 * K) cam = math.max(cam, .25);
        }
      } else if (v > 120 * K) {
        events.add(EvHit(hasBall, v / 1900));
        final pw = math.min(1.0, v / (1700 * K));
        if (hasBall && pw > .2) {
          ball.sq = math.max(ball.sq, pw);
          cam = math.max(cam, pw * .4);
          final pt = h.point;
          burst(pt.x * _S, pt.y * _S, (6 + pw * 10).round(), 260 + pw * 300, const ['#ffffff', '#9fe8ff', '#5cb6ff'], .35, 2);
        }
      }
    }
  }
}
