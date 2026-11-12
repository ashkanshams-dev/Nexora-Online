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

export const fa = (n: number) => n.toLocaleString('fa-IR');
export const faNum = (s: string | number) => String(s).replace(/\d/g, d => '۰۱۲۳۴۵۶۷۸۹'[+d]);

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
