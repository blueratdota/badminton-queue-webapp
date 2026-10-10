// Shuttle Queue engine: the matching, ratings, standings and tournament rules, moved verbatim from the artifact page.
// The rules match the iPad app (RULES.md is the spec); tools/web-sim.js --parity checks they play the same night.
// All logic reads and mutates the module-level session `S`; the UI calls setS/setSessions/setCurrentId and re-renders.

export const NEED = { singles: 2, doubles: 4 };
export const SKILL = ['New', 'Beginner', 'Intermediate', 'Advanced', 'Strong'];
export const PREFS = ['any', 'singles', 'doubles'];
// ponytail: tuning knobs, same values as the iPad app
export const RANGE = 1.0;   // singles opponents within 1 level count as fair
export const FAIR = 0.75;   // doubles teams' averages within 0.75 of a level count as fair
export const SIMILAR = 1.0; // doubles "similar skill": all four within 1 level
export const WIDER = 1.5;   // tried when every similar group would repeat recent partners or opponents, or call someone straight back
export const REPEAT_LIMIT = 3; // ponytail: 1 per pair of the four who shared a recent game, 2 more per repeated partnership
// Nobody should wait longer than 30 minutes. Anyone who has waited 20 (a court still has to free up) plays in the next game,
// which may stretch to OVERDUE_SPREAD levels with balanced teams at worst. ponytail: 20 chosen by simulation, like the iPad app.
export const WAIT_PRIORITY = 20 * 60000;
export const OVERDUE_SPREAD = 2.0;
export const PAIR_SLACK = 0.25; // ponytail: a pair game's team averages may differ by at most this much, like the iPad app
export const K = 0.3, SPREAD = 2; // rating: most one game can move it; level gap where the stronger side is ~90% to win
export const LS_KEY = 'shuttle-queue-v2';
export const THEME_KEY = 'shuttle-queue-theme'; // per-viewer: system, light or dark

export const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2) + Date.now().toString(36));
export const clone = o => JSON.parse(JSON.stringify(o));
export const cmp = (a, b) => { for (let i = 0; i < a.length; i++) { if (a[i] < b[i]) return -1; if (a[i] > b[i]) return 1; } return 0; };
export const level = sk => Math.min(5, Math.max(1, Math.round(sk)));
export const r1 = x => (Math.round(x * 10) / 10).toFixed(1);
export const mulberry32 = a => () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
export const shuffled = (arr, rng) => { const a = [...arr]; for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rng() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };

// ---------- state ----------
export let sessions = new Map(); // id -> session
export let currentId = null;
export let S = null;             // the session being run
export const past = () => [...sessions.values()].filter(x => x.id !== currentId).sort((a, b) => b.date - a.date);

export const blankSession = () => ({
  id: uid(), date: Date.now(), players: [], results: [], tournament: null,
  courts: [court('Court 1', 'doubles'), court('Court 2', 'singles')],
});
export function court(name, format) { return { id: uid(), name, format, match: null, shuffles: 0, plan: null, locked: null }; }

// ---------- session basics ----------
export const P = id => S.players.find(p => p.id === id);
export const players = ids => ids.map(P).filter(Boolean);
export const courtById = id => S.courts.find(c => c.id === id);
export const played = id => S.results.filter(r => r.a.includes(id) || r.b.includes(id)).length;
export const wins = id => S.results.filter(r => r.winner != null && (r.winner === 0 ? r.a : r.b).includes(id)).length;
export const avg = ids => { const s = players(ids).map(p => p.skill); return s.length ? s.reduce((a, b) => a + b, 0) / s.length : 3; };
export const sum = ps => ps.reduce((a, p) => a + p.skill, 0);
export const names = ids => ids.map(id => P(id)?.name ?? 'Removed player').join(' & ');
export function onCourt() { return new Set(S.courts.flatMap(c => c.match ? [...c.match.a, ...c.match.b] : [])); }
/** Games played plus any arrival credit: what "fewest games first" compares. */
export function gamesCounted() {
  const n = {};
  for (const p of S.players) n[p.id] = p.credit || 0;
  for (const r of S.results) for (const id of [...r.a, ...r.b]) if (id in n) n[id]++;
  return n;
}
/** Everyone here and off court: anyone moved to the front, then the four who just came off behind everyone rested (so nobody
    behind on games goes straight back on court), then fewest games counted, then longest rested. */
export function queue() {
  const busy = onCourt(), n = gamesCounted(), off = lastOffCourt();
  const key = p => [p.first ? 0 : 1, off.has(p.id) ? 1 : 0, n[p.id] || 0, p.readyAt];
  return S.players.filter(p => !busy.has(p.id) && !p.away).sort((x, y) => cmp(key(x), key(y)));
}
export function eligible(f) { return queue().filter(p => !p.paused && (p.pref === 'any' || p.pref === f)); }

// ---------- matchmaking ----------
/** Singles opponents for the longest-rested player: in range first, then rested as long, then closest skill, then longest wait. */
export function singlesRivals(q, finishes) {
  if (q.length < 2) return [];
  const head = q[0];
  const nextFinish = Math.min(Infinity, ...finishes.filter(t => t > head.readyAt));
  const ranked = q.slice(1).map((p, i) => {
    const gap = Math.abs(p.skill - head.skill);
    return { k: [gap <= RANGE ? 0 : 1, p.readyAt < nextFinish ? 0 : 1, gap, i], p };
  }).sort((x, y) => cmp(x.k, y.k));
  const inRange = ranked.filter(r => r.k[0] === 0).map(r => r.p);
  return inRange.length ? inRange.slice(0, 3) : [ranked[0].p];
}
export function pickSingles(q, finishes, choice = 0) {
  const rivals = singlesRivals(q, finishes);
  if (!rivals.length) return null;
  return { format: 'singles', a: [q[0]], b: [rivals[choice % rivals.length]], options: rivals.length };
}
/** Fair ways to split four players (strongest-with-newest first); never a stacked side; least uneven if none are fair. */
export function fairSplits(four) {
  const s = [...four].sort((x, y) => y.skill - x.skill);
  const all = [[[s[0], s[3]], [s[1], s[2]]], [[s[0], s[2]], [s[1], s[3]]], [[s[0], s[1]], [s[2], s[3]]]];
  const gap = t => Math.abs(sum(t[0]) - sum(t[1])) / 2;
  const best = Math.min(...all.map(gap));
  return all.filter(t => gap(t) <= Math.max(FAIR, best + 0.001)).map(t => ({ a: t[0], b: t[1] }));
}
/** Longest-rested player plus the earliest three after them who can make fair teams. */
// ponytail: searches the first 12 in line, like the iPad app
export function fairFour(q) {
  const pool = q.slice(0, 12);
  for (let k = 3; k < pool.length; k++) for (let j = 2; j < k; j++) for (let i = 1; i < j; i++) {
    const four = [pool[0], pool[i], pool[j], pool[k]];
    const b = fairSplits(four)[0];
    if (Math.abs(sum(b.a) - sum(b.b)) / 2 <= FAIR) return four;
  }
  return pool.slice(0, 4);
}
/** Each player's partners and opponents over their last two doubles games this session. */
export function recentPairs(games = 2) {
  const out = {}, seen = {};
  for (const r of [...S.results].reverse()) {
    if (r.a.length !== 2) continue;
    for (const [mine, theirs] of [[r.a, r.b], [r.b, r.a]]) for (const id of mine) {
      if ((seen[id] || 0) >= games) continue;
      seen[id] = (seen[id] || 0) + 1;
      const o = out[id] || (out[id] = { partners: new Set(), opponents: new Set() });
      mine.forEach(x => { if (x !== id) o.partners.add(x); }); theirs.forEach(x => o.opponents.add(x));
    }
  }
  return out;
}
/** How much a lineup repeats recent games: 1 for every pair of the four who shared a recent game, plus 2 for each team that partnered lately. */
export function repeats(a, b, recent) {
  const met = (x, y) => [[x, y], [y, x]].some(([p, q]) => { const r = recent[p.id]; return !!r && (r.partners.has(q.id) || r.opponents.has(q.id)); });
  const partnered = (x, y) => !!(recent[x.id]?.partners.has(y.id) || recent[y.id]?.partners.has(x.id));
  const four = [...a, ...b]; let n = 0;
  for (let i = 0; i < four.length; i++) for (let j = i + 1; j < four.length; j++) if (met(four[i], four[j])) n++;
  for (const t of [a, b]) if (t.length === 2 && partnered(t[0], t[1])) n += 2;
  return n;
}
/** The longest-rested player plus three from `pool` (positions in `q`) that `allowed` accepts: fewest players straight off court
    first, then fewest repeats, then (bySpread) nearest ratings, then whoever has waited longest. Splits come back least repetitive first.
    `together`: two ids that must be teammates. */
