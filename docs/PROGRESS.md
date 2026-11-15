# PROGRESS (branch `nxg`)

## Online foundation (M1) — done
- Supabase project `eisstodgncimypdawisy` (shared with the other NEXORA app: same `auth.users` + `profiles`).
- New schema under `nx_` prefix: `supabase/migrations/20261115000000_nx_core.sql` (+ `_100_nx_fk_profiles.sql`), RLS on every table. Applied live.
- `lib/core/online/`: `online_service.dart` (guest = anonymous auth, upgrade to email+password keeps the uid; sign in / out),
  `cloud_profile_sync.dart` (server owns XP/coins via `nx_award` / `nx_purchase` — idempotent, daily cap 3000 XP;
  inventory/achievements/stats/decor in `nx_profiles.data`; offline queue flushes on reconnect), `SupabaseBackend` implements `BackendGateway`.
- Account page: Settings → Account (`/account`). Offline builds (no dart-define) behave exactly as before.

## Online multiplayer (M2) — all 9 games wired
- Model: every phone runs the same pure-Dart core with the same seed; players exchange inputs only. The DB (`nx_push_move`, seq = last+1,
  first writer wins) is the single ordered log → identical order everywhere. Reconnect/resync = rebuild the game and replay the log instantly.
  Pre-move state hashes are verified (`NetLink.verify`).
- Physics (finger soccer, carrom, billiards): shot input relayed, identical deterministic sim, the authority (lowest connected seat) posts a full
  snapshot after every shot; non-authority waits for it (≤3.5 s) before the next aim. Physics/tuning untouched.
- Lobby (`OnlineLobbyPage`): quick match, private/public room by code, open rooms, ready/start, invite friends (`nx_invites`, real-time banner),
  presence dots, forfeit on leave, absent players auto-forfeited by the authority (40 s on their turn / 90 s otherwise).
- Results: `nx_finish_match` → `nx_match_results`, `nx_game_stats` (rating ±), XP/coins; `/leaderboard` (per game + global XP).
- Seat 1 sees finger soccer / carrom rotated 180° (own side at the bottom).
- Mafia online: 6–10 players, seeded roles on every phone, UI shows only what that player may know (roles are hidden by the client UI, not
  cryptographically — a modified client could read them).

## Remaining / next
- Social worlds (Orbit chats/friends/calls, Nova posts, Social Station communities) on Supabase.
- LiveKit calls in Orbit (Edge Function `nx-call-token`; LIVEKIT_* secrets already exist on the project).
- No device testing possible from the build agent: online flows verified against the live DB with a headless Dart client; UI verified by analyzer + CI build.
