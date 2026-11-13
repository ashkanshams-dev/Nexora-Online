// Leaderboard + league ladder (src/online/Ranks.tsx) and the Arena ladder (src/online/Arena.tsx).
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../nav.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../oracle/oracle_bus.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'challenges.dart' show Toast;
import 'matchmaker.dart';
import 'ui.dart';

class Ranks extends StatefulWidget {
  final VoidCallback onBack;
  final Toast toast;
  final String tab;
  const Ranks({super.key, required this.onBack, required this.toast, this.tab = 'top'});
  @override
  State<Ranks> createState() => _RanksState();
}

class _RanksState extends State<Ranks> {
  late String tab = widget.tab;
  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    return Stack(children: [
      Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S.l, ins.top + 76, S.l, S.s),
          child: Tabs2(items: const [('top', 'برترین‌ها'), ('leagues', 'لیگ‌ها')], value: tab, onChange: (v) => setState(() => tab = v)),
        ),
        Expanded(child: AnimatedSwitcher(duration: 220.ms, child: tab == 'top' ? const _Leaderboard(key: ValueKey('top')) : _Leagues(key: const ValueKey('lg'), toast: widget.toast))),
      ]),
      Header(title: tab == 'top' ? 'رده‌بندی' : 'لیگ‌ها و فصل', en: tab == 'top' ? 'LEADERBOARD' : 'LEAGUES · SEASON', accent: C.gold, onBack: widget.onBack),
    ]);
  }
}

class _Leaderboard extends StatefulWidget {
  const _Leaderboard({super.key});
  @override
  State<_Leaderboard> createState() => _LeaderboardState();
}

class _LeaderboardState extends State<_Leaderboard> {
  List<JRow>? rows;
  JRow? me;
  String? err;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final uid = Auth.I.uid;
      final res = await Future.wait<dynamic>([
        supabase.from('leaderboard').select().order('rank').limit(100),
        uid != null ? supabase.from('leaderboard').select().eq('id', uid).maybeSingle() : Future.value(null),
      ]);
      if (!mounted) return;
      setState(() {
        err = null;
        rows = List<JRow>.from(res[0] as List);
        me = res[1] as JRow?;
      });
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context), uid = Auth.I.uid, nav = NavScope.of(context);
    final inTop = me != null && (rows ?? []).any((r) => r['id'] == me!['id']);
    if (err != null && rows == null) return ErrorState(msg: err!, onRetry: load);
    if (rows == null) return const Padding(padding: EdgeInsets.symmetric(horizontal: S.l), child: Skeleton(rows: 8, h: 60));
    if (rows!.isEmpty) return const Empty(title: 'هنوز کسی در رده‌بندی نیست');
    return RefreshIndicator(
      onRefresh: load,
      color: C.cyan,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(S.l, 0, S.l, ins.bottom + S.xl),
        itemCount: rows!.length + (me != null && !inTop ? 1 : 0),
        itemExtent: 64,
        itemBuilder: (_, i) {
          if (me != null && !inTop) {
            if (i == 0) return LbItem(r: me!, mine: true, onPress: () {});
            i--;
          }
          final r = rows![i];
          return LbItem(r: r, mine: r['id'] == uid, onPress: () => nav.openProfile(rs(r, 'id')));
        },
      ),
    );
  }
}

class LbItem extends StatelessWidget {
  final JRow r;
  final bool mine;
  final VoidCallback onPress;
  final int? metric;
  final String? metricLabel;
  const LbItem({super.key, required this.r, required this.mine, required this.onPress, this.metric, this.metricLabel});
  @override
  Widget build(BuildContext context) {
    final rank = ri(r, 'rank');
    final medal = rank >= 1 && rank <= 3 ? [C.gold, hex('#d6e2f0'), hex('#e0954a')][rank - 1] : null;
    return Press(
      onPress: onPress,
      scaleTo: .98,
      child: Container(
        height: 58, margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: S.s),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: mine ? C.cyan : C.line), color: mine ? rgba(79, 227, 255, .12) : rgba(10, 16, 44, .85)),
        child: rrow([
          Container(
            width: 34, height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: medal ?? C.line), color: medal?.withValues(alpha: .2)),
            child: T(fa(rank), style: fs(F.title, 13, color: medal ?? C.dim)),
          ),
          const SizedBox(width: S.s),
          AvatarO(avatar: r['avatar'] as String?, url: r['avatar_url'] as String?, size: 40, ring: medal ?? C.line),
          const SizedBox(width: S.s),
          Expanded(child: rcol([T('${rs(r, 'username')}${mine ? ' (تو)' : ''}', n: 1, style: fs(F.bold, TS.body)), T('سطح ${fa(ri(r, 'level', 1))} · ${fa(ri(r, 'wins'))} برد', style: fs(F.body, TS.tiny, color: C.dim))])),
          Img(leagueImg(r['league'] as String?), w: 30, h: 30),
          SizedBox(width: 56, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [T(fa(metric ?? ri(r, 'rating')), style: fs(F.title, 14, color: C.gold)), T(metricLabel ?? 'امتیاز', style: fs(F.body, 9, color: C.dim))])),
        ]),
      ),
    );
  }
}