// ponytail: searches up to 12 candidates (165 groups), like the iPad app
export function bestFour(q, pool, recent, justOff, { bySpread = false, must = 1, together = null, apart = [], games = {}, heavyFirst = false, allowed }) {
  if (pool.length < 3) return null;
  let best = null;
  for (let k = 2; k < pool.length; k++) for (let j = 1; j < k; j++) for (let i = 0; i < j; i++) {
    const picked = [pool[i], pool[j], pool[k]], four = [q[0], ...picked.map(x => q[x])];
    let ok = true;
    for (let m = 1; m < must; m++) if (!picked.includes(m)) { ok = false; break; }
    if (!ok || !allowed(four)) continue;
    const teamHas = (t, ids) => ids.every(id => t.some(p => p.id === id));
    const fair = fairSplits(four).filter(s => (!together || [s.a, s.b].some(t => teamHas(t, together)))
      && !apart.some(pair => [s.a, s.b].some(t => teamHas(t, pair))));
    if (!fair.length) continue;
    const splits = fair.map((sp, o) => ({ sp, pen: repeats(sp.a, sp.b, recent), o })).sort((x, y) => cmp([x.pen, x.o], [y.pen, y.o]));
    const sk = four.map(p => p.skill), range = Math.max(...sk) - Math.min(...sk);
    // Fewest games among the other three before fewest repeats, so players at either end of the ratings aren't left behind.
    // bySpread (balanced teams): repeats past the limit, then nearest ratings in quarter levels, come before that.
    const key = [four.filter(p => justOff.has(p.id)).length, ...(bySpread || heavyFirst ? [splits[0].pen >= REPEAT_LIMIT ? splits[0].pen : 0] : []), ...(bySpread ? [Math.round(range * 4)] : []),
      picked.reduce((a, i) => a + (games[q[i].id] || 0), 0),
      splits[0].pen, ...(bySpread ? [Math.round(range * 100)] : []), pool[k], picked.reduce((a, b) => a + b, 0)];
    if (!best || cmp(key, best.key) < 0) best = { key, pen: splits[0].pen, splits: splits.map(x => x.sp) };
  }
  return best && { splits: best.splits, penalty: best.pen, justOff: best.key[0] };
}
/** Doubles. Similar skill first: the longest-rested player plus three within a level of each other, choosing the group and teams
    that repeat recent partners and opponents least. If that would call someone straight back on court or repeat too much, a wider
    range, then balanced teams from the nearest ratings. `choice` is the shuffle count, cycling through that group's fair splits. */
/** `apart`: pairs that may not be teammates; `accept`: an extra test every four must pass (a pair game's limits for the others). */
export function pickDoubles(q, choice = 0, { recent = {}, must = 1, justOff = new Set(), together = null, apart = [], accept = () => true, capSpread = null, games = {}, balancedOnly = false } = {}) {
  if (q.length < 4) return null;
  const head = q[0];
  // How far a pick falls short: players straight off court first (rest beats skill match), then repeats past the limit.
  const shortfall = g => g ? [g.justOff, g.penalty >= REPEAT_LIMIT ? g.penalty : 0] : [Infinity, Infinity];
  const fine = g => cmp(shortfall(g), [0, 0]) === 0;
  const reason = (from, to) => (from?.justOff ?? 0) > to.justOff ? (to.justOff ? 'so fewer go straight back' : 'so nobody goes straight back') : 'for new partners';
  const similarGroup = spread => {
    const near = [...new Set([...Array.from({ length: must - 1 }, (_, i) => i + 1),
      ...q.map((_, i) => i).slice(1).filter(i => Math.abs(q[i].skill - head.skill) <= spread + 1e-9).slice(0, 12)])].sort((a, b) => a - b);
    return bestFour(q, near, recent, justOff, { must, together, apart, games, allowed: four => { const s = four.map(p => p.skill); return Math.max(...s) - Math.min(...s) <= spread + 1e-9 && accept(four); } });
  };
  // balancedOnly (too few players for similar groups): straight to even teams, in queue order, no rating-range preference.
  let best = balancedOnly ? null : similarGroup(SIMILAR), note = null;
  if (!balancedOnly && !fine(best)) {
    const w = similarGroup(WIDER);
    if (w && cmp(shortfall(w), shortfall(best)) < 0) { note = 'wider skill range ' + reason(best, w); best = w; }
  }
  if (!fine(best)) {
    // Balanced teams from the nearest ratings; an overdue game (capSpread) stays within that many levels unless nothing else is free.
    const balanced = cap => bestFour(q, q.map((_, i) => i).slice(1, 12), recent, justOff, { bySpread: !balancedOnly, heavyFirst: balancedOnly, must, together, apart, games,
      allowed: four => { const t = fairSplits(four)[0], sk = four.map(p => p.skill);
        return Math.abs(sum(t.a) - sum(t.b)) / 2 <= FAIR && accept(four) && (cap == null || Math.max(...sk) - Math.min(...sk) <= cap + 1e-9); } });
    const b = balanced(capSpread) || (!best && capSpread != null ? balanced(null) : null);
    if (b && cmp(shortfall(b), shortfall(best)) < 0) { note = balancedOnly ? null : best ? 'mixed teams ' + reason(best, b) : 'mixed teams, no similar group free'; best = b; }
  }
  if (!best && together) return null;
  // Nobody straight back while four rested players can play: the evenest four of them, uneven teams if it must be.
  const fallback = best ? [] : fairFour(q);
  if (!together && (best ? best.justOff : fallback.filter(p => justOff.has(p.id)).length) > 0) {
    const four = restedFour(q, must, justOff, apart);
    if (four) { const t = lastResortSplits(four, apart)[0]; return { format: 'doubles', a: t.a, b: t.b, options: 1, note: 'uneven teams so nobody goes straight back' }; }
  }
  const splits = best ? best.splits : lastResortSplits(fallback, apart);
  if (!best) note = 'mixed teams, no similar group free';
  const s = splits[choice % splits.length];
  return { format: 'doubles', a: s.a, b: s.b, options: splits.length, note };
}
/** The first in line (if rested) plus the three rested players, of the first 12, who make the evenest teams, however uneven;
    anyone overdue (the first `must`) included. null if fewer than four are rested. */
export function restedFour(q, must, justOff, apart) {
  if (!q.length || q.slice(0, Math.max(1, must)).some(p => justOff.has(p.id))) return null; // the first in line and anyone overdue must play
  const r = q.filter(p => !justOff.has(p.id)).slice(0, 12);
  if (r.length < 4) return null;
  let best = null;
  for (let k = 3; k < r.length; k++) for (let j = 2; j < k; j++) for (let i = 1; i < j; i++) {
    let ok = true; for (let m = 1; m < must; m++) if (![i, j, k].includes(m)) ok = false;
    if (!ok) continue;
    const four = [r[0], r[i], r[j], r[k]], t = lastResortSplits(four, apart)[0], gap = Math.abs(sum(t.a) - sum(t.b));
    if (!best || gap < best.gap - 1e-9) best = { gap, four };
  }
  return best && best.four;
}
/** Last resort: the fairest split of these four that doesn't team up a pair waiting for its planned game. */
export function lastResortSplits(four, apart) {
  const s = [...four].sort((x, y) => y.skill - x.skill);
  const all = [[[s[0], s[3]], [s[1], s[2]]], [[s[0], s[2]], [s[1], s[3]]], [[s[0], s[1]], [s[2], s[3]]]];
  const keepsApart = t => !apart.some(pair => t.some(team => pair.every(id => team.some(p => p.id === id))));
  const ok = all.filter(keepsApart).sort((x, y) => Math.abs(sum(x[0]) - sum(x[1])) - Math.abs(sum(y[0]) - sum(y[1])));
  return ok.length ? [{ a: ok[0][0], b: ok[0][1] }] : fairSplits(four);
}
export const lastOffCourt = () => { const r = S.results.at(-1); return new Set(r ? [...r.a, ...r.b] : []); };
/** Whether x and y have been teammates in a doubles game this session (on purpose or by chance). */
export const pairPlayed = (x, y) => S.results.some(r => r.a.length === 2 && [r.a, r.b].some(t => t.includes(x) && t.includes(y)));
/** A requested pair is waiting for its game: not played together yet, and each has played one doubles game this session
    (so never in their first game of the night). */
