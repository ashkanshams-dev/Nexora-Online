# redesign-2-fix — debugging pass (phase 1)

Branch `redesign-2-fix` (from `redesign-2` @ 5dc7634). Signed APKs: every push also updates the never-merged draft
PR #3 (`redesign-2-fix` -> `redesign`, "DO NOT MERGE"); its run restores the signing-key cache and publishes the
prerelease `redesign-2-fix-<run>` (arm64-v8a, armeabi-v7a, x86_64, universal). Push runs only analyze + test.

## Root causes found

| Report | Root cause | Fix |
|---|---|---|
| Menus buggy, Back odd | Guest mode (the only way in while the OTP email had no code) redirected `/rooms`, `/social`, `/tournaments`, `/leaderboard`, `/online/*`, chat/social/gallery worlds to `/hub`. Because menus use `context.push`, the redirect pushed a **second home page** on top of the first: buttons looked dead, Back returned to the same menu. | Session-based gate (`lib/app/auth_gate.dart`). Online-only routes open `SignInRequiredPage` (sign in / offline games). Unknown routes show a not-found page instead of a duplicate hub. |
| Game screens don't open | Dock **GAME** button = `/rooms`, which was in the guest block list -> bounced to hub. | `/rooms` open to guests (it has the offline "All games" entry; guest-specific empty state). |
| Online lobby | `OnlineLobbyPage.dispose()` used `ref` -> "Cannot use ref after the widget was disposed", realtime channel left subscribed. Same pattern in invite/call/tournament/announcement watchers. | Client cached in `initState`; watchers only unsubscribe on dispose. |
| Chat doesn't appear | Same guest bounce (`/social`, `/world/orbit_network`). Also: a guest who signed in from Account (password/admin) kept `authMode=guest` and stayed locked out. | Access derives from the real Supabase session; a session sets `authMode=email`. |
| Guided tour over wrong screens | ORACLE buddy read the router's base URI (stays `/hub` for pushed pages) -> home tour shown over other screens; overlay forced RTL + Persian buttons in EN. | Reads the top-most match; overlay follows app language. |
| OTP never arrives | **Server-side.** Verified live: `POST /auth/v1/otp` returns 200 and the email *is* delivered, but it is Supabase's default **"Your sign-in link"** Magic Link email: no 6-digit code (template lacks `{{ .Token }}`), and the link redirects to `http://localhost:3000` (Site URL). Client also mapped errors wrongly (`'invalid login'` vs `'invalid_login'`). | Client: `emailRedirectTo: nexora://login-callback` + Android intent filter (link signs in on the phone), clear FA/EN errors (wrong/expired code, rate limit, SMTP, sign-ups disabled), 60 s resend countdown, change-email, 6–10 digit codes, Persian digits. |

## Supabase dashboard steps (auth project `eisstodgncimypdawisy`) — do these by hand

1. **Authentication -> Emails -> Templates -> Magic Link** (used for existing *and* new users, because "Confirm email" is off /
   `mailer_autoconfirm=true`): put the code in the body, e.g. `<h2>NEXORA</h2><p>Your code: <b>{{ .Token }}</b></p>
   <p>Or open this link on your phone: <a href="{{ .ConfirmationURL }}">Sign in</a></p>`. Do the same in **Confirm signup**
   (used if you ever turn "Confirm email" on). Save.
2. **Authentication -> URL Configuration**: add `nexora://login-callback` to **Redirect URLs** (optionally `nexora://**`).
   Set Site URL to something that is not `http://localhost:3000` (e.g. `nexora://login-callback`).
3. **Authentication -> Emails -> SMTP Settings**: enable **custom SMTP** (Resend, Brevo, Mailgun, Zoho, Gmail app password…).
   The built-in sender is for testing only: a few emails per hour per project, may stop delivering to non-team
   addresses, and lands in spam often.
4. **Authentication -> Rate Limits**: after custom SMTP, raise "Emails sent per hour" (default 2–4 without SMTP, 30 with).
   "OTP / magic link per 60 s per address" stays 60 s — the app counts that down.
5. Optional: **Authentication -> Providers -> Email -> Email OTP length** (6 by default; the app accepts 6–10).

## Moving games to Flame (phase 2 notes)

`flame` is already in `pubspec.yaml` but unused. Every game runs its own `Ticker`/`CustomPainter` loop
(`arcade_kit/arcade_loop.dart` for the arcade games). Candidates, by benefit:
- **Real-time physics/action** (biggest win: `FlameGame` loop, components, collision detection, camera, sprite sheets):
  Finger Soccer (`finger_soccer/core/bm_engine.dart` + `ui/bm_view.dart`, keep the custom W-unit physics as a component
  or move to `flame_forge2d`), 8 Ball Pool (`pool8`), Billiards, Carrom (ball physics -> forge2d or keep engine, render
  via components), Mini Golf (walls/windmills -> collision + forge2d), Basketball Battle (projectile + rim -> forge2d),
  Kart Racing, Obstacle Race, Bomb Arena (tilemap + sprites -> `flame_tiled` optional).
- **Turn/board/card games** gain little (keep Flutter widgets): Backgammon, Ludo, Snakes & Ladders, UNO, Quiz,
  Mafia, Spy & Mafia (pure UI/state).
- Embed with `GameWidget(game: ...)` inside the existing `GameHostPage` so the exit/pause/result shell, ORACLE sheet and
  online `MatchLink` stay unchanged; port the `ArcadeSkin` sprites to `Sprite`/`SpriteAnimation`.
