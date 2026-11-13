// UI kit — port of src/ui/kit.tsx on Material 3 primitives (same sizes, gradients, radii, springs).
import 'dart:math' as math;

import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import '../i18n/i18n.dart';
import '../sound.dart';
import 'theme.dart';

final _FA = RegExp(r'[\u0600-\u06FF]');
bool hasFa(String s) => _FA.hasMatch(s);

/// Text: Persian strings switch to Vazirmatn automatically (Orbitron/Exo have no Persian glyphs),
/// drop letter-spacing (breaks joining) and render RTL — same rule as the RN `T` component.
class T extends StatelessWidget {
  final Object s;
  final TextStyle? style;
  final int? n;
  final TextAlign? align;
  const T(this.s, {super.key, this.style, this.n, this.align});

  static TextStyle styleFor(String text, TextStyle? style) {
    var st = fs(F.body, 14).merge(style);
    if (hasFa(text)) {
      final fam = st.fontFamily;
      final w = st.fontVariations?.firstOrNull?.value ?? 600;
      final heavy = (fam == 'Orbitron') || (fam == 'Exo2' && w >= 800);
      final size = st.fontSize ?? 14;
      st = st.copyWith(
        fontFamily: 'Vazirmatn',
        fontVariations: [FontVariation('wght', heavy ? 800 : 500)],
        fontWeight: heavy ? FontWeight.w800 : FontWeight.w500,
        letterSpacing: 0,
        fontSize: heavy ? (size * (size < 12 ? 1.2 : 1.03)).roundToDouble() : size,
      );
    }
    return st;
  }

  @override
  Widget build(BuildContext context) {
    final text = s is String ? tr(s as String) : '$s';
    final rtl = hasFa(text);
    return Text(
      text,
      maxLines: n,
      overflow: n != null ? TextOverflow.ellipsis : null,
      textAlign: align,
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      style: styleFor(text, style),
    );
  }
}

/// cached asset image (RN expo-image)
class Img extends StatelessWidget {
  final String? src;
  final double? w, h;
  final BoxFit fit;
  final Color? tint;
  final double radius;
  const Img(this.src, {super.key, this.w, this.h, this.fit = BoxFit.contain, this.tint, this.radius = 0});
  @override
  Widget build(BuildContext context) {
    if (src == null) return SizedBox(width: w, height: h);
    final isNet = src!.startsWith('http');
    Widget im = isNet
        ? Image.network(src!, width: w, height: h, fit: fit, color: tint, gaplessPlayback: true, errorBuilder: (_, _, _) => SizedBox(width: w, height: h))
        : Image.asset(src!, width: w, height: h, fit: fit, color: tint, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    if (radius > 0) im = ClipRRect(borderRadius: BorderRadius.circular(radius), child: im);
    return im;
  }
}

/// Press: spring scale, sound + haptic on tap
class Press extends StatefulWidget {
  final VoidCallback? onPress, onLongPress;
  final Widget child;
  final bool disabled, sound, haptic;
  final double scaleTo;
  const Press({super.key, this.onPress, required this.child, this.disabled = false, this.sound = true, this.scaleTo = .94, this.haptic = true, this.onLongPress});
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: 1);
  void _spring(double to, double damping, double stiffness) =>
      _c.animateWith(SpringSimulation(SpringDescription(mass: 1, stiffness: stiffness, damping: damping), _c.value, to, 0));
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dis = widget.disabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: dis ? null : (_) => _spring(widget.scaleTo, 18, 420),
      onTapUp: dis ? null : (_) => _spring(1, 12, 300),
      onTapCancel: dis ? null : () => _spring(1, 12, 300),
      onLongPress: dis ? null : widget.onLongPress,
      onTap: dis
          ? null
          : () {
              if (widget.sound) sfx(Sfx.ui);
              if (widget.haptic) buzz(Buzz.light);
              widget.onPress?.call();
            },
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.scale(scale: _c.value, child: Opacity(opacity: dis ? .45 : 1, child: child)),
        child: widget.child,
      ),
    );
  }
}

