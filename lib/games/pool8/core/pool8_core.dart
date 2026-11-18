import 'dart:math' as math;

import '../../billiards/core/pool_bot.dart';
import '../../billiards/core/pool_config.dart';
import '../../billiards/core/pool_match.dart';

export '../../billiards/core/pool_bot.dart' show PoolBotLevel, PoolBotPlanner;
export '../../billiards/core/pool_config.dart';
export '../../billiards/core/pool_match.dart';
export '../../billiards/core/pool_physics.dart';

/// 8 Ball Pool BLITZ (arcade): the classic 8-ball rules engine of the Billiards game (reused read-only, never
/// modified) plus a shot clock. Running out of time is a foul: the opponent gets ball-in-hand anywhere.
/// Pure Dart and deterministic: online, every phone replays the same shots.
class Pool8Blitz {
  Pool8Blitz({this.shotClock = 20, int breaker = 0}) : match = PoolMatch.newRack(breaker: breaker);

  final PoolMatch match;
  final double shotClock;
  double clock = 0;
  int timeouts = 0;
  PoolShotReport? lastReport;

  /// Balls pocketed by each player over the match (HUD + score).
  final List<int> potted = <int>[0, 0];

  int get current => match.current;
  bool get over => match.isOver;
  int? get winner => match.winner;
  bool get aiming => match.phase == PoolPhase.aiming;
  bool get simulating => match.phase == PoolPhase.simulating;

  double get clockLeft => math.max(0, shotClock - clock);

  /// Starts a shot. Returns false when it is not legal right now.
  bool shoot(PoolShot s) {
    if (!aiming || over) return false;
    if (!match.beginShot(s)) return false;
    clock = 0;
    return true;
  }

  /// Advances the running shot by [ticks] fixed physics steps. Returns the report once the balls settle.
  PoolShotReport? stepShot([int ticks = 2]) {
    if (!simulating) return null;
    for (int i = 0; i < ticks; i++) {
      if (match.world.tick()) {
        final int shooter = match.current;
        final PoolShotReport r = match.finishShot();
        potted[shooter] += r.pocketed.where((int id) => id != 0).length;
        lastReport = r;
        clock = 0;
        return r;
      }
    }
    return null;
  }

  /// Plays a whole shot at once (bots in tests, replays after a re-join).
  PoolShotReport? playNow(PoolShot s) {
    if (!shoot(s)) return null;
    PoolShotReport? r;
    while (r == null && simulating) {
      r = stepShot(64);
    }
    return r;
  }

  /// Shot clock. Returns true when the clock ran out (call [timeout] — online only the shooter's phone or the
  /// authority does, as a logged move, so every phone applies it at the same point of the log).
  bool tickClock(double dt) {
    if (!aiming || over) return false;
    clock += dt;
    return clock >= shotClock;
  }

  /// Shot-clock foul: turn passes, opponent gets ball-in-hand anywhere on the table.
  void timeout() {
    if (!aiming || over) return;
    timeouts++;
    match.current = match.opponent;
    match.isBreak = false;
    match.ballInHand = true;
    match.kitchenOnly = false;
    if (match.cue.pocketed) {
      match.cue
        ..pocketed = false
        ..pocket = -1
        ..x = PoolConfig.breakCueX
        ..y = PoolConfig.breakCueY;
    }
    clock = 0;
  }

  /// Ball-in-hand: free spot nearest to ([x],[y]) (searches a small spiral), or null.
  (double, double)? nearestFreeSpot(double x, double y) {
    for (int ring = 0; ring < 12; ring++) {
      final int n = ring == 0 ? 1 : ring * 8;
      for (int i = 0; i < n; i++) {
        final double a = i / n * math.pi * 2;
        final double px = x + math.cos(a) * ring * PoolConfig.ballR;
        final double py = y + math.sin(a) * ring * PoolConfig.ballR;
        if (match.canPlaceCue(px, py)) return (px, py);
      }
    }
    return null;
  }

  static PoolBotLevel levelFor(double skill) =>
      skill < 0.45 ? PoolBotLevel.easy : (skill < 0.8 ? PoolBotLevel.normal : PoolBotLevel.hard);

  /// Final ranking (seat order best → worst).
  List<int> ranking() {
    final int w = winner ?? (potted[0] >= potted[1] ? 0 : 1);
    return <int>[w, 1 - w];
  }
}
