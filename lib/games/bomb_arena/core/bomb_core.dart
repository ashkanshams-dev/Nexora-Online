import 'dart:collection';
import 'dart:math' as math;

/// Pure-Dart Bomb Arena (Bomberman style) for 2-4 players: bombs, chain reactions, destructible crates,
/// power-ups (range, extra bomb, speed, trap) and stun traps. Last player alive wins.
/// Grid is [w]x[h]; tile chars: '#' wall, 'c' crate, '.' floor.

enum Pu { range, bomb, speed, trap }

class BPlayer {
  BPlayer(this.seat, this.x, this.y);
  final int seat;
  double x, y; // tile units, centre of tile = i + 0.5
  double dx = 0, dy = 0;
  int range = 2;
  int maxBombs = 1;
  double speed = 3.4;
  int traps = 0;
  bool alive = true;
  double stun = 0;
  int kills = 0;
  double outAt = 0;
  int get tx => x.floor();
  int get ty => y.floor();
}

class Bomb {
  Bomb(this.owner, this.tx, this.ty, this.range, {this.fuse = 2.4});
  final int owner;
  final int tx, ty, range;
  double fuse;
  final Set<int> passable = <int>{}; // seats standing on it when placed
}

class Flame {
  Flame(this.tx, this.ty, this.dir, {this.life = 0.55});
  final int tx, ty;
  final int dir; // 0 centre, 1 horizontal, 2 vertical
  double life;
}

class Trap {
  Trap(this.owner, this.tx, this.ty);
  final int owner;
  final int tx, ty;
}

class BEvent {
  const BEvent(this.kind, this.x, this.y, [this.seat = -1]);
  final String kind; // place, boom, crate, pickup, out, trap, stun
  final double x, y;
  final int seat;
}

class BombArena {
  BombArena({required this.seed, required this.count, this.botSkill = const <double>[]}) {
    final math.Random r = math.Random(seed);
    grid = List<List<String>>.generate(h, (int y) => List<String>.generate(w, (int x) {
          if (x == 0 || y == 0 || x == w - 1 || y == h - 1 || (x.isEven && y.isEven)) return '#';
          return r.nextDouble() < 0.62 ? 'c' : '.';
        }));
    final List<List<int>> spawns = <List<int>>[<int>[1, 1], <int>[w - 2, h - 2], <int>[w - 2, 1], <int>[1, h - 2]];
    for (int i = 0; i < count; i++) {
      final int sx = spawns[i][0], sy = spawns[i][1];
      for (final List<int> d in <List<int>>[<int>[0, 0], <int>[1, 0], <int>[-1, 0], <int>[0, 1], <int>[0, -1], <int>[2, 0], <int>[-2, 0], <int>[0, 2], <int>[0, -2]]) {
        final int x = sx + d[0], y = sy + d[1];
        if (x > 0 && y > 0 && x < w - 1 && y < h - 1 && grid[y][x] == 'c') grid[y][x] = '.';
      }
      players.add(BPlayer(i, sx + 0.5, sy + 0.5));
    }
    _r = math.Random(seed ^ 0x1234567);
  }

  static const int w = 13, h = 11;
  final int seed;
  final int count;
  final List<double> botSkill;
  late final List<List<String>> grid;
  late final math.Random _r;
  final List<BPlayer> players = <BPlayer>[];
  final List<Bomb> bombs = <Bomb>[];
  final List<Flame> flames = <Flame>[];
  final Map<int, Pu> powerups = <int, Pu>{};
  final List<Trap> traps = <Trap>[];
  final List<BEvent> events = <BEvent>[];
  final List<int> outOrder = <int>[];
  double time = 0;
  double countdown = 3;
  static const double timeLimit = 150;

  bool isBot(int s) => s < botSkill.length && botSkill[s] > 0;
  int key(int x, int y) => y * w + x;
  int aliveCount() => players.where((BPlayer p) => p.alive).length;
  bool get over => (count > 1 ? aliveCount() <= 1 : aliveCount() == 0) || time >= timeLimit;

  bool solid(int x, int y, {int? forSeat}) {
    if (x < 0 || y < 0 || x >= w || y >= h) return true;
    if (grid[y][x] != '.') return true;
    for (final Bomb b in bombs) {
      if (b.tx == x && b.ty == y && (forSeat == null || !b.passable.contains(forSeat))) return true;
    }
    return false;
  }

