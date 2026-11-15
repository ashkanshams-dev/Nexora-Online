// Cups (tournament v3) UI: list + join by 5-digit code, create sheet, cup page (registration, check-in, bracket,
// my next pairing) and the cup room (series score, lineup window, auto start). Server rules: supabase/cups.sql,
// pure mirrors: cup_logic.dart. Times are UTC on the server and shown in the Jalali calendar, Tehran time.
import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData, FilteringTextInputFormatter;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/assets.dart';
import '../core/owned.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../screens/formation_sheet.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'cup_logic.dart';
import 'link.dart';
import 'ui.dart';

// ------------------------------------------------------------------ shared
const _cupErr = [
  ('tournament not found', 'تورنمنتی با این کد پیدا نشد'),
  ('bad start time', 'زمان شروع باید دست‌کم ۲ دقیقه بعد و حداکثر ۶۰ روز بعد باشد'),
  ('check-in not open', 'اعلام حضور از ۱۵ دقیقه قبل از شروع باز می‌شود'),
  ('not registered', 'در این تورنمنت ثبت‌نام نکرده‌ای'),
  ('too many open tournaments', 'حداکثر ۳ تورنمنت باز همزمان می‌توانی بسازی'),
  ('bad split', 'تقسیم جایزه نامعتبر است'),
  ('bad prize', 'جایزه باید بین ۰ تا ۱۰۰ الماس باشد'),
  ('bad format', 'فرمت نامعتبر است'),
];

String cupErr(Object e) {
  final m = e is PostgrestException ? e.message : '$e';
  for (final (k, v) in _cupErr) {
    if (m.contains(k)) return v;
  }
  return errFa(e);
}

/// Server clock offset so countdowns match the server's decisions (lineup window, check-in).
class CupClock {
  static Duration skew = Duration.zero;
  static DateTime now() => DateTime.now().toUtc().add(skew);
  static void fromServer(Object? iso, DateTime sentAt) {
    final s = DateTime.tryParse('${iso ?? ''}');
    if (s == null) return;
    final back = DateTime.now().toUtc();
    final mid = sentAt.toUtc().add(back.difference(sentAt.toUtc()) ~/ 2);
    skew = s.toUtc().difference(mid);
  }

  static Future<void> sync() async {
    try {
      final t0 = DateTime.now();
      CupClock.fromServer(await rpc('cup_now'), t0);
    } catch (_) {}
  }
}

/// Which cup page / cup room is on screen (the alert layer stays quiet for it).
class CupUi {
  static String? openCup;
  static bool inCupRoom = false;
}

DateTime? _ts(Rec r, String k) => DateTime.tryParse(r.s(k))?.toUtc();

const kCupStatus = {'registration': ('ثبت‌نام', C.green), 'running': ('در جریان', C.orange), 'finished': ('پایان‌یافته', C.dim), 'cancelled': ('لغو شد', C.red)};

Widget _cupPage(BuildContext context, String title, VoidCallback onBack, List<Widget> children, {Future<void> Function()? onRefresh}) {
  final list = ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24), children: [Header(title: title, en: 'TOURNAMENT', onBack: onBack), ...children]);
  return Scaffold(
    backgroundColor: C.bg,
    body: Stack(children: [const Space(theme: SpaceTheme.base, dim: .15), onRefresh != null ? RefreshIndicator(onRefresh: onRefresh, color: C.orange, child: list) : list]),
  );
}

Widget _label(String s) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: tBold(s, size: 13, color: C.dim, align: TextAlign.right));

Widget _stepper(String text, VoidCallback? minus, VoidCallback? plus) => Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(onPressed: minus, icon: Icon(Icons.remove_circle_outline, color: minus == null ? C.dim2 : C.dim)),
      SizedBox(width: 72, child: tBold(text, size: 15, align: TextAlign.center)),
      IconButton(onPressed: plus, icon: Icon(Icons.add_circle_outline, color: plus == null ? C.dim2 : C.dim)),
    ]);

// ------------------------------------------------------------------ list
class CupsScreen extends StatefulWidget {
  final VoidCallback onBack;
  final void Function(String id) onOpen;
  const CupsScreen({super.key, required this.onBack, required this.onOpen});
  @override
  State<CupsScreen> createState() => _CupsScreenState();
}

