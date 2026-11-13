// Conversation screen — port of src/social/Chat.tsx (DM / group / channel / club): realtime messages with paging,
// images, reply, delete own, typing indicator over broadcast, read receipts (last_read_at), info sheet for groups
// (add / remove / promote / demote members, leave), mute, and a "invite to my room" shortcut for DMs.
import 'dart:async';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../game/assets.dart';
import '../i18n/i18n.dart';
import '../nav.dart';
import '../net/auth.dart';
import '../net/media.dart';
import '../net/supabase.dart';
import '../online/challenges.dart' show Toast;
import '../online/ui.dart';
import '../oracle/oracle_bus.dart';
import '../sound.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'notifications.dart';
import 'social_feed.dart';

const _PAGE = 40;

class ChatScreen extends StatefulWidget {
  final String id;
  final VoidCallback onBack;
  final Toast toast;
  const ChatScreen({super.key, required this.id, required this.onBack, required this.toast});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  JRow? conv;
  List<JRow> members = [];
  List<JRow>? msgs;
  bool more = true, sending = false, loadingMore = false;
  JRow? reply;
  final Map<String, int> typing = {};
  final txt = TextEditingController();
  RealtimeChannel? ch;
  Timer? tick;
  int lastTyping = 0;
  String? get uid => Auth.I.uid;

  Map<String, JRow> get byId => {for (final m in members) rs(m, 'user_id'): m};
  JRow? get me => uid == null ? null : byId[uid];
  JRow? get peer => conv?['kind'] == 'dm' ? members.where((m) => m['user_id'] != uid).firstOrNull : null;
  bool get canPost => me != null && (conv?['kind'] != 'channel' || me?['role'] == 'owner' || me?['role'] == 'admin');
  String nameOf(String? u) => u == null ? '' : ((byId[u]?['profiles'] as Map?)?['username'] as String? ?? '…');

