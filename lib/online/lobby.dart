// Room lobby — port of src/online/Lobby.tsx: seats per team, spectators, ready / start, host settings + kick, chat, voice,
// share code, quick/arena auto-start countdown.
import 'dart:async';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../game/assets.dart';
import '../game/data.dart';
import '../nav.dart';
import '../net/discs.dart';
import '../net/supabase.dart';
import '../net/voice.dart';
import '../sound.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'challenges.dart' show Toast;
import 'hub.dart';
import 'link.dart';
import 'online_match.dart' show ruleLabel;
import 'room_widgets.dart';
import 'ui.dart';

class Lobby extends StatelessWidget {
  final RoomLink link;
  final VoidCallback onLeave, onWatch;
  final Toast toast;
  const Lobby({super.key, required this.link, required this.onLeave, required this.onWatch, required this.toast});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LinkState>(
        valueListenable: link,
        builder: (_, st, _) => st.room == null ? const Center(child: Spinner(size: 36)) : _LobbyBody(link: link, st: st, onLeave: onLeave, onWatch: onWatch, toast: toast),
      );
}

class _LobbyBody extends StatefulWidget {
  final RoomLink link;
  final LinkState st;
  final VoidCallback onLeave, onWatch;
  final Toast toast;
  const _LobbyBody({required this.link, required this.st, required this.onLeave, required this.onWatch, required this.toast});
  @override
  State<_LobbyBody> createState() => _LobbyBodyState();
}

class _LobbyBodyState extends State<_LobbyBody> {
  String? busy;
  int count = 0;
  Timer? _cd;
  bool _auto = false;

  RoomLink get link => widget.link;
  LinkState get st => widget.st;
  JRow get room => st.room!;
  String get me => link.me;
  int get n => teamSize(rs(room, 'mode', '1v1'));

  List<List<JRow?>> get seats {
    final t = [List<JRow?>.filled(n, null), List<JRow?>.filled(n, null)];
    for (final p in st.players) {
      final team = p['team'], slot = p['slot'];
      if (p['role'] == 'player' && (team == 0 || team == 1) && slot is num && slot < n) t[team as int][slot.toInt()] = p;
    }
    return t;
  }

  bool get full => seats[0].every((x) => x != null) && seats[1].every((x) => x != null);
  List<JRow> get notReady => st.players.where((p) => p['role'] == 'player' && p['ready'] != true && p['user_id'] != room['host']).toList();
  bool get isHost => room['host'] == me;
  bool get autoKind => room['kind'] == 'quick' || room['kind'] == 'arena';