class _CupsScreenState extends State<CupsScreen> {
  String tab = 'open';
  List<Rec>? list;
  Map<String, int> counts = {};
  final code = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    CupClock.sync();
    load();
  }

  Future<void> load() async {
    setState(() => list = null);
    try {
      final uid = Auth.i.uid;
      List<Rec> rows;
      if (tab == 'mine') {
        final ids = uid == null ? <String>[] : [for (final r in recs(await sb.from('cup_players').select('cup_id').eq('user_id', uid).neq('status', 'out'))) r.s('cup_id')];
        final mineQ = sb.from('cups').select();
        rows = recs(await (ids.isEmpty ? mineQ.eq('created_by', uid ?? '') : mineQ.or('created_by.eq.$uid,id.in.(${ids.join(',')})')).order('starts_at', ascending: false).limit(50));
      } else if (tab == 'done') {
        rows = recs(await sb.from('cups').select().inFilter('status', ['finished', 'cancelled']).order('starts_at', ascending: false).limit(40));
      } else {
        rows = recs(await sb.from('cups').select().eq('status', tab == 'open' ? 'registration' : 'running').order('starts_at').limit(50));
      }
      final c = <String, int>{};
      if (rows.isNotEmpty) {
        for (final p in recs(await sb.from('cup_players').select('cup_id').inFilter('cup_id', [for (final r in rows) r.s('id')]).eq('status', 'main'))) {
          c[p.s('cup_id')] = (c[p.s('cup_id')] ?? 0) + 1;
        }
      }
      if (mounted) {
        setState(() {
          list = rows;
          counts = c;
        });
      }
    } catch (e) {
      if (mounted) setState(() => list = []);
    }
  }

  Future<void> join() async {
    final c = code.text.trim();
    if (!RegExp(r'^\d{5}$').hasMatch(c)) return toast('کد تورنمنت ۵ رقم است', 'err');
    setState(() => busy = true);
    try {
      final r = Rec.of(await rpc('cup_join', {'p_code': c}));
      toast('به تورنمنت «${r.s('name')}» پیوستی', 'ok');
      buzz('success');
      code.clear();
      widget.onOpen(r.s('id'));
    } catch (e) {
      toast(cupErr(e), 'err');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _cupPage(context, 'تورنمنت‌ها', widget.onBack, onRefresh: load, [
        Panel(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          accent: C.orange,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(textDirection: TextDirection.rtl, children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('cupCode'),
                  controller: code,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => join(),
                  style: ts(size: 20, family: F.num, weight: 800, spacing: 6),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'کد ۵ رقمی',
                    hintStyle: ts(size: 13, color: C.dim2, family: F.fa),
                    filled: true,
                    fillColor: const Color(0xcc060a22),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.line)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 110, child: Btn(busy ? '…' : 'پیوستن', small: true, colors: G.green, disabled: busy, onTap: join)),
            ]),
            const SizedBox(height: 10),
            Btn('ساخت تورنمنت', small: true, colors: G.gold, onTap: () => showSheet(context, title: 'ساخت تورنمنت', en: 'CREATE', accent: C.orange, height: .92, child: (ctx) => CreateCupSheet(onCreated: (id) {
                      Navigator.pop(ctx);
                      widget.onOpen(id);
                    }))),
          ]),
        ),
        Tabs2<String>(
            items: const [('open', 'ثبت‌نام'), ('running', 'در جریان'), ('mine', 'من'), ('done', 'تمام‌شده')],
            value: tab,
            onChange: (v) {
              tab = v;
              load();
            }),
        if (list == null)
          const LoadingList()
        else if (list!.isEmpty)
          const EmptyState('تورنمنتی اینجا نیست')
        else
          for (final t in list!)
            ListRow(
              icon: ui2('x_trophy'),
              title: t.s('name'),
              sub: '${jalaliLabel(_ts(t, 'starts_at') ?? DateTime.now())} · ${formatFa(t.i('games'))} · ${fa(counts[t.s('id')] ?? 0)}/${fa(t.i('max_players'))}${t.i('prize') > 0 ? ' · 💎${fa(t.i('prize'))}' : ''}',
              right: Badge2(kCupStatus[t.s('status')]?.$1 ?? '', color: kCupStatus[t.s('status')]?.$2 ?? C.dim, live: t.s('status') == 'running'),
              onTap: () => widget.onOpen(t.s('id')),
            ),
      ]);
}

// ------------------------------------------------------------------ create
class CreateCupSheet extends StatefulWidget {
  final void Function(String id) onCreated;
  const CreateCupSheet({super.key, required this.onCreated});
  @override
  State<CreateCupSheet> createState() => _CreateCupSheetState();
}

class _CreateCupSheetState extends State<CreateCupSheet> {
  final name = TextEditingController();
  int max = 16, games = 1, goals = 3, prize = 0, day = 0, hour = 20, minute = 0;
  List<int> split = kCupDefaultSplit;
  bool play = true, busy = false;

  @override
  void initState() {
    super.initState();
    // default start: the next round half hour that is at least 30 minutes away (Tehran time)
    final w = tehranWall(CupClock.now().add(const Duration(minutes: 30)));
    var h = w.hour, m = w.minute <= 30 ? 30 : 60;
    if (m == 60) {
      m = 0;
      h++;
    }
    if (h >= 24) {
      h = 0;
      day = 1;
    }
    hour = h;
    minute = m;
  }

  /// Tehran calendar day [i] days from today -> (jy, jm, jd, weekday)
  (int, int, int, int) _day(int i) {
    final w = tehranWall(CupClock.now()).add(Duration(days: i));
    final (jy, jm, jd) = gregorianToJalali(w.year, w.month, w.day);
    return (jy, jm, jd, w.weekday);
  }

  DateTime get startsUtc {
    final (jy, jm, jd, _) = _day(day);
    return fromTehranJalali(jy, jm, jd, hour, minute);
  }

