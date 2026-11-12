import { Team, TEAMS } from './data';
export const teamKey = (t: Team) => t.cat + String(t.idx).padStart(2, '0');
export const teamById = (id: string) => TEAMS.find(t => t.id === id) || TEAMS[0];
export const hash = (s: string) => { let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return (h >>> 0); };
// cosmetic card stats (do not affect physics, except VIP speed bonus which the engine applies)
export const cardStats = (seed: string) => { const h = hash(seed); return { power: 60 + (h % 37), control: 55 + ((h >> 6) % 42), speed: 58 + ((h >> 12) % 40), spin: 50 + ((h >> 18) % 46) }; };
export const rarity = (t: Team) => (t.cat === 'vip' || t.cat === 'leg' ? 3 : t.cat === 'lux' || t.cat === 'car' || t.cat === 'emb' ? 2 : t.cat === 'spt' || t.cat === 'elite' ? 1 : 0);
export const RARITY = [{ n: 'COMMON', c: '#8ea3d6' }, { n: 'RARE', c: '#4fe3ff' }, { n: 'EPIC', c: '#b46bff' }, { n: 'LEGENDARY', c: '#ffd257' }];
