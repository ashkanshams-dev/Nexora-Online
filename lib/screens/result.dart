// Result — port of src/screens/Result.tsx: spinning ring + banner spring, score panel, counting rewards, oracle line.
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/util.dart';
import '../oracle/oracle_lines.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'match.dart';

class Reward {
  int coins, xp, trophies, gems;
  Reward(this.coins, this.xp, this.trophies, this.gems);
}

class CupState {
  final int stage;
  final bool won, champion;
  const CupState(this.stage, this.won, this.champion);
}

class ResultScreen extends StatelessWidget {
  final MatchResult r;
  final Reward? reward;
  final List<String> names;
  final VoidCallback onAgain, onHome;
  final CupState? cup;
  final int? levelUp;
  const ResultScreen({super.key, required this.r, required this.reward, required this.names, required this.onAgain, required this.onHome, this.cup, this.levelUp});

  Widget _side(String? img, String name, Color c) => Expanded(
        child: Column(children: [
          Container(
            width: 58, height: 58, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: 2), color: hex('#050816')),
            child: ClipOval(child: Img(img, w: 52, h: 52)),
          ),
          Padding(padding: const EdgeInsets.only(top: 4), child: T(name, n: 1, style: fs(F.bold, 12))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final W = MediaQuery.sizeOf(context).width, ins = MediaQuery.paddingOf(context);
    final a = r.score[0], b = r.score[1];
    final out = a > b ? 'victory' : a < b ? 'defeat' : 'draw';
    final line = resultLine(out);
    final col = out == 'victory' ? C.gold : out == 'defeat' ? C.red : C.cyan;
    final bw = math.min(W * .9, 380.0);
    return ListView(padding: EdgeInsets.fromLTRB(16, ins.top + 10, 16, ins.bottom + 24), children: [
      SizedBox(
        height: bw * .66,
        child: Stack(alignment: Alignment.center, children: [
          Opacity(opacity: .5, child: Img(UI2['ring'], w: bw * .95, h: bw * .95)).animate(onPlay: (c) => c.repeat()).rotate(duration: 20.seconds),
          Pulse(size: bw * .5, color: col.withValues(alpha: .27)),
          Img(UI[out], w: bw, h: bw * .62).animate().scale(begin: const Offset(.4, .4), duration: 900.ms, curve: Curves.elasticOut).fadeIn(duration: 250.ms),
        ]),
      ),
      Panel(
        accent: col,
        glow: true,
        pad: const EdgeInsets.all(14),
        child: Row(children: [
          _side(teamImg(teamKey(r.teams[0])), names[0], C.cyan),
          Column(children: [
            Text('$a : $b', style: fs(F.title, 40, shadows: [Shadow(color: col, blurRadius: 16)])),
            T('FINAL', style: fs(F.head, 9, ls: 4, color: C.dim)),
          ]),
          _side(teamImg(teamKey(r.teams[1])), names[1], C.red),
        ]),
      ),
      if (reward != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(textDirection: TextDirection.rtl, children: [
            _Rw(img: UI2['c_coin'], v: reward!.coins, c: C.gold, d: 200),
            _Rw(img: UI2['x_star'], v: reward!.xp, c: C.cyan, d: 350, label: 'XP'),
            _Rw(img: UI2['x_trophy'], v: reward!.trophies, c: reward!.trophies >= 0 ? C.green : C.red, d: 500),
            if (reward!.gems > 0) _Rw(img: UI2['x_gem'], v: reward!.gems, c: hex('#9fd8ff'), d: 650),
          ]),
        ),
      if (levelUp != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Panel(
            accent: C.violet,
            glow: true,
            pad: const EdgeInsets.all(12),
            child: Row(textDirection: TextDirection.rtl, children: [
              Img(UI2['x_crown'], w: 50, h: 50),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    T('سطح ${fa(levelUp!)}!', style: fs(F.title, 18, color: hex('#d6b8ff'))),
                    T('به سطح جدید رسیدی · ۱۰۰+ سکه هدیه', style: fs(F.body, 11, color: C.dim)),
                  ]),
                ),
              ),
            ]),
          ).animate(delay: 700.ms).shimmer(duration: 1200.ms),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(textDirection: TextDirection.rtl, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Float(amp: 4, child: Img(oracleImg(line.mood), w: 96, h: 104)),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 8, bottom: 24),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4)),
                color: rgba(14, 30, 80, .9),
                border: Border.all(color: rgba(92, 225, 255, .4)),
              ),
              child: T(line.text, align: TextAlign.right, style: fs(F.body, 12, color: hex('#e6f4ff'), height: 1.6)),
            ),
          ),
        ]),
      ),
      if (cup != null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: T(
              cup!.champion ? 'قهرمان جام نکسورا! ۴۰۰+ سکه' : cup!.won ? 'مرحله‌ی ${const ['یک', 'دو', 'سه'][cup!.stage.clamp(0, 2)]} از سه رد شد' : 'از جام حذف شدی',
              align: TextAlign.center,
              style: fs(F.title, 16, color: cup!.won ? C.gold : C.red)),
        ),
      const SizedBox(height: 14),
      Btn(label: cup != null ? (cup!.won && !cup!.champion ? 'مرحله‌ی بعد' : 'جام دوباره') : 'بازی دوباره', colors: out == 'victory' ? G.gold : G.primary, onPress: onAgain),
      const SizedBox(height: 10),
      Btn(label: 'بازگشت به خانه', small: true, colors: G.dark, onPress: onHome),
    ]);
  }
}

class _Rw extends StatelessWidget {
  final String? img;
  final int v, d;
  final Color c;
  final String? label;
  const _Rw({required this.img, required this.v, required this.c, required this.d, this.label});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Panel(
            accent: c,
            pad: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Img(img, w: 40, h: 40),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: v.toDouble()),
                duration: 600.ms,
                curve: Interval(d / 1200, 1),
                builder: (_, n, _) => Text('${n >= 0 ? '+' : ''}${n.round()}${label != null ? ' $label' : ''}', style: fs(F.title, 15, color: c)),
              ),
            ]),
          ),
        ).animate(delay: d.ms).scale(begin: const Offset(.5, .5), curve: Curves.elasticOut, duration: 700.ms).fadeIn(),
      );
}
