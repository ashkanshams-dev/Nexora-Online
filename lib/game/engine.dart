// NEXORA physics engine — faithful Dart port of src/game/engine.ts (v7 deterministic engine).
//
// Determinism contract (lockstep netcode depends on it):
//  * physics uses only + - * / and sqrt on IEEE doubles, in the SAME operation order as the TS source;
//  * every Math.round from JS is reproduced with [jsRound] (round-half-up, NOT Dart's half-away-from-zero);
//  * the seeded aim RNG reproduces mulberry32 with 32-bit integer maths ([imul32] / [u32]) that is exact on
//    both the Dart VM (64-bit ints) and dart2js (doubles);
//  * Math.random / cos / sin / atan2 only feed visuals or host-side AI decisions (never replayed state).
// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:math' as math;
import 'dart:typed_data';

import 'data.dart';

const double K = 1.27;
const double PR = 49; // piece radius (world units)
const double BR = 25.5; // ball radius
const double RC = 70; // rounded corner radius
const double LMAX = 210; // max drag length for full power
const double STEP = 1 / 240;
const double POST_R = 8; // goal-post radius
const double HV = 8, PF1 = 430, PF2 = 1.0, PV0 = 520, EPP = .62, PCAP = 190;
const double BK = 1.9, BF = 175, BFV = 140, BVMAX = 1750, BSTOP = 26;
const double PK = 1.55, PFL = 300, PFV = 230, PSTOP = 20;
const double WALL_VOUT = 820, POST_VOUT = 900;

// ---------------------------------------------------------------- JS-exact helpers
/// JavaScript Math.round: floor(x + .5) semantics (half rounds toward +infinity), exact for all doubles.
double jsRound(double x) {
  if (x.isNaN || x.isInfinite) return x;
  final f = x.floorToDouble();
  return (x - f >= 0.5) ? f + 1 : f;
}

int jsRoundI(double x) => jsRound(x).toInt();

/// x >>> 0
int u32(int x) => x & 0xFFFFFFFF;

/// Math.imul(a, b) >>> 0 — split into 16-bit halves so it is exact on web (doubles) and VM.
int imul32(int a, int b) {
  a = u32(a);
  b = u32(b);
  final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
  final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
  return u32((al * bl) + u32(((ah * bl + al * bh) & 0xFFFF) << 16));
}

/// signed 32-bit view of an unsigned 32-bit int (JS `| 0`)
int i32(int x) {
  x = u32(x);
  return x >= 0x80000000 ? x - 0x100000000 : x;
}

/// deterministic PRNG (mulberry32), bit-identical to the TS rng32
double Function() rng32(int seed) {
  var a = u32(seed);
  return () {
    a = u32(a + 0x6D2B79F5);
    var t = a;
    t = imul32(t ^ (t >> 15), t | 1);
    t = u32(t ^ u32(t + imul32(t ^ (t >> 7), t | 61)));
    return u32(t ^ (t >> 14)) / 4294967296.0;
  };
}

double hyp(double x, double y, [double z = 0]) => math.sqrt(x * x + y * y + z * z);
const double STEP_BK = 0.9921145876, STEP_PK = 0.9935624769, STEP_PK_BOOST = 0.9977421362;
double stepDecay(double k) => k == BK ? STEP_BK : k == PK ? STEP_PK : 1 - k * STEP + k * k * STEP * STEP / 2;
double sinS(double a) {
  final a2 = a * a;
  return a * (1 - a2 / 6 * (1 - a2 / 20 * (1 - a2 / 42)));
}

double cosS(double a) {
  final a2 = a * a;
  return 1 - a2 / 2 * (1 - a2 / 12 * (1 - a2 / 30));
}

double pow08(double p) {
  if (p <= 0) return 0;
  final a = math.sqrt(p), b = math.sqrt(a), c = math.sqrt(math.sqrt(b));
  return a * b * c;
}

const int PACK = 7; // ints per body in a packed state
double qz(double v) => jsRound(v * 64) / 64; // 1/64 world-unit grid
double clampD(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double powerMul(double p) => .75 + (math.min(10.0, math.max(1.0, p)) - 1) / 9 * .5;
double aimDevDeg(double a) => (10 - math.min(10.0, math.max(1.0, a))) / 9 * 4;
double aimPreview(double a) => .45 + (math.min(10.0, math.max(1.0, a)) - 1) / 9 * .75;

// ---------------------------------------------------------------- types
class Pt {
  double x, y, a;
  Pt(this.x, this.y, [this.a = 0]);
}

class Goal {
  final int team;
  final double y, x1, x2;
  final int d;
  const Goal(this.team, this.y, this.x1, this.x2, this.d);
}

class Body {
  final int id;
  final int team; // 0 | 1 | 2 (ball)
  double x, y, px, py, vx = 0, vy = 0;
  final double r, im;
  double spin = 0, ang = 0, sq = 0, tvx = 0, tvy = 0, ramp = 0, boost = 0, vox = 0, voy = 0;
  final Float64List R = Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]);
  Goal? gout;
  final List<Pt> tr = [];
  Body(this.x, this.y, this.team, this.r, double m, this.id) : px = x, py = y, im = 1 / m;
}

class Particle {
  double x, y, vx, vy, l;
  final double m, r, g;
  final String c;
  final int k;
  Particle(this.x, this.y, this.vx, this.vy, this.l, this.m, this.r, this.c, this.k, this.g);
}

