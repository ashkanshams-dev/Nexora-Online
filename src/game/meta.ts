// Progression meta: achievements, daily rewards, chests, daily deals.
import type { Profile } from '../store';
import { BALL_NAMES, FIELDS, TEAMS, ballPrice, fieldPrice, teamPrice } from './data';
import { BALL_IMG, FIELD_THUMB, TEAM_IMG } from './assets';
import { teamKey } from './util';

export type Ach = { id: string; name: string; desc: string; icon: string; max: number; cur: (p: Profile) => number; coins: number; gems: number };
export const ACHS: Ach[] = [
  { id: 'first', name: 'اولین قدم', desc: 'یک بازی انجام بده', icon: 'x_ball', max: 1, cur: p => p.played, coins: 100, gems: 0 },
  { id: 'win5', name: 'برنده', desc: '۵ بازی ببر', icon: 'x_medal', max: 5, cur: p => p.wins, coins: 250, gems: 0 },
  { id: 'goals25', name: 'گلزن', desc: '۲۵ گل بزن', icon: 'x_statue', max: 25, cur: p => p.goalsFor, coins: 300, gems: 0 },
  { id: 'streak3', name: 'شکست‌ناپذیر', desc: '۳ برد پشت سر هم', icon: 'x_star', max: 3, cur: p => p.bestStreak, coins: 350, gems: 0 },
  { id: 'cup1', name: 'قهرمان', desc: 'جام نکسورا را ببر', icon: 'x_trophy', max: 1, cur: p => p.cupsWon, coins: 500, gems: 0 },
  { id: 'collect', name: 'کلکسیونر', desc: '۱۵ دیسک ویژه باز کن', icon: 'x_team', max: 15, cur: p => p.ownedTeams.filter(id => !id.startsWith('club') && !id.startsWith('nat') && !id.startsWith('iran')).length, coins: 400, gems: 0 },
  { id: 'win25', name: 'اسطوره', desc: '۲۵ بازی ببر', icon: 'x_crown', max: 25, cur: p => p.wins, coins: 800, gems: 0 },
  { id: 'gold', name: 'لیگ طلا', desc: 'به ۸۰۰ جام برس', icon: 'x_shield', max: 800, cur: p => p.trophies, coins: 600, gems: 0 },
];

export const DAILY = [
  // gems are a server-side economy now (challenges / seasons / tournaments) — daily login gives coins
  { coins: 100, gems: 0 }, { coins: 150, gems: 0 }, { coins: 250, gems: 0 }, { coins: 300, gems: 0 },
  { coins: 400, gems: 0 }, { coins: 450, gems: 0 }, { coins: 800, gems: 0 },
];

export type Item = { kind: 'team' | 'ball' | 'field'; id: string | number; name: string; price: number; img: any; rar: number };
export function allItems(p: Profile): Item[] {
  const out: Item[] = [];
  // discs are bought with gems from the online catalog (Team tab / Shop), not with coins
  if (false as boolean) for (const t of TEAMS) if (teamPrice(t) > 0 && !p.ownedTeams.includes(t.id)) out.push({ kind: 'team', id: t.id, name: t.name, price: teamPrice(t), img: TEAM_IMG[teamKey(t)], rar: t.cat === 'leg' || t.cat === 'vip' ? 3 : t.cat === 'emb' || t.cat === 'chrome' || t.cat === 'lux' || t.cat === 'car' ? 2 : 1 });
  for (let i = 0; i < 36; i++) if (ballPrice(i) > 0 && !p.ownedBalls.includes(i)) out.push({ kind: 'ball', id: i, name: BALL_NAMES[i], price: ballPrice(i), img: BALL_IMG['b' + i], rar: ballPrice(i) > 140 ? 2 : 1 });
  FIELDS.forEach((f, i) => { if (fieldPrice(i) > 0 && !p.ownedFields.includes(i)) out.push({ kind: 'field', id: i, name: f.name, price: fieldPrice(i), img: FIELD_THUMB[f.id], rar: fieldPrice(i) > 140 ? 2 : 1 }); });
  return out;
}
export const grant = (it: Item) => (q: Profile): Partial<Profile> =>
  it.kind === 'team' ? { ownedTeams: [...q.ownedTeams, it.id as string] } : it.kind === 'ball' ? { ownedBalls: [...q.ownedBalls, it.id as number] } : { ownedFields: [...q.ownedFields, it.id as number] };

// deterministic per-day shuffle so "deals of the day" stay put until midnight
export function dailyDeals(p: Profile, n = 4): Item[] {
  const items = allItems(p); const day = Math.floor(Date.now() / 86400000);
  let h = day * 2654435761 >>> 0; const rnd = () => { h ^= h << 13; h ^= h >>> 17; h ^= h << 5; return ((h >>> 0) % 10000) / 10000; };
  const a = items.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a.slice(0, n).map(it => ({ ...it, price: Math.round(it.price * .7 / 5) * 5 }));
}

export const CHEST_EVERY = 4 * 3600 * 1000;
export type ChestPrize = { item?: Item; coins: number; gems: number };
export function rollChest(p: Profile, premium: boolean): ChestPrize {
  const items = allItems(p).filter(i => premium ? i.rar >= 2 : true);
  const r = Math.random();
  if (items.length && r < (premium ? .75 : .4)) {
    const w = items.map(i => (premium ? i.rar : 4 - i.rar)); const sum = w.reduce((a, b) => a + b, 0); let x = Math.random() * sum;
    for (let i = 0; i < items.length; i++) { x -= w[i]; if (x <= 0) return { item: items[i], coins: premium ? 60 : 20, gems: 0 }; }
  }
  return { coins: premium ? 320 + Math.round(Math.random() * 200) : 80 + Math.round(Math.random() * 120), gems: 0 };
}
