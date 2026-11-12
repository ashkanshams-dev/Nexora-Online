// NEXORA physics engine — TypeScript rewrite of the original game.js simulation.
// Fixed 240 Hz sub-stepping, impulse-based circle collisions with positional correction,
// rolling 3D ball rotation, render interpolation (prev -> current) for buttery motion.
import { FIELDS, GS, slots, Field } from './data';

export const K = 1.27;
export const PR = 49;      // piece radius (world units) — enlarged for touch + readability
export const BR = 25.5;    // ball radius
export const RC = 70;      // rounded corner radius
export const LMAX = 210;   // max drag length (world units) for full power
export const STEP = 1 / 240;
export const POST_R = 8;   // goal-post radius (world units): solid round collider, matches the drawn post
const HV = 8, PF1 = 430, PF2 = 1.0, PV0 = 520, EPP = .62, PCAP = 190;
// ---- motion feel (v6 retune) ----
// Ball: smooth exponential damping (BK, 1/s) + a gentle rolling resistance (BF) that fades in only at low speed,
// a hard speed cap, and a stop threshold so it settles in ~1.2–1.8 s instead of wandering/ping-ponging.
const BK = 1.9, BF = 175, BFV = 140, BVMAX = 1750, BSTOP = 26;
// Discs: "floating" glide — exponential ease-out (PK) with a soft extra brake that blends in at low speed (PFL/PFV), gentle stop.
const PK = 1.55, PFL = 300, PFV = 230, PSTOP = 20;
// Wall / post energy caps (outgoing normal speed after a bounce, world units/s before K)
const WALL_VOUT = 820, POST_VOUT = 900;

export type Body = {
  id: number; team: 0 | 1 | 2; x: number; y: number; px: number; py: number;
  vx: number; vy: number; r: number; im: number;
  spin: number; ang: number; R: Float64Array; sq: number;
  tvx: number; tvy: number; ramp: number; boost: number;
  vox: number; voy: number; gout: Goal | null; tr: { x: number; y: number }[];
};
export type Goal = { team: 0 | 1; y: number; x1: number; x2: number; d: -1 | 1 };
export type Particle = { x: number; y: number; vx: number; vy: number; l: number; m: number; r: number; c: string; k: number; g: number };
export type Phase = 'aim' | 'move' | 'goal' | 'over';
export type EngineEvent =
  | { t: 'hit'; ball: boolean; power: number }
  | { t: 'wall'; power: number }
  | { t: 'post'; power: number }
  | { t: 'goal'; team: 0 | 1; nogoal: boolean }
  | { t: 'turn'; team: 0 | 1 }
  | { t: 'shot'; team: 0 | 1 }
  | { t: 'end'; score: [number, number] }
  | { t: 'clock' };

export type MatchCfg = {
  field: number; ball: number; forms: [number, number]; ai: boolean; aiLvl: 0 | 1 | 2;
  limit: number; matchTime: number; turnTime: number; vip: [boolean, boolean]; first: 0 | 1;
  // disc stats (1–10) per team: power scales shot impulse, accuracy controls aim deviation + preview length
  stats?: [DiscStats, DiscStats];
};
export type DiscStats = { power: number; accuracy: number };
export const powerMul = (p: number) => .75 + (Math.min(10, Math.max(1, p)) - 1) / 9 * .5;     // 1 → 0.75x … 10 → 1.25x
export const aimDevDeg = (a: number) => (10 - Math.min(10, Math.max(1, a))) / 9 * 4;          // 10 → 0° … 1 → ±4°
export const aimPreview = (a: number) => .45 + (Math.min(10, Math.max(1, a)) - 1) / 9 * .75;   // 1 → short … 10 → long

const hyp = Math.hypot;
const clamp = (v: number, a: number, b: number) => (v < a ? a : v > b ? b : v);

