# Training Brain — Working Notes for Claude

## Current state — READ FIRST (updated 2026-10-02)

Two Claude chats work on this repo, and this section is how they stay in sync:
- **Local PC chat** ("Training Brain — Apple Watch app", runs on the user's Windows PC,
  reachable from Mac/iPhone via Remote Control). It has the Garmin Connect IQ SDK and
  simulator, the Firebase CLI (deploys the web.app copy), the user's Chrome (Garmin
  store uploads) and USB access to the Garmin watch. Watch builds and Firebase deploys
  happen there.
- **Cloud chat** ("Training brain project"). Repo access only.

Rules for both: `git pull --rebase` before editing; after shipping, update this section
(version, what changed, open items) in the same push. Never put secrets in the repo.

### iPhone app (`iphone/`, added 2026-10-03)
- WKWebView of the live site + `bridge.js` (Web Bluetooth subset → `BLEBridge.swift` / CoreBluetooth). Replaces Bluefy for
  the bike + HR strap. Remembers picked devices; keeps the screen on while connected; alerts/confirms; Google popup sheet.
  iOS 15+. The user declined the $99 program AND doesn't want Xcode: CI publishes an unsigned `TrainingBrain.ipa` + SideStore/AltStore
  source `apps.json` as release `iphone-latest` (version 1.0.<run>). Install via TrollStore (iOS 14–16.6.1/17.0, permanent) or
  SideStore (free Apple ID, self-renewing). Don't suggest rented enterprise certificates.
  CI: `.github/workflows/iphone.yml` (simulator build + screenshot → `iphone-shots` branch). Bridge tested in the
  sandbox against the real Ride code with a fake native side.

### App — v3.62 (`index.html`)
- Hosting: GitHub Pages from `main` (auto) + Firebase copy https://training-631c1.web.app
  (manual deploy from the PC: `/training-brain/` rewritten to `/`, `changelog.json` copied).
- Service worker: stale-while-revalidate shell. A "New version ready — Reload" bar appears
  when a newer `APP_VERSION` is found; v3.47 also re-checks whenever the app is resumed.
- **Gym planning is by muscle group (v3.46).** The session set comes from the number of
  gym days: 1 Full Body · 2 Upper+Legs · 3 Push/Pull/Legs · 4 +Shoulders & Arms
  (`SHOULDERS_ARMS`) · 5 +Legs · 6 PPL×2 (`_WEEK_SET`). Order = muscles trained longest
  ago first (`_gymOrder`, 21 days of logs). Placement is a permutation search: no shared
  muscles on neighbouring days (Sunday→Monday counts), legs off the days around the long
  ride, most-needed first (`_placeSessions`). "Missed" is muscle-based (`getMissedLastWeek`).
- **The user picks gym days (v3.47).** `openWeekPicker` → `gym_days_<monday>`. It opens
  from 🔄/Generate and once per new week, and the "Gym days … Change" bar handles
  mid-week changes. Rides are placed on the other days jointly with the sessions
  (scored: weather, spacing, no 3+ training days in a row incl. last weekend), and at
  least one rest day is kept.
- **Cycling engine (v3.62).** `BIKE_CATS` (recovery, endurance, tempo, sweetspot, threshold, vo2, hills, skills) ×
  levels 1–10 → `_bikeWorkout(cat,lvl,mins,indoor)` builds steps (fit to the session; level = total work, fewer/longer
  intervals higher up) used by BOTH the plan card (`_bikeBlocks`, personal watts/HR) and Ride mode (`Ride.plan`/`ridePick`).
  `_bikeWeek(mon)` picks each ride day on read: long → endurance (≥60 min), Q=1–2 quality days by goal priority ×
  days since (sweet spot weekly, threshold/VO2 alternate), none the day after legs, no VO2/hills the day before,
  recovery weeks (wk 3) and high fatigue (TSB) → easy. Levels: synced `bike_levels` + `bike_level_log`, moved by
  `_bikeAfterRide` on Ride-mode finish (+ "How did it feel?" `rideFeel`). User goal: fitness & calories + faster; 45–60 min.