  @override
  Widget build(BuildContext context) {
    final gems = Auth.i.profile?.i('gems') ?? 0;
    final st = startsUtc;
    final tooSoon = st.isBefore(CupClock.now().add(const Duration(minutes: 2)));
    final sh = prizeShares(prize, split);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
      Field2(name, label: 'نام تورنمنت', maxLength: 40),
      _label('ظرفیت (حداکثر ${fa(kCupMaxPlayers)} نفر)'),
      Segment<int>(value: max, onChange: (v) => setState(() => max = v), items: const [(4, '۴'), (8, '۸'), (16, '۱۶'), (32, '۳۲'), (64, '۶۴')], accent: C.green),
      Center(child: _stepper('${fa(max)} نفر', max > 2 ? () => setState(() => max--) : null, max < kCupMaxPlayers ? () => setState(() => max++) : null)),
      _label('فرمت هر مسابقه'),
      Wrap(textDirection: TextDirection.rtl, runSpacing: 6, children: [
        for (final g in const [1, 2, 3, 5]) Chip2(formatFa(g), on: games == g, onTap: () => setState(() => games = g), accent: C.violet),
      ]),
      Center(child: _stepper(formatFa(games), games > 1 ? () => setState(() => games--) : null, games < kCupMaxGames ? () => setState(() => games++) : null)),
      T(games == 1 ? 'برنده‌ی یک بازی بالا می‌رود' : 'هر کس زودتر بیش از نیمی از بازی‌ها را ببرد بالا می‌رود؛ تساوی با تفاضل گل و بعد بازی تعیین‌کننده', size: 11, color: C.dim2, align: TextAlign.right),
      _label('گل لازم برای بردن هر بازی'),
      Segment<int>(value: goals, onChange: (v) => setState(() => goals = v), items: const [(1, '۱'), (3, '۳'), (5, '۵')]),
      _label('زمان شروع (به وقت تهران)'),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, reverse: true, children: [
          for (var i = 0; i < 30; i++)
            Builder(builder: (_) {
              final (_, jm, jd, wd) = _day(i);
              final l = i == 0 ? 'امروز' : i == 1 ? 'فردا' : '${kFaWeekdays[wd]} ${faDigits('$jd')} ${kJalaliMonths[jm - 1]}';
              return Chip2(l, on: day == i, onTap: () => setState(() => day = i), accent: C.orange);
            }),
        ]),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, textDirection: TextDirection.ltr, children: [
        _stepper(faDigits(hour.toString().padLeft(2, '0')), () => setState(() => hour = (hour + 23) % 24), () => setState(() => hour = (hour + 1) % 24)),
        tTitle(':', size: 18),
        _stepper(faDigits(minute.toString().padLeft(2, '0')), () => setState(() => minute = (minute + 55) % 60), () => setState(() => minute = (minute + 5) % 60)),
      ]),
      T('${jalaliLabel(st, year: true)} تهران', size: 13, color: tooSoon ? C.red : C.text, align: TextAlign.center),
      if (tooSoon) const T('این زمان گذشته یا خیلی نزدیک است', size: 11, color: C.red, align: TextAlign.center),
      _label('جایزه (الماس، حداکثر ${fa(kCupMaxPrize)})'),
      Row(textDirection: TextDirection.rtl, children: [
        tBold('💎 ${fa(prize)}', size: 15, color: const Color(0xff9fd8ff)),
        Expanded(
          child: Slider(
            value: prize.toDouble(),
            min: 0,
            max: kCupMaxPrize.toDouble(),
            divisions: kCupMaxPrize ~/ 5,
            activeColor: const Color(0xff9fd8ff),
            onChanged: (v) => setState(() => prize = v.round()),
          ),
        ),
      ]),
      if (prize > 0) ...[
        T('از الماس تو برداشته و تا پایان تورنمنت امانت نگه داشته می‌شود (موجودی: ${fa(gems)})', size: 11, color: prize > gems ? C.red : C.dim2, align: TextAlign.right),
        _label('تقسیم بین نفرات اول تا سوم'),
        Wrap(textDirection: TextDirection.rtl, runSpacing: 6, children: [
          for (final s in kCupSplits) Chip2(faDigits(s.where((x) => x > 0).join('/')), on: split == s, onTap: () => setState(() => split = s), accent: C.gold),
        ]),
        T('اول ${fa(sh[0])} · دوم ${fa(sh[1])} · سوم ${fa(sh[2])} الماس', size: 12, color: C.gold, align: TextAlign.right),
      ],
      const SizedBox(height: 12),
      Row(textDirection: TextDirection.rtl, children: [
        const Expanded(child: T('خودم هم بازی می‌کنم', size: 13, align: TextAlign.right)),
        Toggle(on: play, onChange: (v) => setState(() => play = v)),
      ]),
      const SizedBox(height: 18),
      Btn(busy ? '…' : 'ساخت', colors: G.gold, disabled: busy || tooSoon || (prize > gems), onTap: () async {
        if (name.text.trim().length < 3) return toast('نام تورنمنت حداقل ۳ حرف', 'err');
        setState(() => busy = true);
        try {
          final t = Rec.of(await rpc('cup_create', {
            'p_name': name.text.trim(), 'p_max': max, 'p_games': games, 'p_goals': goals, 'p_starts': startsUtc.toIso8601String(),
            'p_prize': prize, 'p_split': split, 'p_join': play,
          }));
          Auth.i.refreshProfile();
          toast('تورنمنت ساخته شد · کد ${faDigits(t.s('code'))}', 'ok');
          widget.onCreated(t.s('id'));
        } catch (e) {
          toast(cupErr(e), 'err');
        } finally {
          if (mounted) setState(() => busy = false);
        }
      }),
    ]);
  }
}

