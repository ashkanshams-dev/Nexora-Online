// Club page — port of src/social/ClubPage.tsx: emblem, tag, description, members with roles, join / request,
// requests management, invite, club chat, leave (two-tap confirm), promote / demote / transfer / kick.
import 'dart:async';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType, RealtimeChannel;

import '../nav.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../online/challenges.dart' show Toast;
import '../online/ui.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'social_feed.dart';

Map<String, (String, Color)> get ROLE_FA => {'leader': ('رهبر', C.gold), 'officer': ('افسر', C.cyan), 'member': ('عضو', C.dim)};

class ClubPage extends StatefulWidget {
  final String id;
  final VoidCallback onBack;
  final Toast toast;
  const ClubPage({super.key, required this.id, required this.onBack, required this.toast});
  @override
  State<ClubPage> createState() => _ClubPageState();
}

class _ClubPageState extends State<ClubPage> {
  JRow? club;
  List<JRow> members = [], reqs = [], found = [];
  String? err, busy;
  bool sureLeave = false;
  final msg = TextEditingController(), inv = TextEditingController();
  RealtimeChannel? _ch;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    load();
    PostgresChangeFilter f() => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'club_id', value: widget.id);
    _ch = supabase
        .channel('club:${widget.id}')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'club_members', filter: f(), callback: (_) => load())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'club_requests', filter: f(), callback: (_) => load())
        .subscribe();
  }

  @override
  void dispose() {
    _t?.cancel();
    if (_ch != null) supabase.removeChannel(_ch!);
    msg.dispose();
    inv.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await Future.wait<dynamic>([
        supabase.from('club_list').select().eq('id', widget.id).maybeSingle(),
        supabase.from('club_members').select('user_id, role, joined_at, profiles(username, avatar, avatar_url, level, rating, online_at)').eq('club_id', widget.id),
        supabase.from('club_requests').select('user_id, kind, message, created_at, profiles(username, avatar, avatar_url, level)').eq('club_id', widget.id),
      ]);
      if (!mounted) return;
      if (r[0] == null) return setState(() => err = 'باشگاه پیدا نشد');
      const order = {'leader': 0, 'officer': 1, 'member': 2};
      final ms = List<JRow>.from(r[1] as List)
        ..sort((a, b) {
          final o = (order[a['role']] ?? 2).compareTo(order[b['role']] ?? 2);
          return o != 0 ? o : ri(b['profiles'] as Map<String, dynamic>?, 'rating').compareTo(ri(a['profiles'] as Map<String, dynamic>?, 'rating'));
        });
      setState(() {
        err = null;
        club = r[0] as JRow;
        members = ms;
        reqs = List<JRow>.from(r[2] as List);
      });
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  void search(String q) {
    _t?.cancel();
    final term = q.trim().replaceAll(RegExp(r'[%_]'), '');
    if (term.length < 2) return setState(() => found = []);
    _t = Timer(const Duration(milliseconds: 300), () async {
      final d = await supabase.from('profiles').select('id, username, avatar, avatar_url, club_id').ilike('username', '%$term%').isFilter('club_id', null).limit(8);
      if (mounted) setState(() => found = List<JRow>.from(d));
    });
  }

  Future<Object?> run(String k, Future<Object?> Function() fn, [String? ok]) async {
    if (busy != null) return null;
    setState(() => busy = k);
    try {
      final r = await fn();
      if (ok != null) widget.toast(ok, 'ok');
      buzz(Buzz.success);
      await load();
      Auth.I.refreshProfile();
      return r ?? true;
    } catch (e) {
      widget.toast(errFa(e), 'err');
      buzz(Buzz.heavy);
      return null;
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  void join() => run('join', () async {
        final r = await rpc('join_club', {'p_club': widget.id, 'p_message': msg.text.trim().isEmpty ? null : msg.text.trim()});
        if (r == 'joined') {
          sfx(Sfx.win);
          widget.toast('به باشگاه پیوستی!', 'ok');
        } else {
          widget.toast('درخواستت ارسال شد', 'ok');
        }
        return r;
      });

  Widget _sm(String s, Color c, VoidCallback f, {double size = 16}) => Press(onPress: f, child: SizedBox(width: 40, height: 44, child: Center(child: T(s, style: fs(F.body, size, color: c)))));
  Widget _h(String s) => Padding(padding: const EdgeInsets.only(top: S.l, bottom: S.s), child: T(s, align: TextAlign.right, style: fs(F.bold, TS.h)));
  BoxDecoration get _row => BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line), color: rgba(10, 16, 44, .86));

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context), c = club;
    if (c == null) {
      return Stack(children: [
        err != null ? Padding(padding: EdgeInsets.only(top: ins.top + 90), child: ErrorState(msg: err!, onRetry: load)) : const Center(child: Spinner(size: 36)),
        Header(title: 'باشگاه', onBack: widget.onBack),
      ]);
    }
    final uid = Auth.I.uid, nav = NavScope.of(context);
    final mine = members.where((m) => m['user_id'] == uid).firstOrNull, role = mine?['role'] as String?;
    final officer = role == 'leader' || role == 'officer';
    final myReq = reqs.where((r) => r['user_id'] == uid).firstOrNull, requests = reqs.where((r) => r['kind'] == 'request').toList();
    final policy = rs(c, 'join_policy', 'open');
    return Stack(children: [
      ListView(padding: EdgeInsets.fromLTRB(S.l, ins.top + 76, S.l, ins.bottom + S.xl), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
        Panel(
          accent: C.gold,
          glow: true,
          pad: const EdgeInsets.all(S.l),
          child: Stack(children: [
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [rgba(255, 210, 87, .22), Colors.transparent])))),
            Column(children: [
              Float(amp: 4, child: Img(discImgOf(c['emblem'] as String?), w: 96, h: 96)),
              const SizedBox(height: S.s),
              rrow(main: MainAxisAlignment.center, [Flexible(child: T(rs(c, 'name'), style: fs(F.title, 20))), Badge2(label: rs(c, 'tag'), color: C.gold)]),
              if (c['description'] != null) Padding(padding: const EdgeInsets.only(top: S.s), child: T('${c['description']}', align: TextAlign.center, style: fs(F.body, TS.small, color: hex('#d9e6ff')))),
              const SizedBox(height: S.m),
              rrow([
                for (final (v, l) in [
                  ('${fa(ri(c, 'members'))}/${fa(ri(c, 'max_members'))}', 'اعضا'),
                  (fa(ri(c, 'power')), 'قدرت'),
                  (policy == 'open' ? 'آزاد' : policy == 'request' ? 'درخواست' : 'دعوت', 'عضوگیری'),
                  (fa(ri(c, 'min_level', 1)), 'حداقل سطح'),
                ])
                  Expanded(child: Column(children: [T(v, style: fs(F.bold, TS.body)), T(l, style: fs(F.body, TS.tiny, color: C.dim))])),
              ]),
            ]),
          ]),
        ),
        const SizedBox(height: S.m),
        if (mine != null)
          rrow([
            if (c['conversation_id'] != null) ...[
              Expanded(child: Btn(label: 'چت باشگاه', small: true, colors: G.green, onPress: () => nav.openChat(rs(c, 'conversation_id')))),
              const SizedBox(width: S.s),
            ],
            Expanded(
              child: Btn(label: sureLeave ? 'مطمئنی؟' : 'ترک باشگاه', small: true, colors: G.red, onPress: () async {
                if (!sureLeave) {
                  buzz(Buzz.medium);
                  return setState(() => sureLeave = true);
                }
                final ok = await run('leave', () => rpc('leave_club'), 'از باشگاه خارج شدی');
                if (ok != null) widget.onBack();
              }),
            ),
          ])
        else if (Auth.I.profile?['club_id'] != null)
          T('تو عضو باشگاه دیگری هستی', align: TextAlign.center, style: fs(F.body, 14, color: C.dim))
        else if (myReq?['kind'] == 'request')
          T('درخواست عضویتت در انتظار بررسی است', align: TextAlign.center, style: fs(F.body, 14, color: C.cyan))
        else if (policy == 'invite' && myReq?['kind'] != 'invite')
          T('این باشگاه فقط با دعوت عضو می‌گیرد', align: TextAlign.center, style: fs(F.body, 14, color: C.dim))
        else
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (policy == 'request' && myReq?['kind'] != 'invite') OField(label: 'پیام برای رهبر (اختیاری)', ctl: msg, maxLength: 120),
            Btn(
              label: busy == 'join' ? '…' : myReq?['kind'] == 'invite' ? 'پذیرفتن دعوت' : policy == 'open' ? 'پیوستن' : 'ارسال درخواست',
              colors: G.gold, disabled: busy != null, onPress: join,
            ),
          ]),
        if (officer && requests.isNotEmpty) ...[
          _h('درخواست‌ها (${fa(requests.length)})'),
          for (final r in requests)
            Container(
              constraints: const BoxConstraints(minHeight: 60), margin: const EdgeInsets.only(bottom: S.s), padding: const EdgeInsets.symmetric(horizontal: S.s), decoration: _row,
              child: rrow([
                AvatarO(avatar: (r['profiles'] as Map?)?['avatar'] as String?, url: (r['profiles'] as Map?)?['avatar_url'] as String?, size: 40),
                const SizedBox(width: S.s),
                Expanded(child: rcol([T('${(r['profiles'] as Map?)?['username'] ?? '…'}', n: 1, style: fs(F.bold, 14)), if (r['message'] != null) T('${r['message']}', n: 2, style: fs(F.body, TS.cap, color: C.dim))])),
                _sm('✓', C.green, () => run('d${r['user_id']}', () => rpc('club_decide', {'p_club': widget.id, 'p_user': r['user_id'], 'p_accept': true}), 'پذیرفته شد'), size: 18),
                _sm('✕', C.red, () => run('d${r['user_id']}', () => rpc('club_decide', {'p_club': widget.id, 'p_user': r['user_id'], 'p_accept': false}))),
              ]),
            ).animate().fadeIn().slideX(begin: .1),
        ],
        if (officer) ...[
          _h('دعوت بازیکن'),
          OField(ctl: inv, placeholder: 'نام کاربری…', onChanged: search),
          for (final f in found)
            Container(
              constraints: const BoxConstraints(minHeight: 56), margin: const EdgeInsets.only(bottom: S.s), padding: const EdgeInsets.symmetric(horizontal: S.s), decoration: _row,
              child: rrow([
                AvatarO(avatar: f['avatar'] as String?, url: f['avatar_url'] as String?, size: 36),
                const SizedBox(width: S.s),
                Expanded(child: T(rs(f, 'username'), n: 1, align: TextAlign.right)),
                Press(
                  onPress: () {
                    run('inv', () => rpc('club_invite', {'p_club': widget.id, 'p_user': f['id']}), 'دعوت فرستاده شد');
                    inv.clear();
                    setState(() => found = []);
                  },
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: S.s, vertical: 12), child: T('دعوت', style: fs(F.bold, TS.small, color: C.gold))),
                ),
              ]),
            ),
        ],
        _h('اعضا (${fa(members.length)})'),
        for (final (i, m) in members.indexed)
          () {
            final (rl, rc) = ROLE_FA[m['role']] ?? ROLE_FA['member']!;
            final pr = m['profiles'] as Map?, u = rs(m, 'user_id');
            return Enter(
              i: i,
              child: Container(
                constraints: const BoxConstraints(minHeight: 60), margin: const EdgeInsets.only(bottom: S.s), padding: const EdgeInsets.symmetric(horizontal: S.s), decoration: _row,
                child: rrow([
                  Press(onPress: () => nav.openProfile(u), child: AvatarO(avatar: pr?['avatar'] as String?, url: pr?['avatar_url'] as String?, size: 42, ring: isOnline(pr?['online_at']) ? C.green : C.line)),
                  const SizedBox(width: S.s),
                  Expanded(
                    child: rcol([
                      T('${pr?['username'] ?? '…'}${u == uid ? ' (تو)' : ''}', n: 1, style: fs(F.bold, 14)),
                      rrow([Badge2(label: rl, color: rc), Badge2(label: 'سطح ${fa((pr?['level'] as num?)?.toInt() ?? 1)}', color: C.sky)]),
                    ]),
                  ),
                  if (role == 'leader' && u != uid) ...[
                    _sm(m['role'] == 'officer' ? '⬇' : '⬆', C.cyan, () => run('a$u', () => rpc('club_member_action', {'p_club': widget.id, 'p_user': u, 'p_action': m['role'] == 'officer' ? 'demote' : 'promote'}))),
                    _sm('👑', C.gold, () => run('a$u', () => rpc('club_member_action', {'p_club': widget.id, 'p_user': u, 'p_action': 'transfer'}), 'رهبری منتقل شد'), size: 14),
                  ],
                  if (officer && u != uid && (m['role'] == 'member' || (role == 'leader' && m['role'] == 'officer')))
                    _sm('✕', C.red, () => run('a$u', () => rpc('club_member_action', {'p_club': widget.id, 'p_user': u, 'p_action': 'kick'}), 'اخراج شد')),
                ]),
              ),
            );
          }(),
      ]),
      Header(title: rs(c, 'name'), en: 'CLUB · ${rs(c, 'tag')}', accent: C.gold, onBack: widget.onBack),
    ]);
  }
}
