// Training Brain service worker
// index.html → network-first (always fresh, fallback to cache when offline)
// Exercise GIFs → cache-forever (immutable CDN assets)
// Everything else → cache-first with background update
const CACHE = 'tb-v4';
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

  // index.html and the app root: network-first so updates land immediately
  const isAppShell = url.pathname === '/training-brain/' ||
                     url.pathname === '/training-brain/index.html';
  if (isAppShell) {
    e.respondWith(
      fetch(e.request).then(res => {
        if (res.ok) caches.open(CACHE).then(c => c.put(e.request, res.clone()));
        return res;
      }).catch(() => caches.match(e.request))
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
