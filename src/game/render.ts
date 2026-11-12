// Skia renderer for the NEXORA match. Records one SkPicture per frame.
import { Skia, SkCanvas, SkImage, SkPaint, SkPicture, TileMode, FilterMode, MipmapMode, BlendMode, PaintStyle, StrokeCap, BlurStyle, ClipOp, createPicture } from '@shopify/react-native-skia';
import { Engine, Body, PR, POST_R, aimPreview } from './engine';
import { TRAILS } from './data';

const BALL_SKSL = `
uniform shader img;
uniform float3 c0;
uniform float3 c1;
uniform float3 c2;
uniform float isz;
uniform float aa;
half4 main(float2 p){
  float d=length(p);
  if(d>1.0) return half4(0);
  float z=sqrt(max(0.0,1.0-d*d));
  float3 n=float3(p.x,p.y,z);
  float3 q=float3(dot(c0,n),dot(c1,n),dot(c2,n));
  // front hemisphere maps the art directly; the back one mirrors it, blended across the seam so rolling never "pops"
  float2 uv=q.xy; float seam=smoothstep(-0.12,0.12,q.z);
  half4 cf=img.eval((uv*0.93*0.5+0.5)*isz);
  half4 cb=img.eval((float2(-uv.x,uv.y)*0.93*0.5+0.5)*isz);
  float3 base=mix(float3(cb.rgb),float3(cf.rgb),seam);
  // studio lighting: key light top-left, soft fill, sky ambient from above, ground bounce from below
  float3 L=normalize(float3(-0.42,-0.55,0.72));
  float3 F=normalize(float3(0.6,0.35,0.7));
  float key=max(dot(n,L),0.0), fill=max(dot(n,F),0.0);
  float amb=0.42+0.18*(-n.y)*0.5+0.12*z;
  float occ=mix(0.72,1.0,smoothstep(-0.2,0.85,-n.y*0.55+z*0.6));   // contact darkening toward the bottom-right
  float3 lit=base*(amb+0.62*key+0.16*fill)*occ;
  float3 H=normalize(L+float3(0,0,1));
  float sp=pow(max(dot(n,H),0.0),64.0)*0.65+pow(max(dot(n,H),0.0),12.0)*0.10;   // sharp glint + soft sheen
  float fres=pow(1.0-z,3.0);
  float3 col=lit*(1.0-0.35*fres)+float3(sp)+float3(0.55,0.75,1.0)*fres*0.22;
  float a=smoothstep(1.0,1.0-aa,d);
  return half4(half3(col)*a,a);
}`;
const ballFx = Skia.RuntimeEffect.Make(BALL_SKSL)!;

const col = (c: string, a = 1) => { const k = Skia.Color(c); return Float32Array.from([k[0], k[1], k[2], k[3] * a]); };
const TEAM_GLOW = ['#3bb6ff', '#ff5b6b'];

export type ArrowImages = { headE: SkImage | null; headS: SkImage | null; shaftE: SkImage | null; shaftS: SkImage | null };
export type Images = { field: SkImage | null; goal: SkImage | null; ball: SkImage | null; t0: SkImage | null; t1: SkImage | null; arrow?: ArrowImages };
export type View = { W: number; H: number; s: number; ox: number; oy: number };

export function computeView(e: Engine, W: number, H: number, top: number, bottom: number): View {
  const f = e.f, FS = 1.12;
  const playH = Math.max(300, H - top - bottom);
  const s = Math.min(W / (f.R - f.L + 56 * FS), playH / ((f.B - f.T) + 2 * e.GG.h + 48)) * .99;
  return { W, H, s, ox: W / 2 - e.CX * s, oy: top + playH / 2 - e.CY * s };
}

const P = () => { const p = Skia.Paint(); p.setAntiAlias(true); return p; };
const paints = {
  img: P(), fill: P(), stroke: P(), add: P(), add2: P(), glow: P(), shadow: P(), dark: P(),
};
paints.add2.setStyle(PaintStyle.Stroke); paints.add2.setBlendMode(BlendMode.Plus);
paints.stroke.setStyle(PaintStyle.Stroke); paints.stroke.setStrokeCap(StrokeCap.Round);
paints.add.setBlendMode(BlendMode.Plus);
paints.glow.setStyle(PaintStyle.Stroke); paints.glow.setBlendMode(BlendMode.Plus); paints.glow.setMaskFilter(Skia.MaskFilter.MakeBlur(BlurStyle.Normal, 6, true));

