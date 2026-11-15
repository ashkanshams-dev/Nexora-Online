import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/games/core/game_contract.dart';
import '../core/body.dart';
import '../core/bot.dart';
import '../core/config.dart';
import '../core/fs_match.dart';
import '../core/physics.dart';
import 'fs_fx.dart';

/// Team colours (team 0 = bottom / seat 0, team 1 = top).
const Color kFsTeam0 = Color(0xFF2EE6D6);
const Color kFsTeam1 = Color(0xFFFF4FA3);

/// Free / original puck skins that may be shown (never the licensed placeholder set).
const List<String> kFsSafeSkins = <String>[
  'nx_green',
  'tech_nx',
  'frost',
  'frost_b',
  'eagle_marble',
  'eagle_gold',
  'noble_lion',
  'royal_lion',
  'phoenix_purple',
  'dragon_fire',
  'cosmic_crown',
];

/// Converts a catalog id ('puck_nx_green') to a skin id ('nx_green'); falls back to nx_green.
String fsSkinFromCatalog(String? catalogId) {
  if (catalogId == null || catalogId.isEmpty) return 'nx_green';
  var s = catalogId;
  if (s.startsWith('puck_')) s = s.substring(5);
  if (!kFsSafeSkins.contains(s)) return 'nx_green';
  return s;
}

/// A different free skin for the opponent.
String fsOpponentSkin(String mine) => mine == 'tech_nx' ? 'nx_green' : 'tech_nx';

@immutable
class FsHudData {
  const FsHudData({
    required this.score0,
    required this.score1,
    required this.turnTeam,
    required this.timeLeft,
    required this.turnNumber,
    required this.phase,
    required this.winner,
    required this.botThinking,
  });

  final int score0;
  final int score1;
  final int turnTeam;
  final int timeLeft;
  final int turnNumber;
  final FsPhase phase;
  final int? winner;
  final bool botThinking;

  @override
  bool operator ==(Object other) =>
      other is FsHudData &&
      other.score0 == score0 &&
      other.score1 == score1 &&
      other.turnTeam == turnTeam &&
      other.timeLeft == timeLeft &&
      other.turnNumber == turnNumber &&
      other.phase == phase &&
      other.winner == winner &&
      other.botThinking == botThinking;

  @override
  int get hashCode => Object.hash(score0, score1, turnTeam, timeLeft, turnNumber, phase, winner, botThinking);
}

/// Drives a match: fixed-step simulation, bot, timer, input -> FsShot, juice.
/// All rules live in the pure core (FsMatch / physics).
class FsController extends ChangeNotifier {
  FsController(this.launch)
      : match = FsMatch.kickoff(),
        fx = FsFx(enabled: launch.fancyEffects && !launch.reducedMotion) {
    if (launch.vsBot) {
      bot = FsBot(team: 1, level: _level(launch.difficulty), seed: launch.seed ?? 7);
    }
    playerSkin = fsSkinFromCatalog(launch.skins['puck']);
    opponentSkin = fsOpponentSkin(playerSkin);
    final NetLink? net = launch.net;
    if (net != null) {
      _netReady = false;
      final NetInbox inbox = NetInbox(_onNet);
      _inbox = inbox;
      net.listen(inbox.add,
          onReplayDone: () => inbox.add(const NetMove(seq: -1, seat: -1, kind: 'replayDone', data: <String, dynamic>{})));
    }
    _pushHud();
  }

  // ------------------------------------------------------------- online
  // Both phones run the same deterministic physics on the same shot input. After each shot settles,
  // the authority posts a snapshot ('snap'); everyone adopts it, so the boards can never drift apart.
  NetInbox? _inbox;
  bool _netReady = true;
  bool _synced = true;
  double _syncWait = 0;
  bool get online => launch.online;
  int get mySeat => launch.mySeat;

  /// Seat 1 sees the pitch rotated so their own goal is at the bottom.
  bool get flipped => online && mySeat == 1;

  String _hash() => hashOf('${match.toJson()}');

