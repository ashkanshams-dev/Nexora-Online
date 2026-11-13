// Bilingual UI (fa / en). Every Persian literal in the app is the lookup key; <T> and tr()
// translate at render time, so screens keep their Persian source text.
import EN from './en.json';

export type Lang = 'fa' | 'en';
export let LANG: Lang = 'fa';
export const setLang = (l: Lang) => { LANG = l; cache.clear(); };

const dict = EN as Record<string, string>;
const esc = (s: string) => s.replace(/[.*+?^$()|[\]\\]/g, '\\$&').replace(/[{}]/g, m => '\\' + m);
// template keys: "+{} سکه" -> /^\+(.*?) سکه$/
const pats: [RegExp, string][] = Object.keys(dict).filter(k => k.includes('{}')).map(k => {
  const re = '^' + k.split('{}').map(esc).join('([\\s\\S]*?)') + '$';
  return [new RegExp(re), dict[k]] as [RegExp, string];
}).sort((a, b) => b[0].source.length - a[0].source.length);
const FA = /[\u0600-\u06FF]/;
const latin = (s: string) => s.replace(/[۰-۹]/g, d => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d))).replace(/[٠-٩]/g, d => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d))).replace(/٬/g, ',').replace(/٫/g, '.');
const cache = new Map<string, string>();

function look(s: string): string {
  const hit = dict[s]; if (hit !== undefined) return hit;
  for (const [re, en] of pats) {
    const m = re.exec(s); if (!m) continue;
    let i = 1; return en.replace(/\{\}/g, () => look(m[i++] ?? ''));
  }
  // multi-line text: translate line by line
  if (s.includes('\n')) return s.split('\n').map(look).join('\n');
  return s;
}

/** translate a UI string for the current language (identity in Persian) */
export function tr(s: string): string {
  if (LANG === 'fa' || !s || !FA.test(s) && !/[۰-۹]/.test(s)) return s;
  let r = cache.get(s); if (r !== undefined) return r;
  r = latin(look(s)); if (cache.size > 4000) cache.clear(); cache.set(s, r); return r;
}
export const isEn = () => LANG === 'en';