export function staticLayer(e: Engine, v: View, im: Images): SkPicture {
  return createPicture((c: SkCanvas) => {
    const p = P(); p.setColor(Skia.Color('#02040c')); c.drawRect(Skia.XYWHRect(0, 0, v.W, v.H), p);
    const f = e.f;
    if (im.field) {
      // blurred, darkened stadium fill behind everything
      const k = Math.max(v.W / f.W, v.H / f.H) * 1.05;
      const bp = P(); bp.setImageFilter(Skia.ImageFilter.MakeBlur(14, 14, TileMode.Clamp, null));
      c.drawImageRect(im.field, Skia.XYWHRect(0, 0, im.field.width(), im.field.height()), Skia.XYWHRect((v.W - f.W * k) / 2, (v.H - f.H * k) / 2, f.W * k, f.H * k), bp);
      const d = P(); d.setColor(Skia.Color('rgba(2,4,14,0.62)')); c.drawRect(Skia.XYWHRect(0, 0, v.W, v.H), d);
      c.save(); c.translate(v.ox, v.oy); c.scale(v.s, v.s);
      // sharp field with soft feathered edges
      c.saveLayer(undefined, Skia.XYWHRect(-40, -40, f.W + 80, f.H + 80));
      c.drawImageRectOptions(im.field, Skia.XYWHRect(0, 0, im.field.width(), im.field.height()), Skia.XYWHRect(0, 0, f.W, f.H), FilterMode.Linear, MipmapMode.Linear, null);
      const m = P(); m.setBlendMode(BlendMode.DstIn);
      m.setShader(Skia.Shader.MakeLinearGradient({ x: 0, y: 0 }, { x: 0, y: f.H }, [col('#000', 0), col('#000'), col('#000'), col('#000', 0)], [0, .06, .94, 1], TileMode.Clamp));
      c.drawRect(Skia.XYWHRect(0, 0, f.W, f.H), m);
      m.setShader(Skia.Shader.MakeLinearGradient({ x: 0, y: 0 }, { x: f.W, y: 0 }, [col('#000', 0), col('#000'), col('#000'), col('#000', 0)], [0, .05, .95, 1], TileMode.Clamp));
      c.drawRect(Skia.XYWHRect(0, 0, f.W, f.H), m);
      c.restore();
      // subtle neon outline of the playing area
      const F = e.F, o = P(); o.setStyle(PaintStyle.Stroke); o.setStrokeWidth(3); o.setColor(Skia.Color('rgba(120,220,255,0.35)'));
      o.setMaskFilter(Skia.MaskFilter.MakeBlur(BlurStyle.Normal, 4, true));
      c.drawRRect(Skia.RRectXY(Skia.XYWHRect(F.l, F.t, F.r - F.l, F.b - F.t), 70, 70), o);
      c.restore();
    }
  }, { width: v.W, height: v.H });
}

