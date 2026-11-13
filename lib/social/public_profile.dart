// Public profile — port of src/social/PublicProfile.tsx: avatar/photo, level, league, stats, followers, follow/unfollow,
// message, block, club; plus friend request / accept / unfriend (friends = mutual follows).
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../nav.dart';
import '../net/auth.dart';
import '../net/discs.dart';
import '../net/supabase.dart';
import '../online/challenges.dart' show Toast;
import '../online/ui.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'social_feed.dart';

/// friend relation between me and another player
enum Rel { none, following, sent, received, friends }

Future<Rel> relationTo(String id) async {
  final uid = Auth.I.uid;
  if (uid == null) return Rel.none;
  final r = await Future.wait<dynamic>([
    supabase.from('follows').select('followee').eq('follower', uid).eq('followee', id).maybeSingle(),
    supabase.from('follows').select('follower').eq('follower', id).eq('followee', uid).maybeSingle(),
    supabase.from('friend_requests').select('from_user, status').or('and(from_user.eq.$uid,to_user.eq.$id),and(from_user.eq.$id,to_user.eq.$uid)').eq('status', 'pending'),
  ]);
  final iFollow = r[0] != null, theyFollow = r[1] != null, pend = List<JRow>.from(r[2] as List);
  if (iFollow && theyFollow) return Rel.friends;
  if (pend.any((p) => p['from_user'] == id)) return Rel.received;
  if (pend.any((p) => p['from_user'] == uid)) return Rel.sent;
  return iFollow ? Rel.following : Rel.none;
}

class PublicProfile extends StatefulWidget {
  final String id;
  final VoidCallback onBack;
  final Toast toast;
  const PublicProfile({super.key, required this.id, required this.onBack, required this.toast});
  @override
  State<PublicProfile> createState() => _PublicProfileState();
}