class _Leagues extends StatefulWidget {
  final Toast toast;
  const _Leagues({super.key, required this.toast});
  @override
  State<_Leagues> createState() => _LeaguesState();
}

class _LeaguesState extends State<_Leagues> with Ticking {
  JRow? season;
  Map<String, int> rewards = {};
  bool busy = false;
  @override
  void initState() {
    super.initState();
    rpc('current_season').then((s) {
      if (mounted && s is Map) setState(() => season = Map<String, dynamic>.from(s));
    }, onError: (_) {});
    supabase.from('season_rewards').select().then((d) {
      if (mounted) setState(() => rewards = {for (final r in d) '${r['league']}': ri(r, 'gems')});
    }, onError: (_) {});
    startTicking(const Duration(seconds: 30));
  }

  Future<void> claim() async {
    setState(() => busy = true);
    try {
      final r = await rpc('claim_season_reward');
      sfx(Sfx.win);
      buzz(Buzz.success);
      widget.toast('+${fa(ri(r as Map<String, dynamic>, 'gems'))} الماس جایزه‌ی فصل', 'ok');
    } catch (e) {
      widget.toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context), now = DateTime.now().millisecondsSinceEpoch;
    final ends = season != null ? DateTime.tryParse(rs(season, 'ends_at'))?.millisecondsSinceEpoch ?? now : now;
    final left = math.max(0, ends - now), d = left ~/ 86400000, h = (left % 86400000) ~/ 3600000;
    return LeaguesBuilder(builder: (_, leagues) {
      final p = Auth.I.profile, rating = ri(p, 'rating');
      final list = [...?leagues]..sort((a, b) => ri(a, 'sort').compareTo(ri(b, 'sort')));
      final cur = list.where((l) => ri(l, 'min_rating') <= rating).lastOrNull, nxt = list.where((l) => ri(l, 'min_rating') > rating).firstOrNull;
      return ListView(padding: EdgeInsets.fromLTRB(S.l, 0, S.l, ins.bottom + S.xl), children: [
        Panel(
          accent: C.violet,
          glow: true,
          pad: const EdgeInsets.all(S.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            rrow([
              Img(UI2['c_calendar'], w: 48, h: 48),
              const SizedBox(width: S.m),
              Expanded(child: rcol([T(season?['name'] as String? ?? 'فصل جاری', style: fs(F.title, TS.h)), T(season != null ? '${fa(d)} روز و ${fa(h)} ساعت تا پایان فصل' : '…', style: fs(F.body, TS.cap, color: C.dim))])),
            ]),
            const SizedBox(height: S.s),
            T('در پایان هر فصل بر اساس لیگت الماس می‌گیری. جایزه‌ی فصل قبل را این‌جا دریافت کن.', align: TextAlign.right, style: fs(F.body, TS.cap, color: C.dim)),
            const SizedBox(height: S.s),
            Btn(label: busy ? '…' : 'دریافت جایزه‌ی فصل قبل', small: true, colors: G.violet, disabled: busy, onPress: claim),
          ]),
        ),
        if (p != null && cur != null)
          Padding(
            padding: const EdgeInsets.only(top: S.m),
            child: Panel(
              accent: colorOf(cur['color']),
              pad: const EdgeInsets.all(S.m),
              child: rrow([
                Img(leagueImg(cur['id'] as String?), w: 56, h: 56),
                const SizedBox(width: S.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    T('لیگ ${rs(cur, 'name_fa')}', style: fs(F.title, TS.h, color: colorOf(cur['color']))),
                    const SizedBox(height: S.s),
                    Bar(v: nxt != null ? (rating - ri(cur, 'min_rating')) / math.max(1, ri(nxt, 'min_rating') - ri(cur, 'min_rating')) : 1, color: colorOf(cur['color']), color2: C.indigo),
                    const SizedBox(height: S.xs),
                    T(nxt != null ? '${fa(rating)} / ${fa(ri(nxt, 'min_rating'))} تا لیگ ${rs(nxt, 'name_fa')}' : '${fa(rating)} · بالاترین لیگ!', style: fs(F.body, TS.cap, color: C.dim)),
                  ]),
                ),
              ]),
            ),
          ),
        Padding(padding: const EdgeInsets.only(top: S.l, bottom: S.s), child: T('نردبان لیگ‌ها', align: TextAlign.right, style: fs(F.bold, TS.h))),
        if (leagues == null)
          const Skeleton(rows: 7, h: 64)
        else
          for (final (i, l) in list.reversed.indexed)
            () {
              final on = cur?['id'] == l['id'], reached = rating >= ri(l, 'min_rating'), c = colorOf(l['color']);
              return Container(
                height: 68, margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: S.s),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: on ? c : C.line), color: on ? c.withValues(alpha: .12) : rgba(10, 16, 44, .85)),
                child: rrow([
                  Opacity(opacity: reached ? 1 : .4, child: Img(leagueImg(l['id'] as String?), w: 44, h: 44)),
                  const SizedBox(width: S.s),
                  Expanded(child: rcol([T(rs(l, 'name_fa'), style: fs(F.bold, TS.body, color: reached ? c : C.dim)), T('از ${fa(ri(l, 'min_rating'))} امتیاز', style: fs(F.body, TS.tiny, color: C.dim))])),
                  if (on) Badge2(label: 'لیگ تو', color: c),
                  SizedBox(width: 64, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [T('💎 ${fa(rewards[l['id']] ?? 0)}', style: fs(F.bold, TS.small, color: hex('#9fd8ff'))), T('جایزه‌ی فصل', style: fs(F.body, 9, color: C.dim))])),
                ]),
              ).animate(delay: (i * 40).ms).fadeIn(duration: 250.ms).slideX(begin: .08);
            }(),
      ]);
    });
  }
}

