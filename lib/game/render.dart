// Match renderer: port of src/game/render.ts on Flutter's Canvas (Impeller), hosted by Flame (game.dart).
//
// Frame cost is kept flat and allocation-free:
//  * the stadium background, the feathered field and the outline are baked ONCE into a single image;
//  * discs, gloss, shadows and particles are drawn from one pre-baked sprite atlas with drawRawAtlas
//    (SpriteBatch-style: 1 draw call for all shadows, 1 for all discs, 1 for gloss, 1 for particles)
//    using pre-allocated Float32List/Int32List buffers;
//  * the static goal nets are cached as Pictures and only rebuilt while a goal ripple/shake plays;
//  * the ball is a FragmentShader (shaders/ball.frag) sampling the ball texture;
//  * every Paint is a long-lived field.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'engine.dart';
import 'goal_skins.dart';

class MatchView {
  final double W, H, s, ox, oy;
  final bool flipped;
  const MatchView(this.W, this.H, this.s, this.ox, this.oy, {this.flipped = false});
  Offset toWorld(double x, double y) {
    if (flipped) {
      x = W - x;
      y = H - y;
    }
    return Offset((x - ox) / s, (y - oy) / s);
  }
}

MatchView computeView(Engine e, double W, double H, double top, double bottom, {bool flipped = false}) {
  final f = e.f;
  const fs = 1.12;
  final playH = math.max(300.0, H - top - bottom);
  final s = math.min(W / (f.R - f.L + 56 * fs), playH / ((f.B - f.T) + 2 * e.GGh + 48)) * .96; // v0.6.1b: pitch a touch smaller on screen
  return MatchView(W, H, s, W / 2 - e.CX * s, top + playH / 2 - e.CY * s, flipped: flipped);
}

Future<ui.Image> loadImage(String path, {int? width}) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
  final fr = await codec.getNextFrame();
  return fr.image;
}

/// A small solid-colour disc image (fallback art when a texture cannot be decoded).
Future<ui.Image> solidImage(ui.Color c, [int size = 64]) {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawCircle(ui.Offset(size / 2, size / 2), size / 2, ui.Paint()..color = c);
  return rec.endRecording().toImage(size, size);
}

