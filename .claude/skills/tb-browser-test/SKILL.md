---
name: tb-browser-test
description: Test the Training Brain PWA (index.html in the training-brain repo) in a headless Chromium with Playwright - serve a local copy, load a realistic fixture with a frozen clock, stub the AI and the iPhone native bridge, drive screens and functions, and read errors and screenshots. Use this whenever you change app behaviour and want to see it actually work before shipping (screens, planner picks, logging sets, swaps, check-in, rest timer, AI cards, backup/export), when the user reports something broken in the app, or when you'd otherwise only run node --check.
---

# Testing Training Brain in a browser

There are no unit tests: the app is one big `index.html` and its functions are globals, so the
reliable check is to load it in Chromium, seed localStorage, and call the same functions the
buttons call. `node --check` only proves it parses.

## Setup (cloud sandbox)
- Chromium and Playwright are preinstalled (`require('playwright')`; if that fails,
  `/opt/node22/lib/node_modules/playwright`). Run node with `PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers`.
  Never run `playwright install`.
- Serve a copy from a scratch folder, because the app expects the `/training-brain/` path:
  ```bash
  mkdir -p $SCRATCH/site/training-brain && cp index.html sw.js $SCRATCH/site/training-brain/
  (cd $SCRATCH/site && nohup python3 -m http.server 8765 >/dev/null 2>&1 &)
  ```
  Copy index.html again after every edit. Stop it with `pkill -f "[h]ttp.server 8765"`
  (the brackets stop pkill from matching your own shell).
- On the PC (Windows) chat, install Playwright and Chromium first if they are missing.

## Run the smoke test first
`node .claude/skills/tb-browser-test/scripts/smoke.cjs [url] [outdir]` walks the week, every
day, the log screen, a set tick, the swap and add sheets, finishing a workout, My Training,
Settings (Advanced open) and Ride, then prints a JSON report and saves two screenshots. It
exits 1 if any screen shows the "Something went wrong" error boundary or the page threw.

## Writing a focused test
Copy the pattern in `scripts/smoke.cjs`:
1. `page.addInitScript({path: seed.js})` then `addInitScript(() => window.__seed({native:true}))`.
   The fixture (`scripts/seed.js`) freezes the clock at Wed 4 Nov 2026 09:00 and seeds a GoodLife
   account with three weeks of logs, rides, this week's plan and an AI Coach review. Change it
   per test (for example, add logs to make a lift stall).
2. After load: set `S.authed=true; S.fbUser={uid:'u'}; S.guest=false`, and remove
   `.swap-modal` (the once-a-week gym-day picker covers the page and blocks clicks).
3. Stub the AI by replacing `window._proxyFetch`. Match the reply shape the caller reads:
   - daily coach note (`getAICoach`) reads `r.text()`, then candidate text like
     `FRESH: ...\nOKAY: ...\nTIRED: ...\nSORE: ...`
   - AI Coach week plan, debriefs and most others read `r.json()` with
     `{candidates:[{content:{parts:[{text:'<json string>'}]}}]}`
4. With `__seed({native:true})`, every message to the iPhone app (`_tbNative`) lands in
   `window._native` (alarms, cancels, share sheet).
5. Drive it with the app's own functions: `go('week'|'prs'|'settings'|'ride')`, `openDay(ds)`,
   `startLog(ds)`, `togSet(ei,si)`, `openExSwap(id,i,ds,type)`, `openExAdd(ds,type)`,
   `filterSwap(...)`, `_swapSetF('eq','smith')`, `completeWk()`, `setCheckin('tired')`,
   `genSession(type,'okay',false,seed)`, `getAlternatives(id,type)`, `exportData()`.
6. Read state with `DB.get(key)`, the DOM, and `page.screenshot` (look at it with Read).

## Gotchas we hit
- `innerText` follows CSS `text-transform: uppercase`: match headings case-insensitively.
- `position:fixed` elements have no `offsetParent`; measure with `getBoundingClientRect()`.
- The fixture freezes `Date.now()`, so countdowns never move: set the end time in the past
  and call the tick function instead of waiting.
- The sandbox blocks jsDelivr, gstatic and Firebase: the 870-exercise library won't load
  ("Couldn't load the full library") and there is no real sign-in. That's expected.
- `DB.get('plan_<monday>')` returns the resolved week, not the stored one; writes bake it in.
- Debriefs and progression ignore sets with no reps; a ticked blank set is filled from the
  shown target since v3.96, so fixtures with real numbers test more.
- A test that "fails" can be the fixture's fault (missing weather object, wrong reply shape,
  an exercise with only named-machine history). Fix the test, never the app, until you've
  confirmed the app is wrong.

## Report
Say what you ran and what passed, show the key numbers, and say plainly what wasn't tested
(usually: a real iPhone, Bluetooth, Firebase sync).
