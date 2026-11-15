// v0.6 main screen (owner sketch "لیست روم و گزینه ساخت روم در بالا" + NEXORA stadium references):
//   - neon purple stadium backdrop (assets/g/v6/bg_stadium.webp, baked once)
//   - one central glass panel with an orange -> pink -> blue side accent and a header bar: CREATE ROOM on top,
//     join-by-code, then the open room list
//   - four slide-out panels on the screen edges, each with a peeking tab; tap or drag a tab to spring it in:
//       TOP    = profile, coins & gems, level / rank, daily reward, notifications, Oracle assistant
//       LEFT   = my team: discs, ball, pitch, formation, shop, chest
//       RIGHT  = social: friends, messages, clubs, leaderboard, leagues
//       BOTTOM = play: offline game modes, online quick match, arena, tournaments, challenges, settings
// Every feature has exactly one home. Light: no BackdropFilter, no per-frame painting; drawers only translate.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../online/lobby.dart' show RoomRow, CreateRoomSheet, kModesOnline;
import '../online/ui.dart' show Field2;
import '../screens/setup.dart';
import 'chrome.dart';
import 'kit.dart';
import 'v4.dart';
import '../social/player_link.dart' show UnreadBadge;

enum HubEdge { top, left, right, bottom }

/// What the main screen can open (wired by the shell).
class HubActions {
  final VoidCallback profile, shop, daily, oracle, settings;
  final void Function(bool premium) chest;
  final void Function(String tab) team, social;
  final void Function(String entry, [String? quick]) online;
  final void Function(Mode m) mode;
  final void Function(Rec room) room;
  const HubActions({
    required this.profile,
    required this.shop,
    required this.daily,
    required this.oracle,
    required this.settings,
    required this.chest,
    required this.team,
    required this.social,
    required this.online,
    required this.mode,
    required this.room,
  });
}

const _bgAsset = 'assets/g/v6/bg_stadium.webp';
const _rimGrad = [Color(0xffffa24a), Color(0xffff5aa0), Color(0xff4f7dff)];
// v0.6.2: richer, a little translucent so the moving backdrop glows through (was f2120d38 / f2090b27)
const _panelFill = [Color(0xc81a0f4a), Color(0xd00c0a30)];

class MainHub extends StatefulWidget {
  final HubActions a;
  final bool dailyReady, chestReady;

  /// tests / snapshots: start with this panel open, and show these rooms instead of loading them
  final HubEdge? initialOpen;
  final List<Rec>? previewRooms;
  const MainHub({super.key, required this.a, required this.dailyReady, required this.chestReady, this.initialOpen, this.previewRooms});
  @override
  State<MainHub> createState() => MainHubState();
}

