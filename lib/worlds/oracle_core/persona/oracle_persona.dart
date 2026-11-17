/// ORACLE personality engine (pure Dart, no Flutter imports — unit-testable).
///
/// Modules (all driven by the JSON config in [kOraclePersonaDefaults], overridable from Supabase):
///  * [OracleNameMatcher]     — Persian NLU for player names (normalisation, ZWNJ, ی/ي ک/ك, Latin spellings, suffixes, fuzzy).
///  * [OracleCooldowns]       — per-category and global cooldowns with an injectable clock.
///  * [OracleShuffleBag]      — no-repeat line picking (a pool is exhausted before any line repeats).
///  * [OraclePersona]         — personalised replies, "{jan}" replies, login greetings, spontaneous lines,
///                              win/lose reactions from real results, funny tutorials, AI context for nx-oracle.
library;

import 'dart:math' as math;

import '../core/oracle_text.dart';
import 'oracle_persona_data.dart';

// ======================================================================== helpers

int _lev(String a, String b, int cap) {
  if ((a.length - b.length).abs() > cap) return cap + 1;
  List<int> prev = List<int>.generate(b.length + 1, (int i) => i);
  for (int i = 1; i <= a.length; i++) {
    final List<int> cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    int rowMin = cur[0];
    for (int j = 1; j <= b.length; j++) {
      final int cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      if (cur[j] < rowMin) rowMin = cur[j];
    }
    if (rowMin > cap) return cap + 1;
    prev = cur;
  }
  return prev[b.length];
}

/// Normalises like the intent engine and also squeezes stretched letters ("جاااان" → "جان", "oracleee" → "oracle").
String oraclePersonaNorm(String s) {
  final String t = normalizeOracleText(s);
  return t.replaceAllMapped(RegExp(r'(.)\1{2,}'), (Match m) => m[1]!);
}

List<String> _strList(Object? o) => o is List ? o.map((Object? e) => '$e').where((String e) => e.isNotEmpty).toList() : <String>[];

Map<String, dynamic> _deepMerge(Map<String, dynamic> base, Map<String, dynamic> over) {
  final Map<String, dynamic> out = Map<String, dynamic>.from(base);
  over.forEach((String k, dynamic v) {
    final dynamic b = out[k];
    if (v is Map && b is Map) {
      out[k] = _deepMerge(Map<String, dynamic>.from(b), Map<String, dynamic>.from(v));
    } else if (v != null) {
      out[k] = v;
    }
  });
  return out;
}

// ======================================================================== cooldowns / no-repeat

