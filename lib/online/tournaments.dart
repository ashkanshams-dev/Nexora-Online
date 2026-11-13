// Tournaments — port of src/online/Tournaments.tsx: list (registration / running / finished), create sheet,
// detail with bracket (single / double elimination, connectors) or standings, organizer override, live updates.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType, RealtimeChannel;

import '../game/assets.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../oracle/oracle_bus.dart';
import '../sound.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'challenges.dart' show Toast;
import 'ui.dart';

const FORMAT_FA = {'single_elim': 'حذفی تک', 'double_elim': 'حذفی دوگانه', 'round_robin': 'دوره‌ای', 'swiss': 'سوئیسی', 'league': 'لیگ'};
Map<String, (String, Color)> get STATUS_FA => {'registration': ('ثبت‌نام', C.green), 'running': ('در جریان', C.orange), 'finished': ('پایان‌یافته', C.dim)};
bool isElim(String? f) => f == 'single_elim' || f == 'double_elim';
(String, Color) statusOf(String? s) => STATUS_FA[s] ?? (s ?? '', C.dim);

class Tournaments extends StatefulWidget {
  final VoidCallback onBack;
  final void Function(String id) onOpen;
  final Toast toast;
  const Tournaments({super.key, required this.onBack, required this.onOpen, required this.toast});
  @override
  State<Tournaments> createState() => _TournamentsState();
}

class _TournamentsState extends State<Tournaments> {
  String tab = 'registration';
  List<JRow>? rows;
  String? err;
  RealtimeChannel? _ch;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _sub();
  }

  void _sub() {
    setState(() => rows = null);
    load();
    if (_ch != null) supabase.removeChannel(_ch!);
    void soon() {
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 500), load);
    }

    _ch = supabase
        .channel('tours:$tab')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tournaments', callback: (_) => soon())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tournament_entries', callback: (_) => soon())
        .subscribe();
  }

  @override
  void dispose() {
    _t?.cancel();
    if (_ch != null) supabase.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> load() async {
    final t = tab;
    try {
      final d = await supabase.from('tournaments').select('*, entries:tournament_entries(count)').eq('status', t).order('created_at', ascending: false).limit(50);
      if (!mounted || t != tab) return;
      setState(() {
        err = null;
        rows = List<JRow>.from(d);
      });
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  void create() => showNxSheet(context, title: 'ساخت تورنمنت', en: 'NEW TOURNAMENT', accent: C.orange, height: .9, builder: (c) => _CreateTournament(toast: widget.toast, onDone: (id) {
        Navigator.of(c).pop();
        widget.onOpen(id);
      }));

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    return Stack(children: [
      RefreshIndicator(
        onRefresh: load,
        color: C.cyan,
        edgeOffset: ins.top + 70,
        child: ListView(padding: EdgeInsets.only(top: ins.top + 76, bottom: ins.bottom + S.xl), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.m),
            child: Tabs2(items: const [('registration', 'ثبت‌نام'), ('running', 'در جریان'), ('finished', 'تمام‌شده')], value: tab, onChange: (v) {
              tab = v;
              _sub();
            }),
          ),
          if (err != null && rows == null)
            ErrorState(msg: err!, onRetry: load)
          else if (rows == null)
            const Padding(padding: EdgeInsets.symmetric(horizontal: S.l), child: Skeleton(rows: 4, h: 92))
          else if (rows!.isEmpty)
            Empty(
              img: UI2['x_trophy'], title: 'تورنمنتی در این بخش نیست',
              sub: tab == 'registration' ? 'اولین تورنمنت را خودت بساز!' : null,
              action: tab == 'registration' ? 'ساخت تورنمنت' : null, onAction: create,
            )
          else
            for (final (i, t) in rows!.indexed)
              Enter(i: i, child: _TourRow(t: t, count: ((t['entries'] as List?)?.firstOrNull as Map?)?['count'] as int? ?? 0, onPress: () => widget.onOpen(rs(t, 'id')))),
        ]),
      ),
      Header(
        title: 'تورنمنت‌ها', en: 'TOURNAMENTS', accent: C.orange, onBack: widget.onBack,
        right: Press(
          onPress: create,
          child: Container(
            width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: rgba(61, 255, 168, .12), border: Border.all(color: C.green.withValues(alpha: .53))),
            child: T('+', style: fs(F.title, 22, color: C.green)),
          ),
        ),
      ),
    ]);
  }
}