class _PublicProfileState extends State<PublicProfile> {
  JRow? p, stats, club;
  Rel rel = Rel.none;
  bool following = false, blocked = false, busy = false;
  String? err;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await supabase.from('profiles').select().eq('id', widget.id).maybeSingle();
      if (d == null) {
        if (mounted) setState(() => err = 'بازیکن پیدا نشد');
        return;
      }
      if (mounted) {
        setState(() {
          p = d;
          err = null;
        });
      }
      final uid = Auth.I.uid;
      final r = await Future.wait<dynamic>([
        supabase.from('profile_stats').select().eq('id', widget.id).maybeSingle(),
        uid != null ? supabase.from('follows').select('followee').eq('follower', uid).eq('followee', widget.id).maybeSingle() : Future.value(null),
        uid != null ? supabase.from('user_blocks').select('blocked').eq('blocker', uid).eq('blocked', widget.id).maybeSingle() : Future.value(null),
        d['club_id'] != null ? supabase.from('clubs').select('id, name, tag, emblem').eq('id', d['club_id']).maybeSingle() : Future.value(null),
        relationTo(widget.id).catchError((_) => Rel.none),
      ]);
      if (!mounted) return;
      setState(() {
        stats = r[0] as JRow?;
        following = r[1] != null;
        blocked = r[2] != null;
        club = r[3] as JRow?;
        rel = r[4] as Rel;
      });
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  Future<void> toggleFollow() async {
    final uid = Auth.I.uid;
    if (uid == null || busy) return;
    setState(() => busy = true);
    try {
      if (following) {
        await supabase.from('follows').delete().eq('follower', uid).eq('followee', widget.id);
      } else {
        await supabase.from('follows').insert({'follower': uid, 'followee': widget.id});
        sfx(Sfx.ready);
      }
      buzz(Buzz.medium);
      setState(() {
        stats = stats == null ? null : {...stats!, 'followers': ri(stats, 'followers') + (following ? -1 : 1)};
        following = !following;
      });
      rel = await relationTo(widget.id);
    } catch (e) {
      widget.toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> friend() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      switch (rel) {
        case Rel.friends:
          await rpc('remove_friend', {'p_user': widget.id});
          widget.toast('از دوستان حذف شد', 'ok');
        case Rel.sent:
          await rpc('cancel_friend_request', {'p_user': widget.id});
        case Rel.received:
          await rpc('respond_friend_request', {'p_from': widget.id, 'p_accept': true});
          sfx(Sfx.win);
          buzz(Buzz.success);
          widget.toast('حالا با هم دوستید 🤝', 'ok');
        case Rel.none || Rel.following:
          final r = await rpc('send_friend_request', {'p_user': widget.id});
          sfx(Sfx.ready);
          buzz(Buzz.medium);
          widget.toast(r == 'friends' ? 'حالا با هم دوستید 🤝' : 'درخواست دوستی فرستاده شد', 'ok');
      }
      await load();
    } catch (e) {
      widget.toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> message() async {
    try {
      final cid = await rpc('open_dm', {'p_user': widget.id});
      if (mounted) NavScope.of(context).openChat('$cid');
    } catch (e) {
      widget.toast(errFa(e), 'err');
    }
  }

  Future<void> toggleBlock() async {
    final uid = Auth.I.uid;
    if (uid == null) return;
    try {
      if (blocked) {
        await supabase.from('user_blocks').delete().eq('blocker', uid).eq('blocked', widget.id);
      } else {
        await supabase.from('user_blocks').insert({'blocker': uid, 'blocked': widget.id});
      }
      setState(() => blocked = !blocked);
      widget.toast(blocked ? 'کاربر مسدود شد' : 'از مسدودی خارج شد', 'ok');
    } catch (e) {
      widget.toast(errFa(e), 'err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context), p = this.p;
    if (p == null) {
      return Stack(children: [
        err != null ? Padding(padding: EdgeInsets.only(top: ins.top + 90), child: ErrorState(msg: err!, onRetry: load)) : const Center(child: Spinner(size: 36)),
        Header(title: 'پروفایل', onBack: widget.onBack),
      ]);
    }
    final me = Auth.I.uid == widget.id, nav = NavScope.of(context);
    return LeaguesBuilder(builder: (_, leagues) {
      final lp = levelProgress(ri(p, 'xp')), lg = leagues?.where((l) => l['id'] == p['league']).firstOrNull, lc = colorOf(lg?['color']);
      final played = ri(p, 'wins') + ri(p, 'losses') + ri(p, 'draws'), wr = played > 0 ? (ri(p, 'wins') / played * 100).round() : 0;
      final ds = discStats(p['equipped_disc'] as String?), on = isOnline(p['online_at']);
      final (relLabel, relColors) = switch (rel) {
        Rel.friends => ('دوست هستید ✓', G.dark),
        Rel.sent => ('درخواست فرستاده شد', G.dark),
        Rel.received => ('پذیرفتن دوستی', G.green),
        _ => ('درخواست دوستی', G.violet),
      };
      return Stack(children: [
        ListView(padding: EdgeInsets.fromLTRB(S.l, ins.top + 76, S.l, ins.bottom + S.xl), children: [
          Panel(
            accent: lc,
            glow: true,
            pad: const EdgeInsets.all(S.l),
            child: Stack(children: [
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [lc.withValues(alpha: .2), Colors.transparent])))),
              Column(children: [
                Stack(children: [
                  AvatarO(avatar: (p['equipped_disc'] ?? p['avatar']) as String?, url: p['avatar_url'] as String?, size: 104, ring: lc).animate().scaleXY(begin: .7, curve: Curves.elasticOut, duration: 800.ms),
                  if (on)
                    Positioned(
                      bottom: 6, left: 6,
                      child: Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: C.green, border: Border.all(color: hex('#0b1236'), width: 3))),
                    ),
                ]),
                const SizedBox(height: S.s),
                T(rs(p, 'username'), style: fs(F.title, 20)),
                T(on ? 'آنلاین' : 'آخرین بازدید ${timeAgo(p['online_at'])} پیش', style: fs(F.body, TS.cap, color: on ? C.green : C.dim)),
                if (p['bio'] != null) Padding(padding: const EdgeInsets.only(top: S.s), child: T('${p['bio']}', align: TextAlign.center, style: fs(F.body, TS.small, color: hex('#cfe0ff')))),
                const SizedBox(height: S.s),
                Wrap(textDirection: TextDirection.rtl, alignment: WrapAlignment.center, runSpacing: 4, children: [
                  Badge2(label: 'سطح ${fa(ri(p, 'level', 1))}', color: C.gold),
                  if (lg != null) Badge2(label: 'لیگ ${rs(lg, 'name_fa')}', color: lc),
                  if (p['is_guest'] == true) Badge2(label: 'مهمان', color: C.dim),
                  if (rel == Rel.friends) Badge2(label: 'دوست', color: C.green),
                  if (club != null) Badge2(label: '[${rs(club, 'tag')}] ${rs(club, 'name')}', color: C.orange),
                ]),
                const SizedBox(height: S.m),
                Bar(v: lp.frac, color: C.cyan, color2: C.violet, h: 8),
                const SizedBox(height: S.xs),
                T('${fa(lp.cur)} / ${fa(lp.need)} XP تا سطح ${fa(lp.level + 1)}', style: fs(F.body, TS.tiny, color: C.dim)),
                const SizedBox(height: S.m),
                rrow([
                  for (final (v, l) in [(ri(stats, 'followers'), 'دنبال‌کننده'), (ri(stats, 'following'), 'دنبال‌شده'), (ri(p, 'trophies'), 'جام')])
                    Expanded(child: Column(children: [T(fa(v), style: fs(F.title, 18)), T(l, style: fs(F.body, TS.tiny, color: C.dim))])),
                ]),
                if (!me) ...[
                  const SizedBox(height: S.m),
                  rrow([
                    Expanded(child: Btn(label: following ? 'دنبال می‌کنی ✓' : 'دنبال کردن', small: true, colors: following ? G.dark : G.primary, disabled: busy, onPress: toggleFollow)),
                    const SizedBox(width: S.s),
                    Expanded(child: Btn(label: 'پیام', small: true, colors: G.green, onPress: message)),
                  ]),
                  const SizedBox(height: S.s),
                  Btn(label: busy ? '…' : relLabel, small: true, colors: relColors, disabled: busy, onPress: friend),
                ],
              ]),
            ]),
          ),
          const SizedBox(height: S.m),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: S.s,
            crossAxisSpacing: S.s,
            childAspectRatio: 1.15,
            children: [
              for (final (i, (img, k, v)) in [
                (UI2['x_ball'], 'بازی', fa(played)),
                (UI2['x_medal'], 'برد', fa(ri(p, 'wins'))),
                (UI2['x_shield'], 'باخت', fa(ri(p, 'losses'))),
                (UI2['x_star'], 'درصد برد', '${fa(wr)}٪'),
                (UI2['x_statue'], 'گل', fa(ri(p, 'goals'))),
                (UI2['x_crown'], 'آرنا', fa(ri(p, 'arena_points'))),
              ].reversed.indexed)
                Panel(
                  noAccent: true,
                  pad: const EdgeInsets.symmetric(vertical: S.s),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Img(img, w: 34, h: 34), T(v, style: fs(F.title, 16)), T(k, style: fs(F.body, TS.tiny, color: C.dim))]),
                ).animate(delay: (i * 50).ms).fadeIn(duration: 250.ms).scaleXY(begin: .85, curve: Curves.easeOutBack),
            ],
          ),
          const SizedBox(height: S.s),
          Panel(
            noAccent: true,
            pad: const EdgeInsets.all(S.m),
            child: rrow([
              Img(discImgOf(p['equipped_disc'] as String?), w: 56, h: 56),
              const SizedBox(width: S.m),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [T('دیسک فعال', style: fs(F.bold, TS.small)), StatBars(power: ds.power.round(), accuracy: ds.accuracy.round())])),
              if (lg != null) ...[const SizedBox(width: S.s), Img(leagueImg(lg['id'] as String?), w: 48, h: 48)],
            ]),
          ),
          if (club != null) ...[const SizedBox(height: S.m), Btn(label: 'باشگاه ${rs(club, 'name')}', small: true, colors: G.gold, onPress: () => nav.openClub(rs(club, 'id')))],
          if (!me)
            Press(
              onPress: toggleBlock,
              child: Container(constraints: const BoxConstraints(minHeight: 44), margin: const EdgeInsets.only(top: S.m), alignment: Alignment.center, child: T(blocked ? 'رفع مسدودی' : 'مسدود کردن این کاربر', style: fs(F.body, TS.small, color: C.red))),
            ),
        ]),
        Header(title: rs(p, 'username'), en: 'PILOT PROFILE', onBack: widget.onBack),
      ]);
    });
  }
}
