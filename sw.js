// Training Brain service worker
// index.html → network-first (always fresh, fallback to cache when offline)
// Exercise GIFs → cache-forever (immutable CDN assets)
// Everything else → cache-first with background update
const CACHE = 'tb-v6';
const ASSETS = [
  '/training-brain/',
  '/training-brain/index.html',
  '/training-brain/apple-touch-icon.png',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  // Remove old caches
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  // Only cache same-origin HTML/assets — pass through API/Firebase/Strava calls
  if (e.request.method !== 'GET') return;
  if (url.hostname.includes('firebase') || url.hostname.includes('googleapis') ||
      url.hostname.includes('strava') || url.hostname.includes('workers.dev')) return;

  // Exercise GIFs/images from the free-exercise-db CDN are immutable — cache them permanently.
  const isExerciseImg = url.hostname === 'yuhonas.github.io';
  if (isExerciseImg) {
    e.respondWith(
      caches.open(CACHE).then(async cache => {
        const cached = await cache.match(e.request);
        if (cached) return cached;
        return fetch(e.request).then(res => {
          if (res.type === 'opaque' || res.ok) cache.put(e.request, res.clone());
          return res;
        });
      })
    );
    return;
  }

  // index.html and the app root: stale-while-revalidate.
  // Serve the cached shell instantly (instant launch, even on slow networks),
  // then refresh the cache in the background. If the freshly-fetched shell is a
  // newer APP_VERSION than what we served, ping open clients so they can offer a
  // one-tap reload — updates still land, just without blocking every launch.
  const isAppShell = url.pathname === '/training-brain/' ||
                     url.pathname === '/training-brain/index.html';
  if (isAppShell) {
    e.respondWith(
      caches.open(CACHE).then(async cache => {
        const cached = await cache.match(e.request);
        const network = fetch(e.request).then(async res => {
          if (res.ok) {
            await cache.put(e.request, res.clone());
            if (cached) {
              try {
                const [oldV, newV] = await Promise.all([
                  cached.clone().text().then(shellVersion),
                  res.clone().text().then(shellVersion),
                ]);
                if (oldV && newV && oldV !== newV) notifyClients(newV);
              } catch (_) {}
            }
          }
          return res;
        }).catch(() => cached);
        // Cache-first on the shell; only wait on the network for the first visit.
        return cached || network;
      })
    );
    return;
  }

  // Everything else: cache-first with background update
  e.respondWith(
    caches.open(CACHE).then(async cache => {
      const cached = await cache.match(e.request);
      const fetchPromise = fetch(e.request).then(res => {
        if (res.ok) cache.put(e.request, res.clone());
        return res;
      }).catch(() => cached);
      return cached || fetchPromise;
    })
  );
});

// Pull the APP_VERSION string out of an index.html body — cheap version check
// for the stale-while-revalidate shell update notification.
function shellVersion(text) {
  const m = text.match(/APP_VERSION\s*=\s*['"]([^'"]+)['"]/);
  return m ? m[1] : null;
}

function notifyClients(version) {
  self.clients.matchAll({ type: 'window' }).then(clients =>
    clients.forEach(c => c.postMessage({ type: 'tb-shell-updated', version }))
  );
}
