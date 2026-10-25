// node tools/web-sim.js <page.html> <sessions.json> [--courts 3] [--minutes 180] [--runs 30] [--pairs "A,B;C,D"] [--parity [--locks "A,B;C,D"]] [--length 10-14]
// Replays whole nights through the web version's own matching (fill, finish, nextPairing) on a virtual clock, with and
// without the pair requests, and prints a report. The sessions file is the iPad's sessions.json (its current session is used).
const fs = require('fs');
const loadPage = require('./load-page');
const [html, input] = process.argv.slice(2);
const opt = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const courts = +opt('courts', 3), minutes = +opt('minutes', 180), runs = +opt('runs', 30);
const [lenMin, lenMax] = opt('length', '10-14').split('-').map(Number); // game length range in minutes
const pairs = (opt('pairs', '') || '').split(';').filter(Boolean).map(p => p.split(',').map(s => s.trim()));
const locks = (opt('locks', '') || '').split(';').filter(Boolean).map(p => p.split(',').map(s => s.trim()));
const page = loadPage(html);
if (pairs.length && !page.setPartner) throw new Error('This web version removed pair requests. Use --locks with --parity for locked teammates.');
if (!(page.get('SPREAD') > 0)) throw new Error('could not read the rating spread from the page');
if (process.argv.includes('--parity')) { // one night with nothing random; same rules as the iPad's -parity
  const t0 = 1e12; let T = t0; Date.now = () => T;
  const src0 = JSON.parse(fs.readFileSync(input, 'utf8'));
  const S = { id: 'p', date: t0, results: [], tournament: null,
    players: (src0.current || src0).players.map((p, n) => ({ id: 'p' + n, name: p.name, skill: p.skill, rated: p.rated, pref: p.pref || 'any', paused: false, readyAt: t0 + n })),
    courts: Array.from({ length: courts }, (_, i) => page.court('Court ' + (i + 1), 'doubles')) };
  page.set('S', S);
  const byName = Object.fromEntries(S.players.map(p => [p.name, p.id])), truth = Object.fromEntries(S.players.map(p => [p.id, p.skill]));
  for (const [x, y] of pairs) page.setPartner(byName[x], byName[y]);
  for (const [x, y] of locks) page.setLock(byName[x], byName[y]); // --locks "A,B;C,D"
  if (opt('scheduled', '')) { S.hours=3; for (const item of opt('scheduled','').split(';')) { const sides=item.split('|').map(t=>t.split(',').map(n=>byName[n.trim()])); if(sides.length===2) page.scheduleMatch('doubles',sides[0],sides[1]); } }
  const lines = [], ends = {}, winners = {}; let k = 0;
  const drawsFile = opt('draws', null), draws = drawsFile ? JSON.parse(fs.readFileSync(drawsFile, 'utf8')) : null; // [[minutes, u], ...]
  while (true) {
    if (T < t0 + 180 * 60000) S.courts.forEach((c, ci) => {
      if (c.match) return;
      const p = page.nextPairing(c); if (!p) return;
      lines.push(`${Math.floor((T - t0) / 60000)} ${c.name}: ${p.a.map(x => x.name).join('+')} v ${p.b.map(x => x.name).join('+')}`);
      page.fill(c.id);
      const d = draws ? draws[k % draws.length] : null;
      ends[ci] = T + (d ? d[0] : 10 + k % 5) * 60000;
      if (d) { const st = ps => ps.reduce((a, x) => a + truth[x.id], 0) / ps.length; winners[ci] = d[1] < 1 / (1 + 10 ** ((st(p.b) - st(p.a)) / page.get('SPREAD'))); }
      k++;
    });
    const next = Object.entries(ends).map(([ci, e]) => [+ci, e]).sort((x, y) => x[1] - y[1] || x[0] - y[0])[0];
    if (!next) break;
    const [ci, end] = next; T = end; delete ends[ci];
    const m = S.courts[ci].match, sumT = ids => ids.reduce((a, id) => a + truth[id], 0);
    page.finish(S.courts[ci].id, ci in winners ? (winners[ci] ? 0 : 1) : sumT(m.a) >= sumT(m.b) ? 0 : 1);
    lines.push('  = ' + [...m.a, ...m.b].map(id => { const p = S.players.find(x => x.id === id); return `${p.name} ${p.skill.toFixed(4)}`; }).join(', '));
    delete winners[ci];
  }
  console.log(lines.join('\n'));
  process.exit(0);
}
const realNow = Date.now;
const src = JSON.parse(fs.readFileSync(input, 'utf8'));
const roster = (src.current || src).players.map(p => ({ name: p.name, skill: p.skill }));
const mean = x => x.length ? x.reduce((a, b) => a + b, 0) / x.length : 0;
const f1 = x => x.toFixed(1), f2 = x => x.toFixed(2);
const clock = m => `${Math.floor(m / 60)}:${String(Math.floor(m % 60)).padStart(2, '0')}`;

