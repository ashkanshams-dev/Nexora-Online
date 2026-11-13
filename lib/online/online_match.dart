// Online match — port of src/online/OnlineMatch.tsx (v7 netcode, wire-compatible with the RN client):
//  HOST   runs the authoritative simulation; every shot is broadcast once as 'go' (quantised flick on the 1/16 grid
//         + exact pre-shot state); snapshots 's' at 10 Hz while moving / 2 Hz at rest carry scalars + a keyframe.
//  OTHERS replay the shot locally with the bit-identical engine (lockstep), the shooter predicts instantly (zero
//         input delay) and only re-syncs if the host disagrees; keyframes every 24 ticks catch drift; spectators
//         that joined mid-shot fall back to snapshot interpolation. Control rotates inside a team; absent → bot.
import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/data.dart';
import '../game/engine.dart';
import '../game/match_game.dart';
import '../net/discs.dart';
import '../net/supabase.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/score_bug.dart';
import '../ui/theme.dart';
import 'link.dart';
import 'room_widgets.dart';
import 'ui.dart';

const KEY_EVERY = 24;
const TAU = math.pi * 2;

class OnlineOutcome {
  final String matchId;
  final List<int> score;
  final int winner; // -1 draw
  final int? ratingDelta, myTeam;
  final List<Team> teams;
  final List<String> names;
  final bool reported, ranked;
  const OnlineOutcome(this.matchId, this.score, this.winner, this.ratingDelta, this.myTeam, this.teams, this.names, this.reported, this.ranked);
}

// ---------- wire format (identical to the TS encEv/decEv) ----------
List<int> encEv(EngineEvent e) => switch (e) {
      EvHit(:final ball, :final power) => [0, ball ? 1 : 0, jsRound(power * 100).toInt()],
      EvWall(:final power) => [1, jsRound(power * 100).toInt()],
      EvPost(:final power) => [2, jsRound(power * 100).toInt()],
      EvGoal(:final team, :final nogoal) => [3, team, nogoal ? 1 : 0],
      EvTurn(:final team) => [4, team],
      EvShot(:final team) => [5, team],
      EvEnd(:final score) => [6, score[0], score[1]],
      EvClock() => [7],
    };
EngineEvent decEv(List a) {
  int i(int k) => (a[k] as num).toInt();
  return switch (i(0)) {
    0 => EvHit(i(1) == 1, i(2) / 100),
    1 => EvWall(i(1) / 100),
    2 => EvPost(i(1) / 100),
    3 => EvGoal(i(1), i(2) == 1),
    4 => EvTurn(i(1)),
    5 => EvShot(i(1)),
    6 => EvEnd([i(1), i(2)]),
    _ => const EvClock(),
  };
}

MatchCfg cfgFromRoom(JRow room) {
  final s = (room['settings'] as Map?) ?? const {};
  double n(Object? v, double d) => v is num ? v.toDouble() : double.tryParse('$v') ?? d;
  final time = math.max(0.0, n(s['time'], 0)), goals = math.max(1, n(s['goals'], 3).toInt());
  return MatchCfg(
    field: n(s['field'], 0).toInt().clamp(0, FIELDS.length - 1), ball: n(s['ball'], 0).toInt().clamp(0, 35), forms: [0, 0], ai: false, aiLvl: 1,
    limit: time > 0 ? 99 : goals, matchTime: time, turnTime: s['turn'] == 0 ? 0 : math.max(5, n(s['turn'], 15)), vip: [false, false], first: 0,
  );
}

String ruleLabel(Map? s) => (s?['time'] is num && (s!['time'] as num) > 0) ? '${fa(((s['time'] as num) / 60).round())} دقیقه' : 'تا ${fa((s?['goals'] as num?)?.toInt() ?? 3)} گل';
String discOf(JRow? p) => (p?['disc_id'] ?? (p?['profiles'] as Map?)?['equipped_disc'] ?? (p?['profiles'] as Map?)?['avatar'] ?? 'club0') as String;
List<JRow> teamOf(List<JRow> players, int t) => players.where((p) => p['role'] == 'player' && p['team'] == t).toList()..sort((a, b) => ri(a, 'slot').compareTo(ri(b, 'slot')));

class _Snap {
  final Map<String, dynamic> m;
  _Snap(this.m);
  int get q => ri(m, 'q');
  int get ts => ri(m, 'ts');
  int get hz => ri(m, 'hz', 12);
  Phase get ph => Phase.values.byName(m['ph'] as String);
  int get tu => ri(m, 'tu');
  List get sc => m['sc'] as List;
  int get n => ri(m, 'n');
  List get p => m['p'] as List;
  List get R => m['R'] as List;
  List get ev => m['ev'] as List? ?? const [];
  bool get lockstep => m['ep'] is num;
  int get ep => ri(m, 'ep');
  int get tk => ri(m, 'tk');
  int get mv => ri(m, 'mv');
  List? get ps => m['ps'] as List?;
  String? get c => m['c'] as String?;
}

class _Pred {
  final int n, b, dx, dy;
  final num pw, ac;
  const _Pred(this.n, this.b, this.dx, this.dy, this.pw, this.ac);
}

class _Replay {
  final int ep;
  int? endTk;
  _Pred? pred;
  final int at;
  _Replay(this.ep, this.pred, this.at);
}

class OnlineMatch extends StatefulWidget {
  final RoomLink link;
  final String matchId;
  final void Function(OnlineOutcome o) onFinish;
  final void Function(String why) onExit;
  final void Function(String m, [String k]) toast;
  final bool fx;
  const OnlineMatch({super.key, required this.link, required this.matchId, required this.onFinish, required this.onExit, required this.toast, this.fx = true});
  @override
  State<OnlineMatch> createState() => _OnlineMatchStateImpl();
}

