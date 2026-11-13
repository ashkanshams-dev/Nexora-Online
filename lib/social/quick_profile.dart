// Tap-on-any-player card — port of src/social/QuickProfile.tsx: avatar, level, followers + one-tap Follow / Message / full profile.
import 'package:material_ui/material_ui.dart';

import '../net/auth.dart';
import '../net/supabase.dart';
import '../online/challenges.dart' show Toast;
import '../online/ui.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'social_feed.dart';

class QuickProfile extends StatefulWidget {
  final String id;
  final VoidCallback onClose, onFull;
  final void Function(String cid) onChat;
  final Toast toast;
  const QuickProfile({super.key, required this.id, required this.onClose, required this.onFull, required this.onChat, required this.toast});
  @override
  State<QuickProfile> createState() => _QuickProfileState();
}

class _QuickProfileState extends State<QuickProfile> {
  JRow? p;
  int followers = 0;
  bool following = false, busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Auth.I.uid;
    try {
      final r = await Future.wait<dynamic>([
        supabase.from('profiles').select().eq('id', widget.id).maybeSingle(),
        supabase.from('profile_stats').select('followers').eq('id', widget.id).maybeSingle(),
        uid != null ? supabase.from('follows').select('followee').eq('follower', uid).eq('followee', widget.id).maybeSingle() : Future.value(null),
      ]);
      if (!mounted) return;
      if (r[0] == null) {
        widget.toast('بازیکن پیدا نشد', 'err');
        return widget.onClose();
      }
      setState(() {
        p = r[0] as JRow;
        followers = ri(r[1] as JRow?, 'followers');
        following = r[2] != null;
      });
    } catch (e) {
      widget.toast(errFa(e), 'err');
      widget.onClose();
    }
  }

  Future<void> toggle() async {
    final uid = Auth.I.uid;
    if (uid == null) return widget.toast('برای دنبال کردن وارد حساب شو', 'err');
    if (busy) return;
    setState(() => busy = true);
    try {
      if (following) {
        await supabase.from('follows').delete().eq('follower', uid).eq('followee', widget.id);
      } else {
        await supabase.from('follows').insert({'follower': uid, 'followee': widget.id});
        sfx(Sfx.ready);
        widget.toast('دنبال کردی ✓', 'ok');
      }
      buzz(Buzz.medium);
      setState(() {
        followers += following ? -1 : 1;
        following = !following;
      });
    } catch (e) {
      widget.toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> message() async {
    try {
      final cid = await rpc('open_dm', {'p_user': widget.id});
      widget.onClose();
      widget.onChat('$cid');
    } catch (e) {
      widget.toast(errFa(e), 'err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = this.p;
    if (p == null) return const SizedBox(height: 220, child: Center(child: Spinner(size: 32)));
    final lp = levelProgress(ri(p, 'xp')), me = Auth.I.uid == widget.id;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AvatarO(avatar: (p['equipped_disc'] ?? p['avatar']) as String?, url: p['avatar_url'] as String?, size: 84, ring: isOnline(p['online_at']) ? C.green : C.cyan),
        const SizedBox(height: 10),
        T(rs(p, 'username', '—'), n: 1, style: fs(F.bold, 19)),
        const SizedBox(height: 8),
        rrow(main: MainAxisAlignment.center, [
          for (final (v, l) in [(fa(lp.level), 'سطح'), (fa(followers), 'دنبال‌کننده'), (fa(ri(p, 'trophies')), 'جام')])
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Column(children: [T(v, style: fs(F.bold, 16, color: C.gold)), T(l, style: fs(F.body, 11, color: C.dim))])),
        ]),
        if (!me) ...[
          const SizedBox(height: 16),
          rrow([
            Expanded(child: Btn(label: following ? 'دنبال می‌کنی ✓' : 'دنبال کردن', small: true, colors: following ? G.dark : G.primary, disabled: busy, onPress: toggle)),
            const SizedBox(width: 8),
            Expanded(child: Btn(label: 'پیام', small: true, colors: G.violet, onPress: message)),
          ]),
        ],
        const SizedBox(height: 8),
        Btn(label: 'مشاهده‌ی پروفایل کامل', small: true, colors: G.dark, onPress: () {
          widget.onClose();
          widget.onFull();
        }),
      ]),
    );
  }
}