class MainHubState extends State<MainHub> with TickerProviderStateMixin {
  late final Map<HubEdge, AnimationController> c = {
    for (final e in HubEdge.values) e: AnimationController(vsync: this, value: e == widget.initialOpen ? 1 : 0, lowerBound: 0, upperBound: 1),
  };
  late final Map<HubEdge, Animation<double>> _fades = {for (final e in HubEdge.values) e: c[e]!.drive(CurveTween(curve: const Interval(0, .16)))};
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: .86);
  // v0.6.2: while a side panel is being swiped its cards shrink and dim (1 = fully squeezed), springing back on release
  late final AnimationController _squeeze = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 420),
  );

  HubEdge? get open => c.entries.where((e) => e.value.value > .5).map((e) => e.key).firstOrNull;

  void _animate(HubEdge e, double to, [double v = 0]) {
    final ac = c[e]!;
    ac.animateWith(SpringSimulation(_spring, ac.value, to, v)..tolerance = const Tolerance(distance: .001, velocity: .01));
  }

  void toggle(HubEdge e) {
    hubPicked.value = null;
    final opening = c[e]!.value < .5;
    for (final o in HubEdge.values) {
      if (o != e && c[o]!.value > 0) _animate(o, 0);
    }
    _animate(e, opening ? 1 : 0);
    sfx(Snd.ui);
  }

  void closeAll() {
    for (final e in HubEdge.values) {
      if (c[e]!.value > 0) _animate(e, 0);
    }
  }

  /// run [fn] after the open panel slid away (keeps the transition smooth)
  void _go(VoidCallback fn) {
    closeAll();
    fn();
  }

  @override
  void dispose() {
    for (final a in c.values) {
      a.dispose();
    }
    _squeeze.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context), sz = mq.size, ins = mq.padding;
    final k = (sz.width / 400).clamp(.86, 1.15);
    final sideW = math.min(sz.width - 2 * 30.0 * k - 18, 380.0), topH = math.min(sz.height * .64, 600.0), botH = math.min(sz.height * .66, 620.0);
    final tabT = 30.0 * k; // tab thickness
    final anyOpen = Listenable.merge(c.values.toList());
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (did) return;
        if (open != null) {
          closeAll();
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Stack(
        children: [
          const Positioned.fill(child: _Backdrop()),
          // central rooms panel
          Positioned(
            left: tabT + 10,
            right: tabT + 10,
            top: ins.top + tabT + 12,
            bottom: ins.bottom + tabT + 16,
            child: RepaintBoundary(
              child: RoomsPanel(a: widget.a, preview: widget.previewRooms),
            ),
          ),
          // scrim
          Positioned.fill(
            child: AnimatedBuilder(
              animation: anyOpen,
              builder: (_, _) {
                final v = c.values.map((x) => x.value).fold(0.0, math.max).clamp(0.0, 1.0);
                return IgnorePointer(
                  ignoring: v < .05,
                  child: GestureDetector(
                    onTap: closeAll,
                    child: ColoredBox(color: Color.fromRGBO(4, 2, 18, .62 * v)),
                  ),
                );
              },
            ),
          ),
          _drawer(HubEdge.left, sz, ins, sideW, tabT, k),
          _drawer(HubEdge.right, sz, ins, sideW, tabT, k),
          _drawer(HubEdge.top, sz, ins, topH, tabT, k),
          _drawer(HubEdge.bottom, sz, ins, botH, tabT, k),
        ],
      ),
    );
  }

  static const _titles = {
    HubEdge.top: ('پروفایل و اعلان‌ها', 'PROFILE'),
    HubEdge.left: ('تیم من', 'MY TEAM'),
    HubEdge.right: ('دوستان و رتبه', 'SOCIAL'),
    HubEdge.bottom: ('حالت‌های بازی', 'PLAY'),
  };
  static const _tabLabel = {HubEdge.top: 'پروفایل', HubEdge.left: 'تیم', HubEdge.right: 'دوستان', HubEdge.bottom: 'بازی'};
  static const _tabIcon = {
    HubEdge.top: Icons.person_rounded,
    HubEdge.left: Icons.shield_rounded,
    HubEdge.right: Icons.forum_rounded,
    HubEdge.bottom: Icons.sports_esports_rounded,
  };

  Widget _content(HubEdge e) => switch (e) {
    HubEdge.top => _TopPanel(a: widget.a, dailyReady: widget.dailyReady, chestReady: widget.chestReady, go: _go),
    HubEdge.left => _LeftPanel(a: widget.a, chestReady: widget.chestReady, go: _go),
    HubEdge.right => _RightPanel(a: widget.a, go: _go),
    HubEdge.bottom => _BottomPanel(a: widget.a, go: _go),
  };

  Widget _drawer(HubEdge e, Size sz, EdgeInsets ins, double ext, double tabT, double k) {
    final ac = c[e]!;
    final horiz = e == HubEdge.left || e == HubEdge.right;
    final travel = ext; // closed: only the tab peeks, at the safe-area edge
    // the closed panel sits just past the safe-area edge; it fades in over the first part of the slide so no rim
    // ever peeks out next to the tab
    final panel = FadeTransition(
      opacity: _fades[e]!,
      child: RepaintBoundary(
        child: _NeonPanel(
          title: _titles[e]!.$1,
          en: _titles[e]!.$2,
          edge: e,
          onClose: () => toggle(e),
          // v0.6.2: cards shrink + dim while the panel is swiped, and grow in as it opens
          child: AnimatedBuilder(
            animation: Listenable.merge([ac, _squeeze]),
            child: _content(e),
            builder: (_, ch) {
              final q = Curves.easeOut.transform(_squeeze.value), open = Curves.easeOutCubic.transform(ac.value);
              final sc = (.86 + .14 * open) * (1 - .12 * q);
              return Opacity(
                opacity: (1 - .3 * q).clamp(0.0, 1.0),
                child: Transform.scale(scale: sc, child: ch),
              );
            },
          ),
        ),
      ),
    );
    final tab = _EdgeTab(
      edge: e,
      label: _tabLabel[e]!,
      icon: _tabIcon[e]!,
      thick: tabT,
      long: (horiz ? 112.0 : 136.0) * k,
      dot: e == HubEdge.top && (widget.dailyReady || widget.chestReady),
      ctrl: ac,
      onTap: () => toggle(e),
      onDrag: (d) {
        // d = delta along the opening direction, in px
        if (ac.isAnimating) ac.stop();
        hubPicked.value = null;
        if (_squeeze.status != AnimationStatus.forward && _squeeze.value < 1) _squeeze.forward();
        if (d > 0) {
          for (final o in HubEdge.values) {
            if (o != e && c[o]!.value > 0) _animate(o, 0);
          }
        }
        ac.value = (ac.value + d / travel).clamp(0.0, 1.0);
      },
      onDragEnd: (v) {
        _squeeze.reverse();
        final vv = v / travel;
        _animate(e, vv.abs() > .6 ? (vv > 0 ? 1 : 0) : (ac.value > .45 ? 1 : 0), vv);
      },
    );
    final Widget body;
    switch (e) {
      case HubEdge.top:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: ext, child: panel),
            tab,
          ],
        );
      case HubEdge.bottom:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tab,
            SizedBox(height: ext, child: panel),
          ],
        );
      case HubEdge.left:
        body = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: ext, child: panel),
            tab,
          ],
        );
      case HubEdge.right:
        body = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tab,
            SizedBox(width: ext, child: panel),
          ],
        );
    }
    final child = AnimatedBuilder(
      animation: ac,
      child: body,
      builder: (_, ch) {
        final off = (1 - ac.value) * travel;
        final o = switch (e) {
          HubEdge.top => Offset(0, -off),
          HubEdge.bottom => Offset(0, off),
          HubEdge.left => Offset(-off, 0),
          HubEdge.right => Offset(off, 0),
        };
        return Transform.translate(offset: o, child: ch);
      },
    );
    final vMargin = ins.top + tabT + 14;
    return switch (e) {
      HubEdge.top => Positioned(left: 8, right: 8, top: ins.top + 4, child: child),
      HubEdge.bottom => Positioned(left: 8, right: 8, bottom: ins.bottom + 4, child: child),
      HubEdge.left => Positioned(left: 4, top: vMargin, bottom: ins.bottom + tabT + 18, child: child),
      HubEdge.right => Positioned(right: 4, top: vMargin, bottom: ins.bottom + tabT + 18, child: child),
    };
  }
}

