// App shell — port of App.tsx: tabs / match / result / online routes, overlays, sheets, modals, veil transitions,
// daily reward + chests, post-match rewards, intro + welcome + password recovery.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import 'game/assets.dart';
import 'game/data.dart';
import 'game/meta.dart';
import 'nav.dart';
import 'net/auth.dart';
import 'net/supabase.dart';
import 'online/challenges.dart';
import 'online/online_root.dart';
import 'online/ui.dart';
import 'screens/account.dart';
import 'screens/home.dart';
import 'screens/intro.dart';
import 'screens/match.dart';
import 'screens/play.dart';
import 'screens/profile.dart';
import 'screens/result.dart';
import 'screens/settings.dart';
import 'screens/setup.dart';
import 'screens/shop.dart';
import 'screens/team.dart';
import 'screens/welcome.dart';
import 'social/social.dart';
import 'sound.dart';
import 'store.dart';
import 'ui/chrome.dart';
import 'ui/kit.dart';
import 'ui/space.dart';
import 'ui/theme.dart';

enum Route { tabs, match, result, online }

const _DAY = 86400000;
const _MULT = {ModeKey.quick: 1.0, ModeKey.cup: 2.0, ModeKey.galaxy: 3.0, ModeKey.train: .3, ModeKey.local: 0.0};

class NexoraApp extends StatefulWidget {
  const NexoraApp({super.key});
  @override
  State<NexoraApp> createState() => _NexoraAppState();
}

class _NexoraAppState extends State<NexoraApp> {
  int _gen = 0; // bumps on theme/lang change → rebuilds the whole tree (RN reloaded the bundle)
  @override
  Widget build(BuildContext context) => MaterialApp(
        key: ValueKey(_gen),
        title: 'NEXORA',
        debugShowCheckedModeBanner: false,
        theme: nexoraTheme(),
        home: Shell(onUiChanged: () => setState(() => _gen++)),
      );
}

class Shell extends StatefulWidget {
  final VoidCallback onUiChanged;
  const Shell({super.key, required this.onUiChanged});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Route route = Route.tabs;
  Tab tab = Tab.home;
  bool intro = true;
  Launch? launch;
  int matchKey = 0;
  ({MatchResult r, Reward? reward, CupState? cup, int? levelUp})? result;
  OnlineEntry onlineEntry = OnlineEntry.hub;
  String? onlineQuick;
  final List<(String, String)> overlays = []; // (kind, id)
  double veil = 0;

  void toast(String m, [String k = 'info']) => showToast(context, m, k);

  @override
  void initState() {
    super.initState();
    Auth.I.toast = toast;
    Store.I.addListener(_audio);
    Auth.I.addListener(_authChanged);
    _audio();
  }

  @override
  void dispose() {
    Store.I.removeListener(_audio);
    Auth.I.removeListener(_authChanged);
    super.dispose();
  }

  bool _recoveryShown = false;
  void _authChanged() {
    if (Auth.I.recovery && !_recoveryShown) {
      _recoveryShown = true;
      showNxModal(context, accent: C.cyan, builder: (_) => RecoveryCard(toast: toast)).then((_) => _recoveryShown = false);
    }
    setState(() {});
  }

  void _audio() {
    final p = Store.I.p;
    setAudioPrefs(sound: p.sound, music: p.music, haptics: p.haptics, volume: p.volume);
  }

