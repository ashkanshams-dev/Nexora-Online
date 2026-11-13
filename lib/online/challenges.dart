// Daily challenges (4 per Tehran day) — port of src/online/Challenges.tsx.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../game/assets.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'ui.dart';

typedef Toast = void Function(String m, [String k]);

class Challenge {
  final String defId, title;
  final int progress, target, gems, xp;
  bool claimed;
  Challenge(this.defId, this.title, this.progress, this.target, this.gems, this.xp, this.claimed);
}

Map<String, JRow>? _defs;

/// next midnight in Asia/Tehran (UTC+03:30, no DST)
int msToTehranMidnight([int? nowMs]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  const off = 12600000, day = 86400000;
  return ((now + off + 1) / day).ceil() * day - off - now;
}

Future<List<Challenge>> loadChallenges() async {
  final rows = await rpc<List<dynamic>>('get_daily_challenges');
  if (_defs == null) {
    final d = await supabase.from('challenge_defs').select();
    _defs = {for (final x in d) x['id'] as String: x};
  }
  return [
    for (final r in rows)
      () {
        final d = _defs![r['def_id']];
        return Challenge(r['def_id'] as String, (d?['title_fa'] ?? r['def_id']) as String, ri(r, 'progress'), d == null ? 1 : ri(d, 'target', 1), ri(d, 'reward_gems'), ri(d, 'reward_xp'), r['claimed'] == true);
      }(),
  ];
}

/// live list for the signed-in user (reloads on user_challenges changes)
class ChallengeFeed extends ChangeNotifier {
  List<Challenge>? list;
  String? err;
  RealtimeChannel? _ch;
  String? _uid;
  ChallengeFeed() {
    Auth.I.addListener(_auth);
    _auth();
  }
  void _auth() {
    final uid = Auth.I.uid;
    if (uid == _uid) return;
    _uid = uid;
    if (_ch != null) supabase.removeChannel(_ch!);
    _ch = null;
    if (uid == null) return;
    load();
    _ch = supabase
        .channel('uc:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'user_challenges',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (_) => load(),
        )
        .subscribe();
  }

  Future<void> load() async {
    if (_uid == null) return;
    try {
      list = await loadChallenges();
      err = null;
    } catch (e) {
      err = errFa(e);
    }
    notifyListeners();
  }

  Future<void> claim(Challenge c, Toast toast) async {
    try {
      final r = await rpc<Map<String, dynamic>>('claim_challenge', {'p_def': c.defId});
      sfx(Sfx.win);
      buzz(Buzz.success);
      toast('+${fa(ri(r, 'gems'))} الماس · +${fa(ri(r, 'xp'))} XP', 'ok');
      c.claimed = true;
      notifyListeners();
    } catch (e) {
      toast(errFa(e), 'err');
    }
  }

  @override
  void dispose() {
    Auth.I.removeListener(_auth);
    if (_ch != null) supabase.removeChannel(_ch!);
    super.dispose();
  }
}

class ChallengeCard extends StatelessWidget {
  final Challenge c;
  final VoidCallback onClaim;
  final bool compact;
  const ChallengeCard({super.key, required this.c, required this.onClaim, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final done = c.progress >= c.target;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.s),
      child: Opacity(
        opacity: c.claimed ? .6 : 1,
        child: Panel(
          accent: done && !c.claimed ? C.green : null,
          noAccent: !(done && !c.claimed),
          glow: done && !c.claimed,
          pad: EdgeInsets.all(compact ? S.s : S.m),
          child: Row(textDirection: TextDirection.rtl, children: [
            Img(c.claimed ? UI2['x_medal'] : done ? UI2['x_star'] : UI2['x_ball'], w: compact ? 36 : 44, h: compact ? 36 : 44),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.s),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  T(c.title, n: 2, align: TextAlign.right, style: fs(F.bold, compact ? TS.small : TS.body)),
                  Padding(padding: const EdgeInsets.only(top: S.xs), child: Bar(v: math.min(1, c.progress / math.max(1, c.target)), h: 6, color: done ? C.green : C.cyan)),
                  T('${fa(math.min(c.progress, c.target))}/${fa(c.target)} · 💎${fa(c.gems)} · ${fa(c.xp)}XP', style: fs(F.body, TS.tiny, color: C.dim)),
                ]),
              ),
            ),
            SizedBox(
              width: 76,
              child: c.claimed
                  ? T('✓ گرفتی', align: TextAlign.center, style: fs(F.body, TS.cap, color: C.green))
                  : done
                      ? Btn(small: true, label: 'دریافت', colors: G.green, onPress: onClaim)
                      : T('در جریان', align: TextAlign.center, style: fs(F.body, TS.cap, color: C.dim)),
            ),
          ]),
        ),
      ),
    );
  }
}

