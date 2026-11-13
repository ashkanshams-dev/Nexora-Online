// Social tab — port of src/social/Social.tsx (messages: inbox + user search + discover / new group-channel; clubs: list,
// search, create; friends) extended with friend requests (friends = mutual follows) and the notifications inbox.
import 'dart:async';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType, RealtimeChannel;

import '../game/assets.dart';
import '../nav.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../online/challenges.dart' show Toast;
import '../online/ui.dart';
import '../sound.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'notifications.dart';
import 'social_feed.dart';

export 'chat.dart' show ChatScreen;
export 'club_page.dart' show ClubPage;
export 'notifications.dart' show NotificationsList, NotifFeed;
export 'public_profile.dart' show PublicProfile;
export 'quick_profile.dart' show QuickProfile;
export 'social_feed.dart';

class Social extends StatefulWidget {
  final double top, bottom;
  final Toast toast;
  const Social({super.key, required this.top, required this.bottom, required this.toast});
  @override
  State<Social> createState() => _SocialState();
}

class _SocialState extends State<Social> {
  String tab = 'msg';
  bool busy = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([Auth.I, NotifFeed.I]),
        builder: (_, _) {
          if (Auth.I.uid == null) {
            return Padding(
              padding: EdgeInsets.only(top: widget.top, bottom: widget.bottom),
              child: Center(
                child: Empty(
                  img: UI2['c_profile'], title: 'اجتماعی', sub: 'برای پیام، باشگاه و دوستان وارد بخش آنلاین شو (مهمان هم می‌شود)',
                  action: busy ? '…' : 'ورود به‌عنوان مهمان',
                  onAction: () async {
                    setState(() => busy = true);
                    try {
                      await Auth.I.ensure();
                    } catch (_) {
                      widget.toast('اتصال برقرار نشد', 'err');
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
                ),
              ),
            );
          }
          final unread = NotifFeed.I.unread, reqs = NotifFeed.I.pendingRequests;
          return Padding(
            padding: EdgeInsets.only(top: widget.top),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.s),
                child: Stack(clipBehavior: Clip.none, children: [
                  Tabs2(items: [('msg', 'پیام‌ها'), ('club', 'باشگاه‌ها'), ('friends', 'دوستان'), ('notif', 'اعلان‌ها')], value: tab, onChange: (v) => setState(() => tab = v)),
                  if (unread > 0) Positioned(left: 6, top: -4, child: _dot(unread)),
                  if (reqs > 0) Positioned(left: MediaQuery.sizeOf(context).width * .25, top: -4, child: _dot(reqs)),
                ]),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: 220.ms,
                  child: KeyedSubtree(
                    key: ValueKey(tab),
                    child: switch (tab) {
                      'msg' => _Messages(bottom: widget.bottom, toast: widget.toast),
                      'club' => _Clubs(bottom: widget.bottom, toast: widget.toast),
                      'friends' => _Friends(bottom: widget.bottom, toast: widget.toast),
                      _ => NotificationsList(bottom: widget.bottom, toast: widget.toast),
                    },
                  ),
                ),
              ),
            ]),
          );
        },
      );

  Widget _dot(int n) => Container(
        constraints: const BoxConstraints(minWidth: 18), height: 18, padding: const EdgeInsets.symmetric(horizontal: 4), alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), color: C.red, border: Border.all(color: hex('#0b1236'), width: 1.5)),
        child: T(n > 9 ? '9+' : fa(n), style: fs(F.bold, 9, color: Colors.white)),
      ).animate(key: ValueKey(n)).scaleXY(begin: .4, curve: Curves.elasticOut, duration: 600.ms);
}

BoxDecoration rowDeco([Color? border]) => BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: border ?? C.line), color: rgba(10, 16, 44, .86));

Widget pillBtn(String label, Color color, VoidCallback onPress, {bool disabled = false}) => Press(
      onPress: onPress,
      disabled: disabled,
      child: Container(
        height: 44, padding: const EdgeInsets.symmetric(horizontal: S.m), alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line), color: rgba(8, 14, 40, .85)),
        child: T(label, style: fs(F.bold, TS.small, color: color)),
      ),
    );

