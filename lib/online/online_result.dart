// Online result — port of src/online/OnlineResult.tsx: score, XP / coins / rating actually granted (profile diff), level-up.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/util.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../oracle/oracle_lines.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'online_match.dart';
import 'ui.dart';

class OnlineResultScreen extends StatefulWidget {
  final OnlineOutcome o;
  final JRow? before;
  final VoidCallback onLobby, onLeave;
  const OnlineResultScreen({super.key, required this.o, required this.before, required this.onLobby, required this.onLeave});
  @override
  State<OnlineResultScreen> createState() => _OnlineResultScreenState();
}

class _OnlineResultScreenState extends State<OnlineResultScreen> {
  JRow? after;
  bool alive = true;
  late final String out = widget.o.myTeam == null || widget.o.winner == -1 ? 'draw' : widget.o.winner == widget.o.myTeam ? 'victory' : 'defeat';
  late final line = resultLine(out);

  @override
  void initState() {
    super.initState();
    if (widget.o.myTeam != null) {
      if (out == 'victory') {
        sfx(Sfx.win);
        buzz(Buzz.success);
      } else if (out == 'defeat') {
        sfx(Sfx.lose);
        buzz(Buzz.heavy);
      }
      if (widget.o.reported) _try(0);
    }
  }

  @override
  void dispose() {
    alive = false;
    super.dispose();
  }

  // the backend has granted rewards by now; poll the profile a couple of times in case realtime is late
  Future<void> _try(int n) async {
    final p = await Auth.I.refreshProfile();
    if (!alive) return;
    final b = widget.before;
    if (p != null && (b == null || p['xp'] != b['xp'] || n >= 2)) {
      setState(() => after = p);
    } else if (n < 2) {
      Timer(const Duration(milliseconds: 1200), () => _try(n + 1));
    } else {
      setState(() => after = p ?? {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.o, b = widget.before, a = after, ins = MediaQuery.paddingOf(context), W = MediaQuery.sizeOf(context).width;
    final col = out == 'victory' ? C.gold : out == 'defeat' ? C.red : C.cyan, bw = math.min(W * .9, 380.0);
    int? d(String k) => a != null && b != null && a[k] != null ? ri(a, k) - ri(b, k) : null;
    final dRating = d('rating') ?? o.ratingDelta ?? 0, dArena = d('arena_points');
    final lvUp = a != null && b != null && ri(a, 'level') > ri(b, 'level') ? ri(a, 'level') : null;
    final lp = a != null && a['xp'] != null ? levelProgress(ri(a, 'xp')) : null;
    return ListView(
      padding: EdgeInsets.fromLTRB(S.l, ins.top + S.s, S.l, ins.bottom + S.xl),
      children: [
        Center(
          child: SizedBox(
            width: bw, height: bw * .62,
            child: Stack(alignment: Alignment.center, children: [
              Opacity(opacity: .5, child: Img(UI2['ring'], w: bw * .9, h: bw * .9)).animate(onPlay: (c) => c.repeat()).rotate(duration: 20.seconds),
              Pulse(size: bw * .5, color: col.withValues(alpha: .27)),
              Img(UI[out], w: bw, h: bw * .6).animate().scaleXY(begin: .4, end: 1, duration: 700.ms, curve: Curves.elasticOut).fadeIn(duration: 300.ms),
            ]),
          ),
        ),
        Panel(
          accent: col,
          glow: true,
          pad: const EdgeInsets.all(S.m),
          child: Row(children: [
            _side(teamImg(teamKey(o.teams[0])), o.names[0], C.cyan),
            Column(children: [
              T('${o.score[0]} : ${o.score[1]}', style: fs(F.title, 38, shadows: [Shadow(color: col, blurRadius: 16)])),
              T(o.ranked ? 'RANKED' : 'FRIENDLY', style: fs(F.head, 9, ls: 3, color: C.dim)),
            ]),
            _side(teamImg(teamKey(o.teams[1])), o.names[1], C.red),
          ]),
        ),
        if (o.myTeam == null)
          Padding(padding: const EdgeInsets.only(top: S.m), child: T('تو تماشاگر این بازی بودی', align: TextAlign.center, style: fs(F.body, TS.small, color: C.dim)))
        else if (!o.reported)
          Padding(
            padding: const EdgeInsets.only(top: S.m),
            child: Panel(accent: C.orange, pad: const EdgeInsets.all(S.m), child: T('نتیجه روی سرور ثبت نشد؛ جایزه‌ای اعمال نشد.', align: TextAlign.center, style: fs(F.body, TS.small, color: C.orange))),
          )
        else if (a == null)
          SizedBox(height: 120, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Spinner(), const SizedBox(height: S.s), T('در حال دریافت جوایز…', style: fs(F.body, TS.cap, color: C.dim))]))
        else ...[
          const SizedBox(height: S.m),
          rrow([
            Expanded(child: _Rw(img: UI2['x_star'], v: d('xp') ?? 0, c: C.cyan, delay: 150, label: 'XP')),
            Expanded(child: _Rw(img: UI2['c_coin'], v: d('coins') ?? 0, c: C.gold, delay: 300)),
            Expanded(child: _Rw(img: UI2['x_trophy'], v: dRating, c: dRating >= 0 ? C.green : C.red, delay: 450, label: 'امتیاز')),
            if (dArena != null && dArena != 0) Expanded(child: _Rw(img: UI2['x_crown'], v: dArena, c: C.violet, delay: 600, label: 'آرنا')),
          ]),
          if (lp != null)
            Padding(
              padding: const EdgeInsets.only(top: S.s),
              child: Panel(
                noAccent: true,
                pad: const EdgeInsets.all(S.m),
                child: Column(children: [
                  rrow(main: MainAxisAlignment.spaceBetween, [T('سطح ${fa(lp.level)}', style: fs(F.bold, TS.body)), T('${fa(lp.cur)} / ${fa(lp.need)} XP', style: fs(F.body, TS.cap, color: C.dim))]),
                  const SizedBox(height: S.s),
                  Bar(v: lp.frac, color: C.cyan, color2: C.violet, h: 8),
                ]),
              ),
            ),
          if (lvUp != null)
            Padding(
              padding: const EdgeInsets.only(top: S.s),
              child: Panel(
                accent: C.violet,
                glow: true,
                pad: const EdgeInsets.all(S.m),
                child: rrow([
                  Img(UI2['x_crown'], w: 48, h: 48),
                  const SizedBox(width: S.m),
                  Expanded(child: rcol([T('سطح ${fa(lvUp)}!', style: fs(F.title, 18, color: hex('#d6b8ff'))), T('به سطح جدید رسیدی', style: fs(F.body, TS.cap, color: C.dim))])),
                ]),
              ).animate().scaleXY(begin: .6, curve: Curves.elasticOut, duration: 900.ms),
            ),
        ],
        if (o.myTeam != null)
          Padding(
            padding: const EdgeInsets.only(top: S.m),
            child: rrow(cross: CrossAxisAlignment.end, [
              Float(amp: 4, child: Img(oracleImg(line.mood), w: 84, h: 92)),
              const SizedBox(width: S.s),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: S.l),
                  padding: const EdgeInsets.all(S.m),
                  decoration: BoxDecoration(
                    color: rgba(14, 24, 64, .92),
                    border: Border.all(color: rgba(92, 225, 255, .4)),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4)),
                  ),
                  child: T(line.text, align: TextAlign.right, style: fs(F.body, TS.small, height: 1.6)),
                ),
              ),
            ]).animate(delay: 500.ms).fadeIn().slideY(begin: .2),
          ),
        const SizedBox(height: S.l),
        Btn(label: 'بازگشت به لابی', colors: out == 'victory' ? G.gold : G.primary, onPress: widget.onLobby),
        const SizedBox(height: S.s),
        Btn(label: 'خروج از اتاق', small: true, colors: G.dark, onPress: widget.onLeave),
      ],
    );
  }

  Widget _side(String? img, String name, Color c) => Expanded(
        child: Column(children: [
          Container(
            width: 54, height: 54, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: 2), color: hex('#050816')),
            child: ClipOval(child: Img(img, w: 48, h: 48)),
          ),
          const SizedBox(height: S.xs),
          T(name, n: 1, style: fs(F.bold, TS.small)),
        ]),
      );
}

