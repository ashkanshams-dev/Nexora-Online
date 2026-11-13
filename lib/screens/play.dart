// Play — port of src/screens/Play.tsx: online card, 3D cover-flow of offline modes, league road.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../nav.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';
import 'online_card.dart';
import 'setup.dart';

const _MEDAL = ['medal_bronze', 'medal_silver', 'medal_gold', 'medal_epic', 'shield_epic', 'shield_crown'];

class Play extends StatefulWidget {
  final double top, bottom;
  final void Function(Mode m) onMode;
  final void Function([OnlineEntry e]) onOnline;
  const Play({super.key, required this.top, required this.bottom, required this.onMode, required this.onOnline});
  @override
  State<Play> createState() => _PlayState();
}

class _PlayState extends State<Play> {
  PageController? _pc;
  int idx = 0;

  @override
  void dispose() {
    _pc?.dispose();
    super.dispose();
  }

  List<Color> _grad(ModeKey k) => k == ModeKey.cup ? G.gold : k == ModeKey.galaxy ? G.violet : k == ModeKey.local ? G.green : G.primary;

  @override
  Widget build(BuildContext context) {
    final W = MediaQuery.sizeOf(context).width;
    final cw = math.min(W * .72, 330.0), gap = 14.0;
    _pc ??= PageController(viewportFraction: (cw + gap) / W);
    final m = MODES[idx];
    return ListenableBuilder(
      listenable: Store.I,
      builder: (context, _) {
        final p = Store.I.p, lg = league(p.trophies);
        return ListView(padding: EdgeInsets.only(top: widget.top, bottom: widget.bottom + 10), children: [
          Enter(
            i: 0,
            child: Column(children: [
              T('PORTAL · SELECT', style: fs(F.head, 10, ls: 5, color: C.cyan)),
              T('انتخاب حالت بازی', style: fs(F.title, 22)),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: OnlineCard(onOnline: widget.onOnline)),
          const Title2('آفلاین', en: 'OFFLINE · BOT & LOCAL'),
          SizedBox(
            height: cw * 1.32 + 32,
            child: PageView.builder(
              controller: _pc,
              itemCount: MODES.length,
              onPageChanged: (i) => setState(() => idx = i),
              itemBuilder: (_, i) => AnimatedBuilder(
                animation: _pc!,
                builder: (_, child) {
                  final page = _pc!.hasClients && _pc!.position.haveDimensions ? _pc!.page ?? idx.toDouble() : idx.toDouble();
                  final d = page - i, ad = d.abs();
                  final op = ad < 1 ? 1 - ad * .45 : (.55 - (ad - 1) * .3).clamp(.25, .55);
                  return Opacity(
                    opacity: op,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 1 / 900)
                        ..rotateY(d.clamp(-1, 1) * -28 * math.pi / 180)
                        ..scaleByDouble(1 - ad.clamp(0, 1) * .16, 1 - ad.clamp(0, 1) * .16, 1, 1),
                      child: _Card(m: MODES[i], w: cw, parallax: d, onPress: () => widget.onMode(MODES[i])),
                    ),
                  );
                },
              ),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final (i, mm) in MODES.indexed)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: i == idx ? 26 : 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: mm.color().withValues(alpha: i == idx ? 1 : .35)),
              ),
          ]),
          Padding(padding: const EdgeInsets.fromLTRB(24, 14, 24, 0), child: Btn(label: 'ورود به ${m.name}', colors: _grad(m.k), onPress: () => widget.onMode(m))),
          Title2('جاده‌ی لیگ', en: 'LEAGUE ROAD', accent: C.gold),
          SizedBox(
            height: 112,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final (i, (n, t)) in LEAGUES.indexed)
                Row(children: [
                  if (i > 0) Container(width: 26, height: 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: p.trophies >= t ? C.gold : const Color(0x1FFFFFFF))),
                  Container(
                    width: 86, padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: i == lg.idx ? C.gold : C.line),
                      color: i == lg.idx ? rgba(255, 210, 87, .12) : rgba(8, 12, 34, .8),
                      boxShadow: i == lg.idx ? [BoxShadow(color: C.gold.withValues(alpha: .8), blurRadius: 12)] : null,
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Opacity(opacity: p.trophies >= t ? 1 : .35, child: Img(UI[_MEDAL[i]], w: 54, h: 54)),
                      T(LEAGUE_FA[n]!, style: fs(F.body, 11, color: p.trophies >= t ? Colors.white : C.dim2)),
                      T(fa(t), style: fs(F.head, 9, color: p.trophies >= t ? C.gold : C.dim2)),
                    ]),
                  ),
                ]),
            ]),
          ),
        ]);
      },
    );
  }
}

class _Card extends StatelessWidget {
  final Mode m;
  final double w, parallax;
  final VoidCallback onPress;
  const _Card({required this.m, required this.w, required this.parallax, required this.onPress});
  @override
  Widget build(BuildContext context) {
    final c = m.color();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 7),
      child: Press(
        onPress: onPress,
        scaleTo: .97,
        child: Container(
          height: w * 1.32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: c.withValues(alpha: .53), width: 1.5),
            color: hex('#0a1030'),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: .33), rgba(14, 22, 64, .85), rgba(5, 8, 24, .98)]),
            boxShadow: [BoxShadow(color: c.withValues(alpha: .6), blurRadius: 18)],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(alignment: Alignment.topCenter, children: [
            Positioned(top: 10, child: Opacity(opacity: .42, child: Img(UI2['portal'], w: w * 1.05, h: w * .7))),
            Positioned(
              top: w * .1,
              child: Transform.translate(
                offset: Offset(parallax * 40, 0),
                child: Stack(alignment: Alignment.center, children: [
                  Pulse(size: w * .45, color: c.withValues(alpha: .33)),
                  Float(amp: 6, dur: 2600, child: Img(m.img, w: w * .58, h: w * .62)),
                ]),
              ),
            ),
            Positioned(
              bottom: 18, left: 16, right: 16,
              child: Column(children: [
                T(m.en, style: fs(F.head, 10, ls: 3, color: c)),
                T(m.name, style: fs(F.title, 24, shadows: [Shadow(color: c, blurRadius: 14)])),
                Padding(padding: const EdgeInsets.only(top: 4), child: T(m.desc, n: 2, align: TextAlign.center, style: fs(F.body, 12, color: hex('#c6dbff')))),
                Container(
                  margin: const EdgeInsets.only(top: 8), height: 28, padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: .4)), color: const Color(0x40000000)),
                  child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
                    Padding(padding: const EdgeInsets.only(left: 4), child: Img(UI2['c_coin'], w: 20, h: 20)),
                    Flexible(child: T(m.reward, n: 1, style: fs(F.body, 11, color: hex('#ffe9a8')))),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