  @override
  void initState() {
    super.initState();
    OracleBus.I.setQuiet('chat', true);
    NotifFeed.I.openConversation = widget.id;
    loadMeta();
    loadMsgs();
    markRead();
    final f = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: widget.id);
    ch = supabase
        .channel('conv:${widget.id}', opts: const RealtimeChannelConfig(self: false))
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'messages', filter: f, callback: (p) {
          final m = p.newRecord;
          if (!mounted) return;
          setState(() {
            if (!(msgs ?? []).any((x) => x['id'] == m['id'])) msgs = [m, ...?msgs];
            if (m['sender'] != null) typing.remove(m['sender']);
          });
          if (m['sender'] != uid) {
            sfx(Sfx.chat);
            markRead();
          }
        })
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'messages', filter: f, callback: (p) {
          final m = p.newRecord;
          if (mounted) setState(() => msgs = msgs?.map((x) => x['id'] == m['id'] ? m : x).toList());
        })
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'conversation_members', filter: f, callback: (_) => loadMeta())
        .onBroadcast(event: 'typing', callback: (p) {
          final pl = p['payload'] is Map ? p['payload'] as Map : p;
          final u = pl['u'] as String?;
          if (u != null && u != uid && mounted) setState(() => typing[u] = DateTime.now().millisecondsSinceEpoch);
        })
        .subscribe();
    tick = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (typing.values.any((t) => now - t >= 4000) && mounted) setState(() => typing.removeWhere((_, t) => now - t >= 4000));
    });
  }

  @override
  void dispose() {
    OracleBus.I.setQuiet('chat', false);
    if (NotifFeed.I.openConversation == widget.id) NotifFeed.I.openConversation = null;
    tick?.cancel();
    if (ch != null) supabase.removeChannel(ch!);
    markRead();
    txt.dispose();
    super.dispose();
  }

  void markRead() {
    final u = uid;
    if (u == null) return;
    supabase.from('conversation_members').update({'last_read_at': DateTime.now().toUtc().toIso8601String()}).eq('conversation_id', widget.id).eq('user_id', u).then((_) {}, onError: (_) {});
  }

  Future<void> loadMeta() async {
    try {
      final r = await Future.wait<dynamic>([
        supabase.from('conversations').select().eq('id', widget.id).maybeSingle(),
        supabase.from('conversation_members').select('user_id, role, muted, profiles(username, avatar, avatar_url, online_at)').eq('conversation_id', widget.id).limit(500),
      ]);
      if (!mounted) return;
      setState(() {
        if (r[0] != null) conv = r[0] as JRow;
        members = List<JRow>.from(r[1] as List);
      });
    } catch (_) {}
  }

  Future<void> loadMsgs([String? before]) async {
    if (before != null) {
      if (loadingMore) return;
      loadingMore = true;
    }
    try {
      var q = supabase.from('messages').select().eq('conversation_id', widget.id);
      if (before != null) q = q.lt('created_at', before);
      final rows = List<JRow>.from(await q.order('created_at', ascending: false).limit(_PAGE));
      if (!mounted) return;
      setState(() {
        more = rows.length == _PAGE;
        msgs = before != null ? [...?msgs, ...rows] : rows;
      });
    } catch (e) {
      widget.toast(errFa(e), 'err');
      if (before == null && mounted) setState(() => msgs = []);
    } finally {
      loadingMore = false;
    }
  }

  void onType(String v) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (v.isNotEmpty && now - lastTyping > 2500) {
      lastTyping = now;
      ch?.sendBroadcastMessage(event: 'typing', payload: {'u': uid}).catchError((_) => ChannelResponse.error);
    }
    setState(() {});
  }

  Future<void> send([String? imageUrl]) async {
    final body = txt.text.trim(), u = uid;
    if (u == null || (body.isEmpty && imageUrl == null) || sending) return;
    setState(() => sending = true);
    try {
      final d = await supabase.from('messages').insert({
        'conversation_id': widget.id, 'sender': u, 'body': body.isEmpty ? null : (body.length > 2000 ? body.substring(0, 2000) : body),
        'image_url': imageUrl, 'reply_to': reply?['id'],
      }).select().single();
      txt.clear();
      buzz();
      if (mounted) {
        setState(() {
          reply = null;
          if (!(msgs ?? []).any((x) => x['id'] == d['id'])) msgs = [d, ...?msgs];
        });
      }
    } catch (e) {
      widget.toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> sendImage() async {
    final u = uid;
    if (u == null) return;
    setState(() => sending = true);
    final r = await pickAndUpload('chat', u, size: 1280);
    if (mounted) setState(() => sending = false);
    if (!r.ok) {
      if (!r.cancelled) widget.toast(r.error ?? '', 'err');
      return;
    }
    send(r.url);
  }

  Future<void> del(JRow m) async {
    try {
      await supabase.from('messages').update({'deleted': true, 'body': null}).eq('id', m['id']);
    } catch (e) {
      widget.toast(errFa(e), 'err');
    }
  }

  void menu(JRow m) {
    if (m['deleted'] == true) return;
    buzz(Buzz.medium);
    final nav = NavScope.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        margin: const EdgeInsets.all(S.l),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: hex('#0e1640'), border: Border.all(color: C.line)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (canPost) _mi('پاسخ', () => setState(() => reply = m), c),
            if (m['body'] != null) _mi('کپی متن', () => Clipboard.setData(ClipboardData(text: '${m['body']}')), c),
            if (m['sender'] != null && m['sender'] != uid) _mi('مشاهده‌ی پروفایل', () => nav.openProfile(rs(m, 'sender')), c),
            if (m['sender'] == uid) _mi('حذف پیام', () => del(m), c, C.red),
            _mi('انصراف', () {}, c, C.dim),
          ]),
        ),
      ),
    );
  }

  Widget _mi(String l, VoidCallback f, BuildContext c, [Color? color]) => Press(
        onPress: () {
          Navigator.of(c).pop();
          f();
        },
        child: Container(height: 52, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: S.l), child: T(l, style: fs(F.bold, TS.body, color: color ?? C.text))),
      );

  void viewImage(String url) => showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'img',
        barrierColor: rgba(1, 3, 12, .92),
        pageBuilder: (c, _, _) => GestureDetector(onTap: () => Navigator.of(c).pop(), child: Center(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)))),
      );

  void info() => showNxSheet(context, title: rs(conv, 'title', KIND_LABEL[conv?['kind']] ?? ''), en: '${KIND_LABEL[conv?['kind']] ?? ''} INFO', height: .85, builder: (c) => _ConvInfo(
        conv: conv!, members: members, myRole: me?['role'] as String?, muted: me?['muted'] == true, toast: widget.toast, onChanged: loadMeta,
        onLeft: () {
          Navigator.of(c).pop();
          widget.onBack();
        },
      ));

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context), kb = MediaQuery.viewInsetsOf(context).bottom, nav = NavScope.of(context);
    final c = conv, p = peer, pp = p?['profiles'] as Map?;
    final title = c?['kind'] == 'dm' ? (pp?['username'] as String? ?? 'گفتگو') : rs(c, 'title', 'گفتگو');
    final typers = typing.keys.map(nameOf).where((x) => x.isNotEmpty).toList();
    final byMsg = {for (final m in msgs ?? <JRow>[]) m['id']: m};
    return Material(
      color: C.bg,
      child: Stack(children: [
        Padding(
          padding: EdgeInsets.only(bottom: kb),
          child: Column(children: [
            Expanded(
              child: msgs == null
                  ? const Center(child: Spinner())
                  : msgs!.isEmpty
                      ? Padding(padding: EdgeInsets.only(top: ins.top + 76), child: Empty(img: UI2['c_mega'], title: 'اولین پیام را بفرست!'))
                      : NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (more && n.metrics.extentAfter < 400 && msgs!.isNotEmpty) loadMsgs(rs(msgs!.last, 'created_at'));
                            return false;
                          },
                          child: ListView.builder(
                            reverse: true,
                            padding: EdgeInsets.only(top: ins.top + 76, bottom: S.s),
                            itemCount: msgs!.length,
                            itemBuilder: (_, i) {
                              final m = msgs![i], prev = i + 1 < msgs!.length ? msgs![i + 1] : null;
                              final mine = m['sender'] == uid;
                              return _Bubble(
                                key: ValueKey(m['id']),
                                m: m, mine: mine,
                                showName: c?['kind'] != 'dm' && !mine && prev?['sender'] != m['sender'],
                                name: nameOf(m['sender'] as String?),
                                replyTo: m['reply_to'] != null ? byMsg[m['reply_to']] : null,
                                replyName: nameOf,
                                onLong: () => menu(m),
                                onImage: viewImage,
                                fresh: i == 0,
                              );
                            },
                          ),
                        ),
            ),
            AnimatedSize(
              duration: 200.ms,
              child: typers.isNotEmpty
                  ? Padding(padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, 2), child: Align(alignment: Alignment.centerRight, child: T('${typers.join('، ')} در حال نوشتن…', n: 1, style: fs(F.body, TS.cap, color: C.cyan))))
                  : const SizedBox(width: double.infinity),
            ),
            if (reply != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: S.m),
                decoration: BoxDecoration(color: rgba(10, 16, 44, .95), border: Border(top: BorderSide(color: C.line))),
                child: Row(children: [
                  Press(onPress: () => setState(() => reply = null), child: SizedBox(width: 44, height: 44, child: Center(child: T('✕', style: fs(F.body, 14, color: C.dim))))),
                  Expanded(
                    child: rcol([
                      T('پاسخ به ${nameOf(reply!['sender'] as String?)}', style: fs(F.body, TS.tiny, color: C.cyan)),
                      T(reply!['body'] as String? ?? '📷 عکس', n: 1, style: fs(F.body, TS.small)),
                    ]),
                  ),
                ]),
              ).animate().slideY(begin: 1, duration: 200.ms, curve: Curves.easeOut),
            if (canPost)
              Container(
                padding: EdgeInsets.fromLTRB(S.s, S.s, S.s, kb > 0 ? S.s : (ins.bottom < S.s ? S.s : ins.bottom)),
                decoration: BoxDecoration(color: rgba(4, 8, 24, .96), border: Border(top: BorderSide(color: C.line))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Press(
                    onPress: () => send(),
                    disabled: txt.text.trim().isEmpty || sending,
                    child: Container(
                      width: 44, height: 44, alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: rgba(79, 227, 255, .18), border: Border.all(color: C.cyan)),
                      child: sending ? const Spinner() : Img(UI2['c_mega'], w: 24, h: 24),
                    ),
                  ),
                  const SizedBox(width: S.s),
                  Expanded(
                    child: TextField(
                      controller: txt,
                      onChanged: onType,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: fs(F.fa, 14),
                      cursorColor: C.cyan,
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        hintText: tr('پیام…'),
                        hintStyle: fs(F.fa, 14, color: C.dim2),
                        filled: true,
                        fillColor: rgba(6, 10, 30, .85),
                        contentPadding: const EdgeInsets.symmetric(horizontal: S.l, vertical: 12),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: C.line)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: C.cyan)),
                      ),
                    ),
                  ),
                  const SizedBox(width: S.s),
                  Press(
                    onPress: sendImage,
                    disabled: sending,
                    child: Container(
                      width: 44, height: 44, alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.line)),
                      child: T('🖼', style: fs(F.body, 20)),
                    ),
                  ),
                ]),
              )
            else if (c != null && me == null && c['is_public'] == true)
              Padding(
                padding: EdgeInsets.fromLTRB(S.m, S.m, S.m, ins.bottom < S.m ? S.m : ins.bottom),
                child: Btn(label: 'پیوستن', colors: G.green, onPress: () async {
                  try {
                    await rpc('join_conversation', {'p_conv': widget.id});
                    sfx(Sfx.join);
                    loadMeta();
                  } catch (e) {
                    widget.toast(errFa(e), 'err');
                  }
                }),
              )
            else if (c != null)
              Padding(
                padding: EdgeInsets.fromLTRB(S.m, S.m, S.m, ins.bottom < S.m ? S.m : ins.bottom),
                child: T(c['kind'] == 'channel' ? 'فقط مدیران کانال می‌توانند پیام بفرستند' : 'امکان ارسال پیام نیست', align: TextAlign.center, style: fs(F.body, TS.small, color: C.dim)),
              ),
          ]),
        ),
        Header(
          title: title,
          en: c == null ? '' : c['kind'] == 'dm' ? (isOnline(pp?['online_at']) ? 'ONLINE' : 'DIRECT') : '${KIND_LABEL[c['kind']] ?? ''} · ${fa(members.length)} عضو',
          onBack: widget.onBack,
          right: c?['kind'] == 'dm' && p != null
              ? Press(onPress: () => nav.openProfile(rs(p, 'user_id')), child: AvatarO(avatar: pp?['avatar'] as String?, url: pp?['avatar_url'] as String?, size: 40, ring: isOnline(pp?['online_at']) ? C.green : C.line))
              : c != null
                  ? Press(
                      onPress: info,
                      child: Container(
                        width: 44, height: 44, alignment: Alignment.center,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: rgba(8, 14, 40, .85), border: Border.all(color: C.line)),
                        child: T('ⓘ', style: fs(F.body, 20, color: C.cyan)),
                      ),
                    )
                  : null,
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final JRow m;
  final bool mine, showName, fresh;
  final String name;
  final JRow? replyTo;
  final String Function(String?) replyName;
  final VoidCallback onLong;
  final void Function(String url) onImage;
  const _Bubble({super.key, required this.m, required this.mine, required this.showName, required this.name, this.replyTo, required this.replyName, required this.onLong, required this.onImage, this.fresh = false});
  @override
  Widget build(BuildContext context) {
    final deleted = m['deleted'] == true, img = m['image_url'] as String?, body = m['body'] as String?;
    final r = const Radius.circular(16), s = const Radius.circular(4);
    Widget b = Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.m, vertical: 2),
        child: GestureDetector(
          onLongPress: onLong,
          onTap: img != null && !deleted ? () => onImage(img) : null,
          child: Opacity(
            opacity: deleted ? .5 : 1,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 290),
              padding: const EdgeInsets.symmetric(horizontal: S.m, vertical: 6),
              decoration: BoxDecoration(
                color: mine ? rgba(79, 227, 255, .16) : rgba(20, 30, 70, .92),
                border: Border.all(color: mine ? rgba(79, 227, 255, .35) : C.line),
                borderRadius: BorderRadius.only(topLeft: r, topRight: r, bottomLeft: mine ? s : r, bottomRight: mine ? r : s),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                if (showName) T(name, n: 1, style: fs(F.bold, TS.tiny, color: C.cyan)),
                if (replyTo != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                    decoration: BoxDecoration(color: rgba(0, 0, 0, .2), borderRadius: BorderRadius.circular(6), border: Border(right: BorderSide(color: C.cyan, width: 3))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      T(replyName(replyTo!['sender'] as String?), style: fs(F.body, 10, color: C.cyan)),
                      T(replyTo!['deleted'] == true ? 'پیام حذف شده' : replyTo!['body'] as String? ?? '📷 عکس', n: 1, style: fs(F.body, TS.cap, color: C.dim)),
                    ]),
                  ),
                if (deleted)
                  T('🚫 این پیام حذف شد', style: fs(F.body, TS.small, color: C.dim))
                else ...[
                  if (img != null) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Img(img, w: 220, h: 220, fit: BoxFit.cover, radius: 12)),
                  if (body != null) T(body, align: TextAlign.right, style: fs(F.body, 14, height: 1.55)),
                ],
                const SizedBox(height: 2),
                T(timeAgo(m['created_at']), style: fs(F.body, 9, color: C.dim2)),
              ]),
            ),
          ),
        ),
      ),
    );
    if (fresh) b = b.animate().fadeIn(duration: 180.ms).slideY(begin: .25, duration: 220.ms, curve: Curves.easeOut);
    return b;
  }
}