enum Phase { aim, move, goal, over }

sealed class EngineEvent {
  const EngineEvent();
}

class EvHit extends EngineEvent {
  final bool ball;
  final double power;
  const EvHit(this.ball, this.power);
}

class EvWall extends EngineEvent {
  final double power;
  const EvWall(this.power);
}

class EvPost extends EngineEvent {
  final double power;
  const EvPost(this.power);
}

class EvGoal extends EngineEvent {
  final int team;
  final bool nogoal;
  const EvGoal(this.team, this.nogoal);
}

class EvTurn extends EngineEvent {
  final int team;
  const EvTurn(this.team);
}

class EvShot extends EngineEvent {
  final int team;
  const EvShot(this.team);
}

class EvEnd extends EngineEvent {
  final List<int> score;
  const EvEnd(this.score);
}

class EvClock extends EngineEvent {
  const EvClock();
}

class DiscStats {
  final double power, accuracy;
  const DiscStats(this.power, this.accuracy);
}

class MatchCfg {
  int field, ball;
  List<int> forms;
  bool ai;
  int aiLvl; // 0..2
  int limit;
  double matchTime, turnTime;
  List<bool> vip;
  int first;
  List<DiscStats>? stats;
  MatchCfg({
    required this.field,
    required this.ball,
    required this.forms,
    required this.ai,
    required this.aiLvl,
    required this.limit,
    required this.matchTime,
    required this.turnTime,
    required this.vip,
    required this.first,
    this.stats,
  });
}

class Drag {
  final Body b;
  final double sx, sy;
  double cx, cy;
  final bool ai;
  Drag(this.b, this.sx, this.sy, this.cx, this.cy, {this.ai = false});
}

class AimInfo {
  final Body b;
  final double p, ux, uy;
  const AimInfo(this.b, this.p, this.ux, this.uy);
}

class AiPlan {
  final Body b;
  final double dx, dy, l;
  double t;
  AiPlan(this.b, this.dx, this.dy, this.l, this.t);
}

class LocalGoal {
  final int team, tick, shot;
  final bool nogoal;
  const LocalGoal(this.team, this.nogoal, this.tick, this.shot);
}

typedef FireHook = void Function(Body b, double dx, double dy, bool human, int seq, List<int> pre);

final _rnd = math.Random();
double _random() => _rnd.nextDouble();

double eBall(double vn) => math.min(.64 - .24 * clampD((vn - 270 * K) / (730 * K), 0, 1), WALL_VOUT * K / math.max(1, vn));
double eDisc(double vn) => math.min(.72, WALL_VOUT * 1.4 * K / math.max(1, vn));

final Float64List _rotTmp = Float64List(9);
void _rotate(Float64List R, double wx, double wy, double wz, double dt) {
  final w = hyp(wx, wy, wz), th = w * dt;
  if (th < 1e-7) return;
  final ax = wx / w, ay = wy / w, az = wz / w, c = math.cos(th), s = math.sin(th), t = 1 - c;
  final m0 = t * ax * ax + c, m1 = t * ax * ay - s * az, m2 = t * ax * az + s * ay;
  final m3 = t * ax * ay + s * az, m4 = t * ay * ay + c, m5 = t * ay * az - s * ax;
  final m6 = t * ax * az - s * ay, m7 = t * ay * az + s * ax, m8 = t * az * az + c;
  final r = _rotTmp;
  for (var i = 0; i < 9; i++) {
    r[i] = R[i];
  }
  R[0] = m0 * r[0] + m1 * r[3] + m2 * r[6];
  R[1] = m0 * r[1] + m1 * r[4] + m2 * r[7];
  R[2] = m0 * r[2] + m1 * r[5] + m2 * r[8];
  R[3] = m3 * r[0] + m4 * r[3] + m5 * r[6];
  R[4] = m3 * r[1] + m4 * r[4] + m5 * r[7];
  R[5] = m3 * r[2] + m4 * r[5] + m5 * r[8];
  R[6] = m6 * r[0] + m7 * r[3] + m8 * r[6];
  R[7] = m6 * r[1] + m7 * r[4] + m8 * r[7];
  R[8] = m6 * r[2] + m7 * r[5] + m8 * r[8];
  var l = hyp(R[0], R[1], R[2]);
  R[0] /= l;
  R[1] /= l;
  R[2] /= l;
  final d = R[0] * R[3] + R[1] * R[4] + R[2] * R[5];
  R[3] -= d * R[0];
  R[4] -= d * R[1];
  R[5] -= d * R[2];
  l = hyp(R[3], R[4], R[5]);
  R[3] /= l;
  R[4] /= l;
  R[5] /= l;
  R[6] = R[1] * R[5] - R[2] * R[4];
  R[7] = R[2] * R[3] - R[0] * R[5];
  R[8] = R[0] * R[4] - R[1] * R[3];
}

class FRect {
  final double l, r, t, b;
  const FRect(this.l, this.r, this.t, this.b);
}

class GoalGeo {
  final double w, h, x;
  const GoalGeo(this.w, this.h, this.x);
}