// ---- pre-rendered sprites (built once per team logo; per-frame cost = 2-3 drawImage calls) ----
const SPR = 256, sprCache = new Map<any, { disc: SkImage; gloss: SkImage }>();
let edgeSpr: SkImage | null = null;
// the puck's side wall: a darker disc peeking out below/right of the face → reads as a real 3D puck, not a sticker
function edgeSprite() {
  if (edgeSpr) return edgeSpr;
  const R = SPR / 2, r = R - 2;
  edgeSpr = makeImg(SPR, SPR, c => {
    const p = P(); p.setShader(Skia.Shader.MakeLinearGradient({ x: R - r, y: R - r }, { x: R + r, y: R + r }, [col('#3a4256'), col('#141823'), col('#05070c')], [0, .55, 1], TileMode.Clamp));
    c.drawCircle(R, R, r, p);
    const hl = P(); hl.setStyle(PaintStyle.Stroke); hl.setStrokeWidth(3); hl.setColor(col('#ffffff', .16)); c.drawCircle(R, R, r - 1.5, hl);
  });
  return edgeSpr;
}
let shadowSpr: SkImage | null = null;
function makeImg(w: number, h: number, draw: (c: SkCanvas) => void): SkImage | null {
  // CPU raster surface: built once, no extra GPU/WebGL context, safe to draw from any thread
  const surf = Skia.Surface.Make(w, h);
  if (!surf) return null;
  const c = surf.getCanvas(); c.clear(Float32Array.from([0, 0, 0, 0])); draw(c); surf.flush?.();
  const img = surf.makeImageSnapshot(); const ni = (img as any).makeNonTextureImage?.();
  return ni || img;
}
function sprites(team: 0 | 1, logo: SkImage | null) {
  const key = logo || team; const hit = sprCache.get(key); if (hit) return hit;
  const R = SPR / 2, r = R - 2;
  const disc = makeImg(SPR, SPR, c => {
    // disc art only (no team ring): the new sprites are full-bleed round discs with their own rim
    if (logo) {
      c.save(); c.clipRRect(Skia.RRectXY(Skia.XYWHRect(R - r, R - r, 2 * r, 2 * r), r, r), ClipOp.Intersect, true);
      c.drawImageRectOptions(logo, Skia.XYWHRect(0, 0, logo.width(), logo.height()), Skia.XYWHRect(R - r, R - r, 2 * r, 2 * r), FilterMode.Linear, MipmapMode.Linear, null);
      c.restore();
    } else { const dk = P(); dk.setColor(col(team ? '#3a0d16' : '#0d1a3a')); c.drawCircle(R, R, r, dk); }
  })!;
  const gloss = makeImg(SPR, SPR, c => {
    // subtle specular sheen + thin top-left rim light (no team colour)
    const gl = P(); gl.setShader(Skia.Shader.MakeRadialGradient({ x: R - r * .38, y: R - r * .48 }, r * .9, [col('#ffffff', .26), col('#ffffff', .05), col('#ffffff', 0)], [0, .45, 1], TileMode.Clamp));
    c.drawCircle(R, R, r * .97, gl);
    const sp = P(); sp.setStyle(PaintStyle.Stroke); sp.setStrokeCap(StrokeCap.Round); sp.setStrokeWidth(3); sp.setColor(col('#ffffff', .38));
    c.drawArc(Skia.XYWHRect(R - r * .93, R - r * .93, r * 1.86, r * 1.86), 205, 60, false, sp);
    // bevelled rim: lit top-left, shaded bottom-right
    const bv = P(); bv.setStyle(PaintStyle.Stroke); bv.setStrokeWidth(r * .07);
    bv.setShader(Skia.Shader.MakeLinearGradient({ x: R - r, y: R - r }, { x: R + r, y: R + r }, [col('#ffffff', .42), col('#ffffff', .06), col('#000000', .38)], [0, .5, 1], TileMode.Clamp));
    c.drawCircle(R, R, r * .965, bv);
    // soft inner shadow at the bottom edge = the face sits slightly recessed in the rim
    const is = P(); is.setShader(Skia.Shader.MakeRadialGradient({ x: R - r * .12, y: R - r * .16 }, r * 1.05, [col('#000000', 0), col('#000000', 0), col('#000000', .28)], [0, .82, 1], TileMode.Clamp));
    c.drawCircle(R, R, r * .99, is);
  })!;
  const v = { disc, gloss }; sprCache.set(key, v); return v;
}
function shadowSprite() {
  if (shadowSpr) return shadowSpr;
  shadowSpr = makeImg(128, 128, c => { const p = P(); p.setShader(Skia.Shader.MakeRadialGradient({ x: 64, y: 64 }, 64, [col('#000', 1), col('#000', .5), col('#000', 0)], [0, .55, 1], TileMode.Clamp)); c.drawCircle(64, 64, 64, p); });
  return shadowSpr;
}
const sprPaint = P(); const shPaint = P();
function drawShadowFast(c: SkCanvas, x: number, y: number, r: number, a: number) {
  const s = shadowSprite(); if (!s) return; const R = r * 1.3; shPaint.setAlphaf(a);
  c.drawImageRectOptions(s, Skia.XYWHRect(0, 0, 128, 128), Skia.XYWHRect(x + r * .14 - R, y + r * .26 - R, 2 * R, 2 * R), FilterMode.Linear, MipmapMode.None, shPaint);
}

