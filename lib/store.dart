// Local profile store — port of src/store.tsx (same JSON key and shape, so the data model is unchanged).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/data.dart';

class Profile {
  String name = 'Pilot';
  int coins = 600, gems = 20, xp = 0, trophies = 0;
  int played = 0, wins = 0, losses = 0, draws = 0, goalsFor = 0, goalsAgainst = 0;
  String team = 'club0';
  int ball = 0, field = DEFAULT_FIELD, form = 0;
  List<String> ownedTeams = TEAMS.where((t) => teamPrice(t) == 0).map((t) => t.id).toList();
  List<int> ownedBalls = [for (var i = 0; i < 36; i++) if (ballPrice(i) == 0) i];
  List<int> ownedFields = [for (var i = 0; i < FIELDS.length; i++) if (fieldPrice(i) == 0) i, 7];
  int lastDaily = 0, streak = 0;
  bool sound = true, music = true, haptics = true;
  int aiLvl = 1, limit = 3, turnTime = 15;
  int cupsWon = 0, winStreak = 0, bestStreak = 0, chests = 1, lastChest = 0;
  List<String> claimedAch = [];
  String quality = 'high';
  double volume = 1;
  bool oracle = true, oracleTour = false;
  /// offline physics backend: 'classic' (bit-exact engine.ts port) | 'forge2d' (Box2D v3). Online is always classic.
  String physics = 'classic';
  int fieldsV = FIELDS_VERSION;

  Profile();

  Map<String, dynamic> toJson() => {
        'name': name, 'coins': coins, 'gems': gems, 'xp': xp, 'trophies': trophies,
        'played': played, 'wins': wins, 'losses': losses, 'draws': draws, 'goalsFor': goalsFor, 'goalsAgainst': goalsAgainst,
        'team': team, 'ball': ball, 'field': field, 'form': form,
        'ownedTeams': ownedTeams, 'ownedBalls': ownedBalls, 'ownedFields': ownedFields,
        'lastDaily': lastDaily, 'streak': streak, 'sound': sound, 'music': music, 'haptics': haptics,
        'aiLvl': aiLvl, 'limit': limit, 'turnTime': turnTime, 'cupsWon': cupsWon, 'winStreak': winStreak,
        'bestStreak': bestStreak, 'chests': chests, 'lastChest': lastChest, 'claimedAch': claimedAch,
        'quality': quality, 'volume': volume, 'oracle': oracle, 'oracleTour': oracleTour, 'fieldsV': fieldsV, 'physics': physics,
      };

  static Profile fromJson(Map<String, dynamic> j) {
    final p = Profile();
    T g<T>(String k, T d) {
      final v = j[k];
      if (v == null) return d;
      if (d is int && v is num) return v.toInt() as T;
      if (d is double && v is num) return v.toDouble() as T;
      return v is T ? v : d;
    }

    p.name = g('name', p.name); p.coins = g('coins', p.coins); p.gems = g('gems', p.gems); p.xp = g('xp', p.xp);
    p.trophies = g('trophies', p.trophies); p.played = g('played', 0); p.wins = g('wins', 0); p.losses = g('losses', 0);
    p.draws = g('draws', 0); p.goalsFor = g('goalsFor', 0); p.goalsAgainst = g('goalsAgainst', 0);
    p.team = g('team', p.team); p.ball = g('ball', 0); p.field = g('field', p.field); p.form = g('form', 0);
    p.ownedTeams = (j['ownedTeams'] as List?)?.cast<String>() ?? p.ownedTeams;
    p.ownedBalls = (j['ownedBalls'] as List?)?.map((e) => (e as num).toInt()).toList() ?? p.ownedBalls;
    p.ownedFields = (j['ownedFields'] as List?)?.map((e) => (e as num).toInt()).toList() ?? p.ownedFields;
    p.lastDaily = g('lastDaily', 0); p.streak = g('streak', 0); p.sound = g('sound', true); p.music = g('music', true);
    p.haptics = g('haptics', true); p.aiLvl = g('aiLvl', 1); p.limit = g('limit', 3); p.turnTime = g('turnTime', 15);
    p.cupsWon = g('cupsWon', 0); p.winStreak = g('winStreak', 0); p.bestStreak = g('bestStreak', 0); p.chests = g('chests', 1);
    p.lastChest = g('lastChest', 0); p.claimedAch = (j['claimedAch'] as List?)?.cast<String>() ?? [];
    p.quality = g('quality', 'high'); p.volume = g('volume', 1.0); p.oracle = g('oracle', true); p.oracleTour = g('oracleTour', false);
    p.fieldsV = g('fieldsV', 1);
    p.physics = g('physics', 'classic');
    return p;
  }
}

