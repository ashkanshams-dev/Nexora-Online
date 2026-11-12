// Online match — host-authoritative netcode on top of the existing Engine + Skia renderer.
//
//  v7 NETCODE — deterministic lockstep replay + client-side prediction (no snapshot-interpolation lag):
//  HOST   runs the real simulation and owns score/turns. Every shot (human, remote or bot) is broadcast once as a
//         'go' message = the quantised flick + the exact pre-shot state. Snapshots drop to 10 Hz (2 Hz at rest) and
//         carry the authoritative state, a keyframe for verification and the match scalars.
//  OTHERS replay the shot locally with the bit-identical engine (sqrt-only maths, seeded aim RNG), so the ball moves
//         the moment 'go' arrives: no interpolation buffer, no jitter. The shooter does not even wait for 'go' — the
//         flick is predicted instantly and only re-synced if the host disagrees. Keyframes every 24 ticks catch any
//         drift (hard re-sync + visual blend). Spectators who joined mid-shot fall back to snapshot interpolation.
//
//  CONTROL RULE (2v2 / 3v3): turns alternate between teams exactly like offline. Within a team the
//  humans rotate: the k-th turn of team T belongs to slot (k-1) mod teamSize. A disconnected player
//  is skipped (next connected teammate); a team with nobody connected is played by the bot.
//  The player in control may flick ANY disc of their team. The HUD always shows whose turn it is.
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Animated, StyleSheet, View, useWindowDimensions } from 'react-native';
import { Canvas, Picture, SkPicture, createPicture, useImage } from '@shopify/react-native-skia';
import { SharedValue, useSharedValue } from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Body, Engine, EngineEvent, MatchCfg, Phase } from '../game/engine';
import { computeView, frame, staticLayer, toWorld, View as GView } from '../game/render';
import { FIELDS, Team } from '../game/data';
import { BALL_IMG, FIELD_IMG, GOAL_IMG, TEAM_IMG, UI2 } from '../game/assets';
import { teamKey } from '../game/util';
import { Btn, Img, Panel, Press, T } from '../ui/kit';
import { C, F, G, fa } from '../ui/theme';
import { buzz, playLoop, sfx, stopLoop } from '../sound';
import { Room, RoomPlayer, rpc, supabase } from '../net/supabase';
import { RoomLink, useLink } from './link';
import { Badge, ChatPanel, PingBadge, S, VoiceBar, teamOfAvatar } from './ui';
import { discStats } from '../net/discs';
import { useOracle } from '../oracle/Oracle';
import { coachMiss } from '../oracle/coach';
import { LMAX } from '../game/engine';

export type OnlineOutcome = {
  matchId: string; score: [number, number]; winner: -1 | 0 | 1; ratingDelta: number | null; myTeam: 0 | 1 | null;
  teams: [Team, Team]; names: [string, string]; reported: boolean; ranked: boolean;
};

type Snap = {
  q: number; ts: number; hz: number; ph: Phase; tu: 0 | 1; sc: [number, number]; ml: number; tl: number; su: 0 | 1; c: string | null; n: number; p: number[]; R: number[]; ev: number[][];
  // v7 lockstep fields: timeline position, epoch kind (1 = shot, 0 = kick-off), shot counters, authoritative state, keyframe
  ep: number; tk: number; mv: 0 | 1; sh: number; sno: number; ps: number[]; kf?: [number, number[]];
};
type Go = { k: 'go'; ep: number; n: number; b: number; dx: number; dy: number; hu: 0 | 1; sq: number; st: number[]; sh: number; sno: number; tu: 0 | 1; pw: number; ac: number };
const KEY_EVERY = 24;   // keyframe every 24 physics ticks = 10 per second

// ---------- wire format ----------
const encEv = (e: EngineEvent): number[] =>
  e.t === 'hit' ? [0, e.ball ? 1 : 0, Math.round(e.power * 100)] : e.t === 'wall' ? [1, Math.round(e.power * 100)] : e.t === 'post' ? [2, Math.round(e.power * 100)]
    : e.t === 'goal' ? [3, e.team, e.nogoal ? 1 : 0] : e.t === 'turn' ? [4, e.team] : e.t === 'shot' ? [5, e.team] : e.t === 'end' ? [6, e.score[0], e.score[1]] : [7];
const decEv = (a: number[]): EngineEvent =>
  a[0] === 0 ? { t: 'hit', ball: !!a[1], power: a[2] / 100 } : a[0] === 1 ? { t: 'wall', power: a[1] / 100 } : a[0] === 2 ? { t: 'post', power: a[1] / 100 }
    : a[0] === 3 ? { t: 'goal', team: a[1] as 0 | 1, nogoal: !!a[2] } : a[0] === 4 ? { t: 'turn', team: a[1] as 0 | 1 } : a[0] === 5 ? { t: 'shot', team: a[1] as 0 | 1 }
      : a[0] === 6 ? { t: 'end', score: [a[1], a[2]] } : { t: 'clock' };
const TAU = Math.PI * 2;

export function cfgFromRoom(room: Room): MatchCfg {
  const s = room.settings || ({} as any);
  const time = Math.max(0, Number(s.time) || 0), goals = Math.max(1, Number(s.goals) || 3);
  return {
    field: Math.min(FIELDS.length - 1, Math.max(0, Number(s.field) || 0)), ball: Math.min(35, Math.max(0, Number(s.ball) || 0)), forms: [0, 0],
    ai: false, aiLvl: 1, limit: time > 0 ? 99 : goals, matchTime: time, turnTime: s.turn === 0 ? 0 : Math.max(5, Number(s.turn) || 15), vip: [false, false], first: 0,
  };
}
export const ruleLabel = (s: Room['settings']) => (Number(s?.time) > 0 ? `${fa(Math.round(Number(s.time) / 60))} دقیقه` : `تا ${fa(Number(s?.goals) || 3)} گل`);

const discOf = (p?: RoomPlayer | null) => p?.disc_id || p?.profiles?.equipped_disc || p?.profiles?.avatar || 'club0';
const teamOf = (players: RoomPlayer[], t: 0 | 1) => players.filter(p => p.role === 'player' && p.team === t).sort((a, b) => (a.slot ?? 0) - (b.slot ?? 0));

type Props = { link: RoomLink; matchId: string; onFinish: (o: OnlineOutcome) => void; onExit: (why: 'quit' | 'hostLost' | 'aborted') => void; toast: (m: string, k?: string) => void; fx?: boolean };