  Bomb? bombAt(int x, int y) {
    for (final Bomb b in bombs) {
      if (b.tx == x && b.ty == y) return b;
    }
    return null;
  }

  /// Ranking best → worst.
  List<int> ranking() {
    final List<BPlayer> alive = players.where((BPlayer p) => p.alive).toList()
      ..sort((BPlayer a, BPlayer b) => b.kills.compareTo(a.kills));
    return <int>[...alive.map((BPlayer p) => p.seat), ...outOrder.reversed];
  }

  void input(int seat, double dx, double dy) {
    final BPlayer p = players[seat];
    p.dx = dx;
    p.dy = dy;
  }

  bool placeBomb(int seat) {
    final BPlayer p = players[seat];
    if (!p.alive || p.stun > 0) return false;
    if (bombs.where((Bomb b) => b.owner == seat).length >= p.maxBombs) return false;
    if (bombAt(p.tx, p.ty) != null) return false;
    final Bomb b = Bomb(seat, p.tx, p.ty, p.range);
    for (final BPlayer q in players) {
      if (q.alive && q.tx == p.tx && q.ty == p.ty) b.passable.add(q.seat);
    }
    bombs.add(b);
    events.add(BEvent('place', p.tx + 0.5, p.ty + 0.5, seat));
    return true;
  }

  bool placeTrap(int seat) {
    final BPlayer p = players[seat];
    if (!p.alive || p.traps <= 0) return false;
    if (traps.any((Trap t) => t.tx == p.tx && t.ty == p.ty)) return false;
    p.traps--;
    traps.add(Trap(seat, p.tx, p.ty));
    events.add(BEvent('trap', p.tx + 0.5, p.ty + 0.5, seat));
    return true;
  }

  void step(double dt) {
    if (countdown > 0) {
      countdown -= dt;
      return;
    }
    time += dt;
    for (final BPlayer p in players) {
      if (!p.alive) continue;
      if (isBot(p.seat)) _bot(p, dt);
      _move(p, dt);
    }
    for (int i = bombs.length - 1; i >= 0; i--) {
      if (i >= bombs.length) continue;
      final Bomb b = bombs[i];
      b.passable.removeWhere((int s) => players[s].tx != b.tx || players[s].ty != b.ty);
      b.fuse -= dt;
      if (b.fuse <= 0) _explode(b);
    }
    for (int i = flames.length - 1; i >= 0; i--) {
      flames[i].life -= dt;
      if (flames[i].life <= 0) flames.removeAt(i);
    }
    for (final Flame f in flames) {
      for (final BPlayer p in players) {
        if (p.alive && p.tx == f.tx && p.ty == f.ty) _kill(p, f);
      }
    }
  }

  void _kill(BPlayer p, Flame f) {
    p.alive = false;
    p.outAt = time;
    outOrder.add(p.seat);
    events.add(BEvent('out', p.x, p.y, p.seat));
  }

  void eliminate(int seat) {
    final BPlayer p = players[seat];
    if (!p.alive) return;
    p.alive = false;
    p.outAt = time;
    outOrder.add(seat);
    events.add(BEvent('out', p.x, p.y, seat));
  }

  void _explode(Bomb b) {
    bombs.remove(b);
    events.add(BEvent('boom', b.tx + 0.5, b.ty + 0.5, b.owner));
    flames.add(Flame(b.tx, b.ty, 0));
    for (final List<int> d in <List<int>>[<int>[1, 0], <int>[-1, 0], <int>[0, 1], <int>[0, -1]]) {
      for (int k = 1; k <= b.range; k++) {
        final int x = b.tx + d[0] * k, y = b.ty + d[1] * k;
        if (x < 0 || y < 0 || x >= w || y >= h || grid[y][x] == '#') break;
        flames.add(Flame(x, y, d[0] != 0 ? 1 : 2));
        if (grid[y][x] == 'c') {
          grid[y][x] = '.';
          events.add(BEvent('crate', x + 0.5, y + 0.5));
          if (_r.nextDouble() < 0.34) powerups[key(x, y)] = Pu.values[_r.nextInt(_r.nextDouble() < 0.15 ? 4 : 3)];
          break;
        }
        powerups.remove(key(x, y));
        traps.removeWhere((Trap t) => t.tx == x && t.ty == y);
        final Bomb? other = bombAt(x, y);
        if (other != null) other.fuse = math.min(other.fuse, 0.05);
      }
    }
    // credit kills to the bomb owner
    for (final BPlayer p in players) {
      if (p.alive && flames.any((Flame f) => f.tx == p.tx && f.ty == p.ty) && p.seat != b.owner) players[b.owner].kills++;
    }
  }

