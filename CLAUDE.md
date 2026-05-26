# Training Brain — Working Notes for Claude

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
```bash
git -C "C:\Users\htse\training-brain" add index.html
git -C "C:\Users\htse\training-brain" commit -m "$(cat <<'EOF'
vX.Y: <one-line summary>

<2-4 line description of what changed and why>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
git -C "C:\Users\htse\training-brain" push
```

Then briefly confirm with the user: `Shipped — <short-hash>` plus a one-line note about what they should see after reload.

### Verification after push
If the user reports not seeing the new version:
1. Check `git log origin/main --oneline -3` — confirm the commit is on remote
2. Check `curl -s https://raw.githubusercontent.com/nipshardaf/training-brain/main/index.html | grep APP_VERSION` — confirm GitHub has the file
3. Check `curl -sI https://nipshardaf.github.io/training-brain/index.html | grep -iE "last-modified|age"` — see if Pages CDN has refreshed
4. If raw shows new but Pages doesn't: it's a GitHub Pages deploy issue, not a push issue. Direct the user to Actions tab.

## Architecture

- Everything lives in `index.html` (~6000+ lines): HTML shell, all CSS, all JS, all data tables
- `sw.js` — service worker, network-first for `index.html`, cache-first for assets
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