/** One night: everyone there from the start, courts refill the moment they free up, games last --length minutes (10–14),
    winners drawn from the starting ratings (each player's "true" strength). */
function night(seed, withPairs) {
  const rng = page.mulberry32(seed * 7919);
  const t0 = 1e12; let T = t0; Date.now = () => T;
  const S = { id: 'sim', date: t0, results: [], tournament: null,
    players: roster.map((p, n) => ({ id: 'p' + n, name: p.name, skill: p.skill, pref: 'any', paused: false, readyAt: t0 + n })),
    courts: Array.from({ length: courts }, (_, i) => page.court('Court ' + (i + 1), 'doubles')) };
  page.set('S', S);
  const truth = Object.fromEntries(S.players.map(p => [p.id, p.skill])), byName = Object.fromEntries(S.players.map(p => [p.name, p.id]));
  if (withPairs) for (const [x, y] of pairs) page.setPartner(byName[x], byName[y]);
  for (const [x, y] of locks) { if (!byName[x] || !byName[y]) throw new Error('Unknown locked teammate: ' + [x,y].join(', ')); page.setLock(byName[x], byName[y]); }
  const games = [], ends = {};
  while (true) {
    if (T < t0 + minutes * 60000) for (const c of S.courts) {
      if (c.match) continue;
      const p = page.nextPairing(c); if (!p) continue;
      const ids = [...p.a, ...p.b].map(x => x.id);
      if (new Set(ids).size !== 4 || ids.some(id => page.onCourt().has(id))) throw new Error('a player was booked twice');
      const planned = (page.isPairGame?.(p.a.map(x => x.id), p.b.map(x => x.id)) || false);
      const len = (lenMin + rng() * (lenMax - lenMin)) * 60000;
      games.push({ minute: (T - t0) / 60000, length: len / 60000, court: c.name, a: p.a.map(x => x.name), b: p.b.map(x => x.name),
        sa: p.a.map(x => truth[x.id]), sb: p.b.map(x => truth[x.id]), planned, plannedGap: planned ? Math.abs(page.sum(p.a) - page.sum(p.b)) / 2 : null, note: p.note });
      page.fill(c.id);
      ends[c.id] = { end: T + len, g: games.length - 1 };
    }
    const next = Object.entries(ends).sort((x, y) => x[1].end - y[1].end)[0];
    if (!next) break;
    const [cid, { end, g }] = next; T = end; delete ends[cid];
    const m = S.courts.find(c => c.id === cid).match, str = ids => mean(ids.map(id => truth[id]));
    const aWon = rng() < 1 / (1 + 10 ** ((str(m.b) - str(m.a)) / page.get('SPREAD')));
    games[g].aWon = aWon;
    page.finish(cid, aWon ? 0 : 1);
  }
  Date.now = realNow;
  return games;
}

const together = (g, x, y) => [g.a, g.b].some(t => t.includes(x) && t.includes(y));
const spread = g => Math.max(...g.sa, ...g.sb) - Math.min(...g.sa, ...g.sb);
const gap = g => Math.abs(mean(g.sa) - mean(g.sb));
const overlaps = (a, b) => a.minute < b.minute + b.length - 1e-6 && b.minute < a.minute + a.length - 1e-6;
function waits(games) {
  const lastEnd = {}, out = [];
  for (const g of [...games].sort((x, y) => x.minute - y.minute)) for (const n of [...g.a, ...g.b]) { out.push({ n, w: g.minute - (lastEnd[n] ?? 0), at: g.minute }); lastEnd[n] = g.minute + g.length; }
  return out;
}