class HomeChallenges extends StatefulWidget {
  final Toast toast;
  final VoidCallback onAll;
  const HomeChallenges({super.key, required this.toast, required this.onAll});
  @override
  State<HomeChallenges> createState() => _HomeChallengesState();
}

class _HomeChallengesState extends State<HomeChallenges> {
  final feed = ChallengeFeed();
  @override
  void dispose() {
    feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: feed,
        builder: (context, _) {
          final list = feed.list;
          if (Auth.I.uid == null || list == null || list.isEmpty) return const SizedBox.shrink();
          final done = list.where((c) => c.claimed).length;
          return Panel(
            accent: C.green,
            pad: const EdgeInsets.all(S.m),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.only(bottom: S.s),
                child: Row(textDirection: TextDirection.rtl, children: [
                  Img(UI2['c_calendar'], w: 34, h: 34),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: S.s),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        T('چالش‌های امروز', style: fs(F.bold, TS.body)),
                        T('${fa(done)}/${fa(list.length)} انجام شد · تازه‌سازی ${fa(msToTehranMidnight() ~/ 3600000)} ساعت دیگر', style: fs(F.body, TS.tiny, color: C.dim)),
                      ]),
                    ),
                  ),
                  SizedBox(width: 72, child: Btn(label: 'همه', small: true, colors: G.dark, onPress: widget.onAll)),
                ]),
              ),
              for (final c in list.take(4)) ChallengeCard(c: c, compact: true, onClaim: () => feed.claim(c, widget.toast)),
            ]),
          );
        },
      );
}

class ChallengesScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Toast toast;
  const ChallengesScreen({super.key, required this.onBack, required this.toast});
  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  final feed = ChallengeFeed();
  late final Timer _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  @override
  void initState() {
    super.initState();
    _t;
  }

  @override
  void dispose() {
    _t.cancel();
    feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    final left = msToTehranMidnight();
    final h = left ~/ 3600000, m = (left % 3600000) ~/ 60000, s = (left % 60000) ~/ 1000;
    return Stack(children: [
      RefreshIndicator(
        onRefresh: feed.load,
        edgeOffset: ins.top + 70,
        color: C.cyan,
        child: ListenableBuilder(
          listenable: feed,
          builder: (context, _) => ListView(padding: EdgeInsets.fromLTRB(S.l, ins.top + 76, S.l, ins.bottom + S.xl), children: [
            Panel(
              accent: C.green,
              pad: const EdgeInsets.all(S.m),
              child: Row(textDirection: TextDirection.rtl, children: [
                Img(UI2['c_calendar'], w: 48, h: 48),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: S.m),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      T('چالش‌های امروز', style: fs(F.title, TS.h)),
                      T('تازه‌سازی تا ${fa(h)}:${faNum(m.toString().padLeft(2, '0'))}:${faNum(s.toString().padLeft(2, '0'))}', style: fs(F.body, TS.cap, color: C.dim)),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: S.m),
            if (feed.err != null)
              ErrorState(msg: feed.err!, onRetry: feed.load)
            else if (feed.list == null)
              const Skeleton(rows: 4, h: 96)
            else if (feed.list!.isEmpty)
              const Empty(title: 'امروز چالشی نیست')
            else
              for (final (i, c) in feed.list!.indexed) Enter(i: i, child: ChallengeCard(c: c, onClaim: () => feed.claim(c, widget.toast))),
          ]),
        ),
      ),
      Header(title: 'چالش‌های روزانه', en: 'DAILY CHALLENGES', accent: C.green, onBack: widget.onBack),
    ]).animate().fadeIn(duration: 200.ms);
  }
}
