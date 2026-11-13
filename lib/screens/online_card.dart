// Prominent "آنلاین" entry card (Home + Play) — port of src/screens/OnlineCard.tsx: 3D tilt on press, shine sweep.
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../nav.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

class OnlineCard extends StatefulWidget {
  final void Function([OnlineEntry e]) onOnline;
  const OnlineCard({super.key, required this.onOnline});
  @override
  State<OnlineCard> createState() => _OnlineCardState();
}

class _OnlineCardState extends State<OnlineCard> {
  double rx = 0, ry = 0;
  @override
  Widget build(BuildContext context) {
    final links = [(OnlineEntry.arena, 'آرنا', UI2['x_crown']), (OnlineEntry.tours, 'تورنمنت', UI2['x_trophy']), (OnlineEntry.leagues, 'لیگ', UI2['x_medal']), (OnlineEntry.challenges, 'چالش', UI2['c_calendar'])];
    return Column(children: [
      GestureDetector(
        onTapDown: (d) => setState(() {
          ry = (d.localPosition.dx / 340 - .5) * -10;
          rx = (d.localPosition.dy / 120 - .5) * 10;
        }),
        onTapUp: (_) => setState(() => rx = ry = 0),
        onTapCancel: () => setState(() => rx = ry = 0),
        onTap: () {
          sfx(Sfx.ui);
          buzz(Buzz.medium);
          widget.onOnline(OnlineEntry.hub);
        },
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(end: Offset(rx, ry)),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          builder: (_, o, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 1 / 700)
              ..rotateX(o.dx * math.pi / 180)
              ..rotateY(o.dy * math.pi / 180),
            child: child,
          ),
          child: Container(
            height: 112,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: rgba(160, 220, 255, .55), width: 1.5),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [hex('#3a1d8a'), hex('#1b2f8f'), hex('#0a5a8a')]),
              boxShadow: [BoxShadow(color: C.violet.withValues(alpha: .7), blurRadius: 18)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Positioned(left: 0, right: 0, top: 0, height: 56, child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x4DFFFFFF), Color(0x00FFFFFF)])))),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.rotate(angle: .35, child: Container(width: 50, height: 220, color: const Color(0x38FFFFFF))),
                ).animate(onPlay: (c) => c.repeat()).moveX(begin: -120, end: 520, delay: 1800.ms, duration: 1300.ms, curve: Curves.easeInOutQuad),
              ),
              Center(
                child: Row(textDirection: TextDirection.rtl, children: [
                  Img(UI['portal_globe'], w: 84, h: 84),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ListenableBuilder(
                        listenable: Auth.I,
                        builder: (_, _) {
                          final prof = Auth.I.profile;
                          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Row(textDirection: TextDirection.rtl, mainAxisSize: MainAxisSize.min, children: [
                              T('آنلاین', style: fs(F.title, 24, color: Colors.white, shadows: [Shadow(color: C.cyan, blurRadius: 12)])),
                              Container(
                                height: 18, margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), color: C.red),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 4), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))
                                      .animate(onPlay: (c) => c.repeat(reverse: true))
                                      .fade(begin: .3, end: 1, duration: 600.ms),
                                  T('LIVE', style: fs(F.head, 9, ls: 1, color: Colors.white)),
                                ]),
                              ),
                            ]),
                            T('مسابقه با بازیکن‌های واقعی · ۱ به ۱، ۲ به ۲، ۳ به ۳', n: 2, align: TextAlign.right, style: fs(F.body, 12, color: hex('#d6e6ff'))),
                            if (prof != null) T('امتیاز ${fa(ri(prof, 'rating'))} · 💎 ${fa(ri(prof, 'gems'))}', style: fs(F.bold, 11, color: C.gold)),
                          ]);
                        },
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(textDirection: TextDirection.rtl, children: [
        for (final (i, (k, l, img)) in links.indexed)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i < links.length - 1 ? 8 : 0),
              child: Press(
                onPress: () => widget.onOnline(k),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: rgba(10, 16, 44, .85), border: Border.all(color: C.line)),
                  child: Row(textDirection: TextDirection.rtl, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Img(img, w: 26, h: 26),
                    Flexible(child: Padding(padding: const EdgeInsets.only(right: 4), child: T(l, n: 1, style: fs(F.bold, 11)))),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    ]);
  }
}