// =========================================================================== chrome
/// v0.6.2 animated backdrop (owner: "richer colours, a moving background"): the stadium art drifts slowly
/// (Ken Burns pan + zoom), three saturated aurora blobs (magenta / cyan / orange) wander across it in additive
/// blend, and a field of small stars drifts upward. One 40 s repeating controller, one CustomPainter, no blur filters.
class _Backdrop extends StatefulWidget {
  const _Backdrop();
  @override
  State<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<_Backdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();
  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xff0a0626)),
        AnimatedBuilder(
          animation: _t,
          child: Image.asset(_bgAsset, fit: BoxFit.cover, filterQuality: FilterQuality.medium, errorBuilder: (_, _, _) => const SizedBox()),
          builder: (_, ch) {
            final a = _t.value * 2 * math.pi;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(math.sin(a) * 18, math.cos(a * .5) * 14, 0, 1)
                ..scaleByDouble(1.10 + .05 * math.sin(a * .5), 1.10 + .05 * math.sin(a * .5), 1, 1),
              child: ch,
            );
          },
        ),
        AnimatedBuilder(
          animation: _t,
          builder: (_, _) => CustomPaint(painter: _AuroraPainter(_t.value)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: RadialGradient(radius: 1.25, colors: [Color(0x00000000), Color(0x7005031a)])),
        ),
      ],
    ),
  );
}