  Map<String, dynamic> _snap() => <String, dynamic>{'a': 'snap', 'tn': match.turnNumber, 'm': match.toJson(), 'h': _hash()};

  void _applySnap(Map<String, dynamic> d) {
    final dynamic m = d['m'];
    if (m is! Map) return;
    final FsMatch next = FsMatch.fromJson(Map<String, dynamic>.from(m));
    if (hashOf('${next.toJson()}') != _hash()) {
      launch.net?.verify(-1, hashOf('${next.toJson()}'), _hash());
      match = next;
      trail.clear();
    }
  }

  void _postSettle() {
    if (!online) return;
    final NetLink net = launch.net!;
    if (net.isAuthority) {
      net.send(_snap(), kind: 'snap');
      _synced = true;
    } else {
      _synced = false;
      _syncWait = 0;
    }
  }

  void _runShotNow(FsShot shot) {
    if (match.validate(shot) != null) return;
    match.beginShot(shot);
    final FsSimulator sim = FsSimulator(match.bodies)..runToEnd();
    match.finishShot(sim.scorer, sim.steps);
  }

  FsShot? _shotFrom(Map<String, dynamic> d) {
    final int? b = (d['b'] as num?)?.toInt();
    if (b == null) return null;
    return FsShot(
      bodyId: b,
      dirX: (d['x'] as num).toDouble(),
      dirY: (d['y'] as num).toDouble(),
      power: (d['p'] as num).toDouble(),
    );
  }

  Future<void> _onNet(NetMove m) async {
    if (_disposed) return;
    if (m.kind == 'replayDone') {
      _netReady = true;
      _synced = true;
      timeLeft = FsConfig.turnSeconds;
      if (match.phase == FsPhase.finished) _onMatchOver();
      _pushHud();
      return;
    }
    final String a = '${m.data['a']}';
    final int tn = (m.data['tn'] as num?)?.toInt() ?? -1;
    if (m.replay) {
      if (a == 'shot' && tn == match.turnNumber) {
        final FsShot? shot = _shotFrom(m.data);
        if (shot != null) _runShotNow(shot);
      } else if (a == 'pass' && tn == match.turnNumber) {
        match.passTurn();
      } else if (a == 'snap' && tn == match.turnNumber) {
        _applySnap(m.data);
      }
      return;
    }
    // Live: never interrupt a running simulation.
    while (!_disposed && match.phase == FsPhase.simulating) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (_disposed) return;
    if (a == 'snap') {
      if (tn == match.turnNumber) _applySnap(m.data);
      _synced = true;
    } else if (a == 'shot') {
      if (tn != match.turnNumber || match.phase != FsPhase.aiming) return;
      launch.net?.verify(m.seq, m.data['h'] as String?, _hash());
      final FsShot? shot = _shotFrom(m.data);
      if (shot != null) startShot(shot, remote: true);
    } else if (a == 'pass') {
      if (tn != match.turnNumber || match.phase != FsPhase.aiming) return;
      _doPass();
    }
    _pushHud();
  }

  void _doPass() {
    aimId = null;
    pull = Offset.zero;
    _search = null;
    match.passTurn();
    timeLeft = FsConfig.turnSeconds;
    _botDelay = 0.9;
    _banner('وقت تمام شد', 'Time up', const Color(0xFFFFC857));
    if (match.phase == FsPhase.finished) _onMatchOver();
  }

  final GameLaunch launch;
  FsMatch match;
  final FsFx fx;
  FsBot? bot;
  FsBotSearch? _search;
  FsSimulator? _sim;
  late final String playerSkin;
  late final String opponentSkin;

  final List<FsImpact> _impacts = <FsImpact>[];
  final List<Offset> trail = <Offset>[];
  int _trailTick = 0;
  double _acc = 0;
  double timeLeft = FsConfig.turnSeconds;
  double _botDelay = 0.9;
  double bannerTime = 0;
  double bannerAge = 0;
  String bannerFa = '';
  String bannerEn = '';
  Color bannerColor = const Color(0xFFFFFFFF);
  double clock = 0;
  double _hapticCooldown = 0;
  double _finishDelay = -1;
  bool _reported = false;
  bool _disposed = false;

