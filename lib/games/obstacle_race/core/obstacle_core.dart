import 'dart:math' as math;

/// Pure-Dart "last one standing" obstacle course (Fall-Guys style, top-down).
/// The camera scrolls up ever faster; runners auto-run, steer and jump. Falling into a pit or dropping off the
/// bottom of the screen eliminates you. Obstacles are generated from the seed and animate from race time only,
/// so every phone sees the same course.

enum ObKind { sweeper, pit, gate, drop, bumper }

class Obstacle {
  Obstacle(this.kind, this.x, this.y, {this.w = 0, this.h = 0, this.speed = 0, this.phase = 0});
  final ObKind kind;
  final double x, y, w, h, speed, phase;

  /// Sweeper angle / gate gap centre / drop cycle at [t].
  double angle(double t) => phase + speed * t;
  double gateGap(double t, double width) => width / 2 + math.sin(phase + speed * t) * (width / 2 - w / 2 - 20);

  /// Drop: 0..1 inside a 2.4 s cycle; lands at 0.75.
  double dropCycle(double t) => ((t * 0.42 + phase) % 1.0);
}

class Runner {
  Runner(this.seat, this.x, this.y);
  final int seat;
  double x, y;
  double vx = 0;
  double z = 0, vz = 0;
  double knock = 0;
  double stun = 0;
  bool alive = true;
  double outAt = 0;
  double steer = 0;
  bool wantJump = false;
  bool get grounded => z <= 0;
}

class ObEvent {
  const ObEvent(this.kind, this.seat, this.x, this.y);
  final String kind; // jump, knock, out, bump
  final int seat;
  final double x, y;
}

class ObstacleRace {
  ObstacleRace({required this.seed, required this.count, this.botSkill = const <double>[]}) {
    _gen();
    for (int i = 0; i < count; i++) {
      runners.add(Runner(i, width * (i + 1) / (count + 1), 120));
    }
  }

  static const double width = 420;
  static const double viewH = 760;
  static const double runnerR = 15;

  final int seed;
  final int count;
  final List<double> botSkill;
  final List<Runner> runners = <Runner>[];
  final List<Obstacle> obstacles = <Obstacle>[];
  final List<ObEvent> events = <ObEvent>[];
  final List<int> outOrder = <int>[];
  double time = 0;
  double countdown = 3;
  double cam = 0;

  bool isBot(int s) => s < botSkill.length && botSkill[s] > 0;
  double get camSpeed => 105 + math.min(165, time * 1.9);
  double get runSpeed => camSpeed + 85;
  int get aliveCount => runners.where((Runner r) => r.alive).length;
  bool get over => count > 1 ? aliveCount <= 1 : aliveCount == 0;

  void _gen() {
    final math.Random r = math.Random(seed);
    double y = 520;
    while (y < 60000) {
      final int pick = r.nextInt(5);
      switch (pick) {
        case 0:
          obstacles.add(Obstacle(ObKind.sweeper, 60 + r.nextDouble() * (width - 120), y,
              w: 120 + r.nextDouble() * 60, speed: (r.nextBool() ? 1 : -1) * (1.4 + r.nextDouble() * 1.4), phase: r.nextDouble() * 6));
          y += 260;
        case 1:
          final double pw = 120 + r.nextDouble() * 140;
          obstacles.add(Obstacle(ObKind.pit, r.nextDouble() * (width - pw), y, w: pw, h: 70 + r.nextDouble() * 40));
          y += 230;
        case 2:
          obstacles.add(Obstacle(ObKind.gate, 0, y, w: 130 + r.nextDouble() * 50, h: 26, speed: 0.45 + r.nextDouble() * 0.5, phase: r.nextDouble() * 6));
          y += 240;
        case 3:
          for (int k = 0; k < 3; k++) {
            obstacles.add(Obstacle(ObKind.drop, 50 + r.nextDouble() * (width - 100), y + k * 60, w: 64, h: 64, phase: r.nextDouble()));
          }
          y += 300;
        default:
          for (int k = 0; k < 3; k++) {
            obstacles.add(Obstacle(ObKind.bumper, 50 + r.nextDouble() * (width - 100), y + r.nextDouble() * 120, w: 26));
          }
          y += 220;
      }
    }
  }

