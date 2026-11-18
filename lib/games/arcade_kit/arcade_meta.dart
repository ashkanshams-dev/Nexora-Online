import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/online/online_service.dart';
import '../../core/profile/profile_service.dart';
import '../../core/storage/local_store.dart';

/// ===================== NEXORA ARCADE META =====================
/// Shared progression for the 20 arcade games added on redesign-2:
/// medals (bronze/silver/gold), personal bests, a seeded daily challenge, account sync (best scores live in the
/// profile counters, which CloudProfileSync uploads) and the global score board on the games project
/// (`nx_arcade_submit` validates every score server-side against the limits in nx_arcade_limits).
/// ================================================================

enum ArcadeMedal { none, bronze, silver, gold }

class ArcadeDef {
  const ArcadeDef({
    required this.id,
    required this.unitFa,
    required this.unitEn,
    required this.bronze,
    required this.silver,
    required this.gold,
    required this.daily,
    this.multiplayer = false,
  });
  final String id;
  final String unitFa;
  final String unitEn;
  final int bronze;
  final int silver;
  final int gold;

  /// Daily-challenge base target (solo games: score to reach; multiplayer: win on Hard vs today's seed).
  final int daily;
  final bool multiplayer;

  ArcadeMedal medalFor(int score) => score >= gold
      ? ArcadeMedal.gold
      : score >= silver
          ? ArcadeMedal.silver
          : score >= bronze
              ? ArcadeMedal.bronze
              : ArcadeMedal.none;
}

/// Multiplayer games (bot opponents offline, online rooms / invites / tournaments).
const List<String> kArcadeMultiIds = <String>[
  'kart_racing',
  'obstacle_race',
  'bomb_arena',
  'pool8',
  'mini_golf',
  'basketball_battle',
  'spy_mafia',
  'stickman_arena',
  'ludo_battle',
  'chess_blitz',
];

/// Single-player competitive games.
const List<String> kArcadeSoloIds = <String>[
  'endless_runner',
  'tetris_rush',
  'helix_jump',
  'fruit_ninja',
  'geo_dash',
  'traffic_racer',
  'stack_tower',
  'bubble_shooter',
  'knife_hit',
  'game_2048',
];

const List<String> kArcadeIds = <String>[...kArcadeMultiIds, ...kArcadeSoloIds];

const Map<String, ArcadeDef> kArcadeDefs = <String, ArcadeDef>{
  // solo — score units and medal thresholds (server limits live in nx_arcade_limits)
  'endless_runner': ArcadeDef(id: 'endless_runner', unitFa: 'متر', unitEn: 'm', bronze: 300, silver: 900, gold: 2000, daily: 700),
  'tetris_rush': ArcadeDef(id: 'tetris_rush', unitFa: 'امتیاز', unitEn: 'pts', bronze: 3000, silver: 12000, gold: 40000, daily: 8000),
  'helix_jump': ArcadeDef(id: 'helix_jump', unitFa: 'امتیاز', unitEn: 'pts', bronze: 200, silver: 600, gold: 1500, daily: 450),
  'fruit_ninja': ArcadeDef(id: 'fruit_ninja', unitFa: 'امتیاز', unitEn: 'pts', bronze: 60, silver: 160, gold: 320, daily: 120),
  'geo_dash': ArcadeDef(id: 'geo_dash', unitFa: 'متر', unitEn: 'm', bronze: 150, silver: 500, gold: 1200, daily: 350),
  'traffic_racer': ArcadeDef(id: 'traffic_racer', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1500, silver: 5000, gold: 12000, daily: 4000),
  'stack_tower': ArcadeDef(id: 'stack_tower', unitFa: 'طبقه', unitEn: 'floors', bronze: 15, silver: 35, gold: 60, daily: 25),
  'bubble_shooter': ArcadeDef(id: 'bubble_shooter', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1500, silver: 5000, gold: 12000, daily: 3500),
  'knife_hit': ArcadeDef(id: 'knife_hit', unitFa: 'امتیاز', unitEn: 'pts', bronze: 40, silver: 120, gold: 260, daily: 90),
  'game_2048': ArcadeDef(id: 'game_2048', unitFa: 'امتیاز', unitEn: 'pts', bronze: 2000, silver: 8000, gold: 20000, daily: 5000),
  // multiplayer — "score" is the game's own match score; medals count wins in a row vs Hard bots
  'kart_racing': ArcadeDef(id: 'kart_racing', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1, silver: 3, gold: 5, daily: 1, multiplayer: true),
  'obstacle_race': ArcadeDef(id: 'obstacle_race', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1, silver: 3, gold: 5, daily: 1, multiplayer: true),
  'bomb_arena': ArcadeDef(id: 'bomb_arena', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1, silver: 3, gold: 5, daily: 1, multiplayer: true),
  'pool8': ArcadeDef(id: 'pool8', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1, silver: 3, gold: 5, daily: 1, multiplayer: true),
  'mini_golf': ArcadeDef(id: 'mini_golf', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1, silver: 3, gold: 5, daily: 1, multiplayer: true),
  'basketball_battle': ArcadeDef(id: 'basketball_battle', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1, silver: 3, gold: 5, daily: 1, multiplayer: true),
  'spy_mafia': ArcadeDef(id: 'spy_mafia', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1, silver: 3, gold: 5, daily: 1, multiplayer: true),
  'stickman_arena': ArcadeDef(id: 'stickman_arena', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1, silver: 3, gold: 5, daily: 1, multiplayer: true),
  'ludo_battle': ArcadeDef(id: 'ludo_battle', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1, silver: 3, gold: 5, daily: 1, multiplayer: true),
  'chess_blitz': ArcadeDef(id: 'chess_blitz', unitFa: 'امتیاز', unitEn: 'pts', bronze: 1, silver: 3, gold: 5, daily: 1, multiplayer: true),
};