const paired = new Set(pairs.flat()), rest = roster.map(p => p.name).filter(n => !paired.has(n));
const skill = Object.fromEntries(roster.map(p => [p.name, p.skill]));
let out = `# ${pairs.length ? pairs.length + ' pair requests against none' : 'Simulated nights'} (web version's matching)\n\n${roster.length} players · ${courts} doubles courts · ${minutes / 60} hours · games ${lenMin}–${lenMax} min · ${runs} nights each · same random draws\n\n`;
if (pairs.length) out += 'Pairs: ' + pairs.map(([x, y]) => `${x} ${f1(skill[x])} & ${y} ${f1(skill[y])}`).join(' · ') + '\n\n';
const configs = pairs.length ? [false, true] : [false];
const seedBase = +opt('seeds', 0); // --seeds N: start from a different set of random nights
const nightsBy = configs.map(w => Array.from({ length: runs }, (_, i) => night(seedBase + i + 1, w)));
if (pairs.length) {
  const withN = nightsBy[1], without = nightsBy[0];
  const planned = withN.flatMap(n => n.filter(g => g.planned));
  out += `Pair games made: ${planned.length} over ${runs} nights · team gap by the ratings at the time: average ${f2(mean(planned.map(g => g.plannedGap)))}, worst ${f2(Math.max(0, ...planned.map(g => g.plannedGap)))}\n\n`;
  out += '## Each pair\'s game together\n\n| Pair | Ratings | Nights they got it | Times together per night | First together at (avg) | Team gap in that game (starting ratings) | Rating range in that game | Games each per night | No request: together per night |\n|---|---|---|---|---|---|---|---|---|\n';
  for (const [x, y] of pairs) {
    const firsts = withN.map(n => n.filter(g => together(g, x, y)).sort((a, b) => a.minute - b.minute)[0]).filter(Boolean);
    out += `| ${x} & ${y} | ${f1(skill[x])} & ${f1(skill[y])} | ${firsts.length} of ${runs} | ${f1(mean(withN.map(n => n.filter(g => together(g, x, y)).length)))} | ${firsts.length ? clock(mean(firsts.map(g => g.minute))) : '–'} | ${f2(mean(firsts.map(gap)))} (worst ${f2(Math.max(0, ...firsts.map(gap)))}) | ${f1(mean(firsts.map(spread)))} (widest ${f1(Math.max(0, ...firsts.map(spread)))}) | ${f1(mean(withN.map(n => n.filter(g => [...g.a, ...g.b].includes(x)).length + n.filter(g => [...g.a, ...g.b].includes(y)).length).map(v => v / 2)))} | ${f1(mean(without.map(n => n.filter(g => together(g, x, y)).length)))} |\n`;
  }
  out += '\n';
}
out += `## Everyone, per night\n\n| | Games | Games per player | Pair games at the same time | Two pairs in one game | Paired players' games | Others' games | Average wait | Longest wait | Waits over 30 min | All four within 1 level | Team gap |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n`;
configs.forEach((w, k) => {
  const ns = nightsBy[k];
  const per = ns.map(n => { const c = {}; for (const g of n) for (const p of [...g.a, ...g.b]) c[p] = (c[p] || 0) + 1; return c; });
  const lo = Math.min(...per.flatMap(c => roster.map(p => c[p.name] || 0))), hi = Math.max(...per.flatMap(c => roster.map(p => c[p.name] || 0)));
  const pairGames = ns.map(n => n.filter(g => g.planned));
  const ov = pairGames.map(pg => { let c = 0; for (let i = 0; i < pg.length; i++) for (let j = i + 1; j < pg.length; j++) if (overlaps(pg[i], pg[j])) c++; return c; });
  const two = ns.map(n => n.filter(g => pairs.filter(([x, y]) => together(g, x, y)).length >= 2).length);
  const games = (n, who) => n.flatMap(g => [...g.a, ...g.b]).filter(p => who.includes(p)).length / Math.max(1, who.length);
  const ws = ns.map(waits);
  out += `| ${w ? 'With requests' : pairs.length ? 'No requests' : `${courts} courts`} | ${f1(mean(ns.map(n => n.length)))} | ${lo}–${hi} | ${w ? f1(mean(ov)) : '–'} | ${f1(mean(two))} | ${pairs.length ? f1(mean(ns.map(n => games(n, [...paired])))) : '–'} | ${f1(mean(ns.map(n => games(n, rest))))} | ${f1(mean(ws.flat().map(x => x.w)))} min | ${Math.round(Math.max(...ws.flat().map(x => x.w)))} min | ${f1(mean(ws.map(x => x.filter(v => v.w > 30).length)))} | ${Math.round(100 * mean(ns.map(n => n.filter(g => spread(g) <= 1 + 1e-9).length / n.length)))}% | ${f2(mean(ns.flatMap(n => n.map(gap))))} |\n`;
});
console.log(out);