function drawPiece(c: SkCanvas, e: Engine, b: Body, x: number, y: number, img: SkImage | null, t: number, active: boolean, dark: boolean) {
  const team = b.team as 0 | 1, sc = 1 + b.sq * .07, r = b.r * sc;
  drawShadowFast(c, x, y, r, .55);
  const ed = edgeSprite(); if (ed) c.drawImageRectOptions(ed, Skia.XYWHRect(0, 0, SPR, SPR), Skia.XYWHRect(x - r + r * .035, y - r + r * .085, 2 * r, 2 * r), FilterMode.Linear, MipmapMode.Linear, sprPaint);
  if (active) {
    // only the selectable pieces of the player on turn: one thin, soft breathing glow hugging the disc
    const pulse = .5 + .5 * Math.sin(t * 4), g = paints.glow;
    g.setStrokeWidth(4); g.setColor(col(TEAM_GLOW[team], .28 + .22 * pulse)); c.drawCircle(x, y, r + 2.5, g);
  }
  const s = sprites(team, img);
  c.save(); c.translate(x, y); c.rotate(b.ang * 57.2958, 0, 0);
  c.drawImageRectOptions(s.disc, Skia.XYWHRect(0, 0, SPR, SPR), Skia.XYWHRect(-r, -r, 2 * r, 2 * r), FilterMode.Linear, MipmapMode.Linear, sprPaint);
  c.restore();
  if (dark) { const dk = paints.dark; dk.setColor(col('#060818', .22)); c.drawCircle(x, y, r * .99, dk); }
  c.drawImageRectOptions(s.gloss, Skia.XYWHRect(0, 0, SPR, SPR), Skia.XYWHRect(x - r, y - r, 2 * r, 2 * r), FilterMode.Linear, MipmapMode.Linear, sprPaint);
  void e;
}

function drawBall(c: SkCanvas, b: Body, x: number, y: number, img: SkImage | null, s: number) {
  const r = b.r * (1 + b.sq * .08);
  drawShadowFast(c, x, y, r, .55); drawShadowFast(c, x - r * .06, y - r * .12, r * .78, .5);   // soft + contact shadow
  if (!img) { const p = paints.fill; p.setColor(col('#ffffff')); c.drawCircle(x, y, r, p); return; }
  const R = b.R, isz = img.width();
  const sh = ballFx.makeShaderWithChildren([R[0], R[3], R[6], R[1], R[4], R[7], R[2], R[5], R[8], isz, Math.min(.2, 1.6 / (r * s))],
    [img.makeShaderOptions(TileMode.Clamp, TileMode.Clamp, FilterMode.Linear, MipmapMode.Linear)]);   // mipmaps: no shimmer while rolling
  const p = paints.img; p.setShader(sh);
  c.save(); c.translate(x, y); c.scale(r, r); c.drawCircle(0, 0, 1, p); c.restore(); p.setShader(null);
}

function drawTrail(c: SkCanvas, e: Engine, ballIdx: number) {
  const tr = e.trail, n = tr.length; if (n < 2) return;
  const cs = (TRAILS[ballIdx % TRAILS.length] || TRAILS[0]).c, BW = e.ball.r, p = paints.stroke;
  p.setBlendMode(BlendMode.Plus);
  const layers: [number, number, string][] = [[2.2, .16, cs[0]], [1.1, .42, cs[1] || cs[0]], [.42, .95, cs[2] || '#ffffff']];
  for (const [w, a, cc] of layers) for (let i = 1; i < n; i++) {
    const q = tr[i], o = tr[i - 1], k = i / n;
    p.setStrokeWidth(Math.max(.6, BW * w * k * q.a)); p.setColor(col(cc, Math.min(1, a * q.a * (.35 + .65 * k))));
    c.drawLine(o.x, o.y, q.x, q.y, p);
  }
  p.setBlendMode(BlendMode.SrcOver);
}