/// glass panel with gradient body, top highlight and accent line
class Panel extends StatelessWidget {
  final Widget? child;
  final Color? accent;
  final bool glow, noAccent;
  final EdgeInsetsGeometry? pad;
  final double radius;
  const Panel({super.key, this.child, this.accent, this.glow = false, this.pad, this.radius = 20, this.noAccent = false});
  @override
  Widget build(BuildContext context) {
    final a = accent ?? C.lineHi;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: glow ? a.withValues(alpha: .4) : C.line),
        color: C.panel2,
        boxShadow: glow ? [BoxShadow(color: a.withValues(alpha: .5), blurRadius: 16)] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: const Alignment(-.3, 1),
                colors: [rgba(34, 52, 124, .62), rgba(12, 18, 52, .86), rgba(6, 9, 28, .94)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0, right: 0, top: 0,
          child: FractionallySizedBox(
            widthFactor: 1,
            child: Container(height: 60, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x1AFFFFFF), Color(0x00FFFFFF)]))),
          ),
        ),
        if (!noAccent) Positioned(top: 0, left: 28, right: 28, child: Container(height: 2, decoration: BoxDecoration(color: a.withValues(alpha: .9), borderRadius: BorderRadius.circular(2)))),
        Padding(padding: pad ?? EdgeInsets.zero, child: child ?? const SizedBox.shrink()),
      ]),
    );
  }
}

class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onPress;
  final List<Color>? colors;
  final String? icon, sub;
  final bool small, disabled, dark, expand;
  const Btn({super.key, required this.label, this.onPress, this.colors, this.icon, this.small = false, this.disabled = false, this.sub, this.dark = false, this.expand = true});
  @override
  Widget build(BuildContext context) {
    final cs = colors ?? G.primary;
    final r = small ? 14.0 : 18.0;
    return Press(
      onPress: onPress,
      disabled: disabled,
      child: Container(
        height: small ? 44 : 58,
        padding: EdgeInsets.symmetric(horizontal: small ? 16 : 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: const Color(0x59FFFFFF)),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cs),
          boxShadow: [BoxShadow(color: cs.last.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Stack(alignment: Alignment.center, children: [
          Positioned(
            left: 0, right: 0, top: 0,
            height: (small ? 44 : 58) * .52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(r)),
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x61FFFFFF), Color(0x0FFFFFFF), Color(0x00FFFFFF)]),
              ),
            ),
          ),
          Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) Padding(padding: const EdgeInsets.only(right: 8), child: Img(icon, w: small ? IC.s : IC.m, h: small ? IC.s : IC.m)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              T(label,
                  style: fs(F.title, small ? 14 : 18,
                      ls: small ? 1.5 : 3,
                      color: dark ? hex('#06122a') : Colors.white,
                      shadows: dark ? null : const [Shadow(color: Color(0x73000000), blurRadius: 6)])),
              if (sub != null) T(sub!, style: fs(F.head, 10, ls: 1.5, color: const Color(0xD9FFFFFF))),
            ]),
          ]),
        ]),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String icon;
  final Object v;
  final Color? tint;
  final VoidCallback? onPress;
  final bool plus;
  const Pill({super.key, required this.icon, required this.v, this.tint, this.onPress, this.plus = false});
  @override
  Widget build(BuildContext context) {
    final body = Container(
      height: 32,
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: rgba(6, 10, 30, .78), border: Border.all(color: C.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Transform.translate(offset: const Offset(-6, 0), child: Img(icon, w: IC.m, h: IC.m)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: T(v is num ? fmtEn(v as num) : '$v', key: ValueKey(v), style: fs(F.head, 12, color: tint ?? C.text)),
          ),
        ),
        if (plus)
          Container(
            width: 20, height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.green),
            child: T('+', style: fs(F.title, 12, color: hex('#04122a'))),
          ),
      ]),
    );
    return onPress != null ? Press(onPress: onPress, child: body) : body;
  }
}

String fmtEn(num n) => n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