class _AuroraPainter extends CustomPainter {
  final double t;
  _AuroraPainter(this.t);
  static final List<(double, double, double)> _stars = [
    for (var i = 0; i < 46; i++) (((i * 0.6180339) % 1), ((i * 0.3819 + i * i * .0137) % 1), .6 + (i % 5) * .35),
  ];
  @override
  void paint(Canvas c, Size s) {
    final a = t * 2 * math.pi;
    final p = Paint()..blendMode = BlendMode.plus;
    for (final (cx, cy, r, col, ph) in [
      (.25 + .18 * math.sin(a), .28 + .12 * math.cos(a * 2), .55, const Color(0x88ff2fd0), 0.0),
      (.78 + .14 * math.cos(a + 1), .55 + .16 * math.sin(a + 2), .6, const Color(0x7724d8ff), 1.0),
      (.45 + .2 * math.sin(a * 2 + 3), .86 + .06 * math.cos(a + 1), .5, const Color(0x66ff8a2a), 2.0),
    ]) {
      final o = Offset(s.width * cx, s.height * cy), rr = s.shortestSide * r * (1 + .12 * math.sin(a * 3 + ph));
      p.shader = RadialGradient(colors: [col, col.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: o, radius: rr));
      c.drawCircle(o, rr, p);
    }
    p.shader = null;
    for (final (x, y, r) in _stars) {
      final yy = (y - t * (.15 + r * .08)) % 1.0;
      final tw = .45 + .55 * (.5 + .5 * math.sin(a * 6 + x * 40));
      p.color = Color.fromRGBO(220, 235, 255, .55 * tw);
      c.drawCircle(Offset(x * s.width, yy * s.height), r, p);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter o) => o.t != t;
}

/// Peeking tab on a screen edge (orange glowing pill / vertical bar). Tap toggles; dragging moves the panel.
class _EdgeTab extends StatelessWidget {
  final HubEdge edge;
  final String label;
  final IconData icon;
  final double thick, long;
  final bool dot;
  final AnimationController ctrl;
  final VoidCallback onTap;
  final ValueChanged<double> onDrag, onDragEnd;
  const _EdgeTab({
    required this.edge,
    required this.label,
    required this.icon,
    required this.thick,
    required this.long,
    required this.dot,
    required this.ctrl,
    required this.onTap,
    required this.onDrag,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final horiz = edge == HubEdge.left || edge == HubEdge.right;
    final sign = edge == HubEdge.top || edge == HubEdge.left ? 1.0 : -1.0; // opening direction along the axis
    final r = Radius.circular(thick * .62);
    final br = switch (edge) {
      HubEdge.top => BorderRadius.vertical(bottom: r),
      HubEdge.bottom => BorderRadius.vertical(top: r),
      HubEdge.left => BorderRadius.horizontal(right: r),
      HubEdge.right => BorderRadius.horizontal(left: r),
    };
    final content = [
      AnimatedBuilder(
        animation: ctrl,
        builder: (_, _) => Transform.rotate(
          angle: ctrl.value * math.pi,
          child: Icon(
            switch (edge) {
              HubEdge.top => Icons.keyboard_arrow_down_rounded,
              HubEdge.bottom => Icons.keyboard_arrow_up_rounded,
              HubEdge.left => Icons.chevron_right_rounded,
              HubEdge.right => Icons.chevron_left_rounded,
            },
            size: thick * .62,
            color: Colors.white,
          ),
        ),
      ),
      SizedBox(width: horiz ? 0 : 4, height: horiz ? 4 : 0),
      Icon(icon, size: thick * .52, color: const Color(0xffffe2c2)),
      SizedBox(width: horiz ? 0 : 5, height: horiz ? 3 : 0),
      if (horiz)
        RotatedBox(quarterTurns: edge == HubEdge.left ? 1 : 3, child: T(label, size: 11.5, weight: 800, lines: 1))
      else
        T(label, size: 12.5, weight: 800, lines: 1),
    ];
    final tab = Container(
      width: horiz ? thick : long,
      height: horiz ? long : thick,
      decoration: BoxDecoration(
        borderRadius: br,
        gradient: LinearGradient(
          begin: horiz ? Alignment.topCenter : Alignment.centerLeft,
          end: horiz ? Alignment.bottomCenter : Alignment.centerRight,
          colors: const [Color(0xffff9a3a), Color(0xffff6a3d), Color(0xffe8458f)],
        ),
        border: Border.all(color: const Color(0xccffd2a0), width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x88ff6a2a), blurRadius: 14)],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: horiz
                  ? Column(mainAxisSize: MainAxisSize.min, children: content)
                  : Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.rtl, children: content.reversed.toList()),
            ),
          ),
          if (dot) const Positioned(top: 3, right: 6, child: _Dot()),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragUpdate: horiz ? null : (d) => onDrag(d.delta.dy * sign),
      onVerticalDragEnd: horiz ? null : (d) => onDragEnd(d.velocity.pixelsPerSecond.dy * sign),
      onHorizontalDragUpdate: horiz ? (d) => onDrag(d.delta.dx * sign) : null,
      onHorizontalDragEnd: horiz ? (d) => onDragEnd(d.velocity.pixelsPerSecond.dx * sign) : null,
      child: tab,
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xffff3d5a),
      border: Border.all(color: Colors.white, width: 1.4),
    ),
  );
}

/// Glowing orange / pink framed panel with an orange pill header (reference frames).
class _NeonPanel extends StatelessWidget {
  final String title, en;
  final HubEdge edge;
  final Widget child;
  final VoidCallback onClose;
  const _NeonPanel({required this.title, required this.en, required this.edge, required this.child, required this.onClose});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xffffa24a), Color(0xffff5aa0), Color(0xffff8a3a)]),
      boxShadow: const [BoxShadow(color: Color(0x77ff5a2a), blurRadius: 22)],
    ),
    padding: const EdgeInsets.all(1.6),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22.5),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _panelFill),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: OrangePill(title: title, en: en),
                ),
                const SizedBox(width: 8),
                Press(
                  onTap: onClose,
                  child: const Icon(Icons.close_rounded, color: Color(0xffffd2a0), size: 24),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

/// Orange glowing pill header (reference "orange pill headers").
class OrangePill extends StatelessWidget {
  final String title;
  final String? en;
  const OrangePill({super.key, required this.title, this.en});
  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(colors: [Color(0xffffb25a), Color(0xffff7a3a), Color(0xffff5a8a)]),
      boxShadow: const [BoxShadow(color: Color(0x99ff7a2a), blurRadius: 14)],
      border: Border.all(color: const Color(0xccffe0b8)),
    ),
    child: Row(
      textDirection: TextDirection.rtl,
      children: [
        Flexible(
          child: T(title, size: 15, weight: 800, lines: 1, shadows: const [Shadow(color: Color(0x66000000), blurRadius: 4)]),
        ),
        const Spacer(),
        if (en != null) T(en!, size: 9.5, family: F.head, weight: 700, spacing: 1.6, color: const Color(0xfffff1de), lines: 1),
      ],
    ),
  );
}