  @override
  void didUpdateWidget(covariant _LobbyBody old) {
    super.didUpdateWidget(old);
    _checkAuto();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuto());
  }

  @override
  void dispose() {
    _cd?.cancel();
    super.dispose();
  }

  // quick / arena rooms: as soon as every seat is filled (players auto-ready) the host starts after 3-2-1
  void _checkAuto() {
    final a = autoKind && room['status'] == 'waiting' && full && notReady.isEmpty;
    if (a == _auto) return;
    _auto = a;
    _cd?.cancel();
    if (!a) {
      if (mounted) setState(() => count = 0);
      return;
    }
    setState(() => count = 3);
    sfx(Sfx.tick);
    buzz();
    _cd = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (count > 1) {
        setState(() => count--);
        sfx(Sfx.tick);
        buzz();
        return;
      }
      t.cancel();
      setState(() => count = 0);
      if (isHost) start();
    });
  }

  Future<void> run(String key, Future<void> Function() fn, [String? ok]) async {
    if (busy != null) return;
    setState(() => busy = key);
    try {
      await fn();
      link.ping();
      await link.refresh();
      if (ok != null) widget.toast(ok, 'ok');
    } catch (e) {
      widget.toast(errFa(e), 'err');
      buzz(Buzz.heavy);
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  void sit(int team, int slot) => run('seat$team$slot', () => rpc('take_seat', {'p_room': room['id'], 'p_team': team, 'p_slot': slot}));
  JRow? get meP => st.players.where((p) => p['user_id'] == me).firstOrNull;
  void ready() => run('ready', () async {
        await rpc('set_ready', {'p_room': room['id'], 'p_ready': meP?['ready'] != true});
        sfx(Sfx.ready);
        buzz(Buzz.medium);
      });
  void start() => run('start', () async {
        await rpc('start_match', {'p_room': room['id']});
        buzz(Buzz.heavy);
      });
  void kick(String uid) => run('kick$uid', () => rpc('kick', {'p_room': room['id'], 'p_user': uid}), 'بازیکن اخراج شد');
  void watch() => run('spec', () => rpc('spectate', {'p_room': room['id']}));
  Future<void> copy() async {
    await copyText(rs(room, 'code'));
    widget.toast('کد اتاق کپی شد', 'ok');
    buzz();
  }

  void share() => SharePlus.instance.share(ShareParams(text: 'بیا NEXORA بازی کنیم! 🚀\nکد اتاق: ${rs(room, 'code')}')).catchError((_) => ShareResult.unavailable);

  void openChat() => showNxSheet(context, title: 'گفتگو', en: 'ROOM CHAT', height: .72, builder: (_) => ChatPanel(link: link, height: double.infinity));
  void openSettings() => showNxSheet(context, title: 'تنظیمات اتاق', en: 'ROOM SETTINGS', height: .8, builder: (c) => _RoomSettings(link: link, toast: widget.toast, onDone: () => Navigator.of(c).pop()));

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    final playing = room['status'] == 'playing', sts = seats, specs = st.players.where((p) => p['role'] == 'spectator').toList();
    final amPlayer = meP?['role'] == 'player', canStart = isHost && full && notReady.isEmpty && room['status'] == 'waiting';
    final reason = !full ? 'منتظر پر شدن جایگاه‌ها…' : notReady.isNotEmpty ? 'منتظر آماده شدن ${fa(notReady.length)} بازیکن…' : '';
    final settings = room['settings'] as Map?;
    final fi = (settings?['field'] as num?)?.toInt() ?? 0;
    final nav = NavScope.of(context);
    return ValueListenableBuilder<VoiceState>(
      valueListenable: link.voice,
      builder: (_, v, _) {
        final speaking = v.speaking.toSet();
        return Stack(children: [
          ListView(
            padding: EdgeInsets.fromLTRB(S.l, ins.top + 76, S.l, 140 + ins.bottom),
            children: [
              Panel(
                accent: C.cyan,
                pad: const EdgeInsets.all(S.m),
                child: Column(children: [
                  rrow([
                    Expanded(child: rcol([T('کد اتاق', style: fs(F.body, TS.cap, color: C.dim)), T(rs(room, 'code'), style: fs(F.title, 24, ls: 4, color: C.cyan))])),
                    _codeBtn('کپی', copy),
                    const SizedBox(width: S.s),
                    _codeBtn('اشتراک', share),
                  ]),
                  const SizedBox(height: S.s),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(textDirection: TextDirection.rtl, runSpacing: S.xs, children: [
                      Badge2(label: ruleLabel(settings), color: C.violet),
                      Badge2(label: fi < FIELDS.length ? FIELDS[fi].name : 'Field', color: C.sky),
                      Badge2(label: room['ranked'] == true ? 'رتبه‌ای' : 'دوستانه', color: room['ranked'] == true ? C.gold : C.green),
                      if (room['is_private'] == true) Badge2(label: 'خصوصی', color: C.pink),
                      if (room['tournament_match_id'] != null) Badge2(label: 'تورنمنت', color: C.orange),
                      if (playing) Badge2(label: 'در حال بازی', color: C.red, live: true),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: S.m),
              rrow(cross: CrossAxisAlignment.start, [
                for (final t in [0, 1]) ...[
                  Expanded(
                    child: Column(children: [
                      Container(
                        height: 36, margin: const EdgeInsets.only(bottom: S.s), alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: (t == 0 ? C.cyan : C.red).withValues(alpha: .4)),
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [(t == 0 ? C.cyan : C.red).withValues(alpha: .19), Colors.transparent]),
                        ),
                        child: T(t == 0 ? 'تیم آبی' : 'تیم قرمز', style: fs(F.bold, TS.body, color: t == 0 ? C.cyan : C.red)),
                      ),
                      for (var i = 0; i < n; i++)
                        AnimatedSwitcher(
                          duration: 250.ms,
                          transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: FadeTransition(opacity: a, child: c)),
                          child: sts[t][i] != null
                              ? _Seat(
                                  key: ValueKey(sts[t][i]!['user_id']), p: sts[t][i]!, me: me, host: rs(room, 'host'), online: st.online.containsKey(sts[t][i]!['user_id']),
                                  talking: speaking.contains(sts[t][i]!['user_id']), color: t == 0 ? C.cyan : C.red,
                                  canKick: isHost && sts[t][i]!['user_id'] != me && !playing, busy: busy == 'kick${sts[t][i]!['user_id']}', onKick: () => kick(rs(sts[t][i], 'user_id')),
                                )
                              : Press(
                                  key: ValueKey('e$t$i'),
                                  onPress: () => sit(t, i),
                                  disabled: playing || busy != null,
                                  child: Container(
                                    height: 68, margin: const EdgeInsets.only(bottom: S.s), alignment: Alignment.center,
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.dim2), color: rgba(6, 10, 30, .4)),
                                    child: busy == 'seat$t$i'
                                        ? const Spinner()
                                        : rrow(main: MainAxisAlignment.center, [T('+', style: fs(F.title, 18, color: C.dim)), const SizedBox(width: S.xs), T('نشستن', style: fs(F.body, TS.cap, color: C.dim))]),
                                  ),
                                ),
                        ),
                    ]),
                  ),
                  if (t == 0) const SizedBox(width: S.s),
                ],
              ]),
              const SizedBox(height: S.m),
              Panel(
                noAccent: true,
                pad: const EdgeInsets.all(S.m),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  rrow(main: MainAxisAlignment.spaceBetween, [
                    T('تماشاگرها (${fa(specs.length)})', style: fs(F.bold, TS.small)),
                    if (amPlayer && !playing)
                      Press(
                        onPress: watch,
                        child: Container(
                          height: 36, padding: const EdgeInsets.symmetric(horizontal: S.m), alignment: Alignment.center,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.sky.withValues(alpha: .4))),
                          child: T('فقط تماشا', style: fs(F.body, TS.cap, color: C.sky)),
                        ),
                      ),
                  ]),
                  if (specs.isNotEmpty)
                    SizedBox(
                      height: 70,
                      child: ListView(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.only(top: S.s), children: [
                        for (final p in specs)
                          SizedBox(
                            width: 64,
                            child: Column(children: [
                              Press(
                                onPress: () => nav.openProfile(rs(p, 'user_id')),
                                child: AvatarO(avatar: _disc(p), url: (p['profiles'] as Map?)?['avatar_url'] as String?, size: 40, ring: speaking.contains(p['user_id']) ? C.green : C.dim2, dim: !st.online.containsKey(p['user_id'])),
                              ),
                              T((p['profiles'] as Map?)?['username'] as String? ?? '…', n: 1, style: fs(F.body, TS.tiny, color: C.dim)),
                            ]),
                          ),
                      ]),
                    )
                  else
                    Padding(padding: const EdgeInsets.only(top: S.xs), child: T('کسی تماشا نمی‌کند', style: fs(F.body, TS.cap, color: C.dim2))),
                ]),
              ),
              const SizedBox(height: S.m),
              Panel(
                noAccent: true,
                pad: const EdgeInsets.all(S.m),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  T('چت صوتی', style: fs(F.bold, TS.small)),
                  const SizedBox(height: S.s),
                  room['voice'] == true ? VoiceBar(link: link) : T('چت صوتی برای این اتاق خاموش است', style: fs(F.body, TS.cap, color: C.dim2)),
                ]),
              ),
              const SizedBox(height: S.m),
              Press(
                onPress: openChat,
                scaleTo: .98,
                child: Panel(
                  noAccent: true,
                  pad: const EdgeInsets.all(S.m),
                  child: rrow([
                    Img(UI2['c_bell'], w: 32, h: 32),
                    const SizedBox(width: S.s),
                    Expanded(
                      child: rcol([
                        T('گفتگوی اتاق', style: fs(F.bold, TS.small)),
                        T(st.chat.isNotEmpty ? '${st.chat.last.name}: ${st.chat.last.text}' : 'برای نوشتن پیام لمس کن', n: 1, style: fs(F.body, TS.cap, color: C.dim)),
                      ]),
                    ),
                    if (st.unread > 0)
                      Container(
                        constraints: const BoxConstraints(minWidth: 22), height: 22, padding: const EdgeInsets.symmetric(horizontal: 4), alignment: Alignment.center,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), color: C.red),
                        child: T(fa(st.unread > 99 ? 99 : st.unread), style: fs(F.bold, 10, color: Colors.white)),
                      ).animate(key: ValueKey(st.unread)).scaleXY(begin: .5, curve: Curves.elasticOut, duration: 500.ms),
                  ]),
                ),
              ),
              if (isHost && !playing && room['tournament_match_id'] == null) ...[
                const SizedBox(height: S.m),
                Btn(label: 'تنظیمات اتاق', small: true, colors: G.dark, onPress: openSettings),
              ],
            ],
          ),
          Header(
            title: rs(room, 'name'),
            en: 'LOBBY · ${rs(room, 'mode').toUpperCase()}',
            onBack: widget.onLeave,
            right: Row(mainAxisSize: MainAxisSize.min, children: [
              Press(
                onPress: share,
                child: Container(
                  width: 44, height: 44, alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: rgba(8, 14, 40, .85), border: Border.all(color: C.line)),
                  child: Img(UI2['c_mega'], w: 24, h: 24),
                ),
              ),
              const SizedBox(width: S.s),
              PingBadge(link: link),
            ]),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(S.l, S.xl, S.l, ins.bottom < S.m ? S.m : ins.bottom),
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, rgba(2, 4, 14, .92), rgba(2, 4, 14, .98)])),
              child: playing
                  ? Btn(label: 'ورود به بازی زنده', colors: G.red, onPress: widget.onWatch)
                  : autoKind
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: S.m),
                          child: T(full ? 'آماده‌ی شروع…' : 'در جستجوی حریف… (${fa(st.players.where((p) => p['role'] == 'player').length)}/${fa(n * 2)})', align: TextAlign.center, style: fs(F.bold, TS.body, color: C.cyan)),
                        )
                      : isHost
                          ? Column(mainAxisSize: MainAxisSize.min, children: [
                              if (reason.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: S.s), child: T(reason, style: fs(F.body, TS.cap, color: C.dim))),
                              Btn(label: busy == 'start' ? 'در حال شروع…' : 'شروع بازی', onPress: start, disabled: !canStart || busy != null, colors: canStart ? G.gold : G.dark),
                            ])
                          : amPlayer
                              ? Btn(label: meP?['ready'] == true ? 'آماده‌ام ✓' : 'اعلام آمادگی', onPress: ready, disabled: busy != null, colors: meP?['ready'] == true ? G.green : G.primary)
                              : Padding(padding: const EdgeInsets.symmetric(vertical: S.m), child: T('برای بازی روی یک جایگاه خالی بزن', align: TextAlign.center, style: fs(F.body, TS.small, color: C.dim))),
            ),
          ),
          if (count > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: rgba(2, 4, 14, .7),
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    T(fa(count), key: ValueKey(count), style: fs(F.title, 96, color: Colors.white, shadows: [Shadow(color: C.cyan, blurRadius: 30)]))
                        .animate(key: ValueKey(count))
                        .scaleXY(begin: 1.8, end: 1, duration: 450.ms, curve: Curves.easeOutBack)
                        .fadeIn(duration: 200.ms),
                    T('بازی شروع می‌شود', style: fs(F.bold, TS.h, color: C.cyan)),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }

  Widget _codeBtn(String l, VoidCallback f) => Press(
        onPress: f,
        child: Container(
          constraints: const BoxConstraints(minWidth: 64), height: 44, padding: const EdgeInsets.symmetric(horizontal: S.m), alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: rgba(79, 227, 255, .12), border: Border.all(color: C.cyan.withValues(alpha: .53))),
          child: T(l, style: fs(F.bold, TS.small)),
        ),
      );
}

