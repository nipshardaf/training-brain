// Cross-check Training Brain's exercise tables after an edit.
// Usage: node refcheck.cjs index.html [free-exercise-db exercises.json]
//   Get the library list with:
//   curl -sS -o exercises.json https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json
// Checks: every EX entry has the required fields, an EX_EQUIP tag list and a cue; every id used by
// SLOTS, SLOT_MORE, CHEST_PRESS, UNILATERAL_MAP, _EX_ALIASES and EX_CUES exists; SLOT_MORE lines
// up with SLOTS; visible names are unique and free of characters that break step text; and (with
// the library file) every string photo `p` is a real free-exercise-db folder. Exits 1 on errors.
const fs = require('fs');
const src = fs.readFileSync(process.argv[2] || 'index.html', 'utf8');
const libPath = process.argv[3];
const grab = name => {
  const i = src.indexOf(name); if (i < 0) throw new Error('not found: ' + name);
  const a = src.indexOf('{', i); let d = 0, j = a;
  for (; j < src.length; j++) { if (src[j] === '{') d++; else if (src[j] === '}') { d--; if (!d) break; } }
  return eval('(' + src.slice(a, j + 1) + ')');
};
const EX = grab('const EX ='), EQ = grab('const EX_EQUIP='), SL = grab('const SLOTS ='), SM = grab('const SLOT_MORE='),
  CP = grab('const CHEST_PRESS='), UM = grab('const UNILATERAL_MAP='), AL = grab('const _EX_ALIASES='), CUES = grab('const EX_CUES=');
const err = [], warn = [];
const has = (id, where) => { if (!EX[id]) err.push(`${where}: unknown id ${id}`); };
for (const [id, e] of Object.entries(EX)) {
  for (const f of ['n', 'g', 't', 'sets', 'reps', 'rpe', 'm']) if (e[f] == null) err.push(`${id}: missing ${f}`);
  if (!EQ[id]) err.push(`${id}: no EX_EQUIP entry`);
  if (!CUES[id]) warn.push(`${id}: no EX_CUES line`);
  if (/[—']/.test(e.n)) err.push(`${id}: name has an apostrophe or em dash (breaks onclick strings / style)`);
  if (/\d/.test(e.n) && !/^\d/.test(e.n)) warn.push(`${id}: digits in the name can read as a duration in intervals.icu step text`);
}
for (const id of Object.keys(EQ)) has(id, 'EX_EQUIP');
for (const [t, sl] of Object.entries(SL)) sl.flat().forEach(id => has(id, 'SLOTS.' + t));
for (const [t, sl] of Object.entries(SM)) {
  if (!SL[t] || sl.length !== SL[t].length) err.push(`SLOT_MORE.${t}: ${sl.length} slots but SLOTS.${t} has ${SL[t] ? SL[t].length : 0}`);
  sl.flat().forEach(id => has(id, 'SLOT_MORE.' + t));
}
Object.keys(CP).forEach(id => has(id, 'CHEST_PRESS'));
Object.entries(UM).forEach(([a, b]) => { has(a, 'UNILATERAL_MAP from'); has(b, 'UNILATERAL_MAP to'); });
Object.values(AL).forEach(id => has(id, '_EX_ALIASES'));
Object.keys(CUES).forEach(id => has(id, 'EX_CUES'));
const names = {};
for (const [id, e] of Object.entries(EX)) if (!e.hide) (names[e.n] = names[e.n] || []).push(id);
for (const [n, ids] of Object.entries(names)) if (ids.length > 1) err.push(`duplicate visible name "${n}": ${ids.join(', ')} (hide one with hide:1)`);
if (libPath) {
  const lib = new Set(JSON.parse(fs.readFileSync(libPath, 'utf8')).map(x => x.id));
  for (const [id, e] of Object.entries(EX)) if (typeof e.p === 'string' && !lib.has(e.p)) err.push(`${id}: photo folder ${e.p} is not in free-exercise-db`);
} else warn.push('no library file given: photo folders not checked');
const tags = [...new Set(Object.values(EQ).flat())].sort();
console.log(`EX ${Object.keys(EX).length} (${Object.values(EX).filter(e => !e.hide).length} visible), ${Object.values(EX).filter(e => !e.p && !e.hide).length} without a photo`);
console.log('equipment tags: ' + tags.join(', '));
warn.forEach(w => console.log('warn  ' + w));
err.forEach(e => console.log('ERROR ' + e));
console.log(err.length ? `${err.length} error(s)` : 'all references OK');
process.exit(err.length ? 1 : 0);
