import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { TEAMS, teamPrice, ballPrice, fieldPrice, FIELDS, DEFAULT_FIELD, FIELDS_VERSION } from './game/data';

export type Profile = {
  name: string; coins: number; gems: number; xp: number; trophies: number;
  played: number; wins: number; losses: number; draws: number; goalsFor: number; goalsAgainst: number;
  team: string; ball: number; field: number; form: number;
  ownedTeams: string[]; ownedBalls: number[]; ownedFields: number[];
  lastDaily: number; streak: number;
  sound: boolean; music: boolean; haptics: boolean; aiLvl: 0 | 1 | 2; limit: number; turnTime: number;
  cupsWon: number; winStreak: number; bestStreak: number; chests: number; lastChest: number; claimedAch: string[]; quality: 'high' | 'low'; volume: number; oracle: boolean; oracleTour: boolean;
  fieldsV?: number; // field-index schema version (see FIELDS_VERSION)
};

const freeTeams = TEAMS.filter(t => teamPrice(t) === 0).map(t => t.id);
const DEFAULT: Profile = {
  name: 'Pilot', coins: 600, gems: 20, xp: 0, trophies: 0,
  played: 0, wins: 0, losses: 0, draws: 0, goalsFor: 0, goalsAgainst: 0,
  team: 'club0', ball: 0, field: DEFAULT_FIELD, form: 0,
  ownedTeams: freeTeams, ownedBalls: Array.from({ length: 36 }, (_, i) => i).filter(i => ballPrice(i) === 0),
  ownedFields: FIELDS.map((_, i) => i).filter(i => fieldPrice(i) === 0).concat([7]), // 7 = Stadium (was the old default, stays owned)
  lastDaily: 0, streak: 0,
  sound: true, music: true, haptics: true, aiLvl: 1, limit: 3, turnTime: 15,
  cupsWon: 0, winStreak: 0, bestStreak: 0, chests: 1, lastChest: 0, claimedAch: [], quality: 'high', volume: 1, oracle: true, oracleTour: false, fieldsV: FIELDS_VERSION,
};

const freeFields = FIELDS.map((_, i) => i).filter(i => fieldPrice(i) === 0);
// Saved profiles from before the NEXORA Pitch was prepended (fieldsV < 2) store old field indices:
// shift them by +1, grant every free field (incl. the pitch), and move players still on the old default (Stadium) onto the pitch.
export function migrate(q: Profile): Profile {
  const n = { ...q };
  if ((n.fieldsV || 1) < 2) {
    const old = typeof n.field === 'number' ? n.field : 6;
    n.ownedFields = (n.ownedFields || []).map(i => i + 1);
    n.field = old === 6 ? DEFAULT_FIELD : old + 1;
    n.fieldsV = 2;
  }
  n.ownedFields = Array.from(new Set([...freeFields, 7, ...(n.ownedFields || [])])).filter(i => i >= 0 && i < FIELDS.length);
  if (!(n.field >= 0 && n.field < FIELDS.length) || !n.ownedFields.includes(n.field)) n.field = DEFAULT_FIELD;
  n.ownedTeams = Array.from(new Set([...freeTeams, ...(n.ownedTeams || [])]));
  if (!TEAMS.some(t => t.id === n.team)) n.team = 'club0';
  return n;
}

export const level = (xp: number) => { let l = 1, need = 100, x = xp; while (x >= need) { x -= need; l++; need = Math.round(need * 1.25); } return { level: l, cur: x, need }; };
export const league = (t: number) => {
  const L = [['BRONZE', 0], ['SILVER', 300], ['GOLD', 800], ['PLATINUM', 1600], ['DIAMOND', 3000], ['NEXORA', 5000]] as const;
  let i = 0; while (i + 1 < L.length && t >= L[i + 1][1]) i++;
  return { name: L[i][0], idx: i, from: L[i][1], to: i + 1 < L.length ? L[i + 1][1] : L[i][1] + 2000 };
};

type Ctx = { p: Profile; ready: boolean; set: (u: Partial<Profile> | ((p: Profile) => Partial<Profile>)) => void; reset: () => void };
const StoreCtx = createContext<Ctx>({ p: DEFAULT, ready: false, set: () => {}, reset: () => {} });
const KEY = 'nexora.profile.v1';
export const LEAGUE_FA: Record<string, string> = { BRONZE: 'برنز', SILVER: 'نقره', GOLD: 'طلا', PLATINUM: 'پلاتین', DIAMOND: 'الماس', NEXORA: 'نکسورا' };
export const LEAGUES = [['BRONZE', 0], ['SILVER', 300], ['GOLD', 800], ['PLATINUM', 1600], ['DIAMOND', 3000], ['NEXORA', 5000]] as const;

export function StoreProvider({ children }: { children: React.ReactNode }) {
  const [p, setP] = useState<Profile>(DEFAULT); const [ready, setReady] = useState(false);
  const saveT = useRef<any>(null);
  useEffect(() => {
    AsyncStorage.getItem(KEY).then(s => { if (s) { try { const raw = JSON.parse(s); const q = migrate({ ...DEFAULT, fieldsV: raw.fieldsV ?? 1, ...raw }); setP(q); } catch { } } }).finally(() => setReady(true));
  }, []);
  const set = useCallback((u: Partial<Profile> | ((p: Profile) => Partial<Profile>)) => {
    setP(prev => {
      const n = { ...prev, ...(typeof u === 'function' ? u(prev) : u) };
      clearTimeout(saveT.current); saveT.current = setTimeout(() => AsyncStorage.setItem(KEY, JSON.stringify(n)).catch(() => {}), 250);
      return n;
    });
  }, []);
  const reset = useCallback(() => { setP(DEFAULT); AsyncStorage.removeItem(KEY).catch(() => {}); }, []);
  const v = useMemo(() => ({ p, ready, set, reset }), [p, ready, set, reset]);
  return <StoreCtx.Provider value={v}>{children}</StoreCtx.Provider>;
}
export const useStore = () => useContext(StoreCtx);