Widget convIcon(String kind, String? url, {double size = 48}) => Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kind == 'club' ? C.gold : kind == 'channel' ? C.violet : C.cyan, width: 2), color: hex('#050816')),
      child: url != null
          ? ClipOval(child: Img(url, w: size - 4, h: size - 4, fit: BoxFit.cover))
          : Img(kind == 'club' ? UI2['x_shield'] : kind == 'channel' ? UI2['c_mega'] : UI2['x_team'], w: size * .66, h: size * .66),
    );

Widget onlineDot([double s = 13]) => Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: C.green, border: Border.all(color: hex('#0b1236'), width: 2)));

/// debounced username search (≥ 2 chars)
class UserSearch {
  Timer? _t;
  void run(String q, void Function(List<JRow>? r) done, {bool noClub = false, String cols = 'id, username, avatar, avatar_url, level, online_at'}) {
    _t?.cancel();
    final term = q.trim().replaceAll(RegExp(r'[%_]'), '');
    if (term.length < 2) return done(null);
    _t = Timer(const Duration(milliseconds: 300), () async {
      try {
        var b = supabase.from('profiles').select(cols).ilike('username', '%$term%');
        final uid = Auth.I.uid;
        if (uid != null) b = b.neq('id', uid);
        if (noClub) b = b.isFilter('club_id', null);
        done(List<JRow>.from(await b.limit(20)));
      } catch (_) {
        done([]);
      }
    });
  }

  void dispose() => _t?.cancel();
}

// ======================= messages =======================
class _Messages extends StatefulWidget {
  final double bottom;
  final Toast toast;
  const _Messages({required this.bottom, required this.toast});
  @override
  State<_Messages> createState() => _MessagesState();
}

class _MessagesState extends State<_Messages> {
  List<JRow>? rows;
  List<JRow>? found;
  String? err;
  RealtimeChannel? _ch;
  Timer? _t;
  final search = UserSearch();

  @override
  void initState() {
    super.initState();
    load();
    final uid = Auth.I.uid!;
    void soon() {
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 400), load);
    }

    // RLS limits message events to conversations I belong to
    _ch = supabase
        .channel('inbox:$uid')
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'messages', callback: (_) => soon())
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'conversation_members',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid), callback: (_) => soon())
        .subscribe();
  }

  @override
  void dispose() {
    _t?.cancel();
    search.dispose();
    if (_ch != null) supabase.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await supabase.from('inbox').select().order('last_message_at', ascending: false).limit(100);
      if (!mounted) return;
      setState(() {
        err = null;
        rows = List<JRow>.from(d);
      });
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  Future<void> dm(String id) async {
    try {
      final cid = await rpc('open_dm', {'p_user': id});
      if (mounted) NavScope.of(context).openChat('$cid');
    } catch (e) {
      widget.toast(errFa(e), 'err');
    }
  }

  void sheet(bool isNew) {
    final nav = NavScope.of(context);
    showNxSheet(context,
        title: isNew ? 'گروه یا کانال جدید' : 'کشف گروه‌ها و کانال‌ها', en: isNew ? 'NEW CONVERSATION' : 'DISCOVER', height: .82,
        builder: (c) => isNew
            ? _NewConv(toast: widget.toast, onDone: (id) {
                Navigator.of(c).pop();
                nav.openChat(id);
              })
            : _Discover(toast: widget.toast, onOpen: (id) {
                Navigator.of(c).pop();
                nav.openChat(id);
              }));
  }

  @override
  Widget build(BuildContext context) {
    final nav = NavScope.of(context);
    return RefreshIndicator(
      onRefresh: load,
      color: C.cyan,
      child: ListView(
        padding: EdgeInsets.only(bottom: widget.bottom + S.l),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.l),
            child: Column(children: [
              OField(placeholder: 'جستجوی بازیکن با نام کاربری…', onChanged: (q) => search.run(q, (r) => mounted ? setState(() => found = r) : null)),
              if (found != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.m),
                  child: found!.isEmpty
                      ? T('کسی پیدا نشد', align: TextAlign.center, style: fs(F.body, 14, color: C.dim))
                      : Column(children: [
                          for (final p in found!)
                            Container(
                              constraints: const BoxConstraints(minHeight: 60), margin: const EdgeInsets.only(bottom: S.s), padding: const EdgeInsets.symmetric(horizontal: S.s),
                              decoration: rowDeco(),
                              child: rrow([
                                Press(onPress: () => nav.openProfile(rs(p, 'id')), child: AvatarO(avatar: p['avatar'] as String?, url: p['avatar_url'] as String?, size: 40, ring: isOnline(p['online_at']) ? C.green : C.line)),
                                const SizedBox(width: S.s),
                                Expanded(child: rcol([T(rs(p, 'username'), n: 1, style: fs(F.bold, TS.body)), T('سطح ${fa(ri(p, 'level', 1))}', style: fs(F.body, TS.tiny, color: C.dim))])),
                                pillBtn('پیام', C.cyan, () => dm(rs(p, 'id'))),
                              ]),
                            ).animate().fadeIn(duration: 200.ms),
                        ]),
                ),
              rrow([
                Expanded(child: Btn(label: 'گروه / کانال جدید', small: true, colors: G.green, onPress: () => sheet(true))),
                const SizedBox(width: S.s),
                Expanded(child: Btn(label: 'کشف گروه‌ها', small: true, colors: G.dark, onPress: () => sheet(false))),
              ]),
              const SizedBox(height: S.m),
            ]),
          ),
          if (err != null && rows == null)
            ErrorState(msg: err!, onRetry: load)
          else if (rows == null)
            const Padding(padding: EdgeInsets.symmetric(horizontal: S.l), child: Skeleton(rows: 5, h: 64))
          else if (rows!.isEmpty)
            Empty(img: UI2['c_mega'], title: 'هنوز گفتگویی نداری', sub: 'یک بازیکن را جستجو کن یا به یک گروه بپیوند')
          else
            for (final (i, r) in rows!.indexed) Enter(i: i, child: _InboxItem(r: r, onPress: () => nav.openChat(rs(r, 'id')))),
        ],
      ),
    );
  }
}