  int? aimId;
  Offset pull = Offset.zero;

  final ValueNotifier<FsHudData> hud = ValueNotifier<FsHudData>(const FsHudData(
    score0: 0,
    score1: 0,
    turnTeam: 0,
    timeLeft: 15,
    turnNumber: 0,
    phase: FsPhase.aiming,
    winner: null,
    botThinking: false,
  ));

  // ------------------------------------------------------------- viewport
  /// The pitch artwork (1080x1698) mapped to field units: field (0,0)-(680,1000) sits at
  /// image px (32.5,101.5)-(1047.5,1596.5), i.e. 1.4935 px per unit.
  static const Rect viewRect = Rect.fromLTWH(-21.76, -67.9, 723.1, 1135.8);

  Size viewSize = Size.zero;
  double get viewScale {
    if (viewSize.width <= 0 || viewSize.height <= 0) return 1;
    return math.min(viewSize.width / viewRect.width, viewSize.height / viewRect.height);
  }

  Offset get viewOrigin {
    final s = viewScale;
    return Offset((viewSize.width - viewRect.width * s) / 2 - viewRect.left * s, (viewSize.height - viewRect.height * s) / 2 - viewRect.top * s);
  }

  Offset toField(Offset local) {
    final s = viewScale;
    final o = viewOrigin;
    return Offset((local.dx - o.dx) / s, (local.dy - o.dy) / s);
  }

  /// Gesture positions arrive in the (possibly rotated) pitch widget's own space.
  Offset toFieldFromGesture(Offset local) => toField(local);

  static FsBotLevel _level(BotDifficulty d) => switch (d) {
        BotDifficulty.easy => FsBotLevel.easy,
        BotDifficulty.normal => FsBotLevel.normal,
        BotDifficulty.hard => FsBotLevel.hard,
      };

  bool get isBotTurn => bot != null && match.turnTeam == bot!.team && match.phase == FsPhase.aiming;
  bool get humanCanAim =>
      match.phase == FsPhase.aiming &&
      !isBotTurn &&
      bannerTime <= 0 &&
      (!online || (_netReady && _synced && match.turnTeam == mySeat));
  bool get botThinking => isBotTurn && bannerTime <= 0;

  String teamName(int team) {
    final String? n = launch.netName(team);
    if (n != null) return n;
    if (team == 0) return launch.playerName.isEmpty ? launch.tx('شما', 'You') : launch.playerName;
    if (launch.vsBot) return launch.tx('ربات', 'Bot');
    return launch.tx('بازیکن ۲', 'Player 2');
  }

  // ------------------------------------------------------------- input
  void onAimStart(Offset local) {
    if (!humanCanAim) return;
    final p = toField(local);
    FsBody? best;
    var bd = FsConfig.discR * 1.9;
    for (final b in match.bodies) {
      if (b.team != match.turnTeam) continue;
      final d = (Offset(b.x, b.y) - p).distance;
      if (d < bd) {
        bd = d;
        best = b;
      }
    }
    aimId = best?.id;
    pull = Offset.zero;
    if (best != null && launch.soundOn) HapticFeedback.selectionClick();
  }

  void onAimUpdate(Offset local) {
    final id = aimId;
    if (id == null) return;
    final b = match.bodies[id];
    var v = toField(local) - Offset(b.x, b.y);
    final len = v.distance;
    if (len > FsConfig.maxPull) v = v * (FsConfig.maxPull / len);
    pull = v;
  }

  void onAimEnd() {
    final id = aimId;
    aimId = null;
    if (id == null) return;
    final len = pull.distance;
    final power = len / FsConfig.maxPull;
    if (power < 0.06 || !humanCanAim) {
      pull = Offset.zero;
      return;
    }
    final shot = FsShot(bodyId: id, dirX: -pull.dx / len, dirY: -pull.dy / len, power: math.min(1.0, power));
    pull = Offset.zero;
    startShot(shot);
  }