class _TourRow extends StatelessWidget {
  final JRow t;
  final int count;
  final VoidCallback onPress;
  const _TourRow({required this.t, required this.count, required this.onPress});
  @override
  Widget build(BuildContext context) {
    final (sl, sc) = statusOf(t['status'] as String?);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.s),
      child: Card2(
        onPress: onPress,
        accent: sc,
        child: rrow([
          Img(t['status'] == 'finished' ? UI2['x_medal'] : UI2['x_trophy'], w: 52, h: 52),
          const SizedBox(width: S.m),
          Expanded(
            child: rcol([
              T(rs(t, 'name'), n: 1, style: fs(F.bold, TS.body)),
              const SizedBox(height: S.xs),
              Wrap(textDirection: TextDirection.rtl, runSpacing: 4, children: [
                Badge2(label: FORMAT_FA[t['format']] ?? rs(t, 'format'), color: C.violet),
                Badge2(label: rs(t, 'mode').toUpperCase(), color: C.sky),
                Badge2(label: sl, color: sc, live: t['status'] == 'running'),
              ]),
            ]),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 60),
            child: Column(children: [
              T('${fa(count)}/${fa(ri(t, 'max_entries'))}', style: fs(F.title, TS.h)),
              T('💎 ${fa(ri(t, 'prize_gems'))}', style: fs(F.body, TS.cap, color: hex('#9fd8ff'))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CreateTournament extends StatefulWidget {
  final Toast toast;
  final void Function(String id) onDone;
  const _CreateTournament({required this.toast, required this.onDone});
  @override
  State<_CreateTournament> createState() => _CreateTournamentState();
}

class _CreateTournamentState extends State<_CreateTournament> {
  final name = TextEditingController();
  String format = 'single_elim', mode = '1v1';
  int max = 8, rounds = 2, gems = 20, minLv = 1;
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> go() async {
    if (name.text.trim().length < 3) return widget.toast('نام تورنمنت حداقل ۳ کاراکتر', 'err');
    setState(() => busy = true);
    try {
      final t = await rpc('create_tournament', {
        'p_name': name.text.trim(), 'p_format': format, 'p_mode': mode, 'p_max': max,
        'p_rounds': format == 'league' || format == 'swiss' ? rounds : null, 'p_prize_gems': gems, 'p_starts': null, 'p_min_level': minLv,
      });
      sfx(Sfx.ready);
      buzz(Buzz.success);
      widget.toast('تورنمنت ساخته شد', 'ok');
      widget.onDone(rs(t as Map<String, dynamic>, 'id'));
    } catch (e) {
      widget.toast(errFa(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget lbl(String s) => Padding(padding: const EdgeInsets.only(top: S.l, bottom: S.s), child: T(s, align: TextAlign.right, style: fs(F.bold, TS.small, color: C.dim)));
    return ListView(padding: const EdgeInsets.fromLTRB(S.l, S.l, S.l, S.xl * 2), children: [
      OField(label: 'نام تورنمنت', ctl: name, maxLength: 40, placeholder: 'جام کهکشان'),
      lbl('فرمت'),
      Wrap(textDirection: TextDirection.rtl, spacing: S.s, runSpacing: S.s, children: [
        for (final f in FORMAT_FA.keys)
          Press(
            onPress: () => setState(() => format = f),
            child: AnimatedContainer(
              duration: 200.ms,
              height: 44, padding: const EdgeInsets.symmetric(horizontal: S.l), alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: f == format ? C.violet : C.line), color: f == format ? C.violet.withValues(alpha: .2) : rgba(8, 12, 34, .7)),
              child: T(FORMAT_FA[f]!, style: fs(F.bold, TS.small, color: f == format ? Colors.white : C.dim)),
            ),
          ),
      ]),
      lbl('حالت'),
      Segment(value: mode, onChange: (v) => setState(() => mode = v), items: const [('1v1', '1v1'), ('2v2', '2v2'), ('3v3', '3v3')]),
      lbl('ظرفیت'),
      Segment(value: max, onChange: (v) => setState(() => max = v), items: const [(4, '۴'), (8, '۸'), (16, '۱۶'), (32, '۳۲'), (64, '۶۴')], accent: C.orange),
      if (format == 'league' || format == 'swiss') ...[
        lbl(format == 'league' ? 'تعداد دور رفت و برگشت' : 'تعداد دورها'),
        Segment(
          value: rounds, onChange: (v) => setState(() => rounds = v), accent: C.violet,
          items: format == 'league' ? const [(1, 'یک'), (2, 'دو'), (3, 'سه')] : const [(3, '۳'), (4, '۴'), (5, '۵'), (6, '۶')],
        ),
      ],
      lbl('جایزه‌ی قهرمان (الماس) — نایب‌قهرمان یک‌سوم'),
      Segment(value: gems, onChange: (v) => setState(() => gems = v), items: const [(0, '۰'), (10, '۱۰'), (20, '۲۰'), (30, '۳۰')], accent: C.sky),
      lbl('حداقل سطح'),
      Segment(value: minLv, onChange: (v) => setState(() => minLv = v), items: const [(1, '۱'), (3, '۳'), (5, '۵'), (10, '۱۰')], accent: C.green),
      const SizedBox(height: S.l),
      Btn(label: busy ? 'در حال ساخت…' : 'ساخت تورنمنت', colors: G.gold, disabled: busy, onPress: go),
    ]);
  }
}

// ======================= detail =======================
class TournamentDetail extends StatefulWidget {
  final String id;
  final VoidCallback onBack;
  final void Function(JRow room) onRoom;
  final Toast toast;
  const TournamentDetail({super.key, required this.id, required this.onBack, required this.onRoom, required this.toast});
  @override
  State<TournamentDetail> createState() => _TournamentDetailState();
}

class _TournamentDetailState extends State<TournamentDetail> {
  JRow? t;
  List<JRow> entries = [], matches = [];
  Map<String, String> names = {};
  String? err, busy;
  String tab = 'board';
  final teamName = TextEditingController();
  RealtimeChannel? _ch;
  Timer? _tm;
  String? _lastReady;

  @override
  void initState() {
    super.initState();
    load();
    void soon() {
      _tm?.cancel();
      _tm = Timer(const Duration(milliseconds: 300), load);
    }

    PostgresChangeFilter f(String col) => PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: col, value: widget.id);
    _ch = supabase
        .channel('tour:${widget.id}')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tournaments', filter: f('id'), callback: (_) => soon())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tournament_entries', filter: f('tournament_id'), callback: (_) => soon())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tournament_matches', filter: f('tournament_id'), callback: (_) => soon())
        .subscribe();
  }

  @override
  void dispose() {
    _tm?.cancel();
    if (_ch != null) supabase.removeChannel(_ch!);
    teamName.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await Future.wait([
        supabase.from('tournaments').select().eq('id', widget.id).maybeSingle(),
        supabase.from('standings').select().eq('tournament_id', widget.id).order('pos'),
        supabase.from('tournament_matches').select().eq('tournament_id', widget.id).order('round').order('idx'),
      ]);
      if (!mounted) return;
      setState(() {
        err = null;
        t = r[0] as JRow?;
        entries = List<JRow>.from(r[1] as List);
        matches = List<JRow>.from(r[2] as List);
        names = {for (final e in entries) rs(e, 'id'): rs(e, 'team_name')};
      });
      final n = next;
      if (n != null && n['status'] == 'ready' && n['id'] != _lastReady) {
        _lastReady = n['id'] as String?;
        OracleBus.I.react(OracleEvent.tourReady);
      }
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  JRow? get myEntry {
    final uid = Auth.I.uid;
    return uid == null ? null : entries.where((e) => (e['members'] as List?)?.contains(uid) == true).firstOrNull;
  }

  JRow? get next {
    final me = myEntry;
    if (me == null) return null;
    return matches.where((m) => (m['status'] == 'ready' || m['status'] == 'live') && (m['entry_a'] == me['id'] || m['entry_b'] == me['id'])).firstOrNull;
  }

  Future<void> run(String k, Future<void> Function() fn, [String? ok]) async {
    if (busy != null) return;
    setState(() => busy = k);
    try {
      await fn();
      if (ok != null) {
        widget.toast(ok, 'ok');
        buzz(Buzz.success);
      }
      await load();
    } catch (e) {
      widget.toast(errFa(e), 'err');
      buzz(Buzz.heavy);
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  void openRoom(JRow tm) => run('room', () async {
        final r = await rpc('open_tournament_room', {'p_tm': tm['id']});
        widget.onRoom(Map<String, dynamic>.from(r as Map));
      });

  void setResult(JRow m) => showNxModal(context, accent: C.gold, builder: (c) => _Override(m: m, names: names, onClose: () => Navigator.of(c).pop(), onSave: (a, b) {
        Navigator.of(c).pop();
        run('ovr', () => rpc('set_tournament_result', {'p_tm': m['id'], 'p_sa': a, 'p_sb': b}), 'نتیجه ثبت شد');
      }));

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    final t = this.t;
    if (t == null) {
      return Stack(children: [
        err != null ? Padding(padding: EdgeInsets.only(top: ins.top + 90), child: ErrorState(msg: err!, onRetry: load)) : const Center(child: Spinner(size: 36)),
        Header(title: 'تورنمنت', onBack: widget.onBack),
      ]);
    }
    final (sl, sc) = statusOf(t['status'] as String?);
    final winner = t['winner_entry'] != null ? names[t['winner_entry']] : null;
    final my = myEntry, isOrg = t['created_by'] == Auth.I.uid, nx = next, reg = t['status'] == 'registration';
    return Stack(children: [
      ListView(padding: EdgeInsets.only(top: ins.top + 76, bottom: ins.bottom + S.xl), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Panel(
              accent: sc,
              pad: const EdgeInsets.all(S.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Wrap(textDirection: TextDirection.rtl, runSpacing: 4, children: [
                  Badge2(label: sl, color: sc, live: t['status'] == 'running'),
                  Badge2(label: '${fa(entries.length)}/${fa(ri(t, 'max_entries'))} شرکت‌کننده', color: C.sky),
                  Badge2(label: '💎 ${fa(ri(t, 'prize_gems'))} قهرمان', color: hex('#9fd8ff')),
                  Badge2(label: '${fa(ri(t, 'prize_xp'))} XP', color: C.cyan),
                  if (ri(t, 'min_level', 1) > 1) Badge2(label: 'حداقل سطح ${fa(ri(t, 'min_level'))}', color: C.green),
                  if (!reg && ri(t, 'current_round') > 0) Badge2(label: 'دور ${fa(ri(t, 'current_round'))}', color: C.violet),
                ]),
                if (winner != null)
                  Padding(
                    padding: const EdgeInsets.only(top: S.m),
                    child: rrow([Img(UI2['x_trophy'], w: 44, h: 44), const SizedBox(width: S.s), T('قهرمان: $winner', style: fs(F.title, TS.h, color: C.gold))]).animate().shimmer(duration: 1600.ms, color: C.gold.withValues(alpha: .4)),
                  ),
              ]),
            ),
            if (reg) ...[
              const SizedBox(height: S.m),
              if (my != null)
                Btn(label: busy == 'leave' ? '…' : 'انصراف از تورنمنت', small: true, colors: G.dark, onPress: () => run('leave', () => rpc('leave_tournament', {'p_tid': t['id']}), 'از تورنمنت خارج شدی'))
              else if (entries.length < ri(t, 'max_entries')) ...[
                if (t['mode'] != '1v1') OField(label: 'نام تیم (اختیاری)', ctl: teamName, maxLength: 24),
                Btn(
                  label: busy == 'join' ? '…' : 'ثبت‌نام', colors: G.green,
                  onPress: () => run('join', () => rpc('join_tournament', {'p_tid': t['id'], 'p_team_name': teamName.text.trim().isEmpty ? null : teamName.text.trim(), 'p_members': null}), 'ثبت‌نام شدی!'),
                ),
              ] else
                T('ظرفیت تکمیل است', align: TextAlign.center, style: fs(F.body, 14, color: C.orange)),
            ],
            if (isOrg && reg) ...[
              const SizedBox(height: S.s),
              Btn(
                label: busy == 'start' ? '…' : 'شروع تورنمنت (${fa(entries.length)} نفر)', colors: G.gold, disabled: entries.length < 2,
                onPress: () => run('start', () => rpc('start_tournament', {'p_tid': t['id']}), 'تورنمنت شروع شد'),
              ),
            ],
            if (nx != null)
              Padding(
                padding: const EdgeInsets.only(top: S.m),
                child: Panel(
                  accent: C.red,
                  glow: true,
                  pad: const EdgeInsets.all(S.m),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    T('مسابقه‌ی بعدی تو', align: TextAlign.right, style: fs(F.bold, TS.small, color: C.red)),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.s),
                      child: T('${names[nx['entry_a']] ?? '؟'}  vs  ${names[nx['entry_b']] ?? '؟'}', n: 1, align: TextAlign.center, style: fs(F.title, TS.h)),
                    ),
                    Btn(label: busy == 'room' ? '…' : 'ورود به مسابقه', colors: G.red, onPress: () => openRoom(nx)),
                  ]),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).custom(duration: 1200.ms, builder: (_, v, ch) => Transform.scale(scale: 1 + v * .015, child: ch)),
              ),
            const SizedBox(height: S.l),
            Tabs2(items: [('board', isElim(t['format'] as String?) ? 'براکت' : 'جدول'), ('entries', 'شرکت‌کنندگان')], value: tab, onChange: (v) => setState(() => tab = v)),
          ]),
        ),
        const SizedBox(height: S.m),
        AnimatedSwitcher(
          duration: 220.ms,
          child: KeyedSubtree(
            key: ValueKey(tab),
            child: tab == 'entries'
                ? (entries.isEmpty
                    ? const Empty(title: 'هنوز کسی ثبت‌نام نکرده')
                    : Column(children: [
                        for (final e in entries)
                          Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            margin: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.s),
                            padding: const EdgeInsets.symmetric(horizontal: S.m),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line), color: rgba(10, 16, 44, .85)),
                            child: rrow([
                              SizedBox(width: 36, child: T(e['seed'] != null ? '#${fa(ri(e, 'seed'))}' : '•', align: TextAlign.right, style: fs(F.bold, 14, color: C.dim))),
                              const SizedBox(width: S.s),
                              Expanded(child: T(rs(e, 'team_name'), n: 1, align: TextAlign.right, style: fs(F.bold, TS.body))),
                              if (e['eliminated'] == true) Badge2(label: 'حذف', color: C.red) else if (e['final_rank'] == 1) Badge2(label: 'قهرمان', color: C.gold),
                            ]),
                          ),
                      ]))
                : reg
                    ? Empty(img: UI2['c_calendar'], title: 'براکت بعد از شروع ساخته می‌شود', sub: 'برگزارکننده تورنمنت را شروع می‌کند')
                    : isElim(t['format'] as String?)
                        ? _Bracket(matches: matches, names: names, format: rs(t, 'format'), myEntry: my?['id'] as String?, onOverride: isOrg ? setResult : null)
                        : _Standings(entries: entries, matches: matches, names: names, myEntry: my?['id'] as String?, onOverride: isOrg ? setResult : null),
          ),
        ),
      ]),
      Header(title: rs(t, 'name'), en: '${FORMAT_FA[t['format']] ?? ''} · ${rs(t, 'mode').toUpperCase()}', accent: C.orange, onBack: widget.onBack),
    ]);
  }
}