  void _move(BPlayer p, double dt) {
    if (p.stun > 0) {
      p.stun -= dt;
      return;
    }
    double dx = p.dx, dy = p.dy;
    if (dx == 0 && dy == 0) return;
    // dominant axis movement with corner assist (snap the other axis toward the lane centre)
    final double sp = p.speed * dt;
    if (dx.abs() >= dy.abs()) {
      dx = dx.sign;
      final int nx = (p.x + dx * (0.5 + sp)).floor();
      final int lane = p.y.floor();
      if (!solid(nx, lane, forSeat: p.seat) || nx == p.tx) {
        p.x += dx * sp;
        p.y += ((lane + 0.5) - p.y).clamp(-sp, sp);
      } else {
        // try to slide around the corner
        final double off = p.y - (lane + 0.5);
        final int alt = off > 0.15 ? lane + 1 : (off < -0.15 ? lane - 1 : lane);
        if (alt != lane && !solid(nx, alt, forSeat: p.seat)) p.y += (alt + 0.5 - p.y).clamp(-sp, sp);
        p.x += ((p.tx + 0.5) - p.x).clamp(-sp, sp);
      }
    } else {
      dy = dy.sign;
      final int ny = (p.y + dy * (0.5 + sp)).floor();
      final int lane = p.x.floor();
      if (!solid(lane, ny, forSeat: p.seat) || ny == p.ty) {
        p.y += dy * sp;
        p.x += ((lane + 0.5) - p.x).clamp(-sp, sp);
      } else {
        final double off = p.x - (lane + 0.5);
        final int alt = off > 0.15 ? lane + 1 : (off < -0.15 ? lane - 1 : lane);
        if (alt != lane && !solid(alt, ny, forSeat: p.seat)) p.x += (alt + 0.5 - p.x).clamp(-sp, sp);
        p.y += ((p.ty + 0.5) - p.y).clamp(-sp, sp);
      }
    }
    final Pu? pu = powerups.remove(key(p.tx, p.ty));
    if (pu != null) {
      switch (pu) {
        case Pu.range:
          p.range = math.min(7, p.range + 1);
        case Pu.bomb:
          p.maxBombs = math.min(6, p.maxBombs + 1);
        case Pu.speed:
          p.speed = math.min(5.6, p.speed + 0.45);
        case Pu.trap:
          p.traps = math.min(3, p.traps + 1);
      }
      events.add(BEvent('pickup', p.x, p.y, p.seat));
    }
    for (int i = traps.length - 1; i >= 0; i--) {
      final Trap t = traps[i];
      if (t.owner != p.seat && t.tx == p.tx && t.ty == p.ty) {
        traps.removeAt(i);
        p.stun = 1.6;
        events.add(BEvent('stun', p.x, p.y, p.seat));
      }
    }
  }

  // ------------------------------------------------------------------ bots
  final Map<int, double> _think = <int, double>{};
  final Map<int, List<int>> _goal = <int, List<int>>{};

  /// Seconds until each tile is hit by a flame (∞ = safe).
  List<double> dangerMap({Bomb? extra}) {
    final List<double> d = List<double>.filled(w * h, double.infinity);
    final List<Bomb> all = <Bomb>[...bombs, if (extra != null) extra];
    for (final Bomb b in all) {
      void mark(int x, int y) => d[key(x, y)] = math.min(d[key(x, y)], b.fuse);
      mark(b.tx, b.ty);
      for (final List<int> dd in <List<int>>[<int>[1, 0], <int>[-1, 0], <int>[0, 1], <int>[0, -1]]) {
        for (int k = 1; k <= b.range; k++) {
          final int x = b.tx + dd[0] * k, y = b.ty + dd[1] * k;
          if (grid[y][x] == '#') break;
          mark(x, y);
          if (grid[y][x] == 'c') break;
        }
      }
    }
    for (final Flame f in flames) {
      d[key(f.tx, f.ty)] = 0;
    }
    return d;
  }