class _H {
  int s0 = 0, s1 = 0, turn = 0;
  String clock = '';
  double tl = 1;
  bool sudden = false, wait = false;
  String? ctrl;
  Phase phase = Phase.aim;
  bool same(_H o) => o.s0 == s0 && o.s1 == s1 && o.turn == turn && o.clock == clock && (o.tl - tl).abs() <= .02 && o.sudden == sudden && o.ctrl == ctrl && o.phase == phase && o.wait == wait;
}

class _OnlineMatchStateImpl extends State<OnlineMatch> with TickerProviderStateMixin {
  RoomLink get link => widget.link;
  late final JRow room0 = link.value.room!;
  late final bool isHost = room0['host'] == link.me;
  late final MatchCfg cfg;
  late final Engine eng;
  late final MatchGame game;
  late final int? myTeam;
  late final List<String> names;
  late final List<Team> teams;
  late final bool ranked = room0['ranked'] == true;
  bool get flipped => myTeam == 1;
  final hud = ValueNotifier(_H());
  bool quit = false, chat = false;
  late final AnimationController banner = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  (String, String, Color) bText = ('', '', C.gold);
  String done = 'no';
  VoidCallback? _unsub;
  int tickAt = -1;
  final t0 = DateTime.now().millisecondsSinceEpoch;

  // host state
  final List<int> turnCount = [0, 0];
  int seq = 0, lastSend = 0, q = 0, lastAim = 0, lastKf = 0;
  String? hctrl;
  List<List<int>> evs = [];
  // client state
  final List<_Snap> buf = [], pend = [];
  final List<(int, int)> offs = [];
  final List<(int, int, List)> kfs = [];
  int applied = -1, lastRecv = DateTime.now().millisecondsSinceEpoch, pendingShot = 0, endAt = 0, cseq = 0, goalEp = -1, lastQ = -1, waitGo = 0;
  ({int winner, int rd, List<int> score, bool ok})? res;
  List<double>? prev;
  String? cctrl;
  bool got = false, interp = false;
  _Replay? replay;
  // coach
  bool cMine = false, cTouched = false;
  double cPower = 0;

  static int now() => DateTime.now().millisecondsSinceEpoch;
  List<JRow> get players => link.value.players;
  Map<String, String> get online => link.value.online;
  String nameOf(String? uid) => uid == null ? 'ربات' : ((players.where((p) => p['user_id'] == uid).firstOrNull?['profiles'] as Map?)?['username'] as String? ?? '…');

  @override
  void initState() {
    super.initState();
    final ps = players;
    cfg = cfgFromRoom(room0);
    cfg.stats = [discStats(discOf(teamOf(ps, 0).firstOrNull)), discStats(discOf(teamOf(ps, 1).firstOrNull))];
    eng = Engine(cfg)..keyEvery = KEY_EVERY;
    var h = 2166136261;
    for (final c in widget.matchId.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF; // Math.imul
    }
    eng.seed = h;
    eng.follower = !isHost;
    final t0p = teamOf(ps, 0), t1p = teamOf(ps, 1);
    final meP = ps.where((p) => p['user_id'] == link.me).firstOrNull;
    myTeam = meP?['role'] == 'player' && (meP?['team'] == 0 || meP?['team'] == 1) ? meP!['team'] as int : null;
    String nm(List<JRow> t, String d) => '${(t.firstOrNull?['profiles'] as Map?)?['username'] ?? d}${t.length > 1 ? ' +${fa(t.length - 1)}' : ''}';
    names = [nm(t0p, 'آبی'), nm(t1p, 'قرمز')];
    teams = [teamOfAvatar(discOf(t0p.firstOrNull)), teamOfAvatar(discOf(t1p.firstOrNull))];
    hud.value.wait = !isHost;
    if (isHost) {
      eng.onFire = (b, dx, dy, hu, sq, pre) {
        lastKf = 0;
        final st = cfg.stats?[b.team] ?? const DiscStats(5, 5);
        link.sendGame({
          'k': 'go', 'ep': eng.epoch + 1, 'n': seq, 'b': b.id, 'dx': jsRound(dx * 16).toInt(), 'dy': jsRound(dy * 16).toInt(), 'hu': hu ? 1 : 0, 'sq': sq,
          'st': pre, 'sh': eng.shots, 'sno': eng.shotNo, 'tu': eng.turn, 'pw': _n(st.power), 'ac': _n(st.accuracy),
        });
      };
    }
    game = MatchGame(eng: eng, teams: teams, ballIdx: cfg.ball, hq: widget.fx, stepper: _loop);
    _unsub = link.onGame(_onMsg);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    sfx(Sfx.whistle);
    playLoop(Sfx.crowd);
    stopLoop(Sfx.music);
  }

  static num _n(double v) => v == v.roundToDouble() ? v.toInt() : v;