/// Square glowing tile used inside the panels.
/// v0.6.2: the card the user tapped in a side panel (scales up big; any new swipe/toggle of a panel resets it).
final ValueNotifier<Object?> hubPicked = ValueNotifier(null);

class HubTile extends StatelessWidget {
  final String label;
  final String? sub, img;
  final IconData? icon;
  final Color color;
  final bool dot;
  final VoidCallback onTap;
  const HubTile({super.key, required this.label, required this.onTap, this.sub, this.img, this.icon, this.color = N.orange, this.dot = false});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Object?>(
    valueListenable: hubPicked,
    builder: (_, picked, ch) => AnimatedScale(
      scale: picked == label ? 1.16 : 1,
      duration: const Duration(milliseconds: 360),
      curve: picked == label ? Curves.easeOutBack : Curves.easeOutCubic,
      child: ch,
    ),
    child: Press(
      onTap: () {
        hubPicked.value = label;
        Future<void>.delayed(const Duration(milliseconds: 240), onTap);
      },
      scaleTo: .95,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .55), width: 1.2),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: .20), const Color(0xe60a0b2a)]),
          boxShadow: [BoxShadow(color: color.withValues(alpha: .18), blurRadius: 10)],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (img != null)
                      Img(img!, w: 40, h: 40)
                    else
                      Icon(
                        icon ?? Icons.circle,
                        color: color,
                        size: 32,
                        shadows: [Shadow(color: color, blurRadius: 12)],
                      ),
                    const SizedBox(height: 5),
                    T(label, size: 12, weight: 800, lines: 1, align: TextAlign.center),
                    if (sub != null) T(sub!, size: 8.5, family: F.head, weight: 700, spacing: 1.2, color: N.amber, lines: 1, align: TextAlign.center),
                  ],
                ),
              ),
            ),
            if (dot) const Positioned(top: -2, right: -2, child: _Dot()),
          ],
        ),
      ),
    ),
  );
}

Widget _grid(List<Widget> tiles, {int cols = 3, double ratio = 1}) => LayoutBuilder(
  builder: (_, bc) {
    final gap = 10.0, w = (bc.maxWidth - gap * (cols - 1)) / cols;
    return Wrap(
      textDirection: TextDirection.rtl,
      spacing: gap,
      runSpacing: gap,
      children: [for (final t in tiles) SizedBox(width: w, height: w / ratio, child: t)],
    );
  },
);

Widget _section(String s) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
  child: Row(
    textDirection: TextDirection.rtl,
    children: [
      Container(
        width: 4,
        height: 16,
        decoration: BoxDecoration(color: N.orange, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 8),
      tBold(s, size: 14),
    ],
  ),
);

ListView _list(List<Widget> c) => ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 18), physics: const BouncingScrollPhysics(), children: c);