class OracleCooldowns {
  OracleCooldowns({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final Map<String, DateTime> _last = <String, DateTime>{};

  DateTime get now => _clock();

  bool ready(String key, Duration gap) {
    final DateTime? l = _last[key];
    return l == null || now.difference(l) >= gap;
  }

  void mark(String key) => _last[key] = now;

  /// True (and marks) when [key] is out of cooldown.
  bool take(String key, Duration gap) {
    if (!ready(key, gap)) return false;
    mark(key);
    return true;
  }

  void reset() => _last.clear();
}

/// Picks lines without repeating any until the whole pool was used; never repeats the last line across refills.
class OracleShuffleBag {
  OracleShuffleBag(this._rng);
  final math.Random _rng;
  final Map<String, List<int>> _left = <String, List<int>>{};
  final Map<String, int> _lastIdx = <String, int>{};

  T? pick<T>(String key, List<T> pool) {
    if (pool.isEmpty) return null;
    List<int>? left = _left[key];
    if (left == null || left.isEmpty || left.any((int i) => i >= pool.length)) {
      left = List<int>.generate(pool.length, (int i) => i);
      final int? last = _lastIdx[key];
      if (last != null && pool.length > 1) left.remove(last);
      _left[key] = left;
    }
    final int idx = left.removeAt(_rng.nextInt(left.length));
    _lastIdx[key] = idx;
    return pool[idx];
  }
}

// ======================================================================== players / NLU

class OraclePlayer {
  OraclePlayer({required this.id, required this.name, required this.aliases, required this.lines, this.traits = '', this.fixed = false});
  final String id;
  final String name;
  final List<String> aliases;
  final List<String> lines;
  final String traits;
  final bool fixed;

  factory OraclePlayer.fromJson(Map<String, dynamic> j) => OraclePlayer(
        id: '${j['id'] ?? j['name']}',
        name: '${j['name'] ?? ''}',
        aliases: _strList(j['aliases']),
        lines: _strList(j['lines']),
        traits: '${j['traits'] ?? ''}',
        fixed: j['fixed'] == true,
      );
}

class OraclePlayerMatch {
  const OraclePlayerMatch(this.player, this.score, this.exact, {this.ambiguous = const <OraclePlayer>[]});
  final OraclePlayer? player;
  final int score;
  final bool exact;
  final List<OraclePlayer> ambiguous;
  bool get isAmbiguous => ambiguous.length > 1;
}

class OracleNameMatcher {
  OracleNameMatcher(this.players) {
    for (final OraclePlayer p in players) {
      final Set<String> keys = <String>{};
      for (final String k in <String>[p.name, ...p.aliases]) {
        final String n = oraclePersonaNorm(k);
        if (n.isNotEmpty) keys.add(n.replaceAll(' ', ''));
      }
      _keys[p] = keys.toList();
      final List<String> first = oraclePersonaNorm(p.name).split(' ');
      if (first.length > 1) _firstWords.putIfAbsent(first.first, () => <OraclePlayer>[]).add(p);
    }
  }

  final List<OraclePlayer> players;
  final Map<OraclePlayer, List<String>> _keys = <OraclePlayer, List<String>>{};
  final Map<String, List<OraclePlayer>> _firstWords = <String, List<OraclePlayer>>{};

  static const List<String> _suffixes = <String>['رو', 'و', 'ی', 'ه', 'ا', 'ها', 'جان', 'جون', 'خان'];

  static int _allowed(String key) => key.length >= 7 ? 2 : key.length >= 5 ? 1 : 0;

  int _scoreWindow(String w, String key) {
    if (w == key) return 1000 + key.length * 10;
    for (final String s in _suffixes) {
      if (w.length > key.length && w.endsWith(s) && w.substring(0, w.length - s.length) == key) return 900 + key.length * 10;
    }
    final int a = _allowed(key);
    if (a > 0) {
      final int d = _lev(w, key, a);
      if (d <= a) return 500 + key.length * 10 - d * 60;
    }
    return 0;
  }

  /// Best player mentioned in [text]; ambiguous when a bare shared first word ("آرش", "لیلا") is all that matched.
  OraclePlayerMatch? match(String text) {
    final List<String> toks = oraclePersonaNorm(text).split(' ').where((String t) => t.isNotEmpty).toList();
    if (toks.isEmpty) return null;
    final Map<OraclePlayer, int> best = <OraclePlayer, int>{};
    for (int i = 0; i < toks.length; i++) {
      for (int n = 1; n <= 4 && i + n <= toks.length; n++) {
        final String w = toks.sublist(i, i + n).join();
        for (final OraclePlayer p in players) {
          for (final String key in _keys[p]!) {
            final int sc = _scoreWindow(w, key);
            if (sc > (best[p] ?? 0)) best[p] = sc;
          }
        }
      }
    }
    if (best.isEmpty) {
      for (final String t in toks) {
        final List<OraclePlayer>? amb = _firstWords[t];
        if (amb != null && amb.length > 1) return OraclePlayerMatch(null, 0, false, ambiguous: amb);
      }
      return null;
    }
    final int top = best.values.reduce(math.max);
    final List<OraclePlayer> winners = best.entries.where((MapEntry<OraclePlayer, int> e) => e.value == top).map((e) => e.key).toList();
    if (winners.length > 1) return OraclePlayerMatch(null, top, top >= 900, ambiguous: winners);
    return OraclePlayerMatch(winners.first, top, top >= 900);
  }

  /// Recognises a display name (whole name, typo-tolerant) — used for login greetings.
  OraclePlayer? byDisplayName(String displayName) {
    final String w = oraclePersonaNorm(displayName).replaceAll(' ', '');
    if (w.isEmpty) return null;
    OraclePlayer? bestP;
    int bestS = 0;
    for (final OraclePlayer p in players) {
      for (final String key in _keys[p]!) {
        final int sc = _scoreWindow(w, key);
        if (sc > bestS) {
          bestS = sc;
          bestP = p;
        }
      }
    }
    return bestP;
  }
}

// ======================================================================== tutorials

class OracleTutorial {
  const OracleTutorial({required this.game, required this.id, required this.title, required this.line, required this.how});
  final String game;
  final String id;
  final String title;
  final String line;
  final String how;
  String get key => '$game.$id';
}

// ======================================================================== persona

class OraclePersona {
  OraclePersona({Map<String, dynamic>? config, math.Random? rng, DateTime Function()? clock})
      : rng = rng ?? math.Random(),
        cooldowns = OracleCooldowns(clock: clock) {
    bag = OracleShuffleBag(this.rng);
    applyConfig(config);
  }

  /// App-wide instance (the store replaces its config with the admin-edited one from Supabase).
  static OraclePersona instance = OraclePersona();

  final math.Random rng;
  final OracleCooldowns cooldowns;
  late OracleShuffleBag bag;
  late Map<String, dynamic> cfg;
  late OracleNameMatcher matcher;

  /// Session context (no fake long-term memory: only what happened in this app session).
  String displayName = '';
  int sessionMatches = 0;
  String? lastOutcome;

  void applyConfig(Map<String, dynamic>? over) {
    cfg = over == null ? Map<String, dynamic>.from(kOraclePersonaDefaults) : _deepMerge(kOraclePersonaDefaults, over);
    final List<OraclePlayer> ps = <OraclePlayer>[];
    final Object? raw = cfg['players'];
    if (raw is List) {
      for (final Object? e in raw) {
        if (e is Map && e['disabled'] != true && '${e['name'] ?? ''}'.trim().isNotEmpty) {
          ps.add(OraclePlayer.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    matcher = OracleNameMatcher(ps);
  }

  List<OraclePlayer> get players => matcher.players;

  bool on(String category) => (cfg['enabled'] as Map?)?[category] != false;
  double _f(String k, double d) => ((cfg['freq'] as Map?)?[k] as num?)?.toDouble() ?? d;
  bool _chance(double p) => p >= 1 || (p > 0 && rng.nextDouble() < p);

  // ---------------------------------------------------------------- signature

  /// The stretched signature "جاااااااااان" (10 ا by default; naturally varies between min and max).
  String jan() {
    final Map<dynamic, dynamic> s = (cfg['jan_stretch'] as Map?) ?? const <String, int>{};
    final int lo = (s['min'] as num?)?.toInt() ?? 8, hi = (s['max'] as num?)?.toInt() ?? 13, base = (s['base'] as num?)?.toInt() ?? 10;
    final int n = rng.nextDouble() < .55 ? base : lo + rng.nextInt(math.max(1, hi - lo + 1));
    return 'ج${'ا' * n}ن';
  }

  static final RegExp _shortJan = RegExp(r'(^|[\s\n«"(])جان(?=[!؟?\s\n.،]|$)');

  /// Fills `{jan}`, `{name}`, `{score}`, `{names}` and upgrades any short signature "جان" to the stretched form.
  String render(String line, {String? name, String? score, String? names}) {
    String s = line.replaceAllMapped(RegExp(r'\{jan\}'), (_) => jan());
    s = s.replaceAllMapped(_shortJan, (Match m) => '${m[1]}${jan()}');
    if (name != null) s = s.replaceAll('{name}', name);
    if (score != null) s = s.replaceAll('{score}', score);
    if (names != null) s = s.replaceAll('{names}', names);
    return s;
  }

  // ---------------------------------------------------------------- players

  static const List<String> _aboutWords = <String>[
    'کیه', 'کی هست', 'کی بود', 'کیست', 'درباره', 'دربارهی', 'راجب', 'راجع', 'نظرت', 'میشناسی', 'می شناسی', 'معرفی', 'بگو',
    'تعریف کن', 'چطوره', 'چجوریه', 'چه جوریه', 'who is', 'who s', 'whos', 'about', 'tell me', 'do you know', 'know',
  ];

  bool _about(String norm) => hasOracleKeyword(norm, _aboutWords);

  /// A personalised reply when the message asks about (or just names) a known player; null otherwise.
  String? playerReply(String input) {
    if (!on('players')) return null;
    final String norm = oraclePersonaNorm(input);
    final int tokens = norm.split(' ').where((String t) => t.isNotEmpty).length;
    final OraclePlayerMatch? m = matcher.match(input);
    if (m == null) return null;
    final bool about = _about(norm);
    if (!about && tokens > 3) return null;
    if (m.isAmbiguous) {
      return render('${cfg['ambiguous_player']}', names: m.ambiguous.map((OraclePlayer p) => p.name).join(' یا '));
    }
    final OraclePlayer p = m.player!;
    if (!m.exact && !about) return null; // a lone typo-ish word is not enough
    final String? line = bag.pick<String>('player.${p.id}', p.lines);
    if (line == null) return render('${cfg['unknown_player']}');
    final String body = render(line);
    // occasionally a playful signature tail (never on every reply, never when the line already has it)
    if (!body.contains('جاا') && on('jan') && rng.nextInt(4) == 0) return '$body\n${jan()}!';
    return body;
  }

  static final RegExp _whoIsPattern = RegExp(r'(\S+)\s+(کیه|کی هست|کیست|رو میشناسی|را میشناسی|رو می شناسی|رو معرفی کن)$');
  static const Set<String> _notNames = <String>{'تو', 'من', 'اون', 'این', 'اوراکل', 'oracle', 'سازنده', 'صاحب', 'کی', 'چی'};

  /// "X کیه؟" for a name that is not in the profile DB → honest "don't know yet" (never invents facts).
  String? unknownPlayerReply(String input) {
    if (!on('players')) return null;
    final String norm = oraclePersonaNorm(input);
    final Match? m = _whoIsPattern.firstMatch(norm);
    final RegExp en = RegExp(r'^(who is|whos|who s|do you know)\s+([a-z]+)');
    final Match? e = en.firstMatch(norm);
    final String? word = m?.group(1) ?? e?.group(2);
    if (word == null || _notNames.contains(word)) return null;
    if (matcher.match(input) != null) return null;
    return render('${cfg['unknown_player']}');
  }

  // ---------------------------------------------------------------- jan replies / wake

  /// "{jan}" reply for common requests ("بریم مسابقه؟" → "جاااااااااان! بزن بریم قهرمان!").
  String? janReply(String input) {
    if (!on('jan')) return null;
    final String padded = ' ${oraclePersonaNorm(input)} ';
    final Object? raw = cfg['jan_replies'];
    if (raw is! List) return null;
    for (final Object? r in raw) {
      if (r is! Map) continue;
      for (final String p in _strList(r['patterns'])) {
        final String np = oraclePersonaNorm(p);
        if (np.isNotEmpty && (padded.contains(' $np ') || padded.replaceAll(' ', '').contains(np.replaceAll(' ', '')))) {
          return render('${r['reply']}');
        }
      }
    }
    return null;
  }

  /// A bare call ("اوراکل!", "oracle") → "جاااااااااان؟" and wait.
  String? wakeReply(String input) {
    if (!on('jan')) return null;
    final String n = oraclePersonaNorm(input);
    if (n.isEmpty) return null;
    for (final String w in _strList(cfg['wake_words'])) {
      if (oraclePersonaNorm(w) == n) return render('${cfg['jan_wait']}');
    }
    return null;
  }

  // ---------------------------------------------------------------- login greetings

  /// Lines to show one after another at login; empty = stay silent this time. Uses the REAL display name and never
  /// claims that another player logged in (the "Original" joke always ends by admitting the mix-up).
  List<String> loginGreeting(String name) {
    displayName = name;
    if (!on('greetings') || !_chance(_f('login_greeting_chance', .55))) return const <String>[];
    final OraclePlayer? me = matcher.byDisplayName(name);
    if (me?.id == 'original') {
      final List<String>? v = bag.pick<List<String>>('login.self', _lists(cfg['login_self_original']));
      if (v != null) return v.map((String l) => render(l, name: name)).toList();
    }
    final List<String> out = <String>[];
    if (_chance(_f('login_original_joke_chance', .6))) {
      final List<String>? v = bag.pick<List<String>>('login.joke', _lists(cfg['login_greetings']));
      if (v != null) out.addAll(v.map((String l) => render(l, name: name)));
    } else {
      final String? l = bag.pick<String>('login.plain', _strList(cfg['login_plain']));
      if (l != null && name.trim().isNotEmpty) out.add(render(l, name: name));
    }
    // Recognised player → their personalised line after the greeting.
    if (me != null && me.lines.isNotEmpty) {
      final String? pl = bag.pick<String>('player.${me.id}', me.lines);
      if (pl != null) out.add(render(pl));
    }
    return out;
  }

  static List<List<String>> _lists(Object? o) =>
      o is List ? o.whereType<List<dynamic>>().map((List<dynamic> l) => l.map((dynamic e) => '$e').toList()).where((List<String> l) => l.isNotEmpty).toList() : <List<String>>[];

  // ---------------------------------------------------------------- spontaneous

  /// A context line (enter / waiting / match / idle / funny / unexpected / tease) or null (cooldown, chance, disabled).
  String? spontaneous(String context, {bool force = false}) {
    if (!on('spontaneous')) return null;
    final Map<dynamic, dynamic>? sp = cfg['spontaneous'] as Map?;
    final List<String> pool = _strList(sp?[context]);
    if (pool.isEmpty) return null;
    final Duration g = Duration(seconds: _f('spontaneous_global_gap_sec', 40).round());
    final Duration c = Duration(seconds: _f('spontaneous_category_gap_sec', 150).round());
    if (!force) {
      if (!cooldowns.ready('sp.global', g) || !cooldowns.ready('sp.$context', c)) return null;
      if (!_chance(_f('spontaneous_chance', .55))) {
        cooldowns.mark('sp.global'); // stay silent for a while
        return null;
      }
    }
    cooldowns
      ..mark('sp.global')
      ..mark('sp.$context');
    final String? l = bag.pick<String>('sp.$context', pool);
    return l == null ? null : render(l, name: displayName);
  }

  // ---------------------------------------------------------------- results

  /// Reaction to a REAL finished match (outcome: win | loss | draw). Null when disabled / by chance.
  String? resultReaction({required String outcome, int myScore = 0, int oppScore = 0, bool force = false}) {
    sessionMatches++;
    lastOutcome = outcome;
    if (!on('results') || (!force && !_chance(_f('result_chance', .9)))) return null;
    final int big = _f('margin_big', 3).round();
    final int margin = myScore - oppScore;
    final String cat = switch (outcome) {
      'win' => margin >= big ? 'great' : 'win',
      'loss' => -margin >= big ? (rng.nextBool() ? 'bad' : 'lose') : 'lose',
      _ => 'draw',
    };
    final Map<dynamic, dynamic>? r = cfg['results'] as Map?;
    List<String> pool = _strList(r?[cat]);
    if (pool.isEmpty) pool = _strList(r?[outcome == 'win' ? 'win' : outcome == 'loss' ? 'lose' : 'draw']);
    final String? l = bag.pick<String>('res.$cat', pool);
    return l == null ? null : render(l, name: displayName, score: '$myScore-$oppScore');
  }

  // ---------------------------------------------------------------- tutorials

  List<OracleTutorial> tutorials(String game) {
    final Object? raw = (cfg['tutorials'] as Map?)?[game];
    if (raw is! List) return const <OracleTutorial>[];
    return <OracleTutorial>[
      for (final Object? e in raw)
        if (e is Map && e['disabled'] != true)
          OracleTutorial(
              game: game, id: '${e['id']}', title: '${e['title'] ?? ''}', line: render('${e['line'] ?? ''}'), how: '${e['how'] ?? ''}'),
    ];
  }

  /// Next tutorial to show automatically for [game]: the least-seen mechanic that is still under the view limit.
  /// Experienced players (every mechanic seen enough) get nothing; [force] replays anyway.
  OracleTutorial? nextTutorial(String game, Map<String, int> views, {bool force = false}) {
    if (!on('tutorials') && !force) return null;
    final List<OracleTutorial> all = tutorials(game);
    if (all.isEmpty) return null;
    final int limit = _f('tutorial_auto_views', 2).round();
    final List<OracleTutorial> cands = force ? all : all.where((OracleTutorial t) => (views[t.key] ?? 0) < limit).toList();
    if (cands.isEmpty) return null;
    final int minV = cands.map((OracleTutorial t) => views[t.key] ?? 0).reduce(math.min);
    final List<OracleTutorial> least = cands.where((OracleTutorial t) => (views[t.key] ?? 0) == minV).toList();
    return bag.pick<OracleTutorial>('tut.$game.$minV', least);
  }

  // ---------------------------------------------------------------- AI context

  /// Compact persona context for the nx-oracle Edge Function (matched players' verified lines only; no invented facts).
  Map<String, dynamic> aiContext(String input) {
    final OraclePlayerMatch? m = matcher.match(input);
    final List<OraclePlayer> ps = <OraclePlayer>[
      if (m?.player != null) m!.player!,
      ...?m?.ambiguous,
    ];
    final OraclePlayer? me = displayName.isEmpty ? null : matcher.byDisplayName(displayName);
    return <String, dynamic>{
      'display_name': displayName,
      if (me != null) 'me_profile': me.id,
      'players': <Map<String, dynamic>>[
        for (final OraclePlayer p in ps) <String, dynamic>{'id': p.id, 'name': p.name, 'lines': p.lines, 'traits': p.traits},
      ],
      'session': <String, dynamic>{'matches': sessionMatches, if (lastOutcome != null) 'last_result': lastOutcome},
    };
  }
}

// ======================================================================== guided tour (pure part)

class OracleTourStep {
  const OracleTourStep({this.target, required this.title, required this.text});
  final String? target;
  final String title;
  final String text;
}

extension OraclePersonaTour on OraclePersona {
  /// Section id for a route path (null = no tour there). Game lobbies are per game ("game_setup.ID").
  static String? sectionForPath(String path) {
    final List<String> seg = path.split('/').where((String s) => s.isNotEmpty).toList();
    if (seg.isEmpty) return null;
    switch (seg.first) {
      case 'hub':
        return 'home';
      case 'rooms':
        return 'rooms';
      case 'social':
        return 'social';
      case 'settings':
        return 'settings';
      case 'oracle':
        return 'oracle';
      case 'admin':
        return 'admin';
      case 'tournaments':
        return seg.length == 1 ? 'tournaments' : null;
      case 'arcade':
        return seg.length == 2 ? 'game_setup.${seg[1]}' : null;
      case 'world':
        if (seg.length < 2) return null;
        return switch (seg[1]) {
          'nexora_arcade' => 'games',
          'nexora_exchange' => 'shop',
          'orbit_network' => 'chat',
          'personal_orbit' => 'profile',
          _ => null,
        };
    }
    return null;
  }

  /// Steps for [section] (rendered: stretched signature etc.). "game_setup.ID" uses the shared game_setup steps.
  List<OracleTourStep> tourSteps(String section) {
    final String key = section.startsWith('game_setup.') ? 'game_setup' : section;
    final Object? raw = (cfg['tours'] as Map?)?[key];
    if (raw is! List || !on('tour')) return const <OracleTourStep>[];
    return <OracleTourStep>[
      for (final Object? e in raw)
        if (e is Map && e['disabled'] != true)
          OracleTourStep(
            target: e['target'] == null ? null : '${e['target']}',
            title: render('${e['title'] ?? ''}'),
            text: render('${e['text'] ?? ''}', name: displayName),
          ),
    ];
  }
}