class Engine {
  late Field f;
  late FRect F;
  double CX = 0, CY = 0, KY = 0;
  late List<Goal> goals;
  late GoalGeo GG;
  double DEPTH = 120;
  List<Body> bodies = [];
  late Body ball;
  final List<Particle> parts = [];
  final List<Pt> trail = [];
  final List<int> score = [0, 0];
  int turn = 0;
  Phase phase = Phase.aim;
  int shots = 0;
  double idle = 0, pause = 0;
  int kick = 0;
  double acc = 0, slow = 0, flash = 0, cam = 0;
  final List<double> shake = [0, 0], ripple = [0, 0], rippleX = [0, 0];
  double mleft = 0, tleft = 0;
  bool sudden = false;
  double aiT = 0;
  AiPlan? aiPlan;
  Drag? drag;
  final List<EngineEvent> events = [];
  final MatchCfg cfg;
  double time = 0;
  int lastWho = 0;
  List<bool> aiTeams = [false, false];
  bool follower = false;
  int tick = 0, shotNo = 0, seed = 0x5eed;
  int epoch = 0, epochKind = 0;
  FireHook? onFire;
  final Map<int, List<int>> keys = {};
  int keyEvery = 0;
  late List<List<double>> _corners;
  double lastPower = 0;
  LocalGoal? localGoal;

  Engine(this.cfg) {
    f = (cfg.field >= 0 && cfg.field < FIELDS.length) ? FIELDS[cfg.field] : FIELDS[0];
    F = FRect(f.L + 4.0, f.R - 4.0, f.T + 4.0, f.B - 4.0);
    CX = (F.l + F.r) / 2;
    CY = (F.t + F.b) / 2;
    KY = f.cs.toDouble();
    final gi = GS[f.gs]!, gw = 2 * f.g / (gi[3] - gi[2]);
    GG = GoalGeo(gw, gw * gi[1] / gi[0] * 1.28, CX - f.g - gi[2] * gw);
    DEPTH = math.max(120, jsRound(GG.h * .98));
    goals = [Goal(0, F.t, CX - f.g, CX + f.g, -1), Goal(1, F.b, CX - f.g, CX + f.g, 1)];
    mleft = cfg.matchTime;
    tleft = cfg.turnTime;
    _corners = [
      [F.l + RC, F.t + RC, 1, 1],
      [F.r - RC, F.t + RC, -1, 1],
      [F.l + RC, F.b - RC, 1, -1],
      [F.r - RC, F.b - RC, -1, -1],
    ];
    reset(cfg.first);
  }

  void reset(int kickTeam) {
    final Fw = F.r - F.l, Fh = F.b - F.t;
    bodies = [];
    trail.clear();
    parts.clear();
    slow = 0;
    cam = 0;
    for (var cm = 0; cm < 2; cm++) {
      final sl = slots(cfg.forms[cm]);
      for (var i = 0; i < sl.length; i++) {
        final (nx, ny) = sl[i];
        final x = F.l + PR + 10 + nx * (Fw - 2 * (PR + 10)), y = cm == 1 ? F.t + ny * Fh : F.b - ny * Fh;
        bodies.add(Body(x, y, cm, PR, 5, cm * 20 + i));
      }
    }
    ball = Body(CX, KY, 2, BR, 1.5, 99);
    bodies.add(ball);
    for (final b in bodies) {
      b.x = b.px = qz(b.x);
      b.y = b.py = qz(b.y);
    }
    tick = 0;
    epoch++;
    epochKind = 0;
    keys.clear();
    localGoal = null;
    turn = kickTeam;
    phase = Phase.aim;
    drag = null;
    pause = 0;
    idle = 0;
    shots = 0;
    tleft = cfg.turnTime;
    aiT = 0;
    aiPlan = null;
    events.add(EvTurn(turn));
  }

  bool isAiTurn() => (cfg.ai && turn == 1) || aiTeams[turn];
  bool canControl() => phase == Phase.aim && !isAiTurn();

  // ---------------------------------------------------------------- input
  bool pick(double x, double y) {
    if (!canControl()) return false;
    Body? fb;
    var bd = 1e9;
    for (final b in bodies) {
      if (b.team == turn && b != ball) {
        final d = hyp(x - b.x, y - b.y);
        if (d < b.r + 34 && d < bd) {
          fb = b;
          bd = d;
        }
      }
    }
    if (fb == null) return false;
    drag = Drag(fb, fb.x, fb.y, x, y);
    return true;
  }

  void move(double x, double y) {
    final d = drag;
    if (d != null && !d.ai) {
      d.cx = x;
      d.cy = y;
    }
  }