String? _disc(JRow p) => (p['profiles'] as Map?)?['equipped_disc'] as String? ?? (p['profiles'] as Map?)?['avatar'] as String?;

class _Seat extends StatelessWidget {
  final JRow p;
  final String me, host;
  final bool online, talking, canKick, busy;
  final Color color;
  final VoidCallback onKick;
  const _Seat({super.key, required this.p, required this.me, required this.host, required this.online, required this.talking, required this.color, required this.canKick, required this.onKick, required this.busy});
  @override
  Widget build(BuildContext context) {
    final uid = rs(p, 'user_id'), isHost = uid == host, pr = p['profiles'] as Map?;
    final ds = discStats((p['disc_id'] ?? pr?['equipped_disc']) as String?);
    final nav = NavScope.of(context);
    return AnimatedContainer(
      duration: 250.ms,
      constraints: const BoxConstraints(minHeight: 68),
      margin: const EdgeInsets.only(bottom: S.s),
      padding: const EdgeInsets.symmetric(horizontal: S.s, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: talking ? C.green : uid == me ? color : C.line),
        color: rgba(10, 16, 44, .88),
        boxShadow: talking ? [BoxShadow(color: C.green.withValues(alpha: .5), blurRadius: 10)] : null,
      ),
      child: rrow([
        Stack(children: [
          Press(onPress: uid != me ? () => nav.openProfile(uid) : null, child: AvatarO(avatar: _disc(p), url: pr?['avatar_url'] as String?, size: 40, ring: talking ? C.green : color, dim: !online)),
          Positioned(
            bottom: 0, left: 0,
            child: Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? C.green : C.dim2, border: Border.all(color: hex('#0b1236'), width: 2))),
          ),
        ]),
        const SizedBox(width: S.s),
        Expanded(
          child: rcol([
            T('${isHost ? '👑 ' : ''}${pr?['username'] ?? '…'}', n: 1, style: fs(F.bold, TS.small)),
            T(isHost ? 'میزبان' : p['ready'] == true ? 'آماده ✓' : 'آماده نیست', n: 1, style: fs(F.body, TS.tiny, color: isHost ? C.gold : p['ready'] == true ? C.green : C.dim2)),
            StatBars(power: ds.power.round(), accuracy: ds.accuracy.round(), compact: true),
          ]),
        ),
        if (canKick)
          Press(onPress: onKick, disabled: busy, child: SizedBox(width: 40, height: 44, child: Center(child: T('✕', style: fs(F.body, 12, color: C.red))))),
      ]),
    );
  }
}

