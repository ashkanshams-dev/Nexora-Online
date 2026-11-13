// Home — port of src/screens/Home.tsx: hologram hero (selected disc on a floating pedestal, parallax tilt),
// play button with shine sweep, 4 quick actions, daily reward and daily challenges.
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/util.dart';
import '../nav.dart';
import '../online/challenges.dart';
import '../store.dart';
import '../ui/kit.dart';
import '../ui/menu_assets.dart';
import '../ui/theme.dart';
import 'setup.dart';

class Home extends StatefulWidget {
  final double top, bottom;
  final void Function([OnlineEntry e]) onOnline;
  final void Function(Mode m) onMode;
  final void Function(String t) onTab;
  final VoidCallback onDaily, onChest;
  final bool dailyReady, chestReady;
  const Home({super.key, required this.top, required this.bottom, required this.onOnline, required this.onMode, required this.onTab, required this.onDaily, required this.onChest, required this.dailyReady, required this.chestReady});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final sy = ValueNotifier(0.0);
  @override
  Widget build(BuildContext context) {
    final W = MediaQuery.sizeOf(context).width;
    final heroW = math.min(W * .5, 240.0);
    final nav = NavScope.of(context);
    final quick = [
      (MENU.ic_friends, 'آنلاین', () => widget.onOnline(OnlineEntry.hub), false),
      (MENU.ic_trophy, 'جام نکسورا', () => widget.onMode(MODES[1]), false),
      (MENU.shield_star, 'تیم من', () => widget.onTab('team'), false),
      (MENU.ic_gift, 'صندوقچه', widget.onChest, widget.chestReady),
    ];
    return ListenableBuilder(
      listenable: Store.I,
      builder: (context, _) {
        final p = Store.I.p, me = teamById(p.team);
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            sy.value = n.metrics.pixels;
            return false;
          },
          child: ListView(padding: EdgeInsets.only(top: widget.top, bottom: widget.bottom + SP.l), children: [
            ValueListenableBuilder<double>(
              valueListenable: sy,
              builder: (_, y, child) => Opacity(
                opacity: (1 - (y / 260) * .65).clamp(.35, 1),
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 1 / 800)
                    ..translateByDouble(0, y * .35, 0, 1)
                    ..rotateX((y / 240).clamp(0, 1) * 18 * math.pi / 180),
                  child: child,
                ),
              ),
              child: SizedBox(
                height: heroW + 120,
                child: Stack(alignment: Alignment.bottomCenter, children: [
                  Positioned(top: 0, child: Img(MENU.logo, w: math.min(W * .62, 300), h: math.min(W * .62, 300) * .48)),
                  Positioned(bottom: 40, child: Pulse(size: heroW * .9, color: rgba(79, 140, 255, .28))),
                  Positioned(bottom: 0, child: Img(MENU.pedestal, w: heroW * 1.5, h: heroW * 1.5 * .42)),
                  Positioned(
                    bottom: 46,
                    child: Container(
                      width: heroW * .78, height: heroW * .78, alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: BG0, border: Border.all(color: rgba(120, 220, 255, .85), width: 3), boxShadow: glow(C.cyan, 22, .75)),
                      child: ClipOval(child: Img(teamImg(teamKey(me)), w: heroW * .74, h: heroW * .74)),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .custom(
                          duration: 2800.ms,
                          curve: Curves.easeInOutSine,
                          builder: (_, t, c) => Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..translateByDouble(0, -(6 + t * 10), 0, 1)
                              ..setEntry(3, 2, 1 / 600)
                              ..rotateY((t - .5) * 14 * math.pi / 180),
                            child: c,
                          ),
                        ),
                  ),
                ]),
              ),
            ),
            Center(
              child: Press(
                onPress: () => widget.onTab('team'),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: SP.l, vertical: 12), child: T('${me.name}  ·  تغییر تیم ›', n: 1, style: fs(F.bold, TY.small, color: C.dim))),
              ),
            ),
            Enter(i: 0, child: Padding(padding: const EdgeInsets.fromLTRB(SP.l, SP.s, SP.l, 0), child: _PlayButton(onPress: () => widget.onMode(MODES[0])))),
            Enter(
              i: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(SP.m, SP.l, SP.m, 0),
                child: Row(textDirection: TextDirection.rtl, children: [
                  for (final (img, label, on, dot) in quick)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: SP.xs),
                        child: Press(
                          onPress: on,
                          child: Container(
                            height: 84,
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: rgba(10, 14, 40, .82), border: Border.all(color: C.line)),
                            child: Stack(children: [
                              Center(
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Img(img, w: 40, h: 40),
                                  Padding(padding: const EdgeInsets.only(top: SP.xs), child: T(label, n: 1, style: fs(F.bold, TY.cap))),
                                ]),
                              ),
                              if (dot) Positioned(top: 6, right: 10, child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: C.red, border: Border.all(color: hex('#0b1236'), width: 2)))),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            Section(
              title: 'جایزه‌ی روزانه',
              child: Enter(
                i: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SP.l),
                  child: Press(
                    onPress: widget.onDaily,
                    scaleTo: .98,
                    child: Panel(
                      accent: widget.dailyReady ? C.gold : null,
                      noAccent: !widget.dailyReady,
                      glow: widget.dailyReady,
                      pad: const EdgeInsets.all(SP.m),
                      child: Row(textDirection: TextDirection.rtl, children: [
                        Img(MENU.ic_gift, w: 40, h: 40),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: SP.m),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              T(widget.dailyReady ? 'جایزه‌ی امروز آماده‌ست!' : 'روز ${fa(p.streak)} از ۷', style: fs(F.bold, TY.body)),
                              T(widget.dailyReady ? 'سکه و الماس رایگان؛ هر روز بزرگ‌تر' : 'فردا دوباره سر بزن', style: fs(F.body, TY.cap, color: C.dim)),
                            ]),
                          ),
                        ),
                        Container(
                          height: 36, constraints: const BoxConstraints(minWidth: 64), padding: const EdgeInsets.symmetric(horizontal: SP.m), alignment: Alignment.center,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: widget.dailyReady ? C.gold : C.line)),
                          child: T(widget.dailyReady ? 'دریافت' : 'جزئیات', style: fs(F.bold, TY.small, color: widget.dailyReady ? C.gold : C.dim)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            Section(
              title: 'چالش‌های امروز',
              action: 'همه ›',
              onAction: () => widget.onOnline(OnlineEntry.challenges),
              child: Enter(i: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: SP.l), child: HomeChallenges(toast: nav.toast, onAll: () => widget.onOnline(OnlineEntry.challenges)))),
            ),
          ]),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  final VoidCallback onPress;
  const _PlayButton({required this.onPress});
  @override
  Widget build(BuildContext context) => Press(
        onPress: onPress,
        scaleTo: .96,
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x80FFFFFF), width: 1.5),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: G.primary),
            boxShadow: [BoxShadow(color: C.cyan.withValues(alpha: .7), blurRadius: 20)],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned(left: 0, right: 0, top: 0, height: 37, child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66FFFFFF), Color(0x0DFFFFFF), Color(0x00FFFFFF)])))),
            Positioned(
              top: -40, left: 0,
              child: Transform.rotate(angle: 20 * math.pi / 180, child: Container(width: 60, height: 160, color: const Color(0x47FFFFFF))),
            ).animate(onPlay: (c) => c.repeat()).moveX(begin: -160, end: 400, duration: 1600.ms, curve: Curves.easeInOutQuad).then(delay: 900.ms),
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Padding(padding: const EdgeInsets.only(right: SP.s), child: Img(MENU.ic_play, w: 40, h: 40)),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  T('شروع بازی', style: fs(F.title, 22, color: Colors.white, shadows: const [Shadow(color: Color(0x80000028), blurRadius: 8)])),
                  T('QUICK MATCH', style: fs(F.head, 9, ls: 3, color: const Color(0xD9FFFFFF))),
                ]),
              ]),
            ),
          ]),
        ),
      );
}
