// node tools/web-scan.js <page.html> <sessions.json> [--courts 3] [--runs 100] [--minutes 180] [--pairs "A,B;C,D"] [--length 10-14] [--late "Name:25,Name:50"]
// Replays nights through the web version's own matching and counts odd queue behaviour per night, with examples:
// players called straight back, someone 2+ games behind left waiting, long waits, repeated partners/foursomes,
// lopsided or wide games, and how even the game counts end up. Late players are marked present at the given minute.
const fs = require('fs');
const loadPage = require('./load-page');
const [html, input] = process.argv.slice(2);
const opt = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const courts = +opt('courts', 3), runs = +opt('runs', 100), minutes = +opt('minutes', 180);
const [lenMin, lenMax] = opt('length', '10-14').split('-').map(Number); // game length range in minutes
const pairs = opt('pairs', '').split(';').filter(Boolean).map(x => x.split(',').map(s => s.trim()));
const late = Object.fromEntries(opt('late', '').split(',').filter(Boolean).map(x => { const [n, m] = x.split(':'); return [n.trim(), +m]; }));
const locks = (opt('locks', '') || '').split(';').filter(Boolean).map(p => p.split(',').map(s => s.trim()));
const page = loadPage(html);
if (pairs.length && !page.setPartner) throw new Error('This web version removed pair requests.');
const inputData = JSON.parse(fs.readFileSync(input, 'utf8'));
const roster = (inputData.current || inputData).players.map(p => ({ name: p.name, skill: p.skill }));
const C = {}, ex = {}, per = {};
const hit = (k, msg) => { C[k] = (C[k] || 0) + 1; (ex[k] = ex[k] || []).length < 3 && ex[k].push(msg); };
const clock = m => `${Math.floor(m / 60)}:${String(Math.floor(m % 60)).padStart(2, '0')}`;
const range = ps => Math.max(...ps.map(p => p.skill)) - Math.min(...ps.map(p => p.skill));
for (let s = 1; s <= runs; s++) {
  const rng = page.mulberry32(s * 7919), t0 = 1e12; let T = t0; Date.now = () => T;
  const S = { id: 'x', date: t0, results: [], tournament: null, courts: Array.from({ length: courts }, (_, i) => page.court('Court ' + (i + 1), 'doubles')),
    players: roster.map((p, n) => ({ id: 'p' + n, name: p.name, skill: p.skill, pref: 'any', paused: false, readyAt: t0 + n, away: p.name in late || undefined })) };
  page.set('S', S);
  const by = Object.fromEntries(S.players.map(p => [p.name, p])), truth = Object.fromEntries(S.players.map(p => [p.id, p.skill]));
  for (const [x, y] of pairs) page.setPartner(by[x].id, by[y].id);
  for (const [x, y] of locks) { if (!by[x] || !by[y]) throw new Error('Unknown locked teammate: ' + [x,y].join(', ')); page.setLock(by[x].id, by[y].id); }
  const ends = {}, lastEnd = {}, arrived = {}, teamed = {}, fours = new Set();
  const arrivals = Object.entries(late).map(([n, m]) => [t0 + m * 60000, n]).sort((a, b) => a[0] - b[0]);
  while (true) {
    for (const [at, n] of arrivals) if (by[n].away && T >= at) { page.arrive(by[n].id); arrived[n] = T; }
    if (T < t0 + minutes * 60000) for (const c of S.courts) {
      if (c.match) continue;
      const line = page.eligible('doubles'), p = page.nextPairing(c); if (!p) continue;
      const four = [...p.a, ...p.b], ids = four.map(x => x.id), at = clock((T - t0) / 60000);
      const n = page.gamesCounted(), off = page.lastOffCourt(), rested = line.filter(x => !off.has(x.id));
      const left = rested.filter(x => !ids.includes(x.id)), back = four.filter(x => lastEnd[x.id] === T);
      const what = `${p.a.map(x => x.name).join('+')} v ${p.b.map(x => x.name).join('+')}${p.note ? ' (' + p.note + ')' : ''}`;
      if (back.length && left.length) hit('straight back while rested wait', `${at} ${back.map(x => x.name).join(', ')} · ${what}`);
      const lo = Math.min(...left.map(x => n[x.id])), hi = Math.max(...ids.map(id => n[id]));
      if (left.length && hi - lo >= 2) hit('someone 2+ games behind left waiting', `${at} ${left.find(x => n[x.id] === lo).name} (${lo}) waits · ${what}`);
      for (const x of four) { const w = (T - (lastEnd[x.id] ?? arrived[x.name] ?? t0)) / 60000; if (w > 30) hit('waited over 30 min', `${at} ${x.name} ${w.toFixed(0)} min`); }
      for (const t of [p.a, p.b]) { const k = t.map(x => x.name).sort().join(' & '); teamed[k] = (teamed[k] || 0) + 1; if (teamed[k] === 3) hit('same partners a 3rd time', `${at} ${k}`); }
      const fk = four.map(x => x.name).sort().join(', '); if (fours.has(fk)) hit('same four again', `${at} ${fk}`); fours.add(fk);
      const gap = Math.abs(page.sum(p.a) - page.sum(p.b)) / 2;
      if (gap > 0.75) hit('teams more than 0.75 apart', `${at} gap ${gap.toFixed(2)} · ${what}`);
      if (range(four) > 2) hit('wider than 2 levels', `${at} ${four.map(x => x.name + ' ' + x.skill.toFixed(1)).join(', ')}${p.note ? ' (' + p.note + ')' : ''}`);
      page.fill(c.id); ends[c.id] = T + (lenMin + rng() * (lenMax - lenMin)) * 60000;
    }
    const next = Object.entries(ends).sort((a, b) => a[1] - b[1])[0], nextLate = arrivals.find(([, n]) => by[n].away)?.[0];
    if (!next && nextLate == null) break;
    if (nextLate != null && (!next || nextLate < next[1])) { T = nextLate; continue; }
    T = next[1]; delete ends[next[0]];
    const m = S.courts.find(c => c.id === next[0]).match, str = ids => ids.reduce((a, id) => a + truth[id], 0) / ids.length;
    for (const id of [...m.a, ...m.b]) lastEnd[id] = T;
    page.finish(next[0], rng() < 1 / (1 + 10 ** ((str(m.b) - str(m.a)) / page.get('SPREAD'))) ? 0 : 1);
  }
  const g = {}; for (const r of S.results) for (const id of [...r.a, ...r.b]) g[id] = (g[id] || 0) + 1;
  const onTime = S.players.filter(p => !(p.name in late)), v = onTime.map(p => g[p.id] || 0), d = Math.max(...v) - Math.min(...v);
  C['spread' + d] = (C['spread' + d] || 0) + 1;
  for (const p of S.players) per[p.name] = (per[p.name] || 0) + (g[p.id] || 0);
}
const f = x => (x / runs).toFixed(2);
let out = `${runs} nights · ${roster.length} players · ${courts} doubles courts · ${minutes / 60} hours · ${locks.length} locked pairs · ${pairs.length} legacy pair requests${Object.keys(late).length ? ' · late: ' + opt('late') : ''}\n\n`;
out += 'Per night: ' + Object.entries(C).filter(([k]) => !k.startsWith('spread')).map(([k, x]) => `${k} ${f(x)}`).join(' · ') + '\n';
out += 'Nights by most − fewest games (on-time players): ' + Object.entries(C).filter(([k]) => k.startsWith('spread')).sort().map(([k, x]) => `${k.slice(6)}: ${x}`).join(', ') + '\n\n';
const sk = Object.fromEntries(roster.map(p => [p.name, p.skill]));
out += 'Games per night by player: ' + Object.entries(per).sort((a, b) => sk[b[0]] - sk[a[0]]).map(([n, x]) => `${n} ${sk[n].toFixed(1)}: ${f(x)}`).join(' · ') + '\n';
for (const [k, list] of Object.entries(ex)) out += `\n${k}:\n  ${list.join('\n  ')}`;
console.log(out);