export default function OnlineMatch({ link, matchId, onFinish, onExit, toast, fx = true }: Props) {
  const { width: W, height: H } = useWindowDimensions(); const ins = useSafeAreaInsets();
  const ls = useLink(link);
  const room0 = useRef(ls.room as Room).current;
  const isHost = room0.host === link.me;
  const cfg = useMemo(() => {
    const c = cfgFromRoom(room0), cap = (t: 0 | 1) => teamOf(ls.players, t)[0];
    c.stats = [discStats(discOf(cap(0))), discStats(discOf(cap(1)))];
    return c;
  }, []);
  const eng = useMemo(() => {
    const e = new Engine(cfg); e.keyEvery = KEY_EVERY;
    let h = 2166136261; for (let i = 0; i < matchId.length; i++) { h ^= matchId.charCodeAt(i); h = Math.imul(h, 16777619); }
    e.seed = h >>> 0; e.follower = room0.host !== link.me; return e;
  }, []);
  const start = useMemo(() => {
    const t0 = teamOf(ls.players, 0), t1 = teamOf(ls.players, 1);
    const meP = ls.players.find(p => p.user_id === link.me);
    const myTeam = meP?.role === 'player' && (meP.team === 0 || meP.team === 1) ? meP.team : null;
    const nm = (t: RoomPlayer[], d: string) => (t[0]?.profiles?.username || d) + (t.length > 1 ? ` +${fa(t.length - 1)}` : '');
    const names: [string, string] = [nm(t0, 'آبی'), nm(t1, 'قرمز')];
    const teams: [Team, Team] = [teamOfAvatar(discOf(t0[0])), teamOfAvatar(discOf(t1[0]))];
    return { myTeam: myTeam as 0 | 1 | null, names, teams, ranked: room0.ranked };
  }, []);
  const flipped = start.myTeam === 1;
  const playersRef = useRef(ls.players); playersRef.current = ls.players;
  const onlineRef = useRef(ls.online); onlineRef.current = ls.online;
  const nameOf = (uid: string | null) => (uid ? playersRef.current.find(p => p.user_id === uid)?.profiles?.username || '…' : 'ربات');

  const f = FIELDS[cfg.field];
  const im = {
    field: useImage(FIELD_IMG[f.id]), goal: useImage(GOAL_IMG[f.gs]), ball: useImage(BALL_IMG['b' + cfg.ball]),
    t0: useImage(TEAM_IMG[teamKey(start.teams[0])]), t1: useImage(TEAM_IMG[teamKey(start.teams[1])]),
  };
  const topM = ins.top + 92, botM = ins.bottom + 72;
  const view = useMemo<GView>(() => computeView(eng, W, H, flipped ? botM : topM, flipped ? topM : botM), [W, H, topM, botM]);
  const bg = useMemo(() => (im.field ? staticLayer(eng, view, im) : null), [im.field, view]);
  const picSet = useRef<(p: SkPicture) => void>(() => {});
  const imRef = useRef(im); imRef.current = im; const bgRef = useRef(bg); bgRef.current = bg; const viewRef = useRef(view); viewRef.current = view;

  const [hud, setHud] = useState({ s0: 0, s1: 0, turn: 0 as 0 | 1, clock: '', tl: 1, sudden: false, ctrl: null as string | null, phase: 'aim' as Phase, wait: !isHost });
  const [quit, setQuit] = useState(false);
  const [chat, setChat] = useState(false);
  const banner = useRef(new Animated.Value(0)).current; const [bText, setBText] = useState({ t: '', s: '', c: C.gold });
  const showBanner = (t: string, s: string, c: string) => {
    setBText({ t, s, c }); banner.setValue(0);
    Animated.sequence([Animated.spring(banner, { toValue: 1, useNativeDriver: true, speed: 14, bounciness: 12 }), Animated.delay(1100), Animated.timing(banner, { toValue: 2, duration: 300, useNativeDriver: true })]).start();
  };

  // shared mutable state for the loop (never triggers renders)
  const hs = useRef({ turnCount: [0, 0] as [number, number], seq: 0, ctrl: null as string | null, lastSend: 0, q: 0, evs: [] as number[][], t0: Date.now(), lastAim: 0, lastKf: 0 }).current;
  // host: broadcast every shot the moment it is fired, with the exact pre-shot state (lockstep replay on every client)
  if (isHost && !eng.onFire) eng.onFire = (b, dx, dy, hu, sq, pre) => {
    hs.lastKf = 0; const st = cfg.stats?.[b.team as 0 | 1] || { power: 5, accuracy: 5 };
    const g: Go = { k: 'go', ep: eng.epoch + 1, n: hs.seq, b: b.id, dx: Math.round(dx * 16), dy: Math.round(dy * 16), hu: hu ? 1 : 0, sq, st: pre, sh: eng.shots, sno: eng.shotNo, tu: eng.turn, pw: st.power, ac: st.accuracy };
    link.sendGame(g);
  };
  const cs = useRef({
    buf: [] as Snap[], offs: [] as [number, number][], applied: -1, lastRecv: Date.now(), pendingShot: 0, lastAim: 0, res: null as null | { winner: -1 | 0 | 1; rd: number; score: [number, number]; ok: boolean }, endAt: 0, prev: null as Float64Array | null, ctrl: null as string | null, seq: 0, got: false,
    // lockstep replay of the current shot (null = at rest or interpolation fallback)
    replay: null as null | { ep: number; endTk: number | null; pred: null | { n: number; b: number; dx: number; dy: number; pw: number; ac: number }; at: number },
    pend: [] as Snap[], kfs: [] as [number, number, number[]][], goalEp: -1, lastQ: -1, waitGo: 0, interp: false,
  }).current;
  const done = useRef<'no' | 'ended' | 'finished' | 'aborted'>('no');
  const finishRef = useRef(onFinish); finishRef.current = onFinish; const exitRef = useRef(onExit); exitRef.current = onExit; const toastRef = useRef(toast); toastRef.current = toast;

  const outcome = (score: [number, number], d: number | null, reported: boolean): OnlineOutcome => {
    const w: -1 | 0 | 1 = score[0] > score[1] ? 0 : score[1] > score[0] ? 1 : -1;
    const my = start.myTeam, rd = d === null ? null : !start.ranked ? 0 : my === 1 ? -d : my === 0 ? d : null;
    return { matchId, score, winner: w, ratingDelta: rd, myTeam: my, teams: start.teams, names: start.names, reported, ranked: start.ranked };
  };

  const oracle = useOracle(); const oracleRef = useRef(oracle); oracleRef.current = oracle;
  useEffect(() => oracle.setScene('match'), []);
  const co = useRef({ mine: false, touched: false, power: 0, lastTip: 0, misses: 0, turnN: 0, reminded: -1 });

  // local feedback for an engine event (host: straight from the engine; others: from snapshots)
  const onEvent = (ev: EngineEvent) => {
    if (ev.t === 'shot') { const c = co.current; c.mine = (isHost ? hs.ctrl : cs.ctrl) === link.me; c.touched = false; if (isHost && c.mine) c.power = eng.lastPower; }
    else if (ev.t === 'hit' && ev.ball) co.current.touched = true;
    else if (ev.t === 'turn') {
      const c = co.current; c.turnN++;
      if (c.mine && !c.touched) {
        c.misses++; const t = coachMiss(c.power, c.misses);
        if (t && Date.now() - c.lastTip > 18000) { c.lastTip = Date.now(); oracleRef.current.coach(t, c.power > .9 ? 'focus' : 'idea'); }
      }
      c.mine = false;
    }
    if (ev.t === 'hit') { sfx(ev.ball ? 'hitb' : 'hitp', ev.power); if (ev.power > .35) buzz(ev.power > .7 ? 'medium' : 'light'); }
    else if (ev.t === 'wall') sfx('wall', ev.power);
    else if (ev.t === 'post') { sfx('post', ev.power); buzz('medium'); }
    else if (ev.t === 'shot') buzz('light');
    else if (ev.t === 'goal') {
      if (ev.nogoal) showBanner('گل مردود', 'با ضربه‌ی اول نمی‌شه گل زد', C.dim);
      else { co.current.touched = true; sfx('goal'); sfx('roar'); buzz('heavy'); showBanner('گل!', start.names[ev.team], ev.team === 0 ? C.cyan : C.red); if (!isHost && cs.goalEp !== eng.epoch) eng.fxGoal(ev.team); if (ev.team === start.myTeam) oracleRef.current.react('goal'); }
    } else if (ev.t === 'clock') showBanner('گل طلایی', 'گل بعدی برنده‌ست', C.gold);
    else if (ev.t === 'end' && done.current === 'no') { done.current = 'ended'; sfx('final'); stopLoop('crowd'); if (isHost) hostReport(ev.score); else cs.endAt = Date.now(); }
  };

  // ---------- host: report the result, then tell everyone ----------
  const hostReport = async (score: [number, number]) => {
    sendSnap(true);
    const dur = Math.round((Date.now() - hs.t0) / 1000);
    let d: number | null = null, ok = false;
    for (let i = 0; i < 3 && !ok; i++) {
      try { const r = await rpc<{ winner: number; rating_delta: number }>('report_match', { p_match: matchId, p_score_a: score[0], p_score_b: score[1], p_duration: dur }); d = r?.rating_delta ?? 0; ok = true; }
      catch (e: any) { if (/not live/i.test(e?.message || '')) break; await new Promise(r => setTimeout(r, 1500)); }
    }
    if (!ok) toastRef.current('ثبت نتیجه ناموفق بود', 'err');
    link.sendGame({ k: 'res', winner: score[0] > score[1] ? 0 : score[1] > score[0] ? 1 : -1, rd: d ?? 0, score, ok });
    link.ping();
    setTimeout(() => { if (done.current === 'ended') { done.current = 'finished'; finishRef.current(outcome(score, d, ok)); } }, 1100);
  };

  // ---------- host: snapshots ----------
  const sendSnap = (force = false) => {
    const now = Date.now();
    // lockstep clients do not need a dense stream any more: 10 Hz while moving keeps keyframe checks + spectators
    // smooth, and cuts Supabase Realtime traffic ~3x (fewer throttled/queued messages = lower, steadier ping)
    const hz = 10;
    const moving = eng.phase === 'move' || eng.phase === 'goal';
    if (!force && now - hs.lastSend < (moving ? 1000 / hz : 500)) return;
    hs.lastSend = now;
    const p: number[] = [];
    for (const b of eng.bodies) { p.push(Math.round(b.x * 10), Math.round(b.y * 10), Math.round((((b.ang % TAU) + TAU) % TAU) * 100)); }
    const R = Array.from(eng.ball.R, v => Math.round(v * 1000));
    let kf: [number, number[]] | undefined;
    if (moving) { let best = -1; eng.keys.forEach((_, t) => { if (t > hs.lastKf && t > best) best = t; }); if (best > 0) { kf = [best, eng.keys.get(best)!]; hs.lastKf = best; } }
    const s: Snap = {
      q: ++hs.q, ts: now, hz, ph: eng.phase, tu: eng.turn, sc: [eng.score[0], eng.score[1]], ml: Math.round(eng.mleft * 10) / 10, tl: Math.round(eng.tleft * 10) / 10, su: eng.sudden ? 1 : 0, c: hs.ctrl, n: hs.seq, p, R, ev: hs.evs,
      ep: eng.epoch, tk: eng.tick, mv: eng.epochKind, sh: eng.shots, sno: eng.shotNo, ps: eng.packState(), kf,
    };
    hs.evs = [];
    link.sendGame({ k: 's', s });
  };

  const ctrlFor = (t: 0 | 1) => {
    const team = teamOf(playersRef.current, t); if (!team.length) return null;
    const n = team.length, st0 = ((hs.turnCount[t] - 1) % n + n) % n;
    for (let i = 0; i < n; i++) { const pl = team[(st0 + i) % n]; if (pl.user_id === link.me || onlineRef.current[pl.user_id]) return pl.user_id; }
    return null;
  };

  // ---------- client: apply snapshots ----------
  const applyScalars = (s: Snap, lockstep = false) => {
    if (!lockstep) eng.phase = s.ph;
    eng.turn = s.tu; eng.score = [s.sc[0], s.sc[1]]; eng.mleft = s.ml; eng.tleft = s.tl; eng.sudden = !!s.su;
    cs.ctrl = s.c; cs.seq = s.n; eng.aiTeams = [false, false]; if (s.c === null) eng.aiTeams[s.tu] = true;
    if (typeof s.ep === 'number') { eng.shots = s.sh; eng.shotNo = s.sno; }
    if (s.ph !== 'aim' && eng.drag && !lockstep) eng.drag = null;
    for (const e of s.ev) {
      const ev = decEv(e);
      // in lockstep the local replay already produced the hit/wall/post/shot feedback in sync with the picture
      if (lockstep && (ev.t === 'hit' || ev.t === 'wall' || ev.t === 'post' || ev.t === 'shot')) continue;
      if (ev.t === 'goal' && cs.goalEp === s.ep) continue;   // banner already shown by the local replay
      onEvent(ev);
    }
  };
  // jump the local engine onto an authoritative state (rest / kick-off / rollback)
  const adopt = (s: Snap) => {
    if (!Array.isArray(s.ps)) return;
    const old = eng.bodies.map(b => [b.x, b.y]);
    eng.unpackState(s.ps); eng.epoch = s.ep; eng.epochKind = s.mv; eng.tick = s.tk; eng.acc = 0; eng.keys.clear();
    // tiny residual (quantisation) → blend visually instead of popping; big jump (kick-off) → snap
    eng.bodies.forEach((b, i) => { const dx = old[i][0] - b.x, dy = old[i][1] - b.y; if (dx * dx + dy * dy < 40 * 40) { b.vox = dx; b.voy = dy; } });
    cs.got = true;
  };
  // start (or restart) the lockstep replay of a shot from the host's 'go'
  const startReplay = (g: Go) => {
    eng.unpackState(g.st); eng.shots = g.sh; eng.shotNo = g.sno; eng.epoch = g.ep - 1; eng.turn = g.tu; eng.phase = 'aim'; eng.acc = 0;
    if (cfg.stats) cfg.stats[g.tu] = { power: g.pw, accuracy: g.ac };
    const b = eng.bodies.find(x => x.id === g.b); if (!b) return false;
    eng.drag = null; const dx = g.dx / 16, dy = g.dy / 16;
    eng.fire(b, dx, dy, Math.hypot(dx, dy), !!g.hu, g.sq);
    cs.replay = { ep: eng.epoch, endTk: null, pred: null, at: Date.now() }; cs.kfs = []; cs.got = true; cs.waitGo = 0;
    return true;
  };
  // keyframe check: same tick, compare; on drift re-sync to the host and fast-forward back to "now"
  const checkKeys = () => {
    const r = cs.replay; if (!r) return;
    for (let i = cs.kfs.length - 1; i >= 0; i--) {
      const [ep, tk, st] = cs.kfs[i];
      if (ep !== r.ep) { cs.kfs.splice(i, 1); continue; }
      const mine = eng.keys.get(tk); if (!mine) { if (eng.tick > tk + KEY_EVERY * 3) cs.kfs.splice(i, 1); continue; }
      cs.kfs.splice(i, 1);
      if (Engine.packError(mine, st) > 2.5) {
        const now = eng.tick, old = eng.bodies.map(b => [b.x, b.y]);
        eng.unpackState(st); eng.tick = tk; eng.fastForward(now);
        eng.bodies.forEach((b, j) => { const dx = old[j][0] - b.x, dy = old[j][1] - b.y; if (dx * dx + dy * dy < 120 * 120) { b.vox = dx; b.voy = dy; } });
      }
    }
  };
  const placeBodies = (a: Snap, b: Snap | null, k: number, dt: number) => {
    const n = eng.bodies.length; if (a.p.length < n * 3) return;
    if (!cs.prev || cs.prev.length !== n * 2) cs.prev = new Float64Array(n * 2);
    for (let i = 0; i < n; i++) {
      const bd = eng.bodies[i];
      let x = a.p[i * 3] / 10, y = a.p[i * 3 + 1] / 10, ang = a.p[i * 3 + 2] / 100;
      if (b && b.p.length >= n * 3) {
        x += (b.p[i * 3] / 10 - x) * k; y += (b.p[i * 3 + 1] / 10 - y) * k;
        let da = b.p[i * 3 + 2] / 100 - ang; if (da > Math.PI) da -= TAU; else if (da < -Math.PI) da += TAU; ang += da * k;
      }
      const px = cs.prev[i * 2], py = cs.prev[i * 2 + 1];
      bd.vx = cs.got ? (x - px) / Math.max(dt, 1e-3) : 0; bd.vy = cs.got ? (y - py) / Math.max(dt, 1e-3) : 0;
      if (Math.abs(bd.vx) < 4) bd.vx = 0; if (Math.abs(bd.vy) < 4) bd.vy = 0;
      bd.x = bd.px = x; bd.y = bd.py = y; bd.ang = ang; bd.vox = bd.voy = 0;
      cs.prev[i * 2] = x; cs.prev[i * 2 + 1] = y;
    }
    const src = (b && k > .5 ? b : a).R; if (src.length === 9) for (let j = 0; j < 9; j++) eng.ball.R[j] = src[j] / 1000;
    cs.got = true; eng.acc = 0;
  };

  // ---------- network messages ----------
  useEffect(() => {
    return link.onGame((m, from) => {
      if (!m || typeof m !== 'object') return;
      if (!isHost) cs.lastRecv = Date.now();
      if (m.k === 'go' && !isHost) {
        const g = m as Go; if (!Array.isArray(g.st)) return;
        const r = cs.replay, pr = r?.pred;
        // my own predicted shot confirmed by the host → nothing to do, the replay is already running
        if (r && pr && r.ep === g.ep && pr.b === g.b && pr.dx === g.dx && pr.dy === g.dy && pr.pw === g.pw && pr.ac === g.ac) { r.pred = null; return; }
        if (r && !pr && r.ep === g.ep) return;   // duplicate
        startReplay(g);
        return;
      }
      if (m.k === 's' && !isHost) {
        const s = m.s as Snap; if (!s || !Array.isArray(s.p)) return;
        const now = Date.now();
        if (s.q <= cs.lastQ) return; cs.lastQ = s.q;
        if (typeof s.ep === 'number') {
          if (s.kf) cs.kfs.push([s.ep, s.kf[0], s.kf[1]]);
          cs.pend.push(s); if (cs.pend.length > 40) cs.pend.splice(0, cs.pend.length - 40);
        }
        cs.offs.push([now, now - s.ts]); while (cs.offs.length && now - cs.offs[0][0] > 4000) cs.offs.shift();
        if (s.q > (cs.buf.length ? cs.buf[cs.buf.length - 1].q : -1)) cs.buf.push(s);
        else { cs.buf.push(s); cs.buf.sort((a, b) => a.q - b.q); }
        if (cs.buf.length > 60) cs.buf.splice(0, cs.buf.length - 60);
      } else if (m.k === 'shot' && isHost) {
        if (from !== hs.ctrl || eng.phase !== 'aim' || m.n !== hs.seq) return;
        const b = eng.bodies.find(x => x.id === m.b && x.team === eng.turn); if (!b) return;
        // v7: dx/dy arrive as integers on the 1/16 grid (exactly what the shooter predicted with)
        const dx = (Number(m.dx) || 0) / (m.q16 ? 16 : 1), dy = (Number(m.dy) || 0) / (m.q16 ? 16 : 1), l = Math.hypot(dx, dy);
        if (l > 18 && l < 5000) eng.fire(b, dx, dy, l, true);
      } else if (m.k === 'aim') {
        const ctrl = isHost ? hs.ctrl : cs.ctrl; if (from !== ctrl || from === link.me) return;
        if (m.b < 0) { if (eng.drag?.ai && !eng.isAiTurn()) eng.drag = null; return; }
        if (eng.phase !== 'aim') return;
        const b = eng.bodies.find(x => x.id === m.b); if (!b) return;
        eng.drag = { b, sx: b.x, sy: b.y, cx: b.x - (Number(m.dx) || 0), cy: b.y - (Number(m.dy) || 0), ai: true };
      } else if (m.k === 'res' && !isHost) {
        cs.res = { winner: m.winner, rd: m.rd, score: m.score, ok: !!m.ok };
      } else if (m.k === 'abort' && !isHost && done.current !== 'finished') {
        done.current = 'aborted'; toastRef.current('میزبان بازی را لغو کرد', 'err'); exitRef.current('aborted');
      }
    });
  }, []);

  // ---------- main loop ----------
  useEffect(() => {
    sfx('whistle'); playLoop('crowd'); stopLoop('music');
    let raf = 0, last = 0, alive = true; const t0 = Date.now(); let tickAt = -1;
    const loop = (ts: number) => {
      if (!alive) return;
      const dt = last ? Math.min(.1, (ts - last) / 1000) : 1 / 60; last = ts;
      const now = Date.now();
      if (isHost) {
        eng.update(dt);
        let urgent = false;
        if (eng.events.length) {
          for (const ev of eng.events) {
            if (ev.t === 'turn') { hs.turnCount[ev.team]++; hs.seq++; }
            hs.evs.push(encEv(ev));
            if (ev.t !== 'hit' && ev.t !== 'wall' && ev.t !== 'post') urgent = true;
          }
          const evs = eng.events.slice(); eng.events.length = 0;
          // controller must be decided before the snapshot that announces the turn
          hs.ctrl = eng.phase === 'over' ? null : ctrlFor(eng.turn);
          for (const ev of evs) onEvent(ev);
        }
        const c = eng.phase === 'over' ? null : ctrlFor(eng.turn);
        if (c !== hs.ctrl) { hs.ctrl = c; urgent = true; if (c !== link.me && eng.drag && !eng.drag.ai) eng.drag = null; }
        const ai = c === null && eng.phase !== 'over';
        if (eng.aiTeams[eng.turn] !== ai || eng.aiTeams[1 - eng.turn]) { eng.aiTeams = [false, false]; eng.aiTeams[eng.turn] = ai; if (!ai) { eng.aiPlan = null; if (eng.drag?.ai) eng.drag = null; } }
        if (done.current !== 'finished') sendSnap(urgent);
      } else {
        const r = cs.replay;
        try {
        if (r) {
          // ---- lockstep: run the identical physics locally; never ahead of the host's confirmed end tick ----
          eng.stepFollower(dt, r.endTk ?? Infinity);
          if (eng.events.length) { const evs = eng.events.slice(); eng.events.length = 0; for (const ev of evs) if (ev.t === 'hit' || ev.t === 'wall' || ev.t === 'post' || ev.t === 'shot') onEvent(ev); }
          const lg = eng.localGoal;
          if (lg && cs.goalEp !== r.ep) { cs.goalEp = r.ep; onEvent({ t: 'goal', team: lg.team, nogoal: lg.nogoal }); }
          checkKeys();
          while (cs.pend.length && cs.replay) {
            const s = cs.pend[0];
            if (s.ep < r.ep) {
              // the host is still behind my predicted shot; roll back only if it clearly moved on without it
              if (r.pred && s.ph === 'aim' && (s.n !== r.pred.n || now - r.at > 2500)) { applyScalars(s); adopt(s); cs.replay = null; }
              cs.pend.shift(); continue;
            }
            if (s.ep === r.ep) {
              if (s.ph === 'aim' || s.ph === 'over') { r.endTk = s.tk; if (eng.tick >= s.tk || now - r.at > 15000) { applyScalars(s, true); adopt(s); eng.phase = s.ph; cs.replay = null; cs.pend.shift(); continue; } break; }
              if (s.tk <= eng.tick) { applyScalars(s, true); cs.pend.shift(); continue; }
              break;
            }
            if (s.mv === 0) { applyScalars(s); adopt(s); cs.replay = null; cs.pend.shift(); continue; }   // kick-off after a goal
            if (!cs.waitGo) cs.waitGo = now;
            if (now - cs.waitGo > 700) { cs.replay = null; cs.interp = true; cs.pend.length = 0; }        // 'go' lost → interpolate
            break;
          }
        } else if (!cs.interp) {
          // ---- at rest: authoritative state straight from the newest snapshots (no buffering delay for turn changes) ----
          while (cs.pend.length) {
            const s = cs.pend[0];
            if (s.mv === 1 && s.ep > eng.epoch && (s.ph === 'move' || s.ph === 'goal')) {
              if (!cs.waitGo) cs.waitGo = now;
              if (now - cs.waitGo > 700 || !cs.got) { cs.interp = true; cs.pend.length = 0; cs.applied = s.q - 1; }
              break;
            }
            cs.waitGo = 0; applyScalars(s); if (s.ep >= eng.epoch || s.ph === 'aim' || s.ph === 'over') adopt(s); cs.pend.shift();
          }
          eng.stepFollower(dt, eng.tick);
        }
        } catch (err) { cs.replay = null; cs.interp = true; cs.pend.length = 0; }   // never let a netcode edge case freeze the match
        // smooth local clocks between snapshots (the host re-anchors them several times a second)
        if (eng.phase !== 'over') {
          if (cfg.matchTime > 0 && !eng.sudden && eng.mleft > 0) eng.mleft = Math.max(0, eng.mleft - dt);
          if (cfg.turnTime > 0 && eng.phase === 'aim') eng.tleft = Math.max(0, eng.tleft - dt);
        }
        // ---- fallback (spectator joined mid-shot / lost 'go'): classic snapshot interpolation ----
        const off = cs.offs.length ? Math.min(...cs.offs.map(o => o[1])) : 0;
        const buf = cs.buf; const hz = buf.length ? buf[buf.length - 1].hz || 12 : 12;
        const rt = now - off - 1700 / hz;
        if (cs.interp) for (const s of buf) if (s.q > cs.applied && s.ts <= rt) {
          cs.applied = s.q; applyScalars(s);
          if (s.ph === 'aim' || s.ph === 'over' || (s.mv === 0 && s.ep > eng.epoch)) { adopt(s); cs.interp = false; cs.pend = cs.pend.filter(x => x.q > s.q); cs.waitGo = 0; break; }
        }
        if (cs.interp && buf.length) {
          let i = 0; while (i + 1 < buf.length && buf[i + 1].ts <= rt) i++;
          const a = buf[i], b = buf[i + 1] || null;
          const k = b ? Math.max(0, Math.min(1, (rt - a.ts) / Math.max(1, b.ts - a.ts))) : 0;
          if (a.ts <= rt || !cs.got) {
            if (cs.applied < a.q && !cs.got) { cs.applied = a.q; applyScalars(a); }
            const pv = i > 0 ? buf[i - 1] : null;
            // buffer starved while things move → extrapolate from the last two snapshots for up to 120 ms
            if (!b && pv && (a.ph === 'move' || a.ph === 'goal') && rt > a.ts) placeBodies(pv, a, 1 + Math.min(120, rt - a.ts) / Math.max(1, a.ts - pv.ts), dt);
            else placeBodies(a, b, k, dt);
          }
          if (i > 3) buf.splice(0, i - 3);
        }
        if (cs.interp) eng.tickFx(dt);
        if (buf.length > 30) buf.splice(0, buf.length - 30);
        if (done.current === 'no' && now - cs.lastRecv > 8000) {
          done.current = 'aborted'; toastRef.current('ارتباط با میزبان قطع شد', 'err'); exitRef.current('hostLost'); return;
        }
        if (done.current === 'ended') {
          if (cs.res && now - cs.endAt > 900) { done.current = 'finished'; finishRef.current(outcome(cs.res.score, cs.res.rd, cs.res.ok)); }
          else if (!cs.res && now - cs.endAt > 10000) {
            done.current = 'finished';
            supabase.from('matches').select('score_a, score_b, status').eq('id', matchId).maybeSingle().then(({ data }) => {
              const sc: [number, number] = data?.status === 'done' ? [data.score_a ?? eng.score[0], data.score_b ?? eng.score[1]] : [eng.score[0], eng.score[1]];
              finishRef.current(outcome(sc, null, data?.status === 'done'));
            }, () => finishRef.current(outcome([eng.score[0], eng.score[1]], null, false)));
          }
        }
      }
      // the player in control flicks with their own equipped disc's stats
      { const cu = isHost ? hs.ctrl : cs.ctrl; if (cu && cfg.stats) { const pl = playersRef.current.find(x => x.user_id === cu); if (pl) cfg.stats[eng.turn] = discStats(discOf(pl)); } }
      if (!fx && eng.parts.length > 40) eng.parts.length = 40;
      picSet.current(frame(eng, viewRef.current, imRef.current, bgRef.current, cfg.ball, (now - t0) / 1000));
      // HUD (setState only on change)
      const ctrl = isHost ? hs.ctrl : cs.ctrl;
      const m = Math.max(0, Math.ceil(eng.mleft));
      const clock = cfg.matchTime > 0 ? (eng.sudden ? 'گل طلایی' : `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`) : `تا ${fa(cfg.limit)} گل`;
      const tl = cfg.turnTime > 0 && eng.phase === 'aim' ? Math.max(0, eng.tleft / cfg.turnTime) : 1;
      const wait = !isHost && !cs.got;
      if (ctrl === link.me && eng.phase === 'aim' && cfg.turnTime > 0 && eng.tleft < 5 && eng.tleft > 0 && co.current.reminded !== co.current.turnN) { co.current.reminded = co.current.turnN; oracleRef.current.coach('نوبت توئه و ۵ ثانیه مونده! ⏱', 'alert'); }
      if (ctrl === link.me && eng.phase === 'aim' && cfg.turnTime > 0) { const sec = Math.ceil(eng.tleft); if (sec <= 3 && sec > 0 && sec !== tickAt) { tickAt = sec; sfx('tick'); } } else tickAt = -1;
      setHud(h => (h.s0 !== eng.score[0] || h.s1 !== eng.score[1] || h.turn !== eng.turn || h.clock !== clock || Math.abs(h.tl - tl) > .02 || h.sudden !== eng.sudden || h.ctrl !== ctrl || h.phase !== eng.phase || h.wait !== wait)
        ? { s0: eng.score[0], s1: eng.score[1], turn: eng.turn, clock, tl, sudden: eng.sudden, ctrl, phase: eng.phase, wait } : h);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => {
      alive = false; cancelAnimationFrame(raf); stopLoop('crowd');
      if (isHost && done.current === 'no') { link.sendGame({ k: 'abort' }); rpc('abandon_match', { p_match: matchId }).catch(() => {}); }
    };
  }, []);

  // my turn → haptic + chime
  const myTurn = hud.ctrl === link.me && hud.phase === 'aim' && start.myTeam !== null;
  useEffect(() => { if (myTurn) { buzz('medium'); sfx('ready'); } }, [myTurn, hud.turn]);

  // ---------- input ----------
  const local = useRef<{ b: Body; sx: number; sy: number } | null>(null);
  const canAct = () => {
    if (start.myTeam === null || done.current !== 'no') return false;
    if (isHost) return eng.phase === 'aim' && hs.ctrl === link.me && !eng.isAiTurn();
    return eng.phase === 'aim' && cs.ctrl === link.me && Date.now() - cs.pendingShot > 1500;
  };
  const world = (e: any) => { const x = e.nativeEvent.locationX, y = e.nativeEvent.locationY; return flipped ? toWorld(viewRef.current, W - x, H - y) : toWorld(viewRef.current, x, y); };
  const sendAim = (force = false) => {
    const d = eng.drag; if (!d || d.ai) return; const now = Date.now();
    if (!force && now - hs.lastAim < 120) return; hs.lastAim = now;
    link.sendGame({ k: 'aim', b: d.b.id, dx: Math.round(d.sx - d.cx), dy: Math.round(d.sy - d.cy) });
  };
  const touch = {
    onStartShouldSetResponder: () => true,
    onMoveShouldSetResponder: () => true,
    onResponderGrant: (e: any) => {
      if (!canAct()) return; const p = world(e);
      if (isHost) { if (eng.pick(p.x, p.y)) { buzz('light'); local.current = eng.drag ? { b: eng.drag.b, sx: eng.drag.sx, sy: eng.drag.sy } : null; } return; }
      let best: Body | null = null, bd = 1e9;
      for (const b of eng.bodies) if (b.team === start.myTeam && b.team === eng.turn) { const d = Math.hypot(p.x - b.x, p.y - b.y); if (d < b.r + 34 && d < bd) { best = b; bd = d; } }
      if (!best) return; buzz('light');
      local.current = { b: best, sx: best.x, sy: best.y }; eng.drag = { b: best, sx: best.x, sy: best.y, cx: p.x, cy: p.y };
    },
    onResponderMove: (e: any) => { if (!local.current || !eng.drag || eng.drag.ai) return; const p = world(e); eng.move(p.x, p.y); sendAim(); },
    onResponderRelease: () => {
      const l0 = local.current; local.current = null; if (!l0) return;
      const d = eng.drag;
      if (isHost) { eng.release(); link.sendGame({ k: 'aim', b: -1 }); return; }
      eng.drag = null; link.sendGame({ k: 'aim', b: -1 });
      if (!d || d.ai) return;
      const dx = d.sx - d.cx, dy = d.sy - d.cy, l = Math.hypot(dx, dy);
      if (l > 18 && canAct()) {
        co.current.power = Math.min(l, LMAX) / LMAX; cs.pendingShot = Date.now();
        const qx = Math.round(dx * 16), qy = Math.round(dy * 16);
        link.sendGame({ k: 'shot', b: l0.b.id, dx: qx, dy: qy, q16: 1, n: cs.seq });
        // client-side prediction: fire locally right now with the exact same quantised input the host will use
        const b = eng.bodies.find(x => x.id === l0.b.id);
        if (b && !cs.interp) {
          const st = cfg.stats?.[b.team as 0 | 1] || { power: 5, accuracy: 5 };
          eng.fire(b, qx / 16, qy / 16, Math.hypot(qx / 16, qy / 16), true);
          cs.replay = { ep: eng.epoch, endTk: null, pred: { n: cs.seq, b: b.id, dx: qx, dy: qy, pw: st.power, ac: st.accuracy }, at: Date.now() }; cs.kfs = []; cs.waitGo = 0;
        }
      }
    },
    onResponderTerminate: () => { local.current = null; if (eng.drag && !eng.drag.ai) eng.drag = null; link.sendGame({ k: 'aim', b: -1 }); },
  };

  const doQuit = () => {
    setQuit(false);
    if (isHost) { done.current = 'aborted'; link.sendGame({ k: 'abort' }); rpc('abandon_match', { p_match: matchId }).catch(() => {}); link.ping(); }
    else done.current = 'aborted';
    stopLoop('crowd'); onExit('quit');
  };

  const bScale = banner.interpolate({ inputRange: [0, 1, 2], outputRange: [.3, 1, 1.25] });
  const bOp = banner.interpolate({ inputRange: [0, .2, 1, 2], outputRange: [0, 1, 1, 0] });
  const viewers = ls.players.filter(p => p.role === 'spectator' && ls.online[p.user_id]).length;
  const turnName = hud.ctrl === link.me ? 'نوبت توئه!' : `نوبت: ${nameOf(hud.ctrl)}`;
  const tc = hud.turn === 0 ? C.cyan : C.red;

  return (
    <View style={{ flex: 1, backgroundColor: '#02040c' }}>
      <View style={StyleSheet.absoluteFill} {...touch}>
        <View style={[StyleSheet.absoluteFill, flipped && { transform: [{ rotate: '180deg' }] }]} pointerEvents="none">
          <Stage w={W} h={H} bind={fn => (picSet.current = fn)} />
        </View>
      </View>

      {/* score board */}
      <View style={[s.hud, { top: ins.top + S.s }]} pointerEvents="box-none">
        <Press onPress={() => setQuit(true)} style={s.iconBtn}><T s="✕" style={{ fontSize: 16, color: C.text }} /></Press>
        <Panel style={s.board} accent={tc}>
          <Side team={start.teams[flipped ? 1 : 0]} name={start.names[flipped ? 1 : 0]} on={hud.turn === (flipped ? 1 : 0)} color={flipped ? C.red : C.cyan} />
          <View style={{ alignItems: 'center', paddingHorizontal: 6 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              <T s={flipped ? hud.s1 : hud.s0} style={s.score} /><T s=":" style={[s.score, { color: C.dim, marginHorizontal: 6 }]} /><T s={flipped ? hud.s0 : hud.s1} style={s.score} />
            </View>
            <T s={hud.clock} style={{ fontFamily: F.head, fontSize: 9, letterSpacing: 1, color: hud.sudden ? C.gold : C.dim }} />
          </View>
          <Side team={start.teams[flipped ? 0 : 1]} name={start.names[flipped ? 0 : 1]} on={hud.turn === (flipped ? 0 : 1)} color={flipped ? C.cyan : C.red} right />
        </Panel>
      </View>
      {/* whose turn + timer */}
      <View style={[s.turnRow, { top: ins.top + 72 }]} pointerEvents="none">
        <View style={[s.turnPill, { borderColor: tc + 'aa', backgroundColor: myTurn ? tc + '33' : 'rgba(6,10,30,.85)' }]}>
          <T s={hud.phase === 'aim' ? turnName : hud.phase === 'goal' ? 'گل!' : hud.phase === 'over' ? 'پایان بازی' : 'در حال حرکت…'} n={1} style={{ fontFamily: F.bold, fontSize: 12, color: myTurn ? '#fff' : C.text }} />
        </View>
        {start.myTeam === null ? <Badge label={`زنده · ${fa(viewers)} تماشاگر`} color={C.red} live /> : null}
        {!isHost ? <View style={{ marginLeft: S.s }}><PingBadge link={link} /></View> : null}
      </View>
      {cfg.turnTime > 0 ? (
        <View style={[s.turnBar, { top: ins.top + 66 }]} pointerEvents="none">
          <LinearGradient colors={hud.turn === 0 ? [C.cyan, C.blue] : [C.red, C.orange]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 0 }} style={{ width: `${hud.tl * 100}%`, height: '100%', borderRadius: 3 }} />
        </View>
      ) : null}

      <Animated.View pointerEvents="none" style={[s.banner, { opacity: bOp, transform: [{ scale: bScale }] }]}>
        <T s={bText.t} style={{ fontFamily: F.title, fontSize: 54, color: '#fff', textShadowColor: bText.c, textShadowRadius: 24 }} />
        {bText.s ? <T s={bText.s} n={1} style={{ fontFamily: F.head, fontSize: 13, color: bText.c, marginTop: 4 }} /> : null}
      </Animated.View>

      {hud.wait ? (
        <View style={s.overlay} pointerEvents="none"><T s="در حال اتصال به میزبان…" style={{ fontFamily: F.bold, fontSize: 15 }} /></View>
      ) : null}

      {/* bottom controls: chat + voice */}
      <View style={[s.bottom, { paddingBottom: Math.max(ins.bottom, S.s) }]} pointerEvents="box-none">
        <Press onPress={() => setChat(c => !c)} style={[s.iconBtn, chat && { borderColor: C.cyan }]}>
          <Img src={UI2.c_mega} style={{ width: 24, height: 24 }} />
          {ls.unread && !chat ? <View style={s.dot}><T s={fa(Math.min(9, ls.unread))} style={{ fontSize: 9, fontFamily: F.bold, color: '#fff' }} /></View> : null}
        </Press>
        {room0.voice ? <VoiceBar link={link} compact /> : null}
      </View>
      {chat ? (
        <View style={[s.chat, { bottom: Math.max(ins.bottom, S.s) + 56 }]}>
          <ChatPanel link={link} compact height={220} />
        </View>
      ) : null}

      {quit ? (
        <View style={s.overlay}>
          <Panel style={{ padding: 20, width: '86%', maxWidth: 380 }} glow>
            <T s="خروج از بازی؟" style={{ fontFamily: F.title, fontSize: 20, textAlign: 'center' }} />
            <T s={isHost ? 'تو میزبانی؛ با خروج تو بازی برای همه لغو می‌شود.' : start.myTeam === null ? 'تماشای بازی را ترک می‌کنی.' : 'بازی بدون تو ادامه پیدا می‌کند و ربات جای تو بازی می‌کند.'}
              style={{ fontSize: 13, color: C.dim, textAlign: 'center', marginTop: S.s, marginBottom: S.l }} />
            <Btn label="ادامه‌ی بازی" onPress={() => setQuit(false)} />
            <View style={{ height: S.m }} />
            <Btn label="خروج" colors={G.red} small onPress={doQuit} />
          </Panel>
        </View>
      ) : null}
    </View>
  );
}

const Stage = React.memo(function Stage({ w, h, bind }: { w: number; h: number; bind: (f: (p: SkPicture) => void) => void }) {
  const pic = useSharedValue<SkPicture>(EMPTY());
  useEffect(() => { bind((p: SkPicture) => { pic.value = p; }); }, []);
  return <Canvas style={{ width: w, height: h }} pointerEvents="none"><Picture picture={pic as SharedValue<SkPicture>} /></Canvas>;
});
let _empty: SkPicture | null = null;
const EMPTY = () => _empty || (_empty = createPicture(() => {}));

function Side({ team, name, on, color, right }: { team: Team; name: string; on: boolean; color: string; right?: boolean }) {
  return (
    <View style={{ flex: 1, flexDirection: right ? 'row-reverse' : 'row', alignItems: 'center' }}>
      <View style={[s.logo, { borderColor: on ? color : 'rgba(255,255,255,.15)', shadowColor: color, shadowOpacity: on ? .9 : 0, shadowRadius: 10 }]}>
        <Img src={TEAM_IMG[teamKey(team)]} style={{ width: 32, height: 32, borderRadius: 16 }} />
      </View>
      <View style={{ flex: 1, alignItems: right ? 'flex-end' : 'flex-start', marginHorizontal: 6 }}>
        <T s={name} n={1} style={{ fontFamily: F.bold, fontSize: 12, color: on ? '#fff' : C.dim }} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  hud: { position: 'absolute', left: S.s, right: S.s, flexDirection: 'row', alignItems: 'center' },
  iconBtn: { width: 44, height: 44, borderRadius: 14, backgroundColor: 'rgba(8,12,34,.88)', borderWidth: 1, borderColor: C.line, alignItems: 'center', justifyContent: 'center', marginRight: S.s },
  board: { flex: 1, height: 56, flexDirection: 'row', alignItems: 'center', paddingHorizontal: S.s },
  score: { fontFamily: F.title, fontSize: 24, color: '#fff' },
  logo: { width: 38, height: 38, borderRadius: 19, borderWidth: 2, alignItems: 'center', justifyContent: 'center', backgroundColor: '#050816' },
  turnBar: { position: 'absolute', left: 60, right: S.m, height: 4, borderRadius: 3, backgroundColor: 'rgba(255,255,255,.08)', overflow: 'hidden' },
  turnRow: { position: 'absolute', left: 0, right: 0, flexDirection: 'row', justifyContent: 'center', alignItems: 'center' },
  turnPill: { height: 28, paddingHorizontal: S.m, borderRadius: 14, borderWidth: 1, justifyContent: 'center', maxWidth: '70%' },
  banner: { position: 'absolute', left: 0, right: 0, top: '38%', alignItems: 'center' },
  overlay: { position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, backgroundColor: 'rgba(2,4,14,.72)', alignItems: 'center', justifyContent: 'center', zIndex: 30 },
  bottom: { position: 'absolute', left: S.m, right: S.m, bottom: 0, flexDirection: 'row', alignItems: 'center' },
  dot: { position: 'absolute', top: -4, right: -4, minWidth: 18, height: 18, borderRadius: 9, backgroundColor: C.red, alignItems: 'center', justifyContent: 'center' },
  chat: { position: 'absolute', left: S.m, right: S.m, height: 280, borderRadius: 18, overflow: 'hidden', backgroundColor: 'rgba(6,10,30,.94)', borderWidth: 1, borderColor: C.line, zIndex: 25 },
});