class _ConvInfo extends StatefulWidget {
  final JRow conv;
  final List<JRow> members;
  final String? myRole;
  final bool muted;
  final Toast toast;
  final VoidCallback onChanged, onLeft;
  const _ConvInfo({required this.conv, required this.members, required this.myRole, required this.muted, required this.toast, required this.onChanged, required this.onLeft});
  @override
  State<_ConvInfo> createState() => _ConvInfoState();
}

class _ConvInfoState extends State<_ConvInfo> {
  List<JRow> found = [];
  late List<JRow> members = widget.members;
  late bool muted = widget.muted;
  Timer? _t;
  bool get admin => widget.myRole == 'owner' || widget.myRole == 'admin';
  String get kind => rs(widget.conv, 'kind');

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void search(String q) {
    _t?.cancel();
    final term = q.trim().replaceAll(RegExp(r'[%_]'), '');
    if (term.length < 2) return setState(() => found = []);
    _t = Timer(const Duration(milliseconds: 300), () async {
      final d = await supabase.from('profiles').select('id, username, avatar, avatar_url').ilike('username', '%$term%').limit(10);
      if (mounted) setState(() => found = List<JRow>.from(d));
    });
  }

  Future<void> act(String u, String a) async {
    try {
      await rpc('manage_member', {'p_conv': widget.conv['id'], 'p_user': u, 'p_action': a});
      buzz();
      widget.onChanged();
      final d = await supabase.from('conversation_members').select('user_id, role, muted, profiles(username, avatar, avatar_url, online_at)').eq('conversation_id', widget.conv['id']).limit(500);
      if (mounted) setState(() => members = List<JRow>.from(d));
    } catch (e) {
      widget.toast(errFa(e), 'err');
    }
  }