// ---- aim arrow art: sliced sprites, all pointing straight UP (assets/g/arrow).
// The head keeps its size and aspect at the tip; the shaft keeps its top collar and tapered tail at native length and
// stretches only its middle, so the arrow grows with power without distorting. Slim art (image 3) for low/mid power,
// electric art (image 1 head + image 2 shaft) takes over at high power.
type ArtK = { hh: number; join: number; sw: number; top: number; tail: number; topLen: number; tailLen: number };
const ART: { e: ArtK; s: ArtK } = {
  // hh: head height (world units); join: where the shaft's top row sits, as a fraction of the head height from the tip;
  // sw: shaft draw width; top/tail: fractions of the shaft image that are fixed caps; topLen/tailLen: their native lengths
  e: { hh: 96, join: .82, sw: 124, top: 0, tail: .734, topLen: 0, tailLen: 46 },     // head = image 1, shaft = image 2
  s: { hh: 68, join: .928, sw: 32.5, top: 0, tail: .704, topLen: 0, tailLen: 38 },  // head + shaft = image 3 (same scale and axis)
};
// no edge AA on the slices: adjacent rects then share their edge exactly (no hairline gap or double-blended seam)
const artPaint = Skia.Paint(); const artGlow = Skia.Paint(); artGlow.setBlendMode(BlendMode.Plus);
const sstep = (a: number, b: number, v: number) => { const k = Math.min(1, Math.max(0, (v - a) / (b - a))); return k * k * (3 - 2 * k); };
function drawSlices(c: SkCanvas, head: SkImage, shaft: SkImage, k: ArtK, L0: number, L: number, p: SkPaint) {
  const hw = k.hh * head.width() / head.height(), sh = shaft.height(), sW = shaft.width();
  const y0 = sh * k.top, y1 = sh * k.tail, x0 = -k.sw / 2;
  const neck = L - k.hh * k.join;                                    // shaft's top row (tucked under the head)
  const len = Math.max(2, neck - L0);
  let topL = k.topLen, tailL = k.tailLen;
  if (topL + tailL > len * .8) { const f = len * .8 / (topL + tailL); topL *= f; tailL *= f; }
  const mid = len - topL - tailL;
  const draw = (sy0: number, sy1: number, dy: number, dh: number) =>
    c.drawImageRectOptions(shaft, Skia.XYWHRect(0, sy0, sW, sy1 - sy0), Skia.XYWHRect(x0, dy, k.sw, dh), FilterMode.Linear, MipmapMode.Linear, p);
  // local frame: arrow points to -y from the disc centre
  draw(y1, sh, -L0 - tailL, tailL);                                  // tail cap at the disc edge
  if (mid > 0) draw(y0, y1, -neck + topL, mid);                      // stretched middle
  if (topL > 0) draw(0, y0, -neck, topL);                            // optional fixed collar under the head
  c.drawImageRectOptions(head, Skia.XYWHRect(0, 0, head.width(), head.height()), Skia.XYWHRect(-hw / 2, -L, hw, k.hh), FilterMode.Linear, MipmapMode.Linear, p);
}
function drawArrowArt(c: SkCanvas, ar: ArrowImages, t: number, x: number, y: number, ux: number, uy: number, r: number, pw: number) {
  const L0 = r + 3, L = r + 70 + pw * 110;                            // tail starts on the disc edge; length tracks power
  const ae = sstep(.66, .72, pw), as = 1 - sstep(.7, .75, pw);          // electric fades in on top before slim fades out
  c.save(); c.translate(x, y); c.rotate(Math.atan2(uy, ux) * 180 / Math.PI + 90, 0, 0);
  if (as > 0) { artPaint.setAlphaf(as); drawSlices(c, ar.headS!, ar.shaftS!, ART.s, L0, L, artPaint); }
  if (ae > 0) {
    artPaint.setAlphaf(ae); drawSlices(c, ar.headE!, ar.shaftE!, ART.e, L0, L, artPaint);
    const pulse = .5 + .5 * Math.sin(t * (6 + pw * 8));             // subtle charged pulse, stronger near full power
    artGlow.setAlphaf(ae * (.06 + .16 * pulse) * pw); drawSlices(c, ar.headE!, ar.shaftE!, ART.e, L0, L, artGlow);
  }
  c.restore();
  return L;
}

// ---- aim arrow: tapered glowing beam, power gradient blue → purple → red, length = power ----
const AIM_C = ['#3b8bff', '#9b5cff', '#ff3b5c'];
const aimS = { on: false, ux: 0, uy: -1, p: 0 };
const mix = (a: string, b: string, k: number) => { const x = Skia.Color(a), y = Skia.Color(b); return Float32Array.from([x[0] + (y[0] - x[0]) * k, x[1] + (y[1] - x[1]) * k, x[2] + (y[2] - x[2]) * k, 1]); };
const powerCol = (p: number) => p < .5 ? mix(AIM_C[0], AIM_C[1], p / .5) : mix(AIM_C[1], AIM_C[2], (p - .5) / .5);
const aimGlow = P(); aimGlow.setBlendMode(BlendMode.Plus); aimGlow.setMaskFilter(Skia.MaskFilter.MakeBlur(BlurStyle.Normal, 9, true));
const aimFill = P(); const aimRing = P(); aimRing.setStyle(PaintStyle.Stroke); aimRing.setStrokeCap(StrokeCap.Round);

