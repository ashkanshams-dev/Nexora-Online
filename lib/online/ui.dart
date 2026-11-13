// Shared online building blocks — port of src/online/ui.tsx (Header, Skeleton, Empty, ErrorState, Badge, Card, Tabs, StatBars).
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import '../game/data.dart';
import '../game/util.dart';
import '../sound.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

class S {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 24;
}

class TS {
  static const double title = 20, h = 16, body = 14, small = 12, cap = 11, tiny = 10;
}

Team teamOfAvatar(String? key) => TEAMS.firstWhere((t) => t.id == key || teamKey(t) == key, orElse: () => TEAMS[0]);
String discImgOf(String? key) => teamImg(teamKey(teamOfAvatar(key))) ?? TEAM_IMG['club00']!;

class AvatarO extends StatelessWidget {
  final String? avatar, url;
  final double size;
  final Color? ring;
  final bool dim;
  const AvatarO({super.key, this.avatar, this.url, this.size = 40, this.ring, this.dim = false});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: dim ? .5 : 1,
        child: Container(
          width: size, height: size, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring ?? C.cyan, width: 2), color: hex('#050816')),
          child: ClipOval(child: Img(url ?? discImgOf(avatar), w: size - 6, h: size - 6, fit: url != null ? BoxFit.cover : BoxFit.contain)),
        ),
      );
}

/// header with a 44pt back button (positioned at the top of a Stack)
class Header extends StatelessWidget {
  final String title;
  final String? en;
  final VoidCallback onBack;
  final Widget? right;
  final Color? accent;
  const Header({super.key, required this.title, this.en, required this.onBack, this.right, this.accent});
  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    return Positioned(
      left: 0, right: 0, top: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(S.m, ins.top + S.s, S.m, S.m),
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [rgba(2, 4, 14, .95), rgba(2, 4, 14, .7), rgba(2, 4, 14, 0)])),
        child: Row(children: [
          Press(
            onPress: onBack,
            child: Container(
              width: 44, height: 44, margin: const EdgeInsets.only(right: S.s), alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: rgba(8, 14, 40, .85), border: Border.all(color: C.line)),
              child: T('‹', style: fs(F.title, 26, color: C.text, height: 1)),
            ),
          ),
          ConstrainedBox(constraints: const BoxConstraints(minWidth: 44), child: right ?? const SizedBox.shrink()),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: S.s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (en != null) T(en!, n: 1, style: fs(F.head, 9, ls: 3, color: accent ?? C.cyan)),
                T(title, n: 1, style: fs(F.title, TS.title)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class Skeleton extends StatelessWidget {
  final int rows;
  final double h;
  const Skeleton({super.key, this.rows = 4, this.h = 72});
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < rows; i++)
          Container(
            height: h, margin: const EdgeInsets.only(bottom: S.s),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: rgba(60, 90, 180, .18), border: Border.all(color: C.line)),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: .35, end: .7, duration: 900.ms, curve: Curves.easeInOutSine).shimmer(duration: 1400.ms, color: const Color(0x22FFFFFF)),
      ]);
}

class Empty extends StatelessWidget {
  final String? img;
  final String title;
  final String? sub, action;
  final VoidCallback? onAction;
  const Empty({super.key, this.img, required this.title, this.sub, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: S.xl, horizontal: S.xl),
        child: Column(children: [
          Opacity(opacity: .85, child: Img(img ?? UI2['x_ball'], w: 72, h: 72)),
          Padding(padding: const EdgeInsets.only(top: S.s), child: T(title, align: TextAlign.center, style: fs(F.bold, TS.h))),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: S.xs), child: T(sub!, align: TextAlign.center, style: fs(F.body, TS.small, color: C.dim))),
          if (action != null && onAction != null) Padding(padding: const EdgeInsets.only(top: S.l), child: SizedBox(width: 180, child: Btn(label: action!, small: true, colors: G.dark, onPress: onAction))),
        ]),
      ).animate().fadeIn(duration: 300.ms);
}

class ErrorState extends StatelessWidget {
  final String msg;
  final VoidCallback? onRetry;
  const ErrorState({super.key, required this.msg, this.onRetry});
  @override
  Widget build(BuildContext context) => Empty(img: UI2['c_bell'], title: 'مشکلی پیش اومد', sub: msg, action: onRetry != null ? 'تلاش دوباره' : null, onAction: onRetry);
}

class Badge2 extends StatelessWidget {
  final String label;
  final Color? color;
  final bool live;
  const Badge2({super.key, required this.label, this.color, this.live = false});
  @override
  Widget build(BuildContext context) {
    final c = color ?? C.cyan;
    return Container(
      height: 22, margin: const EdgeInsets.only(left: S.xs), padding: const EdgeInsets.symmetric(horizontal: S.s),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), border: Border.all(color: c.withValues(alpha: .53)), color: c.withValues(alpha: .13)),
      child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: [
        if (live)
          Container(width: 6, height: 6, margin: const EdgeInsets.only(left: 4), decoration: BoxDecoration(shape: BoxShape.circle, color: c))
              .animate(onPlay: (x) => x.repeat(reverse: true))
              .fade(begin: .4, end: 1, duration: 700.ms),
        T(label, n: 1, style: fs(F.bold, TS.tiny, color: c)),
      ]),
    );
  }
}

class Card2 extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final VoidCallback? onPress;
  const Card2({super.key, required this.child, this.accent, this.onPress});
  @override
  Widget build(BuildContext context) {
    final body = Panel(accent: accent, noAccent: accent == null, pad: const EdgeInsets.all(S.m), child: child);
    return onPress != null ? Press(onPress: onPress, scaleTo: .98, child: body) : body;
  }
}

class Tabs2<K> extends StatelessWidget {
  final List<(K, String)> items;
  final K value;
  final ValueChanged<K> onChange;
  const Tabs2({super.key, required this.items, required this.value, required this.onChange});
  @override
  Widget build(BuildContext context) => Container(
        height: 44, padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: rgba(6, 10, 30, .8), border: Border.all(color: C.line)),
        child: Row(textDirection: TextDirection.rtl, children: [
          for (final (k, l) in items)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  buzz();
                  onChange(k);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(19),
                    color: k == value ? rgba(79, 227, 255, .22) : Colors.transparent,
                    border: Border.all(color: k == value ? C.cyan : Colors.transparent),
                  ),
                  child: T(l, n: 1, style: fs(F.bold, TS.small, color: k == value ? Colors.white : C.dim)),
                ),
              ),
            ),
        ]),
      );
}

class StatBars extends StatelessWidget {
  final int power, accuracy;
  final bool compact;
  const StatBars({super.key, required this.power, required this.accuracy, this.compact = false});
  Widget _row(String label, int v, Color c) => Padding(
        padding: EdgeInsets.only(top: compact ? 2 : 4),
        child: Row(textDirection: TextDirection.rtl, children: [
          SizedBox(width: compact ? 26 : 34, child: T(label, align: TextAlign.right, style: fs(F.body, compact ? 9 : TS.tiny, color: C.dim))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(textDirection: TextDirection.rtl, children: [
                for (var i = 0; i < 10; i++)
                  Expanded(child: Container(height: compact ? 4 : 6, margin: const EdgeInsets.only(left: 1.5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: i < v ? c : const Color(0x1AFFFFFF)))),
              ]),
            ),
          ),
          if (!compact) SizedBox(width: 20, child: T(faNum(v), style: fs(F.bold, TS.tiny, color: c))),
        ]),
      );
  @override
  Widget build(BuildContext context) => Column(children: [_row('قدرت', power, C.orange), _row('دقت', accuracy, C.cyan)]);
}