String roundLabel(int round, int total) {
  final left = total - round;
  return left == 0 ? 'فینال' : left == 1 ? 'نیمه‌نهایی' : left == 2 ? 'یک‌چهارم' : left == 3 ? 'یک‌هشتم' : left == 4 ? 'یک‌شانزدهم' : 'دور ${fa(round)}';
}

const double BOX_W = 168, BOX_H = 64, GAP = 14, COL_GAP = 28;

class _Bracket extends StatelessWidget {
  final List<JRow> matches;
  final Map<String, String> names;
  final String format;
  final String? myEntry;
  final void Function(JRow m)? onOverride;
  const _Bracket({required this.matches, required this.names, required this.format, this.myEntry, this.onOverride});
  @override
  Widget build(BuildContext context) {
    final sections = format == 'double_elim'
        ? [
            ('جدول برندگان', matches.where((m) => m['bracket'] == 'winners').toList()),
            ('جدول بازندگان', matches.where((m) => m['bracket'] == 'losers').toList()),
            ('فینال بزرگ', matches.where((m) => m['bracket'] == 'final').toList()),
          ]
        : [('', matches.where((m) => m['bracket'] == 'main' || m['bracket'] == null).toList())];
    return Column(children: [
      for (final (title, ms) in sections.where((s) => s.$2.isNotEmpty)) _section(title, ms, format != 'double_elim' || title == 'جدول برندگان'),
    ]);
  }