export function pairWaiting(x, y) {
  const playedDoubles = id => S.results.some(r => r.a.length === 2 && [...r.a, ...r.b].includes(id));
  return !pairPlayed(x, y) && playedDoubles(x) && playedDoubles(y);
}
/** One team is a requested pair that hadn't played together yet: their pair game. */
export const isPairGame = (a, b) => [a, b].some(t => t.length === 2 && P(t[0])?.partner === t[1] && P(t[1])?.partner === t[0] && !pairPlayed(t[0], t[1]));
/** Only one pair game at a time: is one being played now? */
export const pairGameOnCourt = () => S.courts.some(c => c.match && isPairGame(c.match.a, c.match.b));
/** Pair requests need enough people: twice the players one full round of courts takes, minus two (14 for 2 doubles
    courts, 22 for 3, 30 for 4; a singles court counts 2). Below that they're kept but on hold. Sitting out doesn't count. */
export const pairingMinimum = () => 2 * S.courts.reduce((n, c) => n + NEED[c.format], 0) - 2;
export const activePlayers = () => S.players.filter(p => !p.paused && !p.away).length; // sitting out and not here don't count
export const pairingActive = () => activePlayers() >= pairingMinimum();
/** All courts doubles and fewer than 8 players per court here: balanced teams instead of similar-skill groups. */
export const balancedOnly = () => S.courts.length > 0 && S.courts.every(c => c.format === 'doubles') && activePlayers() < 8 * S.courts.length;
/** Every requested pair (two-way), whether or not they've played together. */
export const requestedPairs = () => S.players.filter(p => p.partner && P(p.partner)?.partner === p.id && p.id < p.partner).map(p => [p.id, p.partner]);
/** Requested pairs that haven't played together yet: the normal matching won't make them teammates, so their game happens
    only as a planned, even pair game. They can still meet as opponents. After their game they're not listed. */
export const pairsKeptApart = () => pairingActive() ? requestedPairs().filter(([x, y]) => !pairPlayed(x, y)) : [];
/** Partner requests: each requested pair plays one game together per session; after that they're like anyone else.
    When one of a waiting pair is about to play (picked anyway, or in the front four) and the other is rested and nearest the
    front (first 8 in line, then 12, then anyone waiting if no even game can be made), they're offered as teammates alongside
    whoever is first in line: up to 3 games with different other players, each with team averages within PAIR_SLACK and never
    against another requested pair. The rating range may be wider than usual. No court note. */
export function partnerGames(pool, picked, overdue, justOff) {
  if (!pairingActive() || overdue.length > 2) return [];
  const games = gamesCounted();
  for (const depth of [8, 12, pool.length]) { // ponytail: whole line as the last try, once per pair per night
    const near = pool.slice(0, depth);
    for (const x of picked) {
      if (justOff.has(x.id)) continue;
      const y = near.find(p => p.id === x.partner && p.partner === x.id);
      if (!y || justOff.has(y.id) || !pairWaiting(x.id, y.id)) continue;
      const recent = recentPairs();
      for (const [a, b] of [[x.id, y.id], [y.id, x.id]]) { recent[a]?.partners.delete(b); recent[a]?.opponents.delete(b); }
      const front = [...overdue];
      for (const p of [...pool.slice(0, 1), x, y]) if (!front.some(o => o.id === p.id)) front.push(p); // first in line plays, as in any game
      if (front.length > 4) continue;
      const ids = new Set(front.map(p => p.id));
      const even = four => Math.abs(x.skill + y.skill - sum(four.filter(p => p.id !== x.id && p.id !== y.id))) / 2 <= PAIR_SLACK + 1e-9
        && !four.some(p => justOff.has(p.id)); // and nobody called straight back to fit the pair in
      const otherPairs = requestedPairs().filter(([a, b]) => !(a === x.id && b === y.id) && !(a === y.id && b === x.id));
      const games = [], used = new Set();
      while (games.length < 3) {
        const g = pickDoubles([...front, ...near.filter(p => !ids.has(p.id) && !used.has(p.id))], 0,
          { recent, must: front.length, justOff, together: [x.id, y.id], apart: otherPairs, accept: even, games });
        if (!g) break;
        g.note = null; games.push(g);
        [...g.a, ...g.b].forEach(p => { if (!ids.has(p.id)) used.add(p.id); });
      }
      if (games.length) return games;
    }
  }
  return [];
}
/** Sets (or clears, with null) a two-way partner request, ending any request either player had with someone else. */
export function setPartner(id, other) {
  for (const p of S.players) if (p.id === id || p.id === other || (p.partner && (p.partner === id || p.partner === other))) p.partner = null;
  if (other && P(id) && P(other)) { P(id).partner = other; P(other).partner = id; }
}
export const listNames = ps => { try { return new Intl.ListFormat('en', { type: 'conjunction' }).format(ps.map(p => p.name)); } catch { return ps.map(p => p.name).join(', '); } };
/** Overdue first: everyone who has waited 20+ minutes (up to a full court) plays in this game, fewest games counted first
    (a late arrival counts at par, so their missed games don't put them ahead), then longest wait.
    While more players haven't played than a game needs, each shuffle draws a fresh random group from them. */
/** `allowPairGame`: false when another court already has a pair game lined up (one pair game at a time). */
export function pick(f, line, choice = 0, allowPairGame = true) {
  const now = Date.now(), waited = p => p.since ?? p.readyAt;
  const n = gamesCounted();
  const overdue = line.filter(p => now - waited(p) >= WAIT_PRIORITY).sort((x, y) => n[x.id] - n[y.id] || waited(x) - waited(y)).slice(0, NEED[f]);
  const late = new Set(overdue.map(p => p.id));
  const q = line.filter(p => !late.has(p.id));
  const unplayed = q.filter(p => played(p.id) === 0);
  const fresh = unplayed.length > NEED[f];
  let pool = q;
  if (fresh && choice > 0) {
    const ids = new Set(unplayed.map(p => p.id));
    pool = shuffled(unplayed, mulberry32(choice * 2 + (f === 'singles' ? 1 : 0))).concat(q.filter(p => !ids.has(p.id)));
  }
  // Ties on fewest games: whoever is hardest to match (fewest similar-level players waiting) heads the game, so the
  // strongest and weakest aren't left waiting while mid-rated players fill every game. Nobody with more games jumps ahead.
  if (f === 'doubles' && !fresh && !overdue.length && !balancedOnly() && pool.length > 4 && !pool[0].first) {
    const off0 = lastOffCourt(), low = n[pool[0].id];
    const tier = pool.filter(p => n[p.id] === low && !off0.has(p.id) && !p.first);
    const similar = p => pool.filter(x => x.id !== p.id && Math.abs(x.skill - p.skill) <= SIMILAR + 1e-9).length;
    if (tier.length > 1) { const h = tier.reduce((b, p) => similar(p) < similar(b) ? p : b); pool = [h, ...pool.filter(p => p.id !== h.id)]; }
  }
  pool = [...overdue, ...pool];
  const turn = fresh ? 0 : choice, off = lastOffCourt();
  const opts = f === 'doubles' ? { recent: recentPairs(), must: Math.max(1, overdue.length), justOff: off, apart: pairsKeptApart(),
    capSpread: overdue.length ? OVERDUE_SPREAD : null, games: n, balancedOnly: balancedOnly() } : null; // an overdue game may stretch to 2 levels, balanced, at worst
  let p = f === 'singles' ? pickSingles(pool, S.results.map(r => r.end), turn) : pickDoubles(pool, turn, opts);
  if (f === 'doubles' && allowPairGame && !pairGameOnCourt()) {
    // A waiting pair is offered first; shuffle steps through their other options, then on to the normal games.
    const normal = turn === 0 ? p : pickDoubles(pool, 0, opts);
    const pairGames = partnerGames(pool, [...(normal ? [...normal.a, ...normal.b] : []), ...pool.slice(0, 4)], overdue, off);
    if (pairGames.length) {
      const n = pairGames.length + (normal?.options || 0), k = turn % n;
      p = k < pairGames.length ? pairGames[k] : pickDoubles(pool, k - pairGames.length, opts);
      if (p) p.options = n;
    }
  }
  if (p && fresh) p.options = 99; // keeps the shuffle button available
  if (p && overdue.length) p.note = [p.note, `${listNames(overdue)} waited ${WAIT_PRIORITY / 60000}+ min`].filter(Boolean).join(' · ');
  return p;
}
/** A hand-set lineup that still stands. */
export function validPlan(c) {
  if (S.tournament || c.match || !c.plan || c.plan.a.length + c.plan.b.length !== NEED[c.format]) return null;
  const waiting = new Set(eligible(c.format).map(p => p.id));
  return [...c.plan.a, ...c.plan.b].every(id => waiting.has(id)) ? c.plan : null;
}
/** A game for every open court (nobody booked twice); the format whose next player is furthest up the line picks first.
    Busy courts still preview who's next there. */
