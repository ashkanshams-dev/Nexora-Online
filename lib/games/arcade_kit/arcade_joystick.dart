import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Floating virtual joystick: touch anywhere inside its area, drag to steer. Reports a vector in -1..1.
class ArcadeJoystick extends StatefulWidget {
  const ArcadeJoystick({super.key, required this.onChanged, this.color = const Color(0xFF39E1FF), this.radius = 58});
  final void Function(double dx, double dy) onChanged;
  final Color color;
  final double radius;

  @override
  State<ArcadeJoystick> createState() => _ArcadeJoystickState();
}

class _ArcadeJoystickState extends State<ArcadeJoystick> {
  Offset? _origin;
  Offset _knob = Offset.zero;

  void _update(Offset p) {
    final Offset o = _origin ?? p;
    Offset d = p - o;
    final double r = widget.radius;
    if (d.distance > r) d = d / d.distance * r;
    setState(() => _knob = d);
    widget.onChanged(d.dx / r, d.dy / r);
  }

  @override
  Widget build(BuildContext context) {
    final double r = widget.radius;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent e) {
        setState(() => _origin = e.localPosition);
        _update(e.localPosition);
      },
      onPointerMove: (PointerMoveEvent e) => _update(e.localPosition),
      onPointerUp: (_) {
        setState(() {
          _origin = null;
          _knob = Offset.zero;
        });
        widget.onChanged(0, 0);
      },
      onPointerCancel: (_) {
        setState(() {
          _origin = null;
          _knob = Offset.zero;
        });
        widget.onChanged(0, 0);
      },
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final Offset base = _origin ?? Offset(r + 18, c.maxHeight - r - 18);
        return Stack(children: <Widget>[
          Positioned(
            left: base.dx - r,
            top: base.dy - r,
            child: IgnorePointer(
              child: Container(
                width: r * 2,
                height: r * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: <Color>[
                    widget.color.withValues(alpha: 0.05),
                    widget.color.withValues(alpha: _origin == null ? 0.12 : 0.22),
                  ]),
                  border: Border.all(color: widget.color.withValues(alpha: 0.6), width: 2),
                ),
              ),
            ),
          ),
          Positioned(
            left: base.dx + _knob.dx - r * 0.45,
            top: base.dy + _knob.dy - r * 0.45,
            child: IgnorePointer(
              child: Container(
                width: r * 0.9,
                height: r * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.3, -0.4),
                    colors: <Color>[Colors.white, widget.color, Color.lerp(widget.color, Colors.black, 0.4)!],
                    stops: const <double>[0, 0.55, 1],
                  ),
                  boxShadow: <BoxShadow>[BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 16)],
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

/// Snap a joystick vector to 4 directions (dead zone 0.3).
(double, double) dpad4(double dx, double dy) {
  if (math.max(dx.abs(), dy.abs()) < 0.3) return (0, 0);
  return dx.abs() > dy.abs() ? (dx.sign, 0) : (0, dy.sign);
}
