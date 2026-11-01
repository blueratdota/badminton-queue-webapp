// node tools/web-tiers.js <page.html> <sessions.json> [--courts 3] [--minutes 180] [--runs 100]
// Per starting rating, what kind of games players get (range, lopsided, partners, opponents).
const fs = require('fs');
const page = require('./load-page')(process.argv[2]);
const opt = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? +process.argv[i + 1] : d; };
const courts = opt('courts', 3), minutes = opt('minutes', 180), runs = opt('runs', 100);
const roster = JSON.parse(fs.readFileSync(process.argv[3], 'utf8')).current.players;
const st = {}, cnt = {}, tier = r => Math.round(r * 2) / 2; // grouped to the nearest 0.5
for (const p of roster) { cnt[tier(p.skill)] = (cnt[tier(p.skill)] || 0) + 1; st[tier(p.skill)] = { n: 0, w1: 0, wide: 0, lop: 0, part: 0, opp: 0 }; }
for (let s = 1; s <= runs; s++) {
  const rng = page.mulberry32(s * 7919), t0 = 1e12; let T = t0; Date.now = () => T;
  const S = { id: 'x', date: t0, results: [], tournament: null, courts: Array.from({ length: courts }, (_, i) => page.court('Court ' + (i + 1), 'doubles')),
    players: roster.map((p, n) => ({ id: 'p' + n, name: p.name, skill: p.skill, pref: 'any', paused: false, readyAt: t0 + n })) };
  page.set('S', S);
  const tr = Object.fromEntries(S.players.map(p => [p.id, p.skill])), ends = {};
  while (true) {
    if (T < t0 + minutes * 60000) for (const c of S.courts) {
      if (c.match) continue; const p = page.nextPairing(c); if (!p) continue;
      page.fill(c.id); ends[c.id] = T + (10 + rng() * 4) * 60000;
      const a = c.match.a.map(id => tr[id]), b = c.match.b.map(id => tr[id]), all = [...a, ...b];
      const range = Math.max(...all) - Math.min(...all), gap = Math.abs(a[0] + a[1] - b[0] - b[1]) / 2;
      for (const [mine, theirs] of [[a, b], [b, a]]) for (let i = 0; i < 2; i++) {
        const x = st[tier(mine[i])]; x.n++; x.w1 += range <= 1 + 1e-9; x.wide += range > 2 + 1e-9; x.lop += gap > 0.75 + 1e-9;
        x.part += mine[1 - i]; x.opp += (theirs[0] + theirs[1]) / 2;
      }
    }
    const nx = Object.entries(ends).sort((x, y) => x[1] - y[1])[0]; if (!nx) break;
    T = nx[1]; delete ends[nx[0]]; const m = S.courts.find(c => c.id === nx[0]).match;
    const str = ids => ids.reduce((q, id) => q + tr[id], 0) / ids.length;
    page.finish(nx[0], rng() < 1 / (1 + 10 ** ((str(m.b) - str(m.a)) / page.get('SPREAD'))) ? 0 : 1);
  }
}
const pc = (x, n) => Math.round(100 * x / n) + '%';
console.log('| Rating (nearest 0.5) | Players | Games each | All four within 1 level | More than 2 levels | Lopsided (>0.75) | Avg partner | Avg opponents |\n|---|---|---|---|---|---|---|---|');
for (const t of Object.keys(st).map(Number).sort((a, b) => b - a)) { const x = st[t];
  console.log(`| ${t} | ${cnt[t]} | ${(x.n / runs / cnt[t]).toFixed(1)} | ${pc(x.w1, x.n)} | ${pc(x.wide, x.n)} | ${pc(x.lop, x.n)} | ${(x.part / x.n).toFixed(1)} | ${(x.opp / x.n).toFixed(1)} |`); }
