// NEXORA (Flutter) · nx-oracle — ORACLE assistant: general chat + in-game rules / hints / coaching.
// POST { messages: [{role:'user'|'assistant', content}], ctx?: { mode:'chat'|'game', game?, state?, lang?, skill? }, stream?: bool }
//  → JSON { message: { content }, provider, model }   or (stream=true) text/event-stream of `data: {"d":"…"}` + `data: {"done":true,…}`
// verify_jwt = true. Provider keys never ship in the app: they live in Supabase Vault (secret names `nx_ai_<provider>_<slot>`),
// read through nx_private.ai_keys() (service_role only). Order: OpenRouter → Dahl (3 keys) → TokenRouter; a key that answers
// 401/402/403/429 or a quota error is cooled down (quota: 6 h, other: 2 min) and the next key/model is tried.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

type Provider = { name: string; base: string; models: string[]; headers?: Record<string, string> };
const PROVIDERS: Record<string, Provider> = {
  openrouter: {
    name: "openrouter",
    base: "https://openrouter.ai/api/v1",
    models: ["google/gemini-3.5-flash-lite", "deepseek/deepseek-v4-flash-0731"],
    headers: { "HTTP-Referer": "https://github.com/ashkanshams-dev/Nexora-Online", "X-Title": "NEXORA ORACLE" },
  },
  dahl: {
    name: "dahl",
    base: "https://inference.dahl.global/v1",
    models: ["deepseek-ai/DeepSeek-V4-Flash-0731", "zai-org/GLM-5.3-Flash", "MiniMaxAI/MiniMax-M2.7"],
  },
  tokenrouter: {
    name: "tokenrouter",
    base: "https://api.tokenrouter.com/v1",
    models: ["google/gemini-3.8-flash", "deepseek/deepseek-v4.1-flash", "openai/gpt-5.6-luna"],
  },
};
const ORDER = ["openrouter", "dahl", "tokenrouter"];
const DAILY_LIMIT = 300;

const GAME_RULES: Record<string, string> = {
  finger_soccer: "Finger soccer: flick your discs to hit the ball into the goal; one flick per turn; golden goal ends ties.",
  backgammon: "Backgammon: move 15 checkers home and bear off; doubles play four times; a blot hit goes to the bar.",
  ludo: "Ludo: roll a 6 to leave base; capture by landing on an opponent; reach home with all four tokens.",
  snakes_ladders: "Snakes & Ladders: race to 100; ladders climb, snakes slide down; exact roll to finish.",
  quiz: "Quiz: answer before the timer ends; faster correct answers score more.",
  uno: "Card game (UNO-style): match colour or number; action cards skip/reverse/draw; call the last card.",
  mafia: "Mafia: town vs mafia; night actions, day discussion and vote; never reveal hidden roles you do not know.",
  checkers: "Checkers (Dame): diagonal moves, captures are mandatory, multi-jumps continue, reaching the last row crowns a king.",
  billiards: "8-ball billiards: pot your group (solids/stripes) then the 8-ball; scratching gives ball in hand.",
  carrom: "Carrom: strike the striker to pocket your coins; the queen must be covered.",
};