/// Classic white/black soccer ball drawn with Canvas: used when the ball texture fails to load.
Future<ui.Image> proceduralBall([int size = 256]) {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  final R = size / 2, o = ui.Offset(R, R);
  c.drawCircle(o, R, ui.Paint()..color = const ui.Color(0xfff7f8fa));
  final blk = ui.Paint()..color = const ui.Color(0xff15171c);
  final seam = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = size * .018
    ..color = const ui.Color(0xff2a2d33);
  ui.Path pent(ui.Offset ctr, double rad, double rot) {
    final p = ui.Path();
    for (var k = 0; k < 5; k++) {
      final a = rot + k * 2 * math.pi / 5 - math.pi / 2;
      final pt = ctr + ui.Offset(math.cos(a), math.sin(a)) * rad;
      k == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  c.drawPath(pent(o, R * .3, 0), blk);
  for (var k = 0; k < 5; k++) {
    final a = k * 2 * math.pi / 5 - math.pi / 2;
    final inner = o + ui.Offset(math.cos(a), math.sin(a)) * R * .3;
    final outer = o + ui.Offset(math.cos(a), math.sin(a)) * R * .82;
    c.drawLine(inner, outer, seam);
    c.drawPath(pent(o + ui.Offset(math.cos(a + math.pi / 5), math.sin(a + math.pi / 5)) * R * .9, R * .26, a + math.pi / 5 + math.pi), blk);
  }
  return rec.endRecording().toImage(size, size);
}

class MatchImages {
  final ui.Image field, ball, t0, t1;
  final ui.Image? headE, headS, shaftE, shaftS;

  /// v4 goal skin + its honeycomb net texture (null = classic procedural mesh)
  final GoalSkin skin;
  final ui.Image? net;
  /// v0.6.1 aim arrow sprite (assets/g/arrow/aim_v061.webp); preferred over the head/shaft set when present
  final ui.Image? aim;
  MatchImages(this.field, this.ball, this.t0, this.t1, this.headE, this.headS, this.shaftE, this.shaftS, {GoalSkin? skin, this.net, this.aim})
      : skin = skin ?? kGoalSkins[0];
  bool get hasArrow => headE != null && headS != null && shaftE != null && shaftS != null;
}

const _teamGlow = [ui.Color(0xff3bb6ff), ui.Color(0xffff5b6b)];
const double _aimMaxK = 4.0; // Godot AIM_MAX_K: arrow length beyond the rim at full power, in disc radii
const double _aimMinK = .35; // Godot AIM_MIN_K: ... at the lowest power (short stub)
const _aimC = [ui.Color(0xff3b8bff), ui.Color(0xff9b5cff), ui.Color(0xffff3b5c)];

class _ArtK {
  final double hh, join, sw, top, tail, topLen, tailLen;
  const _ArtK(this.hh, this.join, this.sw, this.top, this.tail, this.topLen, this.tailLen);
}

const _artE = _ArtK(96, .82, 124, 0, .734, 0, 46);
const _artS = _ArtK(68, .928, 32.5, 0, .704, 0, 38);

double _sstep(double a, double b, double v) {
  final k = ((v - a) / (b - a)).clamp(0.0, 1.0);
  return k * k * (3 - 2 * k);
}

class MatchRenderer {
  final Engine e;
  final MatchImages im;
  final int ballIdx;
  final bool hq;
  MatchView v;
  final double dpr;
  ui.FragmentShader? ballShader;

  // sprite atlas: [0] disc team0, [1] disc team1, [2] gloss, [3] shadow, [4] particle dot
  static const int spr = 192;
  late ui.Image atlas;
  ui.Image? bg;
  final List<ui.Picture?> _nets = [null, null];
  final math.Random _fxRand = math.Random();

  // pre-allocated atlas buffers (up to 12 bodies, 640 particles)
  final Float32List _xf = Float32List(4 * 32), _rc = Float32List(4 * 32);
  final Float32List _pxf = Float32List(4 * Engine.maxParts), _prc = Float32List(4 * Engine.maxParts);
  final Int32List _pcol = Int32List(Engine.maxParts);
  final Int32List _dcol = Int32List(32);

  final ui.Paint _atlasP = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  final ui.Paint _addP = ui.Paint()..blendMode = ui.BlendMode.plus;
  final ui.Paint _shadowP = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..color = const ui.Color(0x80ffffff);
  final ui.Paint _stroke = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..isAntiAlias = true;
  final ui.Paint _fill = ui.Paint()..isAntiAlias = true;
  final ui.Paint _img = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  final ui.Paint _art = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  final ui.Paint _artGlow = ui.Paint()
    ..filterQuality = ui.FilterQuality.medium
    ..blendMode = ui.BlendMode.plus;
  final ui.Paint _netP = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..isAntiAlias = true;
  final ui.Paint _bar = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round;
  final ui.Path _path = ui.Path();

  // aim smoothing (render.ts aimS)
  bool _aimOn = false;
  double _aux = 0, _auy = -1, _ap = 0;

  // cached exact-length views over the pre-allocated buffers (no per-frame allocation)
  final Map<int, Float32List> _fviews = {};
  final Map<int, Int32List> _iviews = {};
  Float32List _vf(Float32List b, int n) => _fviews[identityHashCode(b) * 4096 + n] ??= b.buffer.asFloat32List(0, n);
  Int32List _vi(Int32List b, int n) => _iviews[identityHashCode(b) * 4096 + n] ??= b.buffer.asInt32List(0, n);

  MatchRenderer(this.e, this.im, this.ballIdx, this.v, {required this.dpr, this.hq = true, this.ballShader});

  Future<void> prepare() async {
    atlas = await _bakeAtlas();
    bg = await _bakeStatic();
    await _bakeBallSprites();
  }

  void resize(MatchView nv) async {
    v = nv;
    bg = await _bakeStatic();
  }

  Future<ui.Image> _bakeAtlas() async {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    const R = spr / 2.0, r = R - 2;
    for (var t = 0; t < 2; t++) {
      final logo = t == 0 ? im.t0 : im.t1;
      final ox = t * spr.toDouble();
      c.save();
      c.clipRRect(ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(ox + R - r, R - r, 2 * r, 2 * r), const ui.Radius.circular(r)));
      c.drawImageRect(logo, ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()), ui.Rect.fromLTWH(ox + R - r, R - r, 2 * r, 2 * r), _img);
      c.restore();
    }
    // gloss
    {
      const ox = 2.0 * spr;
      final gl = ui.Paint()
        ..shader = ui.Gradient.radial(ui.Offset(ox + R - r * .38, R - r * .48), r * .9, const [ui.Color(0x42ffffff), ui.Color(0x0dffffff), ui.Color(0x00ffffff)], const [0, .45, 1]);
      c.drawCircle(const ui.Offset(ox + R, R), r * .97, gl);
      final sp = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = 3
        ..color = const ui.Color(0x61ffffff);
      c.drawArc(ui.Rect.fromLTWH(ox + R - r * .93, R - r * .93, r * 1.86, r * 1.86), 205 * math.pi / 180, 60 * math.pi / 180, false, sp);
    }
    // shadow
    {
      const ox = 3.0 * spr;
      final p = ui.Paint()..shader = ui.Gradient.radial(const ui.Offset(ox + R, R), R, const [ui.Color(0xff000000), ui.Color(0x80000000), ui.Color(0x00000000)], const [0, .55, 1]);
      c.drawCircle(const ui.Offset(ox + R, R), R, p);
    }
    // particle dot (soft white)
    {
      const ox = 4.0 * spr;
      final p = ui.Paint()..shader = ui.Gradient.radial(const ui.Offset(ox + R, R), R, const [ui.Color(0xffffffff), ui.Color(0xccffffff), ui.Color(0x00ffffff)], const [0, .5, 1]);
      c.drawCircle(const ui.Offset(ox + R, R), R, p);
    }
    return rec.endRecording().toImage(spr * 5, spr);
  }

  /// v0.6.1b art transform: (scale, left, top) placing the whole art image in world units with ONE scale, so that the
  /// art's goal lines (art.T, art.B) land on the play area's (f.T, f.B), centred on the play area's centre.
  (double, double, double) _artXf() {
    final a = e.art, f = e.f;
    if (identical(a, f)) return (1.0, 0.0, 0.0);
    final k = (f.B - f.T) / (a.B - a.T);
    final px = (f.L + f.R) / 2, py = (f.T + f.B) / 2, ax = (a.L + a.R) / 2, ay = (a.T + a.B) / 2;
    return (k, px - ax * k, py - ay * k);
  }

  /// Background + feathered field (art at its own aspect) + cushion shading, baked once per view size.
  Future<ui.Image> _bakeStatic() async {
    final w = (v.W * dpr).round(), h = (v.H * dpr).round();
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.scale(dpr);
    final f = e.f, fld = im.field;
    c.drawRect(ui.Rect.fromLTWH(0, 0, v.W, v.H), ui.Paint()..color = const ui.Color(0xff02040c));
    final k = math.max(v.W / f.W, v.H / f.H) * 1.05;
    final src = ui.Rect.fromLTWH(0, 0, fld.width.toDouble(), fld.height.toDouble());
    // blurred, darkened stadium fill (blur costs nothing per frame: it is baked)
    c.drawImageRect(fld, src, ui.Rect.fromLTWH((v.W - f.W * k) / 2, (v.H - f.H * k) / 2, f.W * k, f.H * k),
        ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: ui.TileMode.clamp));
    c.drawRect(ui.Rect.fromLTWH(0, 0, v.W, v.H), ui.Paint()..color = const ui.Color(0x9e02040e));
    c.save();
    if (v.flipped) {
      c.translate(v.W, v.H);
      c.rotate(math.pi);
    }
    c.translate(v.ox, v.oy);
    c.scale(v.s);
    // v0.6.1b: the pitch art keeps its own proportions and markings. It is scaled UNIFORMLY so its goal lines sit on
    // the play area's goal lines (centred on the centre spot); nothing is stretched and no lines are drawn over it.
    // The art's touchlines may fall a little outside the (narrower) side cushions; the area outside the cushions is
    // shaded so the walls read without a drawn border.
    final xf = _artXf();
    final fr = ui.Rect.fromLTWH(xf.$2, xf.$3, e.art.W * xf.$1, e.art.H * xf.$1);
    c.saveLayer(fr.inflate(40), ui.Paint());
    c.drawImageRect(fld, src, fr, ui.Paint()..filterQuality = ui.FilterQuality.medium);
    // sharp corners: rounded inner frames of some arts are patched with pitch copied from just inside along the same
    // rows (stripes stay aligned). Baked once per view, no per-frame cost.
    {
      final ki = fld.width / (e.art.W * xf.$1);
      ui.Rect toImg(ui.Rect r) => ui.Rect.fromLTRB((r.left - fr.left) * ki, (r.top - fr.top) * ki, (r.right - fr.left) * ki, (r.bottom - fr.top) * ki);
      const S = 64.0;
      for (final (cx, cy, sx, sy) in [(e.Fl, e.Ft, 1.0, 1.0), (e.Fr, e.Ft, -1.0, 1.0), (e.Fl, e.Fb, 1.0, -1.0), (e.Fr, e.Fb, -1.0, -1.0)]) {
        final dst = ui.Rect.fromPoints(ui.Offset(cx - sx * 6, cy - sy * 6), ui.Offset(cx + sx * S, cy + sy * S));
        final from = dst.shift(ui.Offset(sx * (S + 18), 0));
        c.drawImageRect(fld, toImg(from), dst, ui.Paint()..filterQuality = ui.FilterQuality.medium);
      }
    }
    final m = ui.Paint()..blendMode = ui.BlendMode.dstIn;
    m.shader = ui.Gradient.linear(ui.Offset(0, fr.top), ui.Offset(0, fr.bottom), const [ui.Color(0x00000000), ui.Color(0xff000000), ui.Color(0xff000000), ui.Color(0x00000000)], const [0, .06, .94, 1]);
    c.drawRect(fr, m);
    m.shader = ui.Gradient.linear(ui.Offset(fr.left, 0), ui.Offset(fr.right, 0), const [ui.Color(0x00000000), ui.Color(0xff000000), ui.Color(0xff000000), ui.Color(0x00000000)], const [0, .05, .95, 1]);
    c.drawRect(fr, m);
    c.restore();
    // outside the cushions: shade (no border line). The play rectangle itself is left exactly as the art.
    final play = ui.Rect.fromLTRB(e.Fl, e.Ft, e.Fr, e.Fb);
    final outside = ui.Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addRect(fr.inflate(60))
      ..addRect(play);
    c.drawPath(outside, ui.Paint()..color = const ui.Color(0x8c02040c));
    // soft inner shadow along the cushions so the edge reads as a raised rail (clipped to the play area)
    c.save();
    c.clipRect(play);
    final sh = ui.Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addRect(play.inflate(30))
      ..addRect(play);
    c.drawPath(sh, ui.Paint()
      ..color = const ui.Color(0x99000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7));
    c.restore();
    c.restore();
    _nets[0] = null;
    _nets[1] = null;
    return rec.endRecording().toImage(w, h);
  }

  // ---------------- frame ----------------
  void render(ui.Canvas c, double t) {
    if (bg != null) {
      c.save();
      c.scale(1 / dpr);
      c.drawImage(bg!, ui.Offset.zero, _img);
      c.restore();
    }
    final cam = e.cam;
    final shx = cam > .05 && hq ? (_fxRand.nextDouble() - .5) * cam * 7 : 0.0;
    final shy = cam > .05 && hq ? (_fxRand.nextDouble() - .5) * cam * 7 : 0.0;
    c.save();
    if (v.flipped) {
      c.translate(v.W, v.H);
      c.rotate(math.pi);
    }
    c.translate(v.ox + shx, v.oy + shy);
    c.scale(v.s);
    final al = e.alpha();
    _netFx(t, al);
    _drawNets(c, t);
    _drawBodies(c, t, al);
    _drawTrail(c);
    _drawStreaks(c, al);
    _drawBall(c, al, shx, shy);
    _drawFrames(c, t);
    final d = e.drag;
    if (d != null) {
      _drawAim(c, t, d.b.px + (d.b.x - d.b.px) * al + d.b.vox, d.b.py + (d.b.y - d.b.py) * al + d.b.voy);
    } else {
      _aimOn = false;
    }
    _drawParts(c);
    c.restore();
    if (e.flash > 0) {
      _fill.color = ui.Color.fromRGBO(255, 255, 255, e.flash * .28);
      c.drawRect(ui.Rect.fromLTWH(0, 0, v.W, v.H), _fill);
    }
  }

  void _drawBodies(ui.Canvas c, double t, double al) {
    var n = 0;
    // shadows (1 atlas call), discs (1 call), dark tint, gloss (1 call)
    for (final b in e.bodies) {
      if (identical(b, e.ball)) continue;
      final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
      final r = b.r * (1 + b.sq * .07), R = r * 1.3;
      final sc = 2 * R / spr;
      _set(_xf, n, sc, 0, x + r * .14 - R, y + r * .26 - R);
      _rect(_rc, n, 3);
      n++;
    }
    c.drawRawAtlas(atlas, _vf(_xf, n * 4), _vf(_rc, n * 4), null, null, null, _shadowP);
    n = 0;
    for (final b in e.bodies) {
      if (identical(b, e.ball)) continue;
      final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
      final r = b.r * (1 + b.sq * .07);
      final sc = 2 * r / spr;
      final cs = math.cos(b.ang) * sc, sn = math.sin(b.ang) * sc;
      // RSTransform rotating about the sprite centre
      _xf[n * 4] = cs;
      _xf[n * 4 + 1] = sn;
      _xf[n * 4 + 2] = x - cs * spr / 2 + sn * spr / 2;
      _xf[n * 4 + 3] = y - sn * spr / 2 - cs * spr / 2;
      _rect(_rc, n, b.team == 0 ? 0 : 1);
      _dcol[n] = (e.phase == Phase.aim && b.team != e.turn) ? 0xffc8c9d0 : 0xffffffff;
      n++;
    }
    c.drawRawAtlas(atlas, _vf(_xf, n * 4), _vf(_rc, n * 4), _vi(_dcol, n), ui.BlendMode.modulate, null, _atlasP);
    n = 0;
    for (final b in e.bodies) {
      if (identical(b, e.ball)) continue;
      final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
      final r = b.r * (1 + b.sq * .07);
      _set(_xf, n, 2 * r / spr, 0, x - r, y - r);
      _rect(_rc, n, 2);
      n++;
    }
    c.drawRawAtlas(atlas, _vf(_xf, n * 4), _vf(_rc, n * 4), null, null, null, _atlasP);
    _turnRings(c, t, al);
  }

  /// Turn marker: a slim ring in the team colour just outside every disc of the side on turn (AI and remote
  /// players included), drawn ABOVE the discs so it is never hidden, with three arcs slowly orbiting the disc
  /// over a faint breathing halo. While a disc is being dragged only that disc keeps its ring.
  void _turnRings(ui.Canvas c, double t, double al) {
    if (e.phase != Phase.aim) return;
    final team = e.turn, col = _teamGlow[team.clamp(0, 1)];
    final pulse = .5 + .5 * math.sin(t * 3), rot = t * 1.4;
    const third = 2 * math.pi / 3;
    for (final b in e.bodies) {
      if (identical(b, e.ball) || b.team != team) continue;
      if (e.drag != null && !identical(e.drag!.b, b)) continue;
      final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
      final r = b.r * (1 + b.sq * .07), rr = r * 1.16, ctr = ui.Offset(x, y);
      _stroke
        ..blendMode = ui.BlendMode.plus
        ..strokeWidth = r * (hq ? .16 : .13)
        ..color = col.withValues(alpha: .10 + .10 * pulse);
      c.drawCircle(ctr, rr, _stroke);
      _stroke
        ..strokeWidth = r * .045
        ..color = col.withValues(alpha: .22 + .1 * pulse);
      c.drawCircle(ctr, rr, _stroke);
      _stroke
        ..blendMode = ui.BlendMode.srcOver
        ..strokeWidth = r * .085
        ..color = col.withValues(alpha: .78 + .2 * pulse);
      final rect = ui.Rect.fromCircle(center: ctr, radius: rr);
      for (var k = 0; k < 3; k++) {
        c.drawArc(rect, rot + k * third, third * .55, false, _stroke);
      }
    }
  }

  void _set(Float32List xf, int i, double scos, double ssin, double tx, double ty) {
    xf[i * 4] = scos;
    xf[i * 4 + 1] = ssin;
    xf[i * 4 + 2] = tx;
    xf[i * 4 + 3] = ty;
  }

  void _rect(Float32List rc, int i, int cell) {
    rc[i * 4] = cell * spr.toDouble();
    rc[i * 4 + 1] = 0;
    rc[i * 4 + 2] = (cell + 1) * spr.toDouble();
    rc[i * 4 + 3] = spr.toDouble();
  }

  /// v5: the shader ball (v3 FragCoord bug, v4.1 per-frame toImageSync) is retired. The ball is now a textured
  /// sphere MESH drawn with Canvas.drawVertices: works on every renderer/GPU, costs no offscreen image per frame
  /// and rolls in true 3D (see [_ballMesh]).
  static bool useBallShader = false;

  // ---- ball ----
  // Rolling: the renderer keeps its own rotation R (material -> view), advanced every frame from the INTERPOLATED
  // movement: axis = up x dir = (-dy, dx, 0), angle = distance / radius, so it slows with the ball, stops exactly
  // when it stops and follows bounces. Render-only: the engine's physics are untouched.
  final Float64List _bR = Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]);
  double _blx = double.nan, _bly = 0;

  void _rollBall(double x, double y, double r) {
    if (_blx.isNaN) {
      _blx = x;
      _bly = y;
      return;
    }
    final dx = x - _blx, dy = y - _bly;
    _blx = x;
    _bly = y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 1e-6 || d > r * 4) return; // at rest, or a teleport (kick-off reset)
    final kx = -dy / d, ky = dx / d, th = d / r; // axis (kz = 0)
    final c = math.cos(th), sn = math.sin(th), t = 1 - c;
    // Rodrigues rotation Q about (kx, ky, 0); R = Q * R
    final q0 = c + kx * kx * t, q1 = kx * ky * t, q2 = ky * sn;
    final q3 = kx * ky * t, q4 = c + ky * ky * t, q5 = -kx * sn;
    final q6 = -ky * sn, q7 = kx * sn, q8 = c;
    final R = _bR;
    final r0 = R[0], r1 = R[1], r2 = R[2], r3 = R[3], r4 = R[4], r5 = R[5], r6 = R[6], r7 = R[7], r8 = R[8];
    R[0] = q0 * r0 + q1 * r3 + q2 * r6;
    R[1] = q0 * r1 + q1 * r4 + q2 * r7;
    R[2] = q0 * r2 + q1 * r5 + q2 * r8;
    R[3] = q3 * r0 + q4 * r3 + q5 * r6;
    R[4] = q3 * r1 + q4 * r4 + q5 * r7;
    R[5] = q3 * r2 + q4 * r5 + q5 * r8;
    R[6] = q6 * r0 + q7 * r3 + q8 * r6;
    R[7] = q6 * r1 + q7 * r4 + q8 * r7;
    R[8] = q6 * r2 + q7 * r5 + q8 * r8;
    // re-orthonormalise (Gram-Schmidt on the columns) so float drift never skews the texture
    var l = math.sqrt(R[0] * R[0] + R[3] * R[3] + R[6] * R[6]);
    R[0] /= l;
    R[3] /= l;
    R[6] /= l;
    final dt = R[0] * R[1] + R[3] * R[4] + R[6] * R[7];
    R[1] -= dt * R[0];
    R[4] -= dt * R[3];
    R[7] -= dt * R[6];
    l = math.sqrt(R[1] * R[1] + R[4] * R[4] + R[7] * R[7]);
    R[1] /= l;
    R[4] /= l;
    R[7] /= l;
    R[2] = R[3] * R[7] - R[6] * R[4];
    R[5] = R[6] * R[1] - R[0] * R[7];
    R[8] = R[0] * R[4] - R[3] * R[1];
  }


  // Sphere mesh: the visible hemisphere of a unit sphere, orthographic, as rings x segments. Each vertex's normal
  // n is rotated by R^T into material space q; the texture (a front view of the ball) is wrapped on the front
  // hemisphere and mirrored on the back one (same mapping as the old shader). Triangles are emitted unindexed so a
  // triangle that straddles the front/back seam takes one side's mapping instead of smearing across the texture.
  static const int _bRings = 9, _bSegs = 26;
  static final int _bVerts = 1 + _bRings * _bSegs;
  late final Float32List _bN = () {
    final o = Float32List(_bVerts * 3);
    o[2] = 1;
    var k = 3;
    for (var i = 1; i <= _bRings; i++) {
      final rho = math.sin(i / _bRings * math.pi / 2) * (i == _bRings ? 1.0 : 1.0);
      final z = math.sqrt(math.max(0.0, 1 - rho * rho));
      for (var j = 0; j < _bSegs; j++) {
        final a = j / _bSegs * 2 * math.pi;
        o[k++] = rho * math.cos(a);
        o[k++] = rho * math.sin(a);
        o[k++] = z;
      }
    }
    return o;
  }();
  late final Uint16List _bTri = () {
    final o = <int>[];
    int at(int ring, int seg) => ring == 0 ? 0 : 1 + (ring - 1) * _bSegs + seg % _bSegs;
    for (var j = 0; j < _bSegs; j++) {
      o.addAll([0, at(1, j), at(1, j + 1)]);
    }
    for (var i = 1; i < _bRings; i++) {
      for (var j = 0; j < _bSegs; j++) {
        o.addAll([at(i, j), at(i + 1, j), at(i + 1, j + 1), at(i, j), at(i + 1, j + 1), at(i, j + 1)]);
      }
    }
    return Uint16List.fromList(o);
  }();
  late final Float32List _bQ = Float32List(_bVerts * 3);
  late final Float32List _bPos = () {
    final o = Float32List(_bTri.length * 2);
    for (var t = 0; t < _bTri.length; t++) {
      o[t * 2] = _bN[_bTri[t] * 3];
      o[t * 2 + 1] = _bN[_bTri[t] * 3 + 1];
    }
    return o;
  }();
  late final Float32List _bTex = Float32List(_bTri.length * 2);
  ui.Vertices? _bMesh;
  bool _bDirty = true;
  late final ui.Paint _ballTexP = ui.Paint()
    ..filterQuality = ui.FilterQuality.medium
    ..isAntiAlias = true
    ..shader = ui.ImageShader(im.ball, ui.TileMode.clamp, ui.TileMode.clamp, Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        filterQuality: ui.FilterQuality.medium);
  ui.Image? _ballLight, _ballHalo;
  final ui.Paint _ballRim = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..isAntiAlias = true
    ..color = const ui.Color(0x66000000);

  ui.Vertices _ballMesh() {
    if (!_bDirty && _bMesh != null) return _bMesh!;
    _bDirty = false;
    final R = _bR, n = _bN, q = _bQ;
    for (var v = 0; v < _bVerts; v++) {
      final nx = n[v * 3], ny = n[v * 3 + 1], nz = n[v * 3 + 2];
      q[v * 3] = R[0] * nx + R[3] * ny + R[6] * nz;
      q[v * 3 + 1] = R[1] * nx + R[4] * ny + R[7] * nz;
      q[v * 3 + 2] = R[2] * nx + R[5] * ny + R[8] * nz;
    }
    final tw = im.ball.width * .5, th = im.ball.height * .5;
    const k = .93;
    final tri = _bTri, tex = _bTex;
    for (var t = 0; t < tri.length; t += 3) {
      final a = tri[t], b = tri[t + 1], c = tri[t + 2];
      final back = q[a * 3 + 2] + q[b * 3 + 2] + q[c * 3 + 2] < 0;
      for (var m = 0; m < 3; m++) {
        final vi = tri[t + m];
        final ux = back ? -q[vi * 3] : q[vi * 3];
        tex[(t + m) * 2] = tw + ux * k * tw;
        tex[(t + m) * 2 + 1] = th + q[vi * 3 + 1] * k * th;
      }
    }
    _bMesh?.dispose();
    return _bMesh = ui.Vertices.raw(ui.VertexMode.triangles, _bPos, textureCoordinates: _bTex);
  }

  /// light (diffuse falloff + specular + faint blue rim) and halo sprites, baked once
  Future<void> _bakeBallSprites() async {
    const S = 128.0, c = ui.Offset(S / 2, S / 2);
    var rec = ui.PictureRecorder();
    var cv = ui.Canvas(rec);
    cv.drawCircle(c, S / 2, ui.Paint()..shader = ui.Gradient.radial(c.translate(-S * .15, -S * .18), S * .72, const [ui.Color(0x00000000), ui.Color(0x00000000), ui.Color(0x47000000), ui.Color(0x99000000)], const [0, .42, .78, 1]));
    cv.drawCircle(c, S / 2, ui.Paint()..shader = ui.Gradient.radial(c, S / 2, const [ui.Color(0x00598cff), ui.Color(0x00598cff), ui.Color(0x2e598cff)], const [0, .82, 1]));
    final hc = c.translate(-S * .19, -S * .21);
    cv.drawCircle(hc, S * .28, ui.Paint()..shader = ui.Gradient.radial(hc, S * .28, const [ui.Color(0xb3ffffff), ui.Color(0x26ffffff), ui.Color(0x00ffffff)], const [0, .45, 1]));
    _ballLight = await rec.endRecording().toImage(S.toInt(), S.toInt());
    rec = ui.PictureRecorder();
    cv = ui.Canvas(rec);
    cv.drawCircle(c, S / 2, ui.Paint()..shader = ui.Gradient.radial(c, S / 2, const [ui.Color(0x00b8bdc6), ui.Color(0x00b8bdc6), ui.Color(0x4db8bdc6), ui.Color(0x1aa0a6b0), ui.Color(0x00a0a6b0)], const [0, .56, .66, .82, 1]));
    _ballHalo = await rec.endRecording().toImage(S.toInt(), S.toInt());
  }

  static final ui.Rect _sprR = ui.Rect.fromLTWH(0, 0, 128, 128);
  ui.Rect get _shadowSrc => ui.Rect.fromLTWH(3.0 * spr, 0, spr.toDouble(), spr.toDouble());

  void _drawBall(ui.Canvas c, double al, double shx, double shy) {
    final b = e.ball;
    final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
    final r = math.max(4.0, b.r * (1 + b.sq * .08));
    final ctr = ui.Offset(x, y);
    final rot = _bR[0] + _bR[4] * 3 + _bR[8] * 5;
    _rollBall(x, y, b.r);
    if (_bR[0] + _bR[4] * 3 + _bR[8] * 5 != rot) _bDirty = true;
    // soft gray halo + drop shadow (offset down-right like the discs): cached sprites, no per-frame gradients
    if (_ballHalo != null) c.drawImageRect(_ballHalo!, _sprR, ui.Rect.fromCircle(center: ctr, radius: r * 1.6), _img);
    c.drawImageRect(atlas, _shadowSrc, ui.Rect.fromCircle(center: ctr.translate(r * .22, r * .3), radius: r * 1.18), _shadowP);
    // textured sphere
    c.save();
    c.translate(x, y);
    c.scale(r);
    c.drawVertices(_ballMesh(), ui.BlendMode.srcOver, _ballTexP);
    c.restore();
    // lighting stays screen top-left even on the flipped (rotated) online view
    if (_ballLight != null) {
      if (v.flipped) {
        c.save();
        c.translate(x, y);
        c.rotate(math.pi);
        c.drawImageRect(_ballLight!, _sprR, ui.Rect.fromCircle(center: ui.Offset.zero, radius: r), _img);
        c.restore();
      } else {
        c.drawImageRect(_ballLight!, _sprR, ui.Rect.fromCircle(center: ctr, radius: r), _img);
      }
    }
    _ballRim.strokeWidth = math.max(.8, 1.2 / v.s);
    c.drawCircle(ctr, r - _ballRim.strokeWidth * .4, _ballRim);
  }

  /// v0.6.1 ball speed trail: thin white streaks behind a fast ball (length and opacity grow with speed).
  final ui.Paint _streakP = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round;
  static const List<(double, double)> _streakL = [(-.62, .55), (-.31, .85), (0, 1), (.31, .8), (.62, .5)];
  void _drawStreaks(ui.Canvas c, double al) {
    final b = e.ball, sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    if (sp < 450) return;
    final k = ((sp - 450) / 2200).clamp(0.0, 1.0), r = b.r;
    final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
    final ux = b.vx / sp, uy = b.vy / sp, nx = -uy, ny = ux;
    final len = r * (2.2 + 8 * k);
    for (final (o, lk) in _streakL) {
      final sx = x + nx * o * r - ux * r * .35, sy = y + ny * o * r - uy * r * .35;
      final ex = sx - ux * len * lk, ey = sy - uy * len * lk;
      _streakP
        ..strokeWidth = 1.6 + .9 * k
        ..shader = ui.Gradient.linear(ui.Offset(sx, sy), ui.Offset(ex, ey), [ui.Color.fromRGBO(235, 245, 255, .25 + .5 * k), const ui.Color(0x00ffffff)]);
      c.drawLine(ui.Offset(sx, sy), ui.Offset(ex, ey), _streakP);
    }
    _streakP.shader = null;
  }

  void _drawTrail(ui.Canvas c) {
    final n = e.nTrail;
    if (n < 2) return;
    final cs = kTrails[ballIdx % kTrails.length].c;
    final bw = e.ball.r;
    _stroke.blendMode = ui.BlendMode.plus;
    const layers = [(2.2, .16, 0), (1.1, .42, 1), (.42, .95, 2)];
    for (final (w, a, ci) in layers) {
      if (!hq && ci == 0) continue;
      final cc = ui.Color(ci < cs.length ? cs[ci] : 0xffffffff);
      for (var i = 1; i < n; i++) {
        final k = i / n, qa = e.tA[i];
        _stroke
          ..strokeWidth = math.max(.6, bw * w * k * qa)
          ..color = cc.withValues(alpha: math.min(1, a * qa * (.35 + .65 * k)));
        c.drawLine(ui.Offset(e.tX[i - 1], e.tY[i - 1]), ui.Offset(e.tX[i], e.tY[i]), _stroke);
      }
    }
    _stroke.blendMode = ui.BlendMode.srcOver;
  }

  void _drawParts(ui.Canvas c) {
    final n = e.nParts;
    if (n == 0) return;
    final cap = hq ? n : math.min(n, 40);
    for (var i = 0; i < cap; i++) {
      final k = math.max(0.0, e.pL[i] / e.pM[i]);
      final rr = e.pR[i] * (e.pK[i] == 3 ? 1.3 : .6 + k * .8) * 1.6;
      final sc = 2 * rr / spr;
      _pxf[i * 4] = sc;
      _pxf[i * 4 + 1] = 0;
      _pxf[i * 4 + 2] = e.pX[i] - rr;
      _pxf[i * 4 + 3] = e.pY[i] - rr;
      _prc[i * 4] = 4.0 * spr;
      _prc[i * 4 + 1] = 0;
      _prc[i * 4 + 2] = 5.0 * spr;
      _prc[i * 4 + 3] = spr.toDouble();
      final a = (math.min(1, k * 1.2) * 255).round();
      _pcol[i] = (a << 24) | (e.pC[i] & 0xffffff);
    }
    c.drawRawAtlas(atlas, _vf(_pxf, cap * 4), _vf(_prc, cap * 4), _vi(_pcol, cap), ui.BlendMode.modulate, null, _addP);
  }

  // ---- goals ----
  // v4 net ripple (render-only, ~0.8 s decay): fired on a goal (rising edge of the engine's ripple) and whenever the
  // ball bounces off the net inside a goal (back wall / side walls). Hits are detected from the ball's interpolated
  // frame-to-frame motion, so it works offline, on the host and on interpolating online clients. Collision untouched.
  static const double _ripDur = .8;
  final Float64List _rip = Float64List(2), _ripX = Float64List(2), _ripK = Float64List(2), _shk = Float64List(2);
  final Float64List _lastER = Float64List(2), _cool = Float64List(2);
  double _lt = -1, _lbx = 0, _lby = 0, _lvx = 0, _lvy = 0;

  void _kick(int i, double x, double k) {
    if (_rip[i] * _ripK[i] <= k) {
      _rip[i] = 1;
      _ripX[i] = x;
      _ripK[i] = k;
    }
    _shk[i] = math.max(_shk[i], .3 * k);
    _cool[i] = .22;
  }

  void _netFx(double t, double al) {
    final dt = _lt < 0 ? 0.0 : (t - _lt).clamp(0.0, .1).toDouble();
    _lt = t;
    for (var i = 0; i < 2; i++) {
      _rip[i] = math.max(0, _rip[i] - dt / _ripDur);
      _shk[i] = math.max(0, _shk[i] - dt * 1.4);
      _cool[i] = math.max(0, _cool[i] - dt);
      final er = e.ripple[i];
      if (er > _lastER[i] + .3) _kick(i, e.rippleX[i], 1);
      _lastER[i] = er;
    }
    final b = e.ball;
    final bx = b.px + (b.x - b.px) * al, by = b.py + (b.y - b.py) * al;
    if (dt > 0) {
      final vx = (bx - _lbx) / dt, vy = (by - _lby) / dt;
      final moved = (bx - _lbx).abs() + (by - _lby).abs() > .01; // skip frames where the sim did not advance
      if (moved) {
        for (var i = 0; i < 2; i++) {
          if (_cool[i] > 0) continue;
          final g = e.goals[i];
          final dep = (by - g.y) * g.d; // depth into the goal mouth
          if (dep <= b.r * .5 || bx < g.x1 - b.r || bx > g.x2 + b.r) continue;
          final back = dep > e.DEPTH - b.r - 8 && _lvy * g.d > 40 && vy * g.d < _lvy * g.d * .4;
          final side = (bx < g.x1 + b.r + 8 && _lvx < -40 && vx > _lvx * .4) || (bx > g.x2 - b.r - 8 && _lvx > 40 && vx < _lvx * .4);
          if (back || side) _kick(i, bx, (math.sqrt(_lvx * _lvx + _lvy * _lvy) / 700).clamp(.3, 1.0).toDouble());
        }
        _lvx = vx;
        _lvy = vy;
      }
    }
    _lbx = bx;
    _lby = by;
  }

  bool _netAnim(int i) => _rip[i] > 0 || e.shake[i] > 0 || _shk[i] > 0;
  double _shakeX(int i, double t) => math.sin(t * 40) * 6 * math.max(e.shake[i], _shk[i]);

  void _drawNets(ui.Canvas c, double t) {
    for (var i = 0; i < 2; i++) {
      if (!_netAnim(i)) {
        _nets[i] ??= () {
          final rec = ui.PictureRecorder();
          _netInto(ui.Canvas(rec), i, t, false);
          return rec.endRecording();
        }();
        c.drawPicture(_nets[i]!);
      } else {
        _netInto(c, i, t, true);
      }
    }
  }

  // v0.6.1b goals (owner: "goals look bad"): a clean, slim top-down frame. The crossbar lies ON the goal line between
  // two round posts, slim side bars run back to a back bar (slightly inset = depth), and the net is a fine diamond
  // mesh over a dark floor that fades towards the back, with an inner shadow under the crossbar. Collision geometry
  // (e.goals) is untouched. Skins recolour the frame and use their own net texture.
  static const int _nu = 12, _nv = 6;
  final Float32List _vPos = Float32List((_nu + 1) * (_nv + 1) * 2), _vTex = Float32List((_nu + 1) * (_nv + 1) * 2);
  late final Uint16List _vIdx = () {
    final out = <int>[];
    for (var j = 0; j < _nv; j++) {
      for (var k = 0; k < _nu; k++) {
        final a = j * (_nu + 1) + k, b = a + 1, c2 = a + _nu + 1, d2 = c2 + 1;
        out.addAll([a, b, d2, a, d2, c2]);
      }
    }
    return Uint16List.fromList(out);
  }();
  ui.Paint? _netTexP;
  late final List<ui.Color> _pal = [for (final v in im.skin.pal) ui.Color(v)];
  late final ui.Color _netCol = ui.Color(im.skin.netCol);

  double _bulge(double x, double k, double t, int i, bool anim) {
    if (!anim || _rip[i] <= 0) return 0;
    final rp = _rip[i], dx = x - _ripX[i], sig = 55 + (1 - rp) * 80;
    return e.goals[i].d * rp * 17 * _ripK[i] * k * math.exp(-(dx * dx) / (sig * sig)) * (.62 + .38 * math.sin(t * 24 - dx.abs() / 14));
  }

  /// goal corners: front posts (x1, x2 at the goal line y0) and the inset back corners (bx1, bx2 at yb)
  (double, double, double, double, double, double) _goalBox(int i) {
    final g = e.goals[i];
    final x1 = g.x1, x2 = g.x2, D = e.DEPTH + 4, y0 = g.y, yb = g.y + g.d * D;
    final inset = (x2 - x1) * .035;
    return (x1, x2, x1 + inset, x2 - inset, y0, yb);
  }

  void _netInto(ui.Canvas c, int i, double t, bool anim) {
    final g = e.goals[i];
    final d = g.d.toDouble();
    final (x1, x2, bx1, bx2, y0, yb) = _goalBox(i);
    final sx = anim ? _shakeX(i, t) : 0.0;
    final tex = im.net;
    c.save();
    c.translate(sx, 0);
    _path
      ..reset()
      ..moveTo(x1, y0)
      ..lineTo(x2, y0)
      ..lineTo(bx2, yb)
      ..lineTo(bx1, yb)
      ..close();
    // floor: dark, a little darker at the back
    _fill.shader = ui.Gradient.linear(ui.Offset(0, y0), ui.Offset(0, yb), const [ui.Color(0x66101a24), ui.Color(0xb3050a12)]);
    c.drawPath(_path, _fill);
    _fill.shader = null;
    c.save();
    c.clipPath(_path);
    if (tex != null) {
      final tw = tex.width.toDouble() * 1.9, k = tw / (x2 - x1); // x1.9: finer cells that read as a net on a phone
      var o = 0;
      for (var j = 0; j <= _nv; j++) {
        final vv = j / _nv;
        for (var q = 0; q <= _nu; q++) {
          final u = q / _nu;
          final fx = x1 + (x2 - x1) * u, rx = bx1 + (bx2 - bx1) * u;
          final px = fx + (rx - fx) * vv, py = y0 + (yb - y0) * vv;
          _vPos[o] = px;
          _vPos[o + 1] = py + _bulge(px, math.sin(vv * math.pi), t, i, anim);
          _vTex[o] = u * tw;
          _vTex[o + 1] = vv * (yb - y0).abs() * k;
          o += 2;
        }
      }
      _netTexP ??= ui.Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..color = _netCol.withValues(alpha: .62)
        ..shader = ui.ImageShader(tex, ui.TileMode.repeated, ui.TileMode.repeated, Float64List.fromList(const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
      c.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, _vPos, textureCoordinates: _vTex, indices: _vIdx), ui.BlendMode.srcOver, _netTexP!);
    } else {
      // fine diamond mesh (two families of diagonals), brighter at the front
      final w = x2 - x1, step = 13.0, n = (w / step).ceil() + 8;
      final dep = (yb - y0).abs();
      _netP.strokeWidth = 1.0;
      for (var fam = -1; fam <= 1; fam += 2) {
        for (var k = -8; k <= n; k++) {
          final xa = x1 + k * step;
          _path
            ..reset()
            ..moveTo(xa, y0);
          for (var j = 1; j <= 6; j++) {
            final vv = j / 6, px = xa + fam * dep * vv;
            _path.lineTo(px, y0 + d * dep * vv + _bulge(px, math.sin(vv * math.pi), t, i, anim));
          }
          _netP.color = const ui.Color(0x5cffffff);
          c.drawPath(_path, _netP);
        }
      }
    }
    // inner shadow under the crossbar + soft side shading = depth
    _fill.shader = ui.Gradient.linear(ui.Offset(0, y0), ui.Offset(0, y0 + d * 22), const [ui.Color(0x8c000000), ui.Color(0x00000000)]);
    c.drawRect(ui.Rect.fromLTRB(x1 - 4, math.min(y0, y0 + d * 22), x2 + 4, math.max(y0, y0 + d * 22)), _fill);
    _fill.shader = ui.Gradient.linear(ui.Offset(x1, 0), ui.Offset(x2, 0), const [ui.Color(0x59000000), ui.Color(0x00000000), ui.Color(0x00000000), ui.Color(0x59000000)], const [0, .12, .88, 1]);
    c.drawRect(ui.Rect.fromLTRB(x1 - 4, math.min(y0, yb), x2 + 4, math.max(y0, yb)), _fill);
    _fill.shader = null;
    c.restore();
    c.restore();
  }

  void _drawFrames(ui.Canvas c, double t) {
    final pal = _pal, classic = im.net == null;
    final light = classic ? const ui.Color(0xfff4f7fb) : ui.Color.lerp(pal[1], const ui.Color(0xffffffff), .35)!;
    final mid = classic ? const ui.Color(0xffc9d2de) : pal[2];
    final dark = classic ? const ui.Color(0xff6f7b8c) : pal[3];
    for (var i = 0; i < 2; i++) {
      final sx = _shakeX(i, t);
      final (x1r, x2r, bx1r, bx2r, y0, yb) = _goalBox(i);
      final x1 = x1r + sx, x2 = x2r + sx, bx1 = bx1r + sx, bx2 = bx2r + sx;
      final rb = _bulge((bx1 + bx2) / 2, .25, t, i, _netAnim(i)) * .3;
      final back = [ui.Offset(x1, y0), ui.Offset(bx1, yb + rb), ui.Offset(bx2, yb + rb), ui.Offset(x2, y0)];
      // soft drop shadow of the whole frame on the grass (light from the top-left)
      _bar
        ..shader = null
        ..strokeWidth = 6
        ..color = const ui.Color(0x55000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
      _path
        ..reset()
        ..addPolygon([for (final p in back) p.translate(3, 4)], false)
        ..moveTo(x1 + 3, y0 + 4)
        ..lineTo(x2 + 3, y0 + 4);
      c.drawPath(_path, _bar);
      _bar.maskFilter = null;
      // side + back bars (thin, slightly darker = further away)
      _bar
        ..strokeWidth = 3.2
        ..color = dark;
      _path
        ..reset()
        ..addPolygon(back, false);
      c.drawPath(_path, _bar);
      _bar
        ..strokeWidth = 1.6
        ..color = mid;
      c.drawPath(_path, _bar);
      // crossbar on the goal line: tube shading across its width + highlight
      const cw = 6.0;
      _bar
        ..strokeWidth = cw
        ..shader = ui.Gradient.linear(ui.Offset(0, y0 - cw / 2), ui.Offset(0, y0 + cw / 2), [light, mid, dark], const [0, .5, 1]);
      c.drawLine(ui.Offset(x1, y0), ui.Offset(x2, y0), _bar);
      _bar
        ..shader = null
        ..strokeWidth = 1.4
        ..color = const ui.Color(0xe6ffffff);
      c.drawLine(ui.Offset(x1 + 3, y0 - 1.2), ui.Offset(x2 - 3, y0 - 1.2), _bar);
      // round posts
      for (final px in [x1, x2]) {
        _fill
          ..color = const ui.Color(0x66000000)
          ..shader = null;
        c.drawCircle(ui.Offset(px + 2.5, y0 + 3), POST_R * .95, _fill);
        _fill.shader = ui.Gradient.radial(ui.Offset(px - POST_R * .35, y0 - POST_R * .35), POST_R * 1.3, [light, mid, dark], const [0, .55, 1]);
        c.drawCircle(ui.Offset(px, y0), POST_R * .9, _fill);
      }
      _fill.shader = null;
    }
  }

  // ---- aim ----
  ui.Color _mix(ui.Color a, ui.Color b, double k) => ui.Color.lerp(a, b, k)!;
  ui.Color _powerCol(double p) => p < .5 ? _mix(_aimC[0], _aimC[1], p / .5) : _mix(_aimC[1], _aimC[2], (p - .5) / .5);

  void _drawAim(ui.Canvas c, double t, double x, double y) {
    final a = e.aimInfo();
    if (a == null || a.p <= 0) {
      _aimOn = false;
      return;
    }
    if (!_aimOn) {
      _aux = a.ux;
      _auy = a.uy;
      _ap = a.p;
      _aimOn = true;
    } else {
      _aux += (a.ux - _aux) * .55;
      _auy += (a.uy - _auy) * .55;
      _ap += (a.p - _ap) * .6;
    }
    var ul = math.sqrt(_aux * _aux + _auy * _auy);
    if (ul == 0) ul = 1;
    final b = a.b!, team = b.team, r = b.r;
    // v4: low accuracy -> the arrow wobbles (visual only; the real deviation is rolled in Engine.fire)
    final wob = e.cfg.stats != null ? aimDevDeg(e.statsOf(team).accuracy) * .45 * math.pi / 180 * math.sin(t * 7.3) * (.4 + .6 * _ap) : 0.0;
    final cw = math.cos(wob), sw = math.sin(wob);
    final ux = (_aux * cw - _auy * sw) / ul, uy = (_aux * sw + _auy * cw) / ul, pw = _ap;
    // Nexora_godot (0c5c3a9): the arrow beyond the rim grows LINEARLY with power from a short stub
    // (AIM_MIN_K x r) to AIM_MAX_K x r; classic keeps the RN lengths.
    final shortLong = e.godot;
    final Lg = r + 4 + r * (_aimMinK + (_aimMaxK - _aimMinK) * pw.clamp(0.0, 1.0));
    double L;
    if (im.aim != null) {
      L = _aimSprite(c, x, y, ux, uy, r, pw, shortLong ? Lg : r + 70 + pw * 110);
    } else if (im.hasArrow) {
      L = _arrowArt(c, t, x, y, ux, uy, r, pw, shortLong ? Lg : null);
    } else {
      final nx = -uy, ny = ux;
      final l0 = r + 6, lmax = r + 250;
      L = shortLong ? Lg : r + 34 + pw * 216;
      // short arrows get a proportionally smaller head so the stub still reads as an arrow
      final hs = shortLong ? math.min(20 + pw * 8, (L - l0) * .6) : 20 + pw * 8;
      final w0 = 9 + pw * 5, w1 = 3.0, neck = L - hs;
      _path
        ..reset()
        ..moveTo(x + ux * l0 + nx * w0, y + uy * l0 + ny * w0)
        ..lineTo(x + ux * neck + nx * w1, y + uy * neck + ny * w1)
        ..lineTo(x + ux * neck + nx * hs * .62, y + uy * neck + ny * hs * .62)
        ..lineTo(x + ux * L, y + uy * L)
        ..lineTo(x + ux * neck - nx * hs * .62, y + uy * neck - ny * hs * .62)
        ..lineTo(x + ux * neck - nx * w1, y + uy * neck - ny * w1)
        ..lineTo(x + ux * l0 - nx * w0, y + uy * l0 - ny * w0)
        ..close();
      _fill.shader = ui.Gradient.linear(ui.Offset(x + ux * l0, y + uy * l0), ui.Offset(x + ux * lmax, y + uy * lmax), _aimC, const [0, .5, 1]);
      c.drawPath(_path, _fill);
      _fill.shader = null;
    }
    final pc = _powerCol(pw);
    _stroke
      ..strokeWidth = 4
      ..color = pc.withValues(alpha: .9);
    c.drawArc(ui.Rect.fromCircle(center: ui.Offset(x, y), radius: r + 9), -math.pi / 2, 2 * math.pi * pw, false, _stroke);
    final steps = shortLong
        ? math.max(2, ((3 + pw * 4) * (e.cfg.stats != null ? aimPreview(e.statsOf(team).accuracy) : 1)).round())
        : math.max(2, ((5 + pw * 6) * (e.cfg.stats != null ? aimPreview(e.statsOf(team).accuracy) : 1)).round());
    for (var i = 1; i <= steps; i++) {
      final d = L + 8 + i * (shortLong ? 12 : 22), k = 1 - i / (steps + 1);
      if (shortLong && d > L + r * .7) break; // Godot: accuracy dots stay just past the tip
      _addP.color = pc.withValues(alpha: .6 * k);
      c.drawCircle(ui.Offset(x + ux * d, y + uy * d), 2.2 + 2 * k, _addP);
    }
    _addP.color = const ui.Color(0xffffffff);
    _stroke
      ..strokeWidth = 2.5
      ..color = const ui.Color(0x2effffff);
    c.drawLine(ui.Offset(x - ux * r, y - uy * r), ui.Offset(x - ux * (r + 18 + pw * 60), y - uy * (r + 18 + pw * 60)), _stroke);
  }

  /// v0.6.1 aim arrow: one silver sprite, head drawn at a fixed aspect and the shaft stretched to the pull length,
  /// over a soft glow in the power colour.
  final ui.Paint _aimGlow = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7);
  double _aimSprite(ui.Canvas c, double x, double y, double ux, double uy, double r, double pw, double L) {
    final img = im.aim!, iw = img.width.toDouble(), ih = img.height.toDouble(), hsrc = ih * 152 / 512;
    final l0 = r + 4;
    var ww = r * (.78 + .22 * pw), hh = ww * hsrc / iw;
    final len = L - l0;
    if (len < hh * 1.4) {
      ww *= len / (hh * 1.4);
      hh = ww * hsrc / iw;
    }
    c.save();
    c.translate(x, y);
    c.rotate(math.atan2(uy, ux) + math.pi / 2);
    _aimGlow
      ..strokeWidth = ww * .35
      ..color = _powerCol(pw).withValues(alpha: .55);
    c.drawLine(ui.Offset(0, -l0 - 4), ui.Offset(0, -L + hh * .4), _aimGlow);
    _art.color = const ui.Color(0xffffffff);
    c.drawImageRect(img, ui.Rect.fromLTWH(0, hsrc, iw, ih - hsrc), ui.Rect.fromLTWH(-ww / 2, -L + hh, ww, math.max(1, len - hh)), _art);
    c.drawImageRect(img, ui.Rect.fromLTWH(0, 0, iw, hsrc), ui.Rect.fromLTWH(-ww / 2, -L, ww, hh), _art);
    c.restore();
    return L;
  }

  double _arrowArt(ui.Canvas c, double t, double x, double y, double ux, double uy, double r, double pw, [double? lOverride]) {
    final l0 = r + 3, L = lOverride ?? r + 70 + pw * 110;
    final ae = _sstep(.66, .72, pw), as_ = 1 - _sstep(.7, .75, pw);
    c.save();
    c.translate(x, y);
    c.rotate(math.atan2(uy, ux) + math.pi / 2);
    if (as_ > 0) {
      _art.color = ui.Color.fromRGBO(255, 255, 255, as_);
      _slices(c, im.headS!, im.shaftS!, _artS, l0, L, _art);
    }
    if (ae > 0) {
      _art.color = ui.Color.fromRGBO(255, 255, 255, ae);
      _slices(c, im.headE!, im.shaftE!, _artE, l0, L, _art);
      final pulse = .5 + .5 * math.sin(t * (6 + pw * 8));
      _artGlow.color = ui.Color.fromRGBO(255, 255, 255, (ae * (.06 + .16 * pulse) * pw).clamp(0, 1));
      _slices(c, im.headE!, im.shaftE!, _artE, l0, L, _artGlow);
    }
    c.restore();
    return L;
  }

  void _slices(ui.Canvas c, ui.Image head, ui.Image shaft, _ArtK k, double l0, double L, ui.Paint p) {
    final hw = k.hh * head.width / head.height, sh = shaft.height.toDouble(), sW = shaft.width.toDouble();
    final y0 = sh * k.top, y1 = sh * k.tail, x0 = -k.sw / 2;
    final neck = L - k.hh * k.join;
    final len = math.max(2.0, neck - l0);
    var topL = k.topLen, tailL = k.tailLen;
    if (topL + tailL > len * .8) {
      final f = len * .8 / (topL + tailL);
      topL *= f;
      tailL *= f;
    }
    final mid = len - topL - tailL;
    void draw(double sy0, double sy1, double dy, double dh) => c.drawImageRect(shaft, ui.Rect.fromLTWH(0, sy0, sW, sy1 - sy0), ui.Rect.fromLTWH(x0, dy, k.sw, dh), p);
    draw(y1, sh, -l0 - tailL, tailL);
    if (mid > 0) draw(y0, y1, -neck + topL, mid);
    if (topL > 0) draw(0, y0, -neck, topL);
    c.drawImageRect(head, ui.Rect.fromLTWH(0, 0, head.width.toDouble(), head.height.toDouble()), ui.Rect.fromLTWH(-hw / 2, -L, hw, k.hh), p);
  }
}
