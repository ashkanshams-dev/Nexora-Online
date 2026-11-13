// NEXORA match renderer — Flutter Canvas + FragmentShader port of src/game/render.ts (Skia).
//
// Same layering, geometry and art as the RN renderer (field, discs, ball sphere shader, ribbon trail, goal art,
// sliced aim-arrow art, particles, flash), plus quality-gated extras on "high":
//   * dynamic light: a soft floor light that follows the ball, contact shadows under discs,
//   * glossy pitch reflections of ball + discs (screen-space mirror, faded),
//   * batched GPU particles (one drawRawAtlas call with a soft-dot sprite, additive),
//   * goal post-FX pass (post.frag): anamorphic flare, god rays, chromatic shock ring, vignette.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../ui/theme.dart' show hex;
import 'data.dart';
import 'engine.dart';

class ArrowImages {
  final ui.Image? headE, headS, shaftE, shaftS;
  const ArrowImages({this.headE, this.headS, this.shaftE, this.shaftS});
  bool get ok => headE != null && headS != null && shaftE != null && shaftS != null;
}

class MatchImages {
  ui.Image? field, goal, ball, t0, t1;
  ArrowImages arrow = const ArrowImages();
}

class GView {
  final double W, H, s, ox, oy;
  const GView(this.W, this.H, this.s, this.ox, this.oy);
}

GView computeView(Engine e, double W, double H, double top, double bottom) {
  final f = e.f;
  const fsc = 1.12;
  final playH = math.max(300.0, H - top - bottom);
  final s = math.min(W / (f.R - f.L + 56 * fsc), playH / ((f.B - f.T) + 2 * e.GG.h + 48)) * .99;
  return GView(W, H, s, W / 2 - e.CX * s, top + playH / 2 - e.CY * s);
}

Offset toWorld(GView v, double x, double y) => Offset((x - v.ox) / v.s, (y - v.oy) / v.s);

const _TEAM_GLOW = ['#3bb6ff', '#ff5b6b'];
const _AIM_C = ['#3b8bff', '#9b5cff', '#ff3b5c'];

class _ArtK {
  final double hh, join, sw, top, tail, topLen, tailLen;
  const _ArtK(this.hh, this.join, this.sw, this.top, this.tail, this.topLen, this.tailLen);
}

const _ART_E = _ArtK(96, .82, 124, 0, .734, 0, 46);
const _ART_S = _ArtK(68, .928, 32.5, 0, .704, 0, 38);

double _sstep(double a, double b, double v) {
  final k = math.min(1.0, math.max(0.0, (v - a) / (b - a)));
  return k * k * (3 - 2 * k);
}

class MatchRenderer {
  final Engine e;
  final MatchImages im;
  final int ballIdx;
  bool hq;
  ui.FragmentShader? ballShader;
  ui.FragmentShader? postShader;
  ui.Picture? _bg;
  GView? _bgView;
  ui.Picture? _goals;
  ui.Image? _dot; // soft particle sprite (built once)
  ui.Image? _shadow;
  final Map<ui.Image?, ui.ImageShader> _imgShaders = {};
  // aim smoothing
  bool _aimOn = false;
  double _aux = 0, _auy = -1, _ap = 0;
  // flare state for post pass
  double _ringT = 0;
  int _ringTeam = 0;

  MatchRenderer(this.e, this.im, this.ballIdx, {this.hq = true});

  final _p = Paint()..isAntiAlias = true;

  // ------------------------------------------------------------- one-time sprites
  Future<void> prepare() async {
    _dot = await _makeImg(64, 64, (c) {
      final p = Paint()
        ..shader = ui.Gradient.radial(const Offset(32, 32), 32, [const Color(0xFFFFFFFF), const Color(0x88FFFFFF), const Color(0x00FFFFFF)], [0, .35, 1]);
      c.drawCircle(const Offset(32, 32), 32, p);
    });
    _shadow = await _makeImg(128, 128, (c) {
      final p = Paint()
        ..shader = ui.Gradient.radial(const Offset(64, 64), 64, [const Color(0xFF000000), const Color(0x80000000), const Color(0x00000000)], [0, .55, 1]);
      c.drawCircle(const Offset(64, 64), 64, p);
    });
  }

  static Future<ui.Image> _makeImg(int w, int h, void Function(Canvas c) draw) {
    final rec = ui.PictureRecorder();
    draw(Canvas(rec));
    return rec.endRecording().toImage(w, h);
  }