  Iterable<Obstacle> near(double y0, double y1) sync* {
    for (final Obstacle o in obstacles) {
      if (o.y + 200 < y0) continue;
      if (o.y - 200 > y1) break;
      yield o;
    }
  }

  void input(int seat, double steer, bool jump) {
    final Runner r = runners[seat];
    r.steer = steer.clamp(-1.0, 1.0);
    if (jump) r.wantJump = true;
  }

  void eliminate(int seat, double at) {
    final Runner r = runners[seat];
    if (!r.alive) return;
    r.alive = false;
    r.outAt = at;
    outOrder.add(seat);
    events.add(ObEvent('out', seat, r.x, r.y));
  }

  /// Ranking best → worst: survivors first (by distance), then reverse elimination order.
  List<int> ranking() {
    final List<Runner> alive = runners.where((Runner r) => r.alive).toList()..sort((Runner a, Runner b) => b.y.compareTo(a.y));
    return <int>[...alive.map((Runner r) => r.seat), ...outOrder.reversed];
  }

  void step(double dt, {Set<int>? simulate}) {
    time += 0; // time advances only after the countdown
    if (countdown > 0) {
      countdown -= dt;
      return;
    }
    time += dt;
    cam += camSpeed * dt;
    for (final Runner r in runners) {
      if (!r.alive || (simulate != null && !simulate.contains(r.seat))) continue;
      if (isBot(r.seat)) _bot(r);
      _move(r, dt);
    }
    // runner-runner shoves
    for (int i = 0; i < runners.length; i++) {
      for (int j = i + 1; j < runners.length; j++) {
        final Runner a = runners[i], b = runners[j];
        if (!a.alive || !b.alive) continue;
        final double dx = b.x - a.x, dy = b.y - a.y;
        final double d = math.sqrt(dx * dx + dy * dy);
        if (d > 0 && d < runnerR * 2) {
          final double k = (runnerR * 2 - d) / d * 0.5;
          if (simulate == null || simulate.contains(a.seat)) {
            a.x -= dx * k;
            a.y -= dy * k;
          }
          if (simulate == null || simulate.contains(b.seat)) {
            b.x += dx * k;
            b.y += dy * k;
          }
        }
      }
    }
  }

  void _move(Runner r, double dt) {
    if (r.wantJump && r.grounded && r.stun <= 0) {
      r.vz = 330;
      events.add(ObEvent('jump', r.seat, r.x, r.y));
    }
    r.wantJump = false;
    r.vz -= 900 * dt;
    r.z = math.max(0, r.z + r.vz * dt);
    if (r.z <= 0) r.vz = 0;
    if (r.stun > 0) r.stun -= dt;
    final double ctrl = r.stun > 0 ? 0.2 : 1;
    r.vx += (r.steer * 330 - r.vx) * math.min(1, dt * 10) * ctrl;
    r.x = (r.x + r.vx * dt).clamp(runnerR, width - runnerR);
    double fwd = runSpeed * ctrl;
    if (r.knock > 0) {
      fwd = -260;
      r.knock -= dt;
    }
    final double top = cam + viewH - 70;
    r.y = math.min(r.y + fwd * dt, top);
    for (final Obstacle o in near(r.y - 60, r.y + 60)) {
      switch (o.kind) {
        case ObKind.sweeper:
          if (r.z > 18) break;
          final double a = o.angle(time);
          final double ex = o.x + math.cos(a) * o.w, ey = o.y + math.sin(a) * o.w;
          final double d = _segDist(r.x, r.y, o.x, o.y, ex, ey);
          if (d < runnerR + 7 && r.knock <= 0) {
            r.knock = 0.28;
            r.stun = 0.5;
            r.vx = (r.x < o.x ? -1 : 1) * 260;
            events.add(ObEvent('knock', r.seat, r.x, r.y));
          }
        case ObKind.pit:
          if (r.z <= 0 && r.x > o.x + 6 && r.x < o.x + o.w - 6 && r.y > o.y + 6 && r.y < o.y + o.h - 6) {
            eliminate(r.seat, time);
            return;
          }
        case ObKind.gate:
          final double g = o.gateGap(time, width);
          final bool inGap = (r.x - g).abs() < o.w / 2 - runnerR * 0.6;
          if (!inGap && r.y + runnerR > o.y && r.y - runnerR < o.y + o.h) {
            r.y = o.y - runnerR;
          }
        case ObKind.drop:
          final double c = o.dropCycle(time);
          if (c > 0.74 && c < 0.8 && (r.x - o.x).abs() < o.w / 2 && (r.y - o.y).abs() < o.h / 2 && r.stun <= 0) {
            r.stun = 0.8;
            r.knock = 0.2;
            events.add(ObEvent('knock', r.seat, r.x, r.y));
          }
        case ObKind.bumper:
          final double dx = r.x - o.x, dy = r.y - o.y;
          final double d = math.sqrt(dx * dx + dy * dy);
          if (d > 0 && d < runnerR + o.w) {
            r.x = o.x + dx / d * (runnerR + o.w);
            r.y = o.y + dy / d * (runnerR + o.w);
            r.vx = dx / d * 380;
            events.add(ObEvent('bump', r.seat, o.x, o.y));
          }
      }
    }
    if (r.y < cam - 20) eliminate(r.seat, time);
  }