export function queueUpNext() {
  const line = queue().map(p => p.id);
  const rank = f => { const e = eligible(f)[0]; return e ? line.indexOf(e.id) : Infinity; };
  const open = S.courts.map((c, i) => ({ c, i })).filter(x => !x.c.match)
    .sort((x, y) => cmp([rank(x.c.format), x.i], [rank(y.c.format), y.i])).map(x => x.c);
  // Hand-set lineups come first and their players are off limits to the automatic picks.
  const taken = new Set(open.flatMap(c => { const pl = validPlan(c); return pl ? [...pl.a, ...pl.b] : []; }));
  const out = [], ids = p => [p.a.map(x => x.id), p.b.map(x => x.id)];
  // One pair game at a time: once one is lined up (or set by hand), the other courts get normal games.
  let pairLined = open.some(c => { const pl = validPlan(c); return pl && isPairGame(pl.a, pl.b); });
  for (const c of open) {
    const pl = validPlan(c);
    if (pl) { out.push({ format: c.format, a: players(pl.a), b: players(pl.b), court: c.id, options: 2 }); continue; }
    const p = pick(c.format, eligible(c.format).filter(x => !taken.has(x.id)), c.shuffles || 0, !pairLined);
    if (!p) continue;
    p.court = c.id; [...p.a, ...p.b].forEach(x => taken.add(x.id)); out.push(p);
    if (isPairGame(...ids(p))) pairLined = true;
  }
  // Busy courts: who's next there once the current game ends, earliest-started court first.
  // ponytail: a guess from who's waiting now; the players coming off other courts can change it
  for (const c of S.courts.filter(c => c.match).sort((x, y) => x.match.start - y.match.start)) {
    const p = pick(c.format, eligible(c.format).filter(x => !taken.has(x.id)), 0, !pairLined);
    if (p) { p.court = c.id; [...p.a, ...p.b].forEach(x => taken.add(x.id)); out.push(p); if (isPairGame(...ids(p))) pairLined = true; }
  }
  return out;
}
export let memo = null; // one run of the matching shared by everything a render (or a shuffle) asks; null = compute fresh
export const upNext = () => memo || (S.tournament ? tournamentUpNext() : queueUpNext());
/** Runs `f` with the matching computed once; `f` must not change who's waiting until it's done reading. */
export function withMatching(f) { memo = upNext(); try { return f(); } finally { memo = null; } }
export function nextPairing(c) {
  if (c.match) return null;
  const n = upNext();
  if (S.tournament) {
    const i = S.courts.filter(x => !x.match).findIndex(x => x.id === c.id);
    return i >= 0 && i < n.length ? n[i] : null;
  }
  return n.find(p => p.court === c.id) || null;
}
export const shuffleOptions = c => (!S.tournament && !c.match) ? (nextPairing(c)?.options || 0) : 0;
/** Shuffle one court's Next up game; every other court keeps its lineup. */
export function shuffleCourt(id) {
  const c = courtById(id); if (!c || c.match) return;
  // One run of the matching for every court, read before any plan below changes it; skipped when nothing else needs keeping.
  const needed = c.locked != null || S.courts.some(o => o.id !== id && !o.match);
  const [keep, here] = !needed ? [[], null] : withMatching(() => [
    S.courts.filter(o => o.id !== id).map(o => [o, nextPairing(o)]).filter(([, p]) => p).map(([o, p]) => [o, { a: p.a.map(x => x.id), b: p.b.map(x => x.id) }]),
    c.locked != null && nextPairing(c)]);
  keep.forEach(([o, pl]) => { o.plan = pl; });
  if (here) {
    // Locked side stays; the other side steps through fair options from the front of the line, rested players first.
    const side = c.locked, kept = (side === 0 ? here.a : here.b).map(p => p.id), current = new Set((side === 0 ? here.b : here.a).map(p => p.id));
    const busy = new Set([...kept, ...keep.flatMap(([, pl]) => [...pl.a, ...pl.b])]), off = lastOffCourt();
    const pool = eligible(c.format).filter(p => !busy.has(p.id)).slice(0, 8).map(p => p.id); // ponytail: front 8 only, like the iPad app
    const sides = kept.length === 1 ? pool.map(x => [x]) : pool.flatMap((x, i) => pool.slice(i + 1).map(y => [x, y]));
    const fair = sides.filter(sd => isEven(kept, sd));
    const options = (fair.length ? fair : sides).map((sd, o) => ({ sd, o, n: sd.filter(x => off.has(x)).length }))
      .sort((x, y) => cmp([x.n, x.o], [y.n, y.o])).map(x => x.sd);
    if (!options.length) return;
    const at = options.findIndex(sd => sd.length === current.size && sd.every(x => current.has(x)));
    const other = options[(at + 1) % options.length];
    c.plan = side === 0 ? { a: kept, b: other } : { a: other, b: kept };
    return;
  }
  c.plan = null; c.shuffles = (c.shuffles || 0) + 1;
}
/** Locks one side of an open court's Next up game (null unlocks): those players stay, and shuffle changes only the other side. */
export function lockSide(id, side) {
  const c = courtById(id); if (!c || c.match) return;
  if (side != null) { const h = nextPairing(c); if (h) c.plan = { a: h.a.map(x => x.id), b: h.b.map(x => x.id) }; }
  c.locked = side;
}

// ---------- actions ----------
export function fill(cid) {
  const c = courtById(cid); const p = c && nextPairing(c);
  if (!p) return;
  c.match = { a: p.a.map(x => x.id), b: p.b.map(x => x.id), start: Date.now(), tm: p.match ?? null };
  c.shuffles = 0; c.plan = null; c.locked = null;
}
export const ratingChange = (ta, tb, aWon) => K * ((aWon ? 1 : 0) - 1 / (1 + 10 ** ((tb - ta) / SPREAD)));
export const length = r => r.end - r.start;
/** How one-sided a game looked from its length: +1 for half the usual time or less, 0 for the usual time,
    −1 for half again the usual time or more. Usual is the median of `lens`. */
export function speedAmong(len, lens) {
  const s = [...lens].sort((a, b) => a - b), med = s[Math.floor(s.length / 2)];
  return med > 0 ? Math.min(1, Math.max(-1, (med - len) / (med / 2))) : 0;
}
/** `speedAmong` for a finished game, against this session's games of the same format. */
export const speed = r => speedAmong(length(r), S.results.filter(x => x.a.length === r.a.length).map(length));
/** Standings score, 0–100. A win counts 0.93–1.0 and a loss 0–0.1, more for a quicker (more one-sided) game,
    so records decide it and game length mostly breaks near-ties. Everyone starts with two extra wins and two extra
    losses so one or two lucky games can't top the table. "No result" doesn't count. */