final _freeFields = [for (var i = 0; i < FIELDS.length; i++) if (fieldPrice(i) == 0) i];

/// saved profiles from before the NEXORA Pitch was prepended (fieldsV < 2) store old field indices
Profile migrate(Profile n) {
  if (n.fieldsV < 2) {
    final old = n.field;
    n.ownedFields = n.ownedFields.map((i) => i + 1).toList();
    n.field = old == 6 ? DEFAULT_FIELD : old + 1;
    n.fieldsV = 2;
  }
  n.ownedFields = {..._freeFields, 7, ...n.ownedFields}.where((i) => i >= 0 && i < FIELDS.length).toList();
  if (!(n.field >= 0 && n.field < FIELDS.length) || !n.ownedFields.contains(n.field)) n.field = DEFAULT_FIELD;
  n.ownedTeams = {...TEAMS.where((t) => teamPrice(t) == 0).map((t) => t.id), ...n.ownedTeams}.toList();
  if (!TEAMS.any((t) => t.id == n.team)) n.team = 'club0';
  return n;
}

class Lvl {
  final int level, cur, need;
  const Lvl(this.level, this.cur, this.need);
}

Lvl level(int xp) {
  var l = 1, need = 100, x = xp;
  while (x >= need) {
    x -= need;
    l++;
    need = (need * 1.25).round();
  }
  return Lvl(l, x, need);
}

const LEAGUES = [('BRONZE', 0), ('SILVER', 300), ('GOLD', 800), ('PLATINUM', 1600), ('DIAMOND', 3000), ('NEXORA', 5000)];
const LEAGUE_FA = {'BRONZE': 'برنز', 'SILVER': 'نقره', 'GOLD': 'طلا', 'PLATINUM': 'پلاتین', 'DIAMOND': 'الماس', 'NEXORA': 'نکسورا'};

({String name, int idx, int from, int to}) league(int t) {
  var i = 0;
  while (i + 1 < LEAGUES.length && t >= LEAGUES[i + 1].$2) {
    i++;
  }
  return (name: LEAGUES[i].$1, idx: i, from: LEAGUES[i].$2, to: i + 1 < LEAGUES.length ? LEAGUES[i + 1].$2 : LEAGUES[i].$2 + 2000);
}

class Store extends ChangeNotifier {
  Store._();
  static final Store I = Store._();
  static const KEY = 'nexora.profile.v1';
  Profile p = Profile();
  bool ready = false;
  Timer? _save;

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString(KEY);
      if (s != null) p = migrate(Profile.fromJson(jsonDecode(s) as Map<String, dynamic>));
    } catch (_) {}
    ready = true;
    notifyListeners();
  }

  /// mutate the profile and persist (debounced 250 ms like the RN store)
  void set(void Function(Profile p) u) {
    u(p);
    notifyListeners();
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 250), () async {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(KEY, jsonEncode(p.toJson()));
    });
  }

  Future<void> reset() async {
    p = Profile();
    notifyListeners();
    (await SharedPreferences.getInstance()).remove(KEY);
  }
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;
int clampI(int v, int a, int b) => math.max(a, math.min(b, v));
