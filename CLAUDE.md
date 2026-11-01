# Training Brain — Working Notes for Claude

### Where the files live (2026-10-19)
Everything was moved under `H:\AI`: the repo is `H:\AI\Training Brain\app`, the Blender
pipeline is `H:\AI\Training Brain\animation\blender`, approved demo videos are copied to
`H:\AI\Training Brain\demos`, and ComfyUI plus clipmaker live in `H:\AI\ComfyUI` (no space in that
path: a space breaks ComfyUI custom nodes). Copy at `H:\AI\Training Brain\docs\TRAINING_BRAIN_HANDOFF.md`.


## Current state — READ FIRST (updated 2026-10-02)

Two Claude chats work on this repo, and this section is how they stay in sync:
- **Local PC chat** ("Training Brain — Apple Watch app", runs on the user's Windows PC,
  reachable from Mac/iPhone via Remote Control). It has the Garmin Connect IQ SDK and
  simulator, the Firebase CLI, the user's Chrome (Garmin
  store uploads) and USB access to the Garmin watch. Watch builds
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


Also under `H:\AI`: the Garmin watch project is `H:\AI\watch` (no space: monkeyc and PowerShell
quoting), ComfyUI is `H:\AI\ComfyUI`, the retired Firebase redirect is
`H:\AI\Training Brain\firebase-hosting`, the Bluetooth adapter switch is `H:\AI\Training Brain\tools\bt-switch.ps1`.
`H:\AI\Training Brain\comfyui` and `watch` are junctions to those two, for browsing only.

### App — v3.96 (`index.html`)
- **v3.79 own 3D demo videos.** `EX_DEMO` (id → `assets/demo/<id>.mp4`, 900×500, silent loop) replaces the
  photo + "Animate" button on the exercise card (`rExList`) with `<video class="ex-vid" autoplay muted loop
  playsinline>`. First: `bb_squat`. Made in Blender from an MPFB (CC0) figure on the PC — scripts, hand-off and
  approvals in `C:\Users\htse\Downloads\Claude\exercise-test` (HANDOFF.md; render with
  `RES=900x500 LENS=34`). Only add an exercise after the user approves its video. sw.js skips `.mp4` (iOS
  Safari needs byte-range responses). Muted autoplay pauses while off screen (Chrome) — expected.
