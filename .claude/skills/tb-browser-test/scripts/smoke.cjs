// Walk every Training Brain screen with the seed fixture and report anything broken.
// Usage: node smoke.cjs [url] [outdir]
//   url    default http://localhost:8765/training-brain/index.html (serve a copy, see SKILL.md)
//   outdir where screenshots go (default: current directory)
// Prints a JSON report; exits 1 if a screen hit the error boundary or the page threw.
let pw; try { pw = require('playwright'); } catch (_) { pw = require('/opt/node22/lib/node_modules/playwright'); }
const path = require('path');
const URL = process.argv[2] || 'http://localhost:8765/training-brain/index.html';
const OUT = process.argv[3] || '.';
(async () => {
  const b = await pw.chromium.launch();
  const pg = await b.newPage({ viewport: { width: 390, height: 844 } });
  const errs = [], cons = [];
  pg.on('pageerror', e => errs.push(e.message));
  pg.on('console', m => { if (m.type() === 'error' && !/net::|Failed to load resource|ERR_|favicon/.test(m.text())) cons.push(m.text().slice(0, 200)); });
  await pg.addInitScript({ path: path.join(__dirname, 'seed.js') });
  await pg.addInitScript(() => window.__seed({ native: true }));
  await pg.goto(URL, { waitUntil: 'load' }); await pg.waitForTimeout(2500);
  const ev = (f, a) => pg.evaluate(f, a);
  // Signed-in state without Firebase; the AI answers through a stub (no network to the Worker).
  await ev(() => {
    S.authed = true; S.fbUser = { uid: 'u', email: 'test@example.com' }; S.guest = false;
    document.querySelectorAll('.swap-modal').forEach(x => x.remove()); // the weekly gym-day picker
    window._calls = 0;
    window._proxyFetch = async () => { window._calls++;
      const body = JSON.stringify({ candidates: [{ content: { parts: [{ text: '{"headline":"ok","notes":[],"next":[]}' }] } }] });
      return { ok: true, status: 200, headers: { get: () => null }, text: async () => body, json: async () => JSON.parse(body) }; };
  });
  const out = {};
  const screen = async (name, fn, arg) => {
    try { await ev(fn, arg); await pg.waitForTimeout(500);
      const t = await ev(() => { const s = document.querySelector('.screen'); return s ? s.innerText : '(no .screen)'; });
      out[name] = /Something went wrong/.test(t) ? 'ERROR: ' + t.slice(0, 300) : 'ok';
    } catch (e) { out[name] = 'THROW ' + e.message.slice(0, 200); }
  };
  await screen('week', () => { S.weekStart = getMon(new Date()); go('week'); });
  await pg.screenshot({ path: path.join(OUT, 'smoke-week.png') });
  for (const ds of ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07'])
    await screen('day ' + ds, d => openDay(d), ds);
  await screen('log', () => { openDay('2026-11-04'); startLog('2026-11-04'); });
  await pg.screenshot({ path: path.join(OUT, 'smoke-log.png') });
  await screen('tick a set', () => togSet(0, 0));
  await screen('swap sheet', () => { openExSwap(S.activeLog.exercises[0].id, 0, '2026-11-04', 'PULL'); });
  await screen('add sheet', () => { closeExSwap(); openExAdd('2026-11-04', 'PULL'); });
  await screen('finish workout', () => { closeExSwap(); completeWk(); });
  await screen('my training', () => go('prs'));
  await screen('settings', () => { go('settings'); const d = document.querySelector('details.set-adv'); if (d) d.open = true; });
  await screen('ride', () => go('ride'));
  await screen('week again', () => go('week'));
  out.aiCalls = await ev(() => window._calls);
  out.pageErrors = errs; out.consoleErrors = cons.slice(0, 15);
  console.log(JSON.stringify(out, null, 1));
  await b.close();
  const bad = errs.length || Object.values(out).some(v => typeof v === 'string' && /^(ERROR|THROW)/.test(v));
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