- **Live sync, one key at a time (v3.60).** `_liveSyncStart` (from `startSyncListener`) listens to
  `users/<uid>/data` child_added/changed/removed and applies each key via `_applyCloudKey` (shared with
  `loadFromCloud`; dirty keys kept; equality via `_rtdbNorm` so own echoes are no-ops). `loadFromCloud` reads only
  `data` + `updated`, never the whole account. `_autoPullIfNewer` just reconnects if needed. The old `updated`
  listener only runs if live sync didn't start. `strava_activities` is no longer a sync key (rides path instead;
  the old cloud copy is removed). `_markChosen` is skipped while applying cloud data (3.58–3.59 bug, cleared once).
- **Rides live in the cloud, one entry each (v3.59).** `users/<uid>/rides/<start minute>` (`_rideKey`). `_ridesListen`
  (from `startSyncListener`) loads them once, then child events merge into local `strava_activities` (`_ridesMerge`:
  twins = starts within 10 min + durations within 2 min, the intervals.icu copy wins). Any change to the local list
  pushes new/better rides (`_ridesPush`). Ride mode writes its ride on save (`job.act` → `_ridesAddLocal`).
  Pulled `strava_activities` blobs are merged, never replace. Worker v13 (`worker.js`, DEPLOYED 2026-10-03 with KV `training-brain-inbox` bound as TB_INBOX and cron `*/10 * * * *`; previous version 18 kept in Cloudflare for rollback) adds `/rides/register` + a Cron Trigger (`pollRides`) that PATCHes the same
  entries AS THE USER (v3.61: the app sends its Firebase refresh token; the Worker swaps it for an ID token, so
  rules apply and no admin key is needed). The app registers daily, only when the Worker replies `X-TB-Worker: 13`.
- **The week is worked out, not stored (v3.58).** `plan_<monday>` holds only what was chosen (generated
  week + your edits). `DB.get` of a plan key returns `_resolveWeek(base)`: logged days show what you did,
  missed gym days are SKIPPED, and if anything was missed/done differently the open gym days are re-chosen by
  `_gymCoverage`. Memoised on raw + `_factsVer` (bumped by every non-plan `DB.set`) + today. Never saved.
  Writers that save the week back bake it in, and days whose type they change get `chosen` (via `_markChosen`),
  which the resolver keeps fixed like `locked`. Whole-week rebuilds go through `_setFreshWeek` (no marks).
  Exercises for re-planned days: the moved session's, else `_autoExercises` (seeded `genSession`, cached in
  synced `auto_ex_<monday>`). `_baseWeek(mon)` reads the raw stored week.
- **Rides on gym days (v3.57)**: a ride never completes a gym day (`_dayWasDone`). Rides are fetched from
  intervals.icu on resume (5 min) and every 15 min while open (`_icuMaybeFetch`, per-device clock), so a
  ride saved on another phone shows up. "Make it a ride day" (week banner/day screen) and the ride
  screen share `_moveGymOffDay`.
- **Missed gym days (v3.56)**: the gym days left this week are re-chosen to cover the muscles
  still untrained (`_gymCoverage` + `_fillGymSlots` in `applyAutoSkipShift`): nothing done with 2
  days left → Upper + Legs, 1 left → Full Body, Push done + 2 left → Pull + Legs. Rides, rest,
  weather and logged days stay put; next week picks up misses via muscle recency. If the watch logs a different session
  than planned, the plan follows (`_followDoneType`).
- New weeks auto-build on open after the cloud pull (`_autoBuildWeek`). `genPlan` never
  fails (remembered location, no-weather fallback).