  @override
  void dispose() {
    _unsub?.call();
    stopLoop(Sfx.crowd);
    if (isHost && done == 'no') {
      link.sendGame({'k': 'abort'});
      rpc('abandon_match', {'p_match': widget.matchId}).catchError((_) => null);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    banner.dispose();
    super.dispose();
  }

  void showBanner(String t, String s, Color c) {
    setState(() => bText = (t, s, c));
    banner.forward(from: 0);
  }

  OnlineOutcome outcome(List<int> score, int? d, bool reported) {
    final w = score[0] > score[1] ? 0 : score[1] > score[0] ? 1 : -1;
    final rd = d == null ? null : !ranked ? 0 : myTeam == 1 ? -d : myTeam == 0 ? d : null;
    return OnlineOutcome(widget.matchId, score, w, rd, myTeam, teams, names, reported, ranked);
  }

  void onEvent(EngineEvent ev) {
    switch (ev) {
      case EvShot():
        cMine = (isHost ? hctrl : cctrl) == link.me;
        cTouched = false;
        if (isHost && cMine) cPower = eng.lastPower;
        buzz();
      case EvHit(:final ball, :final power):
        if (ball) cTouched = true;
        sfx(ball ? Sfx.hitb : Sfx.hitp, power);
        if (power > .35) buzz(power > .7 ? Buzz.medium : Buzz.light);
      case EvWall(:final power):
        sfx(Sfx.wall, power);
      case EvPost(:final power):
        sfx(Sfx.post, power);
        buzz(Buzz.medium);
      case EvTurn():
        cMine = false;
      case EvGoal(:final team, :final nogoal):
        if (nogoal) {
          showBanner('گل مردود', 'با ضربه‌ی اول نمی‌شه گل زد', C.dim);
        } else {
          cTouched = true;
          sfx(Sfx.goal);
          sfx(Sfx.roar);
          buzz(Buzz.heavy);
          showBanner('گل!', names[team], team == 0 ? C.cyan : C.red);
          if (!isHost && goalEp != eng.epoch) eng.fxGoal(team);
        }
      case EvClock():
        showBanner('گل طلایی', 'گل بعدی برنده‌ست', C.gold);
      case EvEnd(:final score):
        if (done == 'no') {
          done = 'ended';
          sfx(Sfx.finalW);
          stopLoop(Sfx.crowd);
          if (isHost) {
            hostReport(score);
          } else {
            endAt = now();
          }
        }
    }
  }

  Future<void> hostReport(List<int> score) async {
    sendSnap(true);
    final dur = ((now() - t0) / 1000).round();
    int? d;
    var ok = false;
    for (var i = 0; i < 3 && !ok; i++) {
      try {
        final r = await rpc<dynamic>('report_match', {'p_match': widget.matchId, 'p_score_a': score[0], 'p_score_b': score[1], 'p_duration': dur});
        d = r is Map ? (r['rating_delta'] as num?)?.toInt() ?? 0 : 0;
        ok = true;
      } catch (e) {
        if (RegExp('not live', caseSensitive: false).hasMatch('$e')) break;
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    }
    if (!ok) widget.toast('ثبت نتیجه ناموفق بود', 'err');
    link.sendGame({'k': 'res', 'winner': score[0] > score[1] ? 0 : score[1] > score[0] ? 1 : -1, 'rd': d ?? 0, 'score': score, 'ok': ok});
    link.ping();
    Timer(const Duration(milliseconds: 1100), () {
      if (done == 'ended') {
        done = 'finished';
        widget.onFinish(outcome(score, d, ok));
      }
    });
  }

  void sendSnap([bool force = false]) {
    final t = now();
    const hz = 10;
    final moving = eng.phase == Phase.move || eng.phase == Phase.goal;
    if (!force && t - lastSend < (moving ? 1000 / hz : 500)) return;
    lastSend = t;
    final p = <int>[];
    for (final b in eng.bodies) {
      p
        ..add(jsRound(b.x * 10).toInt())
        ..add(jsRound(b.y * 10).toInt())
        ..add(jsRound((((b.ang % TAU) + TAU) % TAU) * 100).toInt());
    }
    final R = [for (final v in eng.ball.R) jsRound(v * 1000).toInt()];
    List? kf;
    if (moving) {
      var best = -1;
      for (final tk in eng.keys.keys) {
        if (tk > lastKf && tk > best) best = tk;
      }
      if (best > 0) {
        kf = [best, eng.keys[best]];
        lastKf = best;
      }
    }
    final s = <String, dynamic>{
      'q': ++q, 'ts': t, 'hz': hz, 'ph': eng.phase.name, 'tu': eng.turn, 'sc': [eng.score[0], eng.score[1]], 'ml': (eng.mleft * 10).round() / 10, 'tl': (eng.tleft * 10).round() / 10,
      'su': eng.sudden ? 1 : 0, 'c': hctrl, 'n': seq, 'p': p, 'R': R, 'ev': evs,
      'ep': eng.epoch, 'tk': eng.tick, 'mv': eng.epochKind, 'sh': eng.shots, 'sno': eng.shotNo, 'ps': eng.packState(), 'kf': ?kf,
    };
    evs = [];
    link.sendGame({'k': 's', 's': s});
  }

  String? ctrlFor(int t) {
    final team = teamOf(players, t);
    if (team.isEmpty) return null;
    final n = team.length, st0 = ((turnCount[t] - 1) % n + n) % n;
    for (var i = 0; i < n; i++) {
      final pl = team[(st0 + i) % n], uid = pl['user_id'] as String;
      if (uid == link.me || online.containsKey(uid)) return uid;
    }
    return null;
  }

  // ---------- client: apply snapshots ----------
  void applyScalars(_Snap s, [bool lockstep = false]) {
    if (!lockstep) eng.phase = s.ph;
    eng.turn = s.tu;
    eng.score[0] = (s.sc[0] as num).toInt();
    eng.score[1] = (s.sc[1] as num).toInt();
    eng.mleft = (s.m['ml'] as num).toDouble();
    eng.tleft = (s.m['tl'] as num).toDouble();
    eng.sudden = s.m['su'] == 1;
    cctrl = s.c;
    cseq = s.n;
    eng.aiTeams = [false, false];
    if (s.c == null) eng.aiTeams[s.tu] = true;
    if (s.lockstep) {
      eng.shots = ri(s.m, 'sh');
      eng.shotNo = ri(s.m, 'sno');
    }
    if (s.ph != Phase.aim && eng.drag != null && !lockstep) eng.drag = null;
    for (final e in s.ev) {
      final ev = decEv(e as List);
      if (lockstep && (ev is EvHit || ev is EvWall || ev is EvPost || ev is EvShot)) continue;
      if (ev is EvGoal && goalEp == s.ep) continue;
      onEvent(ev);
    }
  }

  void adopt(_Snap s) {
    final ps = s.ps;
    if (ps == null) return;
    final old = [for (final b in eng.bodies) (b.x, b.y)];
    eng.unpackState(ps.cast<num>());
    eng.epoch = s.ep;
    eng.epochKind = s.mv;
    eng.tick = s.tk;
    eng.acc = 0;
    eng.keys.clear();
    for (var i = 0; i < eng.bodies.length && i < old.length; i++) {
      final b = eng.bodies[i], dx = old[i].$1 - b.x, dy = old[i].$2 - b.y;
      if (dx * dx + dy * dy < 40 * 40) {
        b.vox = dx;
        b.voy = dy;
      }
    }
    got = true;
  }

  bool startReplay(Map<String, dynamic> g) {
    eng.unpackState((g['st'] as List).cast<num>());
    eng.shots = ri(g, 'sh');
    eng.shotNo = ri(g, 'sno');
    eng.epoch = ri(g, 'ep') - 1;
    eng.turn = ri(g, 'tu');
    eng.phase = Phase.aim;
    eng.acc = 0;
    if (cfg.stats != null) cfg.stats![eng.turn] = DiscStats((g['pw'] as num).toDouble(), (g['ac'] as num).toDouble());
    final b = eng.bodies.where((x) => x.id == ri(g, 'b')).firstOrNull;
    if (b == null) return false;
    eng.drag = null;
    final dx = ri(g, 'dx') / 16, dy = ri(g, 'dy') / 16;
    eng.fire(b, dx, dy, hyp(dx, dy), human: g['hu'] == 1, seq: ri(g, 'sq'));
    replay = _Replay(eng.epoch, null, now());
    kfs.clear();
    got = true;
    waitGo = 0;
    return true;
  }

  void checkKeys() {
    final r = replay;
    if (r == null) return;
    for (var i = kfs.length - 1; i >= 0; i--) {
      final (ep, tk, st) = kfs[i];
      if (ep != r.ep) {
        kfs.removeAt(i);
        continue;
      }
      final mine = eng.keys[tk];
      if (mine == null) {
        if (eng.tick > tk + KEY_EVERY * 3) kfs.removeAt(i);
        continue;
      }
      kfs.removeAt(i);
      if (Engine.packError(mine, st.cast<num>()) > 2.5) {
        final nowTk = eng.tick, old = [for (final b in eng.bodies) (b.x, b.y)];
        eng.unpackState(st.cast<num>());
        eng.tick = tk;
        eng.fastForward(nowTk);
        for (var j = 0; j < eng.bodies.length; j++) {
          final b = eng.bodies[j], dx = old[j].$1 - b.x, dy = old[j].$2 - b.y;
          if (dx * dx + dy * dy < 120 * 120) {
            b.vox = dx;
            b.voy = dy;
          }
        }
      }
    }
  }

  void placeBodies(_Snap a, _Snap? b, double k, double dt) {
    final n = eng.bodies.length;
    if (a.p.length < n * 3) return;
    if (prev == null || prev!.length != n * 2) prev = List.filled(n * 2, 0);
    for (var i = 0; i < n; i++) {
      final bd = eng.bodies[i];
      var x = (a.p[i * 3] as num) / 10, y = (a.p[i * 3 + 1] as num) / 10, ang = (a.p[i * 3 + 2] as num) / 100;
      if (b != null && b.p.length >= n * 3) {
        x += ((b.p[i * 3] as num) / 10 - x) * k;
        y += ((b.p[i * 3 + 1] as num) / 10 - y) * k;
        var da = (b.p[i * 3 + 2] as num) / 100 - ang;
        if (da > math.pi) {
          da -= TAU;
        } else if (da < -math.pi) {
          da += TAU;
        }
        ang += da * k;
      }
      final px = prev![i * 2], py = prev![i * 2 + 1];
      bd.vx = got ? (x - px) / math.max(dt, 1e-3) : 0;
      bd.vy = got ? (y - py) / math.max(dt, 1e-3) : 0;
      if (bd.vx.abs() < 4) bd.vx = 0;
      if (bd.vy.abs() < 4) bd.vy = 0;
      bd.x = bd.px = x;
      bd.y = bd.py = y;
      bd.ang = ang;
      bd.vox = bd.voy = 0;
      prev![i * 2] = x;
      prev![i * 2 + 1] = y;
    }
    final src = (b != null && k > .5 ? b : a).R;
    if (src.length == 9) {
      for (var j = 0; j < 9; j++) {
        eng.ball.R[j] = (src[j] as num) / 1000;
      }
    }
    got = true;
    eng.acc = 0;
  }

  // ---------- network messages ----------
  void _onMsg(Map<String, dynamic> m, String? from) {
    if (!isHost) lastRecv = now();
    final k = m['k'];
    if (k == 'go' && !isHost) {
      if (m['st'] is! List) return;
      final r = replay, pr = r?.pred;
      if (r != null && pr != null && r.ep == ri(m, 'ep') && pr.b == ri(m, 'b') && pr.dx == ri(m, 'dx') && pr.dy == ri(m, 'dy') && pr.pw == m['pw'] && pr.ac == m['ac']) {
        r.pred = null;
        return;
      }
      if (r != null && pr == null && r.ep == ri(m, 'ep')) return;
      startReplay(m);
      return;
    }
    if (k == 's' && !isHost) {
      final raw = m['s'];
      if (raw is! Map || raw['p'] is! List) return;
      final s = _Snap(Map<String, dynamic>.from(raw));
      final t = now();
      if (s.q <= lastQ) return;
      lastQ = s.q;
      if (s.lockstep) {
        final kf = s.m['kf'];
        if (kf is List) kfs.add((s.ep, (kf[0] as num).toInt(), kf[1] as List));
        pend.add(s);
        if (pend.length > 40) pend.removeRange(0, pend.length - 40);
      }
      offs.add((t, t - s.ts));
      while (offs.isNotEmpty && t - offs.first.$1 > 4000) {
        offs.removeAt(0);
      }
      buf.add(s);
      if (buf.length > 1 && buf[buf.length - 2].q > s.q) buf.sort((a, b) => a.q.compareTo(b.q));
      if (buf.length > 60) buf.removeRange(0, buf.length - 60);
    } else if (k == 'shot' && isHost) {
      if (from != hctrl || eng.phase != Phase.aim || ri(m, 'n') != seq) return;
      final b = eng.bodies.where((x) => x.id == ri(m, 'b') && x.team == eng.turn).firstOrNull;
      if (b == null) return;
      final div = m['q16'] == 1 ? 16 : 1;
      final dx = ((m['dx'] as num?) ?? 0) / div, dy = ((m['dy'] as num?) ?? 0) / div, l = hyp(dx.toDouble(), dy.toDouble());
      if (l > 18 && l < 5000) eng.fire(b, dx.toDouble(), dy.toDouble(), l, human: true);
    } else if (k == 'aim') {
      final ctrl = isHost ? hctrl : cctrl;
      if (from != ctrl || from == link.me) return;
      if (ri(m, 'b', -1) < 0) {
        if (eng.drag?.ai == true && !eng.isAiTurn()) eng.drag = null;
        return;
      }
      if (eng.phase != Phase.aim) return;
      final b = eng.bodies.where((x) => x.id == ri(m, 'b')).firstOrNull;
      if (b == null) return;
      eng.drag = Drag(b, b.x, b.y, b.x - ((m['dx'] as num?) ?? 0), b.y - ((m['dy'] as num?) ?? 0), ai: true);
    } else if (k == 'res' && !isHost) {
      res = (winner: ri(m, 'winner'), rd: ri(m, 'rd'), score: [for (final v in m['score'] as List) (v as num).toInt()], ok: m['ok'] == true);
    } else if (k == 'abort' && !isHost && done != 'finished') {
      done = 'aborted';
      widget.toast('میزبان بازی را لغو کرد', 'err');
      widget.onExit('aborted');
    }
  }

  // ---------- main loop (driven by Flame's game loop) ----------
  void _loop(double dt) {
    if (done == 'aborted') return;
    final t = now();
    if (isHost) {
      eng.update(dt);
      var urgent = false;
      if (eng.events.isNotEmpty) {
        for (final ev in eng.events) {
          if (ev is EvTurn) {
            turnCount[ev.team]++;
            seq++;
          }
          evs.add(encEv(ev));
          if (ev is! EvHit && ev is! EvWall && ev is! EvPost) urgent = true;
        }
        final es = [...eng.events];
        eng.events.clear();
        hctrl = eng.phase == Phase.over ? null : ctrlFor(eng.turn);
        for (final ev in es) {
          onEvent(ev);
        }
      }
      final c = eng.phase == Phase.over ? null : ctrlFor(eng.turn);
      if (c != hctrl) {
        hctrl = c;
        urgent = true;
        if (c != link.me && eng.drag != null && !eng.drag!.ai) eng.drag = null;
      }
      final ai = c == null && eng.phase != Phase.over;
      if (eng.aiTeams[eng.turn] != ai || eng.aiTeams[1 - eng.turn]) {
        eng.aiTeams = [false, false];
        eng.aiTeams[eng.turn] = ai;
        if (!ai) {
          eng.aiPlan = null;
          if (eng.drag?.ai == true) eng.drag = null;
        }
      }
      if (done != 'finished') sendSnap(urgent);
    } else {
      _follow(dt, t);
    }
    final cu = isHost ? hctrl : cctrl;
    if (cu != null && cfg.stats != null) {
      final pl = players.where((x) => x['user_id'] == cu).firstOrNull;
      if (pl != null) cfg.stats![eng.turn] = discStats(discOf(pl));
    }
    if (!widget.fx && eng.parts.length > 40) eng.parts.removeRange(40, eng.parts.length);
    _hud(dt);
  }

  void _follow(double dt, int t) {
    final r = replay;
    try {
      if (r != null) {
        eng.stepFollower(dt, r.endTk ?? (1 << 52));
        if (eng.events.isNotEmpty) {
          final es = [...eng.events];
          eng.events.clear();
          for (final ev in es) {
            if (ev is EvHit || ev is EvWall || ev is EvPost || ev is EvShot) onEvent(ev);
          }
        }
        final lg = eng.localGoal;
        if (lg != null && goalEp != r.ep) {
          goalEp = r.ep;
          onEvent(EvGoal(lg.team, lg.nogoal));
        }
        checkKeys();
        while (pend.isNotEmpty && replay != null) {
          final s = pend.first;
          if (s.ep < r.ep) {
            if (r.pred != null && s.ph == Phase.aim && (s.n != r.pred!.n || t - r.at > 2500)) {
              applyScalars(s);
              adopt(s);
              replay = null;
            }
            pend.removeAt(0);
            continue;
          }
          if (s.ep == r.ep) {
            if (s.ph == Phase.aim || s.ph == Phase.over) {
              r.endTk = s.tk;
              if (eng.tick >= s.tk || t - r.at > 15000) {
                applyScalars(s, true);
                adopt(s);
                eng.phase = s.ph;
                replay = null;
                pend.removeAt(0);
                continue;
              }
              break;
            }
            if (s.tk <= eng.tick) {
              applyScalars(s, true);
              pend.removeAt(0);
              continue;
            }
            break;
          }
          if (s.mv == 0) {
            applyScalars(s);
            adopt(s);
            replay = null;
            pend.removeAt(0);
            continue;
          }
          if (waitGo == 0) waitGo = t;
          if (t - waitGo > 700) {
            replay = null;
            interp = true;
            pend.clear();
          }
          break;
        }
      } else if (!interp) {
        while (pend.isNotEmpty) {
          final s = pend.first;
          if (s.mv == 1 && s.ep > eng.epoch && (s.ph == Phase.move || s.ph == Phase.goal)) {
            if (waitGo == 0) waitGo = t;
            if (t - waitGo > 700 || !got) {
              interp = true;
              pend.clear();
              applied = s.q - 1;
            }
            break;
          }
          waitGo = 0;
          applyScalars(s);
          if (s.ep >= eng.epoch || s.ph == Phase.aim || s.ph == Phase.over) adopt(s);
          pend.removeAt(0);
        }
        eng.stepFollower(dt, eng.tick);
      }
    } catch (_) {
      replay = null;
      interp = true;
      pend.clear();
    }
    if (eng.phase != Phase.over) {
      if (cfg.matchTime > 0 && !eng.sudden && eng.mleft > 0) eng.mleft = math.max(0, eng.mleft - dt);
      if (cfg.turnTime > 0 && eng.phase == Phase.aim) eng.tleft = math.max(0, eng.tleft - dt);
    }
    // fallback: snapshot interpolation
    final off = offs.isEmpty ? 0 : offs.map((o) => o.$2).reduce(math.min);
    final hz = buf.isNotEmpty ? buf.last.hz : 12;
    final rt = t - off - 1700 / hz;
    if (interp) {
      for (final s in buf) {
        if (s.q > applied && s.ts <= rt) {
          applied = s.q;
          applyScalars(s);
          if (s.ph == Phase.aim || s.ph == Phase.over || (s.mv == 0 && s.ep > eng.epoch)) {
            adopt(s);
            interp = false;
            pend.removeWhere((x) => x.q <= s.q);
            waitGo = 0;
            break;
          }
        }
      }
    }
    if (interp && buf.isNotEmpty) {
      var i = 0;
      while (i + 1 < buf.length && buf[i + 1].ts <= rt) {
        i++;
      }
      final a = buf[i], b = i + 1 < buf.length ? buf[i + 1] : null;
      final k = b != null ? ((rt - a.ts) / math.max(1, b.ts - a.ts)).clamp(0.0, 1.0) : 0.0;
      if (a.ts <= rt || !got) {
        if (applied < a.q && !got) {
          applied = a.q;
          applyScalars(a);
        }
        final pv = i > 0 ? buf[i - 1] : null;
        if (b == null && pv != null && (a.ph == Phase.move || a.ph == Phase.goal) && rt > a.ts) {
          placeBodies(pv, a, 1 + math.min(120, rt - a.ts) / math.max(1, a.ts - pv.ts), dt);
        } else {
          placeBodies(a, b, k, dt);
        }
      }
      if (i > 3) buf.removeRange(0, i - 3);
    }
    if (interp) eng.tickFx(dt);
    if (buf.length > 30) buf.removeRange(0, buf.length - 30);
    if (done == 'no' && t - lastRecv > 8000) {
      done = 'aborted';
      widget.toast('ارتباط با میزبان قطع شد', 'err');
      widget.onExit('hostLost');
      return;
    }
    if (done == 'ended') {
      if (res != null && t - endAt > 900) {
        done = 'finished';
        widget.onFinish(outcome(res!.score, res!.rd, res!.ok));
      } else if (res == null && t - endAt > 10000) {
        done = 'finished';
        supabase.from('matches').select('score_a, score_b, status').eq('id', widget.matchId).maybeSingle().then((d) {
          final sc = d?['status'] == 'done' ? [ri(d, 'score_a', eng.score[0]), ri(d, 'score_b', eng.score[1])] : [eng.score[0], eng.score[1]];
          widget.onFinish(outcome(sc, null, d?['status'] == 'done'));
        }, onError: (_) => widget.onFinish(outcome([eng.score[0], eng.score[1]], null, false)));
      }
    }
  }

  void _hud(double dt) {
    final ctrl = isHost ? hctrl : cctrl;
    final m = math.max(0, eng.mleft.ceil());
    final h = _H()
      ..s0 = eng.score[0]
      ..s1 = eng.score[1]
      ..turn = eng.turn
      ..clock = cfg.matchTime > 0 ? (eng.sudden ? 'گل طلایی' : '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}') : 'تا ${fa(cfg.limit)} گل'
      ..tl = cfg.turnTime > 0 && eng.phase == Phase.aim ? math.max(0, eng.tleft / cfg.turnTime) : 1
      ..sudden = eng.sudden
      ..ctrl = ctrl
      ..phase = eng.phase
      ..wait = !isHost && !got;
    if (ctrl == link.me && eng.phase == Phase.aim && cfg.turnTime > 0) {
      final sec = eng.tleft.ceil();
      if (sec <= 3 && sec > 0 && sec != tickAt) {
        tickAt = sec;
        sfx(Sfx.tick);
      }
    } else {
      tickAt = -1;
    }
    final old = hud.value;
    if (!h.same(old)) {
      final myTurnNow = h.ctrl == link.me && h.phase == Phase.aim && myTeam != null;
      final myTurnOld = old.ctrl == link.me && old.phase == Phase.aim && myTeam != null;
      if (myTurnNow && (!myTurnOld || old.turn != h.turn)) {
        buzz(Buzz.medium);
        sfx(Sfx.ready);
      }
      hud.value = h;
    }
  }

  // ---------- input ----------
  (Body, double, double)? local;
  bool canAct() {
    if (myTeam == null || done != 'no') return false;
    if (isHost) return eng.phase == Phase.aim && hctrl == link.me && !eng.isAiTurn();
    return eng.phase == Phase.aim && cctrl == link.me && now() - pendingShot > 1500;
  }

  Offset? _world(Offset p, Size sz) => game.worldAt(flipped ? Offset(sz.width - p.dx, sz.height - p.dy) : p);
  void sendAim([bool force = false]) {
    final d = eng.drag;
    if (d == null || d.ai) return;
    final t = now();
    if (!force && t - lastAim < 120) return;
    lastAim = t;
    link.sendGame({'k': 'aim', 'b': d.b.id, 'dx': jsRound(d.sx - d.cx).toInt(), 'dy': jsRound(d.sy - d.cy).toInt()});
  }

  void _down(Offset pos, Size sz) {
    if (!canAct()) return;
    final p = _world(pos, sz);
    if (p == null) return;
    if (isHost) {
      if (eng.pick(p.dx, p.dy)) {
        buzz();
        local = eng.drag != null ? (eng.drag!.b, eng.drag!.sx, eng.drag!.sy) : null;
      }
      return;
    }
    Body? best;
    var bd = 1e9;
    for (final b in eng.bodies) {
      if (b.team == myTeam && b.team == eng.turn) {
        final d = hyp(p.dx - b.x, p.dy - b.y);
        if (d < b.r + 34 && d < bd) {
          best = b;
          bd = d;
        }
      }
    }
    if (best == null) return;
    buzz();
    local = (best, best.x, best.y);
    eng.drag = Drag(best, best.x, best.y, p.dx, p.dy);
  }

  void _move(Offset pos, Size sz) {
    if (local == null || eng.drag == null || eng.drag!.ai) return;
    final p = _world(pos, sz);
    if (p == null) return;
    eng.move(p.dx, p.dy);
    sendAim();
  }

  void _up() {
    final l0 = local;
    local = null;
    if (l0 == null) return;
    final d = eng.drag;
    if (isHost) {
      eng.release();
      link.sendGame({'k': 'aim', 'b': -1});
      return;
    }
    eng.drag = null;
    link.sendGame({'k': 'aim', 'b': -1});
    if (d == null || d.ai) return;
    final dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy);
    if (l > 18 && canAct()) {
      cPower = math.min(l, LMAX) / LMAX;
      pendingShot = now();
      final qx = jsRound(dx * 16).toInt(), qy = jsRound(dy * 16).toInt();
      link.sendGame({'k': 'shot', 'b': l0.$1.id, 'dx': qx, 'dy': qy, 'q16': 1, 'n': cseq});
      // client-side prediction: fire locally now with exactly the quantised input the host will use
      final b = eng.bodies.where((x) => x.id == l0.$1.id).firstOrNull;
      if (b != null && !interp) {
        final st = cfg.stats?[b.team] ?? const DiscStats(5, 5);
        eng.fire(b, qx / 16, qy / 16, hyp(qx / 16, qy / 16), human: true);
        replay = _Replay(eng.epoch, _Pred(cseq, b.id, qx, qy, _n(st.power), _n(st.accuracy)), now());
        kfs.clear();
        waitGo = 0;
      }
    }
  }

  void _cancel() {
    local = null;
    if (eng.drag != null && !eng.drag!.ai) eng.drag = null;
    link.sendGame({'k': 'aim', 'b': -1});
  }

  void doQuit() {
    setState(() => quit = false);
    if (isHost) {
      done = 'aborted';
      link.sendGame({'k': 'abort'});
      rpc('abandon_match', {'p_match': widget.matchId}).catchError((_) => null);
      link.ping();
    } else {
      done = 'aborted';
    }
    stopLoop(Sfx.crowd);
    widget.onExit('quit');
  }

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context), sz = MediaQuery.sizeOf(context);
    final topM = ins.top + 92, botM = ins.bottom + 72;
    game.setInsets(flipped ? botM : topM, flipped ? topM : botM);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => setState(() => quit = true),
      child: Scaffold(
        backgroundColor: hex('#02040c'),
        body: Stack(children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _down(e.localPosition, sz),
              onPointerMove: (e) => _move(e.localPosition, sz),
              onPointerUp: (_) => _up(),
              onPointerCancel: (_) => _cancel(),
              child: IgnorePointer(child: Transform.rotate(angle: flipped ? math.pi : 0, child: GameWidget(game: game))),
            ),
          ),
          Positioned(
            top: ins.top + 6, left: 10, right: 10,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 8),
                child: Press(
                  onPress: () => setState(() => quit = true),
                  child: Container(
                    width: 38, height: 38, alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: rgba(5, 8, 22, .9), border: Border.all(color: const Color(0x29FFFFFF))),
                    child: T('✕', style: fs(F.body, 15, color: Colors.white)),
                  ),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<_H>(
                  valueListenable: hud,
                  builder: (_, h, _) {
                    final turnName = h.ctrl == link.me ? 'نوبت توئه!' : 'نوبت: ${nameOf(h.ctrl)}';
                    final a = flipped ? 1 : 0, b = 1 - a;
                    return ScoreBug(
                      left: BugSide(team: teams[a], name: names[a], score: a == 0 ? h.s0 : h.s1, color: a == 0 ? C.cyan : C.red, on: h.turn == a),
                      right: BugSide(team: teams[b], name: names[b], score: b == 0 ? h.s0 : h.s1, color: b == 0 ? C.cyan : C.red, on: h.turn == b),
                      clock: h.clock, sudden: h.sudden, tl: h.tl, timed: cfg.turnTime > 0,
                      status: h.phase == Phase.aim ? turnName : h.phase == Phase.goal ? 'گل!' : h.phase == Phase.over ? 'پایان بازی' : 'در حال حرکت…',
                    );
                  },
                ),
              ),
            ]),
          ),
          Positioned(
            top: ins.top + 112, left: 0, right: 0,
            child: IgnorePointer(
              child: ValueListenableBuilder<LinkState>(
                valueListenable: link,
                builder: (_, ls, _) {
                  final viewers = ls.players.where((p) => p['role'] == 'spectator' && ls.online.containsKey(p['user_id'])).length;
                  return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (myTeam == null) Badge2(label: 'زنده · ${fa(viewers)} تماشاگر', color: C.red, live: true),
                    if (!isHost) Padding(padding: const EdgeInsets.only(left: S.s), child: PingBadge(link: link)),
                  ]);
                },
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: banner,
                builder: (_, _) {
                  final t = banner.value * 1.7;
                  if (banner.isDismissed || t <= 0) return const SizedBox.shrink();
                  final inK = Curves.elasticOut.transform(math.min(1, t / .55));
                  final out = t > 1.4 ? (t - 1.4) / .3 : 0.0;
                  return Align(
                    alignment: const Alignment(0, -.24),
                    child: Opacity(
                      opacity: ((t < .1 ? t / .1 : 1.0) * (1 - out)).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: .3 + .7 * inK + .25 * out,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          T(bText.$1, style: fs(F.title, 54, color: Colors.white, shadows: [Shadow(color: bText.$3, blurRadius: 24)])),
                          if (bText.$2.isNotEmpty) T(bText.$2, n: 1, style: fs(F.head, 13, color: bText.$3)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          ValueListenableBuilder<_H>(
            valueListenable: hud,
            builder: (_, h, _) => h.wait
                ? Positioned.fill(child: IgnorePointer(child: Container(color: rgba(2, 4, 14, .55), alignment: Alignment.center, child: T('در حال اتصال به میزبان…', style: fs(F.bold, 15)))))
                : const SizedBox.shrink(),
          ),
          Positioned(
            left: S.m, right: S.m, bottom: math.max(ins.bottom, S.s),
            child: Row(children: [
              ValueListenableBuilder<LinkState>(
                valueListenable: link,
                builder: (_, ls, _) => Press(
                  onPress: () => setState(() {
                    chat = !chat;
                    link.chatOpen = chat;
                    if (chat) link.markRead();
                  }),
                  child: Container(
                    width: 44, height: 44, alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: rgba(8, 14, 40, .85), border: Border.all(color: chat ? C.cyan : C.line)),
                    child: Stack(clipBehavior: Clip.none, children: [
                      Img(UI2['c_mega'], w: 24, h: 24),
                      if (ls.unread > 0 && !chat)
                        Positioned(
                          top: -8, right: -10,
                          child: Container(
                            width: 16, height: 16, alignment: Alignment.center,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: C.red),
                            child: Text(fa(math.min(9, ls.unread)), style: fs(F.bold, 9, color: Colors.white)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: S.s),
              if (room0['voice'] == true) VoiceBar(link: link, compact: true),
            ]),
          ),
          if (chat) Positioned(left: S.m, right: S.m, bottom: math.max(ins.bottom, S.s) + 56, child: ChatPanel(link: link, compact: true, height: 220)),
          if (quit)
            Positioned.fill(
              child: Container(
                color: rgba(2, 4, 14, .7),
                alignment: Alignment.center,
                child: FractionallySizedBox(
                  widthFactor: .86,
                  child: Panel(
                    glow: true,
                    pad: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      T('خروج از بازی؟', align: TextAlign.center, style: fs(F.title, 20)),
                      Padding(
                        padding: const EdgeInsets.only(top: S.s, bottom: S.l),
                        child: T(
                            isHost ? 'تو میزبانی؛ با خروج تو بازی برای همه لغو می‌شود.' : myTeam == null ? 'تماشای بازی را ترک می‌کنی.' : 'بازی بدون تو ادامه پیدا می‌کند و ربات جای تو بازی می‌کند.',
                            align: TextAlign.center,
                            style: fs(F.body, 13, color: C.dim)),
                      ),
                      Btn(label: 'ادامه‌ی بازی', onPress: () => setState(() => quit = false)),
                      const SizedBox(height: S.m),
                      Btn(label: 'خروج', colors: G.red, small: true, onPress: doQuit),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