  // ------------------------------------------------------------- static layer
  ui.Picture _staticLayer(GView v) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(Rect.fromLTWH(0, 0, v.W, v.H), Paint()..color = hex('#02040c'));
    final f = e.f, img = im.field;
    if (img != null) {
      final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      final k = math.max(v.W / f.W, v.H / f.H) * 1.05;
      c.drawImageRect(img, src, Rect.fromLTWH((v.W - f.W * k) / 2, (v.H - f.H * k) / 2, f.W * k, f.H * k),
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.clamp));
      c.drawRect(Rect.fromLTWH(0, 0, v.W, v.H), Paint()..color = const Color.fromRGBO(2, 4, 14, .62));
      c.save();
      c.translate(v.ox, v.oy);
      c.scale(v.s, v.s);
      final fw = f.W.toDouble(), fh = f.H.toDouble();
      c.saveLayer(Rect.fromLTWH(-40, -40, fw + 80, fh + 80), Paint());
      c.drawImageRect(img, src, Rect.fromLTWH(0, 0, fw, fh), Paint()..filterQuality = FilterQuality.medium);
      const k0 = Color(0x00000000), k1 = Color(0xFF000000);
      c.drawRect(Rect.fromLTWH(0, 0, fw, fh),
          Paint()..blendMode = BlendMode.dstIn..shader = ui.Gradient.linear(Offset.zero, Offset(0, fh), [k0, k1, k1, k0], [0, .06, .94, 1]));
      c.drawRect(Rect.fromLTWH(0, 0, fw, fh),
          Paint()..blendMode = BlendMode.dstIn..shader = ui.Gradient.linear(Offset.zero, Offset(fw, 0), [k0, k1, k1, k0], [0, .05, .95, 1]));
      c.restore();
      if (hq) {
        // stadium light pools: two soft cones from the stands (additive, static so it costs nothing per frame)
        for (final cx in [e.F.l + (e.F.r - e.F.l) * .22, e.F.l + (e.F.r - e.F.l) * .78]) {
          c.drawCircle(Offset(cx, e.CY), (e.F.b - e.F.t) * .55,
              Paint()
                ..blendMode = BlendMode.plus
                ..shader = ui.Gradient.radial(Offset(cx, e.CY), (e.F.b - e.F.t) * .55, [const Color(0x14FFFFFF), const Color(0x00FFFFFF)]));
        }
      }
      final Fr = e.F;
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(Fr.l, Fr.t, Fr.r, Fr.b), const Radius.circular(70)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color.fromRGBO(120, 220, 255, .35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      c.restore();
    }
    return rec.endRecording();
  }

  // ------------------------------------------------------------- pieces
  void _shadowAt(Canvas c, double x, double y, double r, double a) {
    final s = _shadow;
    if (s == null) return;
    final R = r * 1.3;
    c.drawImageRect(s, const Rect.fromLTWH(0, 0, 128, 128), Rect.fromLTWH(x + r * .14 - R, y + r * .26 - R, 2 * R, 2 * R),
        Paint()..color = Color.fromRGBO(0, 0, 0, a)..filterQuality = FilterQuality.low);
  }

  void _drawPiece(Canvas c, Body b, double x, double y, ui.Image? img, double t, bool active) {
    final team = b.team, sc = 1 + b.sq * .07, r = b.r * sc;
    if (hq) _shadowAt(c, x, y, r * .92, .42);
    if (active) {
      final pulse = .5 + .5 * math.sin(t * 4);
      c.drawCircle(Offset(x, y), r + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..blendMode = BlendMode.plus
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
            ..color = hex(_TEAM_GLOW[team], .35 + .25 * pulse));
      c.drawCircle(Offset(x, y), r + 2.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..isAntiAlias = true
            ..color = hex(_TEAM_GLOW[team], .85 + .15 * pulse));
    }
    c.save();
    c.translate(x, y);
    c.rotate(b.ang);
    if (img != null) {
      final rr = Rect.fromLTWH(-r, -r, 2 * r, 2 * r);
      c.save();
      c.clipPath(Path()..addOval(rr));
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), rr, _p..filterQuality = FilterQuality.medium);
      c.restore();
    } else {
      c.drawCircle(Offset.zero, r, Paint()..color = hex(team == 1 ? '#c0283c' : '#2a6cff'));
    }
    c.restore();
  }

  // ------------------------------------------------------------- ball
  void _drawBall(Canvas c, Body b, double x, double y, ui.Image? img, double s) {
    final r = b.r * (1 + b.sq * .08);
    _shadowAt(c, x, y, r, .55);
    _shadowAt(c, x - r * .06, y - r * .12, r * .78, .5);
    final sh = ballShader;
    if (img == null || sh == null) {
      c.drawCircle(Offset(x, y), r, Paint()..color = Colors.white);
      return;
    }
    final R = b.R;
    var i = 0;
    sh
      ..setFloat(i++, 0) // uCenter (local space)
      ..setFloat(i++, 0)
      ..setFloat(i++, 1) // uRadius
      ..setFloat(i++, R[0])
      ..setFloat(i++, R[3])
      ..setFloat(i++, R[6])
      ..setFloat(i++, R[1])
      ..setFloat(i++, R[4])
      ..setFloat(i++, R[7])
      ..setFloat(i++, R[2])
      ..setFloat(i++, R[5])
      ..setFloat(i++, R[8])
      ..setFloat(i++, math.min(.2, 1.6 / (r * s)))
      ..setFloat(i++, hq ? 1 : 0)
      ..setImageSampler(0, img);
    c.save();
    c.translate(x, y);
    c.scale(r, r);
    c.drawRect(const Rect.fromLTWH(-1, -1, 2, 2), Paint()..shader = sh);
    c.restore();
  }

  // ------------------------------------------------------------- trail ribbon
  Path _ribbon(List<Pt> tr, double hx, double hy, double w) {
    final n = tr.length, L = <double>[], Rr = <double>[];
    for (var i = 0; i < n; i++) {
      final q = tr[i], nx = i + 1 < n ? tr[i + 1] : Pt(hx, hy), pv = i > 0 ? tr[i - 1] : q;
      var dx = nx.x - pv.x, dy = nx.y - pv.y;
      var l = math.sqrt(dx * dx + dy * dy);
      if (l == 0) l = 1;
      dx /= l;
      dy /= l;
      final k = (i + 1) / (n + 1), hw = w * k * math.max(.15, q.a);
      L..add(q.x - dy * hw)..add(q.y + dx * hw);
      Rr..add(q.x + dy * hw)..add(q.y - dx * hw);
    }
    final p = Path()..moveTo(L[0], L[1]);
    for (var i = 2; i < L.length; i += 2) {
      p.lineTo(L[i], L[i + 1]);
    }
    p.lineTo(hx, hy);
    for (var i = Rr.length - 2; i >= 0; i -= 2) {
      p.lineTo(Rr[i], Rr[i + 1]);
    }
    return p..close();
  }

  void _drawTrail(Canvas c, double hx, double hy) {
    final tr = e.trail, n = tr.length;
    if (n < 3) return;
    final cs = TRAILS[ballIdx % TRAILS.length].c, bw = e.ball.r, t0 = tr[0], head = tr[n - 1].a;
    final a0 = Offset(t0.x, t0.y), a1 = Offset(hx, hy);
    c.drawPath(
        _ribbon(tr, hx, hy, bw * 1.15),
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
          ..shader = ui.Gradient.linear(a0, a1, [hex(cs[0], 0), hex(cs[0], .55 * head), hex(cs.length > 1 ? cs[1] : cs[0], .9 * head)], [0, .6, 1]));
    final core = cs.length > 2 ? cs[2] : '#ffffff';
    c.drawPath(_ribbon(tr, hx, hy, bw * .32),
        Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.linear(a0, a1, [hex(core, 0), hex(core, .95 * head)]));
  }

  // ------------------------------------------------------------- aim arrow (sliced art)
  void _drawSlices(Canvas c, ui.Image head, ui.Image shaft, _ArtK k, double L0, double L, Paint p) {
    final hw = k.hh * head.width / head.height, sh = shaft.height.toDouble(), sW = shaft.width.toDouble();
    final y0 = sh * k.top, y1 = sh * k.tail, x0 = -k.sw / 2;
    final neck = L - k.hh * k.join, len = math.max(2.0, neck - L0);
    var topL = k.topLen, tailL = k.tailLen;
    if (topL + tailL > len * .8) {
      final f = len * .8 / (topL + tailL);
      topL *= f;
      tailL *= f;
    }
    final mid = len - topL - tailL;
    void draw(double sy0, double sy1, double dy, double dh) =>
        c.drawImageRect(shaft, Rect.fromLTWH(0, sy0, sW, sy1 - sy0), Rect.fromLTWH(x0, dy, k.sw, dh), p);
    draw(y1, sh, -L0 - tailL, tailL);
    if (mid > 0) draw(y0, y1, -neck + topL, mid);
    if (topL > 0) draw(0, y0, -neck, topL);
    c.drawImageRect(head, Rect.fromLTWH(0, 0, head.width.toDouble(), head.height.toDouble()), Rect.fromLTWH(-hw / 2, -L, hw, k.hh), p);
  }

  double _drawArrowArt(Canvas c, ArrowImages ar, double t, double x, double y, double ux, double uy, double r, double pw) {
    final L0 = r + 3, L = r + 70 + pw * 110;
    final ae = _sstep(.66, .72, pw), as_ = 1 - _sstep(.7, .75, pw);
    c.save();
    c.translate(x, y);
    c.rotate(math.atan2(uy, ux) + math.pi / 2);
    final p = Paint()..filterQuality = FilterQuality.medium..isAntiAlias = false;
    if (as_ > 0) _drawSlices(c, ar.headS!, ar.shaftS!, _ART_S, L0, L, p..color = Color.fromRGBO(255, 255, 255, as_));
    if (ae > 0) {
      _drawSlices(c, ar.headE!, ar.shaftE!, _ART_E, L0, L, p..color = Color.fromRGBO(255, 255, 255, ae));
      final pulse = .5 + .5 * math.sin(t * (6 + pw * 8));
      _drawSlices(c, ar.headE!, ar.shaftE!, _ART_E, L0, L,
          Paint()..blendMode = BlendMode.plus..color = Color.fromRGBO(255, 255, 255, (ae * (.06 + .16 * pulse) * pw).clamp(0, 1)));
    }
    c.restore();
    return L;
  }

  Color _powerCol(double p) => p < .5 ? Color.lerp(hex(_AIM_C[0]), hex(_AIM_C[1]), p / .5)! : Color.lerp(hex(_AIM_C[1]), hex(_AIM_C[2]), (p - .5) / .5)!;

  void _drawAim(Canvas c, double t, double x, double y) {
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
    final ux = _aux / ul, uy = _auy / ul, pw = _ap;
    final b = a.b, team = b.team, r = b.r, nx = -uy, ny = ux;
    double L;
    if (im.arrow.ok) {
      L = _drawArrowArt(c, im.arrow, t, x, y, ux, uy, r, pw);
    } else {
      final L0 = r + 6, Lmax = r + 250;
      L = r + 34 + pw * 216;
      final w0 = 9 + pw * 5, w1 = 3.0, hs = 20 + pw * 8, neck = L - hs;
      final path = Path()
        ..moveTo(x + ux * L0 + nx * w0, y + uy * L0 + ny * w0)
        ..lineTo(x + ux * neck + nx * w1, y + uy * neck + ny * w1)
        ..lineTo(x + ux * neck + nx * hs * .62, y + uy * neck + ny * hs * .62)
        ..lineTo(x + ux * L, y + uy * L)
        ..lineTo(x + ux * neck - nx * hs * .62, y + uy * neck - ny * hs * .62)
        ..lineTo(x + ux * neck - nx * w1, y + uy * neck - ny * w1)
        ..lineTo(x + ux * L0 - nx * w0, y + uy * L0 - ny * w0)
        ..close();
      final sh = ui.Gradient.linear(Offset(x + ux * L0, y + uy * L0), Offset(x + ux * Lmax, y + uy * Lmax), _AIM_C.map((s) => hex(s)).toList(), [0, .5, 1]);
      c.drawPath(path, Paint()..shader = sh..blendMode = BlendMode.plus..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
      c.drawPath(path, Paint()..shader = sh);
    }
    final pc = _powerCol(pw);
    c.drawArc(Rect.fromLTWH(x - r - 9, y - r - 9, (r + 9) * 2, (r + 9) * 2), -math.pi / 2, math.pi * 2 * pw, false,
        Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = 4..color = pc.withValues(alpha: .9));
    final steps = math.max(2, ((5 + pw * 6) * (e.cfg.stats != null ? aimPreview(e.statsOf(team).accuracy) : 1)).round());
    final ad = Paint()..blendMode = BlendMode.plus;
    for (var i = 1; i <= steps; i++) {
      final d = L + 8 + i * 22, k = 1 - i / (steps + 1);
      c.drawCircle(Offset(x + ux * d, y + uy * d), 2.2 + 2 * k, ad..color = pc.withValues(alpha: .6 * k));
    }
    c.drawLine(Offset(x - ux * r, y - uy * r), Offset(x - ux * (r + 18 + pw * 60), y - uy * (r + 18 + pw * 60)),
        Paint()..strokeWidth = 2.5..strokeCap = StrokeCap.round..color = const Color.fromRGBO(255, 255, 255, .18));
  }

  // ------------------------------------------------------------- particles (batched atlas)
  final Map<String, Color> _colCache = {};
  void _drawParts(Canvas c) {
    final ps = e.parts;
    if (ps.isEmpty) return;
    final dot = _dot;
    if (dot == null || !hq) {
      final p = Paint()..blendMode = BlendMode.plus;
      for (final q in ps) {
        final k = math.max(0.0, q.l / q.m);
        c.drawCircle(Offset(q.x, q.y), q.r * (q.k == 3 ? 1.3 : .6 + k * .8), p..color = hex(q.c, math.min(1, k * 1.2)));
      }
      return;
    }
    final n = ps.length;
    final xf = Float32List(n * 4), rects = Float32List(n * 4), cols = Int32List(n);
    for (var i = 0; i < n; i++) {
      final q = ps[i], k = math.max(0.0, q.l / q.m);
      final rad = q.r * (q.k == 3 ? 1.3 : .6 + k * .8) * 2.2; // soft sprite: bigger than the hard dot
      final sc = rad / 32;
      xf[i * 4] = sc;
      xf[i * 4 + 1] = 0;
      xf[i * 4 + 2] = q.x - 32 * sc;
      xf[i * 4 + 3] = q.y - 32 * sc;
      rects[i * 4] = 0;
      rects[i * 4 + 1] = 0;
      rects[i * 4 + 2] = 64;
      rects[i * 4 + 3] = 64;
      final base = _colCache.putIfAbsent(q.c, () => hex(q.c));
      cols[i] = base.withValues(alpha: math.min(1, k * 1.2)).toARGB32();
    }
    c.drawRawAtlas(dot, xf, rects, cols, BlendMode.modulate, null, Paint()..blendMode = BlendMode.plus);
  }

  // ------------------------------------------------------------- goals
  void _drawGoalsLive(Canvas c, ui.Image img, double t) {
    final G = e.GG, iw = img.width.toDouble(), ih = img.height.toDouble();
    final gp = Paint()..filterQuality = FilterQuality.medium;
    for (var i = 0; i < e.goals.length; i++) {
      final g = e.goals[i];
      final sx = e.shake[i] > 0 ? math.sin(t * 40) * 6 * e.shake[i] : 0.0;
      c.save();
      c.translate(sx, g.y);
      if (g.d == 1) c.scale(1, -1);
      final dst = Rect.fromLTWH(G.x, -G.h, G.w, G.h);
      // drop shadow (RN: DropShadow 3,6 blur 5)
      c.save();
      c.translate(3, 6);
      c.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), dst,
          Paint()..colorFilter = const ColorFilter.mode(Color(0x80000000), BlendMode.srcIn)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      c.restore();
      c.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), dst, gp);
      c.restore();
    }
  }

  void _drawGoals(Canvas c, double t) {
    final img = im.goal;
    if (img == null) return;
    if (e.shake[0] > 0 || e.shake[1] > 0) {
      _drawGoalsLive(c, img, t);
      return;
    }
    if (_goals == null) {
      final rec = ui.PictureRecorder();
      _drawGoalsLive(Canvas(rec), img, 0);
      _goals = rec.endRecording();
    }
    c.drawPicture(_goals!);
  }

  // ------------------------------------------------------------- reflections + dynamic light
  void _drawFloorFx(Canvas c, List<Offset> pos) {
    if (!hq) return;
    final bi = e.bodies.length - 1;
    final bp = pos[bi];
    final sp = hyp(e.ball.vx, e.ball.vy);
    // light pool under the ball, brighter when it moves fast
    final glowR = e.ball.r * (3.2 + math.min(2.0, sp / 900));
    c.drawCircle(bp, glowR,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(bp, glowR, [Color.fromRGBO(170, 220, 255, .10 + math.min(.12, sp / 9000)), const Color(0x00000000)]));
    // glossy reflections (mirrored down, faded) — reads as a polished pitch
    final rp = Paint()..color = const Color.fromRGBO(255, 255, 255, .10)..filterQuality = FilterQuality.low;
    for (var i = 0; i < e.bodies.length; i++) {
      final b = e.bodies[i];
      if (b == e.ball) continue;
      final img = b.team == 0 ? im.t0 : im.t1;
      if (img == null) continue;
      final p = pos[i];
      c.save();
      c.translate(p.dx, p.dy + b.r * 1.9);
      c.scale(1, -.45);
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Rect.fromLTWH(-b.r, -b.r, 2 * b.r, 2 * b.r), rp);
      c.restore();
    }
  }

  // ------------------------------------------------------------- frame
  void render(Canvas c, GView v, double t, double dpr) {
    if (_bg == null || _bgView != v) {
      _bg = _staticLayer(v);
      _bgView = v;
    }
    c.drawPicture(_bg!);
    final cam = e.cam;
    final rnd = math.Random();
    final shx = cam > .05 ? (rnd.nextDouble() - .5) * cam * 7 : 0.0, shy = cam > .05 ? (rnd.nextDouble() - .5) * cam * 7 : 0.0;
    c.save();
    c.translate(v.ox + shx, v.oy + shy);
    c.scale(v.s, v.s);
    final al = e.alpha();
    final pos = [for (final b in e.bodies) Offset(b.px + (b.x - b.px) * al + b.vox, b.py + (b.y - b.py) * al + b.voy)];
    _drawFloorFx(c, pos);
    final aimTeam = e.phase == Phase.aim ? e.turn : -1;
    for (var i = 0; i < e.bodies.length; i++) {
      final b = e.bodies[i];
      if (b == e.ball) continue;
      _drawPiece(c, b, pos[i].dx, pos[i].dy, b.team == 0 ? im.t0 : im.t1, t,
          b.team == aimTeam && !(e.drag != null && e.drag!.b != b) && !e.isAiTurn());
    }
    final bp = pos[e.bodies.indexOf(e.ball)];
    _drawTrail(c, bp.dx, bp.dy);
    _drawBall(c, e.ball, bp.dx, bp.dy, im.ball, v.s);
    _drawGoals(c, t);
    final ab = e.drag?.b;
    if (ab != null) {
      final i = e.bodies.indexOf(ab);
      _drawAim(c, t, pos[i].dx, pos[i].dy);
    } else {
      _aimOn = false;
    }
    _drawParts(c);
    c.restore();
    // goal post-FX
    for (var tm = 0; tm < 2; tm++) {
      if (e.ripple[tm] > .99) {
        _ringT = 1;
        _ringTeam = tm;
      }
    }
    _ringT = math.max(0, e.ripple[_ringTeam]);
    final ps = postShader;
    if (hq && ps != null && (e.flash > 0 || _ringT > 0)) {
      final g = e.goals[_ringTeam];
      final fx = v.ox + e.rippleX[_ringTeam] * v.s, fy = v.oy + g.y * v.s;
      final col = hex(_ringTeam == 0 ? '#4fe3ff' : '#ff4a5a');
      var i = 0;
      ps
        ..setFloat(i++, v.W)
        ..setFloat(i++, v.H)
        ..setFloat(i++, fx)
        ..setFloat(i++, fy)
        ..setFloat(i++, e.flash)
        ..setFloat(i++, t)
        ..setFloat(i++, _ringT)
        ..setFloat(i++, col.r)
        ..setFloat(i++, col.g)
        ..setFloat(i++, col.b);
      c.drawRect(Rect.fromLTWH(0, 0, v.W, v.H), Paint()..shader = ps..blendMode = BlendMode.plus);
    }
    if (e.flash > 0) c.drawRect(Rect.fromLTWH(0, 0, v.W, v.H), Paint()..color = Color.fromRGBO(255, 255, 255, e.flash * .28));
    _imgShaders.length;
  }

  void dispose() {
    _bg?.dispose();
    _goals?.dispose();
  }
}
