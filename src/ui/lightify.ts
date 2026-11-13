// Light theme without rewriting every screen: once, before any screen module loads, dark surfaces
// in StyleSheets and gradients are mapped to soft daylight tints of the same hue, and pale text is
// mapped to deep ink of the same hue. Saturated brand colours (buttons, accents) and artwork stay.
import { StyleSheet } from 'react-native';

type RGBA = [number, number, number, number];
const NAMED: Record<string, RGBA> = { white: [255, 255, 255, 1], black: [0, 0, 0, 1], transparent: [0, 0, 0, 0] };
function parse(c: string): RGBA | null {
  c = c.trim().toLowerCase();
  if (NAMED[c]) return NAMED[c];
  let m = /^#([0-9a-f]{3,8})$/.exec(c);
  if (m) {
    let h = m[1]; if (h.length === 3 || h.length === 4) h = h.split('').map(x => x + x).join('');
    const n = (i: number) => parseInt(h.slice(i, i + 2), 16);
    return [n(0), n(2), n(4), h.length === 8 ? n(6) / 255 : 1];
  }
  m = /^rgba?\(([^)]+)\)$/.exec(c);
  if (m) { const p = m[1].split(',').map(s => parseFloat(s)); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; }
  return null;
}
function hsl([r, g, b]: RGBA) {
  r /= 255; g /= 255; b /= 255; const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2;
  let h = 0, s = 0;
  if (mx !== mn) { const d = mx - mn; s = l > .5 ? d / (2 - mx - mn) : d / (mx + mn); h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; h /= 6; }
  return [h, s, l];
}
function rgb(h: number, s: number, l: number): [number, number, number] {
  if (!s) return [l, l, l].map(v => Math.round(v * 255)) as any;
  const q = l < .5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  const f = (t: number) => { if (t < 0) t += 1; if (t > 1) t -= 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < .5 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; };
  return [f(h + 1 / 3), f(h), f(h - 1 / 3)].map(v => Math.round(v * 255)) as any;
}
const out = (c: [number, number, number], a: number) => `rgba(${c[0]},${c[1]},${c[2]},${+a.toFixed(3)})`;

/** dark surface -> light tint (same hue) */
export function lightBg(c: any): any {
  if (typeof c !== 'string') return c; const v = parse(c); if (!v) return c;
  const [h, s, l] = hsl(v); if (l >= .38 || v[3] === 0) return c;
  return out(rgb(h, Math.min(s, .55) * .8, .955 - l * .35), Math.min(1, v[3] * 1.05));
}
/** pale text -> deep ink (same hue) */
export function lightText(c: any): any {
  if (typeof c !== 'string') return c; const v = parse(c); if (!v) return c;
  const [h, s, l] = hsl(v); if (l < .62 || (s > .75 && l < .8)) return c;
  return out(rgb(h, Math.min(s, .6), .1 + (1 - l) * .55), v[3]);
}
/** pale hairlines on dark -> soft hairlines on light */
export function lightLine(c: any): any {
  if (typeof c !== 'string') return c; const v = parse(c); if (!v) return c;
  const [h, s, l] = hsl(v); if (l < .55) return lightBg(c);
  return out(rgb(h, Math.min(s, .6), .45), Math.min(1, v[3] * 1.3));
}

const BG_KEYS = ['backgroundColor'], TXT_KEYS = ['color', 'textShadowColor'], LINE_KEYS = ['borderColor', 'borderTopColor', 'borderBottomColor', 'borderLeftColor', 'borderRightColor'];
export function lightStyle(st: any): any {
  if (!st || typeof st !== 'object' || Array.isArray(st)) return st;
  const o: any = { ...st };
  for (const k of BG_KEYS) if (k in o) o[k] = lightBg(o[k]);
  for (const k of TXT_KEYS) if (k in o) o[k] = lightText(o[k]);
  for (const k of LINE_KEYS) if (k in o) o[k] = lightLine(o[k]);
  if ('shadowColor' in o && o.shadowColor === '#000') o.shadowOpacity = (o.shadowOpacity ?? .3) * .35;
  return o;
}

let installed = false;
export function installLight() {
  if (installed) return; installed = true;
  const create = StyleSheet.create;
  (StyleSheet as any).create = (obj: any) => { const r: any = {}; for (const k in obj) r[k] = lightStyle(obj[k]); return create(r); };
  try {
    const LG = require('expo-linear-gradient').LinearGradient;
    const render = LG.prototype.render;
    LG.prototype.render = function () {
      const p = this.props; const self = Object.create(this);
      Object.defineProperty(self, 'props', { value: { ...p, colors: (p.colors || []).map(lightBg) } });
      return render.call(self);
    };
  } catch { }
}