export function score(id) {
  let credit = 2, games = 4;
  for (const r of S.results) {
    if (r.winner == null || !(r.a.includes(id) || r.b.includes(id))) continue;
    const s = speed(r);
    credit += (r.winner === 0 ? r.a : r.b).includes(id) ? 0.965 + 0.035 * s : 0.05 - 0.05 * s;
    games++;
  }
  return credit / games * 100;
}
export function adjust(ids, d) {
  const out = {};
  for (const id of ids) { const p = P(id); if (!p) continue; const old = p.skill; p.skill = Math.min(5, Math.max(1, old + d)); out[id] = p.skill - old; }
  return out;
}
export function finish(cid, winner) {
  const c = courtById(cid); const m = c?.match; if (!m) return;
  const r = { a: m.a, b: m.b, winner, court: c.name, start: m.start, end: Date.now(), changes: null, label: null };
  if (winner != null) {
    // Game length is a nudge: a quick (one-sided) game moves ratings up to 5% more, a long, close one up to 5% less.
    const lens = S.results.filter(x => x.a.length === m.a.length).map(length).concat(length(r));
    const d = ratingChange(avg(m.a), avg(m.b), winner === 0) * (1 + 0.05 * speedAmong(length(r), lens));
    r.changes = { ...adjust(m.a, d), ...adjust(m.b, -d) };
  }
  if (m.tm != null && S.tournament) { r.label = S.tournament.matches[m.tm].label; if (winner != null) recordTournament(m.tm, winner); }
  S.results.push(r);
  const now = Date.now();
  [...m.a, ...m.b].forEach((id, n) => { const p = P(id); if (p) { p.readyAt = now + n; p.first = false; p.since = now; } });
  c.match = null;
}
export function deleteResult(i) {
  const r = S.results.splice(i, 1)[0];
  for (const [id, d] of Object.entries(r.changes || {})) { const p = P(id); if (p) p.skill -= d; }
}
/** The spot for a newcomer: just before the first waiting player who has already played (so behind anyone still on 0 games). */
export function arrivalTime() {
  const q = queue();
  const pos = q.findIndex(p => played(p.id) > 0);
  if (pos < 0) return Date.now(); // nobody waiting has played: back of the line
  const after = q[pos].readyAt;
  // Just after the latest earlier arrival still ahead of them; 0-game players ahead may have later times.
  const earlier = q.slice(0, pos).map(p => p.readyAt).filter(t => t < after);
  const before = earlier.length ? Math.max(...earlier) : after - 2000;
  return (before + after) / 2;
}
/** Before the first game, everyone added starts as not here yet; they're marked present as they arrive. */
export function addPlayer(name, skill) {
  const p = { id: uid(), name, skill, pref: 'any', paused: false, readyAt: Date.now(), away: true };
  S.players.push(p);
  if (S.results.length || onCourt().size) arrive(p.id);
}
/** Marks someone present. They join the line like a late arrival: just ahead of everyone who has played (behind anyone still
    on 0 games), counted at par with the least-played player who has played (never below their own games), wait clock from now. */
export function arrive(id) {
  const p = P(id); if (!p?.away) return;
  const n = gamesCounted();
  const par = Math.min(Infinity, ...S.players.filter(x => !x.paused && !x.away && played(x.id) > 0).map(x => n[x.id]));
  const credit = Math.max(p.credit || 0, (par < Infinity ? par : 0) - played(id));
  Object.assign(p, { away: false, readyAt: arrivalTime(), since: Date.now(), credit: credit > 0 ? credit : null });
}

// ---------- replacing a player in "Next up" ----------
export const unevenness = (a, b) => Math.abs(avg(a) - avg(b));
export const isEven = (a, b) => unevenness(a, b) <= (a.length === 1 ? RANGE : FAIR) + 0.001;
export function arranged(a, b) {
  if (a.length !== 2 || isEven(a, b)) return { a, b };
  const four = players([...a, ...b]); if (four.length !== 4) return { a, b };
  const best = fairSplits(four)[0];
  return { a: best.a.map(p => p.id), b: best.b.map(p => p.id) };
}
export function swapped(p, out, inc) { const sub = ids => ids.map(x => x === out ? inc : x); return arranged(sub(p.a.map(x => x.id)), sub(p.b.map(x => x.id))); }
export function replacements(out, cid) {
  const c = courtById(cid); const here = c && nextPairing(c); if (!here) return [];
  const inGame = new Set([...here.a, ...here.b].map(p => p.id));
  const lined = {};
  for (const o of S.courts) { if (o.id === cid) continue; const np = nextPairing(o); if (np) [...np.a, ...np.b].forEach(p => lined[p.id] = o.name); }
  return eligible(c.format).filter(p => !inGame.has(p.id)).map(p => { const l = swapped(here, out, p.id); return { player: p, even: isEven(l.a, l.b), from: lined[p.id] || null }; });
}
export function replace(out, inc, cid) {
  const c = courtById(cid); const here = c && nextPairing(c); if (!here) return null;
  let other = null, ol = null;
  for (const o of S.courts) { if (o.id === cid) continue; const np = nextPairing(o); if (np && [...np.a, ...np.b].some(p => p.id === inc)) { other = o; ol = np; break; } }
  const mine = swapped(here, out, inc);
  c.plan = { a: mine.a, b: mine.b }; c.shuffles = 0;
  if (!other) return null;
  const busy = new Set([...mine.a, ...mine.b, ...[...ol.a, ...ol.b].map(p => p.id)]);
  const opts = eligible(other.format).filter(p => !busy.has(p.id)).map(p => ({ p, l: swapped(ol, inc, p.id) }));
  const lost = P(inc)?.name ?? '';
  const pk = opts.find(o => isEven(o.l.a, o.l.b)) || [...opts].sort((x, y) => unevenness(x.l.a, x.l.b) - unevenness(y.l.a, y.l.b))[0];
  if (!pk) { other.plan = null; return { court: other.name, lost, incoming: null, even: false }; }
  other.plan = { a: pk.l.a, b: pk.l.b }; other.shuffles = 0;
  return { court: other.name, lost, incoming: pk.p.name, even: isEven(pk.l.a, pk.l.b) };
}