- Hosting: GitHub Pages from `main` only (auto on push). Since 2026-10-06 (user only uses GitHub)
  https://training-631c1.web.app is just a redirect page to GitHub Pages, plus a sw.js that
  clears old caches. Do NOT disable Firebase Hosting: authDomain training-631c1.firebaseapp.com
  serves the Google sign-in handler (/__/auth/handler).
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
  v3.67: real rides showed the bike NOT following the app (power tracked cadence at fixed torque; target ran to 400 W).
  v3.68: AI Gym sends 0x44 torque EVERY 1-s tick unconditionally (ca/f.T → r0 → F0, no dedupe); we only sent on change, so the bike (deposit on, knob dead) sat at its own resistance. Now sent every tick (erg, sprint, manual deposit). Unconfirmed on the bike yet.
  v3.69 CONFIRMED WORKING 2026-10-06 (user: "it's controlling it now"). Root cause: on iPhone/Bluefy, writes without response to the bike are silently dropped; writes WITH response work. Keep wmode resp.
  v3.69 history: user diag (10-06): name "RQ002", bike torque stuck at 12 (=gear 24 raw), asked 31, never any reply frames. Verified vs AI Gym: frame bytes, CRC, SLIP, UUIDs, write type (NO_RESPONSE), command set all identical; RQ002 handled same as others. Suspect iOS/Bluefy silently dropping no-response writes → now writes with response when allowed, swaps mode before giving up, logs every sent frame ("— sent —" in diag). 00 50 payload len 23: p19-20 mc_status, p21-22 mc_temper/10.
  v3.70: mid-ride "Change workout" (rideChangeOpen/_rideSwitch). Ride.progAt offsets the step clock, goalAt/goalKcal offset goals, name0 + " → " + new name; warm-up skipped when 5+ min in; leaving a workout = no level change (_bikeAfterRide uses the final prog only). "Make it easy" = free ride with the Easy HR goal + auto.
  v3.71: HR auto resistance reworked after user feedback (hard start, no adjusting in zone, "not allowing time to adjust"): targetW reset per ride (used to carry over!); start = 80% of learned bike_zone_watts[lo-hi] (else 1 W/kg); HR trend over 30 s projected 1 min; changes ≥30 s apart, ≥60 s same direction, +3/+6 up, −10/−20 down; HR mode holds a torque LEVEL (target W at 30-s avg cadence, ±0.5 N·m/s) instead of ERG watts; easy steps ≥5 min with a strap follow HR even with FTP (_rideHrLed). Sim: no overshoot, ~10 min to zone.
  v3.72: hrShift REMOVED (each +/knob click silently moved the HR band +5; user saw "keep 135–149" while it aimed 150–164). −/+ in HR mode = ±10 W now + 60-s hold (_rideHrNudge). v3.73: user wants the knob usable → 0x52 knob = ±5 W per click via _rideHrNudge (AI Gym also reads 0x52 as knob delta).
  v3.74: HR-goal rides start with a 5-min warm-up ramp: 70%→95% of _rideZoneW (learned bike_zone_watts), HR only lowers it (wuAdj −10/30 s over zone), nudges add to wuAdj. User: "dont kill me" but "dont need super easy… dont make it like 200w".
  v3.75: user data (intervals.icu): ~100 W at HR 129–137, LTHR 168. Zones now Easy .68–.75, Zone 2 .75–.85, Brisk .85–.92 of LTHR (was .68–.81/.81–.89/.89–.94; Zone 2 aimed 142 = 150–165 W). Steady Ride z [.75,.85]. _rideZoneInfo: median of last 8 rides (15+ min, 120 d) with avg HR in/near zone (else within 20 bpm), scaled 1.2%/bpm to zone mid, blended with learned bike_zone_watts2 (old bike_zone_watts with 165 W dropped). Shown on goal card. FIX: _icuToActivity read average_watts but intervals sends icu_average_watts → icu rides had no watts.
  v3.76: _rideLearnZones at finish: samples[6]=Ride.erg flag; only manual seconds (no erg in prior 60 s), after 5 min, HR within 4 of 30 s earlier, HR paired with 60-s avg power; ≥5 min in a band → bike_zone_watts2 (50/50 EMA, matched ±4 bpm via _rideLearnedFor); _rideZoneInfo = learned×0.7 + history×0.3. "Learned from this ride" card. _rideLthr prefers intervals.icu lthr (_lthr kept by _icuToActivity) over 90% of max HR (sandbox with 3 months gave 145 vs real 168).
  v3.80 (15 Oct ride: in zone at 80–90 W yet cut to 50 W, never came back): controller holds anywhere in [lo+2, hi−2] (pred = hr + slope/2, ±6); else ±5 W (±10 well outside) every ≥45 s, no up while slope ≥8; limits only stop changes (never push): floor 0.8·zW (0.6 when hr > hi), ceil 1.3·zW (1.5 when hr < lo); zW = wuW or _rideZoneW(zone) per zone key, nudges move zW; warm-up 70→100%. Sim (today-like / fitter / hot) 100% in zone.
  v3.81: review of 3.80 found (a) a render loop since v3.50: rRide → _rideContext → ridePick(auto) → _rideDraw → render() before #rd-pw exists → recursion ("Maximum call stack"); fixed: auto picks don't draw, _rideDraw.busy guard. (b) stale Ride.hrCut from a watt step shown as "eased off" during an HR-led step; now reset when _rideHrLed. Verified via real _rideTick loop + live site (0 errors).
  v3.82: phones planned different exercises/days because planner inputs were device-local: gym_profile + home_equip (exAvail), week_capacity_<mon>, home_day_<date>. Now synced (SYNC_KEYS / _isSyncKey prefixes) + one-time upload after first pull (settings_sync_v382) of local ones missing from the cloud. If phones still differ: check both show the same version + 'Synced' line (plan_ itself always synced).
  v3.83: _orderByTier = tier (primary compound rank≤3 / accessory / core) → muscle size _G_RANK (legs 1, back+chest 2, shoulder 3, delts 4, arms 5, calf 6, core 8; hback_h too) → same-muscle grouped → chest lead (_chestLead: opposite angle of last logged chest press) → slot order. _pairChest: never two same-angle or two barbell chest presses; on normal PUSH days a chest fly becomes the complementary press. PUSH SLOTS slot 1/3 accept either angle.
  v3.84: AI Coach (aiCoachWeek/rCoachCard): prompt = goals + 8-week best set per exercise with trend + sets/muscle/week (4 wk) + recovery + riding + bodyweight + days + equipment-filtered EX; JSON answer → validated (real/available ids, no dupes, 3–8, home-day equipment, isolation-before-compound moved via _coachOrder) → plan day exercises + exPlan {sets,reps,note} (shown on exercise cards) + synced coachweek_<mon> review (card replaces Weekly Advisor). Runs for new weeks via upgradeWeekExercisesWithAI (old slot AI only if it fails) and once per device per week after the pull (coach_auto_<mon>). Worker v14: DeepSeek (DEEPSEEK_KEY secret, deepseek-chat) after Gemini; fallbacks honour maxOutputTokens (≤8000). Worker v16 DEPLOYED 2026-10-20 (pasted via the dashboard editor; API writes from page fetch get a 403 challenge). v15: accepts DEEPSEEK_KEY or Deepseek_KEY (the user saved it as Deepseek_KEY), X-TB-AI reply header names the provider, X-TB-Try: deepseek skips Gemini for testing. v16: an all-failed 429 carries X-TB-AI-Err (e.g. deepseek:401). Tested 2026-10-20: Gemini OK, DeepSeek OK (secret Deepseek_KEY).
  v3.85: ride load rescaled to the app FTP (_icuToActivity keeps _icuTss/_icuIf/_icuFtp; _annotateRideLoad scales by (icuFtp/ftp)^2 for rides with watts; intervals.icu had FTP 250 vs app 145, so every ride counted ~1/3). Ride sample [7] = auto still finding watts (Ride.steadyFrom: set when the HR controller holds, reset on change/warm-up/nudge/switch/toggle); _rideLearnZones skips on [7] (old rides: [6]), so picked ERG watts and 2+ min steady auto now teach Zone 2 (bike_zone_watts2 had stayed empty). HR controller: hrHist kept 150 s; drift rule eases 5 W from hi-4 when the 2-min slope >=1 and hr+3*slope2 > hi (sim: no mid-zone easing, slow drift peaks 141).
  v3.86: rideAutoToggle on mid-ride (HR mode) starts targetW from the last 30 s of power (was: targetW 0 -> 70% of zone watts, no warm-up). Ride.dbg: once a minute [min, auto, targetW, lastTq, bike torque, hr, ctlLost, ctlTries] + toggle markers, saved at finish as synced key ride_debug - read it after a ride that felt wrong. 21 Oct ride (manual then auto): bike torque level stayed ~11.4 Nm all ride (watts tracked cadence), so auto never changed the level; cause unproven (start-from-scratch path or control not taken) - check ride_debug next time.
  v3.87: _resolveWeek gives re-planned days a `why` (owed = missed sessions not made up) shown on the week row + day hero; a coverage FULL_BODY with part of the week trained uses _fbFocus (owed sessions, e.g. Push done -> Pull + Legs) and _autoExercises(ds,t,trained) picks distinct movements per owed session (5 or 3+3) + core; an already-stored FULL_BODY without why/_aiGen is re-focused too. coachweek.types {date:type}; _coachReplanCheck (from rCoachCard, throttled 60 s, and after the cloud pull) re-runs aiCoachWeek for open gym days whose type differs (local flag coach_rp_<date+type>), prompt marks RE-PLANNED + why. Ask Coach: FULL_BODY exercises listed, SKIPPED shown as "Skipped (planned X)", day names + TOMORROW, why, last gym session gap, this week's coach review, planner explanation, no invented days, 1200 tokens, recommendation + tool call; FULL_BODY in tool enums. 22 Oct: chat said "Push day planned for tomorrow" (it was Full Body) and "well-rested" after 2 weeks off.
  v3.88: iPhone keyboard covered bottom sheets (.swap-sheet, e.g. Log sets). visualViewport listener sets --kb (innerHeight - vv.height - vv.offsetTop, >60) and --vvh (if >200); .swap-modal .swap-sheet uses bottom:var(--kb) + max-height min(80vh, vvh-24); focusin in a sheet scrolls the field to centre after 350 ms. Set inputs autocomplete=off (iOS offered AutoFill Contact). Untested on a real iPhone; desktop test with forced --kb OK.
  v3.89: named machines. le.mach on log entries ('' = none, all old logs); synced gym_machines {gymId:[{n,ex}]}, ex_mach_last {gymId|exId: name}, prs_mach {exId@name}. getLastLog/_lastDoneSets/computeProgressionTarget/makeSets take mach (default _machDefault = last used at this gym); _leMach sets it lazily on render; checkPR(id,w,r,mach) writes prs_mach for named machines. Chips (_machChipsHtml: "Name this machine" / Machine: names + Other + ＋ via prompt) in the Log sets sheet and rLogEx; pickMach re-prefills undone sets. Gyms (GYMS_BUILTIN) only carry equipment tiers, no machine lists: the user fills their GoodLife list as they go (22 Oct: Dual Pulley Pulldown read 130 vs 100 on another pulldown).
  v3.90: EX mach_lat_raise (Machine Lateral Raise, sdelt, photo Seated_Side_Lateral_Raise; no machine-lateral image in free-exercise-db) in EX_EQUIP + the 3 lateral-delt SLOTS. removeSet(ei): button "− Remove set" beside + Add set (log screen + Log sets sheet), removes the last unticked set (confirm if all ticked / only set), _undoBar (own fixed bar above --kb, 7 s; showToast is textContent) + undoRemoveSet.
  v3.96 (cloud chat): EXERCISE LIBRARY + REVIEW FIXES. EX 120 -> 185 (65 built-in machines/stations: Smith, plate-loaded/pin-loaded, cable, landmine, trap bar, kettlebell, DB home options; photos = free-exercise-db folders checked against its dist/exercises.json, p:null = placeholder; EX.k = extra search words, older entries get k via a small map after EX_EQUIP). Every EX has an EX_CUES line. New equipment tags smith/trap_bar/landmine/back_ext/band/medicine_ball/stability_ball in EQUIP_ALL and the _F/_B/_P/_Y gym sets; LIB_EQ maps library bands/balls/'other' (other = unknown kit: exAvail and the My gym filter allow it, Bodyweight filter doesn't). SLOT_MORE (same indexes as SLOTS) = extra options per slot: filterSlot(slot,bwOnly,more,strict) tries main-available, then more, then bodyweight; genSession passes strict (a slot nothing can fill is skipped, never an unavailable exercise) and drops already-picked ids first; _slotCandidates (old AI exercise picks) = main + available extras, empty slots dropped; getAlternatives lists main+extras minus today's exercises, same-muscle shows 6. GoodLife rotation unchanged (tested: 0 extras used); Planet/Fit4Less/dumbbell home now 0 unavailable picks. CHEST_PRESS includes machine ('mc') and Smith ('sm') presses. EX.hide = kept for old logs, left out of lists/coach/name matching: cable_kickback (duplicate of glute_kick, whose photo is now the cable one; UNILATERAL_MAP hip_thrust -> glute_kick) and adopted ex_extra entries whose photo matches a built-in. _EX_ALIASES has gym shorthand. _fillTickedSet: ticking a blank set fills reps (low end of energyTargets reps) and sugW. sw.js tb-v7: only same-origin + STATIC_HOSTS (jsDelivr, yuhonas, wger, wikimedia, gstatic) are cached; everything else (intervals.icu, Open-Meteo, Endurain, Worker, Firebase) goes to the network (the old denylist served API GETs cache-first); jsDelivr exercise photos go to the cache-forever branch. database.rules.json gains users/$uid/rides (app + Worker write there; the repo rules had no write rule for it); a refused ride upload is saved in local rides_cloud_err and shown in Settings > Advanced > Diagnostics. startLog keys the log by its ds. Usage panel labels ask_coach.
  v3.95 (cloud chat): FEWER AI MOMENTS. Week screen shows only rCoachCard (+ rAskCoach); rReviewCard, rWeeklyAdvisor, rReview, generateWeeklyReview and loadWeeklyAdvisor are still in the file but no longer rendered (the 'review' screen is unreachable; rLogEx/togSet still read cached weekly_advisor_ targets if present). emailWeeklyReview(mk) emails coachweek_<mk>.review (escaped) and its button sits on the coach card only when review_email + emailjs_service/template/key are all set; Settings text says so (there never was an automatic Sunday email). Daily note: getAICoach asks the AI only when _coachNoteReason(energy,ct,dp) finds something (tired/sore, dp.why, getLayoffDays >= 7, latest TSB < -20, a gym-day lift with no gain over its last 3 sessions via _dbHist); otherwise built-in coachMsg + a .quiet-note line (S._coachQuiet). bindEnergy drops stale replies (S.energy check) and clears the quiet line on each tap. The gym path still skips the AI when today's lifts have no PRs/history (older rule). AI usage panel labels coach_week, debrief, week_exercise_gen, next_week_plan.
  v3.94 (cloud chat): DEBRIEFS. Facts by rules, words by AI. Gym: _gymDebriefFacts(key) (best set per exercise by e1RM, assisted = less is better, same machine only; trend vs last session, stalled = no gain over 3 sessions, PR today) → _gymDebrief(key) stores log.debrief {at,facts,ai,err,pending}; triggered by completeWk and by final watch notes (_watchApplyNote loop). AI next-time targets validated against today's ids → synced debrief_next {exId:{target,why,date}} shown by _dbNextHtml on later exercise cards (rExList). Ride: _rideDebriefFacts (5-min blocks, HR drift after 10 min = power/HR first vs second half, usual watts = median of past 60 d rides within ±5 bpm, time in HR band, level note, ctl trouble from Ride.dbg) → synced ride_debriefs {startISO:…} (max 20), started in rideFinish, shown in rd-after. Shared _debriefAsk (_proxyFetch, JSON, trackAICall 'debrief'), _debriefCard, _weekDebriefs (today, dismiss → local debrief_seen), _dayDebriefs(ds) under the day hero, debriefRetry. SETTINGS regrouped (.set-grp): Gym · Bike (ride pref, cycling setup, ride sync) · Watches · Account (account, friends, language) · About (about, what's new); <details class=set-adv> Advanced = AI coach/usage, weekly email, Vitruvian, Diagnostics (open state S._advOpen).
  v3.93 (cloud chat, from a whole-app review): GYM_TYPES/_isGym is the ONE list of gym session types (use it; GYM_SEQ is only the rotation order). ~15 copies, half missing FULL_BODY → rDay showed no exercises/Log on Full Body days, getMissedLastWeek/checkWeekCompletion/openAddGymSheet/addGymToRideDay/bindEnergy ignored it. Placeholder weather now carries nowx:true; _wxFake(w) (also matches old unflagged 15/5/0/10/1/0 placeholders) hides the weather line, and the ride verdict badge only shows on OUTDOOR rides with real weather (was red 'Gym day' on indoor rides); AI prompts skip fake weather. CSS body:has(.swap-modal.on) #_toast moves toasts to the top while a sheet is open. Review also found: repo database.rules.json has no users/$uid/rides rule though the app writes there — confirm live rules in the Firebase console; generateWeeklyReview renders AI text unescaped (s.v).
  v3.92 (cloud chat): user got lost on the idle Ride screen. Idle = checklist: stepH '1 · Connect your bike · heart rate optional' (✓ when Bike.status on), picker title '2 · What are you riding?'; #rd-live tiles and #rd-res hidden until the bike is connected; main button = 'Connect the bike to start' (bikeConnect) until connected, then 'Start <workout> · N min'; small link 'Start without the bike'.
  v3.91 (cloud chat): Ride screen on a day with no planned ride used to open on a bare Free ride ("not much suggested"). _bikeTodayPicks() runs the _bikeWeek rules for TODAY: hold easy if form < -30 (Easy Spin), recovery week, legs/full body yesterday or today, hard ride yesterday, a planned quality day tomorrow, this week's quality quota done or covered by a later planned day (names it); else the most-needed quality type (prio × days since, no vo2/hills before legs, a level down if form < -20). Returns top + 1–2 alternatives with a why each; a hard "Feeling fresh?" option only when the hold is just the weekly count. ridePick('sug',i) / _rideWorkoutFor (shared by ridePick and _rideSwitch); Ride.prog.sug marks the pick; _rideContext auto-picks sug 0 instead of free. Library list renamed "All 8 workouts". _rideEntry shows Today/Suggested workout name. Bike workouts are rules, not AI (the AI coach only plans gym exercises) — the user asked.
  v3.77: exercise library = full free-exercise-db (876, LIB_URL jsDelivr dist/exercises.json, slim cache localStorage exlib_v1). _libEntry maps muscles→g (LIB_G) and equipment (LIB_EQ); ids x_<db id>; _exAdopt puts it in EX + synced ex_extra (merged each render by _exExtraMerge; EX entries flagged x:1, kept out of planner SLOTS and coach menu). Swap sheet: SWAP_G muscle chips + SWAP_EQ equipment select ("My gym" default), _swapResults lists your exercises then library ("NEW"). openExAdd/doExAdd: "＋ Add an exercise" under main gym day. Muscle map _mmHtml/_muscleMapSvg (front/back SVG) on every exercise card; muscles from library (_libAttachMuscles) else parsed from EX.m. Also synced bike_zone_watts2. User declined step-by-step instructions for now; considering AI-generated/3D demo guides (offered: licensed ExerciseDB-style set, Blender mannequin loops for top 30–40, AI image-to-video from existing frames).
  v3.78: rRecoveryMap under the current week plan: _muscleLoad = last 4 days of done sets (primary 1, secondary 0.5 via _exMuscles) decaying linearly over 72 h (48 h for _MU_FAST), logs timed 6 pm, plus rides (TSS/25 → quads 1, glutes .6, hams .4, calves .4). worked ≥5, recovering ≥1.5. _muscleMapSvg takes colFn. User chose only the recovery map (not weekly sets / today-trains / planner use). Copyright: free-exercise-db labelled Unlicense but photos/text likely from a commercial site upstream; wger CC-BY-SA + 2 Wikimedia need credits; fine for personal use, replace photos before any public launch.
  Start now = AI Gym order (46 00, 45 01, [N: 44 00], 40 00 02), control re-sent at start/resume; `_rideErg` compares
  bike-reported torque with `lastTq`, retakes control after 5 s off (max 3, then `ctlLost` banner); HR controller capped
  at bike watts + 30 and the torque ceiling; panel shows actual watts + target + ↑/↓. Root cause still unconfirmed.
  v3.66: `_rideSame` also = overlap ≥ 60% of the longer ride (watch + Ride mode recording one session); `_rideRank`
  keeps the copy with power, then icu; `_ridesDedupe` runs on intervals.icu/Endurain fetches, cloud merges and pushes.
  v3.65: FTP test (`_ftpTestProgram`: warm-up 5 min, ramp +8% est. FTP/min (10–25 W), ends at >20 W short for 15 s or
  "I'm done"; FTP = 0.75 × reached, `rideTestSave` → user_profile.ftp + ftp_tested; picker nudges if no FTP or >8 wks).
  Steps with `w` = plain watts. HR-goal rides aim for the band middle; − / + shift the band ±5 bpm + 10 W (`hrShift`),
  10 W in watt workouts, ±1.5 torque in manual. Free-ride HR chips use LTHR zones. R-Q002 N: `00 44 00` at start.
  v3.64: `BIKE_GOALS` (synced `bike_goal`, default "comfort" = ride 2–3 h comfortably: 1 quality/wk unless 5+ rides,
  rotation Brisk → Steady Push → Hill Climbs; "faster" = old mix). Long ride = longest ride of last 3 weeks + 15 min
  (`_bikeLongMins`, cap 180 outdoor / 90 indoor) with fuel/pacing tips. Plain names (Easy Spin, Steady Ride, Brisk Ride,
  Steady Push, Hard Push, Short Bursts, Hill Climbs, Spins & Sprints) + `short`/`feel` (talk test); internal keys unchanged.
  Week ranking ignores this week's log entries (stable); ridden days show what was done.
  v3.63 Renpho tuning (`_rideErg`): a new step jumps straight to its torque (no 1-step/s ramp); sprint steps (lo≥1.3)
  get one fixed torque for ~100 rpm; stall guard eases the target 10%/4 s (max 30%) under 60 rpm (50 on climbs) and
  counts as easing for levels; hill cadence rises so the target fits the bike's 40-torque cap (≈272 W at 65 rpm).
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
- PC chat: deploy database.rules.json (`firebase deploy --only database`). It now has the users/$uid/rides write rule the app and Worker need; if the live rules lack it, ride uploads to the cloud are refused (Settings > Advanced > Diagnostics shows it).
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

**Firebase copy:** retired 2026-10-06. Don't deploy the app there; the web.app site only redirects.

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
