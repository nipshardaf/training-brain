// Test fixture for Training Brain, injected before the app loads (page.addInitScript).
// Freezes the clock at TB_NOW (Wednesday 4 Nov 2026, 09:00) and fills localStorage with a
// realistic account: GoodLife gym, 3 weeks of Push/Pull/Legs logs (one on a named machine),
// three indoor rides, this week's plan and an AI Coach review. Edit freely per test.
window.__seed = (opts = {}) => {
  const now = new Date(opts.now || '2026-11-04T09:00:00').getTime(), R = Date;
  // Date.now() stays fixed: timers that count from it (rest timer, ride) won't advance.
  Date = class extends R { constructor(...a) { a.length ? super(...a) : super(now); } static now() { return now; } };
  const L = (k, v) => localStorage.setItem(k, JSON.stringify(v));
  L('welcome_seen', true); L('gym_profile', opts.gym || 'goodlife_bloor_bay'); L('lang', 'en');
  L('user_profile', { goals: ['fitness', 'muscle'], activities: ['gym', 'cycling'], days: 4, weight: 80, weightUnit: 'kg', ftp: 145, setup_done: true, level: 'intermediate', gender: 'male' });
  L('prs', { bb_bench: { w: 80, r: 8, date: '2026-11-02' }, bb_squat: { w: 100, r: 6, date: '2026-10-29' } });
  const S1 = (w, r, n = 3) => Array.from({ length: n }, () => ({ w: String(w), r: String(r), done: true }));
  const lg = (d, t, ex) => L('log_' + d, { date: d, type: t, completed: true, exercises: ex });
  lg('2026-10-19', 'PUSH', [{ id: 'bb_bench', sets: S1(75, 8) }, { id: 'ohp', sets: S1(45, 8) }, { id: 'lat_raise', sets: S1(10, 12) }, { id: 'tri_push', sets: S1(30, 12) }]);
  lg('2026-10-21', 'PULL', [{ id: 'lat_pull', sets: S1(60, 10), mach: 'Dual Pulley Pulldown' }, { id: 'bb_row', sets: S1(60, 8) }, { id: 'face_pull', sets: S1(20, 15) }, { id: 'bb_curl', sets: S1(30, 10) }]);
  lg('2026-10-23', 'LEGS', [{ id: 'bb_squat', sets: S1(95, 6) }, { id: 'rdl', sets: S1(80, 8) }, { id: 'leg_press', sets: S1(150, 10) }, { id: 'leg_curl', sets: S1(40, 10) }, { id: 'calf_raise', sets: S1(60, 15) }]);
  lg('2026-10-26', 'PUSH', [{ id: 'bb_bench', sets: S1(77.5, 8) }, { id: 'smith_incline', sets: S1(50, 10) }, { id: 'mach_lat_raise', sets: S1(25, 12) }, { id: 'rope_pushdown', sets: S1(25, 12) }]);
  lg('2026-10-28', 'PULL', [{ id: 'lat_pull', sets: S1(62.5, 10), mach: 'Dual Pulley Pulldown' }, { id: 'iso_row', sets: S1(40, 10) }, { id: 'cable_rear_fly', sets: S1(10, 15) }, { id: 'ez_curl', sets: S1(25, 10) }]);
  lg('2026-10-29', 'LEGS', [{ id: 'bb_squat', sets: S1(100, 6) }, { id: 'trap_bar_dl', sets: S1(110, 6) }, { id: 'pendulum_squat', sets: S1(60, 10) }, { id: 'leg_press_calf', sets: S1(100, 15) }]);
  lg('2026-11-02', 'PUSH', [{ id: 'bb_bench', sets: S1(80, 8) }, { id: 'incline_db', sets: S1(26, 10) }, { id: 'cable_y_raise', sets: S1(5, 12) }, { id: 'seated_dip_mach', sets: S1(60, 12) }]);
  const ride = (d, mins, w, hr) => ({ id: +d.replace(/-/g, ''), name: 'Indoor ride', type: 'VirtualRide', sport_type: 'VirtualRide', start_date_local: d + 'T18:00:00', moving_time: mins * 60, elapsed_time: mins * 60, distance: mins * 400, average_watts: w, average_heartrate: hr, max_heartrate: hr + 20, kilojoules: w * mins * 60 / 1000, _src: 'icu' });
  L('strava_activities', [ride('2026-10-20', 45, 105, 132), ride('2026-10-25', 60, 100, 130), ride('2026-11-01', 50, 110, 135)]);
  // Plan days keep weather under `weather` (rDay reads w.score); flat fields crash the day screen.
  const wx = { tmax: 12, tmin: 4, rain: 0, wind: 12, code: 2, score: 6 };
  const types = ['PUSH', 'REST', 'PULL', 'SHORT_INDOOR', 'LEGS', 'LONG_INDOOR', 'REST'];
  const ex = { PUSH: ['bb_bench', 'ohp', 'incline_db', 'lat_raise', 'tri_push'], PULL: ['lat_pull', 'bb_row', 'cable_row', 'face_pull', 'bb_curl'], LEGS: ['bb_squat', 'rdl', 'leg_press', 'leg_curl', 'calf_raise', 'plank'] };
  L('plan_2026-11-02', types.map((t, i) => ({ date: '2026-11-0' + (2 + i), type: t, exercises: ex[t] || [], weather: wx })));
  L('gym_days_2026-11-02', [0, 2, 4]); L('week_picker_2026-11-02', true);
  L('coachweek_2026-11-02', { generated: '2026-11-02T08:00:00Z', days: ['2026-11-04', '2026-11-06'], types: { '2026-11-04': 'PULL', '2026-11-06': 'LEGS' },
    review: { summary: 'Bench is moving up.', progressing: ['Bench 75 to 80'], stalled: [], volume: 'Chest 9 sets', suggestions: ['Keep going'] } });
  // Capture what the page asks the iPhone app's native side to do (alarms, share sheet).
  if (opts.native) { window._native = []; window.webkit = { messageHandlers: { tbnative: { postMessage: m => window._native.push(JSON.parse(JSON.stringify(m))) } } }; }
};