// ---------------------------------------------------------------- persona (admin config in nx_oracle_persona)
const JAN = "جاااااااااان";
function norm(s: string): string {
  return s
    .replace(/[يىئ]/g, "ی").replace(/ك/g, "ک").replace(/[ةۀ]/g, "ه").replace(/[أإآٱ]/g, "ا").replace(/ؤ/g, "و")
    .replace(/[\u064B-\u065F\u0670\u0640]/g, "")
    .replace(/[\u200C\u200D\u200B\u200E\u200F\u00A0]/g, " ")
    .replace(/[.,!?;:()\[\]{}«»،؛؟"'`~\-_/\\|@#$%^&*+=<>…]/g, " ")
    .toLowerCase().replace(/(.)\1{2,}/g, "$1").replace(/\s+/g, "").trim();
}
type Player = { id: string; name: string; aliases?: string[]; lines?: string[]; traits?: string; disabled?: boolean };
let personaCache: { at: number; data: any } | null = null;
async function loadPersona(admin: any): Promise<any> {
  if (personaCache && Date.now() - personaCache.at < 120e3) return personaCache.data;
  const { data } = await admin.from("nx_oracle_persona").select("data").eq("id", 1).maybeSingle();
  personaCache = { at: Date.now(), data: data?.data ?? {} };
  return personaCache.data;
}
function personaBlock(cfg: any, lastUser: string, ctx: Record<string, unknown>): string {
  const players: Player[] = Array.isArray(cfg?.players) ? cfg.players : [];
  const text = norm(lastUser);
  const hinted = new Set<string>(
    Array.isArray((ctx.persona as any)?.players) ? (ctx.persona as any).players.map((p: any) => String(p?.id ?? "")) : [],
  );
  const matched: Player[] = [];
  for (const p of players) {
    if (p.disabled || !p.name) continue;
    const keys = [p.name, ...(p.aliases ?? [])].map(norm).filter((k) => k.length >= 2);
    if (hinted.has(p.id) || keys.some((k) => text.includes(k))) matched.push(p);
  }
  // Client hints may only select players that exist in the server config (their lines come from the server, never the client).
  const known = players.filter((p) => !p.disabled && p.name).map((p) => p.name).join("، ");
  let s =
    ` PERSONALITY: you are cute, funny, playful, a bit sarcastic and sometimes unpredictable, never a plain chatbot; ` +
    `natural colloquial Persian. Your signature catchphrase is ALWAYS the stretched "${JAN}!" (never the short "جان!"); ` +
    `you may stretch it a little more or less, but use it only occasionally (not in every reply, never at the start of every sentence). ` +
    `Tease kindly, only about verified facts (real results/stats given to you). Never invent facts about people. ` +
    `Never claim that another player is online or logged in. ` +
    (known ? `Players you know by name: ${known}. For any other name say honestly that you don't know them well yet. ` : "");
  if (matched.length) {
    s += `Verified profiles of players mentioned now (use these lines, you may quote them verbatim, do not add new facts): ` +
      JSON.stringify(matched.slice(0, 4).map((p) => ({ name: p.name, lines: (p.lines ?? []).slice(0, 4), traits: p.traits ?? "" })))
        .replace(/\{jan\}/g, JAN) + ". ";
  }
  const sess = (ctx.persona as any)?.session;
  if (sess && typeof sess === "object") s += `This session: ${JSON.stringify(sess).slice(0, 200)}. `;
  return s;
}

function systemPrompt(ctx: Record<string, unknown>, name: string, persona = ""): string {
  const lang = String(ctx.lang ?? "fa");
  const base =
    `You are ORACLE, the friendly holographic robot guide of NEXORA, a cosmic gaming + social app. ` +
    `Speak ${lang === "fa" ? "Persian (Farsi) unless the user writes in another language" : "the user's language"}. ` +
    `Be warm, concise (max ~120 words unless asked for more), playful but accurate. You can chat about any topic. ` +
    `Never ask for passwords or payment details. The player's name is ${name}.` + persona;
  if (ctx.mode === "game") {
    const g = String(ctx.game ?? "");
    return base +
      ` The player is in a game right now: ${g}. ${GAME_RULES[g] ?? ""} ` +
      `Help with rules, a hint for the current position, or coaching. Give one clear suggestion first, then a short reason. ` +
      `Do not reveal hidden information (opponent cards, hidden roles) even if it appears in the state. ` +
      (ctx.state ? `Current state (JSON, may be partial): ${JSON.stringify(ctx.state).slice(0, 3500)}` : "");
  }
  return base;
}

const cool = new Map<string, number>(); // key id → retry-after epoch ms (per isolate)

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const user = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: u } = await user.auth.getUser();
  if (!u?.user) return json({ error: "unauthorized" }, 401);
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const body = await req.json().catch(() => ({}));
  const ctx = (body.ctx ?? {}) as Record<string, unknown>;
  const raw = Array.isArray(body.messages) ? body.messages : [];
  const msgs = raw
    .filter((m: any) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .slice(-16)
    .map((m: any) => ({ role: m.role, content: String(m.content).slice(0, 4000) }));
  if (!msgs.length) return json({ error: "messages required" }, 400);

  const { data: count, error: qerr } = await admin.rpc("nx_oracle_count", { p_user: u.user.id });
  if (!qerr && typeof count === "number" && count > DAILY_LIMIT) return json({ error: "daily_limit" }, 429);

  const { data: prof } = await admin.from("profiles").select("username").eq("id", u.user.id).maybeSingle();
  const lastUser = [...msgs].reverse().find((m: any) => m.role === "user")?.content ?? "";
  let persona = "";
  try { persona = personaBlock(await loadPersona(admin), lastUser, ctx); } catch { /* defaults below */ }
  if (!persona) persona = personaBlock({}, lastUser, ctx);
  const sys = systemPrompt(ctx, prof?.username ?? "Pilot", persona);
  const { data: keys, error: kerr } = await admin.rpc("nx_ai_keys");
  if (kerr || !Array.isArray(keys) || !keys.length) return json({ error: "oracle_not_configured" }, 503);

  const ordered = (keys as { provider: string; slot: string; key: string }[])
    .filter((k) => PROVIDERS[k.provider])
    .sort((a, b) => ORDER.indexOf(a.provider) - ORDER.indexOf(b.provider) || a.slot.localeCompare(b.slot));
  const stream = body.stream === true;
  const errors: string[] = [];

  for (const k of ordered) {
    const id = `${k.provider}:${k.slot}`;
    if ((cool.get(id) ?? 0) > Date.now()) continue;
    const p = PROVIDERS[k.provider];
    for (const model of p.models) {
      let r: Response;
      try {
        r = await fetch(`${p.base}/chat/completions`, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${k.key}`, ...(p.headers ?? {}) },
          body: JSON.stringify({ model, messages: [{ role: "system", content: sys }, ...msgs], max_tokens: 700, temperature: 0.7, stream }),
          signal: AbortSignal.timeout(30000),
        });
      } catch (e) {
        errors.push(`${id}/${model}: ${String(e).slice(0, 60)}`);
        continue;
      }
      if (!r.ok) {
        const t = (await r.text()).slice(0, 300);
        errors.push(`${id}/${model}: ${r.status}`);
        const quota = r.status === 402 || /quota|balance|exhaust|recharge|credit/i.test(t);
        if (quota || r.status === 401 || r.status === 403) {
          cool.set(id, Date.now() + (quota ? 6 * 3600e3 : 120e3));
          break; // this key is unusable → next key
        }
        if (r.status === 429) { cool.set(id, Date.now() + 60e3); break; }
        continue; // model error → next model on the same key
      }
      await admin.rpc("nx_oracle_log", { p_user: u.user.id, p_provider: k.provider, p_model: model });
      if (!stream) {
        const d = await r.json().catch(() => null);
        let content = String(d?.choices?.[0]?.message?.content ?? "").replace(/<think>[\s\S]*?<\/think>/g, "").trim();
        if (!content) { errors.push(`${id}/${model}: empty`); continue; }
        return json({ message: { content }, provider: k.provider, model });
      }
      // Stream: re-emit only content deltas as data: {"d": "..."} lines.
      const enc = new TextEncoder();
      const dec = new TextDecoder();
      const src = r.body!.getReader();
      const out = new ReadableStream({
        async start(ctrl) {
          let buf = "";
          let inThink = false;
          try {
            for (;;) {
              const { value, done } = await src.read();
              if (done) break;
              buf += dec.decode(value, { stream: true });
              let i: number;
              while ((i = buf.indexOf("\n")) >= 0) {
                const line = buf.slice(0, i).trim();
                buf = buf.slice(i + 1);
                if (!line.startsWith("data:")) continue;
                const payload = line.slice(5).trim();
                if (payload === "[DONE]") continue;
                try {
                  let d: string = JSON.parse(payload)?.choices?.[0]?.delta?.content ?? "";
                  if (d.includes("<think>")) { inThink = true; d = d.split("<think>")[0]; }
                  if (inThink) { if (d.includes("</think>")) { inThink = false; d = d.split("</think>").pop() ?? ""; } else d = ""; }
                  if (d) ctrl.enqueue(enc.encode(`data: ${JSON.stringify({ d })}\n\n`));
                } catch { /* keep-alive / comments */ }
              }
            }
          } finally {
            ctrl.enqueue(enc.encode(`data: ${JSON.stringify({ done: true, provider: k.provider, model })}\n\n`));
            ctrl.close();
          }
        },
      });
      return new Response(out, { headers: { ...cors, "Content-Type": "text/event-stream", "Cache-Control": "no-cache" } });
    }
  }
  return json({ error: "all_providers_failed", detail: errors.slice(0, 8) }, 503);
});