class _InboxItem extends StatelessWidget {
  final JRow r;
  final VoidCallback onPress;
  const _InboxItem({required this.r, required this.onPress});
  @override
  Widget build(BuildContext context) {
    final kind = rs(r, 'kind', 'dm'), peer = r['peer'] as Map?, lm = r['last_message'] as Map?, unread = ri(r, 'unread');
    final title = kind == 'dm' ? (peer?['username'] as String? ?? 'گفتگو') : (r['title'] as String? ?? KIND_LABEL[kind] ?? '');
    final kc = kind == 'club' ? C.gold : kind == 'channel' ? C.violet : C.cyan;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.l),
      child: Press(
        onPress: onPress,
        scaleTo: .98,
        child: Container(
          height: 72, margin: const EdgeInsets.only(bottom: S.s), padding: const EdgeInsets.symmetric(horizontal: S.s),
          decoration: rowDeco(unread > 0 ? kc.withValues(alpha: .5) : null),
          child: rrow([
            Stack(children: [
              kind == 'dm' ? AvatarO(avatar: peer?['avatar'] as String?, url: peer?['avatar_url'] as String?, size: 48, ring: isOnline(peer?['online_at']) ? C.green : C.line) : convIcon(kind, r['avatar_url'] as String?),
              if (kind == 'dm' && isOnline(peer?['online_at'])) Positioned(bottom: 1, left: 1, child: onlineDot()),
            ]),
            const SizedBox(width: S.s),
            Expanded(
              child: rcol([
                rrow([Flexible(child: T(title, n: 1, style: fs(F.bold, TS.body))), if (kind != 'dm') Badge2(label: KIND_LABEL[kind] ?? kind, color: kc)]),
                const SizedBox(height: 2),
                T(lm == null ? 'بدون پیام' : (lm['image_url'] != null && lm['body'] == null ? '📷 عکس' : '${lm['body'] ?? ''}'), n: 1, style: fs(F.body, TS.small, color: unread > 0 ? C.text : C.dim)),
              ]),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                T(timeAgo(lm?['created_at'] ?? r['last_message_at']), style: fs(F.body, TS.tiny, color: C.dim)),
                if (unread > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22), height: 22, margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 5), alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), color: C.red),
                    child: T(fa(unread > 99 ? 99 : unread), style: fs(F.bold, 10, color: Colors.white)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NewConv extends StatefulWidget {
  final Toast toast;
  final void Function(String id) onDone;
  const _NewConv({required this.toast, required this.onDone});
  @override
  State<_NewConv> createState() => _NewConvState();
}

class _NewConvState extends State<_NewConv> {
  String kind = 'group';
  final title = TextEditingController(), about = TextEditingController();
  bool pub = true, busy = false;
  @override
  void dispose() {
    title.dispose();
    about.dispose();
    super.dispose();
  }

  Future<void> go() async {
    if (title.text.trim().length < 2) return widget.toast('عنوان لازم است', 'err');
    setState(() => busy = true);
    try {
      final id = await rpc('create_conversation', {'p_kind': kind, 'p_title': title.text.trim(), 'p_about': about.text.trim().isEmpty ? null : about.text.trim(), 'p_public': pub, 'p_members': <String>[]});
      sfx(Sfx.ready);
      widget.onDone('$id');
    } catch (e) {
      widget.toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(S.l), children: [
        Segment(value: kind, onChange: (v) => setState(() => kind = v), items: const [('group', 'گروه'), ('channel', 'کانال')]),
        Padding(
          padding: const EdgeInsets.only(top: S.s, bottom: S.m),
          child: T(kind == 'group' ? 'در گروه همه‌ی اعضا پیام می‌فرستند.' : 'در کانال فقط مالک و مدیرها پیام می‌فرستند.', align: TextAlign.right, style: fs(F.body, TS.cap, color: C.dim)),
        ),
        OField(label: 'عنوان', ctl: title, maxLength: 40),
        OField(label: 'توضیح (اختیاری)', ctl: about, maxLength: 200, lines: 3),
        SizedBox(
          height: 56,
          child: rrow([
            Expanded(child: rcol([T('عمومی', style: fs(F.bold, 14)), T('در بخش «کشف» دیده شود و همه بتوانند بپیوندند', style: fs(F.body, TS.cap, color: C.dim))])),
            Toggle(on: pub, onChange: (v) => setState(() => pub = v)),
          ]),
        ),
        const SizedBox(height: S.l),
        Btn(label: busy ? '…' : 'ساختن', colors: G.green, disabled: busy, onPress: go),
      ]);
}

class _Discover extends StatefulWidget {
  final Toast toast;
  final void Function(String id) onOpen;
  const _Discover({required this.toast, required this.onOpen});
  @override
  State<_Discover> createState() => _DiscoverState();
}

class _DiscoverState extends State<_Discover> {
  List<JRow>? rows;
  @override
  void initState() {
    super.initState();
    supabase.from('public_conversations').select().order('members', ascending: false).limit(50).then((d) {
      if (mounted) setState(() => rows = List<JRow>.from(d));
    }, onError: (_) {
      if (mounted) setState(() => rows = []);
    });
  }

  Future<void> join(String id) async {
    try {
      await rpc('join_conversation', {'p_conv': id});
      sfx(Sfx.join);
      widget.onOpen(id);
    } catch (e) {
      widget.toast(errFa(e), 'err');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (rows == null) return const Padding(padding: EdgeInsets.all(S.l), child: Skeleton(rows: 4));
    if (rows!.isEmpty) return const Empty(title: 'هنوز گروه عمومی‌ای نیست', sub: 'اولین گروه را خودت بساز');
    return ListView.builder(
      padding: const EdgeInsets.all(S.l),
      itemCount: rows!.length,
      itemBuilder: (_, i) {
        final it = rows![i], kind = rs(it, 'kind', 'group');
        return Enter(
          i: i,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60), margin: const EdgeInsets.only(bottom: S.s), padding: const EdgeInsets.symmetric(horizontal: S.s),
            decoration: rowDeco(),
            child: rrow([
              convIcon(kind, it['avatar_url'] as String?),
              const SizedBox(width: S.s),
              Expanded(
                child: rcol([
                  T(rs(it, 'title'), n: 1, style: fs(F.bold, 14)),
                  T('${KIND_LABEL[kind] ?? kind} · ${fa(ri(it, 'members'))} عضو${it['about'] != null ? ' · ${it['about']}' : ''}', n: 1, style: fs(F.body, TS.cap, color: C.dim)),
                ]),
              ),
              pillBtn('پیوستن', C.green, () => join(rs(it, 'id'))),
            ]),
          ),
        );
      },
    );
  }
}

// ======================= clubs =======================
final CLUB_EMBLEMS = [for (var i = 0; i < 18; i++) 'leg$i'];

class _Clubs extends StatefulWidget {
  final double bottom;
  final Toast toast;
  const _Clubs({required this.bottom, required this.toast});
  @override
  State<_Clubs> createState() => _ClubsState();
}

class _ClubsState extends State<_Clubs> {
  List<JRow>? rows;
  String q = '';
  Timer? _t;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      var b = supabase.from('club_list').select();
      final term = q.trim().replaceAll(RegExp(r'[%_,()]'), '');
      if (term.isNotEmpty) b = b.or('name.ilike.%$term%,tag.ilike.%$term%');
      final d = await b.order('power', ascending: false).limit(50);
      if (mounted) setState(() => rows = List<JRow>.from(d));
    } catch (_) {
      if (mounted) setState(() => rows ??= []);
    }
  }

  void create() {
    final nav = NavScope.of(context);
    showNxSheet(context, title: 'ساخت باشگاه', en: 'NEW CLUB', accent: C.gold, height: .9, builder: (c) => _CreateClub(toast: widget.toast, onDone: (id) {
          Navigator.of(c).pop();
          nav.openClub(id);
        }));
  }

  @override
  Widget build(BuildContext context) {
    final nav = NavScope.of(context), my = Auth.I.profile?['club_id'] as String?;
    return RefreshIndicator(
      onRefresh: load,
      color: C.cyan,
      child: ListView(
        padding: EdgeInsets.only(bottom: widget.bottom + S.l),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              my != null ? Btn(label: 'باشگاه من', colors: G.gold, small: true, onPress: () => nav.openClub(my)) : Btn(label: 'ساخت باشگاه (۵۰ الماس)', colors: G.green, small: true, onPress: create),
              const SizedBox(height: S.s),
              OField(placeholder: 'جستجوی نام یا تگ باشگاه…', upper: true, onChanged: (v) {
                q = v;
                _t?.cancel();
                _t = Timer(const Duration(milliseconds: 250), load);
              }),
              T('برترین باشگاه‌ها', align: TextAlign.right, style: fs(F.bold, TS.h)),
              const SizedBox(height: S.s),
            ]),
          ),
          if (rows == null)
            const Padding(padding: EdgeInsets.symmetric(horizontal: S.l), child: Skeleton(rows: 5, h: 70))
          else if (rows!.isEmpty)
            Empty(img: UI2['x_shield'], title: 'باشگاهی پیدا نشد')
          else
            for (final (i, it) in rows!.indexed)
              Enter(
                i: i,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.l),
                  child: Press(
                    onPress: () => nav.openClub(rs(it, 'id')),
                    scaleTo: .98,
                    child: Container(
                      height: 70, margin: const EdgeInsets.only(bottom: S.s), padding: const EdgeInsets.symmetric(horizontal: S.s),
                      decoration: rowDeco(it['id'] == my ? C.gold : null),
                      child: rrow([
                        SizedBox(width: 28, child: T(fa(i + 1), align: TextAlign.center, style: fs(F.title, 14, color: i < 3 ? C.gold : C.dim))),
                        Img(discImgOf(it['emblem'] as String?), w: 46, h: 46),
                        const SizedBox(width: S.s),
                        Expanded(
                          child: rcol([
                            rrow([Flexible(child: T(rs(it, 'name'), n: 1, style: fs(F.bold, 14))), Badge2(label: rs(it, 'tag'), color: C.gold)]),
                            T('${fa(ri(it, 'members'))}/${fa(ri(it, 'max_members'))} عضو · ${policyFa(it['join_policy'])}', style: fs(F.body, TS.cap, color: C.dim)),
                          ]),
                        ),
                        SizedBox(width: 64, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [T(fa(ri(it, 'power')), style: fs(F.title, 13, color: C.orange)), T('قدرت', style: fs(F.body, 9, color: C.dim))])),
                      ]),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

String policyFa(Object? p) => p == 'open' ? 'آزاد' : p == 'request' ? 'با درخواست' : 'فقط دعوت';

class _CreateClub extends StatefulWidget {
  final Toast toast;
  final void Function(String id) onDone;
  const _CreateClub({required this.toast, required this.onDone});
  @override
  State<_CreateClub> createState() => _CreateClubState();
}

class _CreateClubState extends State<_CreateClub> {
  final name = TextEditingController(), tag = TextEditingController(), desc = TextEditingController();
  String emblem = 'club0', policy = 'open';
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    tag.dispose();
    desc.dispose();
    super.dispose();
  }

  Future<void> go() async {
    final n = name.text.trim(), t = tag.text;
    if (n.length < 3 || n.length > 24) return widget.toast('نام باشگاه ۳ تا ۲۴ کاراکتر', 'err');
    if (!RegExp(r'^[A-Z0-9]{2,5}$').hasMatch(t)) return widget.toast('تگ: ۲ تا ۵ حرف/عدد انگلیسی بزرگ', 'err');
    if (ri(Auth.I.profile, 'gems') < 50) return widget.toast('۵۰ الماس لازم داری', 'err');
    setState(() => busy = true);
    try {
      final id = await rpc('create_club', {'p_name': n, 'p_tag': t, 'p_emblem': emblem, 'p_desc': desc.text.trim().isEmpty ? null : desc.text.trim(), 'p_policy': policy, 'p_min_level': 1});
      sfx(Sfx.win);
      buzz(Buzz.success);
      widget.toast('باشگاه ساخته شد!', 'ok');
      Auth.I.refreshProfile();
      widget.onDone('$id');
    } catch (e) {
      widget.toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(S.l, S.l, S.l, S.xl * 2), children: [
        OField(label: 'نام باشگاه', ctl: name, maxLength: 24),
        OField(label: 'تگ (۲ تا ۵ حرف انگلیسی)', ctl: tag, center: true, mono: true, upper: true, maxLength: 5, onChanged: (v) {
          final f = v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
          if (f != v) tag.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
        }),
        OField(label: 'توضیح', ctl: desc, maxLength: 300, lines: 3),
        T('نشان', align: TextAlign.right, style: fs(F.bold, TS.small, color: C.dim)),
        const SizedBox(height: S.s),
        Wrap(textDirection: TextDirection.rtl, spacing: S.s, runSpacing: S.s, children: [
          for (final e in CLUB_EMBLEMS)
            Press(
              onPress: () => setState(() => emblem = e),
              child: AnimatedContainer(
                duration: 200.ms,
                width: 56, height: 56, alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: e == emblem ? C.gold : C.line), color: e == emblem ? rgba(255, 210, 87, .15) : null),
                child: Img(discImgOf(e), w: 40, h: 40),
              ),
            ),
        ]),
        Padding(padding: const EdgeInsets.only(top: S.l, bottom: S.s), child: T('عضوگیری', align: TextAlign.right, style: fs(F.bold, TS.small, color: C.dim))),
        Segment(value: policy, onChange: (v) => setState(() => policy = v), items: const [('open', 'آزاد'), ('request', 'با درخواست'), ('invite', 'فقط دعوت')], accent: C.gold),
        const SizedBox(height: S.l),
        Btn(label: busy ? '…' : 'ساخت باشگاه · ۵۰ الماس', colors: G.gold, disabled: busy, onPress: go),
      ]);
}

// ======================= friends =======================
class _Friends extends StatefulWidget {
  final double bottom;
  final Toast toast;
  const _Friends({required this.bottom, required this.toast});
  @override
  State<_Friends> createState() => _FriendsState();
}

class _FriendsState extends State<_Friends> {
  String mode = 'friends';
  List<JRow>? rows;
  List<JRow>? requests;
  String? busy;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => rows = null);
    final uid = Auth.I.uid!;
    try {
      List<String> ids;
      if (mode == 'friends') {
        final d = await supabase.from('friends').select('friend_id').eq('user_id', uid).limit(300);
        ids = [for (final r in d) '${r['friend_id']}'];
      } else if (mode == 'requests') {
        final d = await supabase.from('friend_requests').select('from_user, created_at').eq('to_user', uid).eq('status', 'pending').order('created_at', ascending: false);
        ids = [for (final r in d) '${r['from_user']}'];
      } else {
        final col = mode == 'following' ? 'follower' : 'followee', other = mode == 'following' ? 'followee' : 'follower';
        final d = await supabase.from('follows').select(other).eq(col, uid).limit(200);
        ids = [for (final r in d) '${r[other]}'];
      }
      if (ids.isEmpty) {
        if (mounted) setState(() => rows = []);
        return;
      }
      final ps = List<JRow>.from(await supabase.from('profiles').select('id, username, avatar, avatar_url, level, online_at, league').inFilter('id', ids));
      if (mode != 'requests') ps.sort((a, b) => (isOnline(b['online_at']) ? 1 : 0) - (isOnline(a['online_at']) ? 1 : 0));
      if (mounted) setState(() => rows = ps);
    } catch (e) {
      if (mounted) setState(() => rows = []);
      widget.toast(errFa(e), 'err');
    }
  }

