import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Glossy hold-button for on-screen game controls (multi-touch safe: uses raw pointer events).
class ArcadePadButton extends StatefulWidget {
  const ArcadePadButton({
    super.key,
    required this.icon,
    required this.color,
    this.size = 72,
    this.label,
    this.onDown,
    this.onUp,
    this.enabled = true,
    this.badge,
  });
  final IconData icon;
  final Color color;
  final double size;
  final String? label;
  final VoidCallback? onDown;
  final VoidCallback? onUp;
  final bool enabled;
  final Widget? badge;

  @override
  State<ArcadePadButton> createState() => _ArcadePadButtonState();
}

class _ArcadePadButtonState extends State<ArcadePadButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
    if (v) {
      HapticFeedback.selectionClick();
      widget.onDown?.call();
    } else {
      widget.onUp?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color c = widget.enabled ? widget.color : Colors.grey;
    final double s = widget.size;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => widget.enabled ? _set(true) : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 80),
        child: Stack(clipBehavior: Clip.none, children: <Widget>[
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                radius: 0.95,
                colors: <Color>[
                  Color.lerp(c, Colors.white, _down ? 0.15 : 0.4)!,
                  c,
                  Color.lerp(c, Colors.black, 0.45)!,
                ],
                stops: const <double>[0, 0.5, 1],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(color: c.withValues(alpha: _down ? 0.8 : 0.45), blurRadius: _down ? 22 : 14),
                const BoxShadow(color: Colors.black54, offset: Offset(0, 4), blurRadius: 6),
              ],
            ),
            alignment: Alignment.center,
            child: Opacity(
              opacity: widget.enabled ? 1 : 0.45,
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Icon(widget.icon, color: Colors.white, size: s * 0.42,
                    shadows: const <Shadow>[Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))]),
                if (widget.label != null)
                  Text(widget.label!,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: s * 0.14)),
              ]),
            ),
          ),
          if (widget.badge != null) Positioned(right: -4, top: -4, child: widget.badge!),
        ]),
      ),
    );
  }
}

/// Small glass HUD pill (position, lap, timer …).
class ArcadeHudPill extends StatelessWidget {
  const ArcadeHudPill({super.key, required this.child, this.color = const Color(0xFF39E1FF)});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0.3)],
          ),
          border: Border.all(color: color.withValues(alpha: 0.65)),
          boxShadow: <BoxShadow>[BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 10)],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontFamily: 'ChakraPetch'),
          child: child,
        ),
      );
}

/// Big centred banner text ("3", "GO!", "FINISH").
class ArcadeBanner extends StatelessWidget {
  const ArcadeBanner(this.text, {super.key, this.color = const Color(0xFFFFD34E), this.size = 64});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey<String>(text),
        tween: Tween<double>(begin: 1.8, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (_, double k, __) => Transform.scale(
          scale: k,
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w900,
                fontFamily: 'ChakraPetch',
                color: Colors.white,
                shadows: <Shadow>[
                  Shadow(color: color, blurRadius: 30),
                  Shadow(color: color.withValues(alpha: 0.8), blurRadius: 8),
                  const Shadow(color: Colors.black, offset: Offset(0, 4), blurRadius: 6),
                ],
              )),
        ),
      );
}