function drawAim(c: SkCanvas, e: Engine, t: number, x: number, y: number, ar?: ArrowImages) {
  const a = e.aimInfo();
  if (!a || a.p <= 0) { aimS.on = false; return; }
  // light smoothing of finger noise (snaps on the first frame, so no lag from a stale direction)
  if (!aimS.on) { aimS.ux = a.ux; aimS.uy = a.uy; aimS.p = a.p; aimS.on = true; }
  else { aimS.ux += (a.ux - aimS.ux) * .55; aimS.uy += (a.uy - aimS.uy) * .55; aimS.p += (a.p - aimS.p) * .6; }
  const ul = Math.hypot(aimS.ux, aimS.uy) || 1, ux = aimS.ux / ul, uy = aimS.uy / ul, pw = aimS.p;
  const b = a.b, team = b.team as 0 | 1, r = b.r, nx = -uy, ny = ux;
  let L: number;
  if (ar && ar.headE && ar.headS && ar.shaftE && ar.shaftS) L = drawArrowArt(c, ar, t, x, y, ux, uy, r, pw);
  else {
    const L0 = r + 6, Lmax = r + 250; L = r + 34 + pw * 216;           // beam starts at the disc edge; length tracks power
    const w0 = 9 + pw * 5, w1 = 3;                                        // half-widths: base → neck (taper)
    const hs = 20 + pw * 8, neck = L - hs;
    const pb = Skia.PathBuilder.Make();
    pb.moveTo(x + ux * L0 + nx * w0, y + uy * L0 + ny * w0)
      .lineTo(x + ux * neck + nx * w1, y + uy * neck + ny * w1)
      .lineTo(x + ux * neck + nx * hs * .62, y + uy * neck + ny * hs * .62)
      .lineTo(x + ux * L, y + uy * L)
      .lineTo(x + ux * neck - nx * hs * .62, y + uy * neck - ny * hs * .62)
      .lineTo(x + ux * neck - nx * w1, y + uy * neck - ny * w1)
      .lineTo(x + ux * L0 - nx * w0, y + uy * L0 - ny * w0).close();
    const path = pb.build();
    // gradient laid over the full max length, so a weak shot only shows blue and a full one reaches red
    const sh = Skia.Shader.MakeLinearGradient({ x: x + ux * L0, y: y + uy * L0 }, { x: x + ux * Lmax, y: y + uy * Lmax }, AIM_C.map(s => col(s)), [0, .5, 1], TileMode.Clamp);
    aimGlow.setShader(sh); aimGlow.setAlphaf(.55); c.drawPath(path, aimGlow);
    aimFill.setShader(sh); aimFill.setAlphaf(.95); c.drawPath(path, aimFill);
    aimGlow.setShader(null); aimFill.setShader(null);
  }
  // power ring around the disc
  const pc = powerCol(pw); aimRing.setStrokeWidth(4); aimRing.setColor(Float32Array.from([pc[0], pc[1], pc[2], .9]));
  c.drawArc(Skia.XYWHRect(x - r - 9, y - r - 9, (r + 9) * 2, (r + 9) * 2), -90, 360 * pw, false, aimRing);
  // accuracy preview: dotted continuation, longer for accurate discs
  const ad = paints.add, steps = Math.max(2, Math.round((5 + pw * 6) * (e.cfg.stats ? aimPreview(e.statsOf(team).accuracy) : 1)));
  for (let i = 1; i <= steps; i++) { const d = L + 8 + i * 22, k = 1 - i / (steps + 1); ad.setColor(Float32Array.from([pc[0], pc[1], pc[2], .6 * k])); c.drawCircle(x + ux * d, y + uy * d, 2.2 + 2 * k, ad); }
  // faint pull-back tether toward the finger
  const tp = paints.stroke; tp.setStrokeWidth(2.5); tp.setColor(col('#ffffff', .18)); c.drawLine(x - ux * r, y - uy * r, x - ux * (r + 18 + pw * 60), y - uy * (r + 18 + pw * 60), tp);
  void t;
}

function drawParts(c: SkCanvas, e: Engine) {
  if (!e.parts.length) return; const p = paints.add;
  for (const q of e.parts) { const k = Math.max(0, q.l / q.m); p.setColor(col(q.c, Math.min(1, k * 1.2))); c.drawCircle(q.x, q.y, q.r * (q.k === 3 ? 1.3 : .6 + k * .8), p); }
}

