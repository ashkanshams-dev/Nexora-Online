import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Fixed-rate friendly game loop for CustomPainter games. Subclasses implement [tick] (dt in seconds, clamped to
/// 1/20 s so a hitch never tunnels objects) and paint through [ArcadePainter] which repaints on [frame] only — the
/// widget tree is not rebuilt every frame.
abstract class ArcadeLoopState<T extends StatefulWidget> extends State<T> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double time = 0;
  bool paused = false;

  void tick(double dt);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    if (dt > 0.05) dt = 0.05;
    if (!paused) {
      time += dt;
      tick(dt);
    }
    frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    frame.dispose();
    super.dispose();
  }
}

/// CustomPainter that delegates to a closure and repaints whenever [repaint] ticks.
class ArcadePainter extends CustomPainter {
  ArcadePainter(this.onPaint, Listenable repaint) : super(repaint: repaint);
  final void Function(Canvas canvas, Size size) onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint(canvas, size);

  @override
  bool shouldRepaint(covariant ArcadePainter oldDelegate) => true;
}
