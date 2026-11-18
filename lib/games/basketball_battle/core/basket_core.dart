import 'dart:math' as math;

/// NEXORA Basketball Battle — a 60-second shoot-out. Every player shoots on their own hoop at the same time;
/// scores are broadcast live (peer pattern) and the best score wins. Pure Dart, deterministic for a seed.
///
/// World units: 360 x 640, front view. Swipe up to throw; the rim is two solid points, the ball scores when it falls
/// through the rim line between them. Clean "swish" = 3 points, rim-in = 2. Three makes in a row light the
/// ball ON FIRE (double points until a miss). After 12 points the hoop starts sliding, faster as you score.
const double kBW = 360, kBH = 640;
const double kBallR = 19;
const double kRimHalf = 38;
const double kRimR = 4.5;
const double kGravity = 1650;

class BEvent {
  const BEvent(this.kind, this.x, this.y, [this.value = 0]);
  final String kind; // rim | swish | score | miss | fire
  final double x, y;
  final int value;
}

class BasketCourt {
  BasketCourt({int seed = 1, this.duration = 60}) : _rng = math.Random(seed) {
    _spawn();
  }

  final math.Random _rng;
  final double duration;
  double time = 0;
  double countdown = 3;

  // ball
  double x = 0, y = 0, vx = 0, vy = 0, spin = 0, angle = 0;
  bool flying = false;
  bool _touchedRim = false;
  bool _wasAbove = false;
  bool _scoredThis = false;
  double _respawn = 0;

  // hoop
  double hoopX = kBW / 2;
  double hoopY = 230;
  double _hoopDir = 1;

  int score = 0;
  int streak = 0;
  int made = 0;
  int shots = 0;
  bool get onFire => streak >= 3;
  bool get over => time >= duration;
  double get left => math.max(0, duration - time);
  final List<BEvent> events = <BEvent>[];

  double get hoopSpeed => score < 12 ? 0 : math.min(150, 40 + (score - 12) * 3.0);

  void _spawn() {
    x = 70 + _rng.nextDouble() * (kBW - 140);
    y = kBH - 90;
    vx = 0;
    vy = 0;
    spin = 0;
    flying = false;
    _touchedRim = false;
    _scoredThis = false;
    _wasAbove = false;
  }

  /// Throws the resting ball. [sx],[sy] = swipe vector in world units (up is negative y).
  bool throwBall(double sx, double sy) {
    if (flying || over || countdown > 0 || _respawn > 0) return false;
    if (sy > -20) return false;
    vx = (sx * 3.2).clamp(-700, 700);
    vy = (sy * 4.4).clamp(-1500, -500);
    spin = vx / 60;
    flying = true;
    shots++;
    return true;
  }

  void step(double dt) {
    if (countdown > 0) {
      countdown -= dt;
      return;
    }
    if (over) return;
    time += dt;
    // sliding hoop
    final double hs = hoopSpeed;
    if (hs > 0) {
      hoopX += _hoopDir * hs * dt;
      if (hoopX > kBW - 70) {
        hoopX = kBW - 70;
        _hoopDir = -1;
      } else if (hoopX < 70) {
        hoopX = 70;
        _hoopDir = 1;
      }
    }
    if (_respawn > 0) {
      _respawn -= dt;
      if (_respawn <= 0) _spawn();
      return;
    }
    if (!flying) return;
    const int sub = 3;
    final double h = dt / sub;
    for (int i = 0; i < sub; i++) {
      final double prevY = y;
      vy += kGravity * h;
      x += vx * h;
      y += vy * h;
      angle += spin * h;
      // side walls
      if (x < kBallR) {
        x = kBallR;
        vx = vx.abs() * 0.6;
      } else if (x > kBW - kBallR) {
        x = kBW - kBallR;
        vx = -vx.abs() * 0.6;
      }
      // rim points (only while falling or level, the ball passes in front on the way up)
      if (vy > -200) {
        for (final double rx in <double>[hoopX - kRimHalf, hoopX + kRimHalf]) {
          final double dx = x - rx, dy = y - hoopY;
          final double d = math.sqrt(dx * dx + dy * dy);
          const double min = kBallR + kRimR;
          if (d < min && d > 0) {
            final double nx = dx / d, ny = dy / d;
            x = rx + nx * min;
            y = hoopY + ny * min;
            final double vn = vx * nx + vy * ny;
            if (vn < 0) {
              vx -= 1.55 * vn * nx;
              vy -= 1.55 * vn * ny;
              spin = -spin * 0.6 + nx * 3;
              if (!_touchedRim) events.add(BEvent('rim', rx, hoopY));
              _touchedRim = true;
            }
          }
        }
      }
      // scoring: centre crosses the rim line downward between the points
      if (prevY <= hoopY && y > hoopY && vy > 0 && (x - hoopX).abs() < kRimHalf - kRimR && !_scoredThis && _wasAbove) {
        _scoredThis = true;
        streak++;
        made++;
        final int base = _touchedRim ? 2 : 3;
        final int pts = onFire ? base * 2 : base;
        score += pts;
        events.add(BEvent(_touchedRim ? 'score' : 'swish', hoopX, hoopY, pts));
        if (streak == 3) events.add(BEvent('fire', hoopX, hoopY));
        // the net slows the ball
        vy *= 0.45;
        vx *= 0.3;
      }
      if (y < hoopY - kBallR) _wasAbove = true;
    }
    if (vy > 0 && y > kBH - 60) {
      if (!_scoredThis) {
        streak = 0;
        events.add(BEvent('miss', x, y));
      }
      flying = false;
      _respawn = 0.35;
    }
  }
}

/// Offline opponent: shoots at a human-like rhythm with a skill-based hit rate.
class BasketBot {
  BasketBot({required int seed, required this.skill}) : _rng = math.Random(seed);
  final math.Random _rng;
  final double skill;
  int score = 0;
  int streak = 0;
  double _next = 1.2;
  double time = 0;

  /// Returns points made this step (0 when nothing happened) for HUD pops.
  int step(double dt, double duration) {
    time += dt;
    if (time >= duration) return 0;
    _next -= dt;
    if (_next > 0) return 0;
    _next = 1.25 + _rng.nextDouble() * (1.6 - skill);
    final double p = 0.32 + skill * 0.5 - (score > 30 ? 0.08 : 0);
    if (_rng.nextDouble() < p) {
      streak++;
      final int base = _rng.nextDouble() < 0.25 + skill * 0.35 ? 3 : 2;
      final int pts = streak >= 3 ? base * 2 : base;
      score += pts;
      return pts;
    }
    streak = 0;
    return 0;
  }
}