// =========================================================================== TOP: profile
class _TopPanel extends StatelessWidget {
  final HubActions a;
  final bool dailyReady, chestReady;
  final void Function(VoidCallback) go;
  const _TopPanel({required this.a, required this.dailyReady, required this.chestReady, required this.go});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([Store.i, Auth.i]),
    builder: (context, _) {
      final p = Store.i.p, lv = level(p.xp), lg = league(p.trophies), prof = Auth.i.profile;
      final avatar = prof != null ? (prof.str('avatar_url') ?? teamImgById(prof.s('equipped_disc', 'club0'))) : teamImg(teamById(p.team));
      Widget chip(String img, int v, VoidCallback on) => Expanded(
        child: Press(
          onTap: on,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: const Color(0xcc0a0b2a),
              border: Border.all(color: const Color(0x66ff9a4a)),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Img(img, w: 28, h: 28),
                const SizedBox(width: 8),
                T(en(v), size: 16, family: F.num, weight: 800),
                const Spacer(),
                const Icon(Icons.add_circle_rounded, color: N.amber, size: 20),
              ],
            ),
          ),
        ),
      );
      final notes = <(IconData, String, String, VoidCallback)>[
        if (dailyReady) (Icons.card_giftcard_rounded, 'جایزه‌ی روزانه آماده‌ست', 'دریافت سکه‌ی امروز', () => go(a.daily)),
        if (chestReady) (Icons.inventory_2_rounded, 'صندوقچه‌ی رایگان باز شد', 'در پنل تیم من', () => go(() => a.chest(false))),
        if (lv.need > 0 && lv.cur / lv.need > .8)
          (Icons.trending_up_rounded, 'نزدیک سطح ${fa(lv.level + 1)} هستی', '${fa(lv.need - lv.cur)} XP مانده', () => go(a.profile)),
      ];
      return _list([
        // profile card
        Press(
          onTap: () => go(a.profile),
          scaleTo: .98,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: const Color(0xcc0a0b2a),
              border: Border.all(color: const Color(0x55ff9a4a)),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Disc(avatar, size: 64, ring: N.orange, ringW: 2.6, glowOn: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      tBold(prof?.s('username') ?? p.name, size: 17, lines: 1),
                      const SizedBox(height: 4),
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          T('سطح ${fa(lv.level)}', size: 12, color: N.amber, weight: 800),
                          const Spacer(),
                          T('${en(lv.cur)} / ${en(lv.need)} XP', size: 10.5, family: F.num, weight: 700, color: C.dim),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Bar(v: lv.need > 0 ? lv.cur / lv.need : 0, h: 8, color: N.amber, color2: N.pink),
                      const SizedBox(height: 6),
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Img(V4.h('trophy'), w: 18, h: 18),
                          const SizedBox(width: 4),
                          Flexible(child: T('${fa(p.trophies)} جام · لیگ ${kLeagueFa[lg.name]}', size: 11, color: C.dim, lines: 1)),
                          const Spacer(),
                          T('${fa(p.wins)} برد', size: 11, color: C.dim),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          textDirection: TextDirection.rtl,
          children: [chip(ui2('c_coin'), p.coins, () => go(a.shop)), const SizedBox(width: 10), chip(V4.h('gem'), p.gems, () => go(a.shop))],
        ),
        _section('اعلان‌ها'),
        if (notes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: T('اعلان تازه‌ای نداری', size: 12, color: C.dim2, align: TextAlign.center),
          )
        else
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Press(
                onTap: n.$4,
                scaleTo: .98,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0x33ff8a2a),
                    border: Border.all(color: const Color(0x55ff8a2a)),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(n.$1, color: N.amber, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            tBold(n.$2, size: 13, lines: 1),
                            T(n.$3, size: 10.5, color: C.dim, lines: 1),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_left_rounded, color: C.dim),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: 4),
        _grid([
          HubTile(label: 'پروفایل', sub: 'PROFILE', icon: Icons.person_rounded, onTap: () => go(a.profile)),
          HubTile(label: 'جایزه‌ی روزانه', sub: 'DAILY', img: V4.h('gift'), dot: dailyReady, onTap: () => go(a.daily)),
          HubTile(label: 'اوراکل', sub: 'ORACLE', icon: Icons.auto_awesome_rounded, color: N.pink, onTap: () => go(a.oracle)),
        ], ratio: 1.05),
      ]);
    },
  );
}