  /// cross-fade through a dark veil (170 ms in, swap, 340 ms out)
  void transition(VoidCallback fn) {
    setState(() => veil = 1);
    Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        fn();
        veil = 0;
      });
      if (route != Route.online) setAudioScene(route == Route.match ? AudioScene.match : AudioScene.menu);
    });
  }

  void goHome() => transition(() {
        route = Route.tabs;
        tab = Tab.home;
      });

  void startMatch(Launch l) {
    launch = l;
    matchKey++;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.popUntil((r) => r.isFirst);
    transition(() => route = Route.match);
  }

  void onFinish(MatchResult r) {
    final l = launch!, p = Store.I.p;
    Reward? reward;
    CupState? cup;
    int? levelUp;
    final a = r.score[0], b = r.score[1], win = a > b, draw = a == b;
    if (r.ai) {
      final mult = const [1, 1.5, 2.2][r.aiLvl] * (_MULT[l.mode] ?? 1);
      if (l.mode == ModeKey.cup) cup = CupState(l.stage, win, win && l.stage >= 2);
      reward = Reward(((win ? 60 : draw ? 25 : 12) * mult + a * 5).round(), ((win ? 50 : 20) * math.max(.3, mult)).round(),
          l.mode == ModeKey.train ? 0 : win ? (20 * mult).round() : draw ? 0 : -8, 0);
      if (cup?.champion == true) reward.coins += 400;
      final before = level(p.xp).level, after = level(p.xp + reward.xp).level;
      if (after > before) levelUp = after;
      final rw = reward, lu = levelUp, cp = cup;
      Store.I.set((q) {
        final ws = win ? q.winStreak + 1 : 0;
        q.coins += rw.coins + (lu != null ? 100 : 0);
        q.gems += rw.gems;
        q.xp += rw.xp;
        q.trophies = math.max(0, q.trophies + rw.trophies);
        q.played++;
        if (win) q.wins++;
        if (!win && !draw) q.losses++;
        if (draw) q.draws++;
        q.goalsFor += a;
        q.goalsAgainst += b;
        q.winStreak = ws;
        q.bestStreak = math.max(q.bestStreak, ws);
        if (cp?.champion == true) q.cupsWon++;
      });
      if (win) buzz(Buzz.success);
      if (Auth.I.uid != null && l.mode != ModeKey.train) rpc('report_offline', {'p_won': win}).catchError((_) => null);
    }
    result = (r: r, reward: reward, cup: cup, levelUp: levelUp);
    transition(() => route = Route.result);
  }

  void nextCup() {
    final l = launch!, st = l.stage + 1;
    final pool = TEAMS.where((t) => t.cat == 'club' || t.cat == 'nat' || t.cat == 'elite').toList();
    startMatch(buildLaunch(ModeKey.cup, Store.I.p, lvl: 1, rule: 'g3', tt: Store.I.p.turnTime, opp: pool[math.Random().nextInt(pool.length)], stage: st));
  }

  bool get dailyReady => DateTime.now().millisecondsSinceEpoch - Store.I.p.lastDaily > _DAY;
  bool get chestReady => DateTime.now().millisecondsSinceEpoch - Store.I.p.lastChest > CHEST_EVERY;

  void claimDaily(BuildContext ctx) {
    if (!dailyReady) return;
    final p = Store.I.p, now = DateTime.now().millisecondsSinceEpoch;
    final streak = now - p.lastDaily < 2 * _DAY ? (p.streak % 7) + 1 : 1, rw = DAILY[streak - 1];
    Store.I.set((q) {
      q.lastDaily = now;
      q.streak = streak;
      q.coins += rw.$1;
      q.gems += rw.$2;
    });
    sfx(Sfx.goal);
    buzz(Buzz.success);
    toast('+${fa(rw.$1)} سکه${rw.$2 > 0 ? ' · +${fa(rw.$2)} الماس' : ''}', 'ok');
    Navigator.of(ctx).pop();
  }

  void openChest(bool premium) {
    final p = Store.I.p;
    if (!premium && !chestReady) return toast('صندوقچه‌ی رایگان هنوز آماده نیست', 'info');
    if (premium && p.coins < 600) return toast('۶۰۰ سکه لازمه', 'err');
    final prize = rollChest(p, premium);
    Store.I.set((q) {
      if (prize.item != null) grant(prize.item!, q);
      q.coins += prize.coins - (premium ? 600 : 0);
      if (!premium) q.lastChest = DateTime.now().millisecondsSinceEpoch;
      q.chests++;
    });
    showNxModal(context, accent: premium ? C.gold : C.cyan, builder: (c) => ChestOpen(prize: prize, premium: premium, onDone: () => Navigator.of(c).pop()));
  }

  void openMode(Mode m) => showNxSheet(context, title: m.name, en: m.en, accent: m.color(), height: .9, builder: (c) => Setup(mode: m, onStart: startMatch, onTeam: () {
        Navigator.of(c).pop();
        pushOverlay('team', '');
      }));

  void openSettings() => showNxSheet(context, title: 'تنظیمات', en: 'SYSTEMS', accent: C.sky, height: .78, builder: (c) => SettingsSheet(
        toast: toast,
        onUiChanged: widget.onUiChanged,
        replayIntro: () {
          Navigator.of(c).pop();
          setState(() => intro = true);
        },
      ));

  void openDaily() => showNxModal(context, builder: (c) => _DailyCard(ready: dailyReady, streak: Store.I.p.streak, lastDaily: Store.I.p.lastDaily, onClaim: () => claimDaily(c), onClose: () => Navigator.of(c).pop()));

  void openOnline([OnlineEntry e = OnlineEntry.hub, String? quick]) {
    onlineEntry = e;
    onlineQuick = quick;
    transition(() {
      overlays.clear();
      route = Route.online;
    });
  }

  void pushOverlay(String k, String id) => setState(() {
        overlays.removeWhere((o) => o.$1 == k && o.$2 == id);
        overlays.add((k, id));
        if (overlays.length > 6) overlays.removeAt(0);
      });
  void popOverlay() => setState(() => overlays.removeLast());

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    final top = ins.top + 62, bottom = TAB_H + math.max(10, ins.bottom) + 6;
    final hq = Store.I.p.quality == 'high';
    final nav = Nav(
      toast: toast,
      openOnline: openOnline,
      openProfile: (id) => pushOverlay('profile', id),
      openChat: (id) => pushOverlay('chat', id),
      openClub: (id) => pushOverlay('club', id),
      openTeam: () => pushOverlay('team', ''),
    );
    Widget body;
    switch (route) {
      case Route.tabs:
        body = Stack(children: [
          Positioned.fill(child: Space(theme: tab == Tab.home ? SpaceTheme.stadium : tab == Tab.play ? SpaceTheme.holo : SpaceTheme.base, dim: tab == Tab.home || tab == Tab.play ? 0 : .15, stars: hq)),
          Positioned.fill(
            child: ListenableBuilder(
              listenable: Store.I,
              builder: (_, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: KeyedSubtree(
                  key: ValueKey(tab),
                  child: switch (tab) {
                    Tab.home => Home(
                        top: top, bottom: bottom, onOnline: openOnline, onMode: openMode,
                        onTab: (t) => t == 'team' ? pushOverlay('team', '') : setState(() => tab = Tab.values.byName(t)),
                        onDaily: openDaily, onChest: () => openChest(false), dailyReady: dailyReady, chestReady: chestReady),
                    Tab.play => Play(top: top, bottom: bottom, onMode: openMode, onOnline: openOnline),
                    Tab.social => Social(top: top, bottom: bottom, toast: toast),
                    Tab.shop => Shop(top: top, bottom: bottom, toast: toast, onChest: openChest),
                    Tab.profile => ProfileScreen(top: top, bottom: bottom, toast: toast),
                  },
                ),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, top: 0, child: Hud(onProfile: () => setState(() => tab = Tab.profile), onSettings: openSettings, onDaily: openDaily, dailyReady: dailyReady, onShop: () => setState(() => tab = Tab.shop))),
          Positioned(left: 0, right: 0, bottom: 0, child: TabBar2(tab: tab, onTab: (t) => setState(() => tab = t), badge: {if (chestReady) Tab.shop})),
        ]);
      case Route.online:
        body = OnlineRoot(entry: onlineEntry, quick: onlineQuick, toast: toast, fx: hq, onExit: () => transition(() => route = Route.tabs));
      case Route.match:
        final l = launch!;
        body = MatchScreen(key: ValueKey(matchKey), cfg: l.cfg, teams: l.teams, names: l.names, onFinish: onFinish, onQuit: goHome, fx: hq, coach: (t, _) => toast(t, 'info'));
      case Route.result:
        final res = result!, l = launch!;
        final out = res.r.score[0] > res.r.score[1] ? SpaceTheme.win : res.r.score[0] < res.r.score[1] ? SpaceTheme.lose : SpaceTheme.system;
        body = Stack(children: [
          Positioned.fill(child: Space(theme: out, stars: hq)),
          ResultScreen(
            r: res.r, reward: res.reward, names: l.names, cup: res.cup, levelUp: res.levelUp, onHome: goHome,
            onAgain: () {
              final p = Store.I.p;
              if (res.cup != null) {
                res.cup!.won && !res.cup!.champion ? nextCup() : startMatch(buildLaunch(ModeKey.cup, p, lvl: 0, rule: 'g3', tt: p.turnTime, opp: l.teams[1]));
              } else {
                startMatch(buildLaunch(l.mode, p, lvl: l.cfg.aiLvl, rule: l.cfg.matchTime == 180 ? 't3' : l.cfg.limit == 5 ? 'g5' : 'g3', tt: l.cfg.turnTime.round(), opp: l.teams[1]));
              }
            },
          ),
        ]);
    }
    final auth = Auth.I;
    return NavScope(
      nav: nav,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (overlays.isNotEmpty) return popOverlay();
          if (route == Route.result) return goHome();
          if (route == Route.tabs && tab != Tab.home) return setState(() => tab = Tab.home);
        },
        child: Scaffold(
          backgroundColor: C.bg,
          resizeToAvoidBottomInset: false,
          body: Stack(children: [
            Positioned.fill(child: body),
            if (overlays.isNotEmpty)
              Positioned.fill(
                child: KeyedSubtree(
                  key: ValueKey(overlays.last),
                  child: Material(
                    color: C.bg,
                    child: Stack(children: [
                      Positioned.fill(child: Space(theme: SpaceTheme.base, dim: .15, stars: hq)),
                      _overlay(overlays.last, ins),
                    ]),
                  ).animate().fadeIn(duration: 200.ms),
                ),
              ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: veil,
                duration: Duration(milliseconds: veil > 0 ? 170 : 340),
                curve: veil > 0 ? Curves.easeInQuad : Curves.easeOutCubic,
                child: Container(color: hex('#02030b')),
              ),
            ),
            if (!intro && auth.ready && auth.configured && auth.uid == null) Positioned.fill(child: Welcome(toast: toast, onUiChanged: widget.onUiChanged)),
            if (intro) Positioned.fill(child: Intro(onDone: () => setState(() => intro = false))),
          ]),
        ),
      ),
    );
  }

  Widget _overlay((String, String) o, EdgeInsets ins) => switch (o.$1) {
        'profile' => PublicProfile(id: o.$2, onBack: popOverlay, toast: toast),
        'chat' => ChatScreen(id: o.$2, onBack: popOverlay, toast: toast),
        'club' => ClubPage(id: o.$2, onBack: popOverlay, toast: toast),
        'challenges' => ChallengesScreen(onBack: popOverlay, toast: toast),
        _ => Stack(children: [
            Positioned.fill(child: TeamScreen(top: ins.top + 76, bottom: ins.bottom + 8, toast: toast)),
            Header(title: 'تیم من', en: 'SQUAD · DISCS · LOADOUT', onBack: popOverlay),
          ]),
      };
}

