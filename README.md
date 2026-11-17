<p align="center">
  <img src="docs/media/banner.png" alt="NEXORA" width="100%"/>
</p>

<p align="center">
  <b>YOUR UNIVERSE. YOUR IDENTITY. YOUR EXPERIENCE.</b><br/>
  A cosmic gaming + social universe for Android — 9 online games, chat & calls, posts & stories, tournaments, and ORACLE, a robot buddy with a (very) big personality.
</p>

<p align="center">
  <a href="https://github.com/ashkanshams-dev/Nexora-Online/releases"><img alt="Download APK" src="https://img.shields.io/badge/Download-APK-ff3cac?style=for-the-badge&logo=android&logoColor=white"/></a>
  <a href="https://github.com/ashkanshams-dev/Nexora-Online/actions/workflows/android.yml"><img alt="Android build" src="https://github.com/ashkanshams-dev/Nexora-Online/actions/workflows/android.yml/badge.svg?branch=redesign"/></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.50-02569B?logo=flutter&logoColor=white"/>
  <img alt="Supabase" src="https://img.shields.io/badge/Supabase-Postgres%20%7C%20Realtime%20%7C%20Edge-3ECF8E?logo=supabase&logoColor=white"/>
  <img alt="LiveKit" src="https://img.shields.io/badge/LiveKit-voice%20%26%20video-7B61FF"/>
  <img alt="Platform" src="https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white"/>
  <img alt="Language" src="https://img.shields.io/badge/UI-فارسی%20%7C%20English-orange"/>
</p>

---

## 📥 Download

