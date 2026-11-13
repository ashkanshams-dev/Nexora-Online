// Deep-space backdrop — port of src/ui/Space.tsx (nebula art breathing + two drifting star tiles + gradient),
// upgraded with an additive procedural nebula/twinkle pass (shaders/space.frag) on "high" quality.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../game/assets.dart';
import 'menu_assets.dart';
import 'theme.dart';

enum SpaceTheme { base, win, lose, system, hub, stadium, holo }

String nebFor(SpaceTheme t) => switch (t) {
      SpaceTheme.base => UI['neb_base']!,
      SpaceTheme.win => UI['neb_win']!,
      SpaceTheme.lose => UI['neb_lose']!,
      SpaceTheme.system => UI['neb_system']!,
      SpaceTheme.hub => UI2['home_bg']!,
      SpaceTheme.stadium => MENU.bg_stadium,
      SpaceTheme.holo => MENU.bg_holo,
    };

ui.FragmentProgram? _spaceProg;
Future<void> warmSpace() async {
  try {
    _spaceProg ??= await ui.FragmentProgram.fromAsset('shaders/space.frag');
  } catch (_) {}
}

class Space extends StatefulWidget {
  final SpaceTheme theme;
  final double dim;
  final bool stars;
  const Space({super.key, this.theme = SpaceTheme.base, this.dim = 0, this.stars = true});
  @override
  State<Space> createState() => _SpaceState();
}

class _SpaceState extends State<Space> with SingleTickerProviderStateMixin {
  late final Ticker _t;
  final _time = ValueNotifier(0.0);
  ui.FragmentShader? _sh;

  @override
  void initState() {
    super.initState();
    _sh = _spaceProg?.fragmentShader();
    _t = createTicker((d) => _time.value = d.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = isLight();
    final th = widget.theme, dim = widget.dim;
    final holo = th == SpaceTheme.stadium || th == SpaceTheme.holo;
    final grad = holo
        ? [rgba(5, 4, 14, (.55 + dim).clamp(0, 1)), rgba(5, 4, 14, (.45 + dim).clamp(0, 1)), rgba(5, 4, 14, (.82 + dim).clamp(0, 1))]
        : [rgba(2, 4, 14, (.35 + dim).clamp(0, 1)), rgba(2, 4, 14, dim.clamp(0, 1)), rgba(2, 4, 14, (.55 + dim).clamp(0, 1))];
    return IgnorePointer(
      child: RepaintBoundary(
        child: Container(
          color: light ? C.bg : hex('#02030b'),
          child: Stack(fit: StackFit.expand, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: ValueListenableBuilder<double>(
                key: ValueKey(th),
                valueListenable: _time,
                builder: (_, t, child) {
                  // 16 s sine breathing: scale 1.05→1.10, drift ±6 px
                  final b = .5 - .5 * _cos(t / 16 * 3.14159);
                  return Transform.translate(offset: Offset(0, -6 + b * 12), child: Transform.scale(scale: 1.05 + b * .05, child: child));
                },
                child: Opacity(opacity: light ? .16 : 1, child: Image.asset(nebFor(th), fit: BoxFit.cover, width: double.infinity, height: double.infinity, gaplessPlayback: true)),
              ),
            ),
            if (widget.stars && !light) ...[
              _StarLayer(src: UI['stars1']!, period: 110, opacity: .7, time: _time),
              _StarLayer(src: UI['stars2']!, period: 60, opacity: .75, time: _time),
              if (_sh != null)
                ValueListenableBuilder<double>(
                  valueListenable: _time,
                  builder: (_, t, _) => CustomPaint(painter: _ShaderPainter(_sh!, t, holo ? const Color(0xFF6D5BFF) : const Color(0xFF3B82FF))),
                ),
            ],
            DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: grad, stops: const [0, .45, 1]))),
          ]),
        ),
      ),
    );
  }
}

double _cos(double x) => math.cos(x);

class _StarLayer extends StatelessWidget {
  final String src;
  final double period, opacity;
  final ValueNotifier<double> time;
  const _StarLayer({required this.src, required this.period, required this.opacity, required this.time});
  @override
  Widget build(BuildContext context) {
    const tile = 1024.0;
    final sz = MediaQuery.sizeOf(context);
    final rows = (sz.height / tile).ceil() + 1, cols = (sz.width / tile).ceil();
    return Opacity(
      opacity: opacity,
      child: ClipRect(
        child: ValueListenableBuilder<double>(
          valueListenable: time,
          builder: (_, t, child) => Transform.translate(offset: Offset(0, -tile + (t % period) / period * tile), child: child),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: rows * tile,
            maxWidth: cols * tile,
            child: Column(children: [
              for (var r = 0; r < rows; r++) Row(children: [for (var c = 0; c < cols; c++) Image.asset(src, width: tile, height: tile)]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ShaderPainter extends CustomPainter {
  final ui.FragmentShader sh;
  final double t;
  final Color tint;
  _ShaderPainter(this.sh, this.t, this.tint);
  @override
  void paint(Canvas canvas, Size size) {
    sh
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, t)
      ..setFloat(3, 1)
      ..setFloat(4, tint.r)
      ..setFloat(5, tint.g)
      ..setFloat(6, tint.b);
    canvas.drawRect(Offset.zero & size, Paint()..shader = sh..blendMode = BlendMode.plus);
  }

  @override
  bool shouldRepaint(_ShaderPainter o) => o.t != t;
}
