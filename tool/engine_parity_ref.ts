// Reference generator: copy src/game/engine.ts + data.ts from main next to this file, then
// node --experimental-strip-types tool/engine_parity_ref.ts > test/fixtures/engine_parity_ts.txt
import { Engine } from './engine.ts';
const out: string[] = [];
for (const field of [0, 3, 15, 27]) {
  const e = new Engine({ field, ball: 0, forms: [field % 6, (field + 2) % 6], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0, vip: [false, true], first: 0, stats: field % 2 ? [{ power: 7, accuracy: 3 }, { power: 4, accuracy: 9 }] : undefined } as any);
  e.seed = 0x5eed ^ field;
  let s = 12345 + field;
  const r = () => { s = (s * 48271) % 2147483647; return s / 2147483647; };
  for (let shot = 0; shot < 120; shot++) {
    const team = shot % 2; const mine = e.bodies.filter(b => b.team === team);
    const b = mine[Math.floor(r() * mine.length)];
    let dx = e.ball.x - b.x + (r() - .5) * 120, dy = e.ball.y - b.y + (r() - .5) * 120; const l = Math.sqrt(dx * dx + dy * dy); const k = (40 + r() * 200) / l; dx *= k; dy *= k;
    e.phase = 'aim'; e.fire(b, dx, dy, Math.sqrt(dx * dx + dy * dy), true);
    let guard = 0;
    while (guard++ < 6000) { for (const q of e.bodies) { q.px = q.x; q.py = q.y; } (e as any).sim(1 / 240); if (e.tick % 60 === 0) out.push(field + ':' + shot + ':' + e.tick + ':' + e.packState().join(',')); if (e.atRest() || e.phase === 'goal') break; }
    out.push(field + ':' + shot + ':end:' + e.tick + ':' + e.phase + ':' + e.packState().join(','));
    if (e.phase === 'goal') e.reset(team as 0 | 1);
    for (const q of e.bodies) { q.x = q.px = Math.round(q.x * 64) / 64; q.y = q.py = Math.round(q.y * 64) / 64; q.vx = q.vy = 0; }
  }
}
console.log(out.join('\n'));