  Widget _section(String title, List<JRow> ms, bool labels) {
    final byRound = <int, List<JRow>>{};
    for (final m in ms) {
      (byRound[ri(m, 'round')] ??= []).add(m);
    }
    final keys = byRound.keys.toList()..sort();
    final rounds = [for (final k in keys) byRound[k]!..sort((a, b) => ri(a, 'idx').compareTo(ri(b, 'idx')))];
    final total = rounds.length, firstN = rounds.isEmpty ? 1 : rounds[0].length;
    final H = math.max(firstN * (BOX_H + GAP), BOX_H + GAP);
    final line = rgba(120, 200, 255, .45);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (title.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.s), child: T(title, style: fs(F.bold, TS.body))),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: S.l),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (ri_, col) in rounds.indexed)
              SizedBox(
                width: BOX_W + COL_GAP,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: BOX_W, child: T(labels ? roundLabel(ri_ + 1, total) : 'دور ${fa(ri_ + 1)}', align: TextAlign.center, style: fs(F.bold, TS.cap, color: C.cyan))),
                  const SizedBox(height: S.s),
                  SizedBox(
                    height: H,
                    width: BOX_W + COL_GAP,
                    child: Stack(clipBehavior: Clip.none, children: [
                      for (final (i, m) in col.indexed) ...() {
                        final slotH = H / col.length, top = i * slotH + (slotH - BOX_H) / 2;
                        return [
                          Positioned(
                            top: top, left: 0,
                            child: _MatchBox(
                              m: m, names: names, mine: myEntry != null && (m['entry_a'] == myEntry || m['entry_b'] == myEntry),
                              onPress: onOverride != null && (m['status'] == 'ready' || m['status'] == 'live') ? () => onOverride!(m) : null,
                            ).animate(delay: (ri_ * 90 + i * 30).ms).fadeIn(duration: 250.ms).slideX(begin: -.1),
                          ),
                          if (ri_ < total - 1) ...[
                            Positioned(top: top + BOX_H / 2, left: BOX_W, child: Container(width: COL_GAP / 2, height: 1.5, color: line)),
                            Positioned(
                              left: BOX_W + COL_GAP / 2,
                              top: top + (i.isEven ? BOX_H / 2 : BOX_H / 2 - slotH / 2),
                              child: Container(width: 1.5, height: slotH / 2, color: line),
                            ),
                            if (i.isEven) Positioned(top: top + BOX_H / 2 + slotH / 2, left: BOX_W + COL_GAP / 2, child: Container(width: COL_GAP / 2, height: 1.5, color: line)),
                          ],
                        ];
                      }(),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _MatchBox extends StatelessWidget {
  final JRow m;
  final Map<String, String> names;
  final bool mine;
  final VoidCallback? onPress;
  const _MatchBox({required this.m, required this.names, required this.mine, this.onPress});
  Widget _side(String? e, Object? sc) {
    final win = e != null && m['winner_entry'] == e;
    return Expanded(
      child: Container(
        color: win ? rgba(255, 210, 87, .14) : null,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(children: [
          SizedBox(width: 22, child: T(sc is num ? fa(sc) : m['status'] == 'bye' && e != null ? '–' : '', align: TextAlign.center, style: fs(F.title, TS.small, color: win ? C.gold : C.dim))),
          Expanded(
            child: T(e != null ? names[e] ?? '…' : m['status'] == 'bye' ? 'استراحت' : '—', n: 1, align: TextAlign.right,
                style: fs(win ? F.bold : F.body, TS.small, color: e != null ? (win ? C.gold : C.text) : C.dim2)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = m['status'] == 'live', done = m['status'] == 'done' || m['status'] == 'bye';
    final body = Opacity(
      opacity: done ? .9 : 1,
      child: Container(
        width: BOX_W, height: BOX_H,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: live ? C.red : mine ? C.cyan : C.line), color: rgba(10, 16, 44, .95)),
        child: Stack(children: [
          Column(children: [_side(m['entry_a'] as String?, m['score_a']), Container(height: .5, color: C.line), _side(m['entry_b'] as String?, m['score_b'])]),
          if (live)
            Positioned(top: 4, left: 4, child: Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: C.red)).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: .3, duration: 600.ms)),
        ]),
      ),
    );
    return onPress != null ? Press(onPress: onPress, scaleTo: .97, child: body) : body;
  }
}

class _Standings extends StatelessWidget {
  final List<JRow> entries, matches;
  final Map<String, String> names;
  final String? myEntry;
  final void Function(JRow m)? onOverride;
  const _Standings({required this.entries, required this.matches, required this.names, this.myEntry, this.onOverride});
  @override
  Widget build(BuildContext context) {
    final open = matches.where((m) => m['status'] == 'ready' || m['status'] == 'live').toList();
    Widget td(String s, {double w = 30, bool flex = false, TextStyle? st}) {
      final t = T(s, n: 1, align: flex ? TextAlign.right : TextAlign.center, style: st ?? fs(F.body, TS.small));
      return flex ? Expanded(child: t) : SizedBox(width: w, child: t);
    }

    Widget tr(List<Widget> c, {Color? bg, Color? border}) => Container(
          height: 40, padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(color: bg, border: Border(bottom: BorderSide(color: border ?? C.line, width: .5))),
          child: rrow(c),
        );
    final h = fs(F.bold, TS.small, color: C.dim);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        tr([td('#', st: h), td('تیم', flex: true, st: h), td('بازی', st: h), td('ب', st: h), td('م', st: h), td('ش', st: h), td('گل', w: 44, st: h), td('امتیاز', w: 40, st: h)], border: C.lineHi),
        for (final e in entries)
          tr(bg: e['id'] == myEntry ? rgba(79, 227, 255, .1) : null, [
            td(fa(ri(e, 'pos'))),
            td(rs(e, 'team_name'), flex: true, st: fs(F.bold, TS.small)),
            td(fa(ri(e, 'played'))), td(fa(ri(e, 'wins'))), td(fa(ri(e, 'draws'))), td(fa(ri(e, 'losses'))),
            td('${fa(ri(e, 'gf'))}:${fa(ri(e, 'ga'))}', w: 44),
            td(fa(ri(e, 'points')), w: 40, st: fs(F.title, TS.small, color: C.gold)),
          ]),
        if (open.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.only(top: S.l, bottom: S.s), child: T('مسابقات باز', align: TextAlign.right, style: fs(F.bold, TS.body))),
          for (final m in open)
            Press(
              onPress: onOverride != null ? () => onOverride!(m) : null,
              disabled: onOverride == null,
              scaleTo: .98,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48), margin: const EdgeInsets.only(bottom: S.s), padding: const EdgeInsets.symmetric(horizontal: S.m),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: m['entry_a'] == myEntry || m['entry_b'] == myEntry ? C.cyan : C.line), color: rgba(10, 16, 44, .85)),
                child: rrow([
                  Badge2(label: 'دور ${fa(ri(m, 'round'))}', color: C.violet),
                  const SizedBox(width: S.s),
                  Expanded(child: T('${names[m['entry_a']] ?? '؟'}  vs  ${names[m['entry_b']] ?? '؟'}', n: 1, align: TextAlign.right, style: fs(F.body, TS.small))),
                  if (m['status'] == 'live') Badge2(label: 'زنده', color: C.red, live: true),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}

class _Override extends StatefulWidget {
  final JRow m;
  final Map<String, String> names;
  final VoidCallback onClose;
  final void Function(int a, int b) onSave;
  const _Override({required this.m, required this.names, required this.onClose, required this.onSave});
  @override
  State<_Override> createState() => _OverrideState();
}

class _OverrideState extends State<_Override> {
  int a = 0, b = 0;
  Widget _step(int v, ValueChanged<int> set) {
    Widget btn(String s, VoidCallback f) => Press(
        onPress: f,
        child: Container(
          width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line), color: rgba(8, 12, 34, .8)),
          child: T(s, style: fs(F.body, 20)),
        ));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn('−', () => set(math.max(0, v - 1))),
      SizedBox(width: 40, child: T(fa(v), align: TextAlign.center, style: fs(F.title, 24))),
      btn('+', () => set(math.min(30, v + 1))),
    ]);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(S.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          T('ثبت نتیجه توسط برگزارکننده', align: TextAlign.center, style: fs(F.bold, TS.h)),
          const SizedBox(height: S.m),
          for (final (e, v, set) in [
            (widget.m['entry_a'], a, (int x) => setState(() => a = x)),
            (widget.m['entry_b'], b, (int x) => setState(() => b = x)),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: S.s),
              child: rrow([Expanded(child: T(widget.names[e] ?? '؟', n: 1, align: TextAlign.right, style: fs(F.body, TS.body))), _step(v, set)]),
            ),
          const SizedBox(height: S.s),
          Btn(label: 'ثبت', colors: G.gold, onPress: () => widget.onSave(a, b)),
          const SizedBox(height: S.s),
          Btn(label: 'انصراف', small: true, colors: G.dark, onPress: widget.onClose),
        ]),
      );
}