- **Ride mode (v3.50)**: `rRide` screen (S.screen `ride`, entry `_rideEntry` on today). Web Bluetooth to the
  Renpho bike (`Bike`, `_bikeFrame`/`_bikeFeed`/`_bikeLive`, protocol in `applewatch/BIKE_PROTOCOL.md`) plus a
  second device for heart rate (standard HR service). Records 1 s samples, uploads a TCX to intervals.icu
  (`_rideUpload`, pending copy in localStorage `ride_pending`), resistance +/- and hold-a-target-power.
  iPhone needs the Bluefy browser (Safari has no Web Bluetooth). Confirmed working on the real bike 2026-10-02 (data, HR strap, recording). v3.51: landscape layout (`.rd-grid` media query) and speed/distance computed from power (`_rideSpeedFor`, flat road + profile weight) because the bike's raw speed is flywheel speed (read 70+ km/h).
  v3.53: ride picker (today's workout / library `BIKE_PROGRAM_NAMES` via `_bikeProgram` / free ride with goal time|kcal|hr),
  goal panel (`_rideGoalHtml`), auto resistance (`_rideAutoTick`: step watts from FTP, or HR controller every 15 s),
  beeps on step change. Big tiles: HR, time, calories, watts. The user wants HR + time + calories, not speed.
  v3.54: HR guard in watt workouts (`Ride.hrCut`, personal HR zones from `_rideLthr` = 0.9 × max HR of the last year) and
  calories via `_rideKcalPerSec` (Keytel HR formula with a strap, else AI Gym's power × BMI factor × 1.1).
  v3.55: "Ride with my bike" entry on the week screen; after a ride on a gym day it offers to move that session (`rideMoveGym`).
- Rides: intervals.icu is the ride source (Apple Watch rides via an OAuth uploader app, Garmin via Garmin Connect). Strava is an optional source, used only while `_stravaWorking()` (token, not expired, API app active) — then alongside intervals.icu (v3.49). The Renpho app alone syncs nowhere, so such rides are logged manually (v3.48 ride card says so).
- Set logger: carry-forward, plates helper (barbell only), "last time"/"why this weight".
  Watch sets inherit phone weights (v3.42); ⌚ marks on watch sets; "Watch session live"
  card (v3.43).

### Watches ↔ app (via intervals.icu, key in the user's app settings)
- The app pushes each gym day as a WORKOUT event, `external_id` `tb-<date>`
  (`tb-<date>-x` for an extra session). Step text is like
  `- Bench Press 135lb x8 1s press lap`; sets ticked on the phone get `done` (before
  the duration on holds, e.g. `- Plank done 45s`).
- Watches send NOTE `tb-live-<date>-<session>` with
  `TB2;date;session;final(0/1);workout name;ex|w|unit|reps|flags;…`, which the app
  imports (`_watchApplyNote`, idempotent per `external_id@updated`). An empty note at
  start = "session started". Only ever touch `tb-*` events on the user's calendar.
- **Garmin epix Pro 51mm**: Connect IQ app 1.0.1, private beta on the Connect IQ store.
  Source is on the PC only (`C:\Users\htse\garmin-dev\tbwatch`), not in this repo.
- **Apple Watch Ultra**: `applewatch/` (SwiftUI, watchOS 10+, XcodeGen, watch-only app,
  HealthKit strength workout, Digital Crown for weight/reps, 15 s polling). CI:
  `.github/workflows/applewatch.yml` builds it on a GitHub Mac and pushes simulator
  screenshots to the `applewatch-shots` branch. Being installed on the user's MacBook Air
  M1 via Xcode (see `applewatch/README.md`).

### Open items
- User: paste `worker.js` (v12, AI proxy auth) into Cloudflare.
- User: remove the old USB-sideloaded Garmin copy (next USB connection, PC chat).
- Verify on real devices: Garmin heart rate, phone ticks skipping on the watch, week picker.
- Apple Watch: first install on the real watch; decide on the $99 Developer Program (TestFlight).
- Garmin free-Strength sessions: does intervals.icu keep sets? Waiting for Settings →
  Diagnostics → Inspect output; otherwise parse the original .FIT.
- Renpho bike: the AI Gym app syncs nowhere useful (only energy + distance to Apple Health), so
  Renpho-only rides never reach the app. Its Bluetooth protocol is now documented in
  `applewatch/BIKE_PROTOCOL.md` (private Mage Fitness service, NOT standard FTMS). Next: a ride
  mode in the Apple Watch app that connects to the bike, records the ride and uploads it to
  intervals.icu. Unverified against the real bike.

## Auto-publish rule (MANDATORY)

**After every meaningful change to `index.html`, commit AND push without being asked.**

This is a single-file PWA deployed via GitHub Pages from `main`. Uncommitted changes have zero user value — the user can only see the new version after it's deployed.

### What counts as "meaningful"
- A version bump (e.g. bumping `APP_VERSION` and adding to `CHANGELOG`)
- A new feature or screen
- A bug fix that addresses a user-reported issue
- A logical unit of work the user explicitly approved (e.g. "ship v2.X")

### What does NOT trigger auto-publish
- Exploratory reads / greps / file inspections
- Half-finished work mid-iteration (user is still tweaking)
- Failed builds or syntax errors
- Branch work (only auto-push to current branch, never force-push to `main`)

### Standard publish flow
Run from the repo root (works in either chat):
```bash
git pull --rebase
# edit index.html: bump APP_VERSION and add an entry at the top of the inline CHANGELOG
git add index.html
git commit -m "vX.Y: <one-line summary>

<2-4 line description of what changed and why>"
git push
```
Then update the "Current state" section above (version + what changed) and push that too.

Tell the user in plain words what changed and that the app shows a "New version ready —
Reload" bar (or pick it up on the next launch).

**Firebase copy:** https://training-631c1.web.app is NOT updated by a push. Only the local
PC chat can deploy it. If you shipped from the cloud chat, add
"deploy v<X.Y> to Firebase" to Open items so the PC chat does it next time.

**Can't test in a browser here?** Say so. At least check the JS still parses, e.g. extract
the main `<script>` and run `node --check` on it if node exists, before pushing.

### Verification after push
If the user reports not seeing the new version:
1. Check `git log origin/main --oneline -3` — confirm the commit is on remote
2. Check `curl -s https://raw.githubusercontent.com/nipshardaf/training-brain/main/index.html | grep APP_VERSION` — confirm GitHub has the file
3. Check `curl -sI https://nipshardaf.github.io/training-brain/index.html | grep -iE "last-modified|age"` — see if Pages CDN has refreshed
4. If raw shows new but Pages doesn't: it's a GitHub Pages deploy issue, not a push issue. Direct the user to Actions tab.

## Architecture

- Everything lives in `index.html` (~6000+ lines): HTML shell, all CSS, all JS, all data tables
- `sw.js` — service worker, stale-while-revalidate for `index.html` (Reload bar on a new version), cache-first for assets
- Storage: `localStorage` via `DB.get/set`, mirrored to Firebase via `_syncKeys` array in `saveToCloud`
- `S` — central state object (current screen, active log, etc.)
- `render()` — re-renders the current screen based on `S.screen`
- All log saves go through `_saveLog()` using `S.activeLogKey`

## Key storage keys
- `log_YYYY-MM-DD` — gym workout for that day
- `extralog_YYYY-MM-DD` — extra gym session stacked on a ride day
- `plan_YYYY-MM-DD` — weekly plan (key is Monday)
- `strava_activities` — stripped activity objects (see `_annotateRideLoad` for derived fields)
- `bike_fitness_curve` — `{date: {tss, ctl, atl, tsb}}` 120-day window
- `weight_log` — `{date: kg}` weigh-ins history
- `user_profile` — goals, FTP, weight, weight_goal, level, gender, activities[]

## When adding charts
- SVG with `viewBox="0 0 320 H"` + `preserveAspectRatio="none"` + `width:100%`
- Reuse `_regSlope()` for trend lines
- Use CSS vars: `var(--acc)` for accent, `var(--bord)` for grid, `var(--t2)` for secondary text
- Always include an empty state + a single-data-point graceful fallback