class _Rw extends StatefulWidget {
  final String? img, label;
  final int v, delay;
  final Color c;
  const _Rw({required this.img, required this.v, required this.c, required this.delay, this.label});
  @override
  State<_Rw> createState() => _RwState();
}

class _RwState extends State<_Rw> {
  int n = 0, k = 0;
  Timer? _t0, _t;
  @override
  void initState() {
    super.initState();
    _t0 = Timer(Duration(milliseconds: widget.delay), () {
      _t = Timer.periodic(const Duration(milliseconds: 30), (t) {
        k++;
        if (!mounted) return t.cancel();
        setState(() => n = (widget.v * k / 20).round());
        if (k >= 20) t.cancel();
      });
    });
  }

  @override
  void dispose() {
    _t0?.cancel();
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(S.xs),
        child: Panel(
          accent: widget.c,
          pad: const EdgeInsets.symmetric(vertical: S.s),
          child: Column(children: [
            Img(widget.img, w: 36, h: 36),
            const SizedBox(height: 2),
            T('${n >= 0 ? '+' : ''}${fa(n)}', style: fs(F.title, 15, color: widget.c)),
            if (widget.label != null) T(widget.label!, style: fs(F.body, TS.tiny, color: C.dim)),
          ]),
        ),
      ).animate(delay: widget.delay.ms).fadeIn(duration: 250.ms).scaleXY(begin: .5, curve: Curves.elasticOut, duration: 700.ms);
}
