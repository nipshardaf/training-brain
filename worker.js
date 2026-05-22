// v8 — Gemini → Perplexity → OpenAI fallback chain + Strava OAuth
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin') || '';
    const allowed = ['https://nipshardaf.github.io', 'http://127.0.0.1', 'null'];
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

    // ── AI proxy with fallback chain: Gemini → Perplexity → OpenAI ───────────
    const body = await request.text();
    const cors = corsHeaders(origin);

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
            max_tokens: 500,
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
            max_tokens: 500,
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

function corsHeaders(origin) {
  return {
    'Access-Control-Allow-Origin': origin || '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}
