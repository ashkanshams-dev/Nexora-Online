// Online hub — port of src/online/Hub.tsx: profile strip, quick match (realtime queue), shortcuts, create / join by code,
// live room list (postgres_changes + 20 s poll), create-room sheet.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent, RealtimeChannel;

import '../game/assets.dart';
import '../game/data.dart';
import '../nav.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../oracle/oracle_bus.dart';
import '../sound.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'challenges.dart' show Toast;
import 'matchmaker.dart';
import 'online_match.dart' show ruleLabel;
import 'ui.dart';

enum HubNav { tours, ranks, arena, challenges }

const MODES = ['1v1', '2v2', '3v3'];
const MODE_FA = {'1v1': 'تک به تک', '2v2': '۲ به ۲', '3v3': '۳ به ۳'};
Map<String, (String, Color)> get KIND_FA => {'casual': ('دوستانه', C.green), 'quick': ('سریع', C.cyan), 'arena': ('آرنا', C.violet), 'tournament': ('تورنمنت', C.orange), 'duel': ('دوئل', C.gold)};

const RULES = [('g3', 'تا ۳ گل'), ('g5', 'تا ۵ گل'), ('t3', '۳ دقیقه'), ('t5', '۵ دقیقه')];
Map<String, int> ruleToSettings(String r) => r == 'g3'
    ? {'goals': 3, 'time': 0}
    : r == 'g5'
        ? {'goals': 5, 'time': 0}
        : r == 't5'
            ? {'goals': 3, 'time': 300}
            : {'goals': 3, 'time': 180};
String settingsToRule(Map? st) {
  num n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
  return n(st?['time']) >= 300 ? 't5' : n(st?['time']) > 0 ? 't3' : n(st?['goals']) >= 5 ? 'g5' : 'g3';
}

class Hub extends StatefulWidget {
  final VoidCallback onBack;
  final void Function(JRow room) onRoom;
  final void Function(HubNav n) onNav;
  final Toast toast;
  const Hub({super.key, required this.onBack, required this.onRoom, required this.onNav, required this.toast});
  @override
  State<Hub> createState() => _HubState();
}

class _HubState extends State<Hub> {
  List<JRow>? rows;
  String? err, busy;
  String filter = 'all';
  final code = TextEditingController();
  RealtimeChannel? _ch;
  Timer? _t, _poll;

