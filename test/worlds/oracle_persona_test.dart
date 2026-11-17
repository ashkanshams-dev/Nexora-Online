import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/worlds/oracle_core/core/oracle_brain.dart';
import 'package:nexora/worlds/oracle_core/persona/oracle_persona.dart';
import 'package:nexora/worlds/oracle_core/persona/oracle_persona_data.dart';

final RegExp janRe = RegExp('جا{8,13}ن');

OraclePersona _p({DateTime Function()? clock, int seed = 7, Map<String, dynamic>? cfg}) =>
    OraclePersona(rng: math.Random(seed), clock: clock, config: cfg);

void main() {
  group('name recognition', () {
    final OraclePersona p = _p();

    test('all 39 players are configured', () {
      expect(p.players.length, 39);
    });

    const Map<String, String> cases = <String, String>{
      'نظرت درباره کاکرو چیه؟': 'kakaro',
      'صابر کیه؟': 'saber',
      'درباره اورجینال بگو': 'original',
      'مهیار رو می‌شناسی؟': 'mahyar',
      'اسکورپیون رو معرفی کن': 'scorpion',
      'who is pedro': 'pedro',
      'denny kie?': 'denny',
      'mahyar ro mishnasi': 'mahyar',
      'اوریجینال کیه': 'original',
      'orginal': 'original',
      'علي‌گاد كيه؟': 'ali_god', // Arabic ي/ك + ZWNJ
      'علی گاد کیه': 'ali_god',
      'امیر افسانه ها کیه': 'amir_afsaneha',
      'لیلا نور کیه': 'leila_noor',
      'نور کیه': 'noor',
      'امیر نور رو میشناسی': 'amir_noor',
      'عارفه کیه': 'arefe',
      'عارف کیه': 'aref',
      'حسین آ کیه': 'hossein_a',
      'آرش سیبیل کیه': 'arash_sibil',
      'arash perfect kie': 'arash_perfect',
      'کاپیتان فرشید کیه': 'captain_farshid',
      'scorpian': 'scorpion',
      'Shaadow kie': 'shadow',
      'رو اینفانتینو کیه': 'ro_infantino',
      'مرضیه کیه': 'marzieh',
      'یحیی کیه': 'yahya',
      'کاکرو رو': 'kakaro',
      'صابرو میشناسی': 'saber',
    };
    cases.forEach((String input, String id) {
      test('"$input" → $id', () {
        final OraclePlayerMatch? m = p.matcher.match(input);
        expect(m, isNotNull);
        expect(m!.isAmbiguous, isFalse, reason: m.ambiguous.map((OraclePlayer e) => e.id).join(','));
        expect(m.player!.id, id);
      });
    });

    test('Pedro, Denny and Mahyar are never merged', () {
      expect(p.matcher.match('pedro')!.player!.id, 'pedro');
      expect(p.matcher.match('denny')!.player!.id, 'denny');
      expect(p.matcher.match('mahyar')!.player!.id, 'mahyar');
      expect(p.matcher.match('پدرو')!.player!.id, 'pedro');
      expect(p.matcher.match('دنی')!.player!.id, 'denny');
      expect(p.matcher.match('مهیار')!.player!.id, 'mahyar');
    });

    test('bare shared first name is ambiguous', () {
      final OraclePlayerMatch? m = p.matcher.match('آرش کیه');
      expect(m, isNotNull);
      expect(m!.isAmbiguous, isTrue);
      expect(p.playerReply('آرش کیه'), contains('آرش سیبیل'));
    });

    test('ordinary words do not trigger a player', () {
      expect(p.matcher.match('سلام خوبی'), isNull);
      expect(p.matcher.match('قوانین لودو رو بگو'), isNull);
      expect(p.playerReply('امروز خیلی شادی کردم'), isNull);
    });

    test('display name recognition (login)', () {
      expect(p.matcher.byDisplayName('Original')!.id, 'original');
      expect(p.matcher.byDisplayName('AliGod')!.id, 'ali_god');
      expect(p.matcher.byDisplayName('xyz123'), isNull);
    });
  });

  group('personalised replies', () {
    test('fixed lines are preserved verbatim (with stretched signature)', () {
      final OraclePersona p = _p();
      expect(p.playerReply('صابر کیه؟'), startsWith('مردی که همیشه صورتیه و صورتی رو دوست داره!'));
      expect(p.playerReply('پدرو کیه'), startsWith('پدرو... هشتاد و پنج کی بودی؟\nپدرو هشتاد و پنج!'));
      final String k = p.playerReply('کاکرو کیه')!;
      expect(k, matches(RegExp('^جا{8,13}ن امام رو بگیر!')));
      final String o = p.playerReply('اورجینال کیه')!;
      expect(o, startsWith('اورجینال سلطان تله‌های نامنظم!\nکسی که باخت و هیچ‌وقت امضا نکرد.\n'));
      expect(o, matches(RegExp('جا{8,13}ن تله رو بگیر!')));
    });

    test('unknown name → honest reply, never invented', () {
      final OraclePersona p = _p();
      final String r = p.unknownPlayerReply('بهرام کیه؟')!;
      expect(r, contains('هنوز درست نمی‌شناسم'));
      expect(r, matches(janRe));
      expect(p.unknownPlayerReply('تو کیه'), isNull);
    });
  });

  group('signature catchphrase', () {
    test('always stretched, never the short form', () {
      final OraclePersona p = _p();
      for (int i = 0; i < 50; i++) {
        final String j = p.jan();
        expect(j, matches(RegExp(r'^جا{8,13}ن$')));
      }
      expect(p.render('جان! گل‌کوچیکو بگیر!'), matches(RegExp(r'^جا{8,13}ن! گل‌کوچیکو بگیر!$')));
      expect(p.render('{jan} بزن بریم قهرمان!'), matches(RegExp(r'^جا{8,13}ن! ?بزن بریم قهرمان!$|^جا{8,13}ن بزن بریم قهرمان!$')));
      // words that merely contain جان are not touched
      expect(p.render('جانور'), 'جانور');
    });

    test('no short "جان" signature remains in any default line', () {
      final OraclePersona p = _p();
      final List<String> all = <String>[];
      void collect(Object? o) {
        if (o is String) all.add(o);
        if (o is List) o.forEach(collect);
        if (o is Map) o.values.forEach(collect);
      }

      collect(kOraclePersonaDefaults);
      for (final String s in all) {
        expect(p.render(s).contains(RegExp(r'(^|\s)جان[!؟?\s]')), isFalse, reason: s);
      }
    });

    test('jan replies for the spec examples', () {
      final OraclePersona p = _p();
      expect(p.janReply('می‌خوام گل‌کوچیک بازی کنم.'), matches(RegExp(r'^جا{8,13}ن گل‌کوچیکو بگیر!$')));
      expect(p.janReply('بریم مسابقه؟'), matches(RegExp(r'^جا{8,13}ن بزن بریم قهرمان!$')));
      expect(p.janReply('نظرت چیه؟'), matches(RegExp(r'^جا{8,13}ن چی رو می‌خوای بدونی؟$')));
      expect(p.janReply('بریم تمرین؟'), matches(RegExp(r'^جا{8,13}ن تمرین رو بترکون!$')));
      expect(p.janReply('چیکار کنم؟'), contains('تله'));
      expect(p.janReply('بازی شروع کنیم؟'), contains('توپ رو بنداز وسط'));
      expect(p.wakeReply('اوراکل'), matches(RegExp(r'^جا{8,13}ن؟$')));
      expect(p.wakeReply('Oracleee'), isNotNull);
    });
  });

  group('cooldowns and no-repeat', () {
    test('shuffle bag never repeats before the pool is exhausted', () {
      final OracleShuffleBag bag = OracleShuffleBag(math.Random(1));
      final List<int> pool = List<int>.generate(9, (int i) => i);
      final Set<int> first = <int>{for (int i = 0; i < 9; i++) bag.pick<int>('k', pool)!};
      expect(first.length, 9);
      int last = -1;
      for (int round = 0; round < 6; round++) {
        final List<int> picks = <int>[for (int i = 0; i < 8; i++) bag.pick<int>('k', pool)!];
        expect(picks.toSet().length, 8, reason: 'no repeats inside a refill');
        if (last >= 0) expect(picks.first, isNot(last));
        last = picks.last;
      }
    });

    test('spontaneous lines respect global and category cooldowns', () {
      DateTime now = DateTime(2026, 11, 17, 12);
      final OraclePersona p = _p(clock: () => now, cfg: <String, dynamic>{
        'freq': <String, dynamic>{'spontaneous_chance': 1.0, 'spontaneous_global_gap_sec': 40, 'spontaneous_category_gap_sec': 150},
      });
      expect(p.spontaneous('idle'), isNotNull);
      expect(p.spontaneous('funny'), isNull, reason: 'global gap');
      now = now.add(const Duration(seconds: 41));
      expect(p.spontaneous('idle'), isNull, reason: 'category gap');
      expect(p.spontaneous('funny'), isNotNull);
      now = now.add(const Duration(seconds: 160));
      expect(p.spontaneous('idle'), isNotNull);
    });

    test('disabled categories stay silent', () {
      final OraclePersona p = _p(cfg: <String, dynamic>{
        'enabled': <String, dynamic>{'spontaneous': false, 'results': false},
      });
      expect(p.spontaneous('idle', force: true), isNull);
      expect(p.resultReaction(outcome: 'win', force: true), isNull);
    });
  });

  group('event reactions', () {
    final Map<String, dynamic> spec = kOraclePersonaDefaults['results'] as Map<String, dynamic>;
    List<String> pool(String k) => (spec[k] as List<dynamic>).cast<String>();

    test('win / loss / draw pick from the right pool', () {
      final OraclePersona p = _p();
      final String w = p.resultReaction(outcome: 'win', myScore: 2, oppScore: 1, force: true)!;
      expect(pool('win'), contains(w));
      final String l = p.resultReaction(outcome: 'loss', myScore: 1, oppScore: 2, force: true)!;
      expect(pool('lose').map((String s) => s.replaceAll('{jan}', '')).any((String s) => l.endsWith(s.trim())), isTrue);
      final String d = p.resultReaction(outcome: 'draw', force: true)!;
      expect(pool('draw'), contains(d));
    });

    test('exceptional win and heavy loss use the special pools', () {
      final OraclePersona p = _p();
      final String g = p.resultReaction(outcome: 'win', myScore: 5, oppScore: 0, force: true)!;
      expect(g, contains('5-0'));
      final String b = p.resultReaction(outcome: 'loss', myScore: 0, oppScore: 4, force: true)!;
      final List<String> both = <String>[...pool('bad'), ...pool('lose')];
      expect(both.map((String s) => s.replaceAll('{jan}', '').trim()).any((String s) => b.endsWith(s)), isTrue);
    });

    test('session context counts real results only', () {
      final OraclePersona p = _p();
      p.resultReaction(outcome: 'win', force: true);
      p.resultReaction(outcome: 'loss', force: true);
      expect(p.sessionMatches, 2);
      expect(p.lastOutcome, 'loss');
    });
  });

  group('login greetings', () {
    test('never claims Original logged in for another player', () {
      for (int seed = 0; seed < 40; seed++) {
        final OraclePersona p = _p(seed: seed, cfg: <String, dynamic>{
          'freq': <String, dynamic>{'login_greeting_chance': 1.0, 'login_original_joke_chance': 1.0},
        });
        final List<String> g = p.loginGreeting('Babak');
        expect(g.length, greaterThanOrEqualTo(3));
        // last line admits the mix-up
        expect(g[2], isNot(contains('خودتی')));
      }
    });

    test('the real Original gets the self variant', () {
      final OraclePersona p = _p(cfg: <String, dynamic>{
        'freq': <String, dynamic>{'login_greeting_chance': 1.0},
      });
      final List<String> g = p.loginGreeting('اورجینال');
      expect(g.join('\n'), anyOf(contains('واقعاً خودتی'), contains('آره خودشه')));
    });

    test('sometimes silent', () {
      final OraclePersona p = _p(cfg: <String, dynamic>{
        'freq': <String, dynamic>{'login_greeting_chance': 0.0},
      });
      expect(p.loginGreeting('Babak'), isEmpty);
    });
  });

  group('tutorials', () {
    test('finger soccer tutorials explain real controls and stop for experienced players', () {
      final OraclePersona p = _p();
      final List<OracleTutorial> all = p.tutorials('finger_soccer');
      expect(all.map((OracleTutorial t) => t.id), containsAll(<String>['ice', 'power', 'fast']));
      expect(all.firstWhere((OracleTutorial t) => t.id == 'ice').line, startsWith('ضربات یخی فرم بزن!'));
      expect(all.firstWhere((OracleTutorial t) => t.id == 'power').how, contains('بکش'));
      final Map<String, int> views = <String, int>{};
      for (int i = 0; i < all.length * 2; i++) {
        final OracleTutorial t = p.nextTutorial('finger_soccer', views)!;
        views[t.key] = (views[t.key] ?? 0) + 1;
      }
      expect(p.nextTutorial('finger_soccer', views), isNull);
      expect(p.nextTutorial('finger_soccer', views, force: true), isNotNull);
    });
  });

  group('guided tour', () {
    test('routes map to sections', () {
      expect(OraclePersonaTour.sectionForPath('/hub'), 'home');
      expect(OraclePersonaTour.sectionForPath('/rooms'), 'rooms');
      expect(OraclePersonaTour.sectionForPath('/arcade/ludo'), 'game_setup.ludo');
      expect(OraclePersonaTour.sectionForPath('/world/nexora_exchange'), 'shop');
      expect(OraclePersonaTour.sectionForPath('/world/orbit_network'), 'chat');
      expect(OraclePersonaTour.sectionForPath('/world/personal_orbit'), 'profile');
      expect(OraclePersonaTour.sectionForPath('/tournaments'), 'tournaments');
      expect(OraclePersonaTour.sectionForPath('/tournaments/abc'), isNull);
      expect(OraclePersonaTour.sectionForPath('/admin/oracle'), 'admin');
    });

    test('every section has steps and the signature is stretched', () {
      final OraclePersona p = _p();
      for (final String s in <String>['home', 'dock', 'rooms', 'games', 'game_setup.carrom', 'tournaments', 'shop', 'social',
        'chat', 'profile', 'settings', 'oracle', 'admin']) {
        final List<OracleTourStep> steps = p.tourSteps(s);
        expect(steps, isNotEmpty, reason: s);
        for (final OracleTourStep st in steps) {
          expect(st.text.contains('{jan}'), isFalse);
          expect(st.text.contains(RegExp(r'(^|\s)جان[!؟?\s]')), isFalse);
        }
      }
      expect(p.tourSteps('home').first.text, matches(janRe));
    });
  });

  group('brain integration', () {
    final OfflineOracleEngine e = OfflineOracleEngine();
    const OracleContext ctx = OracleContext(username: 'Babak');

    test('player question answered by persona', () {
      final OracleReply r = e.answer('مهیار رو می‌شناسی؟', ctx);
      expect(r.intent, 'persona.player');
      expect(r.textFa, contains('گنگ‌من'));
    });

    test('bare call gets the stretched wait', () {
      expect(e.answer('اوراکل', ctx).textFa, matches(RegExp(r'^جا{8,13}ن؟$')));
    });

    test('game request keeps its action and adds the catchphrase', () {
      final OracleReply r = e.answer('می‌خوام گل‌کوچیک بازی کنم', ctx);
      expect(r.textFa, matches(RegExp(r'^جا{8,13}ن گل‌کوچیکو بگیر!')));
    });

    test('AI context carries only verified lines of matched players', () {
      final Map<String, dynamic> c = OraclePersona.instance.aiContext('نظرت درباره صابر چیه');
      final List<dynamic> ps = c['players'] as List<dynamic>;
      expect(ps.single['id'], 'saber');
      expect((ps.single['lines'] as List<dynamic>).first, contains('صورتی'));
    });
  });
}