  /// BFS from the player's tile; returns the path (list of tile keys) to the first tile matching [goal].
  List<int>? _bfs(BPlayer p, bool Function(int x, int y, int dist) goal, List<double> danger) {
    final int start = key(p.tx, p.ty);
    final Map<int, int> prev = <int, int>{start: -1};
    final Queue<int> q = Queue<int>()..add(start);
    final Map<int, int> dist = <int, int>{start: 0};
    while (q.isNotEmpty) {
      final int c = q.removeFirst();
      final int cx = c % w, cy = c ~/ w;
      if (goal(cx, cy, dist[c]!)) {
        final List<int> path = <int>[];
        int k = c;
        while (k != start && k != -1) {
          path.add(k);
          k = prev[k]!;
        }
        return path.reversed.toList();
      }
      for (final List<int> d in <List<int>>[<int>[1, 0], <int>[-1, 0], <int>[0, 1], <int>[0, -1]]) {
        final int nx = cx + d[0], ny = cy + d[1];
        final int nk = key(nx, ny);
        if (prev.containsKey(nk) || solid(nx, ny, forSeat: p.seat)) continue;
        final int nd = dist[c]! + 1;
        // don't walk into a tile that explodes before/while we pass it
        final double arrive = nd / p.speed;
        if (danger[nk] < arrive + 0.35 && danger[nk] > arrive - 0.7) continue;
        if (danger[nk] <= 0.05) continue;
        prev[nk] = c;
        dist[nk] = nd;
        q.add(nk);
      }
    }
    return null;
  }

  void _bot(BPlayer p, double dt) {
    final double skill = botSkill[p.seat];
    if (p.stun > 0) return;
    final double t = (_think[p.seat] ?? 0) - dt;
    _think[p.seat] = t;
    final List<double> danger = dangerMap();
    final bool inDanger = danger[key(p.tx, p.ty)].isFinite;
    if (t <= 0 || inDanger) {
      _think[p.seat] = 0.12 + (1 - skill) * 0.35;
      List<int>? path;
      if (inDanger) {
        path = _bfs(p, (int x, int y, int d) => danger[key(x, y)].isInfinite, danger);
      } else {
        // bomb opportunity: crate or enemy in blast line, and an escape exists
        final bool canBomb = bombs.where((Bomb b) => b.owner == p.seat).length < p.maxBombs && bombAt(p.tx, p.ty) == null;
        if (canBomb && _worthBombing(p, skill)) {
          final Bomb hypo = Bomb(p.seat, p.tx, p.ty, p.range);
          final List<double> d2 = dangerMap(extra: hypo);
          final List<int>? esc = _bfs(p, (int x, int y, int d) => d2[key(x, y)].isInfinite, d2);
          if (esc != null && esc.length <= 5) {
            placeBomb(p.seat);
            if (p.traps > 0 && _r.nextDouble() < 0.3) placeTrap(p.seat);
            path = esc;
          }
        }
        path ??= _bfs(p, (int x, int y, int d) {
          if (d == 0) return false;
          if (powerups.containsKey(key(x, y))) return true;
          for (final BPlayer o in players) {
            if (o.alive && o.seat != p.seat && skill > 0.5 && (o.tx - x).abs() + (o.ty - y).abs() <= 1) return true;
          }
          for (final List<int> dd in <List<int>>[<int>[1, 0], <int>[-1, 0], <int>[0, 1], <int>[0, -1]]) {
            if (grid[y + dd[1]][x + dd[0]] == 'c') return true;
          }
          return false;
        }, danger);
      }
      _goal[p.seat] = path ?? <int>[];
    }
    final List<int> g = _goal[p.seat] ?? <int>[];
    while (g.isNotEmpty && g.first == key(p.tx, p.ty) && ((p.x - p.tx - 0.5).abs() < 0.15 && (p.y - p.ty - 0.5).abs() < 0.15)) {
      g.removeAt(0);
    }
    if (g.isEmpty) {
      p.dx = 0;
      p.dy = 0;
      return;
    }
    final int gx = g.first % w, gy = g.first ~/ w;
    p.dx = (gx + 0.5 - p.x).abs() > 0.08 ? (gx + 0.5 - p.x).sign : 0;
    p.dy = (gy + 0.5 - p.y).abs() > 0.08 ? (gy + 0.5 - p.y).sign : 0;
    if (p.dx != 0 && p.dy != 0) {
      // finish the current axis first
      if ((p.y - p.ty - 0.5).abs() > 0.08) {
        p.dx = 0;
      } else {
        p.dy = 0;
      }
    }
  }