// ---------- tournament: round robin, then double elimination ----------
export function buildTournament(format, entrants, advance) {
  const t = { format, entrants, advance, matches: [], seeds: null };
  const add = (stage, label, a, b) => { t.matches.push({ id: t.matches.length, stage, label, a, b, winner: null }); return t.matches.length - 1; };
  const num = (base, i, count) => count > 1 ? `${base} ${i + 1}` : base;
  const ring = entrants.map((_, i) => i); if (ring.length % 2) ring.push(-1);
  const n = ring.length;
  for (let r = 1; r < n; r++) {
    for (let i = 0; i < n / 2; i++) { const x = ring[i], y = ring[n - 1 - i]; if (x >= 0 && y >= 0) add('roundRobin', 'Round Robin', ['e', x], ['e', y]); }
    ring.splice(1, 0, ring.pop());
  }
  const order = advance === 8 ? [0, 7, 3, 4, 1, 6, 2, 5] : [0, 3, 1, 2];
  const upper = []; let slots = order.map(k => ['s', k]);
  while (slots.length > 1) {
    const name = slots.length === 2 ? 'Upper Final' : slots.length === 4 ? 'Upper Semifinal' : 'Upper Quarterfinal';
    const ids = []; for (let i = 0; i < slots.length; i += 2) ids.push(add('upper', num(name, i / 2, slots.length / 2), slots[i], slots[i + 1]));
    upper.push(ids); slots = ids.map(id => ['w', id]);
  }
  let round = 1, cur = [];
  for (let i = 0; i < upper[0].length; i += 2) cur.push(add('lower', num('Lower Round 1', i / 2, upper[0].length / 2), ['l', upper[0][i]], ['l', upper[0][i + 1]]));
  for (let r = 1; r < upper.length; r++) {
    round++;
    const last = r === upper.length - 1;
    const drops = r % 2 === 1 ? [...upper[r]].reverse() : upper[r];
    let next = []; cur.forEach((w, i) => { if (i < drops.length) next.push(add('lower', last ? 'Lower Final' : num(`Lower Round ${round}`, i, drops.length), ['w', w], ['l', drops[i]])); });
    cur = next;
    if (!last) { round++; next = []; for (let i = 0; i < cur.length; i += 2) next.push(add('lower', num(`Lower Round ${round}`, i / 2, cur.length / 2), ['w', cur[i]], ['w', cur[i + 1]])); cur = next; }
  }
  // ponytail: single Grand Final, no bracket reset — same as the iPad app
  add('final', 'Grand Final', ['w', upper[upper.length - 1][0]], ['w', cur[0]]);
  return t;
}
export function tEntrant(t, [k, v]) {
  if (k === 'e') return v;
  if (k === 's') return t.seeds && v < t.seeds.length ? t.seeds[v] : null;
  const m = t.matches[v]; if (m.winner == null) return null;
  return k === 'w' ? tEntrant(t, m.winner === 0 ? m.a : m.b) : tEntrant(t, m.winner === 0 ? m.b : m.a);
}
export function sidesIfReady(t, m) { if (m.winner != null) return null; const x = tEntrant(t, m.a), y = tEntrant(t, m.b); return x == null || y == null ? null : [x, y]; }
export const champion = t => { const m = t.matches[t.matches.length - 1]; return m?.stage === 'final' ? tEntrant(t, ['w', m.id]) : null; };
export function rrTable(t) {
  return t.entrants.map((_, e) => {
    let w = 0, l = 0;
    for (const m of t.matches) {
      if (m.stage !== 'roundRobin' || m.winner == null) continue;
      const x = tEntrant(t, m.a), y = tEntrant(t, m.b); if (e !== x && e !== y) continue;
      if ((m.winner === 0) === (e === x)) w++; else l++;
    }
    return { e, w, l };
  }).sort((a, b) => b.w - a.w || avg(t.entrants[b.e]) - avg(t.entrants[a.e]));
}
export function recordTournament(id, winner) {
  const t = S.tournament; t.matches[id].winner = winner;
  if (!t.seeds && t.matches.filter(m => m.stage === 'roundRobin').every(m => m.winner != null)) t.seeds = rrTable(t).map(r => r.e);
}
export function tournamentUpNext() {
  const t = S.tournament; if (!t) return [];
  const lastOff = ids => Math.max(-Infinity, ...players(ids).map(p => p.readyAt));
  const key = r => r.m.stage === 'roundRobin' ? [0, lastOff([...r.a, ...r.b]), r.m.id] : [1, 0, r.m.id];
  const ready = t.matches.map(m => { const s = sidesIfReady(t, m); return s && { m, a: t.entrants[s[0]], b: t.entrants[s[1]] }; }).filter(Boolean).sort((x, y) => cmp(key(x), key(y)));
  const taken = onCourt(); const out = [];
  for (const r of ready) {
    if ([...r.a, ...r.b].some(id => taken.has(id))) continue;
    out.push({ format: t.format, a: players(r.a), b: players(r.b), match: r.m.id, options: 1 });
    [...r.a, ...r.b].forEach(id => taken.add(id));
  }
  return out;
}
export const entrantName = e => S.tournament.entrants[e].map(id => P(id)?.name ?? 'Removed player').join(' & ');
export function tournamentEntrants(format) {
  const out = S.players.filter(p => p.paused || p.away); // sitting out or not here
  const active = S.players.filter(p => !p.paused && !p.away);
  if (format === 'singles') return { entrants: active.map(p => [p.id]), out };
  const s = [...active].sort((a, b) => b.skill - a.skill);
  if (s.length % 2) out.push(s.splice(Math.floor(s.length / 2), 1)[0]);
  const half = s.length / 2;
  return { entrants: Array.from({ length: half }, (_, i) => [s[i].id, s[s.length - 1 - i].id]), out };
}

// ---------- sessions ----------
export function nextSession(keepPlayers) {
  const now = Date.now();
  return {
    id: uid(), date: now, results: [], tournament: null,
    players: keepPlayers ? S.players.map((p, n) => ({ id: uid(), name: p.name, skill: p.skill, pref: 'any', paused: false, readyAt: now + n, away: true })) : [], // marked present as they arrive
    courts: S.courts.map(c => court(c.name, c.format)),
  };
}
export function returningPlayers() {
  const here = new Set(S.players.map(p => p.name.toLowerCase()));
  const latest = new Map();
  for (const x of [...past()].reverse()) for (const p of x.players) latest.set(p.name.toLowerCase(), p);
  return [...latest.entries()].filter(([k]) => !here.has(k)).map(([, p]) => p).sort((a, b) => a.name.localeCompare(b.name));
}
/** Everyone ever registered, one row per person (matched by name, ignoring case), with their latest rating. */
export function registry() {
  const out = new Map();
  for (const x of [...sessions.values()].sort((a, b) => a.date - b.date)) {
    for (const p of x.players) {
      const k = p.name.toLowerCase();
      const r = out.get(k) || { name: p.name, skill: p.skill, sessions: 0, played: 0, won: 0, last: x.date };
      r.name = p.name; r.skill = p.skill; r.last = x.date; r.sessions++;
      r.played += x.results.filter(g => g.a.includes(p.id) || g.b.includes(p.id)).length;
      r.won += x.results.filter(g => g.winner != null && (g.winner === 0 ? g.a : g.b).includes(p.id)).length;
      out.set(k, r);
    }
  }
  return [...out.values()].sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
}
export const isDupName = (name, except) => !!name && S.players.some(p => p.id !== except && p.name.toLowerCase() === name.toLowerCase());
export const setS = x => { S = x; }, setSessions = x => { sessions = x; }, setCurrentId = x => { currentId = x; };
export const getS = () => S, getSessions = () => sessions, getCurrentId = () => currentId;