  void release() {
    final d = drag;
    if (d == null || d.ai) return;
    drag = null;
    final dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy);
    if (l > 18 && phase == Phase.aim) fire(d.b, dx, dy, l, human: true);
  }

  void cancel() {
    if (drag != null && !drag!.ai) drag = null;
  }

  AimInfo? aimInfo() {
    final d = drag;
    if (d == null) return null;
    final dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy);
    if (l < 18) return AimInfo(d.b, 0, 0, 0);
    return AimInfo(d.b, math.min(l, LMAX) / LMAX, dx / l, dy / l);
  }

  DiscStats statsOf(int team) => cfg.stats?[team] ?? const DiscStats(5, 5);

  void fire(Body b, double dx, double dy, double l, {bool human = false, int? seq}) {
    dx = jsRound(dx * 16) / 16;
    dy = jsRound(dy * 16) / 16;
    l = hyp(dx, dy);
    if (l < 1e-6) return;
    final p = math.min(l, LMAX) / LMAX, team = b.team, sq = seq ?? shotNo;
    lastPower = p;
    var v = (260 + 1085 * pow08(p)) * K * 1.32;
    if (cfg.stats != null) {
      v *= powerMul(statsOf(team).power);
    } else if (cfg.vip[team]) {
      v *= 1.16;
    }
    var ux = dx / l, uy = dy / l;
    if (human && cfg.stats != null) {
      final dev = aimDevDeg(statsOf(team).accuracy) * math.pi / 180;
      if (dev > 0) {
        final rnd = rng32(u32(seed ^ imul32(sq + 1, 0x9E3779B1)));
        final a = (rnd() + rnd() - 1) * dev, c = cosS(a), s = sinS(a), nx = ux * c - uy * s, ny = ux * s + uy * c;
        ux = nx;
        uy = ny;
      }
    }
    final vx = ux * v, vy = uy * v;
    b.tvx = vx * 1.02;
    b.tvy = vy * 1.02;
    b.ramp = .06;
    b.vx = vx * .5;
    b.vy = vy * .5;
    b.boost = .22;
    for (final o in bodies) {
      o.x = o.px = qz(o.x);
      o.y = o.py = qz(o.y);
    }
    onFire?.call(b, dx, dy, human, sq, packState());
    phase = Phase.move;
    idle = 0;
    shots++;
    shotNo++;
    tick = 0;
    epoch++;
    epochKind = 1;
    keys.clear();
    localGoal = null;
    drag = null;
    cam = math.max(cam, .18);
    lastWho = b.team;
    events.add(EvShot(b.team));
  }

  // ---------------------------------------------------------------- simulation
  void _walls(Body b) {
    final Fr = F;
    if (b != ball && b.gout != null) {
      final g = b.gout!, dq = g.d * (b.y - g.y);
      if (dq > -b.r * 1.05) {
        b.vy = -g.d * 270 * K;
        b.vx *= .6;
      } else {
        b.vy = 0;
        b.vx *= .2;
        b.gout = null;
      }
    }
    final bl = b == ball, r = b.r, vs = hyp(b.vx, b.vy);
    final double Function(double) eN = bl ? eBall : eDisc;
    if (b.x - r < Fr.l) {
      b.x = Fr.l + r;
      if (b.vx < 0) {
        if (bl && vs > 200) events.add(EvWall(vs / 1800));
        b.vx *= -eN(-b.vx);
        b.spin += b.vy / r * .05;
      }
    }
    if (b.x + r > Fr.r) {
      b.x = Fr.r - r;
      if (b.vx > 0) {
        if (bl && vs > 200) events.add(EvWall(vs / 1800));
        b.vx *= -eN(b.vx);
        b.spin -= b.vy / r * .05;
      }
    }
    for (final g in goals) {
      final dp = g.d * (b.y - g.y);
      if (dp <= -r) continue;
      final lo = g.x1 + (bl ? 0 : r), hi = g.x2 - (bl ? 0 : r);
      final inside = bl ? (b.x > g.x1 && b.x < g.x2) : (dp > 0 || (b.x >= lo && b.x <= hi));
      if (inside) {
        final gl = phase == Phase.goal && bl, eb = gl ? .2 : eN(b.vy.abs()), back = g.y + g.d * DEPTH;
        if (!bl && dp > r * .3 && vs < 150 * K && b.gout == null) b.gout = g;
        if (dp + r > DEPTH) {
          b.y = back - g.d * r;
          b.vy = -g.d * b.vy.abs() * eb;
          if (gl) b.vx *= .6;
        }
        if (dp > (bl ? r * .6 : 0)) {
          final ee = gl ? .3 : eN(b.vx.abs());
          if (b.x < g.x1 + r) {
            b.x = g.x1 + r;
            if (b.vx < 0) b.vx *= -ee;
          }
          if (b.x > g.x2 - r) {
            b.x = g.x2 - r;
            if (b.vx > 0) b.vx *= -ee;
          }
        }
      } else {
        if (bl && vs > 200 && g.d * b.vy > 0) events.add(EvWall(vs / 1800));
        b.y = g.y - g.d * r;
        if (g.d * b.vy > 0) b.vy = -g.d * b.vy.abs() * eN(b.vy.abs());
        b.spin += g.d * b.vx / r * .05;
      }
    }
    for (var ci = 0; ci < 4; ci++) {
      final cr = _corners[ci], cx = cr[0], cy = cr[1], sx = cr[2], sy = cr[3];
      if ((b.x - cx) * sx < 0 && (b.y - cy) * sy < 0) {
        final dx = b.x - cx, dy = b.y - cy, d = hyp(dx, dy), lim = RC - r;
        if (d > lim && d > 0) {
          final nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
          b.x = cx + nx * lim;
          b.y = cy + ny * lim;
          if (vn > 0) {
            final ec = eN(vn);
            b.vx -= (1 + ec) * vn * nx;
            b.vy -= (1 + ec) * vn * ny;
          }
        }
      }
    }
  }

  void _post(Body b, double px, double py) {
    final dx = b.x - px, dy = b.y - py, d = hyp(dx, dy), m = b.r + POST_R;
    if (d >= m || d == 0) return;
    final nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
    b.x = px + nx * m;
    b.y = py + ny * m;
    if (vn < 0) {
      final kp = 1 + math.min(.62 - .14 * math.min(1, -vn / (2000 * K)), POST_VOUT * K / math.max(1, -vn));
      b.vx -= kp * vn * nx;
      b.vy -= kp * vn * ny;
      if (b == ball) events.add(EvPost(-vn / 1800));
      if (b == ball && -vn > 900 * K) cam = math.max(cam, .25);
    }
  }

  void _hit(Body a, Body b) {
    var dx = b.x - a.x, dy = b.y - a.y, d = hyp(dx, dy);
    final m = a.r + b.r;
    if (d >= m) return;
    if (d < 1e-4) {
      dx = 1;
      dy = 0;
      d = 1;
    }
    final bl = ball, nx = dx / d, ny = dy / d, sm = a.im + b.im, isB = a == bl || b == bl;
    double ka = isB && a != bl ? 1 / HV : 1, kb = isB && b != bl ? 1 / HV : 1;
    if (!isB) {
      final sa = hyp(a.vx, a.vy), sb = hyp(b.vx, b.vy);
      if (sa > sb) {
        kb = .85;
      } else {
        ka = .85;
      }
    }
    var wa = a.im / sm * ka, wb = b.im / sm * kb;
    if (isB) {
      if (a == bl) {
        wa = 1 - wb;
      } else {
        wb = 1 - wa;
      }
    }
    final pen = math.max(m - d - .3, 0) * .9;
    a.x -= nx * pen * wa;
    a.y -= ny * pen * wa;
    b.x += nx * pen * wb;
    b.y += ny * pen * wb;
    a.vox = clampD(a.vox + nx * pen * wa, -9, 9);
    a.voy = clampD(a.voy + ny * pen * wa, -9, 9);
    b.vox = clampD(b.vox - nx * pen * wb, -9, 9);
    b.voy = clampD(b.voy - ny * pen * wb, -9, 9);
    final vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
    if (vn >= 0) return;
    final e = vn < -40 * K ? (isB ? .68 - .12 * clampD((-vn - 500 * K) / (1200 * K), 0, 1) : EPP) : 0.0;
    final j = -(1 + e) * vn / sm;
    final Body? pa = isB ? (a == bl ? b : a) : null;
    final pre = pa != null ? hyp(pa.vx, pa.vy) : 0.0;
    a.vx -= j * nx * a.im * ka;
    a.vy -= j * ny * a.im * ka;
    b.vx += j * nx * b.im * kb;
    b.vy += j * ny * b.im * kb;
    if (pa != null && pre < 260 * K) {
      final ps = hyp(pa.vx, pa.vy), cp = PCAP * K;
      if (ps > cp) {
        pa.vx *= cp / ps;
        pa.vy *= cp / ps;
      }
    }
    if (vn < -120 * K) {
      events.add(EvHit(isB, -vn / 1900));
      if (!isB && vn < -420 * K) {
        final q = math.min(1.0, -vn / (1500 * K));
        a.sq = math.max(a.sq, q);
        b.sq = math.max(b.sq, q);
      }
    }
    if (isB) {
      bl.spin += (bl == b ? 1 : -1) * (-ny * (b.vx - a.vx) + nx * (b.vy - a.vy)) / bl.r * .3;
      bl.spin = clampD(bl.spin, -34, 34);
      final pw = math.min(1.0, -vn / (1700 * K));
      if (pw > .2) {
        final o = bl == b ? a : b;
        bl.sq = math.max(bl.sq, pw);
        o.sq = math.max(o.sq, pw * .7);
        cam = math.max(cam, pw * .4);
        final cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2;
        burst(cx, cy, jsRoundI(6 + pw * 10), 260 + pw * 300, const ['#ffffff', '#9fe8ff', '#5cb6ff'], .35, 2);
      }
    }
  }

  void _sim(double dt) {
    final bl = ball;
    tick++;
    for (final b in bodies) {
      if (b.ramp > 0) {
        final k = math.min(1.0, dt / b.ramp);
        b.vx += (b.tvx - b.vx) * k;
        b.vy += (b.tvy - b.vy) * k;
        b.ramp -= dt;
        if (b.ramp <= 0) b.ramp = 0;
      }
      if (b.vox != 0 || b.voy != 0) {
        final q = 1 - math.min(1.0, dt * 15);
        b.vox *= q;
        b.voy *= q;
        if (b.vox.abs() < .04) b.vox = 0;
        if (b.voy.abs() < .04) b.voy = 0;
      }
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      final sp = hyp(b.vx, b.vy), isBall = b == bl;
      if (sp > 0) {
        if (isBall) {
          var ns = sp * stepDecay(BK) - BF * K * math.min(1.0, sp / (BFV * K)) * dt;
          if (ns < BSTOP * K) {
            b.vx = b.vy = 0;
            b.vox = b.voy = 0;
          } else {
            ns = math.min(ns, BVMAX * K);
            final k = ns / sp;
            b.vx *= k;
            b.vy *= k;
          }
        } else {
          final double fb = b.boost > 0 ? .35 : 1;
          if (b.boost > 0) b.boost -= dt;
          var ns = sp * (fb == 1 ? stepDecay(PK) : STEP_PK_BOOST) - PFL * K * math.min(1.0, sp / (PFV * K)) * fb * dt;
          if (ns < PSTOP * K && b.ramp <= 0) {
            b.vx = b.vy = 0;
          } else {
            ns = math.max(0.0, math.min(ns, 2800 * K));
            final k = ns / sp;
            b.vx *= k;
            b.vy *= k;
          }
        }
      }
      if (isBall) {
        final sp2 = hyp(b.vx, b.vy);
        b.spin *= 1 - (sp2 > 0 ? 1.05 : 3.2) * dt;
        if (b.spin.abs() < .02) b.spin = 0;
        final roll = .95 / b.r;
        if (sp2 > 0 || b.spin != 0) _rotate(b.R, -b.vy * roll, b.vx * roll, b.spin * .55, dt);
        b.ang += b.spin * dt;
      } else {
        b.spin *= 1 - 2.6 * dt;
        b.ang += b.spin * dt;
      }
      b.sq *= 1 - 9 * dt;
      _walls(b);
    }
    final B = bodies;
    for (var it = 0; it < 2; it++) {
      for (var a = 0; a < B.length; a++) {
        for (var c = a + 1; c < B.length; c++) {
          _hit(B[a], B[c]);
        }
      }
    }
    for (final g in goals) {
      for (final b in B) {
        _post(b, g.x1, g.y);
        _post(b, g.x2, g.y);
      }
    }
    for (final b in B) {
      _walls(b);
    }
    if (phase == Phase.move) {
      for (final g in goals) {
        if (bl.x > g.x1 && bl.x < g.x2 && (g.d < 0 ? bl.y < g.y - bl.r * .8 : bl.y > g.y + bl.r * .8)) _scored(g.team);
      }
    }
    if (keyEvery != 0 && tick % keyEvery == 0) {
      keys[tick] = packState();
      if (keys.length > 64) keys.remove(keys.keys.first);
    }
  }

  void _scored(int t) {
    final nogoal = shots <= 1;
    if (follower) {
      phase = Phase.goal;
      localGoal = LocalGoal(t, nogoal, tick, shotNo);
      if (!nogoal) {
        slow = 1.1;
        fxGoal(t);
      }
      return;
    }
    events.add(EvGoal(t, nogoal));
    if (nogoal) {
      phase = Phase.goal;
      pause = 1.4;
      kick = turn;
      return;
    }
    ripple[t] = 1;
    rippleX[t] = ball.x;
    score[t]++;
    pause = 2.0;
    flash = 1;
    shake[t] = .6;
    phase = Phase.goal;
    kick = 1 - t;
    slow = 1.1;
    cam = 1.4;
    final g = goals[t];
    const c = ['#ffd23a', '#ffffff', '#3bd0ff', '#ff4a7a', '#7bff5a'];
    burst(ball.x, g.y, 80, 760, c, 1.4, 1);
    burst(ball.x, g.y, 50, 520, c, 1.8, 3);
  }

  /// visual particles only (Math.random is fine: never part of the replayed state)
  void burst(double x, double y, int n, double sp, List<String> cols, double life, [int k = 0]) {
    if (parts.length > 420) return;
    for (var i = 0; i < n; i++) {
      final a = _random() * math.pi * 2, v = sp * (.3 + _random());
      parts.add(Particle(x, y, math.cos(a) * v, math.sin(a) * v, life * (.6 + _random() * .6), life, 2 + _random() * 3.5,
          cols[i % cols.length], k, k == 3 ? 600 : 0));
    }
  }

  void _finishTurn() {
    for (final b in bodies) {
      b.vx = b.vy = 0;
      b.x = b.px = qz(b.x);
      b.y = b.py = qz(b.y);
    }
    turn = 1 - turn;
    phase = Phase.aim;
    tleft = cfg.turnTime;
    aiT = 0;
    aiPlan = null;
    events.add(EvTurn(turn));
  }

  void _end() {
    phase = Phase.over;
    events.add(EvEnd([score[0], score[1]]));
  }

  // ---------------------------------------------------------------- follower (online client)
  void stepFollower(double rdt, [int maxTick = 1 << 52]) {
    final dt = math.min(rdt, .1);
    time += dt;
    double ts = 1;
    if (slow > 0) {
      slow -= dt;
      final q = 1 - math.max(0.0, slow) / 1.1;
      ts = .3 + .7 * q * q;
    }
    if (phase == Phase.move || phase == Phase.goal) {
      acc += dt * ts;
      var n = 0;
      while (acc >= STEP && n < 32 && tick < maxTick) {
        n++;
        for (final b in bodies) {
          b.px = b.x;
          b.py = b.y;
        }
        _sim(STEP);
        acc -= STEP;
      }
      if (acc > STEP * 4) acc = STEP * 4;
    } else {
      acc = 0;
      final q = 1 - math.min(1.0, dt * 12);
      for (final b in bodies) {
        if (b.vox != 0 || b.voy != 0) {
          b.vox *= q;
          b.voy *= q;
          if (b.vox.abs() < .05) b.vox = 0;
          if (b.voy.abs() < .05) b.voy = 0;
        }
      }
    }
    tickFx(dt);
  }

  bool atRest() {
    for (final b in bodies) {
      if (b.vx != 0 || b.vy != 0 || b.ramp > 0) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------- compact state
  static const double _tau = 6.283185307179586;
  List<int> packState() {
    final o = <int>[];
    for (final b in bodies) {
      // JS % keeps the dividend's sign -> Dart remainder()
      o
        ..add(jsRoundI(b.x * 64))
        ..add(jsRoundI(b.y * 64))
        ..add(jsRoundI(b.vx * 16))
        ..add(jsRoundI(b.vy * 16))
        ..add(jsRoundI(((b.ang.remainder(_tau) + _tau).remainder(_tau)) * 1000))
        ..add(jsRoundI(b.boost * 4800))
        ..add(jsRoundI(b.spin * 100));
    }
    return o;
  }

  bool unpackState(List<num>? a, {bool keepVel = false}) {
    final n = bodies.length;
    const S = PACK;
    if (a == null || a.length < n * S) return false;
    for (var i = 0; i < n; i++) {
      final b = bodies[i];
      b.x = b.px = a[i * S] / 64;
      b.y = b.py = a[i * S + 1] / 64;
      if (!keepVel) {
        b.vx = a[i * S + 2] / 16;
        b.vy = a[i * S + 3] / 16;
        b.ramp = 0;
        b.boost = a[i * S + 5] / 4800;
        b.tvx = b.tvy = 0;
        b.spin = a[i * S + 6] / 100;
      }
      b.ang = a[i * S + 4] / 1000;
      b.vox = b.voy = 0;
      b.gout = null;
    }
    return true;
  }

  double stateError(List<num>? a) {
    var m = 0.0;
    final n = bodies.length;
    const S = PACK;
    if (a == null || a.length < n * S) return 1e9;
    for (var i = 0; i < n; i++) {
      final b = bodies[i], e = (b.x - a[i * S] / 64).abs() + (b.y - a[i * S + 1] / 64).abs();
      if (e > m) m = e;
    }
    return m;
  }

  static double packError(List<num> a, List<num> b) {
    var m = 0.0;
    for (var i = 0; i + 1 < a.length && i + 1 < b.length; i += PACK) {
      final e = (a[i] - b[i]).abs() / 64 + (a[i + 1] - b[i + 1]).abs() / 64;
      if (e > m) m = e;
    }
    return m;
  }

  void fastForward(int toTick) {
    var n = 0;
    while (tick < toTick && n++ < 2400) {
      for (final b in bodies) {
        b.px = b.x;
        b.py = b.y;
      }
      _sim(STEP);
    }
    events.clear();
  }

  // ---------------------------------------------------------------- main step
  void update(double rdt) {
    final dt = math.min(rdt, .1);
    time += dt;
    if (phase == Phase.over) {
      tickFx(dt);
      return;
    }
    if (cfg.matchTime > 0 && !sudden && mleft > 0) mleft = math.max(0, mleft - dt);
    double ts = 1;
    if (slow > 0) {
      slow -= dt;
      final q = 1 - math.max(0.0, slow) / 1.1;
      ts = .3 + .7 * q * q;
    }
    acc += dt * ts;
    var n = 0;
    while (acc >= STEP && n < 32) {
      n++;
      for (final b in bodies) {
        b.px = b.x;
        b.py = b.y;
      }
      _sim(STEP);
      acc -= STEP;
    }
    if (acc > STEP * 4) acc = STEP * 4;
    if (phase == Phase.move) {
      idle = bodies.any((b) => b.vx != 0 || b.vy != 0 || b.ramp > 0) ? 0 : idle + dt;
      if (idle > .15) _finishTurn();
    } else if (phase == Phase.aim) {
      if (cfg.matchTime > 0 && !sudden && mleft <= 0) {
        if (score[0] != score[1]) {
          _end();
          return;
        }
        sudden = true;
        events.add(const EvClock());
      }
      if (cfg.turnTime > 0) {
        tleft -= dt;
        if (tleft <= 0) {
          drag = null;
          aiPlan = null;
          _finishTurn();
        }
      }
      if (isAiTurn()) _aiTick(dt);
    } else if (phase == Phase.goal) {
      pause -= dt;
      if (pause <= 0) {
        if (cfg.matchTime > 0) {
          if (sudden || (mleft <= 0 && score[0] != score[1])) {
            _end();
          } else {
            if (mleft <= 0) sudden = true;
            reset(kick);
          }
        } else if (score[0] >= cfg.limit || score[1] >= cfg.limit) {
          _end();
        } else {
          reset(kick);
        }
      }
    }
    tickFx(dt);
  }

  void fxGoal(int t) {
    ripple[t] = 1;
    rippleX[t] = ball.x;
    flash = 1;
    shake[t] = .6;
    cam = 1.4;
    final g = goals[t];
    const c = ['#ffd23a', '#ffffff', '#3bd0ff', '#ff4a7a', '#7bff5a'];
    burst(ball.x, g.y, 80, 760, c, 1.4, 1);
    burst(ball.x, g.y, 50, 520, c, 1.8, 3);
  }

  void tickFx(double dt) {
    flash = math.max(0, flash - dt * 2);
    cam = math.max(0, cam - dt * 3.2);
    shake[0] = math.max(0, shake[0] - dt);
    ripple[0] = math.max(0, ripple[0] - dt * .8);
    ripple[1] = math.max(0, ripple[1] - dt * .8);
    shake[1] = math.max(0, shake[1] - dt);
    final sp = hyp(ball.vx, ball.vy);
    if (sp > 45) trail.add(Pt(ball.x, ball.y, math.min(1, sp / 900)));
    trail.removeWhere((p) => (p.a -= dt * 1.9) <= 0);
    if (trail.length > 64) trail.removeRange(0, trail.length - 64);
    for (final b in bodies) {
      if (b == ball) continue;
      final s = hyp(b.vx, b.vy);
      if (s > 140 * K) {
        b.tr.add(Pt(b.x, b.y));
      } else if (b.tr.isNotEmpty) {
        b.tr.removeAt(0);
      }
      if (b.tr.length > 12) b.tr.removeAt(0);
    }
    parts.removeWhere((p) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= .965;
      p.vy = p.vy * .965 + p.g * dt;
      p.l -= dt;
      return p.l <= 0;
    });
  }

  double alpha() => clampD(acc / STEP, 0, 1);

  /// one raw physics sub-step (parity tests / tools)
  void simStep() {
    for (final b in bodies) {
      b.px = b.x;
      b.py = b.y;
    }
    _sim(STEP);
  }

  // ---------------------------------------------------------------- AI (host-side only)
  void _aiTick(double dt) {
    if (aiPlan == null) {
      aiT += dt;
      if (aiT < .7 + _random() * .5) return;
      final p = _aiDecide();
      if (p == null) return;
      aiPlan = p;
      drag = Drag(p.b, p.b.x, p.b.y, p.b.x, p.b.y, ai: true);
      return;
    }
    final pl = aiPlan!;
    pl.t += dt;
    final k = math.min(1.0, pl.t / .75), e = k * k * (3 - 2 * k);
    final d = drag;
    if (d != null) {
      d.cx = pl.b.x - pl.dx * pl.l * e;
      d.cy = pl.b.y - pl.dy * pl.l * e;
    }
    if (k >= 1) {
      drag = null;
      aiPlan = null;
      fire(pl.b, pl.dx * pl.l, pl.dy * pl.l, pl.l);
    }
  }

  AiPlan? _aiDecide() {
    final me = turn, bl = ball, B = bodies, mine = B.where((b) => b.team == me && b != bl).toList();
    final og = goals[1 - me];
    final target = goals[me == 1 ? 1 : 0];
    final lvl = cfg.aiLvl, sg = const [.14, .06, .016][lvl], gw = (target.x2 - target.x1) / 2;
    double segDist(double px, double py, double ax, double ay, double bx, double by) {
      final vx = bx - ax, vy = by - ay;
      var l2 = vx * vx + vy * vy;
      if (l2 == 0) l2 = 1;
      var t = ((px - ax) * vx + (py - ay) * vy) / l2;
      t = clampD(t, 0, 1);
      return hyp(px - (ax + vx * t), py - (ay + vy * t));
    }

    bool clear(Body p, double x, double y) {
      for (final o in B) {
        if (o == p || o == bl) continue;
        if (segDist(o.x, o.y, p.x, p.y, x, y) < p.r + o.r - 6) return false;
      }
      return true;
    }

    final cands = <({Body p, double dx, double dy, double sc, double dist, int atk})>[];
    for (final p in mine) {
      for (final ox in const [-.55, 0.0, .55]) {
        final Tx = CX + ox * gw, Ty = target.y;
        var ux = Tx - bl.x, uy = Ty - bl.y;
        var ul = hyp(ux, uy);
        if (ul == 0) ul = 1;
        ux /= ul;
        uy /= ul;
        final cx = bl.x - ux * (p.r + bl.r + 1), cy = bl.y - uy * (p.r + bl.r + 1);
        var vx = cx - p.x, vy = cy - p.y;
        final dist = hyp(vx, vy);
        if (dist < 8) continue;
        vx /= dist;
        vy /= dist;
        final al = vx * ux + vy * uy;
        if (al < .2 || !clear(p, cx, cy)) continue;
        var blk = 0;
        for (final o in B) {
          if (o.team == me || o == bl) continue;
          if (segDist(o.x, o.y, bl.x, bl.y, Tx, Ty) < bl.r + o.r + 6) blk++;
        }
        cands.add((p: p, dx: vx, dy: vy, sc: 100 * al - dist * .03 - blk * 28 + ((bl.y - Ty).abs() < 420 ? 25 : 0), dist: dist, atk: 1));
      }
      var vx = bl.x - p.x, vy = bl.y - p.y;
      final dist = hyp(vx, vy);
      if (dist > 8) {
        vx /= dist;
        vy /= dist;
        if (clear(p, bl.x, bl.y)) {
          final toOwn = (vy * (og.y - bl.y) > 0) ? vy.abs() : 0;
          cands.add((p: p, dx: vx, dy: vy, sc: 10 - dist * .04 - toOwn * 55, dist: dist, atk: 0));
        }
      }
    }
    if (cands.isEmpty) {
      final s = mine.toList()..sort((a, b) => hyp(a.x - bl.x, a.y - bl.y).compareTo(hyp(b.x - bl.x, b.y - bl.y)));
      if (s.isEmpty) return null;
      final p = s.first;
      final vx = bl.x - p.x, vy = bl.y - p.y;
      var d = hyp(vx, vy);
      if (d == 0) d = 1;
      cands.add((p: p, dx: vx / d, dy: vy / d, sc: 0, dist: d, atk: 0));
    }
    cands.sort((a, b) => b.sc.compareTo(a.sc));
    final pool = cands.take(const [4, 2, 1][lvl]).toList(), c = pool[(_random() * pool.length).floor()];
    double gauss() => (_random() + _random() + _random() - 1.5) * 1.15;
    final ang = math.atan2(c.dy, c.dx) + gauss() * sg;
    var pw = lvl == 2 ? math.min(1.0, .66 + c.dist / 1000) : math.min(1.0, .5 + c.dist / 1100);
    if (lvl == 0) pw *= .7 + _random() * .3;
    if (c.atk == 1 && lvl > 0) pw = math.max(pw, .78);
    return AiPlan(c.p, math.cos(ang), math.sin(ang), math.max(.3, pw) * LMAX, 0);
  }
}