  @override
  void initState() {
    super.initState();
    load();
    void soon() {
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 600), load);
    }

    _ch = supabase
        .channel('hub:rooms')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'rooms', callback: (_) => soon())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'room_players', callback: (_) => soon())
        .subscribe();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => load());
  }

  @override
  void dispose() {
    _t?.cancel();
    _poll?.cancel();
    if (_ch != null) supabase.removeChannel(_ch!);
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await supabase.from('room_list').select().order('created_at', ascending: false).limit(60);
      if (!mounted) return;
      setState(() {
        err = null;
        rows = List<JRow>.from(d);
      });
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  Future<void> act(String key, Future<Object?> Function() fn) async {
    if (busy != null) return;
    setState(() => busy = key);
    try {
      final r = await fn();
      sfx(Sfx.join);
      buzz(Buzz.medium);
      widget.onRoom(Map<String, dynamic>.from(r as Map));
    } catch (e) {
      widget.toast(errFa(e), 'err');
      buzz(Buzz.heavy);
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  void quick(String m, [String kind = 'quick']) {
    OracleBus.I.react(OracleEvent.search);
    buzz(Buzz.medium);
    Matchmaker.I.start(m, kind: kind);
  }

  void join(String id, bool spectate) => act((spectate ? 'w' : 'j') + id, () => rpc('join_room', {'p_room': id, 'p_spectate': spectate}));
  void joinCode() {
    final c = code.text.trim().toUpperCase();
    if (c.length != 6) return widget.toast('کد اتاق ۶ کاراکتر است', 'err');
    act('code', () => rpc('join_room', {'p_code': c}));
  }

  void create() => showNxSheet(context, title: 'ساخت اتاق', en: 'CREATE ROOM', accent: C.green, height: .88, builder: (c) => CreateRoom(onCreate: (a) {
        Navigator.of(c).pop();
        act('create', () => rpc('create_room', a));
      }));

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    final data = (rows ?? []).where((r) => filter == 'all' || r['mode'] == filter).toList();
    return Stack(children: [
      RefreshIndicator(
        onRefresh: load,
        color: C.cyan,
        edgeOffset: ins.top + 70,
        child: ListView(
          padding: EdgeInsets.only(top: ins.top + 76, bottom: ins.bottom + S.xl),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            ListenableBuilder(listenable: Auth.I, builder: (_, _) => _profileCard()),
            Enter(i: 1, child: Padding(padding: const EdgeInsets.fromLTRB(S.l, S.m, S.l, 0), child: _quickPanel())),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.l, S.m, S.l, 0),
              child: rrow([
                for (final (i, (k, l, img, c)) in [
                  (HubNav.arena, 'آرنا', UI2['x_crown'], C.violet),
                  (HubNav.tours, 'تورنمنت', UI2['x_trophy'], C.orange),
                  (HubNav.ranks, 'رده‌بندی', UI2['x_medal'], C.gold),
                  (HubNav.challenges, 'چالش‌ها', UI2['c_calendar'], C.green),
                ].indexed)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i < 3 ? S.s : 0),
                      child: Press(
                        onPress: () => widget.onNav(k),
                        child: Container(
                          height: 76,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: c.withValues(alpha: .4)),
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: .2), rgba(8, 12, 34, .9)]),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Img(img, w: 36, h: 36), T(l, n: 1, style: fs(F.bold, TS.cap))]),
                        ),
                      ),
                    ).animate(delay: (80 + i * 45).ms).fadeIn(duration: 300.ms).scaleXY(begin: .9, curve: Curves.easeOutBack),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.l, S.m, S.l, 0),
              child: rrow(cross: CrossAxisAlignment.start, [
                SizedBox(width: 128, child: Btn(label: 'ساخت اتاق', small: true, colors: G.green, onPress: create)),
                const SizedBox(width: S.s),
                Expanded(
                  child: OField(
                    ctl: code, placeholder: 'کد ۶ رقمی', center: true, mono: true, maxLength: 6, upper: true, onSubmit: (_) => joinCode(),
                    onChanged: (v) {
                      final f = v.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
                      final s = f.substring(0, math.min(6, f.length));
                      if (s != v) code.value = TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
                    },
                  ),
                ),
                const SizedBox(width: S.s),
                Press(
                  onPress: joinCode,
                  disabled: busy == 'code',
                  child: Container(
                    width: 64, height: 48, alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: rgba(79, 227, 255, .18), border: Border.all(color: C.cyan)),
                    child: busy == 'code' ? const Spinner() : T('ورود', style: fs(F.bold, TS.small)),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.l, S.xs, S.l, S.s),
              child: Column(children: [
                rrow([T('اتاق‌های باز', style: fs(F.bold, TS.h)), const Spacer(), T(rows != null ? '${fa(data.length)} اتاق' : '', style: fs(F.body, TS.cap, color: C.dim))]),
                const SizedBox(height: S.s),
                Tabs2(items: const [('all', 'همه'), ('1v1', '1v1'), ('2v2', '2v2'), ('3v3', '3v3')], value: filter, onChange: (v) => setState(() => filter = v)),
              ]),
            ),
            if (err != null && rows == null)
              ErrorState(msg: err!, onRetry: load)
            else if (rows == null)
              const Padding(padding: EdgeInsets.symmetric(horizontal: S.l), child: Skeleton(rows: 4))
            else if (data.isEmpty)
              Empty(img: UI2['x_ball'], title: 'فعلاً اتاقی باز نیست', sub: 'یک اتاق بساز و دوستانت را با کد دعوت کن', action: 'ساخت اتاق', onAction: create)
            else
              for (final (i, r) in data.indexed) Enter(i: i, child: RoomRow(r: r, busy: busy, onJoin: join)),
          ],
        ),
      ),
      Header(title: 'آنلاین', en: 'ONLINE ARENA', onBack: widget.onBack),
    ]);
  }

  Widget _profileCard() {
    final p = Auth.I.profile;
    if (p == null) return const SizedBox.shrink();
    final lp = levelProgress(ri(p, 'xp'));
    return Enter(
      i: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.l),
        child: Press(
          onPress: () => widget.onNav(HubNav.ranks),
          scaleTo: .98,
          child: Panel(
            accent: C.gold,
            pad: const EdgeInsets.all(S.m),
            child: rrow([
              AvatarO(avatar: (p['equipped_disc'] ?? p['avatar']) as String?, url: p['avatar_url'] as String?, size: 52, ring: C.gold),
              const SizedBox(width: S.m),
              Expanded(
                child: rcol([
                  rrow([Flexible(child: T(rs(p, 'username'), n: 1, style: fs(F.bold, TS.h))), Badge2(label: 'سطح ${fa(ri(p, 'level', 1))}', color: C.gold)]),
                  const SizedBox(height: S.s),
                  Bar(v: lp.frac, color: C.cyan, color2: C.violet, h: 6),
                  const SizedBox(height: 2),
                  T('${fa(lp.cur)} / ${fa(lp.need)} XP · امتیاز ${fa(ri(p, 'rating'))}', style: fs(F.body, TS.tiny, color: C.dim)),
                ]),
              ),
              Img(leagueImg(p['league'] as String?), w: 48, h: 48),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _quickPanel() => Panel(
        accent: C.cyan,
        glow: true,
        pad: const EdgeInsets.all(S.m),
        child: Stack(children: [
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [rgba(79, 227, 255, .14), Colors.transparent])))),
          Column(children: [
            rrow([
              Img(UI2['x_ball'], w: 36, h: 36),
              const SizedBox(width: S.s),
              Expanded(child: rcol([T('مسابقه‌ی سریع', style: fs(F.title, TS.h)), T('هم‌سطح‌ترین حریف آنلاین را پیدا کن', style: fs(F.body, TS.cap, color: C.dim))])),
            ]),
            const SizedBox(height: S.s),
            rrow([
              for (final (i, m) in MODES.indexed)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i < 2 ? S.s : 0),
                    child: Btn(label: m.toUpperCase(), sub: MODE_FA[m], small: true, onPress: () => quick(m), colors: i == 0 ? G.primary : i == 1 ? G.violet : G.gold),
                  ),
                ),
            ]),
          ]),
        ]),
      );
}