  bool _worthBombing(BPlayer p, double skill) {
    for (final List<int> d in <List<int>>[<int>[1, 0], <int>[-1, 0], <int>[0, 1], <int>[0, -1]]) {
      for (int k = 1; k <= p.range; k++) {
        final int x = p.tx + d[0] * k, y = p.ty + d[1] * k;
        if (grid[y][x] == '#') break;
        if (grid[y][x] == 'c') {
          if (k == 1) return true;
          break;
        }
        for (final BPlayer o in players) {
          if (o.alive && o.seat != p.seat && o.tx == x && o.ty == y && _r.nextDouble() < 0.3 + skill * 0.6) return true;
        }
      }
    }
    return false;
  }

  // ------------------------------------------------------------------ network snapshot
  Map<String, dynamic> snapshot() => <String, dynamic>{
        'g': grid.map((List<String> r) => r.join()).join(),
        'p': <List<num>>[
          for (final BPlayer p in players)
            <num>[(p.x * 100).round(), (p.y * 100).round(), p.alive ? 1 : 0, p.stun > 0 ? 1 : 0, p.range, p.maxBombs, p.traps, p.kills]
        ],
        'b': <List<num>>[for (final Bomb b in bombs) <num>[b.tx, b.ty, (b.fuse * 100).round(), b.range, b.owner]],
        'f': <List<num>>[for (final Flame f in flames) <num>[f.tx, f.ty, f.dir, (f.life * 100).round()]],
        'u': <String, int>{for (final MapEntry<int, Pu> e in powerups.entries) '${e.key}': e.value.index},
        't': (time * 100).round(),
        'o': outOrder,
      };

  void applySnapshot(Map<String, dynamic> s, {int? keepSeat}) {
    final String g = '${s['g']}';
    if (g.length == w * h) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final String c = g[y * w + x];
          if (grid[y][x] == 'c' && c == '.') events.add(BEvent('crate', x + 0.5, y + 0.5));
          grid[y][x] = c;
        }
      }
    }
    final List<dynamic> ps = s['p'] as List<dynamic>;
    for (int i = 0; i < ps.length && i < players.length; i++) {
      final List<dynamic> v = ps[i] as List<dynamic>;
      final BPlayer p = players[i];
      final bool alive = v[2] == 1;
      if (p.alive && !alive) events.add(BEvent('out', p.x, p.y, p.seat));
      p
        ..x = (v[0] as num) / 100
        ..y = (v[1] as num) / 100
        ..alive = alive
        ..stun = v[3] == 1 ? 0.2 : 0
        ..range = (v[4] as num).toInt()
        ..maxBombs = (v[5] as num).toInt()
        ..traps = (v[6] as num).toInt()
        ..kills = (v[7] as num).toInt();
    }
    final int before = bombs.length;
    bombs
      ..clear()
      ..addAll((s['b'] as List<dynamic>).map((dynamic e) {
        final List<dynamic> v = e as List<dynamic>;
        return Bomb((v[4] as num).toInt(), (v[0] as num).toInt(), (v[1] as num).toInt(), (v[3] as num).toInt(),
            fuse: (v[2] as num) / 100);
      }));
    final List<dynamic> fs = s['f'] as List<dynamic>;
    if (fs.isNotEmpty && flames.isEmpty && before > 0) {
      final List<dynamic> c = fs.first as List<dynamic>;
      events.add(BEvent('boom', (c[0] as num) + 0.5, (c[1] as num) + 0.5));
    }
    flames
      ..clear()
      ..addAll(fs.map((dynamic e) {
        final List<dynamic> v = e as List<dynamic>;
        return Flame((v[0] as num).toInt(), (v[1] as num).toInt(), (v[2] as num).toInt(), life: (v[3] as num) / 100);
      }));
    powerups
      ..clear()
      ..addAll(((s['u'] as Map?) ?? const <String, int>{})
          .map((dynamic k, dynamic v) => MapEntry<int, Pu>(int.parse('$k'), Pu.values[(v as num).toInt()])));
    time = ((s['t'] as num?) ?? 0) / 100;
    countdown = time > 0 ? 0 : countdown;
    outOrder
      ..clear()
      ..addAll(((s['o'] as List?) ?? const <dynamic>[]).map((dynamic e) => (e as num).toInt()));
  }
}
