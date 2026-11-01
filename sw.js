// Training Brain service worker
// index.html → stale-while-revalidate (instant launch; a newer version shows the Reload bar)
// Exercise photos → cache-forever (immutable CDN assets, so they still show with no signal)
// This site's other files and static CDN files → cache-first with background update
// Anything else (intervals.icu, weather, Endurain, the AI Worker, Firebase) → network only
const CACHE = 'tb-v7'; // v3.96: new name clears API replies the old catch-all had cached
// Hosts that only serve files that don't change. v3.96: before, every GET that wasn't
// Firebase, Strava or the Worker was answered from the cache first, so an intervals.icu
// sync or a weather check could show the previous fetch's data.
const STATIC_HOSTS = ['cdn.jsdelivr.net', 'yuhonas.github.io', 'wger.de', 'upload.wikimedia.org', 'www.gstatic.com'];
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
  if (url.origin !== self.location.origin && !STATIC_HOSTS.includes(url.hostname)) return;
  // Demo videos: leave to the browser. iPhone Safari fetches video in byte ranges and
  // won't play a whole cached copy handed back by a service worker.
  if (url.pathname.endsWith('.mp4')) return;

  // Exercise photos from free-exercise-db never change, so keep them for good. v3.96: they
  // come from jsDelivr now, which the old check (yuhonas.github.io only) missed.
  const isExerciseImg = url.hostname === 'yuhonas.github.io' ||
    (url.hostname === 'cdn.jsdelivr.net' && url.pathname.includes('/free-exercise-db@main/exercises/'));
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