class Bar extends StatelessWidget {
  final double v, h;
  final Color? color, color2;
  const Bar({super.key, required this.v, this.color, this.color2, this.h = 8});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: h,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(h), color: const Color(0x14FFFFFF), border: Border.all(color: const Color(0x1AFFFFFF), width: .5)),
      clipBehavior: Clip.antiAlias,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: math.max(.02, math.min(1, v))),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, w, _) => Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: w,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(h), gradient: LinearGradient(colors: [color2 ?? C.indigo, color ?? C.cyan])),
              child: Align(alignment: Alignment.topCenter, child: FractionallySizedBox(heightFactor: .45, widthFactor: 1, child: Container(color: const Color(0x4DFFFFFF)))),
            ),
          ),
        ),
      ),
    );
  }
}

class Chip2 extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onPress;
  final Color? accent;
  final String? icon;
  const Chip2({super.key, required this.label, this.on = false, this.onPress, this.accent, this.icon});
  @override
  Widget build(BuildContext context) {
    final a = accent ?? C.cyan;
    return Press(
      onPress: onPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 36,
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? a : C.line),
          color: on ? a.withValues(alpha: .16) : rgba(8, 12, 34, .7),
          boxShadow: on ? [BoxShadow(color: a.withValues(alpha: .6), blurRadius: 8)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Padding(padding: const EdgeInsets.only(right: 5), child: Img(icon, w: IC.s, h: IC.s)),
          T(label, style: fs(F.bold, 12, color: on ? Colors.white : C.dim)),
        ]),
      ),
    );
  }
}

/// segmented control with a sliding highlight (RTL order like the RN row-reverse)
class Segment<V> extends StatelessWidget {
  final List<(V, String)> items;
  final V value;
  final ValueChanged<V> onChange;
  final Color? accent;
  const Segment({super.key, required this.items, required this.value, required this.onChange, this.accent});
  @override
  Widget build(BuildContext context) {
    final a = accent ?? C.cyan;
    final idx = math.max(0, items.indexWhere((i) => i.$1 == value));
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: rgba(6, 10, 30, .8), border: Border.all(color: C.line)),
      child: LayoutBuilder(builder: (context, bc) {
        final cw = bc.maxWidth / items.length;
        return Stack(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: idx.toDouble()),
            duration: const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (_, x, _) => Positioned(
              right: x * cw, top: 0, bottom: 0, width: cw,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: a),
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [a.withValues(alpha: .33), a.withValues(alpha: .09)]),
                  boxShadow: [BoxShadow(color: a.withValues(alpha: .6), blurRadius: 8)],
                ),
              ),
            ),
          ),
          Row(textDirection: TextDirection.rtl, children: [
            for (final (k, l) in items)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    sfx(Sfx.ui);
                    buzz();
                    onChange(k);
                  },
                  child: Center(child: T(l, style: fs(F.bold, 12, color: k == value ? Colors.white : C.dim))),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

class Toggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChange;
  final Color? accent;
  const Toggle({super.key, required this.on, required this.onChange, this.accent});
  @override
  Widget build(BuildContext context) {
    final a = accent ?? C.cyan;
    return GestureDetector(
      onTap: () {
        sfx(Sfx.ui);
        buzz();
        onChange(!on);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: on ? 1 : 0),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (_, x, _) => Container(
          width: 54, height: 30,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), color: Color.lerp(const Color(0x1FFFFFFF), a, x.clamp(0, 1))),
          child: Stack(children: [
            Positioned(
              left: 3 + x * 24, top: 3,
              child: Container(width: 24, height: 24, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Color(0x4D000000), blurRadius: 3, offset: Offset(0, 1))])),
            ),
          ]),
        ),
      ),
    );
  }
}

/// staggered enter (RN FadeInDown.delay(i*45).springify())
class Enter extends StatelessWidget {
  final Widget child;
  final int i;
  const Enter({super.key, required this.child, this.i = 0});
  @override
  Widget build(BuildContext context) => child
      .animate(delay: Duration(milliseconds: math.min(i, 10) * 45))
      .fadeIn(duration: 380.ms)
      .slideY(begin: .15, end: 0, duration: 420.ms, curve: Curves.easeOutBack);
}

class Title2 extends StatelessWidget {
  final String s;
  final String? en;
  final Color? accent;
  final Widget? right;
  const Title2(this.s, {super.key, this.en, this.accent, this.right});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(children: [
          ?right,
          Expanded(child: Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 10), color: rgba(120, 180, 255, .18))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            T(s, style: fs(F.bold, 16)),
            if (en != null) T(en!, style: fs(F.head, 8, ls: 3, color: accent ?? C.cyan)),
          ]),
        ]),
      );
}