  void onAimCancel() {
    aimId = null;
    pull = Offset.zero;
  }

  /// Entry point for human, bot and (later) remote shots.
  void startShot(FsShot shot, {bool remote = false}) {
    if (match.validate(shot) != null) return;
    if (online && !remote) {
      launch.net!.send(<String, dynamic>{
        'a': 'shot',
        'tn': match.turnNumber,
        'b': shot.bodyId,
        'x': shot.dirX,
        'y': shot.dirY,
        'p': shot.power,
        'h': _hash(),
      });
    }
    match.beginShot(shot);
    _sim = FsSimulator(match.bodies, impactSink: _impacts);
    _acc = 0;
    trail.clear();
    if (launch.soundOn) HapticFeedback.mediumImpact();
    _pushHud();
  }

  // ------------------------------------------------------------- loop
  void tick(double dt) {
    if (_disposed) return;
    clock += dt;
    fx.update(dt);
    if (_hapticCooldown > 0) _hapticCooldown -= dt;
    if (bannerTime > 0) bannerTime -= dt;
    bannerAge += dt;
    switch (match.phase) {
      case FsPhase.aiming:
        _tickAiming(dt);
        break;
      case FsPhase.simulating:
        _tickSim(dt);
        break;
      case FsPhase.finished:
        if (_finishDelay > 0) {
          _finishDelay -= dt;
          if (_finishDelay <= 0) _report();
        }
        break;
    }
    // onFinish may tear the host down synchronously.
    if (_disposed) return;
    _pushHud();
    notifyListeners();
  }

  void _tickAiming(double dt) {
    if (bannerTime > 0) return;
    if (online) {
      if (!_netReady) return;
      if (!_synced) {
        _syncWait += dt;
        if (_syncWait > 3.5) _synced = true; // authority silent: continue on our identical simulation
        return;
      }
      timeLeft -= dt;
      final NetLink net = launch.net!;
      if (match.turnTeam == mySeat && timeLeft <= 0) {
        net.send(<String, dynamic>{'a': 'pass', 'tn': match.turnNumber});
        _doPass();
      } else if (match.turnTeam != mySeat && timeLeft <= -8 && net.isAuthority) {
        // The other player went silent: record their timeout for them.
        net.send(<String, dynamic>{'a': 'pass', 'tn': match.turnNumber}, kind: 'timeout', asSeat: match.turnTeam);
        _doPass();
      }
      return;
    }
    timeLeft -= dt;
    if (timeLeft <= 0) {
      aimId = null;
      pull = Offset.zero;
      _search = null;
      match.passTurn();
      timeLeft = FsConfig.turnSeconds;
      _botDelay = 0.9;
      _banner('وقت تمام شد', 'Time up', const Color(0xFFFFC857));
      if (match.phase == FsPhase.finished) _onMatchOver();
      return;
    }
    if (isBotTurn) {
      if (_botDelay > 0) {
        _botDelay -= dt;
        return;
      }
      final b = bot;
      if (b == null) return;
      final search = _search ??= FsBotSearch(b, match);
      if (search.step(6)) {
        _search = null;
        startShot(search.best);
      }
    }
  }

  void _tickSim(double dt) {
    _acc += math.min(dt, 0.05);
    final sim = _sim;
    if (sim == null) return;
    while (_acc >= FsConfig.dt) {
      _acc -= FsConfig.dt;
      final finished = sim.tick();
      _drainImpacts();
      _trailTick++;
      if (fx.enabled && _trailTick % 2 == 0) {
        trail.add(Offset(match.ball.x, match.ball.y));
        if (trail.length > 16) trail.removeAt(0);
      }
      if (finished) {
        final ballX = match.ball.x;
        final out = match.finishShot(sim.scorer, sim.steps);
        _sim = null;
        timeLeft = FsConfig.turnSeconds;
        _botDelay = 0.9;
        if (out.scorer >= 0) _onGoal(out.scorer, ballX);
        if (out.matchOver) _onMatchOver();
        _postSettle();
        break;
      }
    }
  }

