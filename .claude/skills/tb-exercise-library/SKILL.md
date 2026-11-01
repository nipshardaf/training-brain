---
name: tb-exercise-library
description: Add, fix, rename, hide or re-group exercises and gym machines in Training Brain's built-in exercise library (the EX table in index.html) and wire them into everything that reads it - equipment tags and gym presets, planner slots and their extra options, chest-press pairing, search words, form cues, photos, the unilateral tool and name matching for imports. Use this whenever Hugo mentions a missing exercise or machine, a wrong or missing photo, an exercise in the wrong muscle group, gym equipment, or swaps/search/the AI coach not offering something, even if he doesn't say "library".
---

# Changing the exercise library

Everything about an exercise lives in `index.html` as plain data tables. The planner, the swap
sheet, search, the AI coach's menu, set logging, the watch push and imports all read the same
tables, so one missing piece shows up as a bug somewhere else. Work through the list below,
then run the checker.

## Where an exercise is defined
1. **`EX`** (`const EX = {`): `id: {n, g, t, sets, reps, rpe, m, p, ...}`
   - `n` name: no apostrophes (they break onclick strings) and avoid digits (intervals.icu
     reads "45" in step text as a duration). Write "Farmers Walk", "Back Extension".
   - `g` group: chest, shoulder, sdelt, rdelt, tri, bi, vback, hback, hback_h, quad, ham,
     glute, calf, core, foot. It drives the muscle rank (`_G_RANK`), ordering and swaps.
   - `t`: 'C' compound or 'I' isolation. `sets`, `reps` ('8–10', '12/side', '45s'), `rpe`.
   - `m` muscles label ("Chest · Triceps"); the muscle map parses it when there's no photo match.
   - `p` photo: a free-exercise-db folder id (checked against its `dist/exercises.json`), an
     array of image URLs (wger, wikimedia, or our own `assets/ex/<id>.webp`), or `null` for the
     coloured placeholder (then add it to `assets/ex/README.md`, the picture job list).
   - Flags: `uni` one side at a time (logged L/R), `bw` bodyweight, `assist` assisted machine
     (lower weight = stronger), `k` extra search words ("hammer strength plate loaded"),
     `hide:1` keep for old logs but leave out of lists, the coach and name matching.
2. **`EX_EQUIP`**: tag list; ALL tags must be in the gym's set for the exercise to be offered.
   Tags: barbell, dumbbell, ez_bar, bench, incline_bench, rack, cable, machine, pullup_bar,
   dip_bar, kettlebell, ab_wheel, bodyweight, smith, trap_bar, landmine, back_ext, band,
   medicine_ball, stability_ball. A new tag also goes in `EQUIP_ALL` (home picker label) and in
   the gym presets `_F` (full gym), `_B` (budget), `_P` (Planet), `_Y` (YMCA) that have it.
3. **`EX_CUES`**: one plain-words form cue per exercise (every entry has one).
4. Optional: `EX_ZH` Chinese name (falls back to English), `EX_COACH_TIPS`.

## Where the planner uses it
- **`SLOTS`** = the normal rotation per session type. Adding here changes everyone's plans:
  avoid unless it is a core exercise. The no-AI rules keep main lifts (`SLOT_ANCHOR` slots)
  stable while they progress, prefer full-stretch isolation (`LEN_BIAS`) and force a leg curl
  (`LEG_CURLS`) on leg days.
- **`SLOT_MORE`** = extra options per slot (same indexes as SLOTS). Used when the gym lacks
  the main options, listed under "Same movement slot" in swaps, and offered to the old AI picker.
  This is the right place for most machines and variants.
- **`CHEST_PRESS`**: any chest press must be listed with its angle (flat/incline/decline) and
  kind (bb, db, bw, mc machine, sm Smith) so two presses never share an angle.
- **`UNILATERAL_MAP`**: bilateral leg exercise -> its single-leg version (Ask Coach tool).
- **`_EX_ALIASES`**: gym shorthand -> id for pasted/imported names ("pec fly" -> pec_deck).
- The AI coach's menu is automatic: every EX entry without `x` or `hide` the gym can do.
- Library exercises adopted from free-exercise-db get `x_` ids and live in synced `ex_extra`.

## Check before shipping
```bash
curl -sS -o /tmp/exercises.json https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json
node .claude/skills/tb-exercise-library/scripts/refcheck.cjs index.html /tmp/exercises.json
```
It reports missing fields, tags or cues, unknown ids in any table, SLOT_MORE/SLOTS mismatches,
duplicate visible names and photo folders that don't exist. Then test planner picks at a few
gyms (tb-browser-test skill): `genSession(type,'okay',false,'seed'+i)` for i in 0..39 with
`gym_profile` set to `goodlife_bloor_bay`, `planet_toronto_north`, `fit4less_etobicoke` and
`home`, and assert every pick passes `exAvail(id)`. Ship with the tb-ship skill.

To find a photo, search the library list by name, e.g.
`python3 -c "import json,re,sys;[print(x['id'],'|',x['name'],'|',x.get('equipment')) for x in json.load(open('/tmp/exercises.json')) if re.search(sys.argv[1],x['name'],re.I)]" "smith|leverage"`.