// ---------- self-check: the matchmaking rules the iPad app is tested on ----------
export function selfCheck() {
  const keep = S;
  const pl = (skill, i) => ({ id: 'p' + i + '-' + skill, name: String(i), skill, pref: 'any', paused: false, readyAt: i });
  S = { players: [], courts: [], results: [], tournament: null };
  const d = pickDoubles([5, 1, 4, 2].map(pl));
  console.assert(d.a.map(p => p.skill).join() === '5,1' && d.b.map(p => p.skill).join() === '4,2', 'doubles pairs strong with new');
  const mixed = fairSplits([3.9, 3.8, 2, 1.1].map(pl));
  console.assert(mixed.length === 2, 'no stacked doubles split');
  const g = pickDoubles([5, 5, 5, 1, 3, 3].map(pl));
  console.assert(Math.abs(sum(g.a) - sum(g.b)) < 0.01, 'doubles group should be fair');
  console.assert(pickSingles([3, 5, 5, 1, 1, 5, 3].map(pl), [])?.b[0].name === '6', 'singles stays within skill range');
  const t = buildTournament('singles', [0, 1, 2, 3, 4].map(i => ['x' + i]), 4);
  console.assert(t.matches.length === 16, 'tournament game count');
  // Two doubles courts both get a game, nobody twice; shuffling one leaves the other alone.
  S = { players: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(i => pl(3, i)), courts: [court('C1', 'doubles'), court('C2', 'doubles')], results: [], tournament: null };
  const ids = c => { const p = nextPairing(c); return p ? [...p.a, ...p.b].map(x => x.id).join() : ''; };
  const c2 = ids(S.courts[1]);
  console.assert(ids(S.courts[0]) && c2 && new Set((ids(S.courts[0]) + ',' + c2).split(',')).size === 8, 'two doubles courts both get a game');
  for (let i = 0; i < 3; i++) shuffleCourt(S.courts[0].id);
  console.assert(ids(S.courts[1]) === c2 && ids(S.courts[0]), 'shuffling one court leaves the other alone');
  // Standings: 5 of 5 beats 6 of 7 at the same pace; quick wins count more; 5 close wins still beat 1 win.
  const game = (w, l, mins = 10, won = true) => ({ a: [w], b: [l], winner: won ? 0 : 1, start: 0, end: mins * 60000 });
  S = { players: [], courts: [], results: [...Array(6).fill(game('A', 'X')), game('A', 'X', 10, false), ...Array(5).fill(game('B', 'X'))], tournament: null };
  console.assert(score('B') > score('A'), '5 of 5 should rank above 6 of 7');
  S.results.push(game('A', 'X', 4));
  console.assert(speed(S.results.at(-1)) === 1 && speed(S.results[0]) === 0, 'quick game is one-sided, usual game is neutral');
  const fastWin = score('A'); S.results[S.results.length - 1] = game('A', 'X', 20);
  console.assert(score('A') < fastWin, 'a quick win counts more than a close one');
  S.results = [...Array(5).fill(game('B', 'X', 18)), game('A', 'X'), ...Array(5).fill(game('Y', 'Z'))];
  console.assert(score('B') > score('A'), '5 close wins should still beat 1 win');
  S.results = [...Array(4).fill(game('A', 'X', 18)), ...Array(3).fill(game('B', 'X', 4)), game('B', 'X', 4, false), ...Array(5).fill(game('Y', 'Z'))];
  console.assert(score('A') > score('B'), 'an extra win outweighs any game length');
  S = { players: [pl(3, 1), pl(3, 2)], courts: [], results: [{ a: ['p1-3'], b: ['x'] }], tournament: null };
  console.assert(queue()[0].name === '2', 'fewer games goes first');
  S.players[0].first = true;
  console.assert(queue()[0].name === '1', 'moved to front beats fewer games');
  // Doubles: similar groups, repeat avoidance, balanced teams for new partners, rest first.
  S = { players: [], courts: [], results: [], tournament: null };
  const eight = [5, 4.8, 4.6, 4.4, 4.2, 4.1, 4, 3.9].map(pl);
  const lastGame = (a, b) => { const r = {}; for (const [mine, theirs] of [[a, b], [b, a]]) for (const i of mine)
    r[eight[i].id] = { partners: new Set(mine.filter(x => x !== i).map(x => eight[x].id)), opponents: new Set(theirs.map(x => eight[x].id)) }; return r; };
  const again = pickDoubles(eight, 0, { recent: lastGame([0, 3], [1, 2]) });
  console.assert(repeats(again.a, again.b, lastGame([0, 3], [1, 2])) === 0 && again.note == null, 'avoid repeating last game');
  const firstTry = pickDoubles(eight);
  // Too few players for similar groups (under 8 per doubles court): balanced teams in queue order instead.
  const lineup = extra => ({ players: [5.0, 2.6, 4.6, 3.0, 5.0, 4.8, 4.9, 2.8, ...Array(extra).fill(3)].map((sk, i) => ({ ...pl(sk, i), name: String(i), readyAt: Date.now() - 60000 + i })),
    courts: [court('C1', 'doubles'), court('C2', 'doubles')], results: [], tournament: null });
  const names4 = g => [...g.a, ...g.b].map(p => p.name).sort().join();
  S = lineup(0);
  console.assert(balancedOnly() && names4(pick('doubles', queue())) === '0,1,2,3', 'too few players: the first in line with the next who make even teams');
  S = lineup(8);
  console.assert(!balancedOnly() && names4(pick('doubles', queue())) === '0,2,4,5', 'enough players: similar-skill groups');
  S = { players: [], courts: [], results: [], tournament: null };
  // Ties on fewest games: the hardest to match heads the game (four strong players rather than mid-rated ones first in line).
  S = { players: [3.0, 5.0, 4.9, 4.8, 4.7, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3].map((sk, i) => ({ ...pl(sk, i), name: i < 12 ? String(i) : 'x' + (i - 12), readyAt: Date.now() - 60000 + i })),
    courts: [court('C1', 'doubles'), court('C2', 'doubles')], results: [], tournament: null };
  for (const p of S.players) S.results.push({ a: [p.id], b: ['x'] });
  console.assert(names4(pick('doubles', queue())) === '1,2,3,4', 'on ties, the hardest to match goes first');
  S = { players: [], courts: [], results: [], tournament: null };
  // Four rested but no fair game among them: they play anyway, strongest with weakest, rather than call anyone back.
  const four4 = [5.0, 3.1, 3.3, 3.2, 4.5, 2.9, 3.0, 3.6].map(pl);
  const rest4 = pickDoubles(four4, 0, { justOff: new Set(four4.slice(4).map(p => p.id)) });
  console.assert([...rest4.a, ...rest4.b].map(p => p.name).sort().join() === '0,1,2,3' && [rest4.a, rest4.b].some(t => t.map(p => p.name).sort().join() === '0,1')
    && /straight back/.test(rest4.note), 'four rested play, strongest with weakest, nobody called back');
  // Fewest games before fewest repeats: A, B and C (1 game each) play although A and B met last game; D, E, F have 3.
  const fg = ['H', 'A', 'B', 'C', 'D', 'E', 'F'].map((n, i) => ({ ...pl(3, i), name: n }));
  const fgGame = pickDoubles(fg, 0, { recent: { [fg[1].id]: { partners: new Set(), opponents: new Set([fg[2].id]) }, [fg[2].id]: { partners: new Set(), opponents: new Set([fg[1].id]) } },
    games: Object.fromEntries(fg.slice(1).map(p => [p.id, 'ABC'.includes(p.name) ? 1 : 3])) });
  console.assert([...fgGame.a, ...fgGame.b].map(p => p.name).sort().join() === 'A,B,C,H', 'fewest games fill a game before fewest repeats');
  console.assert([...firstTry.a, ...firstTry.b].map(p => p.name).sort().join() === '0,1,2,3', 'no history: earliest similar group');
  const top = [5, 5, 5, 5, 3, 3, 3, 3].map(pl), topRecent = {};
  for (let i = 0; i < 4; i++) topRecent[top[i].id] = { partners: new Set([top[i ^ 1].id]), opponents: new Set([0, 1, 2, 3].filter(x => (x >> 1) !== (i >> 1)).map(x => top[x].id)) };
  const mixedUp = pickDoubles(top, 0, { recent: topRecent });
  console.assert(mixedUp.note === 'mixed teams for new partners' && repeats(mixedUp.a, mixedUp.b, topRecent) < REPEAT_LIMIT, 'balanced teams break up a repeat');
  const resting = [5, 4.2, 3.8, 3.0, 5, 5, 4.8].map(pl);
  const restGame = pickDoubles(resting, 0, { justOff: new Set(resting.slice(4).map(p => p.id)) });
  console.assert([...restGame.a, ...restGame.b].map(p => p.name).sort().join() === '0,1,2,3' && restGame.note === 'mixed teams so nobody goes straight back', 'rest first');
  // Overdue: everyone waiting 20+ minutes plays next; an overdue game stays within 2 levels.
  const fresh = i => ({ ...pl(3, i), readyAt: Date.now() - 60000 + i });
  S = { players: [0, 1, 2, 3, 4, 5, 6, 7].map(fresh), courts: [], results: [], tournament: null };
  for (const i of [6, 7]) { S.players[i].since = Date.now() - 50 * 60000; S.results.push({ a: [S.players[i].id], b: ['x'] }); }
  const od = pick('doubles', queue());
  console.assert([S.players[6].id, S.players[7].id].every(x => [...od.a, ...od.b].some(p => p.id === x)) && /waited/.test(od.note), 'overdue players play next');
  // More overdue than a court takes: fewest games first, and a late arrival counts at par (not ahead for the games they missed).
  S = { players: ["C", "D", "E", "F", "A", "Late", "G", "H"].map((nm, i) => ({ ...fresh(i), name: nm })), courts: [], results: [], tournament: null };
  for (const [i, games, mins] of [[0, 2, 25], [1, 2, 25], [2, 2, 25], [3, 2, 25], [5, 0, 40], [4, 3, 50]]) {
    S.players[i].since = Date.now() - mins * 60000;
    for (let k = 0; k < games; k++) S.results.push({ a: [S.players[i].id], b: ["x"] });
  }
  S.players[5].credit = 3;
  const few = pick("doubles", queue());
  console.assert([...few.a, ...few.b].map(p => p.name).sort().join() === "C,D,E,F", "overdue: fewest games first, a late arrival at par");
  S = { players: [5, 4.5, 3.5, 3, 3, 3, 2, 1].map((sk, i) => ({ ...fresh(i), skill: sk })), courts: [], results: [], tournament: null };
  S.players[0].since = Date.now() - 35 * 60000; S.results.push({ a: [S.players[0].id], b: ['x'] });
  const st = pick('doubles', queue()), stSk = [...st.a, ...st.b].map(p => p.skill);
  console.assert(stSk.includes(5) && Math.max(...stSk) - Math.min(...stSk) <= OVERDUE_SPREAD + 1e-9, 'an overdue game stays within 2 levels');
  // Late arrivals: behind 0-game players, ahead of everyone who has played, at par; then the normal order.
  S = { players: ['X', 'Y', 'Z'].map((n, i) => ({ ...fresh(i), name: n })), courts: [], results: [], tournament: null };
  for (let i = 0; i < 3; i++) S.results.push({ a: [S.players[0].id], b: [S.players[1].id] });
  S.players[2].readyAt = Date.now() - 10000;
  addPlayer('Late', 3);
  console.assert(queue().map(p => p.name).join() === 'Z,Late,X,Y' && S.players[3].credit === 3, 'late arrival goes after 0-game players, at par');
  // Present: before the first game, players added are not here yet; marked present, they join in order of arrival.
  S = { players: [], courts: [], results: [], tournament: null };
  for (const nm of ['P', 'Q', 'R']) addPlayer(nm, 3);
  console.assert(!queue().length && activePlayers() === 0, "at the start, players aren't here until marked present");
  const rn = Date.now; arrive(S.players[2].id); Date.now = () => rn() + 1000; arrive(S.players[0].id); Date.now = rn;
  console.assert(queue().map(p => p.name).join() === 'R,P', 'they join the line in the order they arrive');
  // Marked present later, they come in like a late arrival: after 0-game players, at par.
  S = { players: ['X', 'Y', 'Z', 'W'].map((n, i) => ({ ...fresh(i), name: n })), courts: [], results: [], tournament: null };
  S.players[3].away = true;
  for (let i = 0; i < 3; i++) S.results.push({ a: [S.players[0].id], b: [S.players[1].id] });
  S.players[2].readyAt = Date.now() - 10000;
  console.assert(!queue().some(p => p.name === 'W'), 'not here: out of the line');
  arrive(S.players[3].id);
  console.assert(queue().map(p => p.name).join() === 'Z,W,X,Y' && S.players[3].credit === 3, 'marked present: like a late arrival, at par');
  // Just off court: behind everyone rested even when behind on games (a late arrival's credit can leave them lowest).
  S = { players: ['A', 'B', 'C', 'D', 'E'].map((n, i) => ({ ...fresh(i), name: n })), courts: [], results: [], tournament: null };
  for (let i = 1; i <= 4; i++) for (let k = 0; k < 4; k++) S.results.push({ a: [S.players[i].id], b: ['x'] });
  for (let k = 0; k < 3; k++) S.results.push({ a: [S.players[0].id], b: ['x'] });
  console.assert(queue().map(p => p.name).join() === 'B,C,D,E,A', 'just off court waits behind everyone rested');
  // Partner requests: one even game together per session, never in the first game, then like anyone else.
  S = { players: [3.5, 3, 3, 3, 3, 3, 3, 2.5].map((sk, i) => ({ ...fresh(i), skill: sk })), courts: [], results: [], tournament: null };
  const [dx, dy] = [S.players[0].id, S.players[7].id], id = i => S.players[i].id;
  const gapOf = g => Math.abs(sum(g.a) - sum(g.b)) / 2;
  setPartner(dx, dy);
  console.assert(!pairWaiting(dx, dy) && pairsKeptApart().length === 1, 'start of the night: kept apart until each has played');
  for (const x of [dx, dy]) S.results.push({ a: [x, id(3)], b: [id(4), id(5)] });
  S.results.push({ a: [id(1), id(2)], b: [id(6), id(4)] });
  const duo = pick('doubles', eligible('doubles'));
  console.assert([duo.a, duo.b].some(t => t.map(p => p.id).sort().join() === [dx, dy].sort().join()) && gapOf(duo) <= PAIR_SLACK + 1e-9, 'a waiting pair gets an even game');
  console.assert(duo.options >= 2, "shuffle stays available on a pair's game");
  const beforeGame = clone(S.results);
  S.results.push({ a: [dx, dy], b: [id(1), id(2)] });
  console.assert(!pairWaiting(dx, dy) && !pairsKeptApart().length && !partnerGames(queue(), queue(), [], new Set()).length, 'after their game the pair is like anyone else');
  S.results = beforeGame; S.courts = [court('C1', 'doubles'), court('C2', 'doubles')];
  console.assert(pairingMinimum() === 14 && !pairingActive() && !partnerGames(queue(), queue(), [], new Set()).length && !pairsKeptApart().length, 'pair requests wait for 14 players on 2 courts');
  // A far-apart pair (4.9 & 3.0) still gets an even game.
  S = { players: [4.9, 4.0, 3.9, 3.5, 3.2, 3.1, 3.0, 2.8].map((sk, i) => ({ ...fresh(i), skill: sk })), courts: [], results: [], tournament: null };
  setPartner(id(0), id(6));
  S.results.push({ a: [id(0), id(7)], b: [id(5), id(4)] }, { a: [id(6), id(7)], b: [id(5), id(4)] });
  const wideGames = partnerGames(queue(), queue(), [], new Set());
  console.assert(wideGames.length && wideGames.every(g => gapOf(g) <= PAIR_SLACK + 1e-9), 'a far-apart pair still gets an even game');
  const rested = partnerGames(queue(), queue(), [], new Set([id(2)]));
  console.assert(rested.length && !rested.some(g => [...g.a, ...g.b].some(p => p.id === id(2))), 'a pair game calls nobody straight back');
  // One pair game at a time, and never two pairs in one game.
  S = { players: Array.from({ length: 16 }, (_, i) => fresh(i)), courts: [court('C1', 'doubles'), court('C2', 'doubles')], results: [], tournament: null };
  setPartner(id(0), id(1)); setPartner(id(2), id(3));
  for (const [a, b] of [[[0, 4], [5, 6]], [[1, 7], [8, 9]], [[2, 10], [11, 12]], [[3, 13], [14, 15]], [[4, 5], [6, 7]]]) S.results.push({ a: a.map(id), b: b.map(id) });
  const isPair = g => isPairGame(g.a.map(p => p.id), g.b.map(p => p.id));
  console.assert(queueUpNext().filter(isPair).length === 1, 'exactly one pair game lined up at a time');
  console.assert(!queueUpNext().some(g => [g.a, g.b].every(t => requestedPairs().some(pr => pr.every(x => t.some(p => p.id === x))))), 'never two pairs in one game');
  fill(S.courts.find(c => { const n = nextPairing(c); return n && isPair(n); }).id);
  console.assert(pairGameOnCourt() && !queueUpNext().some(isPair), 'no second pair game while one is playing');
  // Locking a side: shuffle keeps it and changes only the other side.
  S = { players: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map(fresh), courts: [court('C', 'doubles')], results: [], tournament: null };
  const lc = S.courts[0], lockedA = nextPairing(lc).a.map(p => p.id).sort().join(), seenB = new Set();
  lockSide(lc.id, 0);
  for (let i = 0; i < 4; i++) {
    shuffleCourt(lc.id);
    const g = nextPairing(lc);
    console.assert(g.a.map(p => p.id).sort().join() === lockedA && g.b.length === 2 && !g.b.some(p => lockedA.includes(p.id)), 'a locked side stays put');
    seenB.add(g.b.map(p => p.id).sort().join());
  }
  console.assert(seenB.size === 4, 'shuffle with a lock keeps changing the other side');
  S = keep;
}