// ------------------------------------------------------------------ cup page
class CupScreen extends StatefulWidget {
  final String id;
  final VoidCallback onBack;
  final void Function(Rec room) onRoom;
  const CupScreen({super.key, required this.id, required this.onBack, required this.onRoom});
  @override
  State<CupScreen> createState() => _CupScreenState();
}

class _CupScreenState extends State<CupScreen> {
  Rec? c;
  List<Rec> players = [], matches = [];
  Map<String, String> names = {};
  String? err, busy;
  String tab = 'bracket';
  RealtimeChannel? _ch;
  Timer? _soon, _tick;
  final Set<String> _auto = {};

  @override
  void initState() {
    super.initState();
    CupUi.openCup = widget.id;
    CupClock.sync();
    load();
    final id = widget.id;
    void soon() {
      _soon?.cancel();
      _soon = Timer(const Duration(milliseconds: 300), load);
    }

    _ch = sb
        .channel('cup:$id')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'cups', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id), callback: (_) => soon())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'cup_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'cup_id', value: id), callback: (_) => soon())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'cup_matches', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'cup_id', value: id), callback: (_) => soon())
        .subscribe();
    var n = 0;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {}); // countdowns
      if (++n % 15 == 0) load(); // realtime safety net
    });
  }

  @override
  void dispose() {
    if (CupUi.openCup == widget.id) CupUi.openCup = null;
    _soon?.cancel();
    _tick?.cancel();
    if (_ch != null) sb.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await Future.wait([
        sb.from('cups').select().eq('id', widget.id).maybeSingle(),
        sb.from('cup_players').select('*, profiles(username, avatar, avatar_url)').eq('cup_id', widget.id).order('joined_at'),
        sb.from('cup_matches').select().eq('cup_id', widget.id).order('kind').order('round').order('idx'),
      ]);
      if (!mounted) return;
      setState(() {
        err = null;
        c = r[0] == null ? null : Rec.of(r[0]);
        players = recs(r[1]);
        matches = recs(r[2]);
        names = {for (final p in players) p.s('user_id'): p.rec('profiles').s('username', 'بازیکن')};
      });
      _autoEnter();
    } catch (e) {
      if (mounted) setState(() => err = errFa(e));
    }
  }

  Rec? get myMatch {
    final uid = Auth.i.uid;
    if (uid == null) return null;
    return matches.where((m) => (m.s('p1') == uid || m.s('p2') == uid) && const ['pending', 'ready', 'live'].contains(m.s('status'))).firstOrNull;
  }

  /// the drawn pairing becomes ready -> straight into its room (both players do this, the server starts the game)
  void _autoEnter() {
    final m = myMatch;
    if (m == null || !(m.s('status') == 'ready' || m.s('status') == 'live') || _auto.contains(m.s('id')) || busy != null) return;
    _auto.add(m.s('id'));
    sfx(Snd.whistle);
    buzz('heavy');
    enter(m);
  }

  Future<void> enter(Rec m) => run('enter', () async {
        final t0 = DateTime.now();
        final r = Rec.of(await rpc('cup_enter', {'p_match': m.s('id')}));
        CupClock.fromServer(r['now'], t0);
        widget.onRoom(r.rec('room'));
      });

  Future<void> run(String k, Future<void> Function() fn, [String? ok]) async {
    if (busy != null) return;
    setState(() => busy = k);
    try {
      await fn();
      if (ok != null) {
        toast(ok, 'ok');
        buzz('success');
      }
    } catch (e) {
      toast(cupErr(e), 'err');
      buzz('heavy');
    } finally {
      if (mounted) setState(() => busy = null);
    }
    load();
  }

  String nm(String? uid) => uid == null || uid.isEmpty ? '—' : names[uid] ?? 'بازیکن';

  @override
  Widget build(BuildContext context) {
    final t = c;
    if (t == null) return _cupPage(context, 'تورنمنت', widget.onBack, [err != null ? ErrorState(err!, onRetry: load) : const LoadingList()]);
    final uid = Auth.i.uid;
    final now = CupClock.now();
    final starts = _ts(t, 'starts_at') ?? now;
    final me = players.where((p) => p.s('user_id') == uid && p.s('status') != 'out').firstOrNull;
    final mains = players.where((p) => p.s('status') == 'main').toList();
    final waits = players.where((p) => p.s('status') == 'wait').toList();
    final isOrg = t.s('created_by') == uid;
    final status = t.s('status');
    final (sl, sc) = kCupStatus[status] ?? ('', C.dim);
    final sh = prizeShares(t.i('prize'), [for (final x in (t['split'] as List? ?? kCupDefaultSplit)) (x as num).toInt()]);
    final checkinOpen = status == 'registration' && now.isAfter(starts.subtract(const Duration(minutes: kCupCheckinMinutes)));
    return _cupPage(context, t.s('name'), widget.onBack, onRefresh: load, [
      Panel(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        accent: sc,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(textDirection: TextDirection.rtl, children: [
            Badge2(sl, color: sc, live: status == 'running'),
            const Spacer(),
            Press(
              onTap: () {
                Clipboard.setData(ClipboardData(text: t.s('code')));
                toast('کد کپی شد', 'ok');
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.copy_rounded, size: 14, color: C.dim),
                const SizedBox(width: 4),
                T(t.s('code'), size: 20, family: F.num, weight: 800, spacing: 4, color: C.gold),
                const SizedBox(width: 6),
                const T('کد', size: 11, color: C.dim),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          T('${jalaliLabel(starts, year: true)} به وقت تهران', size: 13, align: TextAlign.right),
          if (status == 'registration' && starts.isAfter(now)) T('شروع تا ${faCountdown(starts.difference(now))}', size: 12, color: C.orange, align: TextAlign.right),
          const SizedBox(height: 6),
          Wrap(textDirection: TextDirection.rtl, runSpacing: 4, children: [
            Badge2(formatFa(t.i('games')), color: C.violet),
            Badge2('هر بازی ${fa(t.i('goals'))} گل', color: C.sky),
            Badge2('${fa(mains.length)}/${fa(t.i('max_players'))} بازیکن', color: C.green),
            if (waits.isNotEmpty) Badge2('${fa(waits.length)} در صف', color: C.orange),
            if (t.i('prize') > 0) Badge2('💎 ${fa(sh[0])} · ${fa(sh[1])} · ${fa(sh[2])}', color: const Color(0xff9fd8ff)),
          ]),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _actions(t, me, mains, waits, isOrg, checkinOpen, starts, now))),
      if (status == 'registration' || status == 'cancelled')
        ..._playerList(mains, waits, checkinOpen)
      else ...[
        Tabs2<String>(items: const [('bracket', 'براکت'), ('players', 'بازیکنان')], value: tab, onChange: (v) => setState(() => tab = v)),
        if (tab == 'players') ..._playerList(mains, waits, false) else ..._bracket(t, uid),
      ],
    ]);
  }

  List<Widget> _actions(Rec t, Rec? me, List<Rec> mains, List<Rec> waits, bool isOrg, bool checkinOpen, DateTime starts, DateTime now) {
    final status = t.s('status');
    final out = <Widget>[];
    if (status == 'registration') {
      if (me == null) {
        out.add(Btn(busy == 'join' ? '…' : mains.length >= t.i('max_players') ? 'ثبت‌نام در صف انتظار' : 'ثبت‌نام',
            colors: G.green, onTap: () => run('join', () async => rpc('cup_join', {'p_code': t.s('code')}), 'ثبت‌نام شدی')));
      } else {
        final wait = me.s('status') == 'wait';
        final pos = waits.indexWhere((p) => p.s('user_id') == me.s('user_id')) + 1;
        out.add(T(wait ? 'در صف انتظاری (نفر ${fa(pos)}) · اگر کسی غایب باشد جایش را می‌گیری' : 'ثبت‌نام شدی ✓', size: 13, color: wait ? C.orange : C.green, align: TextAlign.center));
        out.add(const SizedBox(height: 8));
        if (me.str('checked_in_at') != null) {
          out.add(const T('اعلام حضور کردی ✓ · قرعه‌کشی در زمان شروع', size: 13, color: C.green, align: TextAlign.center));
        } else if (checkinOpen) {
          out.add(Btn(busy == 'checkin' ? '…' : 'اعلام حضور', colors: G.green, onTap: () => run('checkin', () async => rpc('cup_checkin', {'p_cup': t.s('id')}), 'حضورت ثبت شد')));
        } else {
          out.add(T('اعلام حضور از ساعت ${tehranClock(starts.subtract(const Duration(minutes: kCupCheckinMinutes)))} باز می‌شود؛ بدون آن از قرعه‌کشی حذف می‌شوی', size: 12, color: C.dim, align: TextAlign.center));
        }
        out.add(const SizedBox(height: 8));
        out.add(Btn(busy == 'leave' ? '…' : 'انصراف', small: true, colors: G.dark, onTap: () => run('leave', () async => rpc('cup_leave', {'p_cup': t.s('id')}), 'از تورنمنت خارج شدی')));
      }
      if (isOrg) {
        out.add(const SizedBox(height: 8));
        out.add(Btn(busy == 'cancel' ? '…' : 'لغو تورنمنت', small: true, colors: G.red, onTap: () async {
          if (await confirm(context, 'لغو تورنمنت؟', t.i('prize') > 0 ? 'الماس‌های جایزه به حسابت برمی‌گردد.' : 'همه‌ی ثبت‌نام‌ها لغو می‌شود.', yes: 'لغو کن', no: 'نه')) {
            run('cancel', () async => rpc('cup_cancel', {'p_cup': t.s('id')}), 'تورنمنت لغو شد');
          }
        }));
      }
    } else if (status == 'running') {
      final m = myMatch;
      final uid = Auth.i.uid;
      if (m != null) {
        final opp = m.s('p1') == uid ? m.str('p2') : m.str('p1');
        final sched = _ts(m, 'scheduled_at');
        final ready = m.s('status') == 'ready' || m.s('status') == 'live';
        out.add(Panel(
          accent: ready ? C.red : C.orange,
          glowOn: ready,
          child: Column(children: [
            tBold('${roundNameFa(m.i('round'), t.i('rounds'), third: m.s('kind') == 'third')} · مسابقه‌ی تو', size: 12, color: ready ? C.red : C.orange),
            const SizedBox(height: 4),
            tTitle('${nm(uid)}  vs  ${opp == null ? 'منتظر حریف' : nm(opp)}', size: 15, lines: 1),
            if (m.i('games_played') > 0) T('نتیجه‌ی سری: ${fa(m.s('p1') == uid ? m.i('wins1') : m.i('wins2'))} - ${fa(m.s('p1') == uid ? m.i('wins2') : m.i('wins1'))}', size: 12, color: C.dim),
            const SizedBox(height: 8),
            if (ready)
              Btn(busy == 'enter' ? '…' : 'ورود به مسابقه', colors: G.red, onTap: () => enter(m))
            else
              T(opp == null ? 'بعد از پایان مسابقه‌ی قبلی حریفت معلوم می‌شود' : 'شروع خودکار ساعت ${tehranClock(sched ?? CupClock.now())}${sched != null && sched.isAfter(CupClock.now()) ? ' (${faCountdown(sched.difference(CupClock.now()))})' : ''}',
                  size: 12, color: C.dim, align: TextAlign.center),
            const SizedBox(height: 4),
            const T('این صفحه را باز نگه دار تا خودکار وارد مسابقه شوی', size: 10, color: C.dim2, align: TextAlign.center),
          ]),
        ));
      } else if (me != null && me.b('eliminated')) {
        out.add(const T('از تورنمنت حذف شدی · نتیجه‌ها را دنبال کن', size: 13, color: C.dim, align: TextAlign.center));
      }
    } else if (status == 'finished') {
      final podium = players.where((p) => p.i('final_place') >= 1 && p.i('final_place') <= 3).toList()..sort((a, b) => a.i('final_place').compareTo(b.i('final_place')));
      final sh = prizeShares(t.i('prize'), [for (final x in (t['split'] as List? ?? kCupDefaultSplit)) (x as num).toInt()]);
      out.add(Panel(
        accent: C.gold,
        child: Column(children: [
          for (final p in podium)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(textDirection: TextDirection.rtl, children: [
                T(const ['🥇', '🥈', '🥉'][p.i('final_place') - 1], size: 20),
                const SizedBox(width: 8),
                Expanded(child: tBold(nm(p.s('user_id')), size: 14, lines: 1)),
                if (t.i('prize') > 0 && sh[p.i('final_place') - 1] > 0) T('💎 ${fa(sh[p.i('final_place') - 1])}', size: 13, color: const Color(0xff9fd8ff)),
              ]),
            ),
        ]),
      ));
    } else if (status == 'cancelled') {
      out.add(T('لغو شد · ${t.s('cancelled_reason')}', size: 13, color: C.red, align: TextAlign.center));
    }
    return out;
  }

  List<Widget> _playerList(List<Rec> mains, List<Rec> waits, bool showCheckin) => [
        _sectionTitle('بازیکنان (${fa(mains.length)})'),
        if (mains.isEmpty) const EmptyState('هنوز کسی ثبت‌نام نکرده'),
        for (final p in mains) _playerRow(p, showCheckin),
        if (waits.isNotEmpty) ...[_sectionTitle('صف انتظار'), for (final p in waits) _playerRow(p, showCheckin)],
      ];

  Widget _playerRow(Rec p, bool showCheckin) => ListRow(
        leading: Avatar(avatar: p.rec('profiles').str('avatar'), url: p.rec('profiles').str('avatar_url'), size: 32),
        title: nm(p.s('user_id')),
        right: p.i('final_place') == 1
            ? const Badge2('قهرمان', color: C.gold)
            : p.b('eliminated')
                ? const Badge2('حذف', color: C.red)
                : showCheckin && p.str('checked_in_at') != null
                    ? const Badge2('حاضر', color: C.green)
                    : p.i('seed') > 0
                        ? T('#${fa(p.i('seed'))}', size: 12, color: C.dim)
                        : null,
      );

  Widget _sectionTitle(String s) => Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6), child: tBold(s, size: 13, color: C.cyan, align: TextAlign.right));

  List<Widget> _bracket(Rec t, String? uid) {
    final out = <Widget>[];
    final rounds = t.i('rounds');
    for (var r = 1; r <= rounds; r++) {
      final ms = matches.where((m) => m.s('kind') == 'main' && m.i('round') == r).toList();
      if (ms.isEmpty) continue;
      final sched = _ts(ms.first, 'scheduled_at');
      out.add(_sectionTitle('${roundNameFa(r, rounds)}${sched != null ? ' · ${tehranClock(sched)}' : ''}'));
      out.addAll(ms.map((m) => _matchRow(m, uid)));
    }
    final third = matches.where((m) => m.s('kind') == 'third').toList();
    if (third.isNotEmpty) {
      out.add(_sectionTitle('رده‌بندی (مقام سوم)'));
      out.addAll(third.map((m) => _matchRow(m, uid)));
    }
    return out;
  }

  Widget _matchRow(Rec m, String? uid) {
    final st = m.s('status');
    final mine = m.s('p1') == uid || m.s('p2') == uid;
    final w = m.str('winner');
    Color col(String k) => w != null && w == m.str(k) ? C.gold : C.text;
    final mid = st == 'bye'
        ? 'بای'
        : st == 'done' || m.i('games_played') > 0
            ? '${fa(m.i('wins1'))} : ${fa(m.i('wins2'))}'
            : 'vs';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xd10a0e28), borderRadius: BorderRadius.circular(12), border: Border.all(color: mine ? C.cyan : C.line)),
      child: Row(textDirection: TextDirection.rtl, children: [
        Expanded(child: T(nm(m.str('p1')), size: 12, lines: 1, color: col('p1'))),
        T(mid, size: 13, family: F.title, weight: 900, color: C.dim),
        Expanded(child: T(m.str('p2') == null && st == 'bye' ? '—' : nm(m.str('p2')), size: 12, lines: 1, align: TextAlign.left, color: col('p2'))),
        if (st == 'live') const Badge2('زنده', color: C.red, live: true),
        if (st == 'ready') const Badge2('آماده', color: C.orange),
        if (m.b('walkover')) const Badge2('غیبت', color: C.dim),
      ]),
    );
  }
}