/// full-screen searching overlay: radar pulse, elapsed time, queue size, ping, cancel
class QueueOverlay extends StatefulWidget {
  final MMState s;
  const QueueOverlay({super.key, required this.s});
  @override
  State<QueueOverlay> createState() => _QueueOverlayState();
}

class _QueueOverlayState extends State<QueueOverlay> with Ticking {
  @override
  void initState() {
    super.initState();
    startTicking(const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s, failed = s.status == MMStatus.failed, w = s.waited;
    return Material(
      color: rgba(2, 4, 14, .86),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(S.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 200, height: 200,
              child: Stack(alignment: Alignment.center, children: [
                if (!failed)
                  for (var i = 0; i < 3; i++)
                    Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.cyan, width: 2)))
                        .animate(onPlay: (c) => c.repeat(), delay: (i * 600).ms)
                        .scaleXY(begin: .3, end: 1, duration: 1800.ms, curve: Curves.easeOut)
                        .fadeOut(begin: .9, duration: 1800.ms),
                Img(failed ? UI2['c_bell'] : UI2['x_ball'], w: 84, h: 84)
                    .animate(onPlay: (c) => c.repeat())
                    .rotate(duration: failed ? 1.ms : 2400.ms),
              ]),
            ),
            const SizedBox(height: S.l),
            T(failed ? 'جستجو متوقف شد' : 'در جستجوی حریف…', style: fs(F.title, 20)),
            const SizedBox(height: S.xs),
            if (failed)
              T(s.error ?? '', align: TextAlign.center, style: fs(F.body, TS.small, color: C.orange))
            else ...[
              T('${s.mode?.toUpperCase() ?? ''} · ${s.kind == 'arena' ? 'آرنا' : 'سریع'} · ${fa(w ~/ 60)}:${faNum((w % 60).toString().padLeft(2, '0'))}', style: fs(F.head, 14, color: C.cyan)),
              const SizedBox(height: S.xs),
              T(s.queued > 1 ? '${fa(s.queued)} بازیکن در صف · پینگ ${fa(s.rtt)}ms' : 'پینگ ${fa(s.rtt)}ms', style: fs(F.body, TS.cap, color: C.dim)),
              const SizedBox(height: S.xs),
              AnimatedOpacity(
                opacity: w >= 15 ? 1 : 0,
                duration: 400.ms,
                child: T('اگر حریفی پیدا نشه، با ربات‌ها شروع می‌کنیم 🤖', style: fs(F.body, TS.cap, color: C.dim2)),
              ),
            ],
            const SizedBox(height: S.xl),
            SizedBox(
              width: 220,
              child: failed
                  ? Column(children: [
                      Btn(label: 'دوباره', small: true, onPress: () => Matchmaker.I.start(s.mode ?? '1v1', kind: s.kind ?? 'quick')),
                      const SizedBox(height: S.s),
                      Btn(label: 'بستن', small: true, colors: G.dark, onPress: Matchmaker.I.reset),
                    ])
                  : Btn(label: 'لغو جستجو', small: true, colors: G.red, onPress: () {
                      buzz(Buzz.medium);
                      Matchmaker.I.cancel();
                    }),
            ),
          ]),
        ),
      ).animate().fadeIn(duration: 220.ms),
    );
  }
}

