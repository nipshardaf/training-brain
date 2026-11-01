---
name: tb-ship
description: Ship a new version of the Training Brain app (single-file PWA index.html on GitHub Pages, plus sw.js and the iphone/ app) the way this repo expects - version bump, in-app changelog, syntax check, CLAUDE.md current-state note, commit, push to main, verify, and a plain-words report to Hugo. Use this whenever a change to index.html, sw.js or iphone/ in the training-brain repo is ready for the user, or the user says ship it, publish, deploy, push it live, release, make it live, or asks why they don't see the new version, even if they don't list the steps.
---

# Shipping Training Brain

The app is one file, `index.html`, served by GitHub Pages from `main`. Nothing reaches
Hugo's phone until it is pushed, so a finished change always ends with a push. Two Claude
chats work on this repo (the PC chat and the cloud chat) and the "Current state" section of
`CLAUDE.md` is how they stay in sync, so every ship updates it in the same push.

## Steps

1. **Start from the latest main.** `git pull --rebase origin main`. If you have local edits,
   commit them first or the rebase refuses. Shipping goes straight to `main` (Hugo chose this);
   never force-push it.

2. **Bump the version and add a changelog entry** in `index.html`:
   - `const APP_VERSION='3.99';` becomes the next number (3.99 then 4.00 style; ask if unsure).
   - Add one object at the TOP of `const CHANGELOG=[`:
     `{v:'X.YZ',d:'one-line summary',det:'what changed and why, in plain words'},`
   - `d` and `det` are shown to Hugo in the app ("What's new"), so write them for him:
     plain words, no jargon, no em dashes (see the my-writing-style skill), escape `'` as `\'`.
   - The service worker compares `APP_VERSION`, so a bump is what shows the
     "New version ready" bar. A text-only fix to something shipped minutes ago can skip it.

3. **Check the script still parses** (there is no build step to catch mistakes):
   ```bash
   python3 - <<'EOF' > /tmp/tb-main.js
   import re
   s=open('index.html',encoding='utf-8').read()
   print(max(re.findall(r'<script(?![^>]*src)[^>]*>(.*?)</script>',s,re.S),key=len))
   EOF
   node --check /tmp/tb-main.js && echo SYNTAX_OK
   ```
   Also `node --check sw.js` if you touched it, and validate `database.rules.json` with
   `python3 -c "import json;json.load(open('database.rules.json'))"` if you touched it.
   For behaviour, test in a browser first (tb-browser-test skill).

4. **Update CLAUDE.md "Current state"**:
   - The heading `### App — vX.YZ (\`index.html\`)` gets the new number.
   - Add a dense note for the next chat ABOVE the previous version's note, starting
     `  vX.YZ (cloud chat):` or `(PC chat)`: function names, storage keys (say which are synced),
     rules and numbers, what was tested, what is unverified. Future chats rely on this.
   - Update "Open items" when something now waits on Hugo or the PC chat.

5. **Commit and push.**
   ```bash
   git add index.html CLAUDE.md   # plus sw.js, iphone/..., assets/... if changed
   git commit -F - <<'EOF'
   vX.YZ: one-line summary

   2-4 lines on what changed and why.

   <attribution lines from the session's system reminder, if it gives any>
   EOF
   git push origin main
   ```
   If you're on another branch after a resume: `git push origin HEAD:main`, then
   `git checkout main && git merge --ff-only origin/main`.

6. **Verify.** `git fetch -q origin main && git show origin/main:index.html | grep -o "APP_VERSION='[0-9.]*'"`.
   Don't trust raw.githubusercontent.com for this (it caches) and don't expect to reach
   nipshardaf.github.io from the cloud sandbox (it's blocked there).
   If `iphone/` changed, a GitHub Mac build runs (`.github/workflows/iphone.yml`) and publishes
   the `iphone-latest` release; watch it as the tb-iphone-bridge skill describes.

7. **Tell Hugo** in plain words, short (my-writing-style skill): what changed for him, that the
   app shows a "New version ready" bar (or updates on next launch), what you tested, and what
   you could not test (usually: not on his phone). If the iPhone app changed, tell him to update
   it in SideStore once the build is published.

## Things that bit us before
- The repo is public: never commit secrets, API keys or Hugo's training data (backups, logs).
- `git pull --rebase` with uncommitted edits fails; commit first.
- `pkill -f "http.server 8765"` kills your own shell; use `pkill -f "[h]ttp.server 8765"`.
- Big edits to the ~1.1 MB index.html: use exact-string replacements (Python with an
  `assert s.count(old)==1`, or the Edit tool) so a near-miss can't land in the wrong place.
