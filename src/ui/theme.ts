import { LANG } from '../i18n';
export const C = {
  bg: '#030614',
  bg2: '#060b22',
  panel: 'rgba(14,22,58,0.78)',
  panel2: 'rgba(8,12,34,0.9)',
  glass: 'rgba(14,24,64,0.62)',
  line: 'rgba(110,170,255,0.24)',
  lineHi: 'rgba(120,220,255,0.75)',
  cyan: '#4fe3ff',
  sky: '#7fc8ff',
  blue: '#3b82ff',
  indigo: '#6d5bff',
  violet: '#a35bff',
  pink: '#ff4fa3',
  gold: '#ffd257',
  orange: '#ff8a3a',
  red: '#ff4a5a',
  green: '#3dffa8',
  text: '#eef4ff',
  dim: '#93a7d8',
  dim2: '#5f6f9e',
};

export const F = {
  title: 'Orbitron_900Black',
  head: 'Orbitron_700Bold',
  body: 'Exo2_600SemiBold',
  bold: 'Exo2_800ExtraBold',
  fa: 'Vazirmatn_500Medium',
  faB: 'Vazirmatn_800ExtraBold',
};

// gradient presets (always 3 stops so LinearGradient typing stays happy)
export const G = {
  primary: [C.cyan, '#5b8cff', C.violet] as const,
  gold: ['#8a5200', '#d39420', '#ffe08a'] as const,
  green: ['#0a6b4a', '#16b77a', '#5dffbf'] as const,
  red: ['#5a0f24', '#a3203f', '#ff5b74'] as const,
  dark: ['#151f4a', '#1d2b63', '#2a3f86'] as const,
  violet: ['#3a1d8a', '#6d3bff', '#c08bff'] as const,
};

export const fa = (n: number) => n.toLocaleString(LANG === 'en' ? 'en-US' : 'fa-IR');
export const faNum = (s: string | number) => LANG === 'en' ? String(s) : String(s).replace(/\d/g, d => '۰۱۲۳۴۵۶۷۸۹'[+d]);

// ---------- theme switch (applied once at boot, before screens load) ----------
export type ThemeName = 'dark' | 'light';
export let THEME: ThemeName = 'dark';
export const isLight = () => THEME === 'light';
export function applyTheme(t: ThemeName) {
  THEME = t;
  if (t !== 'light') return;
  Object.assign(C, {
    bg: '#eef3fc', bg2: '#e2eaf8',
    panel: 'rgba(255,255,255,0.86)', panel2: 'rgba(246,249,255,0.95)', glass: 'rgba(255,255,255,0.72)',
    line: 'rgba(40,70,140,0.18)', lineHi: 'rgba(30,120,220,0.6)',
    cyan: '#0796c9', sky: '#2b74d6', blue: '#2f6bff', indigo: '#5546e8', violet: '#7c3bea', pink: '#d92c80',
    gold: '#b07800', orange: '#d9601a', red: '#dc2f44', green: '#0a9a62',
    text: '#0e1a3a', dim: '#4a5a84', dim2: '#7b88aa',
  });
  require('./lightify').installLight();
}

// ---------- design tokens (menu rebuild) ----------
/** logo backdrop colour */
export const BG0 = '#05040E';
/** spacing scale */
export const SP = { xs: 4, s: 8, m: 12, l: 16, xl: 24, xxl: 32 } as const;
export const R = { s: 10, m: 14, l: 20, xl: 26, pill: 999 } as const;
/** typography scale (px) */
export const TY = { tiny: 10, cap: 11, small: 12, body: 14, h3: 16, h2: 19, h1: 24, hero: 30 } as const;
/** ONE icon size scale: vector/inline glyphs 20/24/28, round art buttons always ICON_ART inside a 44pt target */
export const IC = { s: 20, m: 24, l: 28 } as const;
export const ICON_ART = 40;
export const TOUCH = 44;
export const glow = (color: string, r = 14, o = .6) => ({ shadowColor: color, shadowOpacity: o, shadowRadius: r, shadowOffset: { width: 0, height: 0 }, elevation: Math.round(r / 2) });
export const depth = { shadowColor: '#000', shadowOpacity: .55, shadowRadius: 14, shadowOffset: { width: 0, height: 8 }, elevation: 10 };