function rotate(R: Float64Array, wx: number, wy: number, wz: number, dt: number) {
  const w = hyp(wx, wy, wz), th = w * dt; if (th < 1e-7) return;
  const ax = wx / w, ay = wy / w, az = wz / w, c = Math.cos(th), s = Math.sin(th), t = 1 - c;
  const m0 = t * ax * ax + c, m1 = t * ax * ay - s * az, m2 = t * ax * az + s * ay;
  const m3 = t * ax * ay + s * az, m4 = t * ay * ay + c, m5 = t * ay * az - s * ax;
  const m6 = t * ax * az - s * ay, m7 = t * ay * az + s * ax, m8 = t * az * az + c;
  const r = R.slice();
  R[0] = m0 * r[0] + m1 * r[3] + m2 * r[6]; R[1] = m0 * r[1] + m1 * r[4] + m2 * r[7]; R[2] = m0 * r[2] + m1 * r[5] + m2 * r[8];
  R[3] = m3 * r[0] + m4 * r[3] + m5 * r[6]; R[4] = m3 * r[1] + m4 * r[4] + m5 * r[7]; R[5] = m3 * r[2] + m4 * r[5] + m5 * r[8];
  R[6] = m6 * r[0] + m7 * r[3] + m8 * r[6]; R[7] = m6 * r[1] + m7 * r[4] + m8 * r[7]; R[8] = m6 * r[2] + m7 * r[5] + m8 * r[8];
  // re-orthonormalise occasionally to stop drift
  const l0 = hyp(R[0], R[1], R[2]); R[0] /= l0; R[1] /= l0; R[2] /= l0;
}

export class Engine {
  f: Field; F = { l: 0, r: 0, t: 0, b: 0 }; CX = 0; CY = 0; KY = 0;
  goals: Goal[] = []; GG = { w: 0, h: 0, x: 0 }; DEPTH = 120;
  bodies: Body[] = []; ball!: Body; parts: Particle[] = []; trail: { x: number; y: number; a: number }[] = [];
  score: [number, number] = [0, 0]; turn: 0 | 1 = 0; phase: Phase = 'aim';
  shots = 0; idle = 0; pause = 0; kick: 0 | 1 = 0; acc = 0; slow = 0; flash = 0; cam = 0; shake: [number, number] = [0, 0]; ripple: [number, number] = [0, 0]; rippleX: [number, number] = [0, 0];
  mleft = 0; tleft = 0; sudden = false; aiT = 0; aiPlan: null | { b: Body; dx: number; dy: number; l: number; t: number } = null;
  drag: null | { b: Body; sx: number; sy: number; cx: number; cy: number; ai?: boolean } = null;
  events: EngineEvent[] = []; cfg: MatchCfg; time = 0; lastWho: 0 | 1 = 0;
  // online: per-team AI takeover (a team with no connected human is played by the bot)
  aiTeams: [boolean, boolean] = [false, false];

  constructor(cfg: MatchCfg) {
    this.cfg = cfg; this.f = FIELDS[cfg.field] || FIELDS[0];
    const f = this.f;
    this.F = { l: f.L + 4, r: f.R - 4, t: f.T + 4, b: f.B - 4 };
    this.CX = (this.F.l + this.F.r) / 2; this.CY = (this.F.t + this.F.b) / 2; this.KY = f.cs;
    const gi = GS[f.gs], gw = 2 * f.g / (gi[3] - gi[2]);
    this.GG = { w: gw, h: gw * gi[1] / gi[0] * 1.28, x: this.CX - f.g - gi[2] * gw };
    this.DEPTH = Math.max(120, Math.round(this.GG.h * .98));
    this.goals = [{ team: 0, y: this.F.t, x1: this.CX - f.g, x2: this.CX + f.g, d: -1 }, { team: 1, y: this.F.b, x1: this.CX - f.g, x2: this.CX + f.g, d: 1 }];
    this.mleft = cfg.matchTime; this.tleft = cfg.turnTime;
    this.reset(cfg.first);
  }

  private mk(x: number, y: number, team: 0 | 1 | 2, r: number, m: number, id: number): Body {
    return { id, team, x, y, px: x, py: y, vx: 0, vy: 0, r, im: 1 / m, spin: 0, ang: 0, R: new Float64Array([1, 0, 0, 0, 1, 0, 0, 0, 1]), sq: 0, tvx: 0, tvy: 0, ramp: 0, boost: 0, vox: 0, voy: 0, gout: null, tr: [] };
  }

