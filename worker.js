// v5 — Gemini proxy + Strava OAuth token exchange
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin') || '';
    const allowed = ['https://nipshardaf.github.io', 'http://127.0.0.1', 'null'];
    if (!allowed.some(o => origin.startsWith(o))) {
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
      const data = await resp.text();
      return new Response(data, {
        status: resp.status,
        headers: { 'Content-Type': 'application/json', ...corsHeaders(origin) },
      });
    }

    // ── Gemini proxy (default route) ─────────────────────────────────────────
    if (!env.GEMINI_KEY) {
      return new Response(JSON.stringify({ error: 'GEMINI_KEY not set' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json', ...corsHeaders(origin) },
      });
    }
    const body = await request.text();
    const resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${env.GEMINI_KEY}`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body }
    );
    const data = await resp.text();
    return new Response(data, {
      status: resp.status,
      headers: { 'Content-Type': 'application/json', ...corsHeaders(origin) },
    });
  },
};

function corsHeaders(origin) {
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}