// ---- 3D goals, drawn in two layers: the net (behind bodies) and the frame (in front) ----
// Top-down camera: the net floor recedes from the goal line to the back bar (physics back wall = e.DEPTH);
// the crossbar sits over the goal line and the posts are round, so a ball inside the goal reads as
// being under the bar and in front of the net.
const netP = P(); netP.setStyle(PaintStyle.Stroke); netP.setStrokeCap(StrokeCap.Round);
const netFill = P(); const barP = P(); barP.setStyle(PaintStyle.Stroke); barP.setStrokeCap(StrokeCap.Round);
const barSh = P(); barSh.setStyle(PaintStyle.Stroke); barSh.setStrokeCap(StrokeCap.Round); barSh.setMaskFilter(Skia.MaskFilter.MakeBlur(BlurStyle.Normal, 4, true));
const postP = P();

// the nets + frames are static unless a goal ripple/shake is playing: cache them as pictures (≈60 Skia paths and
// several gradient shaders per frame saved → far less JS↔native traffic and GC churn on the match thread)
const goalCache = { nets: null as SkPicture | null, frames: null as SkPicture | null, key: null as any };
function goalsStatic(e: Engine) { return e.ripple[0] <= 0 && e.ripple[1] <= 0 && e.shake[0] <= 0 && e.shake[1] <= 0; }
function cachedGoals(c: SkCanvas, e: Engine, t: number, which: 'nets' | 'frames') {
  if (!goalsStatic(e)) { which === 'nets' ? drawGoalNetsLive(c, e, t) : drawGoalFramesLive(c, e, t); return; }
  if (goalCache.key !== e) { goalCache.key = e; goalCache.nets = goalCache.frames = null; }
  let pic = goalCache[which];
  if (!pic) { pic = createPicture((pc: SkCanvas) => { which === 'nets' ? drawGoalNetsLive(pc, e, 0) : drawGoalFramesLive(pc, e, 0); }); goalCache[which] = pic; }
  c.drawPicture(pic);
}
function drawGoalNets(c: SkCanvas, e: Engine, t: number) { cachedGoals(c, e, t, 'nets'); }
function drawGoalFrames(c: SkCanvas, e: Engine, t: number) { cachedGoals(c, e, t, 'frames'); }
function drawGoalNetsLive(c: SkCanvas, e: Engine, t: number) {
  e.goals.forEach((g, i) => {
    const d = g.d, x1 = g.x1 - POST_R, x2 = g.x2 + POST_R, D = e.DEPTH + 6, y0 = g.y, yb = g.y + d * D;
    const inset = (x2 - x1) * .045, bx1 = x1 + inset, bx2 = x2 - inset;   // back of the net appears slightly narrower
    const sx = Math.sin(t * 40) * 6 * e.shake[i];
    const rp = e.ripple[i], rx = e.rippleX[i];
    const bulge = (x: number, k: number) => rp > 0 ? d * rp * 16 * k * Math.exp(-Math.pow((x - rx) / 70, 2)) * (1 + .35 * Math.sin(t * 22)) : 0;
    c.save(); c.translate(sx, 0);
    // net floor: darker toward the back (shadow inside the goal)
    const fl = Skia.PathBuilder.Make(); fl.moveTo(x1, y0).lineTo(x2, y0).lineTo(bx2, yb).lineTo(bx1, yb).close();
    netFill.setShader(Skia.Shader.MakeLinearGradient({ x: 0, y: y0 }, { x: 0, y: yb }, [col('#000000', .18), col('#000000', .5)], null, TileMode.Clamp));
    c.drawPath(fl.build(), netFill); netFill.setShader(null);
    // mesh: longitudinal strings converging to the back bar
    const n = Math.max(8, Math.round((x2 - x1) / 18));
    netP.setStrokeWidth(1.3); netP.setColor(col('#ffffff', .26));
    for (let k = 0; k <= n; k++) {
      const u = k / n, fx = x1 + (x2 - x1) * u, bx = bx1 + (bx2 - bx1) * u;
      const pb = Skia.PathBuilder.Make(); pb.moveTo(fx, y0);
      for (let j = 1; j <= 6; j++) { const v = j / 6, x = fx + (bx - fx) * v; pb.lineTo(x, y0 + d * D * v + bulge(x, Math.sin(v * Math.PI))); }
      c.drawPath(pb.build(), netP);
    }
    // transverse strings (closer together toward the back = perspective)
    for (let j = 1; j <= 7; j++) {
      const v = Math.pow(j / 7, .85), xa = x1 + (bx1 - x1) * v, xb = x2 + (bx2 - x2) * v, y = y0 + d * D * v;
      const pb = Skia.PathBuilder.Make(); pb.moveTo(xa, y);
      for (let k = 1; k <= 12; k++) { const x = xa + (xb - xa) * k / 12; pb.lineTo(x, y + bulge(x, Math.sin(v * Math.PI))); }
      c.drawPath(pb.build(), netP);
    }
    // side nets + back bar
    netP.setStrokeWidth(3); netP.setColor(col('#ffffff', .5));
    c.drawLine(x1, y0, bx1, yb, netP); c.drawLine(x2, y0, bx2, yb, netP);
    netP.setStrokeWidth(4.5); netP.setColor(col('#e8edf5', .7)); c.drawLine(bx1, yb, bx2, yb, netP);
    c.restore();
  });
}