  reset(kickTeam: 0 | 1) {
    const { F } = this, Fw = F.r - F.l, Fh = F.b - F.t;
    this.bodies = []; this.trail = []; this.parts = []; this.slow = 0; this.cam = 0;
    for (let cm = 0 as 0 | 1; cm < 2; cm = (cm + 1) as 0 | 1) {
      slots(this.cfg.forms[cm]).forEach(([nx, ny], i) => {
        const x = F.l + PR + 10 + nx * (Fw - 2 * (PR + 10)), y = cm ? F.t + ny * Fh : F.b - ny * Fh;
        this.bodies.push(this.mk(x, y, cm, PR, 5, cm * 20 + i));
      });
    }
    this.ball = this.mk(this.CX, this.KY, 2, BR, 1.5, 99); this.bodies.push(this.ball);
    this.turn = kickTeam; this.phase = 'aim'; this.drag = null; this.pause = 0; this.idle = 0; this.shots = 0;
    this.tleft = this.cfg.turnTime; this.aiT = 0; this.aiPlan = null;
    this.events.push({ t: 'turn', team: this.turn });
  }

  isAiTurn() { return (this.cfg.ai && this.turn === 1) || this.aiTeams[this.turn]; }
  canControl() { return this.phase === 'aim' && !this.isAiTurn(); }

