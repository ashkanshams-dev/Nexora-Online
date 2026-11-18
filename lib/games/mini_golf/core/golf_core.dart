import 'dart:math' as math;

/// NEXORA Mini Golf — pure Dart, deterministic (fixed 1/120 s steps, the windmill turns with simulation time
/// counted from the start of each shot, so every phone replays the same shot identically).
///
/// Course units: 300 x 520 portrait. 9 holes; players take turns (the player furthest from the cup who has not
/// holed out shoots next — classic golf order); 7 strokes max per hole (8 written on the card). Lowest total wins.

class GVec {
  const GVec(this.x, this.y);
  final double x;
  final double y;
}

class GWall {
  const GWall(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
}

class GRect {
  const GRect(this.l, this.t, this.r, this.b);
  final double l, t, r, b;
  bool has(double x, double y) => x >= l && x <= r && y >= t && y <= b;
}

class GBumper {
  const GBumper(this.x, this.y, this.r);
  final double x, y, r;
}

class GWindmill {
  const GWindmill(this.x, this.y, this.len, this.speed);
  final double x, y, len, speed;
}

class GHole {
  GHole({
    required this.par,
    required this.start,
    required this.cup,
    required this.walls,
    this.sand = const <GRect>[],
    this.water = const <GRect>[],
    this.bumpers = const <GBumper>[],
    this.mills = const <GWindmill>[],
  });
  final int par;
  final GVec start;
  final GVec cup;
  final List<GWall> walls;
  final List<GRect> sand;
  final List<GRect> water;
  final List<GBumper> bumpers;
  final List<GWindmill> mills;
}

const double kGolfW = 300, kGolfH = 520;
const double kBallR = 6, kCupR = 10;
const double kMaxShot = 720; // units / s
const int kMaxStrokes = 7;

List<GWall> _box(double l, double t, double r, double b) =>
    <GWall>[GWall(l, t, r, t), GWall(r, t, r, b), GWall(r, b, l, b), GWall(l, b, l, t)];

/// The 9 holes. [seed] mirrors some layouts so daily courses differ.
List<GHole> golfCourse(int seed) {
  final List<GHole> h = <GHole>[
    // 1: straight, gentle
    GHole(par: 2, start: const GVec(150, 450), cup: const GVec(150, 90), walls: _box(70, 40, 230, 490)),
    // 2: bumpers slalom
    GHole(par: 3, start: const GVec(150, 460), cup: const GVec(150, 80), walls: _box(40, 40, 260, 490), bumpers: const <GBumper>[
      GBumper(110, 330, 16), GBumper(190, 250, 16), GBumper(110, 170, 16),
    ]),
    // 3: L-shape
    GHole(par: 3, start: const GVec(80, 460), cup: const GVec(240, 90), walls: <GWall>[
      ..._box(30, 40, 270, 490),
      const GWall(130, 160, 130, 490),
      const GWall(130, 160, 270, 160),
    ]),
    // 4: sand trap in front of the cup
    GHole(par: 3, start: const GVec(150, 460), cup: const GVec(150, 100), walls: _box(50, 40, 250, 490), sand: const <GRect>[
      GRect(80, 140, 220, 200),
    ], bumpers: const <GBumper>[GBumper(150, 300, 22)]),
    // 5: windmill
    GHole(par: 3, start: const GVec(150, 460), cup: const GVec(150, 90), walls: <GWall>[
      ..._box(60, 40, 240, 490),
      const GWall(60, 260, 120, 260),
      const GWall(180, 260, 240, 260),
    ], mills: const <GWindmill>[GWindmill(150, 260, 52, 1.6)]),
    // 6: water hazard with a bridge
    GHole(par: 3, start: const GVec(150, 465), cup: const GVec(150, 80), walls: _box(40, 40, 260, 490), water: const <GRect>[
      GRect(40, 230, 125, 300), GRect(175, 230, 260, 300),
    ]),
    // 7: zig-zag
    GHole(par: 4, start: const GVec(70, 465), cup: const GVec(230, 80), walls: <GWall>[
      ..._box(30, 40, 270, 490),
      const GWall(30, 370, 200, 370),
      const GWall(100, 250, 270, 250),
      const GWall(30, 140, 200, 140),
    ]),
    // 8: diamond bank shot
    GHole(par: 3, start: const GVec(150, 465), cup: const GVec(150, 80), walls: <GWall>[
      ..._box(30, 40, 270, 490),
      const GWall(150, 200, 210, 270),
      const GWall(210, 270, 150, 340),
      const GWall(150, 340, 90, 270),
      const GWall(90, 270, 150, 200),
    ], sand: const <GRect>[GRect(30, 40, 90, 100), GRect(210, 40, 270, 100)]),
    // 9: finale — windmill + water + bumpers
    GHole(par: 4, start: const GVec(150, 470), cup: const GVec(150, 70), walls: <GWall>[
      ..._box(30, 30, 270, 500),
      const GWall(30, 200, 120, 200),
      const GWall(180, 200, 270, 200),
    ], water: const <GRect>[GRect(30, 330, 110, 380), GRect(190, 330, 270, 380)], bumpers: const <GBumper>[
      GBumper(150, 355, 14), GBumper(80, 120, 12), GBumper(220, 120, 12),
    ], mills: const <GWindmill>[GWindmill(150, 200, 46, -2.1)]),
  ];
  if (seed.isOdd) {
    // mirror the asymmetric holes horizontally
    return <GHole>[for (final GHole x in h) _mirror(x)];
  }
  return h;
}

GHole _mirror(GHole h) {
  double m(double x) => kGolfW - x;
  return GHole(
    par: h.par,
    start: GVec(m(h.start.x), h.start.y),
    cup: GVec(m(h.cup.x), h.cup.y),
    walls: <GWall>[for (final GWall w in h.walls) GWall(m(w.x1), w.y1, m(w.x2), w.y2)],
    sand: <GRect>[for (final GRect r in h.sand) GRect(m(r.r), r.t, m(r.l), r.b)],
    water: <GRect>[for (final GRect r in h.water) GRect(m(r.r), r.t, m(r.l), r.b)],
    bumpers: <GBumper>[for (final GBumper b in h.bumpers) GBumper(m(b.x), b.y, b.r)],
    mills: <GWindmill>[for (final GWindmill w in h.mills) GWindmill(m(w.x), w.y, w.len, -w.speed)],
  );
}

class GBall {
  GBall(this.x, this.y);
  double x, y;
  double vx = 0, vy = 0;
  bool holed = false;
  int strokes = 0;
  double lastX = 0, lastY = 0; // position before the current shot (water reset)
  bool get moving => vx != 0 || vy != 0;
}

/// Events for the renderer (sound/FX); never affect results.
class GEvent {
  const GEvent(this.kind, this.x, this.y, [this.strength = 0]);
  final String kind; // wall | bumper | sand | water | cup | mill
  final double x, y, strength;
}

class GolfMatch {
  GolfMatch({required this.players, int seed = 1}) : course = golfCourse(seed) {
    cards = List<List<int>>.generate(players, (_) => <int>[]);
    _startHole();
  }

