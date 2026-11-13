// NEXORA · push-send — called by the notifications AFTER INSERT trigger (pg_net) and delivers the notification
// to every device of the user through Firebase Cloud Messaging HTTP v1.
// Secrets: PUSH_WEBHOOK_SECRET (must equal Vault secret 'push_webhook_secret'), FCM_SERVICE_ACCOUNT (service-account JSON).
// While FCM_SERVICE_ACCOUNT is not set the function answers 200 {skipped:"fcm_not_configured"} so nothing breaks.
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });

const CHANNEL: Record<string, string> = {
  dm: "messages", friend_request: "social", friend_accept: "social", follow: "social", club_invite: "social", club_request: "social",
  room_invite: "matches", match_found: "matches",
};

function b64url(data: ArrayBuffer | string) {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = ""; for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cached: { token: string; exp: number } | null = null;
async function accessToken(sa: { client_email: string; private_key: string; token_uri?: string }) {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp > now + 60) return cached.token;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri ?? "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
  const jwt = `${header}.${claim}.${b64url(sig)}`;
  const r = await fetch(sa.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const t = await r.json();
  if (!t.access_token) throw new Error("oauth: " + JSON.stringify(t).slice(0, 200));
  cached = { token: t.access_token, exp: now + (t.expires_in ?? 3600) };
  return cached.token;
}

Deno.serve(async (req) => {
  try {
    const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
    if (!secret || req.headers.get("x-push-secret") !== secret) return json({ error: "forbidden" }, 403);
    const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!raw) return json({ skipped: "fcm_not_configured" });
    const sa = JSON.parse(raw);
    const n = await req.json();
    if (!n?.user_id) return json({ error: "bad payload" }, 400);

    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: toks } = await sb.from("device_tokens").select("token").eq("user_id", n.user_id);
    if (!toks?.length) return json({ sent: 0 });

    const token = await accessToken(sa);
    const data: Record<string, string> = { kind: String(n.kind ?? ""), id: String(n.id ?? "") };
    for (const [k, v] of Object.entries(n.data ?? {})) data[k] = typeof v === "string" ? v : JSON.stringify(v);
    let sent = 0; const dead: string[] = [];
    await Promise.all(toks.map(async ({ token: t }: { token: string }) => {
      const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: t,
            notification: { title: n.title ?? "NEXORA", body: n.body ?? "" },
            data,
            android: { priority: "HIGH", notification: { channel_id: CHANNEL[n.kind] ?? "general", sound: "default", tag: `${n.kind}:${data.conversation ?? data.room ?? data.user ?? ""}` } },
          },
        }),
      });
      if (r.ok) sent++;
      else if (r.status === 404 || r.status === 400) {
        const e = await r.text();
        if (/UNREGISTERED|INVALID_ARGUMENT|registration-token-not-registered/.test(e)) dead.push(t);
      }
    }));
    if (dead.length) await sb.from("device_tokens").delete().in("token", dead);
    return json({ sent, pruned: dead.length });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