  // ---------- input ----------
  pick(x: number, y: number) {
    if (!this.canControl()) return false;
    let f: Body | null = null, bd = 1e9;
    for (const b of this.bodies) if (b.team === this.turn && b !== this.ball) { const d = hyp(x - b.x, y - b.y); if (d < b.r + 34 && d < bd) { f = b; bd = d; } }
    if (!f) return false;
    this.drag = { b: f, sx: f.x, sy: f.y, cx: x, cy: y }; return true;
  }
  move(x: number, y: number) { if (this.drag && !this.drag.ai) { this.drag.cx = x; this.drag.cy = y; } }
  release() {
    const d = this.drag; if (!d || d.ai) return; this.drag = null;
    const dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy);
    if (l > 18 && this.phase === 'aim') this.fire(d.b, dx, dy, l, true);
  }
  cancel() { if (this.drag && !this.drag.ai) this.drag = null; }
  aimInfo() {
    const d = this.drag; if (!d) return null;
    const dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy); if (l < 18) return { b: d.b, p: 0, ux: 0, uy: 0 };
    return { b: d.b, p: Math.min(l, LMAX) / LMAX, ux: dx / l, uy: dy / l };
  }

  lastPower = 0;
  statsOf(team: 0 | 1): DiscStats { return this.cfg.stats?.[team] || { power: 5, accuracy: 5 }; }

  // human = a player's flick: disc accuracy adds a small random deviation (the bot has its own error model)
  fire(b: Body, dx: number, dy: number, l: number, human = false) {
    const p = Math.min(l, LMAX) / LMAX, team = b.team as 0 | 1;
    this.lastPower = p;
    let v = (260 + 1085 * Math.pow(p, .8)) * K * 1.32;
    if (this.cfg.stats) v *= powerMul(this.statsOf(team).power);
    else if (this.cfg.vip[team]) v *= 1.16;
    let ux = dx / l, uy = dy / l;
    if (human && this.cfg.stats) {
      const dev = aimDevDeg(this.statsOf(team).accuracy) * Math.PI / 180;
      if (dev > 0) { const a = Math.atan2(uy, ux) + (Math.random() + Math.random() - 1) * dev; ux = Math.cos(a); uy = Math.sin(a); }
    }
    const vx = ux * v, vy = uy * v;
    b.tvx = vx * 1.02; b.tvy = vy * 1.02; b.ramp = .06; b.vx = vx * .5; b.vy = vy * .5; b.boost = .22;
    this.phase = 'move'; this.idle = 0; this.shots++; this.drag = null; this.cam = Math.max(this.cam, .18);
    this.lastWho = b.team as 0 | 1;
    this.events.push({ t: 'shot', team: b.team as 0 | 1 });
  }

  // ---------- simulation ----------
  private walls(b: Body) {
    const { F, ball } = this;
    if (b !== ball && b.gout) { const g = b.gout, dq = g.d * (b.y - g.y); if (dq > -b.r * 1.05) { b.vy = -g.d * 270 * K; b.vx *= .6; } else { b.vy = 0; b.vx *= .2; b.gout = null; } }
    const bl = b === ball, r = b.r, vs = hyp(b.vx, b.vy);
    const eN = (vn: number) => bl ? Math.min(.64 - .24 * clamp((vn - 270 * K) / (730 * K), 0, 1), WALL_VOUT * K / Math.max(1, vn)) : Math.min(.72, WALL_VOUT * 1.4 * K / Math.max(1, vn));
    if (b.x - r < F.l) { b.x = F.l + r; if (b.vx < 0) { if (bl && vs > 200) this.events.push({ t: 'wall', power: vs / 1800 }); b.vx *= -eN(-b.vx); b.spin += b.vy / r * .05; } }
    if (b.x + r > F.r) { b.x = F.r - r; if (b.vx > 0) { if (bl && vs > 200) this.events.push({ t: 'wall', power: vs / 1800 }); b.vx *= -eN(b.vx); b.spin -= b.vy / r * .05; } }
    for (const g of this.goals) {
      const dp = g.d * (b.y - g.y); if (dp <= -r) continue;
      const lo = g.x1 + (bl ? 0 : r), hi = g.x2 - (bl ? 0 : r);
      const inside = bl ? (b.x > g.x1 && b.x < g.x2) : (dp > 0 || (b.x >= lo && b.x <= hi));
      if (inside) {
        const gl = this.phase === 'goal' && bl, eb = gl ? .2 : eN(Math.abs(b.vy)), back = g.y + g.d * this.DEPTH;
        if (!bl && dp > r * .3 && vs < 150 * K && !b.gout) b.gout = g;
        if (dp + r > this.DEPTH) { b.y = back - g.d * r; b.vy = -g.d * Math.abs(b.vy) * eb; if (gl) b.vx *= .6; }
        if (dp > (bl ? r * .6 : 0)) {
          const ee = gl ? .3 : eN(Math.abs(b.vx));
          if (b.x < g.x1 + r) { b.x = g.x1 + r; if (b.vx < 0) b.vx *= -ee; }
          if (b.x > g.x2 - r) { b.x = g.x2 - r; if (b.vx > 0) b.vx *= -ee; }
        }
      } else {
        if (bl && vs > 200 && g.d * b.vy > 0) this.events.push({ t: 'wall', power: vs / 1800 });
        b.y = g.y - g.d * r; if (g.d * b.vy > 0) b.vy = -g.d * Math.abs(b.vy) * eN(Math.abs(b.vy)); b.spin += g.d * b.vx / r * .05;
      }
    }
    const corners: [number, number, number, number][] = [[F.l + RC, F.t + RC, 1, 1], [F.r - RC, F.t + RC, -1, 1], [F.l + RC, F.b - RC, 1, -1], [F.r - RC, F.b - RC, -1, -1]];
    for (const [cx, cy, sx, sy] of corners) {
      if ((b.x - cx) * sx < 0 && (b.y - cy) * sy < 0) {
        const dx = b.x - cx, dy = b.y - cy, d = hyp(dx, dy), lim = RC - r;
        if (d > lim && d > 0) { const nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny; b.x = cx + nx * lim; b.y = cy + ny * lim; if (vn > 0) { const ec = eN(vn); b.vx -= (1 + ec) * vn * nx; b.vy -= (1 + ec) * vn * ny; } }
      }
    }
  }

  private post(b: Body, px: number, py: number) {
    const dx = b.x - px, dy = b.y - py, d = hyp(dx, dy), m = b.r + POST_R; if (d >= m || !d) return;
    const nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny; b.x = px + nx * m; b.y = py + ny * m;
    if (vn < 0) { const kp = 1 + Math.min(.62 - .14 * Math.min(1, -vn / (2000 * K)), POST_VOUT * K / Math.max(1, -vn)); b.vx -= kp * vn * nx; b.vy -= kp * vn * ny; if (b === this.ball) this.events.push({ t: 'post', power: -vn / 1800 }); if (b === this.ball && -vn > 900 * K) this.cam = Math.max(this.cam, .25); }
  }

  private hit(a: Body, b: Body) {
    let dx = b.x - a.x, dy = b.y - a.y, d = hyp(dx, dy); const m = a.r + b.r; if (d >= m) return; if (d < 1e-4) { dx = 1; dy = 0; d = 1; }
    const ball = this.ball, nx = dx / d, ny = dy / d, sm = a.im + b.im, isB = a === ball || b === ball;
    let ka = isB && a !== ball ? 1 / HV : 1, kb = isB && b !== ball ? 1 / HV : 1;
    if (!isB) { const sa = hyp(a.vx, a.vy), sb = hyp(b.vx, b.vy); if (sa > sb) kb = .85; else ka = .85; }
    let wa = a.im / sm * ka, wb = b.im / sm * kb; if (isB) { if (a === ball) wa = 1 - wb; else wb = 1 - wa; }
    const pen = Math.max(m - d - .3, 0) * .9;
    a.x -= nx * pen * wa; a.y -= ny * pen * wa; b.x += nx * pen * wb; b.y += ny * pen * wb;
    a.vox = clamp(a.vox + nx * pen * wa, -9, 9); a.voy = clamp(a.voy + ny * pen * wa, -9, 9);
    b.vox = clamp(b.vox - nx * pen * wb, -9, 9); b.voy = clamp(b.voy - ny * pen * wb, -9, 9);
    const vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny; if (vn >= 0) return;
    const e = vn < -40 * K ? (isB ? .68 - .12 * clamp((-vn - 500 * K) / (1200 * K), 0, 1) : EPP) : 0;
    const j = -(1 + e) * vn / sm, pa = isB ? (a === ball ? b : a) : null, pre = pa ? hyp(pa.vx, pa.vy) : 0;
    a.vx -= j * nx * a.im * ka; a.vy -= j * ny * a.im * ka; b.vx += j * nx * b.im * kb; b.vy += j * ny * b.im * kb;
    if (pa && pre < 260 * K) { const ps = hyp(pa.vx, pa.vy), cp = PCAP * K; if (ps > cp) { pa.vx *= cp / ps; pa.vy *= cp / ps; } }
    if (vn < -120 * K) {
      this.events.push({ t: 'hit', ball: isB, power: -vn / 1900 });
      if (!isB && vn < -420 * K) { const q = Math.min(1, -vn / (1500 * K)); a.sq = Math.max(a.sq, q); b.sq = Math.max(b.sq, q); }
    }
    if (isB) {
      ball.spin += (ball === b ? 1 : -1) * (-ny * (b.vx - a.vx) + nx * (b.vy - a.vy)) / ball.r * .3; ball.spin = clamp(ball.spin, -34, 34);
      const pw = Math.min(1, -vn / (1700 * K));
      if (pw > .2) { const o = ball === b ? a : b; ball.sq = Math.max(ball.sq, pw); o.sq = Math.max(o.sq, pw * .7); this.cam = Math.max(this.cam, pw * .4);
        const cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2; this.burst(cx, cy, Math.round(6 + pw * 10), 260 + pw * 300, ['#ffffff', '#9fe8ff', '#5cb6ff'], .35, 2); }
    }
  }

  private sim(dt: number) {
    const ball = this.ball;
    for (const b of this.bodies) {
      if (b.ramp > 0) { const k = Math.min(1, dt / b.ramp); b.vx += (b.tvx - b.vx) * k; b.vy += (b.tvy - b.vy) * k; b.ramp -= dt; if (b.ramp <= 0) b.ramp = 0; }
      if (b.vox || b.voy) { const q = 1 - Math.min(1, dt * 15); b.vox *= q; b.voy *= q; if (Math.abs(b.vox) < .04) b.vox = 0; if (Math.abs(b.voy) < .04) b.voy = 0; }
      b.x += b.vx * dt; b.y += b.vy * dt;
      const sp = hyp(b.vx, b.vy), bl = b === ball;
      if (sp > 0) {
        if (bl) {
          // exponential damping (frame-rate independent) + low-speed rolling resistance; straight roll, no side drift
          let ns = sp * Math.exp(-BK * dt) - BF * K * Math.min(1, sp / (BFV * K)) * dt;
          if (ns < BSTOP * K) { b.vx = b.vy = 0; b.vox = b.voy = 0; } else { ns = Math.min(ns, BVMAX * K); const k = ns / sp; b.vx *= k; b.vy *= k; }
        } else {
          const fb = b.boost > 0 ? .35 : 1; if (b.boost > 0) b.boost -= dt;
          let ns = sp * Math.exp(-PK * fb * dt) - PFL * K * Math.min(1, sp / (PFV * K)) * fb * dt;
          if (ns < PSTOP * K && b.ramp <= 0) { b.vx = b.vy = 0; } else { ns = Math.max(0, Math.min(ns, 2800 * K)); const k = ns / sp; b.vx *= k; b.vy *= k; }
        }
      }
      if (bl) {
        const sp2 = hyp(b.vx, b.vy); b.spin *= 1 - (sp2 > 0 ? 1.05 : 3.2) * dt; if (Math.abs(b.spin) < .02) b.spin = 0;
        const roll = .95 / b.r; if (sp2 > 0 || b.spin) rotate(b.R, -b.vy * roll, b.vx * roll, b.spin * .55, dt); b.ang += b.spin * dt;
      } else { b.spin *= 1 - 2.6 * dt; b.ang += b.spin * dt; }
      b.sq *= 1 - 9 * dt;
      this.walls(b);
    }
    const B = this.bodies;
    for (let it = 0; it < 2; it++) for (let a = 0; a < B.length; a++) for (let c = a + 1; c < B.length; c++) this.hit(B[a], B[c]);
    for (const g of this.goals) for (const b of B) { this.post(b, g.x1, g.y); this.post(b, g.x2, g.y); }
    for (const b of B) this.walls(b);
    if (this.phase === 'move') for (const g of this.goals)
      if (ball.x > g.x1 && ball.x < g.x2 && (g.d < 0 ? ball.y < g.y - ball.r * .8 : ball.y > g.y + ball.r * .8)) this.scored(g.team);
  }

  private scored(t: 0 | 1) {
    const nogoal = this.shots <= 1;
    this.events.push({ t: 'goal', team: t, nogoal });
    if (nogoal) { this.phase = 'goal'; this.pause = 1.4; this.kick = this.turn; return; }
    this.ripple[t] = 1; this.rippleX[t] = this.ball.x; this.score[t]++; this.pause = 2.0; this.flash = 1; this.shake[t] = .6; this.phase = 'goal'; this.kick = (1 - t) as 0 | 1;
    this.slow = 1.1; this.cam = 1.4;
    const g = this.goals[t], c = ['#ffd23a', '#ffffff', '#3bd0ff', '#ff4a7a', '#7bff5a'];
    this.burst(this.ball.x, g.y, 80, 760, c, 1.4, 1); this.burst(this.ball.x, g.y, 50, 520, c, 1.8, 3);
  }

  burst(x: number, y: number, n: number, sp: number, cols: string[], life: number, k = 0) {
    if (this.parts.length > 420) return;
    for (let i = 0; i < n; i++) { const a = Math.random() * Math.PI * 2, v = sp * (.3 + Math.random()); this.parts.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, l: life * (.6 + Math.random() * .6), m: life, c: cols[i % cols.length], r: 2 + Math.random() * 3.5, k, g: k === 3 ? 600 : 0 }); }
  }

  private finishTurn() {
    this.turn = (1 - this.turn) as 0 | 1; this.phase = 'aim'; this.tleft = this.cfg.turnTime; this.aiT = 0; this.aiPlan = null;
    this.events.push({ t: 'turn', team: this.turn });
  }
  private end() { this.phase = 'over'; this.events.push({ t: 'end', score: [this.score[0], this.score[1]] }); }

  private timeUp() { return this.cfg.matchTime > 0 && !this.sudden && this.mleft <= 0; }

  // ---------- main step (call once per frame) ----------
  update(rdt: number) {
    const dt = Math.min(rdt, .05); this.time += dt;
    if (this.phase === 'over') { this.tickFx(dt); return; }
    if (this.cfg.matchTime > 0 && !this.sudden && this.mleft > 0) { this.mleft = Math.max(0, this.mleft - dt); }
    let ts = 1; if (this.slow > 0) { this.slow -= dt; ts = .3 + .7 * Math.pow(1 - Math.max(0, this.slow) / 1.1, 2); }
    this.acc += dt * ts; let n = 0;
    while (this.acc >= STEP && n++ < 16) {
      for (const b of this.bodies) { b.px = b.x; b.py = b.y; }
      this.sim(STEP); this.acc -= STEP;
    }
    if (n > 16) this.acc = 0;
    if (this.phase === 'move') {
      // at rest = every body stopped (speeds are snapped to 0 under the stop thresholds) and no shot ramp pending
      this.idle = this.bodies.some(b => b.vx || b.vy || b.ramp > 0) ? 0 : this.idle + dt;
      if (this.idle > .15) this.finishTurn();
    } else if (this.phase === 'aim') {
      if (this.cfg.matchTime > 0 && !this.sudden && this.mleft <= 0) {
        if (this.score[0] !== this.score[1]) { this.end(); return; }
        this.sudden = true; this.events.push({ t: 'clock' });
      }
      if (this.cfg.turnTime > 0) { this.tleft -= dt; if (this.tleft <= 0) { this.drag = null; this.aiPlan = null; this.finishTurn(); } }
      if (this.isAiTurn()) this.aiTick(dt);
    } else if (this.phase === 'goal') {
      this.pause -= dt;
      if (this.pause <= 0) {
        if (this.cfg.matchTime > 0) { if (this.sudden || (this.mleft <= 0 && this.score[0] !== this.score[1])) this.end(); else { if (this.mleft <= 0) this.sudden = true; this.reset(this.kick); } }
        else if (this.score[0] >= this.cfg.limit || this.score[1] >= this.cfg.limit) this.end();
        else this.reset(this.kick);
      }
    }
    this.tickFx(dt);
  }

  // online clients: visual-only goal feedback (the host owns the score)
  fxGoal(t: 0 | 1) {
    this.ripple[t] = 1; this.rippleX[t] = this.ball.x;
    this.flash = 1; this.shake[t] = .6; this.cam = 1.4;
    const g = this.goals[t], c = ['#ffd23a', '#ffffff', '#3bd0ff', '#ff4a7a', '#7bff5a'];
    this.burst(this.ball.x, g.y, 80, 760, c, 1.4, 1); this.burst(this.ball.x, g.y, 50, 520, c, 1.8, 3);
  }

  tickFx(dt: number) {
    this.flash = Math.max(0, this.flash - dt * 2); this.cam = Math.max(0, this.cam - dt * 3.2);
    this.shake[0] = Math.max(0, this.shake[0] - dt); this.ripple[0] = Math.max(0, this.ripple[0] - dt * .8); this.ripple[1] = Math.max(0, this.ripple[1] - dt * .8); this.shake[1] = Math.max(0, this.shake[1] - dt);
    const ball = this.ball; const sp = ball ? hyp(ball.vx, ball.vy) : 0;
    if (ball && sp > 60) this.trail.push({ x: ball.x, y: ball.y, a: Math.min(1, sp / 900) });
    let k = 0; for (const p of this.trail) { p.a -= dt * 3.2; if (p.a > 0) this.trail[k++] = p; } this.trail.length = k; if (this.trail.length > 40) this.trail.splice(0, this.trail.length - 40);
    for (const b of this.bodies) if (b !== ball) { const s = hyp(b.vx, b.vy); if (s > 140 * K) b.tr.push({ x: b.x, y: b.y }); else if (b.tr.length) b.tr.shift(); if (b.tr.length > 12) b.tr.shift(); }
    k = 0; for (const p of this.parts) { p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= .965; p.vy = p.vy * .965 + p.g * dt; p.l -= dt; if (p.l > 0) this.parts[k++] = p; } this.parts.length = k;
  }

  // interpolation factor for rendering between physics steps
  alpha() { return clamp(this.acc / STEP, 0, 1); }

  // ---------- AI ----------
  private aiTick(dt: number) {
    if (!this.aiPlan) {
      this.aiT += dt; if (this.aiT < .7 + Math.random() * .5) return;
      const p = this.aiDecide(); if (!p) return; this.aiPlan = { ...p, t: 0 };
      this.drag = { b: p.b, sx: p.b.x, sy: p.b.y, cx: p.b.x, cy: p.b.y, ai: true }; return;
    }
    const pl = this.aiPlan; pl.t += dt; const k = Math.min(1, pl.t / .75), e = k * k * (3 - 2 * k);
    if (this.drag) { this.drag.cx = pl.b.x - pl.dx * pl.l * e; this.drag.cy = pl.b.y - pl.dy * pl.l * e; }
    if (k >= 1) { this.drag = null; this.aiPlan = null; this.fire(pl.b, pl.dx * pl.l, pl.dy * pl.l, pl.l); }
  }

  private aiDecide() {
    const me = this.turn, ball = this.ball, B = this.bodies, mine = B.filter(b => b.team === me && b !== ball);
    const tg = this.goals[me === 0 ? 0 : 1 - 0], og = this.goals[1 - me];
    // team 1 attacks the bottom goal (goals[1]); team 0 attacks the top goal (goals[0])
    const target = this.goals[me === 1 ? 1 : 0]; void tg;
    const lvl = this.cfg.aiLvl, sg = [.14, .06, .016][lvl], gw = (target.x2 - target.x1) / 2;
    const segDist = (px: number, py: number, ax: number, ay: number, bx: number, by: number) => { const vx = bx - ax, vy = by - ay, l2 = vx * vx + vy * vy || 1; let t = ((px - ax) * vx + (py - ay) * vy) / l2; t = clamp(t, 0, 1); return hyp(px - (ax + vx * t), py - (ay + vy * t)); };
    const clear = (p: Body, x: number, y: number) => { for (const o of B) { if (o === p || o === ball) continue; if (segDist(o.x, o.y, p.x, p.y, x, y) < p.r + o.r - 6) return false; } return true; };
    const cands: { p: Body; dx: number; dy: number; sc: number; dist: number; atk: number }[] = [];
    for (const p of mine) {
      for (const ox of [-.55, 0, .55]) {
        const Tx = this.CX + ox * gw, Ty = target.y; let ux = Tx - ball.x, uy = Ty - ball.y; const ul = hyp(ux, uy) || 1; ux /= ul; uy /= ul;
        const cx = ball.x - ux * (p.r + ball.r + 1), cy = ball.y - uy * (p.r + ball.r + 1); let vx = cx - p.x, vy = cy - p.y; const dist = hyp(vx, vy); if (dist < 8) continue; vx /= dist; vy /= dist;
        const al = vx * ux + vy * uy; if (al < .2 || !clear(p, cx, cy)) continue;
        let blk = 0; for (const o of B) { if (o.team === me || o === ball) continue; if (segDist(o.x, o.y, ball.x, ball.y, Tx, Ty) < ball.r + o.r + 6) blk++; }
        cands.push({ p, dx: vx, dy: vy, sc: 100 * al - dist * .03 - blk * 28 + (Math.abs(ball.y - Ty) < 420 ? 25 : 0), dist, atk: 1 });
      }
      let vx = ball.x - p.x, vy = ball.y - p.y; const dist = hyp(vx, vy);
      if (dist > 8) { vx /= dist; vy /= dist; if (clear(p, ball.x, ball.y)) { const toOwn = (vy * (og.y - ball.y) > 0) ? Math.abs(vy) : 0; cands.push({ p, dx: vx, dy: vy, sc: 10 - dist * .04 - toOwn * 55, dist, atk: 0 }); } }
    }
    if (!cands.length) { const p = mine.slice().sort((a, b) => hyp(a.x - ball.x, a.y - ball.y) - hyp(b.x - ball.x, b.y - ball.y))[0]; if (!p) return null; let vx = ball.x - p.x, vy = ball.y - p.y; const d = hyp(vx, vy) || 1; cands.push({ p, dx: vx / d, dy: vy / d, sc: 0, dist: d, atk: 0 }); }
    cands.sort((a, b) => b.sc - a.sc); const pool = cands.slice(0, [4, 2, 1][lvl]), c = pool[Math.floor(Math.random() * pool.length)];
    const gauss = () => (Math.random() + Math.random() + Math.random() - 1.5) * 1.15;
    const ang = Math.atan2(c.dy, c.dx) + gauss() * sg;
    let pw = lvl === 2 ? Math.min(1, .66 + c.dist / 1000) : Math.min(1, .5 + c.dist / 1100); if (lvl === 0) pw *= .7 + Math.random() * .3; if (c.atk && lvl > 0) pw = Math.max(pw, .78);
    return { b: c.p, dx: Math.cos(ang), dy: Math.sin(ang), l: Math.max(.3, pw) * LMAX };
  }
}