class _RoomSettings extends StatefulWidget {
  final RoomLink link;
  final Toast toast;
  final VoidCallback onDone;
  const _RoomSettings({required this.link, required this.toast, required this.onDone});
  @override
  State<_RoomSettings> createState() => _RoomSettingsState();
}

class _RoomSettingsState extends State<_RoomSettings> {
  late final JRow room = widget.link.value.room!;
  late final name = TextEditingController(text: rs(room, 'name'));
  late String rule = settingsToRule(room['settings'] as Map?);
  late int turn = ((room['settings'] as Map?)?['turn'] as num?)?.toInt() ?? 15;
  late int field = ((room['settings'] as Map?)?['field'] as num?)?.toInt() ?? 0;
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final nm = name.text.trim();
      await rpc('update_room', {
        'p_room': room['id'],
        'p_settings': {...?(room['settings'] as Map?)?.cast<String, dynamic>(), ...ruleToSettings(rule), 'turn': turn, 'field': field},
        'p_name': nm.length > 40 ? nm.substring(0, 40) : nm,
      });
      widget.link.ping();
      await widget.link.refresh();
      widget.toast('تنظیمات ذخیره شد', 'ok');
      widget.onDone();
    } catch (e) {
      widget.toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget lbl(String s) => Padding(padding: const EdgeInsets.only(top: S.l, bottom: S.s), child: T(s, align: TextAlign.right, style: fs(F.bold, TS.small, color: C.dim)));
    return ListView(padding: const EdgeInsets.fromLTRB(S.l, S.l, S.l, S.xl), children: [
      OField(label: 'نام اتاق', ctl: name, maxLength: 40),
      lbl('قانون بازی'),
      Segment(value: rule, onChange: (v) => setState(() => rule = v), items: RULES, accent: C.violet),
      lbl('زمان هر نوبت'),
      Segment(value: turn, onChange: (v) => setState(() => turn = v), items: const [(10, '۱۰ث'), (15, '۱۵ث'), (20, '۲۰ث'), (0, 'بدون')], accent: C.green),
      lbl('زمین'),
      FieldPicker(value: field, onChange: (v) => setState(() => field = v)),
      const SizedBox(height: S.l),
      Btn(label: busy ? 'در حال ذخیره…' : 'ذخیره', disabled: busy, onPress: save),
    ]);
  }
}
