// Public profile of any player (opened by tapping a name/avatar anywhere, see player_link.dart): avatar, level,
// league, stats, achievements, follower/following counts, Follow, Message, Block. Data comes from the player_card
// RPC; follow/block go through follow_user / unfollow_user / block_user / unblock_user (server-side, RLS + guards).
import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../net/discs.dart';
import '../net/supabase.dart';
import '../online/ui.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'player_link.dart';
import 'social.dart' show openClub, openDm;

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  const PublicProfileScreen({super.key, required this.userId});
  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Rec? p, club, lg;
  int? followers, followingN;
  bool following = false, followsMe = false, blocked = false, blockedMe = false, busy = false;
  List<Achievement> ach = const [];
  String? err;

  String get id => widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<dynamic> _maybe(Future<dynamic> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    Rec pr;
    try {
      pr = await SocialApi.card(id);
    } catch (e) {
      if (mounted) setState(() => err = '$e'.contains('player not found') ? 'بازیکن پیدا نشد' : errFa(e));
      return;
    }
    if (!mounted) return;
    setState(() {
      p = pr;
      err = null;
      followers = pr.i('followers');
      followingN = pr.i('following_n');
      following = pr.b('is_following');
      followsMe = pr.b('follows_me');
      blocked = pr.b('blocked_by_me');
      blockedMe = pr.b('blocked_me');
      ach = achievementsOf(pr['achievements']);
    });
    final clubId = pr.str('club_id');
    final res = await Future.wait([
      clubId != null && clubId.isNotEmpty ? _maybe(sb.from('clubs').select('id, name, tag, emblem').eq('id', clubId).maybeSingle()) : Future.value(null),
      leagues(),
    ]);
    if (!mounted) return;
    final ls = res[1] as List<Rec>;
    setState(() {
      club = res[0] is Map ? Rec.of(res[0]) : null;
      lg = ls.where((l) => l.s('id') == pr.s('league')).firstOrNull;
    });
  }

  Future<void> _toggleFollow() async {
    final uid = Auth.i.uid;
    if (uid == null || busy || blocked || blockedMe) return;
    setState(() => busy = true);
    final was = following;
    try {
      final r = was ? await SocialApi.unfollow(id) : await SocialApi.follow(id);
      if (!mounted) return;
      setState(() {
        following = r.b('following');
        followers = r.i('followers', followers ?? 0);
      });
      buzz('medium');
      if (!was) sfx(Snd.ready);
    } catch (e) {
      toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _toggleBlock() async {
    if (Auth.i.uid == null || busy) return;
    final was = blocked;
    if (!was && !await confirm(context, 'مسدود کردن ${p?.s('username') ?? ''}؟', 'دیگر نمی‌تواند به تو پیام بدهد یا دنبالت کند و دنبال‌کردن دوطرفه حذف می‌شود.', yes: 'مسدود کن', no: 'نه')) return;
    setState(() => busy = true);
    try {
      was ? await SocialApi.unblock(id) : await SocialApi.block(id);
      toast(was ? 'از مسدودی خارج شد' : 'کاربر مسدود شد', 'ok');
      await _load();
    } catch (e) {
      toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _back() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (err != null) {
      body = Column(children: [
        Header(title: 'پروفایل', en: 'PILOT PROFILE', onBack: _back),
        const SizedBox(height: 60),
        ErrorState(err!, onRetry: _load),
      ]);
    } else if (p == null) {
      body = Column(children: [
        Header(title: 'پروفایل', en: 'PILOT PROFILE', onBack: _back),
        const Expanded(child: Center(child: Spinner(size: 36))),
      ]);
    } else {
      body = _profile(p!);
    }
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        const Positioned.fill(child: Space(theme: SpaceTheme.base, dim: .15)),
        Positioned.fill(child: body),
      ]),
    );
  }

  Widget _profile(Rec p) {
    final uid = Auth.i.uid;
    final me = uid == id;
    final lp = levelProgress(p.i('xp'));
    final lc = lg != null ? hexColor(lg!.s('color', '#4fe3ff')) : C.cyan;
    final wins = p.i('wins'), losses = p.i('losses'), draws = p.i('draws');
    final played = wins + losses + draws, wr = played > 0 ? (wins / played * 100).round() : 0;
    final eq = p.str('equipped_disc');
    final ds = Discs.i.stats(eq);
    final on = isOnline(p.str('online_at'));
    final bio = p.s('bio');
    final stats = <(String, String, String)>[
      (ui2('x_ball'), 'بازی', fa(played)),
      (ui2('x_medal'), 'برد', fa(wins)),
      (ui2('x_shield'), 'باخت', fa(losses)),
      (ui2('x_star'), 'درصد برد', '${fa(wr)}٪'),
      (ui2('x_statue'), 'گل', fa(p.i('goals'))),
      (ui2('x_crown'), 'آرنا', fa(p.i('arena_points'))),
    ];
    Widget statCell((String, String, String) s) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(SP.xs),
            child: Panel(
              accent: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: SP.s),
              child: Column(children: [
                Img(s.$1, w: 34, h: 34),
                const SizedBox(height: 2),
                T(s.$3, size: 16, family: F.title, weight: 900),
                T(s.$2, size: 10, color: C.dim),
              ]),
            ),
          ),
        );
    Widget count(int v, String l) => Expanded(
          child: Column(children: [T(fa(v), size: 18, family: F.title, weight: 900), T(l, size: 10, color: C.dim)]),
        );
    Widget statBar(String l, double v, Color c) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(textDirection: TextDirection.rtl, children: [
            SizedBox(width: 44, child: T(l, size: 10, color: C.dim, align: TextAlign.right)),
            const SizedBox(width: 6),
            Expanded(child: Bar(v: (v / 10).clamp(0, 1).toDouble(), color: c, color2: C.violet, h: 6)),
            const SizedBox(width: 6),
            SizedBox(width: 26, child: T(fa(v.round()), size: 10, color: C.text)),
          ]),
        );

    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + SP.xl),
      children: [
        Header(title: p.s('username'), en: 'PILOT PROFILE', onBack: _back),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SP.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Panel(
              accent: lc,
              glowOn: true,
              padding: const EdgeInsets.all(SP.l),
              child: Column(children: [
                Stack(clipBehavior: Clip.none, children: [
                  Avatar(avatar: eq ?? p.str('avatar'), url: p.str('avatar_url'), size: 104, ring: lc),
                  if (on)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: C.green, border: Border.all(color: const Color(0xff0b1236), width: 3))),
                    ),
                ]),
                const SizedBox(height: SP.s),
                tTitle(p.s('username'), size: 20, align: TextAlign.center, lines: 1),
                T(on ? 'آنلاین · Online' : 'آخرین بازدید ${timeAgo(p.str('online_at'))} پیش', size: 11, color: on ? C.green : C.dim),
                if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: SP.s), child: T(bio, size: 12, color: const Color(0xffcfe0ff), align: TextAlign.center)),
                const SizedBox(height: SP.s),
                Wrap(textDirection: TextDirection.rtl, alignment: WrapAlignment.center, runSpacing: 4, children: [
                  Badge2('سطح ${fa(p.i('level', lp.level))}', color: C.gold),
                  if (lg != null) Badge2('لیگ ${lg!.s('name_fa')}', color: lc),
                  if (p.b('is_guest')) const Badge2('مهمان', color: C.dim),
                  if (club != null) Badge2('[${club!.s('tag')}] ${club!.s('name')}', color: C.orange),
                ]),
                const SizedBox(height: SP.m),
                Bar(v: lp.frac.clamp(0, 1).toDouble(), color: C.cyan, color2: C.violet, h: 8),
                const SizedBox(height: SP.xs),
                T('${fa(lp.cur)} / ${fa(lp.need)} XP تا سطح ${fa(lp.level + 1)}', size: 10, color: C.dim),
                const SizedBox(height: SP.m),
                Row(textDirection: TextDirection.rtl, children: [
                  count(followers ?? 0, 'دنبال‌کننده'),
                  count(followingN ?? 0, 'دنبال‌شده'),
                  count(p.i('trophies'), 'جام'),
                ]),
                if (!me && uid != null) ...[
                  const SizedBox(height: SP.m),
                  Row(textDirection: TextDirection.rtl, children: [
                    Expanded(
                        child: Btn(following ? 'دنبال می‌کنی ✓' : (followsMe ? 'دنبال کردن متقابل' : 'دنبال کردن'),
                            small: true, colors: following ? G.dark : G.primary, disabled: busy || blocked || blockedMe, onTap: _toggleFollow)),
                    const SizedBox(width: SP.s),
                    Expanded(child: Btn('ارسال پیام', small: true, colors: G.green, disabled: blocked || blockedMe, onTap: () => openDm(context, id))),
                  ]),
                  if (blocked || blockedMe)
                    Padding(
                      padding: const EdgeInsets.only(top: SP.xs),
                      child: T(blocked ? 'این بازیکن را مسدود کرده‌ای' : 'امکان پیام و دنبال کردن نیست', size: 10, color: C.dim, align: TextAlign.center),
                    ),
                ],
              ]),
            ),
            const SizedBox(height: SP.m),
            Row(textDirection: TextDirection.rtl, children: [for (final s in stats.take(3)) statCell(s)]),
            Row(textDirection: TextDirection.rtl, children: [for (final s in stats.skip(3)) statCell(s)]),
            const SizedBox(height: SP.s),
            Panel(
              accent: Colors.transparent,
              padding: const EdgeInsets.all(SP.m),
              child: Row(textDirection: TextDirection.rtl, children: [
                Img(discImg(eq), w: 56, h: 56),
                const SizedBox(width: SP.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const T('دیسک فعال · Active disc', size: 12, family: F.bold, weight: 800, align: TextAlign.right),
                    statBar('قدرت', ds.power, C.orange),
                    statBar('دقت', ds.accuracy, C.cyan),
                  ]),
                ),
                if (lg != null) ...[const SizedBox(width: SP.s), Img(ui(kLeagueImg[lg!.s('id')] ?? 'medal_bronze'), w: 48, h: 48)],
              ]),
            ),
            if (ach.isNotEmpty) ...[const SizedBox(height: SP.m), AchievementsPanel(items: ach)],
            if (club != null) ...[
              const SizedBox(height: SP.m),
              Btn('باشگاه ${club!.s('name')}', small: true, colors: G.gold, onTap: () => openClub(context, club!.s('id'))),
            ],
            if (!me && uid != null)
              Press(
                onTap: _toggleBlock,
                child: Container(
                  margin: const EdgeInsets.only(top: SP.m),
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  child: T(blocked ? 'رفع مسدودی' : 'مسدود کردن این بازیکن', size: 12, color: C.red, align: TextAlign.center),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

/// Achievements grid: earned ones in full colour, the rest dimmed with a progress bar.
class AchievementsPanel extends StatelessWidget {
  final List<Achievement> items;
  const AchievementsPanel({super.key, required this.items});
  @override
  Widget build(BuildContext context) {
    final done = items.where((a) => a.done).length;
    return Panel(
      accent: Colors.transparent,
      padding: const EdgeInsets.all(SP.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(textDirection: TextDirection.rtl, children: [
          const Expanded(child: T('دستاوردها', size: 13, family: F.bold, weight: 800, align: TextAlign.right)),
          T('${fa(done)} از ${fa(items.length)}', size: 11, color: C.gold),
        ]),
        const SizedBox(height: SP.s),
        LayoutBuilder(builder: (_, c) {
          final w = (c.maxWidth - SP.s * 2) / 3;
          return Wrap(
            textDirection: TextDirection.rtl,
            spacing: SP.s,
            runSpacing: SP.s,
            children: [for (final a in items) SizedBox(width: w, child: _AchTile(a))],
          );
        }),
      ]),
    );
  }
}

class _AchTile extends StatelessWidget {
  final Achievement a;
  const _AchTile(this.a);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: a.done ? C.gold.withValues(alpha: .6) : C.line),
          color: const Color(0x66080d2c),
        ),
        child: Column(children: [
          Opacity(opacity: a.done ? 1 : .32, child: Img(achIcon(a.id), w: 30, h: 30)),
          const SizedBox(height: 2),
          T(a.title, size: 11, weight: 800, color: a.done ? C.text : C.dim, align: TextAlign.center, lines: 1),
          T(a.desc, size: 9, color: C.dim, align: TextAlign.center, lines: 1),
          if (!a.done) ...[
            const SizedBox(height: 3),
            Bar(v: a.frac, color: C.cyan, color2: C.violet, h: 4),
          ],
        ]),
      );
}