class RoomRow extends StatelessWidget {
  final JRow r;
  final String? busy;
  final void Function(String id, bool spectate) onJoin;
  const RoomRow({super.key, required this.r, required this.busy, required this.onJoin});
  @override
  Widget build(BuildContext context) {
    final full = ri(r, 'players') >= ri(r, 'capacity'), playing = r['status'] == 'playing', id = rs(r, 'id');
    final (kl, kc) = KIND_FA[r['kind']] ?? KIND_FA['casual']!;
    final nav = NavScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.s),
      child: Panel(
        noAccent: true,
        pad: const EdgeInsets.all(S.m),
        child: Column(children: [
          rrow([
            Press(onPress: () => nav.openProfile(rs(r, 'host')), child: AvatarO(avatar: r['host_avatar'] as String?, url: r['host_avatar_url'] as String?, size: 44, ring: playing ? C.red : C.cyan)),
            const SizedBox(width: S.s),
            Expanded(
              child: rcol([
                T(rs(r, 'name'), n: 1, style: fs(F.bold, TS.body)),
                T('${rs(r, 'host_name')} · سطح ${fa(ri(r, 'host_level', 1))} · ${ruleLabel(r['settings'] as Map?)}', n: 1, style: fs(F.body, TS.cap, color: C.dim)),
                const SizedBox(height: S.xs),
                rrow([
                  Badge2(label: rs(r, 'mode').toUpperCase(), color: C.sky),
                  Badge2(label: kl, color: kc),
                  playing ? Badge2(label: 'زنده', color: C.red, live: true) : Badge2(label: 'در انتظار', color: C.green),
                ]),
              ]),
            ),
            SizedBox(
              width: 64,
              child: Column(children: [
                T('${fa(ri(r, 'players'))}/${fa(ri(r, 'capacity'))}', style: fs(F.title, TS.h, color: full ? C.orange : C.text)),
                T('👁 ${fa(ri(r, 'spectators'))}', style: fs(F.body, TS.tiny, color: C.dim)),
              ]),
            ),
          ]),
          const SizedBox(height: S.s),
          rrow([
            if (!playing && !full) ...[
              Expanded(child: Btn(label: busy == 'j$id' ? '…' : 'ورود', small: true, disabled: busy != null, onPress: () => onJoin(id, false))),
              const SizedBox(width: S.s),
            ],
            Expanded(child: Btn(label: busy == 'w$id' ? '…' : 'تماشا', small: true, colors: G.dark, disabled: busy != null, onPress: () => onJoin(id, true))),
          ]),
        ]),
      ),
    );
  }
}

class FieldPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChange;
  const FieldPicker({super.key, required this.value, required this.onChange});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 96,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          reverse: true,
          itemCount: FIELDS.length,
          itemBuilder: (_, i) {
            final f = FIELDS[i], on = i == value;
            return Padding(
              padding: const EdgeInsets.only(left: S.s, top: S.xs, bottom: S.xs),
              child: Press(
                onPress: () => onChange(i),
                child: AnimatedContainer(
                  duration: 200.ms,
                  width: 78, padding: const EdgeInsets.all(S.xs),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? C.cyan : C.line), color: on ? rgba(79, 227, 255, .12) : null),
                  child: Column(children: [
                    Img(FIELD_THUMB[f.id], w: 44, h: 58, fit: BoxFit.cover, radius: 6),
                    const SizedBox(height: 2),
                    T(f.name, n: 1, style: fs(F.body, TS.tiny, color: on ? C.text : C.dim)),
                  ]),
                ),
              ),
            );
          },
        ),
      );
}

class CreateRoom extends StatefulWidget {
  final void Function(Map<String, dynamic> args) onCreate;
  const CreateRoom({super.key, required this.onCreate});
  @override
  State<CreateRoom> createState() => _CreateRoomState();
}

class _CreateRoomState extends State<CreateRoom> {
  final name = TextEditingController();
  String mode = '1v1', rule = 'g3';
  bool priv = false, ranked = true, voice = true;
  int turn = 15, field = 0;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Widget _row(String label, String sub, bool v, ValueChanged<bool> set) => Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF), width: .5))),
        child: rrow([Expanded(child: rcol([T(label, style: fs(F.bold, TS.body)), T(sub, style: fs(F.body, TS.cap, color: C.dim))])), const SizedBox(width: S.m), Toggle(on: v, onChange: set)]),
      );

  @override
  Widget build(BuildContext context) {
    Widget lbl(String s) => Padding(padding: const EdgeInsets.only(top: S.l, bottom: S.s), child: T(s, align: TextAlign.right, style: fs(F.bold, TS.small, color: C.dim)));
    return ListView(padding: const EdgeInsets.fromLTRB(S.l, S.l, S.l, S.xl * 2), children: [
      OField(label: 'نام اتاق', ctl: name, placeholder: 'مثلاً: فینال کهکشانی', maxLength: 40),
      lbl('حالت'),
      Segment(value: mode, onChange: (v) => setState(() => mode = v), items: [for (final m in MODES) (m, MODE_FA[m]!)]),
      lbl('قانون'),
      Segment(value: rule, onChange: (v) => setState(() => rule = v), items: RULES, accent: C.violet),
      lbl('زمان هر نوبت'),
      Segment(value: turn, onChange: (v) => setState(() => turn = v), items: const [(10, '۱۰ث'), (15, '۱۵ث'), (20, '۲۰ث'), (0, 'بدون')], accent: C.green),
      lbl('زمین'),
      FieldPicker(value: field, onChange: (v) => setState(() => field = v)),
      const SizedBox(height: S.m),
      _row('خصوصی', 'فقط با کد اتاق می‌شود وارد شد', priv, (v) => setState(() => priv = v)),
      _row('رتبه‌ای', 'نتیجه روی امتیاز و لیگ اثر دارد', ranked, (v) => setState(() => ranked = v)),
      _row('چت صوتی', 'بازیکن‌ها می‌توانند صحبت کنند', voice, (v) => setState(() => voice = v)),
      const SizedBox(height: S.l),
      Btn(
        label: 'ساخت اتاق',
        colors: G.green,
        onPress: () => widget.onCreate({
          'p_mode': mode, 'p_name': name.text.trim().isEmpty ? null : name.text.trim(), 'p_private': priv, 'p_ranked': ranked, 'p_voice': voice,
          'p_settings': {...ruleToSettings(rule), 'field': field, 'turn': turn, 'ball': 0},
        }),
      ),
    ]);
  }
}

/// copy helper shared by lobby/club screens
Future<void> copyText(String s) => Clipboard.setData(ClipboardData(text: s));