  final int players;
  final List<GHole> course;
  late List<List<int>> cards;
  int hole = 0;
  late List<GBall> balls;
  int current = 0;
  bool simulating = false;
  double simTime = 0;
  int _steps = 0;
  int shotsTaken = 0;
  final List<GEvent> events = <GEvent>[];
  final Set<int> out = <int>{}; // forfeited seats

  GHole get h => course[hole];
  bool get over => hole >= course.length;

  void _startHole() {
    if (over) return;
    balls = <GBall>[
      for (int i = 0; i < players; i++) GBall(h.start.x + (i - (players - 1) / 2) * 14, h.start.y)
    ];
    for (final GBall b in balls) {
      b
        ..lastX = b.x
        ..lastY = b.y;
    }
    current = _nextShooter() ?? 0;
  }

  /// Golf order: furthest from the cup first (ties: lower seat).
  int? _nextShooter() {
    int? best;
    double bd = -1;
    for (int i = 0; i < players; i++) {
      final GBall b = balls[i];
      if (b.holed || out.contains(i)) continue;
      final double d = _dist(b.x, b.y, h.cup.x, h.cup.y) + (b.strokes == 0 ? 1000 - i : 0);
      if (d > bd + 1e-9) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  static double _dist(double ax, double ay, double bx, double by) => math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));

  /// Total strokes per player (finished holes).
  int total(int seat) => cards[seat].fold(0, (int a, int b) => a + b);
  int parSoFar() => <int>[for (int i = 0; i < cards[0].length && i < course.length; i++) course[i].par].fold(0, (int a, int b) => a + b);