  void _drainImpacts() {
    if (_impacts.isEmpty) return;
    for (final im in _impacts) {
      final s = im.strength;
      if (s < 180) continue;
      final k = math.min(1.0, s / 1800);
      fx.burst(im.x, im.y,
          count: 4 + (k * 10).round(),
          speed: 120 + 320 * k,
          color: im.wall ? const Color(0xFF9FE8FF) : const Color(0xFFFFF2B0),
          size: 3 + 3 * k,
          life: 0.35 + 0.25 * k);
      if (s > 900) fx.shake(3 + 7 * k);
      if (launch.soundOn && _hapticCooldown <= 0 && s > 400) {
        _hapticCooldown = 0.09;
        HapticFeedback.lightImpact();
      }
    }
    _impacts.clear();
  }

  void _onGoal(int scorer, double ballX) {
    final c = scorer == 0 ? kFsTeam0 : kFsTeam1;
    final goalY = scorer == 0 ? 0.0 : FsConfig.fieldH;
    fx.doFlash(c, 0.55);
    fx.shake(14);
    fx.burst(ballX, goalY, count: 46, speed: 620, color: c, size: 7, life: 1.1);
    fx.burst(ballX, goalY, count: 24, speed: 420, color: const Color(0xFFFFC857), size: 5, life: 0.9);
    _banner('گل!', 'GOAL!', c);
    bannerTime = 1.7;
    trail.clear();
    if (launch.soundOn) HapticFeedback.heavyImpact();
  }

  void _onMatchOver() {
    final w = match.winner;
    if (w == -1) {
      _banner('مساوی', 'Draw', const Color(0xFFFFC857));
    } else if (online) {
      final bool won = w == mySeat;
      _banner(won ? 'بردی!' : 'باختی', won ? 'You win!' : 'You lose', w == 0 ? kFsTeam0 : kFsTeam1);
    } else if (w == 0) {
      _banner(launch.vsBot ? 'بردی!' : 'تیم آبی برد', launch.vsBot ? 'You win!' : 'Blue wins', kFsTeam0);
    } else {
      _banner(launch.vsBot ? 'باختی' : 'تیم صورتی برد', launch.vsBot ? 'You lose' : 'Pink wins', kFsTeam1);
    }
    bannerTime = 2.4;
    _finishDelay = 2.3;
  }

  void _banner(String fa, String en, Color c) {
    bannerFa = fa;
    bannerEn = en;
    bannerColor = c;
    bannerAge = 0;
    if (bannerTime < 1.1) bannerTime = 1.1;
  }

  void _report() {
    if (_reported) return;
    _reported = true;
    final w = match.winner;
    final int me = mySeat;
    final GameOutcome outcome = w == null || w == -1 ? GameOutcome.draw : (w == me ? GameOutcome.win : GameOutcome.loss);
    final s0 = match.score[0], s1 = match.score[1];
    launch.onFinish(GameResult(
      outcome: outcome,
      score: match.score[me],
      opponentScore: match.score[1 - me],
      winnerSeats: w == null || w < 0 ? <int>[] : <int>[w],
      scores: <int>[s0, s1],
      summaryFa: 'نتیجه‌ی فوتبال انگشتی: $s0 - $s1 در ${match.turnNumber} نوبت',
      summaryEn: 'Finger Soccer final: $s0 - $s1 after ${match.turnNumber} turns',
    ));
  }

  void _pushHud() {
    if (_disposed) return;
    hud.value = FsHudData(
      score0: match.score[0],
      score1: match.score[1],
      turnTeam: match.turnTeam,
      timeLeft: math.max(0, timeLeft.ceil()),
      turnNumber: match.turnNumber,
      phase: match.phase,
      winner: match.winner,
      botThinking: botThinking,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _inbox?.close();
    hud.dispose();
    super.dispose();
  }
}
