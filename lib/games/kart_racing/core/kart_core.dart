import 'dart:math' as math;

/// Pure-Dart kart racing simulation (CTR style): closed track from a seed, drift + mini-turbo, boost pads,
/// item boxes (turbo, homing missile, shield, oil slick), laps, positions and bot drivers.
/// No Flutter imports: unit-tested and identical on every phone.

class V2 {
  const V2(this.x, this.y);
  final double x, y;
  V2 operator +(V2 o) => V2(x + o.x, y + o.y);
  V2 operator -(V2 o) => V2(x - o.x, y - o.y);
  V2 operator *(double k) => V2(x * k, y * k);
  double get len => math.sqrt(x * x + y * y);
  double dist(V2 o) => (this - o).len;
}

class KartTrack {
  KartTrack(this.points, {this.width = 132});

  /// Generates a star-shaped (never self-intersecting) closed track.
  factory KartTrack.generate(int seed) {
    final math.Random r = math.Random(seed);
    final int k1 = 2 + r.nextInt(2), k2 = 3 + r.nextInt(3);
    final double p1 = r.nextDouble() * math.pi * 2, p2 = r.nextDouble() * math.pi * 2;
    final double a1 = 0.14 + r.nextDouble() * 0.12, a2 = 0.06 + r.nextDouble() * 0.08;
    const int n = 240;
    final List<V2> pts = <V2>[];
    for (int i = 0; i < n; i++) {
      final double t = i / n * math.pi * 2;
      final double rad = 1 + a1 * math.sin(k1 * t + p1) + a2 * math.sin(k2 * t + p2);
      pts.add(V2(math.cos(t) * 1150 * rad, math.sin(t) * 760 * rad));
    }
    return KartTrack(pts);
  }

  final List<V2> points;
  final double width;
  int get n => points.length;
  V2 at(int i) => points[((i % n) + n) % n];

  /// Unit direction of travel at sample [i].
  V2 dir(int i) {
    final V2 d = at(i + 1) - at(i - 1);
    final double l = d.len;
    return l == 0 ? const V2(1, 0) : d * (1 / l);
  }

  double get length {
    double s = 0;
    for (int i = 0; i < n; i++) {
      s += at(i).dist(at(i + 1));
    }
    return s;
  }