// ------------------------------------------------------------------ cup room (series, lineup window, auto start)
bool isCupRoom(Rec? room) => room != null && room.str('cup_match_id') != null;

class CupLobby extends StatefulWidget {
  final RoomLink link;
  final VoidCallback onLeave;
  const CupLobby({super.key, required this.link, required this.onLeave});
  @override
  State<CupLobby> createState() => _CupLobbyState();
}

class _CupLobbyState extends State<CupLobby> {
  Rec? m, cup;
  Map<String, String> names = {};
  RealtimeChannel? _ch;
  Timer? _tick;
  DateTime _lastKick = DateTime(2000);
  int _lastSec = -1;

  String get matchId => widget.link.room?.s('cup_match_id') ?? '';

  @override
  void initState() {
    super.initState();
    CupUi.inCupRoom = true;
    widget.link.addListener(_onLink);
    load();
    _ch = sb
        .channel('cupm:$matchId')
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'cup_matches', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: matchId), callback: (p) {
          if (mounted) setState(() => m = Rec(Map<String, dynamic>.from(p.newRecord)));
        })
        .subscribe();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
  }

  @override
  void dispose() {
    CupUi.inCupRoom = false;
    widget.link.removeListener(_onLink);
    _tick?.cancel();
    if (_ch != null) sb.removeChannel(_ch!);
    super.dispose();
  }

  void _onLink() => mounted ? setState(() {}) : null;

  Future<void> load() async {
    try {
      final r = Rec.of(await sb.from('cup_matches').select().eq('id', matchId).maybeSingle());
      final cu = Rec.of(await sb.from('cups').select().eq('id', r.s('cup_id')).maybeSingle());
      final ids = [r.s('p1'), r.s('p2')].where((x) => x.isNotEmpty).toList();
      final ps = recs(await sb.from('profiles').select('id, username').inFilter('id', ids));
      if (!mounted) return;
      setState(() {
        m = r;
        cup = cu;
        names = {for (final p in ps) p.s('id'): p.s('username')};
      });
      _kick();
    } catch (_) {}
  }

  Future<void> _kick() async {
    _lastKick = DateTime.now();
    try {
      final t0 = DateTime.now();
      final r = Rec.of(await rpc('cup_kick', {'p_match': matchId}));
      CupClock.fromServer(r['now'], t0);
      if (mounted && m != null) setState(() => m = m!.merge({'lineup_until': r['lineup_until'], 'status': r['status'], 'games_played': r['games_played']}));
    } catch (_) {}
  }

  void _onTick() {
    if (!mounted) return;
    final mm = m;
    final playing = widget.link.room?.s('status') == 'playing';
    if (mm == null || playing || !const ['ready', 'live'].contains(mm.s('status'))) return;
    final lu = _ts(mm, 'lineup_until');
    final since = DateTime.now().difference(_lastKick);
    if (lu != null) {
      final left = lu.difference(CupClock.now());
      final sec = left.inMilliseconds <= 0 ? 0 : (left.inMilliseconds / 1000).ceil();
      if (sec != _lastSec) {
        _lastSec = sec;
        if (sec > 0 && sec <= kCupLineupSeconds) sfx(Snd.tick);
        setState(() {});
      }
      // the window is over: ask the server to start (it checks the time and both seats itself)
      if (left.inMilliseconds <= 0 && since > const Duration(milliseconds: 900)) _kick();
    } else if (since > const Duration(seconds: 3)) {
      _kick(); // arms the lineup window once both players sit in the room
    }
  }

  String nm(String? uid) => uid == null ? '—' : names[uid] ?? 'بازیکن';

  Future<void> _leave() async {
    final done = m != null && const ['done', 'bye'].contains(m!.s('status'));
    if (done || await confirm(context, 'خروج از مسابقه؟', 'اگر تا ${fa(kCupNoShowMinutes)} دقیقه برنگردی با غیبت می‌بازی.', yes: 'خروج', no: 'ماندن')) widget.onLeave();
  }

  @override
  Widget build(BuildContext context) {
    final mm = m, uid = Auth.i.uid;
    final cu = cup;
    if (mm == null || cu == null) return Scaffold(backgroundColor: C.bg, body: Stack(children: [const Space(), Center(child: Spinner(size: 40))]));
    final me1 = mm.s('p1') == uid;
    final opp = me1 ? mm.str('p2') : mm.str('p1');
    final myW = me1 ? mm.i('wins1') : mm.i('wins2'), opW = me1 ? mm.i('wins2') : mm.i('wins1');
    final st = mm.s('status');
    final oppHere = opp != null && widget.link.online.containsKey(opp);
    final lu = _ts(mm, 'lineup_until');
    final left = lu?.difference(CupClock.now());
    final secs = left == null ? null : (left.inMilliseconds <= 0 ? 0 : (left.inMilliseconds / 1000).ceil());
    final finished = st == 'done' || st == 'bye';
    final won = finished && mm.str('winner') == uid;
    final gameNo = mm.i('games_played') + 1;
    Widget status;
    if (finished) {
      status = Column(children: [
        tTitle(won ? 'بردی! 🏆' : 'این سری را باختی', size: 20, color: won ? C.gold : C.red),
        const SizedBox(height: 4),
        T(won ? 'به مرحله‌ی بعد رفتی؛ زمان مسابقه‌ی بعدی در صفحه‌ی تورنمنت است' : 'از تورنمنت حذف شدی', size: 12, color: C.dim, align: TextAlign.center),
        const SizedBox(height: 12),
        Btn('بازگشت به تورنمنت', colors: G.gold, onTap: widget.onLeave),
      ]);
    } else if (!oppHere) {
      status = Column(children: [
        const Spinner(size: 28),
        const SizedBox(height: 8),
        T('منتظر ورود حریف… (حداکثر ${fa(kCupNoShowMinutes)} دقیقه، بعد برد با غیبت)', size: 12, color: C.dim, align: TextAlign.center),
      ]);
    } else if (secs != null && secs <= kCupLineupSeconds) {
      status = Column(children: [
        const T('ترکیب و تیمت را انتخاب کن', size: 13, color: C.orange),
        tTitle(fa(secs), size: 54, color: C.orange),
      ]);
    } else if (secs != null) {
      status = T('بازی ${fa(gameNo)} تا ${fa(secs)} ثانیه‌ی دیگر', size: 14, color: C.text, align: TextAlign.center);
    } else {
      status = const T('آماده‌سازی…', size: 13, color: C.dim);
    }
    return Scaffold(
        backgroundColor: C.bg,
        body: Stack(children: [
          const Space(theme: SpaceTheme.base, dim: .15),
          ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24), children: [
            Header(title: cu.s('name'), en: 'CUP MATCH', onBack: _leave),
            Panel(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              accent: C.orange,
              child: Column(children: [
                tBold('${roundNameFa(mm.i('round'), cu.i('rounds'), third: mm.s('kind') == 'third')} · ${formatFa(cu.i('games'))}', size: 12, color: C.orange),
                const SizedBox(height: 10),
                Row(textDirection: TextDirection.rtl, children: [
                  Expanded(child: Column(children: [tBold(nm(uid), size: 14, lines: 1, color: C.cyan), const T('تو', size: 10, color: C.dim)])),
                  tTitle('${fa(myW)} - ${fa(opW)}', size: 28),
                  Expanded(child: Column(children: [tBold(nm(opp), size: 14, lines: 1), T(oppHere ? 'آنلاین' : 'آفلاین', size: 10, color: oppHere ? C.green : C.dim2)])),
                ]),
                if (!finished) T('بازی ${fa(gameNo)}${gameNo > cu.i('games') ? ' (تعیین‌کننده)' : ' از ${fa(cu.i('games'))}'} · ${fa(cu.i('goals'))} گل برنده است', size: 11, color: C.dim),
                const SizedBox(height: 14),
                status,
              ]),
            ),
            if (!finished) ...[
              const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 6), child: T('ترکیب', size: 13, color: C.dim, align: TextAlign.right)),
              SizedBox(
                height: 92,
                child: ListView(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (var i = 0; i < kForms.length; i++)
                    Press(
                      key: ValueKey('cupForm$i'),
                      onTap: () {
                        Store.i.set((p) => p.form = i);
                        setState(() {});
                      },
                      child: Container(
                        width: 58,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Store.i.p.form == i ? C.cyan : const Color(0x33ffffff), width: Store.i.p.form == i ? 2.4 : 1)),
                              clipBehavior: Clip.antiAlias,
                              child: CustomPaint(painter: MiniFormationPainter(i), child: const SizedBox.expand()),
                            ),
                          ),
                          const SizedBox(height: 3),
                          T(kForms[i].code, size: 10, color: Store.i.p.form == i ? C.cyan : C.dim),
                        ]),
                      ),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(textDirection: TextDirection.rtl, children: [
                  Disc(teamImgById(Store.i.p.team), size: 44),
                  const SizedBox(width: 10),
                  Expanded(child: tBold(teamById(Store.i.p.team).name, size: 13, lines: 1, align: TextAlign.right)),
                  SizedBox(width: 120, child: Btn('تغییر تیم', small: true, colors: G.dark, onTap: () => _pickTeam(context))),
                ]),
              ),
            ],
          ]),
        ]),
    );
  }

  void _pickTeam(BuildContext context) => showSheet(context, title: 'انتخاب تیم', en: 'TEAM', height: .7, child: (ctx) {
        final teams = kTeams.where((t) => ownsTeam(t.id)).toList();
        return GridView.count(
          crossAxisCount: 5,
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            for (final t in teams)
              Press(
                onTap: () {
                  Store.i.set((p) => p.team = t.id);
                  Navigator.pop(ctx);
                  if (mounted) setState(() {});
                },
                child: Disc(teamImg(t), size: 54, ring: t.id == Store.i.p.team ? C.cyan : C.line),
              ),
          ],
        );
      });
}