Grab the newest **`NEXORA-redesign-universal.apk`** from **[Releases](https://github.com/ashkanshams-dev/Nexora-Online/releases)** (look for the `redesign-*` tags; `arm64-v8a` is smaller and fits most phones).

1. Download the APK on your phone.
2. Allow *Install unknown apps* for your browser / file manager when Android asks.
3. Install and open. Later builds update in place, and the app tells you when a new `redesign-*` build is out.

<div dir="rtl">

**فارسی:** آخرین فایل `NEXORA-redesign-universal.apk` را از بخش [Releases](https://github.com/ashkanshams-dev/Nexora-Online/releases) دانلود و نصب کن. اپ خودش نسخه‌های جدید را خبر می‌دهد.

</div>

---

## 🎮 Games

Every game runs offline against a bot and **online** against real players (one shared deterministic core per game, moves sequenced by Postgres, reconnect & resync by replay).

| | Game | Highlights |
|---|---|---|
| ⚽ | **Finger Soccer (گل‌کوچیک)** | Flick-to-shoot discs, 6 formations, team & ball picks, golden goal, 15 s online turns, animated GIF balls |
| 🎯 | **Carrom** | Striker on the baseline, queen + cover rule, fouls, deterministic physics replay online |
| 🎱 | **8-Ball Billiards** | Groups, ball-in-hand fouls, cue skins, server-checked results |
| 🎲 | **Backgammon (تخته‌نرد)** | Bar, bearing off, gammons & backgammons, NX2 boards |
| 🟡 | **Ludo** | Safe stars, captures, extra turns on 6, 2–4 players |
| 🐍 | **Snakes & Ladders** | Light ladders, exact 100, 2–4 players |
| 🃏 | **NX Cards** (UNO-style) | Skip / reverse / +2 / wild, the **NX!** call |
| ❓ | **Quiz** | 10 timed questions, speed bonus, Persian question banks |
| 🕵️ | **Mafia** | 6–10 players online, narrator mode for parties, smart bots |

## 🤖 ORACLE — the robot with attitude

<img align="right" src="docs/media/oracle.png" width="150" alt="ORACLE"/>

- Cute, funny, playful, a bit sarcastic — and famous for its stretched **«جاااااااااان!»**
- Knows **39 players** by name (typos, Latin spellings, ZWNJ & Arabic-letter variants handled) with their verbatim personalised lines.
- Random login greetings, spontaneous lines with cooldowns and no repeats, reactions to **real** wins and losses.
- Funny-but-accurate tutorials for each game mechanic, and a **first-run guided tour** with spotlight coach marks for every section.
- Offline Persian/English intent brain (navigation, rules, stats, settings) + the `nx-oracle` Edge Function for open conversation (provider keys in Supabase Vault, never in the app).
- **Admin-editable**: players, aliases, lines, greetings, tutorials, tour texts, frequencies and cooldowns live in Supabase (`nx_oracle_persona`).

## 🌌 The universe

- **Hub & dock** — cosmic neon menus, big centre GAME button, sliding pages.
- **Rooms & matchmaking** — quick match, private/public rooms by code, invites, presence, forfeits.
- **Tournaments** — up to 64 players, approvals & invite codes, check-in reminders, automatic draws and rounds, server-side results and prize payouts.
- **Orbit Network** — 1:1, groups and channels, read receipts, voice & video calls (LiveKit).
- **Nova Gallery** — posts, 24 h stories, likes, comments, hashtags, follows.
- **Personal Orbit** — avatar & wardrobe, personal space, missions, achievements, stats.
- **Exchange** — transparent coin shop (no gambling), rarity tiers, server-validated prices.

## 🧰 Tech stack

| Layer | What |
|---|---|
| App | **Flutter 3.50** (Dart 3.14), Riverpod, go_router, CustomPainter/Ticker game loops (Flame available) |
| Backend | **Supabase only** — Auth, Postgres (RLS on every table, SECURITY DEFINER RPCs), Realtime, Storage, pg_cron, Vault, Edge Functions (Deno) |
| Real-time voice/video | **LiveKit** (short-lived tokens from the `nx-call-token` Edge Function) |
| CI/CD | GitHub Actions: analyze → tests → split-per-ABI + universal APKs → install checks → GitHub release |

No other servers — game state, tournaments and economy are server-authoritative inside Postgres.

## 🛠️ Build from source

```bash
git clone -b redesign https://github.com/ashkanshams-dev/Nexora-Online.git
cd Nexora-Online
flutter create --platforms=android --org com.nexora --project-name nexora .   # generates android/ (CI does the same)
flutter pub get
flutter analyze && flutter test
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key> \
  --dart-define=LIVEKIT_URL=wss://<your-livekit-host>
```

Without the `--dart-define`s the app runs fully offline (bots, local profile). Server setup: [`docs/ONLINE_SETUP.md`](docs/ONLINE_SETUP.md); SQL in [`supabase/migrations`](supabase/migrations), Edge Functions in [`supabase/functions`](supabase/functions).

## 🗂️ Project structure

```
lib/
  app/                 app shell, router, global overlays (ORACLE buddy, update banner)
  core/                backend gateway, online services, profile & economy, settings, theme, NX2 UI kit, updater
  features/tournaments tournament domain (bracket mirror), data, pages, organiser tools
  games/               one folder per game: pure-Dart core + UI + bots (+ online link)
  worlds/              hub, arcade, rooms, social hub, orbit network, nova gallery, personal orbit,
                       exchange, settings, oracle_core (brain + persona + guided tour)
supabase/
  migrations/          social/auth project schema (nx_*), tournaments engine, owner tools, ORACLE persona
  games/migrations/    games project (rooms, matches, matchmaking, tournaments) — backend split in progress
  functions/           nx-oracle (AI), nx-call-token (LiveKit)
test/                  unit + widget tests (games, worlds, ORACLE persona, updater, tournaments)
docs/                  progress, decisions, online setup, release notes
```

## 📜 Notes

- The React Native NEXORA app lives on `main`; this Flutter redesign lives on `redesign` and never marks its releases as "latest".
- Licensed national pucks/logos are never used — only original skins. "NX Cards" is an UNO-style game, not affiliated with UNO.

<p align="center"><sub>Made with 💜 for the گل‌کوچیک crew · جاااااااااان!</sub></p>