  /// Shoots for the current player: [angle] radians, [power] 0..1.
  bool shoot(double angle, double power) {
    if (simulating || over) return false;
    final GBall b = balls[current];
    if (b.holed) return false;
    final double p = power.clamp(0.05, 1.0);
    b
      ..lastX = b.x
      ..lastY = b.y
      ..vx = math.cos(angle) * kMaxShot * p
      ..vy = math.sin(angle) * kMaxShot * p
      ..strokes += 1;
    simulating = true;
    simTime = 0;
    _steps = 0;
    shotsTaken++;
    return true;
  }

  /// Windmill blade angle during a shot (deterministic: depends on hole + shots taken + sim time).
  double millAngle(GWindmill w, [double? t]) => (shotsTaken * 0.9 + hole * 0.7) + w.speed * (t ?? simTime);

  /// Advances the simulation by [n] fixed steps; returns true when the ball has stopped (turn resolved).
  bool step([int n = 2]) {
    if (!simulating) return true;
    for (int i = 0; i < n; i++) {
      if (_tick()) {
        _resolve();
        return true;
      }
    }
    return false;
  }

  void runToEnd() {
    while (!step(240)) {}
  }

  static const double _dt = 1 / 120;

  bool _tick() {
    final GBall b = balls[current];
    simTime += _dt;
    _steps++;
    final double sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    final bool inSand = h.sand.any((GRect r) => r.has(b.x, b.y));
    final double decel = inSand ? 900 : 190;
    if (sp > 0) {
      final double ns = math.max(0, sp - decel * _dt) * (1 - 0.25 * _dt);
      if (ns < 4) {
        b.vx = 0;
        b.vy = 0;
      } else {
        b.vx = b.vx / sp * ns;
        b.vy = b.vy / sp * ns;
      }
    }
    // 2 sub-steps for collisions (max 6 units per sub-step at full power)
    for (int s = 0; s < 2; s++) {
      b.x += b.vx * _dt / 2;
      b.y += b.vy * _dt / 2;
      for (final GWall w in h.walls) {
        _collideSeg(b, w.x1, w.y1, w.x2, w.y2, 0.78, 'wall');
      }
      for (final GWindmill m in h.mills) {
        final double a = millAngle(m);
        for (int k = 0; k < 2; k++) {
          final double aa = a + k * math.pi / 2;
          final double cx = math.cos(aa) * m.len, cy = math.sin(aa) * m.len;
          _collideSeg(b, m.x - cx, m.y - cy, m.x + cx, m.y + cy, 0.9, 'mill');
        }
      }
      for (final GBumper p in h.bumpers) {
        final double dx = b.x - p.x, dy = b.y - p.y;
        final double d = math.sqrt(dx * dx + dy * dy);
        final double min = p.r + kBallR;
        if (d < min && d > 0) {
          final double nx = dx / d, ny = dy / d;
          b.x = p.x + nx * min;
          b.y = p.y + ny * min;
          final double vn = b.vx * nx + b.vy * ny;
          if (vn < 0) {
            b.vx -= 2.15 * vn * nx; // springy bumper adds a little energy
            b.vy -= 2.15 * vn * ny;
            events.add(GEvent('bumper', b.x, b.y, -vn));
          }
        }
      }
    }
    // cup: captured when slow enough over it, lipped out when fast
    final double dc = _dist(b.x, b.y, h.cup.x, h.cup.y);
    final double v = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    if (dc < kCupR - 1 && v < 330) {
      b
        ..holed = true
        ..x = h.cup.x
        ..y = h.cup.y
        ..vx = 0
        ..vy = 0;
      events.add(GEvent('cup', b.x, b.y));
      return true;
    } else if (dc < kCupR && v >= 330) {
      // lip: pull the path slightly toward the cup centre
      b.vx += (h.cup.x - b.x) * 3;
      b.vy += (h.cup.y - b.y) * 3;
    }
    for (final GRect r in h.water) {
      if (r.has(b.x, b.y)) {
        events.add(GEvent('water', b.x, b.y));
        b
          ..x = b.lastX
          ..y = b.lastY
          ..vx = 0
          ..vy = 0
          ..strokes += 1; // penalty stroke
        return true;
      }
    }
    return (b.vx == 0 && b.vy == 0) || _steps > 120 * 14;
  }