// =========================================================================== LEFT: my team
class _LeftPanel extends StatelessWidget {
  final HubActions a;
  final bool chestReady;
  final void Function(VoidCallback) go;
  const _LeftPanel({required this.a, required this.chestReady, required this.go});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Store.i,
    builder: (context, _) {
      final p = Store.i.p, me = teamById(p.team);
      return _list([
        Press(
          onTap: () => go(() => a.team('disc')),
          scaleTo: .98,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [Color(0x40ff8a2a), Color(0xcc0a0b2a)]),
              border: Border.all(color: const Color(0x66ff9a4a)),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Disc(teamImg(me), size: 70, ring: N.amber, ringW: 3, glowOn: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      tBold(me.name, size: 16, lines: 1),
                      const SizedBox(height: 3),
                      T('ترکیب ${kForms[p.form].code} · ${kBallNames[p.ball]}', size: 11, color: C.dim, lines: 1),
                      T(kFields[p.field].name, size: 11, color: C.dim, lines: 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _section('تجهیزات'),
        _grid(
          [
            HubTile(label: 'دیسک‌ها', sub: 'DISCS', img: teamImg(me), onTap: () => go(() => a.team('disc'))),
            HubTile(label: 'توپ', sub: 'BALL', img: ballImg(p.ball), color: N.cyan, onTap: () => go(() => a.team('ball'))),
            HubTile(label: 'زمین', sub: 'PITCH', img: fieldThumb(p.field), color: C.green, onTap: () => go(() => a.team('field'))),
            HubTile(label: 'ترکیب', sub: 'FORMATION', icon: Icons.grid_view_rounded, color: C.violet, onTap: () => go(() => a.team('form'))),
          ],
          cols: 2,
          ratio: 1.25,
        ),
        _section('خرید'),
        _grid(
          [
            HubTile(label: 'فروشگاه', sub: 'SHOP', img: V4.ic('bag'), color: N.pink, onTap: () => go(a.shop)),
            HubTile(label: 'صندوقچه', sub: 'CHEST', img: V4.h('chest'), dot: chestReady, color: N.amber, onTap: () => go(() => a.chest(false))),
          ],
          cols: 2,
          ratio: 1.25,
        ),
      ]);
    },
  );
}

// =========================================================================== RIGHT: social
class _RightPanel extends StatelessWidget {
  final HubActions a;
  final void Function(VoidCallback) go;
  const _RightPanel({required this.a, required this.go});
  @override
  Widget build(BuildContext context) => _list([
    _section('اجتماعی'),
    _grid(
      [
        HubTile(label: 'دوستان', sub: 'FRIENDS', img: V4.ic('friends'), color: N.cyan, onTap: () => go(() => a.social('friends'))),
        UnreadBadge(child: HubTile(label: 'پیام‌ها', sub: 'CHAT', icon: Icons.chat_bubble_rounded, color: N.pink, onTap: () => go(() => a.social('msg')))),
        HubTile(label: 'باشگاه‌ها', sub: 'CLUBS', img: V4.h('shield'), color: C.violet, onTap: () => go(() => a.social('club'))),
      ],
      cols: 2,
      ratio: 1.25,
    ),
    _section('رتبه‌بندی'),
    _grid(
      [
        HubTile(label: 'جدول برترین‌ها', sub: 'LEADERBOARD', img: V4.h('trophy'), color: C.gold, onTap: () => go(() => a.online('ranks'))),
        HubTile(label: 'لیگ‌ها', sub: 'LEAGUES', img: ui2('x_medal'), color: N.amber, onTap: () => go(() => a.online('leagues'))),
      ],
      cols: 2,
      ratio: 1.25,
    ),
  ]);
}

// =========================================================================== BOTTOM: play
class _BottomPanel extends StatelessWidget {
  final HubActions a;
  final void Function(VoidCallback) go;
  const _BottomPanel({required this.a, required this.go});
  @override
  Widget build(BuildContext context) => _list([
    Press(
      onTap: () => go(() => a.mode(kModes.first)),
      scaleTo: .97,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xffffb25a), Color(0xffff7a2a), Color(0xffff4f8a)]),
          boxShadow: const [BoxShadow(color: Color(0x99ff6a2a), blurRadius: 20)],
          border: Border.all(color: const Color(0xccffe0b8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          textDirection: TextDirection.rtl,
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
            const SizedBox(width: 6),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                tBold(kModes.first.name, size: 19),
                T('QUICK MATCH · VS BOT', size: 9, family: F.head, weight: 700, spacing: 1.6, color: const Color(0xfffff1de)),
              ],
            ),
          ],
        ),
      ),
    ),
    _section('آفلاین'),
    _grid(
      [for (final m in kModes.skip(1)) HubTile(label: m.name, sub: m.en.split(' ').first, img: m.img, color: m.color, onTap: () => go(() => a.mode(m)))],
      cols: 4,
      ratio: .82,
    ),
    _section('آنلاین'),
    _grid(
      [
        HubTile(label: 'سریع ۱ به ۱', sub: 'ONLINE', img: V4.holoBall, color: N.cyan, onTap: () => go(() => a.online('hub', kModesOnline.first))),
        HubTile(label: 'آرنا', sub: 'ARENA', img: ui2('x_crown'), color: C.violet, onTap: () => go(() => a.online('arena'))),
        HubTile(label: 'تورنمنت', sub: 'TOURS', img: ui2('x_trophy'), color: N.amber, onTap: () => go(() => a.online('tours'))),
        HubTile(label: 'چالش‌ها', sub: 'DAILY', img: ui2('c_calendar'), color: C.green, onTap: () => go(() => a.online('challenges'))),
      ],
      cols: 4,
      ratio: .82,
    ),
    _section('سیستم'),
    _grid([HubTile(label: 'تنظیمات', sub: 'SETTINGS', img: V4.ic('gear'), color: C.sky, onTap: () => go(a.settings))], cols: 4, ratio: .82),
  ]);
}

// =========================================================================== CENTER: rooms
/// Central glass panel: header bar, CREATE ROOM on top, join by code, open room list (live from room_list).
class RoomsPanel extends StatefulWidget {
  final HubActions a;
  final List<Rec>? preview;
  const RoomsPanel({super.key, required this.a, this.preview});
  @override
  State<RoomsPanel> createState() => _RoomsPanelState();
}

