import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// ===================== NEXORA ARCADE SKIN LAYER =====================
/// Every new arcade game draws ALL of its visuals through an [ArcadeSkin]:
///  * palette (background gradient, accents, glow, per-player colours),
///  * optional sprites (PNG/WebP) keyed by role ('player', 'kart_0', 'bg', ...),
///  * FX tuning (particle counts, glow strength, shake) in [fx].
///
/// Drop-in art without code changes: put files in `assets/games/<gameId>/` and list them in that folder's
/// `skin.json` ("sprites": {"player": "runner.png"}). Any sprite that is missing (or any key not listed) falls back to
/// the game's procedural vector renderer, so the game always works. Palette / FX keys in skin.json override the
/// code defaults below key by key. See docs/ARCADE_ASSETS.md for every game's sprite keys.
/// =====================================================================

class ArcadeSkin {
  ArcadeSkin({
    required this.gameId,
    required this.bgTop,
    required this.bgBottom,
    required this.accent,
    required this.accent2,
    required this.glow,
    this.players = const <Color>[
      Color(0xFF34D8FF),
      Color(0xFFFF4F9A),
      Color(0xFFFFC94A),
      Color(0xFF7CFF7A),
    ],
    Map<String, double>? fx,
    Map<String, String>? sprites,
  })  : fx = <String, double>{...kDefaultFx, ...?fx},
        sprites = <String, String>{...?sprites};

  final String gameId;
  Color bgTop;
  Color bgBottom;
  Color accent;
  Color accent2;
  Color glow;
  List<Color> players;

  /// FX tuning: 'particles' (multiplier), 'glow' (0..2), 'shake' (0..2), 'trail' (0..1), 'bloom' (0..1).
  final Map<String, double> fx;

  /// role -> file name inside assets/games/<gameId>/
  final Map<String, String> sprites;
  final Map<String, ui.Image> _images = <String, ui.Image>{};

  static const Map<String, double> kDefaultFx = <String, double>{
    'particles': 1,
    'glow': 1,
    'shake': 1,
    'trail': 1,
    'bloom': 1,
  };

  double fxv(String k) => fx[k] ?? 1;
  Color player(int i) => players[i % players.length];

  /// Loaded sprite for [role], or null (= draw the procedural version).
  ui.Image? image(String role) => _images[role];
  bool has(String role) => _images.containsKey(role);

  String get folder => 'assets/games/$gameId/';

  /// Reads assets/games/<id>/skin.json (if any) and decodes the sprites it lists. Never throws.
  Future<ArcadeSkin> load({AssetBundle? bundle}) async {
    final AssetBundle b = bundle ?? rootBundle;
    try {
      final String raw = await b.loadString('${folder}skin.json');
      final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
      Color? c(String k) {
        final dynamic v = j['palette'] is Map ? (j['palette'] as Map)[k] : null;
        if (v is! String) return null;
        final String h = v.replaceFirst('#', '');
        final int? n = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
        return n == null ? null : Color(n);
      }

      bgTop = c('bgTop') ?? bgTop;
      bgBottom = c('bgBottom') ?? bgBottom;
      accent = c('accent') ?? accent;
      accent2 = c('accent2') ?? accent2;
      glow = c('glow') ?? glow;
      final dynamic pl = (j['palette'] is Map) ? (j['palette'] as Map)['players'] : null;
      if (pl is List && pl.isNotEmpty) {
        players = <Color>[
          for (final dynamic p in pl)
            if (p is String) Color(int.tryParse('FF${p.replaceFirst('#', '')}', radix: 16) ?? 0xFFFFFFFF)
        ];
      }
      final dynamic f = j['fx'];
      if (f is Map) {
        f.forEach((dynamic k, dynamic v) {
          if (v is num) fx['$k'] = v.toDouble();
        });
      }
      final dynamic s = j['sprites'];
      if (s is Map) {
        s.forEach((dynamic k, dynamic v) {
          if (v is String && v.isNotEmpty) sprites['$k'] = v;
        });
      }
    } catch (_) {
      // no skin.json: code defaults
    }
    for (final MapEntry<String, String> e in sprites.entries) {
      try {
        final ByteData data = await b.load('$folder${e.value}');
        final ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final ui.FrameInfo fi = await codec.getNextFrame();
        _images[e.key] = fi.image;
      } catch (_) {
        // missing art: procedural fallback
      }
    }
    return this;
  }

  /// Draws sprite [role] into [dst] (rotated by [angle] around its centre). Returns false when the sprite is missing.
  bool drawSprite(Canvas canvas, String role, Rect dst, {double angle = 0, double opacity = 1}) {
    final ui.Image? img = _images[role];
    if (img == null) return false;
    final Paint p = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, opacity);
    canvas.save();
    canvas.translate(dst.center.dx, dst.center.dy);
    if (angle != 0) canvas.rotate(angle);
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: dst.width, height: dst.height), p);
    canvas.restore();
    return true;
  }
}

/// Loads a skin once and rebuilds when it is ready (procedural visuals are shown meanwhile).
class ArcadeSkinLoader extends StatefulWidget {
  const ArcadeSkinLoader({super.key, required this.skin, required this.builder});
  final ArcadeSkin skin;
  final Widget Function(BuildContext context, ArcadeSkin skin) builder;

  @override
  State<ArcadeSkinLoader> createState() => _ArcadeSkinLoaderState();
}

class _ArcadeSkinLoaderState extends State<ArcadeSkinLoader> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.skin.load().then((_) {
      if (mounted) setState(() {});
    }));
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.skin);
}
