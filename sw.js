// Training Brain service worker — cache-first with background update
const CACHE = 'tb-v2';
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
  // Cross-origin responses are "opaque" (res.ok is false), so they need explicit handling.
  const isExerciseImg = url.hostname === 'yuhonas.github.io';

  e.respondWith(
    caches.open(CACHE).then(async cache => {
      const cached = await cache.match(e.request);
      // Exercise images never change — once stored, always serve from cache (no network)
      if (cached && isExerciseImg) return cached;
      const fetchPromise = fetch(e.request).then(res => {
        // Store normal responses, plus opaque exercise images
        if (res.ok || (isExerciseImg && res.type === 'opaque')) cache.put(e.request, res.clone());
        return res;
      }).catch(() => cached); // network fail → fall back to cache
      // Serve cache instantly, update in background
      return cached || fetchPromise;
    })
  );
});