  Future<void> respond(String from, bool accept) async {
    setState(() => busy = from);
    try {
      await rpc('respond_friend_request', {'p_from': from, 'p_accept': accept});
      buzz(accept ? Buzz.success : Buzz.light);
      if (accept) {
        sfx(Sfx.ready);
        widget.toast('حالا با هم دوستید 🤝', 'ok');
      }
      NotifFeed.I.refreshRequests();
      await load();
    } catch (e) {
      widget.toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = NavScope.of(context);
    return RefreshIndicator(
      onRefresh: load,
      color: C.cyan,
      child: ListView(padding: EdgeInsets.only(bottom: widget.bottom + S.l), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.s),
          child: Segment(
            value: mode, accent: C.green,
            onChange: (v) {
              mode = v;
              load();
            },
            items: [('friends', 'دوستان'), ('requests', NotifFeed.I.pendingRequests > 0 ? 'درخواست‌ها (${fa(NotifFeed.I.pendingRequests)})' : 'درخواست‌ها'), ('following', 'دنبال‌شده'), ('followers', 'دنبال‌کننده')],
          ),
        ),
        if (rows == null)
          const Padding(padding: EdgeInsets.all(S.xl), child: Center(child: Spinner()))
        else if (rows!.isEmpty)
          Empty(
            img: UI2['x_player'],
            title: switch (mode) {
              'friends' => 'هنوز دوستی نداری',
              'requests' => 'درخواست دوستی تازه‌ای نداری',
              'following' => 'هنوز کسی را دنبال نمی‌کنی',
              _ => 'هنوز دنبال‌کننده‌ای نداری',
            },
            sub: 'از رده‌بندی یا جستجو بازیکن‌ها را پیدا کن',
          )
        else
          for (final (i, it) in rows!.indexed)
            Enter(
              i: i,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.l),
                child: Press(
                  onPress: () => nav.openProfile(rs(it, 'id')),
                  scaleTo: .98,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 60), margin: const EdgeInsets.only(bottom: S.s), padding: const EdgeInsets.symmetric(horizontal: S.s, vertical: 6),
                    decoration: rowDeco(mode == 'requests' ? C.green.withValues(alpha: .5) : null),
                    child: rrow([
                      Stack(children: [
                        AvatarO(avatar: it['avatar'] as String?, url: it['avatar_url'] as String?, size: 44, ring: isOnline(it['online_at']) ? C.green : C.line),
                        if (isOnline(it['online_at'])) Positioned(bottom: 0, left: 0, child: onlineDot(12)),
                      ]),
                      const SizedBox(width: S.s),
                      Expanded(
                        child: rcol([
                          T(rs(it, 'username'), n: 1, style: fs(F.bold, 14)),
                          T(isOnline(it['online_at']) ? 'آنلاین' : 'آخرین بازدید ${timeAgo(it['online_at'])} پیش', style: fs(F.body, TS.cap, color: isOnline(it['online_at']) ? C.green : C.dim)),
                        ]),
                      ),
                      if (mode == 'requests') ...[
                        busy == it['id']
                            ? const Spinner()
                            : rrow([
                                _round('✓', C.green, () => respond(rs(it, 'id'), true)),
                                const SizedBox(width: S.xs),
                                _round('✕', C.red, () => respond(rs(it, 'id'), false)),
                              ]),
                      ] else
                        Badge2(label: 'سطح ${fa(ri(it, 'level', 1))}', color: C.gold),
                    ]),
                  ),
                ),
              ),
            ),
      ]),
    );
  }

  Widget _round(String s, Color c, VoidCallback f) => Press(
        onPress: f,
        child: Container(
          width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.withValues(alpha: .6)), color: c.withValues(alpha: .12)),
          child: T(s, style: fs(F.bold, 18, color: c)),
        ),
      );
}