  static double _segDist(double px, double py, double ax, double ay, double bx, double by) {
    final double vx = bx - ax, vy = by - ay;
    final double l2 = vx * vx + vy * vy;
    double t = l2 == 0 ? 0 : ((px - ax) * vx + (py - ay) * vy) / l2;
    t = t.clamp(0.0, 1.0);
    final double cx = ax + vx * t - px, cy = ay + vy * t - py;
    return math.sqrt(cx * cx + cy * cy);
  }

  final math.Random _br = math.Random(99);

  void _bot(Runner r) {
    final double skill = botSkill[r.seat];
    double targetX = r.x;
    bool jump = false;
    for (final Obstacle o in near(r.y, r.y + 220)) {
      final double ahead = o.y - r.y;
      switch (o.kind) {
        case ObKind.pit:
          if (r.x > o.x - runnerR && r.x < o.x + o.w + runnerR && ahead > -o.h) {
            final double left = o.x - runnerR * 2, right = o.x + o.w + runnerR * 2;
            final bool canL = left > runnerR, canR = right < width - runnerR;
            targetX = (canL && (!canR || (r.x - left).abs() < (right - r.x).abs())) ? left : right;
            if (ahead < 40 + (1 - skill) * 30 && ahead > 0) jump = true;
          }
        case ObKind.gate:
          if (ahead > 0 && ahead < 200) targetX = o.gateGap(time + ahead / runSpeed, width);
        case ObKind.sweeper:
          final double a = o.angle(time + 0.12);
          final double ex = o.x + math.cos(a) * o.w, ey = o.y + math.sin(a) * o.w;
          if (_segDist(r.x, r.y + 26, o.x, o.y, ex, ey) < 32) jump = true;
        case ObKind.drop:
          final double c = o.dropCycle(time + 0.25);
          if (c > 0.6 && c < 0.8 && (r.x - o.x).abs() < o.w && ahead < 80 && ahead > -30) {
            targetX = r.x < o.x ? o.x - o.w : o.x + o.w;
          }
        case ObKind.bumper:
          break;
      }
      if (ahead > 140) break;
    }
    final double err = (1 - skill) * 0.9;
    if (_br.nextDouble() < err * 0.08) jump = !jump;
    r.steer = ((targetX - r.x) / 40).clamp(-1.0, 1.0) * (0.6 + skill * 0.4);
    if (jump && _br.nextDouble() < 0.4 + skill * 0.6) r.wantJump = true;
  }
}