class _DailyCard extends StatelessWidget {
  final bool ready;
  final int streak, lastDaily;
  final VoidCallback onClaim, onClose;
  const _DailyCard({required this.ready, required this.streak, required this.lastDaily, required this.onClaim, required this.onClose});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = ready ? (now - lastDaily < 2 * _DAY ? (streak % 7) + 1 : 1) : streak;
    final left = math.max(0, lastDaily + _DAY - now), h = left ~/ 3600000, m = ((left % 3600000) / 60000).ceil();
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Img(UI2['c_calendar'], w: 96, h: 96).animate().scale(begin: const Offset(.5, .5), curve: Curves.elasticOut, duration: 800.ms),
        T('جایزه‌ی روزانه', style: fs(F.title, 21)),
        T('هر روز سر بزن، جایزه‌ها بزرگ‌تر می‌شن', style: fs(F.body, 12, color: C.dim)),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.center, textDirection: TextDirection.rtl, children: [
          for (final (i, d) in DAILY.indexed)
            () {
              final day = i + 1, got = ready ? day < next : day <= next, cur = ready && day == next;
              return Container(
                width: day == 7 ? 132 : 62, margin: const EdgeInsets.all(3), padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cur ? C.gold : got ? C.green : C.line),
                  color: cur ? rgba(255, 210, 87, .16) : got ? rgba(61, 255, 168, .1) : rgba(8, 12, 34, .8),
                  boxShadow: cur ? [BoxShadow(color: C.gold.withValues(alpha: .8), blurRadius: 10)] : null,
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  Center(
                    child: Column(children: [
                      T('روز ${fa(day)}', style: fs(F.body, 10, color: cur ? C.gold : C.dim)),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Img(day == 7 ? UI2['x_chest'] : d.$2 > 0 ? UI2['x_gem'] : UI2['c_coin'], w: 34, h: 34)),
                      T(d.$2 > 0 ? '${fa(d.$1)}+${fa(d.$2)}💎' : fa(d.$1), style: fs(F.bold, 10)),
                    ]),
                  ),
                  if (got)
                    Positioned(
                      top: -4, left: 4,
                      child: Container(width: 16, height: 16, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: C.green), child: T('✓', style: fs(F.bold, 10, color: hex('#03140c')))),
                    ),
                ]),
              );
            }(),
        ]),
        const SizedBox(height: 16),
        ready ? Btn(label: 'دریافت جایزه‌ی روز ${fa(next)}', colors: G.gold, onPress: onClaim) : Btn(label: 'جایزه‌ی بعدی: ${fa(h)}س ${fa(m)}د', colors: G.dark, small: true, onPress: onClose),
      ]),
    );
  }
}