/// slow breathing glow used behind hero art
class Pulse extends StatelessWidget {
  final double size;
  final Color color;
  const Pulse({super.key, required this.size, required this.color});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color, blurRadius: size / 4)]),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .custom(duration: 2200.ms, curve: Curves.easeInOutSine, builder: (_, p, child) => Opacity(opacity: .35 + p * .4, child: Transform.scale(scale: .9 + p * .12, child: child))),
      );
}

class Float extends StatelessWidget {
  final Widget child;
  final double amp;
  final int dur, delay;
  const Float({super.key, required this.child, this.amp = 6, this.dur = 2600, this.delay = 0});
  @override
  Widget build(BuildContext context) => child
      .animate(delay: delay.ms, onPlay: (c) => c.repeat(reverse: true))
      .custom(duration: dur.ms, curve: Curves.easeInOutSine, builder: (_, p, c) => Transform.translate(offset: Offset(0, amp - p * amp * 2), child: c));
}

/// round glowing art button: ICON_ART inside a 44pt target
class IconButton2 extends StatelessWidget {
  final String src;
  final VoidCallback? onPress;
  final Object? badge; // bool | int
  final bool disabled;
  const IconButton2(this.src, {super.key, this.onPress, this.badge, this.disabled = false});
  @override
  Widget build(BuildContext context) => Press(
        onPress: onPress,
        disabled: disabled,
        scaleTo: .88,
        child: SizedBox(
          width: TOUCH, height: TOUCH,
          child: Stack(alignment: Alignment.center, children: [
            Img(src, w: ICON_ART, h: ICON_ART),
            if (badge != null && badge != false && badge != 0)
              Positioned(
                top: 2, right: 2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 14), height: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), color: C.red, border: Border.all(color: hex('#0b1236'), width: 1.5)),
                  child: badge is int ? Center(child: T((badge as int) > 9 ? '9+' : '$badge', style: fs(F.bold, 9, color: Colors.white))) : null,
                ),
              ),
          ]),
        ),
      );
}

class ArtIcon extends StatelessWidget {
  final String src;
  final double size;
  const ArtIcon(this.src, {super.key, this.size = IC.m});
  @override
  Widget build(BuildContext context) => Img(src, w: size, h: size);
}

class Section extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? child;
  const Section({super.key, required this.title, this.action, this.onAction, this.child});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: SP.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SP.l, 0, SP.l, SP.s),
            child: Row(textDirection: TextDirection.rtl, children: [
              Container(width: 3, height: 16, margin: const EdgeInsets.only(left: SP.s), decoration: BoxDecoration(color: C.cyan, borderRadius: BorderRadius.circular(2))),
              Expanded(child: Align(alignment: Alignment.centerRight, child: T(title, style: fs(F.bold, TY.h3)))),
              if (action != null)
                Press(onPress: onAction, child: Padding(padding: const EdgeInsets.symmetric(horizontal: SP.s, vertical: 12), child: T(action!, style: fs(F.body, TY.small, color: C.cyan)))),
            ]),
          ),
          ?child,
        ]),
      );
}

class ListRow extends StatelessWidget {
  final String? icon;
  final String title;
  final String? sub;
  final Widget? right;
  final VoidCallback? onPress;
  const ListRow({super.key, this.icon, required this.title, this.sub, this.right, this.onPress});
  @override
  Widget build(BuildContext context) {
    final body = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: SP.m),
      margin: const EdgeInsets.fromLTRB(SP.l, 0, SP.l, SP.s),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line), color: rgba(10, 14, 40, .82)),
      child: Row(textDirection: TextDirection.rtl, children: [
        if (icon != null) ArtIcon(icon!, size: IC.l),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SP.m),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              T(title, n: 1, style: fs(F.bold, TY.body)),
              if (sub != null) T(sub!, n: 1, style: fs(F.body, TY.cap, color: C.dim)),
            ]),
          ),
        ),
        ?right,
      ]),
    );
    return onPress != null ? Press(onPress: onPress, scaleTo: .98, child: body) : body;
  }
}
