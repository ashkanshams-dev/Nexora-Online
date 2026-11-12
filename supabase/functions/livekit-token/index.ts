// NEXORA · LiveKit voice token
// Secrets: LIVEKIT_URL, and LIVEKIT_KEYS="APIKEY:SECRET" (or LIVEKIT_API_KEY + LIVEKIT_API_SECRET)
import { createClient } from "npm:@supabase/supabase-js@2";
import { AccessToken } from "npm:livekit-server-sdk@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("LIVEKIT_URL");
    let key = Deno.env.get("LIVEKIT_API_KEY");
    let secret = Deno.env.get("LIVEKIT_API_SECRET");
    const pair = Deno.env.get("LIVEKIT_KEYS");
    if ((!key || !secret) && pair && pair.includes(":")) {
      const i = pair.indexOf(":");
      key = pair.slice(0, i).trim();
      secret = pair.slice(i + 1).trim();
    }
    if (!url || !key || !secret) return json({ error: "voice_not_configured" }, 503);

    const auth = req.headers.get("Authorization") ?? "";
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: auth } },
    });
    const { data: u } = await sb.auth.getUser();
    if (!u?.user) return json({ error: "unauthorized" }, 401);

    const { room_id, purpose } = await req.json();
    const game = purpose === "game";   // v8: data-only room for low-latency match traffic
    if (!room_id) return json({ error: "room_id required" }, 400);

    const { data: rp } = await sb.from("room_players").select("role, team").eq("room_id", room_id).eq("user_id", u.user.id).maybeSingle();
    if (!rp) return json({ error: "not_in_room" }, 403);
    const { data: prof } = await sb.from("profiles").select("username, avatar").eq("id", u.user.id).maybeSingle();

    const isPlayer = rp.role === "player";
    const at = new AccessToken(key, secret, {
      identity: u.user.id,
      name: prof?.username ?? "Pilot",
      ttl: "2h",
      metadata: JSON.stringify({ team: rp.team, role: rp.role, avatar: prof?.avatar }),
    });
    const lkRoom = game ? `nexora-${room_id}-g` : `nexora-${room_id}`;
    at.addGrant({
      room: lkRoom,
      roomJoin: true,
      canPublish: game ? false : isPlayer,
      canSubscribe: true,
      canPublishData: true,
    });
    return json({ url, token: await at.toJwt(), room: lkRoom, canPublish: game ? false : isPlayer });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