/// Compact player card (modal) used where leaving the screen is unwelcome, e.g. a running match.
Future<void> showPlayerCard(BuildContext context, String uid) => showCard<void>(context, accent: C.cyan, child: (cc) => _PlayerCard(uid: uid, close: () => Navigator.of(cc).pop()));

class _PlayerCard extends StatefulWidget {
  final String uid;
  final VoidCallback close;
  const _PlayerCard({required this.uid, required this.close});
  @override
  State<_PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<_PlayerCard> {
  Rec? p;
  String? err;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await SocialApi.card(widget.uid);
      if (mounted) setState(() => p = r);
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  Future<void> _follow() async {
    final c = p;
    if (c == null || busy) return;
    setState(() => busy = true);
    try {
      final r = c.b('is_following') ? await SocialApi.unfollow(widget.uid) : await SocialApi.follow(widget.uid);
      if (mounted) setState(() => p = c.merge({'is_following': r.b('following'), 'followers': r.i('followers')}));
      buzz('medium');
    } catch (e) {
      toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = p;
    if (c == null) {
      return SizedBox(height: 180, child: Center(child: err != null ? T(err!, size: 12, color: C.red, align: TextAlign.center) : const Spinner(size: 32)));
    }
    final ach = achievementsOf(c['achievements']).where((a) => a.done).toList();
    final off = c.b('blocked_by_me') || c.b('blocked_me');
    Widget count(int v, String l) => Expanded(child: Column(children: [T(fa(v), size: 16, family: F.title, weight: 900), T(l, size: 10, color: C.dim)]));
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Avatar(avatar: c.str('equipped_disc') ?? c.str('avatar'), url: c.str('avatar_url'), size: 72, ring: C.cyan)),
        const SizedBox(height: 6),
        tTitle(c.s('username'), size: 18, align: TextAlign.center, lines: 1),
        T('سطح ${fa(c.i('level', 1))} · ${fa(c.i('wins'))} برد · ${fa(ach.length)} دستاورد', size: 11, color: C.dim, align: TextAlign.center),
        const SizedBox(height: 10),
        Row(textDirection: TextDirection.rtl, children: [count(c.i('followers'), 'دنبال‌کننده'), count(c.i('following_n'), 'دنبال‌شده')]),
        const SizedBox(height: 12),
        Row(textDirection: TextDirection.rtl, children: [
          Expanded(child: Btn(c.b('is_following') ? 'دنبال می‌کنی ✓' : 'دنبال کردن', small: true, colors: c.b('is_following') ? G.dark : G.primary, disabled: busy || off, onTap: _follow)),
          const SizedBox(width: 8),
          Expanded(
              child: Btn('ارسال پیام', small: true, colors: G.green, disabled: off, onTap: () {
            widget.close();
            startDm(widget.uid);
          })),
        ]),
        const SizedBox(height: 8),
        Btn('پروفایل کامل', small: true, colors: G.dark, onTap: () {
          widget.close();
          openPlayer(context, widget.uid);
        }),
      ]),
    );
  }
}