  /// Nearest sample to [p], searching around [hint] (or the whole track when hint < 0).
  int nearest(V2 p, [int hint = -1]) {
    int best = 0;
    double bd = double.infinity;
    if (hint < 0) {
      for (int i = 0; i < n; i++) {
        final double d = p.dist(points[i]);
        if (d < bd) {
          bd = d;
          best = i;
        }
      }
      return best;
    }
    for (int k = -14; k <= 14; k++) {
      final int i = ((hint + k) % n + n) % n;
      final double d = p.dist(points[i]);
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  double offTrack(V2 p, int idx) => math.max(0, p.dist(at(idx)) - width / 2);
}

enum KartItem { none, turbo, missile, shield, oil }

class Kart {
  Kart(this.seat, this.pos, this.heading);
  final int seat;
  V2 pos;
  double heading;
  double speed = 0;
  double steer = 0;
  bool drifting = false;
  int driftDir = 0;
  double driftCharge = 0;
  double boost = 0;
  double spin = 0;
  double shield = 0;
  KartItem item = KartItem.none;
  int idx = 0;
  int lap = 0;
  bool halfway = false;
  bool finished = false;
  double finishTime = 0;
  double slip = 0;

  /// Monotonic race progress in samples.
  int progress(int n) => lap * n + idx;
}

class Missile {
  Missile(this.owner, this.target, this.pos, this.idx);
  final int owner;
  final int target;
  V2 pos;
  int idx;
  double life = 6;
}

class OilSlick {
  OilSlick(this.pos);
  final V2 pos;
  double life = 18;
}

class ItemBox {
  ItemBox(this.pos);
  final V2 pos;
  double respawn = 0;
  bool get active => respawn <= 0;
}

class KartEvent {
  const KartEvent(this.kind, this.seat, [this.x = 0, this.y = 0, this.other = -1]);
  final String kind; // pickup, boost, hit, shield, lap, finish, drift
  final int seat;
  final double x, y;
  final int other;
}

class KartRace {
  KartRace({required this.seed, required this.racers, this.laps = 3, this.botSkill = const <double>[]}) {
    track = KartTrack.generate(seed);
    _r = math.Random(seed ^ 0x5bd1e995);
    final V2 d = track.dir(0);
    final V2 nrm = V2(-d.y, d.x);
    for (int i = 0; i < racers; i++) {
      final int row = i ~/ 2;
      final double side = (i.isEven ? -1 : 1) * 28.0;
      final V2 p = track.at(-4 - row * 3) + nrm * side;
      karts.add(Kart(i, p, math.atan2(d.y, d.x))..idx = track.nearest(p));
    }
    for (int s = 0; s < 4; s++) {
      final int i = (track.n * (s + 0.5) / 4).round();
      final V2 c = track.at(i), dd = track.dir(i);
      final V2 nn = V2(-dd.y, dd.x);
      for (int k = -1; k <= 1; k++) {
        boxes.add(ItemBox(c + nn * (k * 38.0)));
      }
    }
    for (int s = 0; s < 3; s++) {
      pads.add((track.n * (s + 0.25) / 3).round());
    }
  }

  final int seed;
  final int racers;
  final int laps;

  /// Per-seat bot skill 0..1 (seats without an entry are human).
  final List<double> botSkill;
  late final KartTrack track;
  late final math.Random _r;
  final List<Kart> karts = <Kart>[];
  final List<Missile> missiles = <Missile>[];
  final List<OilSlick> oils = <OilSlick>[];
  final List<ItemBox> boxes = <ItemBox>[];
  final List<int> pads = <int>[];
  final List<KartEvent> events = <KartEvent>[];
  double time = 0;
  double countdown = 3;
  final List<int> finishOrder = <int>[];

  static const double maxSpeed = 380;
  static const double kartR = 17;

  bool get started => countdown <= 0;
  bool get allFinished => karts.every((Kart k) => k.finished);

  bool isBot(int seat) => seat < botSkill.length && botSkill[seat] > 0;

  /// Race standings (index 0 = leader).
  List<Kart> standings() {
    final List<Kart> l = List<Kart>.of(karts);
    l.sort((Kart a, Kart b) {
      if (a.finished && b.finished) return a.finishTime.compareTo(b.finishTime);
      if (a.finished) return -1;
      if (b.finished) return 1;
      return b.progress(track.n).compareTo(a.progress(track.n));
    });
    return l;
  }

  int placeOf(int seat) => standings().indexWhere((Kart k) => k.seat == seat) + 1;

  /// Human input for [seat]: steer -1..1, drift held, use item pressed (edge).
  void input(int seat, double steer, bool drift, bool useItem) {
    final Kart k = karts[seat];
    k.steer = steer.clamp(-1.0, 1.0);
    if (drift && !k.drifting && k.speed > 160 && k.steer.abs() > 0.2) {
      k.drifting = true;
      k.driftDir = k.steer.sign.toInt();
      k.driftCharge = 0;
    } else if (!drift && k.drifting) {
      _endDrift(k);
    }
    if (useItem) this.useItem(seat);
  }

  void _endDrift(Kart k) {
    k.drifting = false;
    if (k.driftCharge > 1.6) {
      k.boost = math.max(k.boost, 1.1);
      events.add(KartEvent('boost', k.seat, k.pos.x, k.pos.y, 2));
    } else if (k.driftCharge > 0.8) {
      k.boost = math.max(k.boost, 0.6);
      events.add(KartEvent('boost', k.seat, k.pos.x, k.pos.y, 1));
    }
    k.driftCharge = 0;
  }

  void useItem(int seat) {
    final Kart k = karts[seat];
    switch (k.item) {
      case KartItem.none:
        return;
      case KartItem.turbo:
        k.boost = math.max(k.boost, 1.6);
        events.add(KartEvent('boost', seat, k.pos.x, k.pos.y, 3));
      case KartItem.shield:
        k.shield = 8;
        events.add(KartEvent('shield', seat, k.pos.x, k.pos.y));
      case KartItem.oil:
        final V2 back = V2(math.cos(k.heading), math.sin(k.heading)) * -34;
        oils.add(OilSlick(k.pos + back));
      case KartItem.missile:
        final List<Kart> st = standings();
        final int me = st.indexWhere((Kart x) => x.seat == seat);
        final Kart? target = me > 0 ? st[me - 1] : (st.length > 1 ? st[1] : null);
        if (target != null) missiles.add(Missile(seat, target.seat, k.pos, k.idx));
    }
    k.item = KartItem.none;
  }

  /// Applies a hit to [seat] (missile / oil / remote event). Shield absorbs it.
  void hit(int seat, {int by = -1}) {
    final Kart k = karts[seat];
    if (k.shield > 0) {
      k.shield = 0;
      events.add(KartEvent('shield_break', seat, k.pos.x, k.pos.y));
      return;
    }
    k.spin = 0.9;
    k.speed *= 0.25;
    k.drifting = false;
    k.boost = 0;
    events.add(KartEvent('hit', seat, k.pos.x, k.pos.y, by));
  }

  KartItem _roll(int place) {
    final double behind = racers <= 1 ? 0 : (place - 1) / (racers - 1);
    final double x = _r.nextDouble();
    if (x < 0.25 + behind * 0.25) return KartItem.turbo;
    if (x < 0.5 + behind * 0.2) return KartItem.missile;
    if (x < 0.78) return KartItem.shield;
    return KartItem.oil;
  }

  /// Advances the race. [simulate] = seats this phone simulates (all offline; own seat online).
  void step(double dt, {Set<int>? simulate}) {
    time += dt;
    if (countdown > 0) {
      countdown -= dt;
      return;
    }
    for (final Kart k in karts) {
      if (simulate != null && !simulate.contains(k.seat)) continue;
      if (isBot(k.seat) && !k.finished) _bot(k, dt);
      _physics(k, dt);
    }
    // kart-kart bumps
    for (int i = 0; i < karts.length; i++) {
      for (int j = i + 1; j < karts.length; j++) {
        final Kart a = karts[i], b = karts[j];
        final V2 d = b.pos - a.pos;
        final double l = d.len;
        if (l > 0 && l < kartR * 2) {
          final V2 push = d * ((kartR * 2 - l) / l * 0.5);
          if (simulate == null || simulate.contains(a.seat)) a.pos = a.pos - push;
          if (simulate == null || simulate.contains(b.seat)) b.pos = b.pos + push;
        }
      }
    }
    for (final ItemBox b in boxes) {
      if (!b.active) {
        b.respawn -= dt;
        continue;
      }
      for (final Kart k in karts) {
        if (simulate != null && !simulate.contains(k.seat)) continue;
        if (k.pos.dist(b.pos) < 30) {
          b.respawn = 3;
          if (k.item == KartItem.none) {
            k.item = _roll(placeOf(k.seat));
            events.add(KartEvent('pickup', k.seat, b.pos.x, b.pos.y));
          }
          break;
        }
      }
    }
    for (int i = missiles.length - 1; i >= 0; i--) {
      final Missile m = missiles[i];
      m.life -= dt;
      final Kart t = karts[m.target];
      final V2 aim = m.pos.dist(t.pos) < 220 ? t.pos : track.at(m.idx + 6);
      final V2 d = aim - m.pos;
      final double l = d.len;
      if (l > 0) m.pos = m.pos + d * (math.min(l, 640 * dt) / l);
      m.idx = track.nearest(m.pos, m.idx);
      if (m.pos.dist(t.pos) < 24) {
        missiles.removeAt(i);
        events.add(KartEvent('missile_hit', t.seat, t.pos.x, t.pos.y, m.owner));
        if (simulate == null || simulate.contains(t.seat)) hit(t.seat, by: m.owner);
        continue;
      }
      if (m.life <= 0) missiles.removeAt(i);
    }
    for (int i = oils.length - 1; i >= 0; i--) {
      final OilSlick o = oils[i];
      o.life -= dt;
      bool used = false;
      for (final Kart k in karts) {
        if (simulate != null && !simulate.contains(k.seat)) continue;
        if (k.spin <= 0 && k.pos.dist(o.pos) < 26) {
          hit(k.seat);
          used = true;
          break;
        }
      }
      if (used || o.life <= 0) oils.removeAt(i);
    }
  }

  void _physics(Kart k, double dt) {
    final int n = track.n;
    if (k.spin > 0) {
      k.spin -= dt;
      k.heading += dt * 14;
      k.speed *= math.pow(0.2, dt).toDouble();
    } else {
      final double grip = math.min(1, k.speed / 140);
      double turn = 2.5 * k.steer * grip;
      if (k.drifting) {
        turn = (k.driftDir * 1.55 + k.steer * 0.9) * grip;
        k.driftCharge += dt * (0.6 + k.steer.abs() * 0.8);
        if (k.speed < 120) _endDrift(k);
      }
      k.heading += turn * dt;
      double top = maxSpeed * (k.finished ? 0.6 : 1);
      if (k.boost > 0) {
        k.boost -= dt;
        top *= 1.45;
      }
      if (track.offTrack(k.pos, k.idx) > 4) top *= 0.45;
      final double acc = k.speed < top ? 260 : -420;
      k.speed = (k.speed + acc * dt).clamp(0, math.max(top, k.speed - 420 * dt));
    }
    k.slip = k.drifting ? rtApproach(k.slip, k.driftDir * 0.45, dt * 6) : rtApproach(k.slip, 0, dt * 6);
    final double mv = k.heading - k.slip;
    k.pos = k.pos + V2(math.cos(mv), math.sin(mv)) * (k.speed * dt);
    // keep inside the outer wall
    final int ni = track.nearest(k.pos, k.idx);
    final V2 c = track.at(ni);
    final V2 off = k.pos - c;
    final double wall = track.width / 2 + 70;
    if (off.len > wall) {
      k.pos = c + off * (wall / off.len);
      k.speed *= 0.6;
    }
    if (k.shield > 0) k.shield -= dt;
    // boost pads
    for (final int p in pads) {
      if ((ni - p).abs() <= 1 && k.pos.dist(track.at(p)) < track.width * 0.35 && k.boost < 0.5) {
        k.boost = 0.9;
        events.add(KartEvent('pad', k.seat, k.pos.x, k.pos.y));
      }
    }
    // progress / laps (must pass halfway before the line counts)
    if (ni > n * 0.45 && ni < n * 0.55) k.halfway = true;
    if (k.idx > n * 0.85 && ni < n * 0.15 && k.halfway) {
      k.lap++;
      k.halfway = false;
      events.add(KartEvent('lap', k.seat, k.pos.x, k.pos.y, k.lap));
      if (k.lap >= laps && !k.finished) finish(k.seat, time);
    } else if (k.idx < n * 0.15 && ni > n * 0.85 && k.lap > 0) {
      k.lap--; // drove backwards over the line
      k.halfway = true;
    }
    k.idx = ni;
  }

  void finish(int seat, double at) {
    final Kart k = karts[seat];
    if (k.finished) return;
    k.finished = true;
    k.finishTime = at;
    finishOrder.add(seat);
    events.add(KartEvent('finish', seat, k.pos.x, k.pos.y, finishOrder.length));
  }

  void _bot(Kart k, double dt) {
    final double skill = botSkill[k.seat];
    final int look = 4 + (k.speed / 90).round();
    final V2 target = track.at(k.idx + look);
    final double want = math.atan2(target.y - k.pos.y, target.x - k.pos.x);
    double diff = want - k.heading;
    while (diff > math.pi) {
      diff -= math.pi * 2;
    }
    while (diff < -math.pi) {
      diff += math.pi * 2;
    }
    k.steer = (diff * 3.2).clamp(-1.0, 1.0);
    // rubber band + skill
    final int place = placeOf(k.seat);
    final double cap = 0.82 + skill * 0.17 + (place > 1 ? 0.03 : 0);
    if (k.speed > maxSpeed * cap && k.boost <= 0) k.speed = maxSpeed * cap;
    // drift on long corners
    if (skill > 0.5 && !k.drifting && k.speed > 240 && diff.abs() > 0.22) {
      k.drifting = true;
      k.driftDir = diff.sign.toInt();
      k.driftCharge = 0;
    } else if (k.drifting && (diff.abs() < 0.12 || k.driftCharge > 1.7)) {
      _endDrift(k);
    }
    if (k.item != KartItem.none && _r.nextDouble() < dt * (0.4 + skill)) useItem(k.seat);
  }
}

double rtApproach(double cur, double target, double k) => cur + (target - cur) * k.clamp(0.0, 1.0);
