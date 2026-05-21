// Training Brain service worker — cache-first with background update
const CACHE = 'tb-v1';
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

  e.respondWith(
    caches.open(CACHE).then(async cache => {
      const cached = await cache.match(e.request);
      const fetchPromise = fetch(e.request).then(res => {
        if (res.ok) cache.put(e.request, res.clone());
        return res;
      }).catch(() => cached); // network fail → fall back to cache
      // Serve cache instantly, update in background
      return cached || fetchPromise;
    })
  );
});