// ============================ Arena ============================
class Arena extends StatefulWidget {
  final VoidCallback onBack;
  final void Function(JRow room) onRoom;
  final Toast toast;
  const Arena({super.key, required this.onBack, required this.onRoom, required this.toast});
  @override
  State<Arena> createState() => _ArenaState();
}

class _ArenaState extends State<Arena> {
  List<JRow>? rows;
  String? err;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await supabase
          .from('profiles')
          .select('id, username, avatar, avatar_url, level, xp, rating, league, wins, losses, draws, trophies, arena_points')
          .gt('arena_points', 0)
          .order('arena_points', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        err = null;
        rows = [for (final (i, r) in d.indexed) {...r, 'rank': i + 1}];
      });
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  void find(String m) {
    OracleBus.I.react(OracleEvent.search);
    buzz(Buzz.medium);
    Matchmaker.I.start(m, kind: 'arena');
  }

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context), nav = NavScope.of(context);
    return Stack(children: [
      RefreshIndicator(
        onRefresh: load,
        color: C.cyan,
        edgeOffset: ins.top + 70,
        child: ListView(padding: EdgeInsets.fromLTRB(S.l, ins.top + 76, S.l, ins.bottom + S.xl), children: [
          ListenableBuilder(
            listenable: Auth.I,
            builder: (_, _) {
              final p = Auth.I.profile;
              return Panel(
                accent: C.violet,
                glow: true,
                pad: const EdgeInsets.all(S.l),
                child: Stack(children: [
                  Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [rgba(163, 91, 255, .25), Colors.transparent])))),
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    rrow([
                      Img(UI2['x_crown'], w: 64, h: 64),
                      const SizedBox(width: S.m),
                      Expanded(child: rcol([T('امتیاز آرنا', style: fs(F.body, TS.small, color: C.dim)), T(fa(ri(p, 'arena_points')), style: fs(F.title, 32, color: hex('#e2c8ff')))])),
                      Column(children: [
                        T('🔥 ${fa(ri(p, 'win_streak'))}', style: fs(F.title, 18, color: C.orange)),
                        T('برد پیاپی', style: fs(F.body, TS.tiny, color: C.dim)),
                        T('بهترین ${fa(ri(p, 'best_streak'))}', style: fs(F.body, TS.tiny, color: C.dim2)),
                      ]),
                    ]),
                    const SizedBox(height: S.s),
                    T('برد: ۳۰+ و ۵+ برای هر برد پیاپی · باخت: ۲۰−', align: TextAlign.right, style: fs(F.body, TS.cap, color: C.dim)),
                    const SizedBox(height: S.m),
                    rrow([
                      for (final (i, m) in ['1v1', '2v2', '3v3'].indexed)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i < 2 ? S.s : 0),
                            child: Btn(label: m.toUpperCase(), sub: 'یافتن حریف', small: true, colors: i == 0 ? G.violet : i == 1 ? G.primary : G.gold, onPress: () => find(m)),
                          ),
                        ),
                    ]),
                  ]),
                ]),
              );
            },
          ),
          Padding(padding: const EdgeInsets.only(top: S.l, bottom: S.s), child: T('نردبان آرنا', align: TextAlign.right, style: fs(F.bold, TS.h))),
          if (err != null && rows == null)
            ErrorState(msg: err!, onRetry: load)
          else if (rows == null)
            const Skeleton(rows: 6, h: 58)
          else if (rows!.isEmpty)
            Empty(img: UI2['x_crown'], title: 'هنوز کسی امتیاز آرنا ندارد', sub: 'اولین برد آرنا مال تو باشد!')
          else
            for (final (i, r) in rows!.indexed)
              Enter(i: i, child: LbItem(r: r, mine: r['id'] == Auth.I.uid, metric: ri(r, 'arena_points'), metricLabel: 'آرنا', onPress: () => nav.openProfile(rs(r, 'id')))),
        ]),
      ),
      Header(title: 'آرنا', en: 'ARENA LADDER', accent: C.violet, onBack: widget.onBack),
    ]);
  }
}
