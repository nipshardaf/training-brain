// v12 — AI proxy only answers signed-in users of the app: it checks the Firebase
//       ID token (Authorization: Bearer …) against Google's public keys. Every
//       reply carries X-TB-Auth: 1 so the app knows it can start sending the
//       token (an older worker's CORS check would reject that header).
//       Kill switch: set the REQUIRE_AUTH variable to 0 to accept anyone again.
// v11 — Vitruvian auto-ingest inbox (/vitruvian/*) fed by an iOS Shortcut
//       accepts duration in either minutes or seconds
// v10 — Gemini → Perplexity → OpenAI fallback chain + Strava OAuth
//       + Firebase Hosting origins (training-631c1.web.app / .firebaseapp.com)
//       + fallback max_tokens raised 500 → 1500 (was truncating weekly reviews)
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin') || '';
    const allowed = [
      'https://nipshardaf.github.io',
      'https://training-631c1.web.app',
      'https://training-631c1.firebaseapp.com',
      'http://127.0.0.1',
      'null',
    ];
    // Allow empty origin (iOS standalone PWA sends no Origin header)
    if (origin && !allowed.some(o => origin.startsWith(o))) {
      return new Response('Forbidden', { status: 403 });
    }
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders(origin) });
    }

    // ── Strava token exchange / refresh ──────────────────────────────────────
    if (url.pathname === '/strava/token') {
      const body = await request.json();
      const params = new URLSearchParams({
        client_id: env.STRAVA_CLIENT_ID || '',
        client_secret: env.STRAVA_CLIENT_SECRET || '',
        grant_type: body.grant_type,
      });
      if (body.grant_type === 'authorization_code') {
        params.set('code', body.code);
      } else {
        params.set('refresh_token', body.refresh_token);
      }
      const resp = await fetch('https://www.strava.com/oauth/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params,
      });
      return new Response(await resp.text(), {
        status: resp.status,
        headers: { 'Content-Type': 'application/json', ...corsHeaders(origin) },
      });
    }

    // ── YouTube video search — resolve an exercise name to an EMBEDDABLE video ──
    // The app caches the returned videoId per exercise, so each one is searched
    // at most once. videoEmbeddable=true guarantees it can play in the in-app
    // iframe (some videos disable embedding). Returns {videoId, title}.
    if (url.pathname === '/yt-search') {
      const q = url.searchParams.get('q') || '';
      if (!env.YOUTUBE_KEY || !q) {
        return new Response(JSON.stringify({ videoId: null, error: 'missing key or query' }),
          { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders(origin) } });
      }
      try {
        const yt = await fetch(
          'https://www.googleapis.com/youtube/v3/search?part=snippet&type=video' +
          '&videoEmbeddable=true&safeSearch=strict&maxResults=1&q=' +
          encodeURIComponent(q) + '&key=' + env.YOUTUBE_KEY
        );
        const data = await yt.json();
        const item = data && data.items && data.items[0];
        return new Response(JSON.stringify({
          videoId: (item && item.id && item.id.videoId) || null,
          title: (item && item.snippet && item.snippet.title) || '',
        }), { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders(origin) } });
      } catch (e) {
        return new Response(JSON.stringify({ videoId: null, error: String(e) }),
          { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders(origin) } });
      }
    }

    // ── Vitruvian auto-ingest inbox ─────────────────────────────────────────
    // The Vitruvian app has no public API, so the bridge runs the other way: an
    // iOS Shortcut (triggered by the "Vitruvian closed" automation) reads the
    // strength workout Vitruvian just wrote to Apple Health and POSTs it here.
    // Sessions park in KV until the app next opens and drains them — the phone
    // and the app are never awake at the same time, so a queue is required.
    //
    // Auth is a single shared secret (TB_INGEST_TOKEN) because a Shortcut can't
    // do OAuth. It only ever grants access to this inbox — never to Firebase,
    // Strava, or anything else — so a leak costs bogus gym sessions, nothing more.
    // Requires a KV namespace bound as TB_INBOX.
    if (url.pathname.startsWith('/vitruvian/')) {
      const jsonRes = (obj, status = 200) => new Response(JSON.stringify(obj), {
        status, headers: { 'Content-Type': 'application/json', ...corsHeaders(origin) },
      });
      if (!env.TB_INGEST_TOKEN) return jsonRes({ error: 'ingest not configured' }, 503);
      if (!env.TB_INBOX) return jsonRes({ error: 'KV namespace TB_INBOX not bound' }, 503);

      // Length-independent compare so a wrong token can't be recovered by timing.
      const tokenOk = (t) => {
        const a = String(t || ''), b = String(env.TB_INGEST_TOKEN);
        if (a.length !== b.length) return false;
        let diff = 0;
        for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
        return diff === 0;
      };

      // POST /vitruvian/session — the Shortcut hands over one finished workout.
      if (url.pathname === '/vitruvian/session' && request.method === 'POST') {
        let payload;
        try { payload = await request.json(); } catch { return jsonRes({ error: 'bad json' }, 400); }
        if (!tokenOk(payload.token)) return jsonRes({ error: 'unauthorized' }, 401);

        const start = String(payload.start || '').trim();
        // Must be a parseable instant — the app keys the log by its date, and a
        // junk timestamp would silently file the session under the wrong day.
        if (!start || isNaN(Date.parse(start))) return jsonRes({ error: 'invalid start' }, 400);

        const num = (v, max) => {
          const n = parseFloat(v);
          return (isNaN(n) || n <= 0 || n > max) ? null : Math.round(n * 10) / 10;
        };
        // Health reports duration in seconds; a Shortcut can hand over either
        // unit depending on how the value was pulled. Accept both rather than
        // silently nulling a 2520-second workout for exceeding the minute cap.
        const durMin = payload.duration_min != null ? num(payload.duration_min, 600)
                     : payload.duration_sec != null ? num(parseFloat(payload.duration_sec) / 60, 600)
                     : null;
        const session = {
          start,
          duration_min: durMin,
          calories:     num(payload.calories, 5000),
          avg_hr:       num(payload.avg_hr, 250),
          name:         String(payload.name || 'Vitruvian').slice(0, 80),
          source:       String(payload.source || 'shortcut').slice(0, 40),
          received:     new Date().toISOString(),
        };
        // Keyed by start instant, so re-running the Shortcut on the same workout
        // overwrites rather than queuing a duplicate. Expires after 45 days —
        // long enough to survive a holiday, short enough to self-clean.
        await env.TB_INBOX.put('v:' + start, JSON.stringify(session), { expirationTtl: 60 * 60 * 24 * 45 });
        return jsonRes({ ok: true, id: 'v:' + start });
      }

      // GET /vitruvian/pending — the app drains the queue on open.
      if (url.pathname === '/vitruvian/pending' && request.method === 'GET') {
        if (!tokenOk(url.searchParams.get('token'))) return jsonRes({ error: 'unauthorized' }, 401);
        const list = await env.TB_INBOX.list({ prefix: 'v:', limit: 200 });
        const sessions = [];
        for (const k of list.keys) {
          const raw = await env.TB_INBOX.get(k.name);
          if (!raw) continue;
          try { sessions.push({ id: k.name, ...JSON.parse(raw) }); } catch {}
        }
        return jsonRes({ sessions });
      }

      // POST /vitruvian/ack — drop the ones the app has safely stored.
      if (url.pathname === '/vitruvian/ack' && request.method === 'POST') {
        let payload;
        try { payload = await request.json(); } catch { return jsonRes({ error: 'bad json' }, 400); }
        if (!tokenOk(payload.token)) return jsonRes({ error: 'unauthorized' }, 401);
        const ids = Array.isArray(payload.ids) ? payload.ids.slice(0, 200) : [];
        // Only ever delete inside our own prefix, whatever the caller sends.
        for (const id of ids) if (String(id).startsWith('v:')) await env.TB_INBOX.delete(String(id));
        return jsonRes({ ok: true, deleted: ids.length });
      }

      return jsonRes({ error: 'not found' }, 404);
    }

    // ── AI proxy with fallback chain: Gemini → Perplexity → OpenAI ───────────
    const cors = corsHeaders(origin);
    // Anyone could call the AI proxy before (iOS home-screen apps send no Origin,
    // so the origin check can't block scripts) and spend the Gemini quota — and
    // then the paid Perplexity/OpenAI fallbacks. Only signed-in users get through.
    if (env.REQUIRE_AUTH !== '0') {
      const token = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
      const user = token ? await verifyFirebaseToken(token, env.FIREBASE_PROJECT_ID || 'training-631c1') : null;
      if (!user) {
        return new Response(JSON.stringify({ error: 'Sign in to use the AI coach.' }), {
          status: 401, headers: { 'Content-Type': 'application/json', ...cors },
        });
      }
    }
    const body = await request.text();

    // Extract prompt from Gemini-format request body (used for fallback providers)
    function extractPrompt(rawBody) {
      try {
        const parsed = JSON.parse(rawBody);
        return parsed?.contents?.[0]?.parts?.[0]?.text || '';
      } catch { return ''; }
    }

    // Convert OpenAI-compatible response → Gemini response format
    function toGeminiFormat(text) {
      return JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] });
    }

    // 1️⃣ Try Gemini
    if (env.GEMINI_KEY) {
      const r = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${env.GEMINI_KEY}`,
        { method: 'POST', headers: { 'Content-Type': 'application/json' }, body }
      );
      // Fall through to next provider on quota/auth errors or temporary overload
      if (r.status !== 429 && r.status !== 401 && r.status !== 403 && r.status !== 503) {
        return new Response(await r.text(), {
          status: r.status,
          headers: { 'Content-Type': 'application/json', ...cors },
        });
      }
      // 429/401/403 — fall through to next provider
    }

    const prompt = extractPrompt(body);

    // 2️⃣ Try Perplexity
    if (env.PERPLEXITY_KEY && prompt) {
      try {
        const r = await fetch('https://api.perplexity.ai/chat/completions', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${env.PERPLEXITY_KEY}` },
          body: JSON.stringify({
            model: 'sonar',
            messages: [{ role: 'user', content: prompt }],
            // 1500 covers the app's largest expected response (coach-with-tools
            // asks Gemini for up to 1400 output tokens); 500 truncated weekly
            // reviews (5 labelled sections) and tool-call JSON on fallback. v10.
            max_tokens: 1500,
          }),
        });
        if (r.ok) {
          const data = await r.json();
          const text = data.choices?.[0]?.message?.content || '';
          if (text) return new Response(toGeminiFormat(text), {
            status: 200,
            headers: { 'Content-Type': 'application/json', ...cors },
          });
        }
      } catch {}
    }

    // 3️⃣ Try OpenAI
    if (env.OPENAI_KEY && prompt) {
      try {
        const r = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${env.OPENAI_KEY}` },
          body: JSON.stringify({
            model: 'gpt-4o-mini',
            messages: [{ role: 'user', content: prompt }],
            // 1500 covers the app's largest expected response (coach-with-tools
            // asks Gemini for up to 1400 output tokens); 500 truncated weekly
            // reviews (5 labelled sections) and tool-call JSON on fallback. v10.
            max_tokens: 1500,
          }),
        });
        if (r.ok) {
          const data = await r.json();
          const text = data.choices?.[0]?.message?.content || '';
          if (text) return new Response(toGeminiFormat(text), {
            status: 200,
            headers: { 'Content-Type': 'application/json', ...cors },
          });
        }
      } catch {}
    }

    // All providers exhausted
    return new Response(JSON.stringify({ error: 'All AI providers quota exceeded or unavailable.' }), {
      status: 429,
      headers: { 'Content-Type': 'application/json', ...cors },
    });
  },
};

// ── Firebase ID token check (RS256 JWT signed by Google's securetoken keys) ──
const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
let _jwks = null, _jwksExp = 0;
async function getJwks() {
  if (_jwks && Date.now() < _jwksExp) return _jwks;
  const r = await fetch(JWKS_URL);
  if (!r.ok) throw new Error('jwks ' + r.status);
  const maxAge = +(/max-age=(\d+)/.exec(r.headers.get('Cache-Control') || '') || [])[1] || 3600;
  _jwks = await r.json();
  _jwksExp = Date.now() + maxAge * 1000;
  return _jwks;
}
function b64urlBytes(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const bin = atob(s), out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
// Returns the token's claims if it is a valid, unexpired ID token for this
// Firebase project; null otherwise. Never throws.
async function verifyFirebaseToken(token, projectId, jwksOverride) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const [h, p, sig] = parts;
    const dec = s => JSON.parse(new TextDecoder().decode(b64urlBytes(s)));
    const header = dec(h), claims = dec(p);
    if (header.alg !== 'RS256' || !header.kid) return null;
    const now = Math.floor(Date.now() / 1000);
    if (claims.aud !== projectId) return null;
    if (claims.iss !== 'https://securetoken.google.com/' + projectId) return null;
    if (!claims.sub || claims.exp <= now || claims.iat > now + 300) return null;
    const jwks = jwksOverride || await getJwks();
    const jwk = (jwks.keys || []).find(k => k.kid === header.kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64urlBytes(sig), new TextEncoder().encode(h + '.' + p));
    return ok ? claims : null;
  } catch (e) {
    return null;
  }
}

function corsHeaders(origin) {
  return {
    'Access-Control-Allow-Origin': origin || '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Expose-Headers': 'X-TB-Auth',
    'X-TB-Auth': '1',
  };
}