  void _collideSeg(GBall b, double x1, double y1, double x2, double y2, double e, String kind) {
    final double ex = x2 - x1, ey = y2 - y1;
    final double l2 = ex * ex + ey * ey;
    if (l2 == 0) return;
    double t = ((b.x - x1) * ex + (b.y - y1) * ey) / l2;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    final double px = x1 + ex * t, py = y1 + ey * t;
    final double dx = b.x - px, dy = b.y - py;
    final double d2 = dx * dx + dy * dy;
    if (d2 >= kBallR * kBallR) return;
    final double d = math.sqrt(d2);
    double nx, ny;
    if (d > 1e-9) {
      nx = dx / d;
      ny = dy / d;
    } else {
      nx = -ey / math.sqrt(l2);
      ny = ex / math.sqrt(l2);
    }
    b.x = px + nx * kBallR;
    b.y = py + ny * kBallR;
    final double vn = b.vx * nx + b.vy * ny;
    if (vn < 0) {
      b.vx -= (1 + e) * vn * nx;
      b.vy -= (1 + e) * vn * ny;
      if (-vn > 40) events.add(GEvent(kind, b.x, b.y, -vn));
    }
  }

  /// After the ball stops: max strokes, next shooter, next hole.
  void _resolve() {
    simulating = false;
    final GBall b = balls[current];
    b.vx = 0;
    b.vy = 0;
    if (!b.holed && b.strokes >= kMaxStrokes) {
      b.holed = true;
      b.strokes = kMaxStrokes + 1;
    }
    _advance();
  }

  void _advance() {
    final int? n = _nextShooter();
    if (n != null) {
      current = n;
      return;
    }
    for (int i = 0; i < players; i++) {
      cards[i].add(out.contains(i) ? kMaxStrokes + 1 : balls[i].strokes);
    }
    hole++;
    _startHole();
  }

  /// A player left: they are written down for the max on every remaining hole.
  void forfeit(int seat) {
    out.add(seat);
    if (!simulating && current == seat && !over) _advance();
  }

  /// Ranking best → worst (fewest strokes, then lower seat).
  List<int> ranking() {
    final List<int> s = List<int>.generate(players, (int i) => i);
    int tot(int i) => total(i) + (out.contains(i) ? 1000 : 0);
    s.sort((int a, int b) => tot(a) != tot(b) ? tot(a).compareTo(tot(b)) : a.compareTo(b));
    return s;
  }

  String stateKey() =>
      '$hole|$current|${balls.map((GBall b) => '${b.x.toStringAsFixed(2)},${b.y.toStringAsFixed(2)},${b.strokes},${b.holed ? 1 : 0}').join(';')}';

  /// Clone for bot look-ahead.
  GolfMatch _probe() => GolfMatch._copy(this);

  GolfMatch._copy(GolfMatch o)
      : players = o.players,
        course = o.course {
    cards = o.cards;
    hole = o.hole;
    current = o.current;
    shotsTaken = o.shotsTaken;
    balls = <GBall>[
      for (final GBall b in o.balls)
        GBall(b.x, b.y)
          ..strokes = b.strokes
          ..holed = b.holed
    ];
  }

  /// Bot: samples shots and returns (angle, power) with the best outcome. [skill] 0..1 adds aim noise.
  (double, double) botShot(math.Random rng, double skill, {int samples = 48}) {
    final GBall me = balls[current];
    final double direct = math.atan2(h.cup.y - me.y, h.cup.x - me.x);
    double bestA = direct, bestP = 0.5, bestScore = double.infinity;
    for (int i = 0; i < samples; i++) {
      final double a = i < samples ~/ 3 ? direct + (rng.nextDouble() - 0.5) * 0.5 : rng.nextDouble() * math.pi * 2;
      final double p = 0.15 + rng.nextDouble() * 0.85;
      final GolfMatch g = _probe();
      final int cur = g.current;
      g.shoot(a, p);
      while (g.simulating) {
        if (g._tick()) {
          g.simulating = false;
        }
      }
      final GBall r = g.balls[cur];
      final double score = r.holed ? -1000 + p : _dist(r.x, r.y, h.cup.x, h.cup.y) + (r.strokes > me.strokes + 1 ? 120 : 0);
      if (score < bestScore) {
        bestScore = score;
        bestA = a;
        bestP = p;
      }
    }
    final double noise = (1 - skill) * 0.16;
    return (bestA + (rng.nextDouble() - 0.5) * noise, (bestP * (1 + (rng.nextDouble() - 0.5) * noise)).clamp(0.05, 1.0));
  }
}
