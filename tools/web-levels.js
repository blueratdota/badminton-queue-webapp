// node tools/web-levels.js <page.html> <sessions.json> [--session "Name"] [--courts 3] [--minutes 180] [--nights 20] [--runs 10]
//   [--true "Name:+1,Name:-1"] [--noise 0.4] [--length 8-12]
// Calibrates level checks: plays --nights club nights in a row with the page's own matching, where the --true players are
// really a level better (+1) or worse (-1) than their set level and everyone else's true strength is their level plus a random
// offset of up to --noise levels. Winners are drawn from true strength. After each night it runs the page's levelCheck on
// every player and reports how many nights it takes to flag the mis-levelled players, and how many correctly-levelled players
// get flagged (false flags). Nobody's level is changed during the run.
const fs = require('fs');
const loadPage = require('./load-page');
const [html, input] = process.argv.slice(2);
const opt = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const courts = +opt('courts', 3), minutes = +opt('minutes', 180), nights = +opt('nights', 20), runs = +opt('runs', 10), noise = +opt('noise', 0.4);
const [lenMin, lenMax] = opt('length', '8-12').split('-').map(Number);
const page = loadPage(html);
if (!page.levelCheck) throw new Error('this page has no levelCheck');
const src = JSON.parse(fs.readFileSync(input, 'utf8'));
const all = src.sessions || [src.current || src];
const base = opt('session', null) ? all.find(s => s.name?.trim() === opt('session').trim()) : [...all].sort((a, b) => a.date - b.date).at(-1);
const roster = base.players.filter(p => !p.away).map(p => ({ name: p.name, skill: p.skill }));
const offsets = Object.fromEntries((opt('true', '') || '').split(',').filter(Boolean).map(t => { const [n, d] = t.split(':'); return [n.trim(), +d]; }));
for (const n of Object.keys(offsets)) if (!roster.some(p => p.name === n)) throw new Error('not in the roster: ' + n);
const STEP = 0.8, mean = x => x.reduce((a, b) => a + b, 0) / x.length;

function season(seed) {
  const rng = page.mulberry32(seed * 7919), realNow = Date.now;
  const truth = Object.fromEntries(roster.map(p => [p.name, p.skill + STEP * (offsets[p.name] ?? (rng() * 2 - 1) * noise)]));
  const list = [], first = {}; // name -> { night, dir }
  for (let n = 0; n < nights; n++) {
    const t0 = 1e12 + n * 7 * 864e5; let T = t0; Date.now = () => T;
    const S = { id: 'n' + n, date: t0, results: [], tournament: null, queueMatching: 'auto',
      players: roster.map((p, i) => ({ id: `n${n}p${i}`, name: p.name, skill: p.skill, pref: 'any', paused: false, readyAt: t0 + i })),
      courts: Array.from({ length: courts }, (_, i) => page.court('Court ' + (i + 1), 'doubles')) };
    page.set('S', S);
    const nameOf = Object.fromEntries(S.players.map(p => [p.id, p.name])), ends = {};
    while (true) {
      if (T < t0 + minutes * 60000) for (const c of S.courts) {
        if (c.match || !page.nextPairing(c)) continue;
        page.fill(c.id); ends[c.id] = T + (lenMin + rng() * (lenMax - lenMin)) * 60000;
      }
      const next = Object.entries(ends).sort((x, y) => x[1] - y[1])[0];
      if (!next) { if (T < t0 + minutes * 60000 && S.courts.some(c => page.eligible(c.format).length >= 4)) { T += 30000; continue; } break; }
      const [cid, end] = next; T = end; delete ends[cid];
      const m = S.courts.find(c => c.id === cid).match, str = ids => mean(ids.map(id => truth[nameOf[id]]));
      page.finish(cid, rng() < 1 / (1 + 10 ** ((str(m.b) - str(m.a)) / page.get('SPREAD'))) ? 0 : 1);
    }
    list.push(S);
    for (const p of roster) if (!first[p.name]) { const c = page.levelCheck(p.name, list); if (c) first[p.name] = { night: n + 1, dir: c.dir }; }
  }
  Date.now = realNow;
  return first;
}

const results = Array.from({ length: runs }, (_, i) => season(i + 1));
const dirOf = d => d > 0 ? 'up' : 'down';
console.log(`# Level checks: ${roster.length} players · ${courts} courts · ${minutes / 60} h · ${nights} nights in a row · ${runs} runs · noise ±${noise} level\n`);
console.log('Mis-levelled players (true level differs from the set one):');
for (const [n, d] of Object.entries(offsets)) {
  const hits = results.map(r => r[n]).filter(f => f && f.dir === dirOf(d)), wrong = results.filter(r => r[n] && r[n].dir !== dirOf(d)).length;
  const ns = hits.map(f => f.night).sort((a, b) => a - b);
  console.log(`  ${n} (${d > 0 ? 'really one level up' : 'really one level down'}): flagged in ${hits.length}/${runs} runs` +
    (ns.length ? `, after ${ns[0]}–${ns.at(-1)} nights (median ${ns[ns.length >> 1]})` : '') + (wrong ? ` · ${wrong} wrong-way flags` : ''));
}
const fair = roster.map(p => p.name).filter(n => !(n in offsets));
const falses = results.flatMap(r => fair.filter(n => r[n]).map(n => ({ n, ...r[n] })));
console.log(`\nCorrectly levelled players: ${fair.length}. False flags: ${falses.length} in ${runs * nights} nights (${(falses.length / (runs * nights) * 10).toFixed(2)} per 10 nights)`);
const byName = {}; for (const f of falses) (byName[f.n] ??= []).push(`${f.dir}@${f.night}`);
for (const [n, fs_] of Object.entries(byName)) console.log(`  ${n}: ${fs_.join(', ')}`);