/// Today's challenge (UTC day, identical on every phone).
class ArcadeDaily {
  const ArcadeDaily._();

  static String dayKey([DateTime? now]) {
    final DateTime d = (now ?? DateTime.now()).toUtc();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Deterministic seed for [gameId] on [day].
  static int seed(String gameId, [String? day]) {
    final String s = '$gameId|${day ?? dayKey()}';
    int h = 0x811c9dc5;
    for (final int c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  /// Score target for a solo game today (base ±20%, rounded to a friendly number).
  static int target(String gameId, [String? day]) {
    final ArcadeDef? d = kArcadeDefs[gameId];
    if (d == null) return 0;
    if (d.multiplayer) return 1;
    final double f = 0.85 + (seed(gameId, day) % 8) * 0.05;
    final int raw = (d.daily * f).round();
    final int step = raw >= 1000 ? 100 : (raw >= 100 ? 10 : 1);
    return math.max(1, (raw / step).round() * step);
  }
}

class ArcadeRecordResult {
  const ArcadeRecordResult({
    required this.score,
    required this.best,
    required this.newBest,
    required this.medal,
    required this.dailyTarget,
    required this.dailyDone,
    required this.dailyJustDone,
  });
  final int score;
  final int best;
  final bool newBest;
  final ArcadeMedal medal;
  final int dailyTarget;
  final bool dailyDone;
  final bool dailyJustDone;
}

/// Local + account-synced records. Bests are mirrored into [ProfileService.counters] (`best.<game>`,
/// `daily.<game>` = last completed day number) so they follow the account across phones.
class ArcadeRecords {
  const ArcadeRecords._();

  static LocalStore? get _s {
    try {
      return LocalStore.instance;
    } catch (_) {
      return null;
    }
  }

  static int best(String id, [ProfileService? p]) =>
      math.max(_s?.getInt('arcade.best.$id') ?? 0, p?.counter('best.$id') ?? 0);

  static int dayNumber([DateTime? now]) => (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 86400000;

  static bool dailyDone(String id, [ProfileService? p]) =>
      (_s?.getInt('arcade.daily.$id') ?? -1) == dayNumber() || (p?.counter('daily.$id') ?? -1) == dayNumber();

  /// Records a finished run. [dailyWon] is used by multiplayer games (won the daily match).
  static ArcadeRecordResult record(String id, int score, {ProfileService? profile, bool daily = false, bool? dailyWon}) {
    final ArcadeDef? def = kArcadeDefs[id];
    final int prev = best(id, profile);
    final bool newBest = score > prev;
    final int b = math.max(prev, score);
    final ArcadeMedal medal = def?.medalFor(score) ?? ArcadeMedal.none;
    final int target = ArcadeDaily.target(id);
    final bool was = dailyDone(id, profile);
    final bool reached = daily && (dailyWon ?? (score >= target));
    final LocalStore? st = _s;
    if (st != null) {
      unawaited(st.setInt('arcade.best.$id', b));
      if (reached) unawaited(st.setInt('arcade.daily.$id', dayNumber()));
    }
    if (profile != null) {
      profile.counters['best.$id'] = b;
      profile.bump('arcade.$id.runs');
      if (medal == ArcadeMedal.gold) profile.bump('arcade.medal.gold');
      if (medal.index >= ArcadeMedal.silver.index) profile.bump('arcade.medal.silver');
      if (reached && !was) {
        profile.counters['daily.$id'] = dayNumber();
        profile.bump('arcade.daily.done');
        profile.award('challenge.$id.${ArcadeDaily.dayKey()}',
            xp: 80, coins: 60, fa: 'چالش روزانه کامل شد', en: 'Daily challenge complete');
      }
    }
    return ArcadeRecordResult(
      score: score,
      best: b,
      newBest: newBest && score > 0,
      medal: medal,
      dailyTarget: target,
      dailyDone: reached || was,
      dailyJustDone: reached && !was,
    );
  }
}

/// Global score boards on the games project (server-validated).
class ArcadeOnline {
  const ArcadeOnline._();

  /// Submits a solo score. The server rejects impossible scores (rate / max limits) and rate-limits submits.
  static Future<Map<String, dynamic>?> submit(OnlineService o, String id, int score,
      {required int durationMs, bool daily = false, Map<String, dynamic>? meta}) async {
    try {
      final dynamic r = await o.grpc('nx_arcade_submit', <String, dynamic>{
        'p_game': id,
        'p_score': score,
        'p_duration_ms': durationMs,
        'p_daily': daily,
        'p_meta': meta ?? <String, dynamic>{},
      });
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (e) {
      debugPrint('arcade submit: $e');
      return null;
    }
  }

  /// Top scores: [daily] = today's challenge board, otherwise all-time bests.
  static Future<List<Map<String, dynamic>>> top(OnlineService o, String id, {bool daily = false, int limit = 50}) async {
    try {
      final dynamic r = await o.grpc('nx_arcade_top', <String, dynamic>{'p_game': id, 'p_daily': daily, 'p_limit': limit});
      if (r is List) return r.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('arcade top: $e');
    }
    return <Map<String, dynamic>>[];
  }
}