  Future<void> leave() async {
    try {
      await rpc('leave_conversation', {'p_conv': widget.conv['id']});
      widget.toast('خارج شدی', 'ok');
      widget.onLeft();
    } catch (e) {
      widget.toast(errFa(e), 'err');
    }
  }

  Future<void> toggleMute(bool v) async {
    setState(() => muted = v);
    try {
      await supabase.from('conversation_members').update({'muted': v}).eq('conversation_id', widget.conv['id']).eq('user_id', Auth.I.uid!);
    } catch (e) {
      setState(() => muted = !v);
      widget.toast(errFa(e), 'err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = Auth.I.uid, nav = NavScope.of(context);
    Widget small(String l, Color c, VoidCallback f) => Press(onPress: f, child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: S.s), alignment: Alignment.center, child: T(l, style: fs(F.body, TS.cap, color: c))));
    return ListView(padding: const EdgeInsets.fromLTRB(S.l, S.l, S.l, S.xl * 2), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
      if (widget.conv['about'] != null) Padding(padding: const EdgeInsets.only(bottom: S.m), child: T('${widget.conv['about']}', align: TextAlign.right, style: fs(F.body, 14, color: C.dim))),
      SizedBox(height: 56, child: rrow([Expanded(child: rcol([T('بی‌صدا', style: fs(F.bold, 14)), T('برای این گفتگو اعلان نفرست', style: fs(F.body, TS.cap, color: C.dim))])), Toggle(on: muted, onChange: toggleMute)])),
      if (admin && kind != 'club') ...[
        OField(label: 'افزودن عضو', placeholder: 'نام کاربری…', onChanged: search),
        for (final f in found.where((f) => !members.any((m) => m['user_id'] == f['id'])))
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x14FFFFFF), width: .5))),
            child: rrow([
              AvatarO(avatar: f['avatar'] as String?, url: f['avatar_url'] as String?, size: 36),
              const SizedBox(width: S.s),
              Expanded(child: T(rs(f, 'username'), n: 1, align: TextAlign.right)),
              small('افزودن', C.green, () {
                act(rs(f, 'id'), 'add');
                setState(() => found = []);
              }),
            ]),
          ),
      ],
      Padding(padding: const EdgeInsets.symmetric(vertical: S.s), child: T('اعضا (${fa(members.length)})', align: TextAlign.right, style: fs(F.bold, TS.h))),
      for (final m in members)
        () {
          final p = m['profiles'] as Map?, u = rs(m, 'user_id'), role = rs(m, 'role', 'member');
          return Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x14FFFFFF), width: .5))),
            child: rrow([
              Press(onPress: () => nav.openProfile(u), child: AvatarO(avatar: p?['avatar'] as String?, url: p?['avatar_url'] as String?, size: 40, ring: isOnline(p?['online_at']) ? C.green : C.line)),
              const SizedBox(width: S.s),
              Expanded(
                child: rcol([
                  T('${p?['username'] ?? '…'}${u == uid ? ' (تو)' : ''}', n: 1, style: fs(F.bold, 14)),
                  if (role != 'member') Badge2(label: role == 'owner' ? 'مالک' : 'مدیر', color: role == 'owner' ? C.gold : C.cyan),
                ]),
              ),
              if (widget.myRole == 'owner' && u != uid && kind != 'club') small(role == 'admin' ? 'برکناری' : 'مدیر کن', C.cyan, () => act(u, role == 'admin' ? 'demote' : 'promote')),
              if (admin && u != uid && role != 'owner' && kind != 'club') small('حذف', C.red, () => act(u, 'remove')),
            ]),
          );
        }(),
      if (kind != 'club' && kind != 'dm') ...[const SizedBox(height: S.l), Btn(label: 'خروج از گفتگو', small: true, colors: G.red, onPress: leave)],
    ]);
  }
}