class _RoomsPanelState extends State<RoomsPanel> {
  List<Rec>? rows;
  String? err, busy;
  final code = TextEditingController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      rows = widget.preview;
    } else {
      load();
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => load());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final id = await Auth.i.ensure();
      if (id == null) throw 'اتصال به سرور برقرار نشد';
      final d = await sb.from('room_list').select().order('created_at', ascending: false).limit(60);
      if (mounted) {
        setState(() {
          err = null;
          rows = recs(d).where((r) => r.s('mode', '1v1') == '1v1').toList();
        });
      }
    } catch (e, st) {
      debugPrint('NX_ERR rooms load: $e\n$st');
      if (mounted) setState(() => err = errFa(e));
    }
  }

  Future<void> act(String key, Future<dynamic> Function() fn) async {
    if (busy != null) return;
    setState(() => busy = key);
    try {
      final id = await Auth.i.ensure();
      if (id == null) throw 'اتصال به سرور برقرار نشد';
      final r = Rec.of(await fn());
      sfx(Snd.join);
      buzz('medium');
      widget.a.room(r);
    } catch (e) {
      toast(errFa(e), 'err');
      buzz('heavy');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  void _create() => showSheet(
    context,
    title: 'ساخت اتاق',
    en: 'CREATE ROOM',
    accent: N.orange,
    height: .88,
    child: (ctx) => CreateRoomSheet(
      onCreate: (args) {
        Navigator.pop(ctx);
        act('create', () => rpc('create_room', args));
      },
    ),
  );

  void _join() {
    final c = code.text.trim().toUpperCase();
    if (c.length != 6) return toast('کد اتاق ۶ کاراکتر است', 'err');
    act('code', () => rpc('join_room', {'p_code': c}));
  }

  @override
  Widget build(BuildContext context) {
    final data = rows ?? const <Rec>[];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0x99ffc08a), width: 1.4),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xb8241657), Color(0xc00a0c2e), Color(0xb8142a5c)]), // v0.6.2 richer + translucent over the moving backdrop
        boxShadow: const [
          BoxShadow(color: Color(0x55ff7a2a), blurRadius: 24),
          BoxShadow(color: Color(0x553b6bff), blurRadius: 30, offset: Offset(-6, 0)),
        ],
      ),
      child: Stack(
        children: [
          // orange -> pink -> blue side accent (reference: blue at the top, orange at the bottom, on the left rim)
          Positioned(
            left: 6,
            top: 70,
            bottom: 34,
            child: Container(
              width: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xff4f7dff), Color(0xffff5aa0), Color(0xffffa24a)],
                ),
                boxShadow: const [BoxShadow(color: Color(0xaaff5aa0), blurRadius: 10)],
              ),
            ),
          ),
          // glass highlight
          Positioned(
            right: 22,
            bottom: 18,
            child: IgnorePointer(
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Color(0x33ffffff), Color(0x00ffffff)]),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
            child: Column(
              children: [
                // header bar
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xcc070a20),
                    border: Border.all(color: const Color(0x88ffb070)),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      const Icon(Icons.meeting_room_rounded, color: N.amber, size: 22),
                      const SizedBox(width: 8),
                      tBold('اتاق‌ها', size: 16),
                      const SizedBox(width: 6),
                      const T('ROOMS', size: 9, family: F.head, weight: 700, spacing: 2, color: N.amber),
                      const Spacer(),
                      Flexible(child: T(rows != null ? '${fa(data.length)} اتاق باز' : '', size: 11, color: C.dim, lines: 1)),
                      const SizedBox(width: 6),
                      Press(
                        onTap: widget.preview == null ? load : null,
                        child: const Icon(Icons.refresh_rounded, color: C.dim, size: 22),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // CREATE ROOM (top)
                Press(
                  onTap: busy == null ? _create : null,
                  scaleTo: .97,
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(colors: _rimGrad),
                      boxShadow: const [BoxShadow(color: Color(0x88ff6a5a), blurRadius: 18)],
                      border: Border.all(color: const Color(0xccffe8d2)),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        textDirection: TextDirection.rtl,
                        children: [
                          const Icon(Icons.add_circle_rounded, color: Colors.white, size: 26),
                          const SizedBox(width: 8),
                          tBold(busy == 'create' ? 'در حال ساخت…' : 'ساخت اتاق', size: 18),
                          const SizedBox(width: 8),
                          const T('CREATE ROOM', size: 9.5, family: F.head, weight: 700, spacing: 1.6, color: Color(0xfffff1de)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Expanded(
                      child: Field2(code, hint: 'کد ۶ رقمی اتاق', ltr: true, maxLength: 6, onSubmit: (_) => _join()),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 72,
                      child: Btn(busy == 'code' ? '…' : 'ورود', small: true, colors: G.violet, onTap: _join),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: err != null && rows == null
                        ? Center(
                            key: const ValueKey('e'),
                            child: ErrorState(err!, onRetry: load),
                          )
                        : rows == null
                        ? const Center(key: ValueKey('l'), child: Spinner(size: 30))
                        : data.isEmpty
                        ? const Center(key: ValueKey('0'), child: EmptyState('فعلاً اتاقی باز نیست · اتاق بساز و دوستانت را با کد دعوت کن'))
                        : RefreshIndicator(
                            key: const ValueKey('d'),
                            onRefresh: load,
                            color: N.orange,
                            child: ListView(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              children: [
                                for (final r in data)
                                  RoomRow(
                                    r: r,
                                    busy: busy,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    onJoin: (id, spec) => act((spec ? 'w' : 'j') + id, () => rpc('join_room', {'p_room': id, 'p_spectate': spec})),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