function drawGoalFramesLive(c: SkCanvas, e: Engine, t: number) {
  e.goals.forEach((g, i) => {
    const sx = Math.sin(t * 40) * 6 * e.shake[i], y = g.y, x1 = g.x1 + sx, x2 = g.x2 + sx, W = POST_R * 1.6;
    // soft cast shadow (light from top-left → shadow down-right)
    barSh.setStrokeWidth(W); barSh.setColor(col('#000000', .45)); c.drawLine(x1 + 5, y + 7, x2 + 5, y + 7, barSh);
    // crossbar: cylindrical shading across its width
    barP.setStrokeWidth(W);
    barP.setShader(Skia.Shader.MakeLinearGradient({ x: 0, y: y - W / 2 }, { x: 0, y: y + W / 2 }, [col('#8d96a6'), col('#ffffff'), col('#dfe5ee'), col('#6c7484')], [0, .35, .6, 1], TileMode.Clamp));
    c.drawLine(x1, y, x2, y, barP); barP.setShader(null);
    // posts: round, lit from the top-left
    for (const px of [x1, x2]) {
      postP.setShader(Skia.Shader.MakeRadialGradient({ x: px - POST_R * .35, y: y - POST_R * .4 }, POST_R * 1.25, [col('#ffffff'), col('#d5dbe5'), col('#5d6575')], [0, .5, 1], TileMode.Clamp));
      c.drawCircle(px, y, POST_R + 1, postP); postP.setShader(null);
    }
  });
}

export function frame(e: Engine, v: View, im: Images, bg: SkPicture | null, ballIdx: number, t: number): SkPicture {
  return createPicture((c: SkCanvas) => {
    if (bg) c.drawPicture(bg);
    const cam = e.cam, shx = cam > .05 ? (Math.random() - .5) * cam * 7 : 0, shy = cam > .05 ? (Math.random() - .5) * cam * 7 : 0;
    c.save(); c.translate(v.ox + shx, v.oy + shy); c.scale(v.s, v.s);
    const al = e.alpha();
    drawGoalNets(c, e, t);
    const pos = (b: Body) => [b.px + (b.x - b.px) * al + b.vox, b.py + (b.y - b.py) * al + b.voy];
    const aimTeam = e.phase === 'aim' ? e.turn : -1;
    for (const b of e.bodies) if (b !== e.ball) { const [x, y] = pos(b); drawPiece(c, e, b, x, y, b.team === 0 ? im.t0 : im.t1, t, b.team === aimTeam && !(e.drag && e.drag.b !== b) && !e.isAiTurn(), e.phase === 'aim' && b.team !== e.turn); }
    drawTrail(c, e, ballIdx);
    { const [x, y] = pos(e.ball); drawBall(c, e.ball, x, y, im.ball, v.s); }
    drawGoalFrames(c, e, t);
    { const ab = e.drag?.b; if (ab) { const [x, y] = pos(ab); drawAim(c, e, t, x, y, im.arrow); } else aimS.on = false; }
    drawParts(c, e);
    c.restore();
    if (e.flash > 0) { const p = paints.fill; p.setColor(col('#ffffff', e.flash * .28)); c.drawRect(Skia.XYWHRect(0, 0, v.W, v.H), p); }
  }, { width: v.W, height: v.H });
}

export function toWorld(v: View, x: number, y: number) { return { x: (x - v.ox) / v.s, y: (y - v.oy) / v.s }; }
export type { SkPaint };
