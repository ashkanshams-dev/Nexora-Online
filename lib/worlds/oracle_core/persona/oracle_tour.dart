/// ORACLE first-run guided tour: coach marks with a spotlight on real UI elements, step by step, once per section
/// per account (local + profile cloud copy), replayable from Settings. Texts come from the admin-editable persona
/// config (`tours`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/storage/local_store.dart';
import 'oracle_persona.dart';

/// Marks a UI element the tour can spotlight (`key:<id>` in the config).
class OracleTourTarget extends StatefulWidget {
  const OracleTourTarget({super.key, required this.id, required this.child});
  final String id;
  final Widget child;

  static final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  static Rect? rectOf(String id) {
    final BuildContext? c = _keys[id]?.currentContext;
    final RenderObject? r = c?.findRenderObject();
    if (r is! RenderBox || !r.attached || !r.hasSize) return null;
    return r.localToGlobal(Offset.zero) & r.size;
  }

  @override
  State<OracleTourTarget> createState() => _OracleTourTargetState();
}

class _OracleTourTargetState extends State<OracleTourTarget> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    OracleTourTarget._keys[widget.id] = _key;
  }

  @override
  void dispose() {
    if (OracleTourTarget._keys[widget.id] == _key) OracleTourTarget._keys.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.child);
}

/// Seen-state per account (local) + a copy in the cloud profile (`nx_profiles.tour_seen`).
class OracleTourStore {
  OracleTourStore._();

  /// Bumped by "Replay ORACLE tour" in Settings; the corner ORACLE restarts the tour of the current screen.
  static final ValueNotifier<int> replayTick = ValueNotifier<int>(0);
  static String _key(String? uid) => 'oracle_tour.seen.${uid ?? 'local'}';

  static Set<String> seen(String? uid) {
    try {
      final Object? j = jsonDecode(LocalStore.instance.getString(_key(uid)) ?? '[]');
      return j is List ? j.map((Object? e) => '$e').toSet() : <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> markSeen(String? uid, String section, {SupabaseClient? client}) async {
    final Set<String> s = seen(uid)..add(section);
    await LocalStore.instance.setString(_key(uid), jsonEncode(s.toList()));
    if (client != null && uid != null) unawaited(_pushCloud(client, uid, s));
  }

  /// Replay: forget every section (local + cloud).
  static Future<void> reset(String? uid, {SupabaseClient? client}) async {
    await LocalStore.instance.setString(_key(uid), '[]');
    if (client != null && uid != null) unawaited(_pushCloud(client, uid, <String>{}, replace: true));
  }

  /// Merges the cloud copy into the local one (new device / reinstall keeps the "already seen" state).
  static Future<void> pullCloud(SupabaseClient? client, String? uid) async {
    if (client == null || uid == null) return;
    try {
      final Map<String, dynamic>? row = await client.from('nx_profiles').select('tour_seen').eq('id', uid).maybeSingle();
      final Object? d = row?['tour_seen'];
      if (d is List) {
        final Set<String> s = seen(uid)..addAll(d.map((Object? e) => '$e'));
        await LocalStore.instance.setString(_key(uid), jsonEncode(s.toList()));
      }
    } catch (_) {}
  }

  static Future<void> _pushCloud(SupabaseClient c, String uid, Set<String> s, {bool replace = false}) async {
    try {
      await c.rpc('nx_tour_seen_set', params: <String, dynamic>{'p_sections': s.toList(), 'p_replace': replace});
    } catch (_) {}
  }
}

/// Full-screen coach-mark overlay for one section.
class OracleTourOverlay extends StatefulWidget {
  const OracleTourOverlay({super.key, required this.steps, required this.onDone});
  final List<OracleTourStep> steps;
  final VoidCallback onDone;

  @override
  State<OracleTourOverlay> createState() => _OracleTourOverlayState();
}

class _OracleTourOverlayState extends State<OracleTourOverlay> with SingleTickerProviderStateMixin {
  int _i = 0;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Rect? _target(Size sz, EdgeInsets pad) {
    final String? t = widget.steps[_i].target;
    if (t == null) return null;
    if (t.startsWith('key:')) return OracleTourTarget.rectOf(t.substring(4));
    switch (t) {
      case 'area:top':
        return Rect.fromLTWH(12, pad.top + 8, sz.width - 24, sz.height * .2);
      case 'area:center':
        return Rect.fromLTWH(12, sz.height * .3, sz.width - 24, sz.height * .34);
      case 'area:bottom':
        return Rect.fromLTWH(12, sz.height * .66, sz.width - 24, sz.height * .3 - pad.bottom);
    }
    return null;
  }

  void _next() {
    if (_i >= widget.steps.length - 1) {
      widget.onDone();
    } else {
      setState(() => _i++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size sz = MediaQuery.sizeOf(context);
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final Rect? r = _target(sz, pad)?.inflate(6);
    final OracleTourStep s = widget.steps[_i];
    final bool cardTop = r != null && r.center.dy > sz.height * .55;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: Stack(children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _next,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (BuildContext context, _) => CustomPaint(painter: _SpotPainter(r, _pulse.value)),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: cardTop ? pad.top + 24 : null,
            bottom: cardTop ? null : pad.bottom + 24,
            child: TweenAnimationBuilder<double>(
              key: ValueKey<int>(_i),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              builder: (BuildContext context, double v, Widget? c) =>
                  Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.scale(scale: .9 + .1 * v, child: c)),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(colors: <Color>[Color(0xF5182A5E), Color(0xF52A1556)]),
                  border: Border.all(color: const Color(0xFF39E6FF), width: 1.2),
                  boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x8839E6FF), blurRadius: 24)],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  Row(children: <Widget>[
                    Image.asset('assets/characters/oracle/moods/wave.webp',
                        width: 46, height: 46, errorBuilder: (_, __, ___) => const Icon(Icons.smart_toy_rounded, color: Color(0xFF8FF3FF))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.title,
                          style: const TextStyle(color: Color(0xFF8FF3FF), fontSize: 15, fontWeight: FontWeight.w900)),
                    ),
                    Text('${_i + 1}/${widget.steps.length}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                  const SizedBox(height: 6),
                  Text(s.text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(children: <Widget>[
                    TextButton(
                      onPressed: widget.onDone,
                      child: const Text('رد کردن', style: TextStyle(color: Colors.white60)),
                    ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF39E6FF), foregroundColor: Colors.black),
                      onPressed: _next,
                      child: Text(_i >= widget.steps.length - 1 ? 'فهمیدم!' : 'بعدی',
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SpotPainter extends CustomPainter {
  _SpotPainter(this.r, this.t);
  final Rect? r;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Path bg = Path()..addRect(Offset.zero & size);
    final Paint dim = Paint()..color = const Color(0xC0050818);
    if (r == null) {
      canvas.drawPath(bg, dim);
      return;
    }
    final RRect hole = RRect.fromRectAndRadius(r!, const Radius.circular(18));
    canvas.drawPath(Path.combine(PathOperation.difference, bg, Path()..addRRect(hole)), dim);
    final double g = 4 + 6 * (0.5 + 0.5 * (1 - (t * 2 - 1).abs()));
    canvas.drawRRect(
        hole,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF39E6FF)
          ..maskFilter = MaskFilter.blur(BlurStyle.solid, g));
  }

  @override
  bool shouldRepaint(_SpotPainter o) => o.r != r || o.t != t;
}
