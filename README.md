# NEXORA — React Native (Expo SDK 58, TypeScript)

## Run in Expo Go
1. Install Node.js 20+ on your PC.
2. In this folder: `npm install`
3. `npx expo start` (if the phone is not on the same Wi-Fi: `npx expo start --tunnel`)
4. Open **Expo Go** on the phone (latest version, SDK 58) and scan the QR code.

Web preview: `npx expo start --web`

## Structure
- `src/game/engine.ts` — physics engine (pure TS, fixed 240 Hz sub-steps, render interpolation, AI)
- `src/game/render.ts` — Skia renderer (GPU sphere shader for the ball, glow, trails, particles)
- `src/screens/*` — Home, Pilot (discs), Armory (balls/arenas), Market, Profile, Settings, Setup, Match, Result
- `src/ui/Backdrop.tsx` — GPU nebula/starfield shader per sector
- `src/store.tsx` — local profile (AsyncStorage)

Online multiplayer/backend from the web build is not part of this version (offline: vs bot + local 2P).

## v3 (NX8 world UI)
- Home is now the 3D gate world from the "Nexora 3D Menu" page: warp intro, swipeable portal ring, holographic draggable panels (profile, shop, discs, settings, mode).
- Performance: match canvas no longer re-renders through React (picture pushed via a Reanimated shared value), pieces drawn from pre-rendered sprites, no per-frame blur, backdrop is baked images animated on the UI thread (no full-screen shader).
- Pieces enlarged (radius 42 -> 49). Ball curve (spin drift) removed: shots travel straight.
- To judge real speed, run without dev mode:  npx expo start --no-dev --minify -c

## v4 (full UI rebuild)
- New app shell: top HUD (level, coins, gems, daily gift, settings) + animated bottom tab bar (Home, Team, Play, Shop, Profile).
- Home hub: hero pedestal art, mascot, quick-play button, league strip, game-mode rail, command-deck menu plates, loadout, missions.
- Play: 3D swipe carousel of game modes (UI-thread scroll animation), league road, rewards.
- Team: discs (10 categories incl. new Elite 36, Emblems 16, Legends 6, Chrome 8), balls, fields, formation preview on a mini pitch.
- Shop: legendary discs, free + royal chests with opening animation, daily -30% deals, gem exchange, full catalogue.
- Profile: editable name, level, league, win-rate ring, stats, 8 achievements with claimable rewards.
- 7-day daily reward calendar, match setup bottom sheet, settings sheet (sound, music, haptics, graphics quality, default AI).
- Performance: expo-image (memory+disk cache), FlatList grids, all animation on the UI thread (Reanimated), "Smooth" graphics mode for weak phones.

## v7 (pro physics + lockstep netcode + final disc roster)
- Physics: deterministic engine (sqrt-only maths, precomputed damping, seeded aim RNG, quantised shot input), 3 solver
  iterations, allocation-free hot loop (no GC hitches), full ball-rotation re-orthonormalisation.
- Online: lockstep replay + client-side prediction. The host broadcasts each shot once ('go' = flick + pre-shot state);
  every phone replays it with the bit-identical engine, so motion starts instantly with no interpolation delay. The
  shooter predicts locally (zero input lag). Keyframes every 24 ticks auto-correct any drift; snapshots dropped from
  30 Hz to 10 Hz (less Supabase Realtime load = lower, steadier ping). Spectators joining mid-shot fall back to interpolation.
- Visuals: new ball shader (studio lighting, Fresnel, seamless back hemisphere, mipmapped texture = no shimmer), 3D puck
  discs (side wall, bevelled rim, inner shadow, 256 px sprites), contact shadows, cached goal nets/frames (less per-frame work).
- Discs: final roster of 308 discs in 10 collections (assets/g/teams). Supabase catalogue synced by supabase/discs_v7.sql.
