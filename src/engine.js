// Rules port shared with the iPad app; RULES.md is the spec. No browser UI or persistence here.
// ---------- constants & helpers ----------
export const NEED = { singles: 2, doubles: 4 };
export const SKILL = ['New', 'Beginner', 'Intermediate', 'Advanced', 'Strong'];
// What each level button sets (Add Player, Edit Player's "Set level"). Names still follow the rounded rating, and each preset rounds to its own level.
export const PRESETS = [1, 1.75, 2.5, 3.5, 4.5];
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
export const WAIT_CAP = 30 * 60000;
export const OVERDUE_SPREAD = 2.0;
export const K = 0.3, SPREAD = 2; // rating: most one game can move it; level gap where the stronger side is ~90% to win
// ponytail: how fast ratings settle, like the iPad app: a new player's first NEW_GAMES games move NEW_K times as much, a regular's REG_K times
export const NEW_GAMES = 8, NEW_K = 1.5, REG_K = 0.75;
// Streaks (matching only): 3 wins in a row counts as 0.5 higher, each further win 0.5 more, at most 1.5; losses the same, lower.
export const STREAK = 3, STREAK_BOOST = 0.5, STREAK_STEP = 0.5, STREAK_MAX = 1.5;
// ponytail: hot/cold teaming, chosen by simulation: partners within 1.0 level, teams within 0.25, all four within 2 levels
export const HOTCOLD_GAP = 1.0, HOTCOLD_SLACK = 0.25, HOTCOLD_RANGE = 2.0;
export const LATE_FIRST = 4, LATE_PER_GAME = 2; // late arrivals go first while fewer than 4 are waiting; at most 2 in a game
export const NOTE_AFTER = 25 * 60000; // the court names someone overdue only once they've waited this long
export const LATE_AFTER = 30 * 60000; // arrivals in the first 30 minutes after the first game count as on time (no credit), like the iPad app
// ponytail: chosen by simulation, like the iPad app: similar-skill groups from 6.25 players per doubles court (13 for 2 courts,
// 19 for 3, 25 for 4); fewer, balanced teams. EVEN_REPEAT: an even-games pick that repeats this much (all four met lately) gives way.
export const BALANCED_BELOW = 6.25, EVEN_REPEAT = 6;
export const LOCK_GAME_LEAD = 1;
export const LOCK_EQUAL = 0.05; // locked teammates: opponents' average at least the pair's (within display rounding)
export const LS_KEY = 'shuttle-queue-v2';
export const THEME_KEY = 'shuttle-queue-theme'; // per-viewer: system, light or dark

export const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
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
export const past = () => [...sessions.values()].filter(x => x.id !== currentId).sort((a, b) => b.date - a.date); // every other session
export const title = x => x.name || new Date(x.date).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
export const clock = t => new Date(t).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
/** When play began (the first game's start), and when the planned length runs out. */
export function startedAt(x = S) {
  const t = [...x.results.map(r => r.start), ...x.courts.filter(c => c.match).map(c => c.match.start)].filter(Number.isFinite);
  return t.length ? Math.min(...t) : null;
}
/** When this player's wait began: their last game's end, or when they arrived. Sitting out doesn't restart it, and nothing
    counts before the session's first game (before then it's now, so nobody is overdue). The 20-minute rule and the queue's minutes use it. */
export const waitStart = p => Math.max(p.since ?? p.readyAt, startedAt() ?? Date.now());
/** " · 12 min" waited, on the wait rule's clock (orange from 20, when the rule puts them in the next game); '' before play starts. */
export function waitedLabel(p) {
  if (S.ended != null || startedAt() == null) return '';
  const mins = Math.floor((Date.now() - waitStart(p)) / 60000);
  return ` · <span class="${mins * 60000 >= WAIT_PRIORITY ? 'warnc' : ''}">${mins} min</span>`;
}
export const endsAt = (x = S) => x.hours && startedAt(x) != null ? startedAt(x) + x.hours * 3600000 : null;
/** "2 h · until 9:30 PM · 1 hr, 20 min left", or "2 h · not started"; '' without a planned length. */
export function lengthLabel(x, now = Date.now()) {
  if (!x.hours) return '';
  const len = `${x.hours} h`, end = endsAt(x);
  if (end == null) return `${len} · not started`;
  const mins = Math.round((end - now) / 60000), h = Math.floor(mins / 60), mm = mins % 60;
  return mins > 0 ? `${len} · until ${clock(end)} · ${[h ? h + ' hr' : '', mm ? mm + ' min' : ''].filter(Boolean).join(', ')} left` : `${len} · time's up (${clock(end)})`;
}
/** All Players edits: renames and re-rates this person (by name, ignoring case) in every session; returns the sessions changed. */
export function editEverywhere(old, name, skill = null) {
  const changed = [];
  for (const x of sessions.values()) {
    let hit = false;
    for (const p of x.players) if (p.name.toLowerCase() === old.toLowerCase()) { p.name = name; if (skill != null) p.skill = skill; hit = true; }
    if (hit) changed.push(x);
  }
  return changed;
}
/** Saved before live sessions: every session but the open one had ended. Marks them; returns the sessions changed. */
export function markEndedOnce() {
  const changed = [];
  for (const x of sessions.values()) if (x.id !== currentId && x.ended == null) {
    x.ended = Math.max(x.date, ...x.results.map(r => r.end || 0)); changed.push(x);
  }
  return changed;
}

export const blankSession = () => ({
  id: uid(), date: Date.now(), players: [], results: [], tournament: null,
  courts: [court('Court 1', 'doubles'), court('Court 2', 'singles')],
});
export function court(name, format) { return { id: uid(), name, format, match: null, shuffles: 0, plan: null, locked: null, manual: null }; }

// ---------- session basics ----------
export const P = id => S.players.find(p => p.id === id);
export const players = ids => ids.map(P).filter(Boolean);
export const courtById = id => S.courts.find(c => c.id === id);
/** The games that count. A cancelled game (no result) stays in the history but isn't a game: it doesn't count towards
    anyone's games, partners, repeats or ratings, and its players went back to where they were in line. */
export const counted = (x = S) => x.results.filter(r => r.winner != null);
export const played = id => counted().filter(r => r.a.includes(id) || r.b.includes(id)).length;
export const wins = id => S.results.filter(r => r.winner != null && (r.winner === 0 ? r.a : r.b).includes(id)).length;
export const avg = ids => { const s = players(ids).map(p => p.skill); return s.length ? s.reduce((a, b) => a + b, 0) / s.length : 3; };
export const sum = ps => ps.reduce((a, p) => a + p.skill, 0);
export const names = ids => ids.map(id => P(id)?.name ?? 'Removed player').join(' & ');
export function onCourt() { return new Set(S.courts.flatMap(c => c.match ? [...c.match.a, ...c.match.b] : [])); }
/** Games played plus any arrival credit: what "fewest games first" compares. */
export function gamesCounted() {
  const n = {};
  for (const p of S.players) n[p.id] = p.credit || 0;
  for (const r of counted()) for (const id of [...r.a, ...r.b]) if (id in n) n[id]++;
  const penalty=scheduledPenalties();
  for (const id in n) n[id]+=penalty[id]||0;
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
/** Keeps as many of the first `must` (anyone overdue, longest waiting first) as fair teams allow. */
export function fairFour(q, must = 1) {
  const pool = q.slice(0, 12);
  for (let keep = Math.max(1, must); keep >= 1; keep--) for (let k = 3; k < pool.length; k++) for (let j = 2; j < k; j++) for (let i = 1; i < j; i++) {
    let ok = true; for (let m = 1; m < keep; m++) if (![i, j, k].includes(m)) ok = false;
    if (!ok) continue;
    const four = [pool[0], pool[i], pool[j], pool[k]];
    const b = fairSplits(four)[0];
    if (Math.abs(sum(b.a) - sum(b.b)) / 2 <= FAIR) return four;
  }
  return pool.slice(0, 4);
}
/** Each player's partners and opponents over their last two doubles games this session. */
export function recentPairs(games = 3) {
  const out = {}, seen = {};
  for (const r of counted().reverse()) {
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
export function bestFour(q, pool, recent, justOff, { bySpread = false, must = 1, together = null, games = {}, heavyFirst = false, allowed }) {
  if (pool.length < 3) return null;
  let best = null;
  const lk = lockCtx ? lockCtx.locks.filter(l => q.some(p => p.id === l.x) && q.some(p => p.id === l.y)) : [];
  const idsOf = t => t.map(p => p.id);
  for (let k = 2; k < pool.length; k++) for (let j = 1; j < k; j++) for (let i = 0; i < j; i++) {
    const picked = [pool[i], pool[j], pool[k]], four = [q[0], ...picked.map(x => q[x])];
    let ok = true;
    for (let m = 1; m < must; m++) if (!picked.includes(m)) { ok = false; break; }
    if (!ok || !allowed(four) || (lk.length && !lockMembers(idsOf(four), lk))) continue;
    const teamHas = (t, ids) => ids.every(id => t.some(p => p.id === id));
    const fair = fairSplits(four).filter(s => (!together || [s.a, s.b].some(t => teamHas(t, together)))
      && (!lk.length || keepsLocks(idsOf(s.a), idsOf(s.b), lk, lockCtx.strict, lockCtx.protection)));
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
/** `accept`: an extra test every four must pass (a hot/cold game's limits for the others). */
export function pickDoubles(q, choice = 0, { recent = {}, must = 1, justOff = new Set(), together = null, accept = () => true, capSpread = null, games = {}, balancedOnly = false } = {}) {
  if (q.length < 4) return null;
  const head = q[0];
  // How far a pick falls short: players straight off court first (rest beats skill match), then repeats past the limit.
  const shortfall = g => g ? [g.justOff, g.penalty >= REPEAT_LIMIT ? g.penalty : 0] : [Infinity, Infinity];
  const fine = g => cmp(shortfall(g), [0, 0]) === 0;
  const reason = (from, to) => (from?.justOff ?? 0) > to.justOff ? (to.justOff ? 'so fewer go straight back' : 'so nobody goes straight back') : 'for new partners';
  const similarGroup = spread => {
    const near = [...new Set([...Array.from({ length: must - 1 }, (_, i) => i + 1),
      ...q.map((_, i) => i).slice(1).filter(i => Math.abs(q[i].skill - head.skill) <= spread + 1e-9).slice(0, 12)])].sort((a, b) => a - b);
    return bestFour(q, near, recent, justOff, { must, together, games, allowed: four => { const s = four.map(p => p.skill); return Math.max(...s) - Math.min(...s) <= spread + 1e-9 && accept(four); } });
  };
  // balancedOnly (too few players for similar groups): straight to even teams, in queue order, no rating-range preference.
  let best = balancedOnly ? null : similarGroup(SIMILAR), note = null;
  if (!balancedOnly && !fine(best)) {
    const w = similarGroup(WIDER);
    if (w && cmp(shortfall(w), shortfall(best)) < 0) { note = 'wider skill range ' + reason(best, w); best = w; }
  }
  if (!fine(best)) {
    // Balanced teams from the nearest ratings; an overdue game (capSpread) stays within that many levels unless nothing else is free.
    const balanced = cap => bestFour(q, q.map((_, i) => i).slice(1, 12), recent, justOff, { bySpread: !balancedOnly, heavyFirst: balancedOnly, must, together, games,
      allowed: four => { const t = fairSplits(four)[0], sk = four.map(p => p.skill);
        return Math.abs(sum(t.a) - sum(t.b)) / 2 <= FAIR && accept(four) && (cap == null || Math.max(...sk) - Math.min(...sk) <= cap + 1e-9); } });
    const b = balanced(capSpread) || (!best && capSpread != null ? balanced(null) : null);
    if (b && cmp(shortfall(b), shortfall(best)) < 0) { note = balancedOnly ? null : best ? 'mixed teams ' + reason(best, b) : 'mixed teams, no similar group free'; best = b; }
  }
  if (!best && together) return null;
  // Nobody straight back while four rested players can play: the evenest four of them, uneven teams if it must be.
  const fallback = best ? [] : fairFour(q, must);
  if (!together && (best ? best.justOff : fallback.filter(p => justOff.has(p.id)).length) > 0) {
    const four = restedFour(q, must, justOff);
    if (four && lastResortSplits(four).length) { const t = lastResortSplits(four)[0]; return { format: 'doubles', a: t.a, b: t.b, options: 1, note: 'uneven teams so nobody goes straight back' }; }
  }
  const splits = best ? best.splits : lastResortSplits(fallback);
  if (!splits.length) return null;
  if (!best) note = lockCtx && Math.abs(sum(splits[0].a)-sum(splits[0].b))/2>FAIR ? 'uneven teams to keep released teammates apart' : 'mixed teams, no similar group free';
  const s = splits[choice % splits.length];
  return { format: 'doubles', a: s.a, b: s.b, options: splits.length, note };
}
/** The first in line (if rested) plus the three rested players, of the first 12, who make the evenest teams, however uneven;
    anyone overdue (the first `must`) included. null if fewer than four are rested. */
export function restedFour(q, must, justOff) {
  if (!q.length || q.slice(0, Math.max(1, must)).some(p => justOff.has(p.id))) return null; // the first in line and anyone overdue must play
  const r = q.filter(p => !justOff.has(p.id)).slice(0, 12);
  if (r.length < 4) return null;
  let best = null;
  for (let k = 3; k < r.length; k++) for (let j = 2; j < k; j++) for (let i = 1; i < j; i++) {
    let ok = true; for (let m = 1; m < must; m++) if (![i, j, k].includes(m)) ok = false;
    if (!ok) continue;
    const four = [r[0], r[i], r[j], r[k]], t = lastResortSplits(four)[0];
    if (!t) continue;
    const gap = Math.abs(sum(t.a) - sum(t.b));
    if (!best || gap < best.gap - 1e-9) best = { gap, four };
  }
  return best && best.four;
}
/** Last resort: the fairest split of these four. */
export function lastResortSplits(four) {
  const s = [...four].sort((x, y) => y.skill - x.skill);
  const all = [[[s[0],s[3]],[s[1],s[2]]],[[s[0],s[2]],[s[1],s[3]]],[[s[0],s[1]],[s[2],s[3]]]];
  // The fairest raw split can put a released pair back together and deadlock an otherwise playable court.
  const valid = all.filter(([a,b])=>!lockCtx || keepsLocks(a.map(p=>p.id),b.map(p=>p.id),lockCtx.locks,lockCtx.strict,lockCtx.protection));
  valid.sort((x,y)=>Math.abs(sum(x[0])-sum(x[1]))-Math.abs(sum(y[0])-sum(y[1])));
  return valid.length ? [{a:valid[0][0],b:valid[0][1]}] : [];
}
export const lastOffCourt = () => { const r = counted().at(-1); return new Set(r ? [...r.a, ...r.b] : []); };
export const activePlayers = () => S.players.filter(p => !p.paused && !p.away).length; // sitting out and not here don't count
/** All courts doubles and fewer than 6.25 players per court here: balanced teams instead of similar-skill groups. */
export const balancedOnly = () => S.courts.length > 0 && S.courts.every(c => c.format === 'doubles') && activePlayers() < BALANCED_BELOW * S.courts.length;
/** Hot/cold teaming: when someone on a win streak (or losing streak) is about to play and someone on the opposite streak within
    1.0 level is resting near the front (first 8, then 12), they're teammates, against even opponents (teams within 0.25, all four
    within 2 levels). The first in line still plays and nobody is called straight back. No court note. */
export function hotColdGame(pool, picked, overdue, justOff) {
  if (overdue.length > 2) return null;
  const games = gamesCounted(), sign = id => Math.sign(streakBoost(id)), real = p => p.skill; // the line carries ratings with streak boosts
  for (const depth of [8, 12]) {
    const near = pool.slice(0, depth);
    for (const x of picked) {
      const sx = sign(x.id); if (!sx || justOff.has(x.id)) continue;
      const ys = near.filter(p => p.id !== x.id && sign(p.id) === -sx && !justOff.has(p.id) && Math.abs(real(p) - real(x)) <= HOTCOLD_GAP + 1e-9)
        .sort((a, b) => Math.abs(real(a) - real(x)) - Math.abs(real(b) - real(x)));
      for (const y of ys) {
        const front = [...overdue]; for (const p of [...pool.slice(0, 1), x, y]) if (!front.some(o => o.id === p.id)) front.push(p);
        if (front.length > 4) continue;
        const ids = new Set(front.map(p => p.id)), sk = four => four.map(real);
        const ok = four => Math.abs(x.skill + y.skill - sum(four.filter(p => p.id !== x.id && p.id !== y.id))) / 2 <= HOTCOLD_SLACK + 1e-9
          && !four.some(p => justOff.has(p.id)) && Math.max(...sk(four)) - Math.min(...sk(four)) <= HOTCOLD_RANGE + 1e-9;
        const g = pickDoubles([...front, ...near.filter(p => !ids.has(p.id))], 0, { recent: recentPairs(), must: front.length, justOff, together: [x.id, y.id], accept: ok, games });
        if (g) { g.note = null; return g; }
      }
    }
  }
  return null;
}
// ---------- locked teammates ----------
/** Locked teams preserve rating, rest and game-count protections; cooldown and overdue unmatchable players are selected independently. */
export const lockedPairs = () => S.players.filter(p => p.lock && P(p.lock)?.lock === p.id && p.id < p.lock).map(p => [p.id, p.lock]);
export const isLocked = p => !!p.lock && P(p.lock)?.lock === p.id;
/** Wins in a row the pair has as teammates, counted back from their latest game. */
export function lockStreak(x, y) {
  let n = 0;
  for (const r of counted().reverse()) {
    if (!r.a.includes(x) && !r.b.includes(x)) continue;
    const team = r.a.includes(x) ? r.a : r.b;
    if (!team.includes(y) || (r.winner === 0 ? r.a : r.b) !== team) break;
    n++;
  }
  return n;
}
export const splitDue = (x, y) => Math.max(lockStreak(x, y), lockStreak(y, x)) >= STREAK;
/** Sets (or clears, with null) a lock, ending any lock either player had. */
export function setLock(id, other) {
  for (const p of S.players) if (p.id === id || p.id === other || (p.lock && (p.lock === id || p.lock === other))) p.lock = null;
  if (other && P(id) && P(other)) { P(id).lock = other; P(other).lock = id; }
}
export let lockCtx = null; // during a doubles pick: { locks: [{ x, y, apart }], strict }, read by bestFour and the overdue rule
/** The locked pairs with both partners in this line, each with whoever is first in line as `x` (same order as the iPad app). */
export function lockContext(line) {
  const at = id => line.findIndex(p => p.id === id);
  return lockedPairs().filter(([x, y]) => at(x) >= 0 && at(y) >= 0)
    .map(([x, y]) => at(x) <= at(y) ? { x, y, apart: splitDue(x, y) } : { x: y, y: x, apart: splitDue(x, y) }).sort((a,b) => at(a.x)-at(b.x));
}
export const realAvg = ids => ids.reduce((a, id) => a + (P(id)?.skill ?? 3), 0) / ids.length;
/** Both partners of a normal lock in the game, or neither; cooldown partners are selected independently. */
export const lockMembers = (ids, locks) => locks.every(l => l.apart || ids.includes(l.x) === ids.includes(l.y));
/** A lineup keeps the locks: together, or individually during a cooldown (never as teammates), and when strict
    against a team whose average is at least theirs. */
export function keepsLocks(a, b, locks, strict, protection = null) {
  if (protection?.rested && ![...a,...b].every(id => protection.rested.has(id))) return false;
  for (const l of locks) {
    const inA = [l.x, l.y].filter(id => a.includes(id)).length, inB = [l.x, l.y].filter(id => b.includes(id)).length;
    if (!inA && !inB) continue;
    if (!l.apart && (inA + inB === 1 || inA === 1)) return false;
    if (l.apart && (inA === 2 || inB === 2)) return false;
    if (!l.apart) { const [own, opp] = inA ? [a,b] : [b,a];
      if (protection && ![...own,...opp].every(id => protection.opponents.has(id))) return false;
      if (strict && realAvg(opp) < realAvg(own) - LOCK_EQUAL) return false; }
  }
  return true;
}
export const listNames = ps => { try { return new Intl.ListFormat('en', { type: 'conjunction' }).format(ps.map(p => p.name)); } catch { return ps.map(p => p.name).join(', '); } };
/** Overdue first: everyone who has waited 20+ minutes (up to a full court) plays in this game, fewest games counted first
    (a late arrival counts at par, so their missed games don't put them ahead), then longest wait.
    While more players haven't played than a game needs, each shuffle draws a fresh random group from them. */
/** Matching only: +0.5 on 3 wins in a row, +0.5 more per further win, at most +1.5; losses the same, negative. A cancelled
    game doesn't count. Ratings don't change. */
export function streakBoost(id) {
  let run = 0, sign = 0;
  const games = counted();
  for (let i = games.length - 1; i >= 0; i--) {
    const r = games[i]; if (!r.a.includes(id) && !r.b.includes(id)) continue;
    const s = (r.winner === 0 ? r.a : r.b).includes(id) ? 1 : -1;
    if (sign && s !== sign) break;
    sign = s; run++;
  }
  return run >= STREAK ? sign * Math.min(STREAK_MAX, STREAK_BOOST + STREAK_STEP * (run - STREAK)) : 0;
}
/** A late arrival who hasn't played since arriving. */
export const newcomer = p => !!p.credit && played(p.id) === 0;
/** Keep locked teams only while normal rest, game-count and opponent-rating rules allow it. */
export function pick(f, line, choice = 0, allowIdleRelease = false) {
  if (f !== 'doubles') return pickCore(f, line, choice);
  const busy = onCourt(), now = Date.now();
  line = line.filter(p => !(isLocked(p) && busy.has(p.lock) && !splitDue(p.id, p.lock) && now - waitStart(p) < WAIT_PRIORITY));
  const locks = lockContext(line);
  if (!locks.length) return pickCore(f, line, choice);
  const counts = gamesCounted();
  for (const l of locks) {
    const own = Math.min(counts[l.x],counts[l.y]), behind = line.some(p => counts[p.id] > own + LOCK_GAME_LEAD);
    if (!l.apart && (behind || [P(l.x),P(l.y)].some(p => now-waitStart(p) >= WAIT_PRIORITY)) && !lockedGame(line,l,locks)) l.apart=true;
  }
  const order = [];
  for (const p of line) if (!order.includes(p)) {
    order.push(p);
    const l = locks.find(l => !l.apart && (l.x === p.id || l.y === p.id));
    if (l) order.push(P(l.x === p.id ? l.y : l.x));
  }
  const protection = lockProtection(line);
  const core = candidates => {
    lockCtx = { locks, strict: true, protection };
    let p; try { p = pickCore(f, candidates, choice); } finally { lockCtx = null; }
    return p && keepsLocks(p.a.map(x => x.id), p.b.map(x => x.id), locks, true, protection) ? lockNotes(p, locks) : null;
  };
  for (const l of locks) if (!l.apart && [P(l.x),P(l.y)].some(p => now-waitStart(p) >= WAIT_PRIORITY)) {
    const g=lockedGame(order,l,locks); if(g) return g;
  }
  const p = core(order); if (p) return p;
  for (const l of locks) if (!l.apart) { const g = lockedGame(order, l, locks); if (g) return g; }
  const held = new Set(locks.filter(l => !l.apart).flatMap(l => [l.x, l.y]));
  const free = core(order.filter(p => !held.has(p.id))); if (free) return free;
  if (!allowIdleRelease) return null;
  for (const l of locks) if (!l.apart) { l.apart = true; l.idle = true; }
  return core(line);
}
export function lockProtection(line) {
  const n = gamesCounted(), low = Math.min(...line.map(p => n[p.id])), off = lastOffCourt();
  const rested = new Set(line.filter(p => !off.has(p.id)).map(p => p.id));
  return { opponents: new Set(line.filter(p => n[p.id] <= low + LOCK_GAME_LEAD).map(p => p.id)), rested: rested.size >= 4 ? rested : null };
}
/** Equal-or-higher opponents from the full queue, preserving rest and games-played protections. */
export function lockedGame(order, l, locks) {
  if (l.apart) return null;
  const x = P(l.x), y = P(l.y), others = order.filter(p => p.id !== l.x && p.id !== l.y);
  const counts = gamesCounted(), protection = lockProtection(order), recent = recentPairs();
  const oldest = order.filter(p=>Date.now()-waitStart(p)>=WAIT_CAP).sort((a,b)=>waitStart(a)-waitStart(b))[0];
  let best = null;
  for (let j = 1; j < others.length; j++) for (let i = 0; i < j; i++) {
    const a = [x, y], b = [others[i], others[j]];
    if (oldest && ![...a,...b].some(p=>p.id===oldest.id)) continue;
    if (!keepsLocks(a.map(p => p.id), b.map(p => p.id), locks, true, protection)) continue;
    const gap = Math.abs(realAvg(a.map(p => p.id)) - realAvg(b.map(p => p.id)));
    const key = [b.reduce((n,p) => n + counts[p.id], 0), repeats(a,b,recent), Math.round(gap * 100), i + j];
    if (!best || cmp(key,best.key) < 0) best = {key,b};
  }
  return best && lockNotes({format:'doubles', a:[x,y], b:best.b, options:1, note:null},locks);
}
export function lockNotes(p, locks) {
  const ids = new Set([...p.a,...p.b].map(p => p.id));
  const notes = locks.filter(l => l.apart && (ids.has(l.x) || ids.has(l.y))).map(l => {
    const names=`${P(l.x).name} & ${P(l.y).name}`;
    if(splitDue(l.x,l.y)) return names+' cooldown after 3 wins together';
    if(l.idle) return names+' released to avoid an idle court';
    return names+([P(l.x),P(l.y)].some(p=>Date.now()-waitStart(p)>=WAIT_PRIORITY) ? ` released after ${WAIT_PRIORITY/60000}-minute wait` : ' released to catch up on games');
  });
  if (notes.length) p.note = [p.note,...notes].filter(Boolean).join(' · ');
  return p;
}
export function pickCore(f, line, choice = 0) {
  // Streaks: matched at the boosted rating; the players handed back carry their real ratings.
  line = line.map(p => { const b = streakBoost(p.id); return b ? { ...p, skill: p.skill + b } : p; });
  // Wait clocks run from the session's first game: time before play starts doesn't make anyone overdue.
  const now = Date.now(), waited = waitStart;
  const n = gamesCounted();
  const hard = p => now-waited(p)>=WAIT_CAP;
  let overdue = line.filter(p => now - waited(p) >= WAIT_PRIORITY).sort((x,y) => Number(!hard(x))-Number(!hard(y)) || (hard(x) && hard(y) ? waited(x)-waited(y) : 0) || n[x.id]-n[y.id] || waited(x)-waited(y));
  // A together-locked pair is overdue together; cooldown partners are overdue independently.
  if (lockCtx) { const units = []; let pair = false;
    for (const p of overdue) { if (units.includes(p)) continue;
      const l = lockCtx.locks.find(l => l.x === p.id || l.y === p.id), mate = l && line.find(x => x.id === (l.x === p.id ? l.y : l.x));
      if (mate && l && !l.apart) { if (!pair && units.length + 2 <= NEED[f]) { units.push(p, mate); pair = true; } }
      else if (units.length < NEED[f]) units.push(p); }
    overdue = units; }
  overdue = overdue.slice(0, NEED[f]);
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
  const opts = f === 'doubles' ? { recent: recentPairs(), must: Math.max(1, overdue.length), justOff: off,
    capSpread: overdue.length ? OVERDUE_SPREAD : null, games: n, balancedOnly: balancedOnly() } : null; // an overdue game may stretch to 2 levels, balanced, at worst
  // At most 2 late arrivals on their first game in one game, so a wave of arrivals doesn't take over a court.
  const newIds = new Set(line.filter(newcomer).map(p => p.id));
  const fewNew = opts && newIds.size > LATE_PER_GAME ? four => four.filter(p => newIds.has(p.id)).length <= LATE_PER_GAME : undefined;
  // Even games: nobody plays while someone with fewer games is left waiting (a late arrival counts at par), so similar-skill
  // groups don't leave anyone 2 games behind.
  const even = four => { const ids = new Set(four.map(p => p.id)), rest = pool.filter(p => !ids.has(p.id));
    return !rest.length || four.every(p => (n[p.id] || 0) <= Math.min(...rest.map(x => n[x.id] || 0))); };
  if (opts) opts.accept = four => (!fewNew || fewNew(four)) && even(four);
  let p = f === 'singles' ? pickSingles(pool, S.results.map(r => r.end), turn) : pickDoubles(pool, turn, opts);
  // ...unless that brings back a foursome that all met lately: then the usual pick, if it repeats less.
  if (p && opts && repeats(p.a, p.b, opts.recent) >= EVEN_REPEAT) {
    const u = pickDoubles(pool, turn, { ...opts, accept: fewNew });
    if (u && repeats(u.a, u.b, opts.recent) < repeats(p.a, p.b, opts.recent)) p = u;
  }
  if (!p && opts?.accept) { delete opts.accept; p = pickDoubles(pool, turn, opts); }
  // Hot/cold teaming: offered first; shuffle then steps through the normal games.
  if (f === 'doubles') {
    const normal = turn === 0 ? p : pickDoubles(pool, 0, opts);
    const hc = hotColdGame(pool, [...(normal ? [...normal.a, ...normal.b] : []), ...pool.slice(0, 4)], overdue, off);
    if (hc) { const n = 1 + (normal?.options || 0), k = turn % n; p = k === 0 ? hc : pickDoubles(pool, k - 1, opts); if (p) p.options = n; }
  }
  if (p && fresh) p.options = 99; // keeps the shuffle button available
  // The note names only the overdue players actually in this game.
  const inGame = p ? overdue.filter(o => now - waited(o) >= NOTE_AFTER && [...p.a, ...p.b].some(x => x.id === o.id)) : [];
  if (inGame.length) p.note = [p.note, `${listNames(inGame)} waited ${NOTE_AFTER / 60000}+ min`].filter(Boolean).join(' · ');
  if (p) { p.a = p.a.map(x => P(x.id) || x); p.b = p.b.map(x => P(x.id) || x); }
  return p;
}
/** A manual court's slots (team A, then team B), sized to its format, keeping only players still waiting. null: automatic. */
export function manualSlots(c) {
  if (S.tournament || c.match || !c.manual) return null;
  const waiting = new Set(eligible(c.format).map(p => p.id));
  return Array.from({ length: NEED[c.format] }, (_, k) => waiting.has(c.manual[k]) ? c.manual[k] : null);
}
/** Manual mode on (empty slots: the organiser picks every player) or off (back to automatic picks). */
export function setManual(id, on) {
  const c = courtById(id); if (!c || c.match) return;
  c.manual = on ? Array(NEED[c.format]).fill(null) : null; c.plan = null; c.locked = null; c.shuffles = 0;
}
/** Puts a player in a manual slot (null empties it); they leave any other manual slot they were in. */
export function setSlot(id, k, pid) {
  const c = courtById(id); if (!c || !manualSlots(c)) return;
  if (pid) for (const o of S.courts) if (o.manual) o.manual = o.manual.map(x => x === pid ? null : x);
  const m = manualSlots(c); if (k < 0 || k >= m.length) return;
  m[k] = pid || null; c.manual = m;
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
  // Hand-set lineups and players chosen for manual courts come first; they're off limits to the automatic picks.
  const taken = new Set(open.flatMap(c => { const pl = validPlan(c); return [...(pl ? [...pl.a, ...pl.b] : []), ...(manualSlots(c) || []).filter(Boolean)]; }));
  const reservation = scheduledReservation();
  const reserved = new Set(reservation ? [...reservation.a,...reservation.b] : []);
  const free = onCourt();
  const scheduledCourt = reservation && ![...reserved].some(id=>free.has(id)||taken.has(id)) ? open.find(c=>c.format===reservation.format&&!c.manual&&!validPlan(c)) : null;
  reserved.forEach(id=>taken.add(id));
  const out = [];
  for (const c of open) {
    const ms = manualSlots(c);
    if (ms) { // manual: the chosen lineup once every slot is filled, never shuffled
      if (ms.every(Boolean)) out.push({ format: c.format, a: players(ms.slice(0, ms.length / 2)), b: players(ms.slice(ms.length / 2)), court: c.id, options: 1 });
      continue;
    }
    const pl = validPlan(c);
    if (pl) { out.push({ format: c.format, a: players(pl.a), b: players(pl.b), court: c.id, options: 2 }); continue; }
    if (scheduledCourt?.id===c.id) { out.push({format:c.format,a:players(reservation.a),b:players(reservation.b),court:c.id,options:1,note:'Scheduled',scheduled:reservation.id}); continue; }
    const p = pick(c.format, eligible(c.format).filter(x => !taken.has(x.id)), c.shuffles || 0, true);
    if (!p) continue;
    p.court = c.id; [...p.a, ...p.b].forEach(x => taken.add(x.id)); out.push(p);
  }
  // Busy courts: who's next there once the current game ends, earliest-started court first.
  // ponytail: a guess from who's waiting now; the players coming off other courts can change it
  for (const c of S.courts.filter(c => c.match).sort((x, y) => x.match.start - y.match.start)) {
    const p = pick(c.format, eligible(c.format).filter(x => !taken.has(x.id)), 0);
    if (p) { p.court = c.id; [...p.a, ...p.b].forEach(x => taken.add(x.id)); out.push(p); }
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
  const c = courtById(id); if (!c || c.match || c.manual) return;
  // One run of the matching for every court, read before any plan below changes it; skipped when nothing else needs keeping.
  const needed = c.locked != null || S.courts.some(o => o.id !== id && !o.match);
  const [keep, here] = !needed ? [[], null] : withMatching(() => [
    S.courts.filter(o => o.id !== id && !o.manual).map(o => [o, nextPairing(o)]).filter(([, p]) => p).map(([o, p]) => [o, { a: p.a.map(x => x.id), b: p.b.map(x => x.id) }]),
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
  const c = courtById(id); if (!c || c.match || c.manual) return;
  if (side != null) { const h = nextPairing(c); if (h) c.plan = { a: h.a.map(x => x.id), b: h.b.map(x => x.id) }; }
  c.locked = side;
}

// ---------- scheduled matches ----------
// One reservation; duration estimates only enforce the session deadline.
export const SCHEDULE_DEFAULT = 12 * 60000;
export function scheduledDuration(format) {
  const lens = counted().filter(r => r.a.length === NEED[format] / 2 && r.end > r.start).slice(-10).map(r => r.end - r.start).sort((a,b)=>a-b);
  if (!lens.length) return SCHEDULE_DEFAULT;
  const m = Math.floor(lens.length / 2);
  return lens.length % 2 ? lens[m] : (lens[m-1] + lens[m]) / 2;
}
export function normalizeEnd(x = S) {
  const last = x.results.filter(r => r.winner != null && Number.isFinite(r.end)).map(r => r.end);
  if (x.ended != null && last.length) x.ended = Math.max(...last);
}
export function endLabel(x) {
  if (x.ended == null) return '';
  return new Date(x.ended).toLocaleString(undefined, { ...(new Date(x.ended).toDateString() !== new Date(x.date).toDateString() ? {year:'numeric',month:'short',day:'numeric'} : {}),hour:'numeric',minute:'2-digit' });
}
export function scheduleMatch(format, a, b) {
  const ids = [...a,...b];
  if (S.ended != null || S.tournament) throw new Error('Scheduled matches are available in live queue sessions.');
  if (!Number.isFinite(S.hours) || !(S.hours > 0)) throw new Error('Set the session length first.');
  if (!NEED[format] || a.length !== NEED[format]/2 || b.length !== a.length || new Set(ids).size !== NEED[format] || ids.some(id=>!P(id))) throw new Error('Choose distinct players for both teams.');
  const request = {id:uid(),format,a:[...a],b:[...b]};
  (S.scheduled ||= []).push(request); refreshSchedule(); return request.id;
}
export const scheduledDone = r => counted().some(g => g.scheduled === r.id);
export const scheduledPlaying = r => S.courts.some(c => c.match?.scheduled === r.id);
export function scheduleBlock(r) {
  if (S.ended != null) return 'Session ended';
  if (S.tournament) return 'Waiting for queue mode';
  if ([...r.a,...r.b].some(id=>played(id)===0)) return 'Waiting for participants’ first game';
  if (!endsAt() || Date.now()+scheduledDuration(r.format)>endsAt()) return 'Insufficient time';
  const ids = [...r.a,...r.b];
  if (ids.some(id=>!P(id) || P(id).away || P(id).paused) || ids.every(id=>onCourt().has(id))) return 'Waiting for players';
  const pinned = S.courts.flatMap(c=>c.manual ? c.manual.filter(Boolean) : validPlan(c) ? [...c.plan.a,...c.plan.b] : []);
  if (ids.some(id=>pinned.includes(id))) return 'Waiting for manual lineup';
  if (!S.courts.some(c=>c.format===r.format && !c.manual && !validPlan(c))) return 'Waiting for court';
  return null;
}
export function refreshSchedule() {
  // Legacy hold windows no longer control reservations.
  for (const r of S.scheduled || []) { delete r.heldAt; delete r.retryAt; }
}
export function scheduledReservation() {
  return (S.scheduled||[]).find(r=>!scheduledDone(r)&&!scheduledPlaying(r)&&!scheduleBlock(r)) || null;
}
export function scheduledStatus(r) {
  if (scheduledDone(r)) return 'Completed';
  if (scheduledPlaying(r)) return 'Playing';
  const blocked = scheduleBlock(r); if (blocked) return blocked;
  const busy=onCourt();
  if ([...r.a,...r.b].some(id=>busy.has(id))) return 'Waiting for players';
  return scheduledReservation()?.id===r.id && S.courts.some(c=>!c.match&&c.format===r.format&&!c.manual&&!validPlan(c)) ? 'Ready' : 'Waiting for court';
}
export function cancelScheduled(id) { if (S.courts.some(c=>c.match?.scheduled===id)) throw new Error('Finish or cancel the game on its court first.'); S.scheduled=(S.scheduled||[]).filter(r=>r.id!==id); refreshSchedule(); }

// ---------- actions ----------
/** Start: begins `shown` (the game the screen drew for this court) while all four are still free, so the lineup never changes
    on Start. Who's overdue moves with the clock between redraws. Otherwise Up Next now. */
export function fill(cid, shown) {
  const c = courtById(cid); if (!c || c.match) return;
  refreshSchedule();
  if (S.ended != null) return;
  const free = new Set(queue().map(p => p.id));
  const p = shown && [...shown.a, ...shown.b].every(x => free.has(x.id)) ? shown : nextPairing(c);
  if (!p) return;
  const current = p.scheduled && queueUpNext().find(g=>g.court===cid&&g.scheduled===p.scheduled);
  if (p.scheduled && (!current || current.a.map(x=>x.id).join()!==p.a.map(x=>x.id).join() || current.b.map(x=>x.id).join()!==p.b.map(x=>x.id).join())) return;
  const held=scheduledReservation();
  if (!p.scheduled && held && [...p.a,...p.b].some(x=>[...held.a,...held.b].includes(x.id))) return;
  c.match = { a: p.a.map(x => x.id), b: p.b.map(x => x.id), start: Date.now(), tm: p.match ?? null, scheduled:p.scheduled ?? null, jumpers:p.scheduled ? scheduledJumpers([...p.a,...p.b].map(x=>x.id)) : null };
  c.shuffles = 0; c.plan = null; c.locked = null;
  refreshSchedule();
}
export const ratingChange = (ta, tb, aWon) => K * ((aWon ? 1 : 0) - 1 / (1 + 10 ** ((tb - ta) / SPREAD)));
/** Standings score, 0–100: the win rate with two extra wins and two extra losses, so one or two lucky games can't top
    the table. Game length doesn't count. Equal records score exactly the same, a draw. A cancelled game doesn't count. */
export function score(id) {
  const mine = counted().filter(r => r.a.includes(id) || r.b.includes(id));
  return (mine.filter(r => (r.winner === 0 ? r.a : r.b).includes(id)).length + 2) / (mine.length + 4) * 100;
}
/** Places for scores sorted high to low: equal scores (equal records) share a place, and the next score takes the
    next place: 1, 1, 1, 2, 3, 3. */
export function places(scores) {
  const out = [];
  scores.forEach((s, i) => out.push(i > 0 && s === scores[i - 1] ? out[i - 1] : (out.at(-1) || 0) + 1));
  return out;
}
/** How much one game moves a rating: more over a new player's first games, less for regulars (anyone without a count). */
export const kFactor = p => p.rated != null && p.rated + played(p.id) < NEW_GAMES ? NEW_K : REG_K;
export function adjust(ids, d) {
  const out = {};
  for (const id of ids) { const p = P(id); if (!p) continue; const old = p.skill; p.skill = Math.min(5, Math.max(1, old + d * kFactor(p))); out[id] = p.skill - old; }
  return out;
}
/** Ends the game on a court. With a winner (0 = team A, 1 = team B), moves both teams' ratings. Without one the game is
    cancelled: it's kept in the history, but like Undo Start the players are back exactly where they were in line. */
export function finish(cid, winner) {
  const c = courtById(cid); const m = c?.match; if (!m) return;
  const r = { a: m.a, b: m.b, winner, court: c.name, start: m.start, end: Date.now(), changes: null, label: null, scheduled:m.scheduled ?? null, jumpers:m.jumpers ?? null };
  if (winner != null) {
    // A win is a win: game length isn't counted (games to 11 and to 21 last very different times).
    const d = ratingChange(avg(m.a), avg(m.b), winner === 0);
    r.changes = { ...adjust(m.a, d), ...adjust(m.b, -d) };
  }
  if (m.tm != null && S.tournament) { r.label = S.tournament.matches[m.tm].label; if (winner != null) recordTournament(m.tm, winner); }
  S.results.push(r);
  const now = Date.now();
  if (winner != null) [...m.a, ...m.b].forEach((id, n) => { const p = P(id); if (p) { p.readyAt = now + n; p.first = false; p.since = now; } });
  c.match = null;
  refreshSchedule();
  if (winner != null) c.manual = null; // a finished game ends manual mode; a cancelled one keeps the lineup, like Undo Start
}
/** End Session: games still on court are cancelled, then the session is marked ended. */
export function endSession() { for (const c of S.courts) if (c.match) finish(c.id, null); S.ended = Date.now(); normalizeEnd(); refreshSchedule(); }
export function deleteResult(i) {
  const r = S.results.splice(i, 1)[0];
  for (const [id, d] of Object.entries(r.changes || {})) { const p = P(id); if (p) p.skill -= d; }
  normalizeEnd(); refreshSchedule();
}
/** Corrects a finished game's result (0 = team A won, 1 = team B, null = cancelled): undoes the rating change it made,
    then applies the corrected one, worked out as when a game finishes. Places in line aren't touched. */
export function setWinner(i, winner) {
  const r = S.results[i]; if (!r || r.winner === winner) return;
  for (const [id, d] of Object.entries(r.changes || {})) { const p = P(id); if (p) p.skill -= d; }
  r.changes = null; r.winner = winner; normalizeEnd();
  if (winner == null) return;
  const d = ratingChange(avg(r.a), avg(r.b), winner === 0);
  r.changes = { ...adjust(r.a, d), ...adjust(r.b, -d) };
}
// ponytail: 75% of the median games played; tune if late arrivals or early leavers are still ranked (or too many aren't)
export const RANK_SHARE = 0.75;
/** Standings rank only players with at least this many games: 75% of the session's typical night (the median among
    those who played), so someone who played a few games and left can't top the table. */
export function rankingMinimum() {
  const n = S.players.map(p => played(p.id)).filter(x => x > 0).sort((a, b) => a - b);
  return n.length ? Math.max(1, Math.ceil(n[Math.floor(n.length / 2)] * RANK_SHARE)) : 1;
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
/** `rated`: rated games before this session (0 for a new player, null for a regular from before this was counted). */
export function addPlayer(name, skill, rated = 0) {
  const p = { id: uid(), name, skill, pref: 'any', paused: false, readyAt: Date.now(), away: true, rated };
  if (!S.players.length && !S.results.length) S.date = Date.now(); // an empty session made at the end of last night is tonight's
  S.players.push(p);
  if (S.results.length || onCourt().size) arrive(p.id);
}
/** Marks someone present. They join the line like a late arrival: just ahead of everyone who has played (behind anyone still
    on 0 games), counted at par with the least-played player who has played (never below their own games), wait clock from now.
    Once 4 late arrivals are already waiting for their first game, later ones join at par in arrival order instead of going first. */
export function arrive(id) {
  const p = P(id); if (!p?.away) return;
  const n = gamesCounted();
  const par = Math.min(Infinity, ...S.players.filter(x => !x.paused && !x.away && played(x.id) > 0).map(x => n[x.id]));
  // In the first 30 minutes after the first game an arrival counts as on time: no credit, so they're up next like anyone yet to play.
  const st = startedAt(), onTime = st == null || Date.now() - st < LATE_AFTER;
  const credit = onTime ? 0 : Math.max(p.credit || 0, (par < Infinity ? par : 0) - played(id));
  const first = queue().filter(newcomer).length < LATE_FIRST;
  Object.assign(p, { away: false, readyAt: first ? arrivalTime() : Date.now(), since: Date.now(), credit: credit > 0 ? credit : null });
}

// ---------- replacing a player in "Next up" ----------
/** The rating matching uses: the real rating plus any streak boost. The screen always shows the real one. */
export const matchSkill = id => (P(id)?.skill ?? 3) + streakBoost(id);
export const avgMatch = ids => { const s = ids.filter(P).map(matchSkill); return s.length ? s.reduce((a, b) => a + b, 0) / s.length : 3; };
export const unevenness = (a, b) => Math.abs(avgMatch(a) - avgMatch(b));
export const isEven = (a, b) => unevenness(a, b) <= (a.length === 1 ? RANGE : FAIR) + 0.001;
export function arranged(a, b) {
  if (a.length !== 2 || isEven(a, b)) return { a, b };
  const four = players([...a, ...b]).map(p => ({ ...p, skill: matchSkill(p.id) })); if (four.length !== 4) return { a, b };
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
  const now = Date.now(), ids = new Map(S.players.map(p => [p.id, uid()]));
  return {
    id: uid(), date: now, results: [], tournament: null,
    // marked present as they arrive; locked teammates carry over
    players: keepPlayers ? S.players.map((p, n) => ({ id: ids.get(p.id), name: p.name, skill: p.skill, pref: 'any', paused: false, readyAt: now + n, away: true,
      lock: (p.lock && ids.get(p.lock)) || null, rated: p.rated != null ? p.rated + played(p.id) : null })) : [],
    courts: S.courts.map(c => court(c.name, c.format)),
  };
}
/** The latest version of everyone in these sessions (by name, ignoring case), with their rated games carried forward. */
export function playerPool(list) {
  const latest = new Map();
  for (const x of [...list].sort((a, b) => a.date - b.date)) for (const p of x.players) {
    const games = counted(x).filter(r => r.a.includes(p.id) || r.b.includes(p.id)).length;
    latest.set(p.name.toLowerCase(), { ...p, rated: p.rated != null ? p.rated + games : null });
  }
  return [...latest.values()].sort((a, b) => a.name.localeCompare(b.name));
}
export function returningPlayers() {
  const here = new Set(S.players.map(p => p.name.toLowerCase()));
  return playerPool(past()).filter(p => !here.has(p.name.toLowerCase()));
}

/** Everyone ever registered, one row per person (matched by name, ignoring case), with their latest rating. */
export function registry() {
  const out = new Map();
  for (const x of [...sessions.values()].sort((a, b) => a.date - b.date)) {
    for (const p of x.players) {
      const k = p.name.toLowerCase();
      const r = out.get(k) || { name: p.name, skill: p.skill, sessions: 0, played: 0, won: 0, last: x.date };
      r.name = p.name; r.skill = p.skill; r.last = x.date; r.sessions++;
      r.played += counted(x).filter(g => g.a.includes(p.id) || g.b.includes(p.id)).length;
      r.won += x.results.filter(g => g.winner != null && (g.winner === 0 ? g.a : g.b).includes(p.id)).length;
      out.set(k, r);
    }
  }
  return [...out.values()].sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
}
export const isDupEverywhere = (name, old) => !!name && name.toLowerCase() !== old.toLowerCase() && registry().some(r => r.name.toLowerCase() === name.toLowerCase());
export const isDupName = (name, except) => !!name && S.players.some(p => p.id !== except && p.name.toLowerCase() === name.toLowerCase());

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
  // Standings: 5 of 5 beats 6 of 7; game length doesn't count, so equal records draw; draws share a place.
  const game = (w, l, mins = 10, won = true) => ({ a: [w], b: [l], winner: won ? 0 : 1, start: 0, end: mins * 60000 });
  S = { players: [], courts: [], results: [...Array(6).fill(game('A', 'X')), game('A', 'X', 10, false), ...Array(5).fill(game('B', 'X'))], tournament: null };
  console.assert(score('B') > score('A'), '5 of 5 should rank above 6 of 7');
  S.results = [...Array(7).fill(game('A', 'X', 4)), game('A', 'X', 4, false), ...Array(7).fill(game('B', 'X', 20)), game('B', 'X', 20, false)];
  console.assert(score('A') === score('B'), "game length doesn't count: equal records draw");
  console.assert(places([70, 70, 70, 64, 61, 61, 50]).join() === '1,1,1,2,3,3,4', 'draws share a place; the next score takes the next place');
  S = { players: [pl(3, 1), pl(3, 2)], courts: [], results: [{ winner: 0, a: ['p1-3'], b: ['x'] }], tournament: null };
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
  // Too few players for similar groups (under 6.25 per doubles court): balanced teams in queue order instead.
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
  for (const p of S.players) S.results.push({ winner: 0, a: [p.id], b: ['x'] });
  console.assert(names4(pick('doubles', queue())) === '1,2,3,4', 'on ties, the hardest to match goes first');
  S = { players: [], courts: [], results: [], tournament: null };
  // Before the first game, nobody is overdue however long they've been here, so shuffle keeps working.
  S = { players: Array.from({ length: 12 }, (_, i) => ({ ...pl(2 + i % 4, i), readyAt: Date.now() - 1800000 + i })), courts: [court('C1', 'doubles')], results: [], tournament: null };
  console.assert(!/waited/.test(pick('doubles', queue())?.note || ''), 'no one is overdue before the first game');
  // Overdue players who can't make even teams together: as many as fair teams allow play, and the note names only them.
  S = { players: [['A', 4.9], ['B', 3.0], ['C', 2.5], ['D', 2.5], ['E', 3.0], ['F', 3.0], ['G', 3.0], ['H', 3.0]].map(([nm, sk], i) => ({ ...pl(sk, i), name: nm, readyAt: Date.now() - 60000 + i })),
    courts: [], results: [], tournament: null };
  for (let i = 0; i < 4; i++) { S.players[i].since = Date.now() - 50 * 60000; S.results.push({ winner: 0, a: [S.players[i].id], b: ['x'], start: Date.now() - 3600000 }); }
  const odGame = pick('doubles', queue()), odNames = [...odGame.a, ...odGame.b].map(p => p.name);
  console.assert(['A', 'B', 'C'].every(n => odNames.includes(n)) && !odNames.includes('D') && !/\bD\b/.test(odGame.note || '')
    && Math.abs(sum(odGame.a) - sum(odGame.b)) / 2 <= FAIR, 'overdue: even teams, note names only who plays');
  S = { players: [], courts: [], results: [], tournament: null };
  // Streaks: matched 1.5 higher after 3 wins in a row, 1.5 lower after 3 losses; a cancelled game doesn't count; real ratings unchanged.
  S = { players: [pl(3, 0), pl(3, 1), pl(3, 2)], courts: [], results: [], tournament: null };
  const [s0, s1, s2] = S.players.map(p => p.id), res = (w, l, winner = 0) => ({ a: [w], b: [l], winner });
  S.results = [res(s0, s1), res(s0, s1), res(s0, s1)];
  console.assert(streakBoost(s0) === 0.5 && streakBoost(s1) === -0.5 && streakBoost(s2) === 0, '3 in a row: 0.5 for matching');
  S.results.push(res(s0, s1)); console.assert(streakBoost(s0) === 1 && streakBoost(s1) === -1, 'each further win or loss: 0.5 more');
  S.results.push(res(s0, s1), res(s0, s1)); console.assert(streakBoost(s0) === 1.5 && streakBoost(s1) === -1.5, 'capped at 1.5');
  S.results = [res(s0, s1), res(s0, s1), res(s0, s1)];
  S.results.push(res(s0, s1, null));
  console.assert(streakBoost(s0) === 0.5, "a cancelled game doesn't break a streak");
  console.assert(PRESETS.every((x, i) => level(x) === i + 1), 'each level preset reads as its own level');
  // Standings: ranked from 75% of the median games played; a corrected winner moves ratings as if it had been entered right.
  {
    const keepS = S;
    S = { players: [0, 1, 2, 3, 4, 5].map(i => pl(3, i)), courts: [], results: [], tournament: null };
    [9, 9, 9, 10, 4, 5].forEach((g, i) => { for (let k = 0; k < g; k++) S.results.push({ a: [S.players[i].id], b: ['x'], winner: 0 }); });
    console.assert(rankingMinimum() === 7, 'ranked from 75% of the median games played');
    const fresh = () => ({ players: [0, 1, 2, 3].map(i => pl(3, i)), courts: [court('C', 'doubles')], results: [], tournament: null });
    S = fresh(); const ids = S.players.map(p => p.id), t0 = Date.now() - 600000;
    S.courts[0].match = { a: ids.slice(0, 2), b: ids.slice(2), start: t0 }; finish(S.courts[0].id, 1);
    const right = S.players.map(p => p.skill).join(), end = S.results[0].end;
    S = fresh(); S.players.forEach((p, k) => p.id = ids[k]);
    S.results = [{ a: ids.slice(0, 2), b: ids.slice(2), winner: 0, start: t0, end, changes: Object.fromEntries(ids.map(x => [x, 0])) }];
    setWinner(0, 1);
    console.assert(S.players.map(p => p.skill).join() === right, 'a corrected winner moves ratings as if entered right');
    setWinner(0, null);
    console.assert(S.players.every(p => p.skill === 3) && !counted().length, 'corrected to cancelled: no rating change, not a game');
    S = keepS;
  }
  // Streaks on the rating dots: red into the empty dots, blue over the top filled ones, half a dot per 0.5; a ring past the dots.
  const sd = (f, b) => { const x = streakDots(f, b); return x.parts.join() + (x.ring ? ' ring' : ''); };
  console.assert(sd(3, 0.5) === '0,0,0,0.5,0' && sd(3, 1.5) === '0,0,0,1,0.5' && sd(3, -1) === '0,0,1,0,0' && sd(3, -0.5) === '0,0,0.5,0,0', 'streak dots');
  // Wait clock (the queue's minutes and the 20-minute rule): nothing before the first game, then from the last game or arrival.
  {
    const keepS = S;
    S = { players: [{ id: 'w', readyAt: Date.now() - 3000000 }], results: [], courts: [] };
    console.assert(Date.now() - waitStart(S.players[0]) < 1000, "before the first game nobody's clock runs");
    S.results = [{ start: Date.now() - 3600000 }];
    console.assert(Math.abs(Date.now() - waitStart(S.players[0]) - 3000000) < 1000, 'a late arrival waits from arriving');
    S.players[0].since = Date.now() - 600000; S.players[0].paused = true;
    console.assert(Math.abs(Date.now() - waitStart(S.players[0]) - 600000) < 1000, "from their last game; sitting out doesn't restart it");
    S = keepS;
  }
  console.assert(streakDots(5, 0.5).fire && !streakDots(5, 0.5).ring && sd(1, -1.5) === '1,0,0,0,0 ring' && sd(3, 0) === '0,0,0,0,0', 'overflow wins show fire; overflow losses retain rings');
  S.results.pop();
  // A cancelled game isn't a game: no count, no rating, nobody just off, and the four are back where they were in line.
  S = { players: [0, 1, 2, 3, 4, 5, 6, 7].map(i => ({ ...pl(3, i), readyAt: Date.now() - 60000 + i })), courts: [court('C', 'doubles')], results: [], tournament: null };
  const lineBefore = queue().map(p => p.id).join(), ratingsBefore = S.players.map(p => p.skill).join();
  fill(S.courts[0].id);
  const cm = S.courts[0].match;
  finish(S.courts[0].id, null);
  console.assert(queue().map(p => p.id).join() === lineBefore && S.players.map(p => p.skill).join() === ratingsBefore, 'a cancelled game leaves the line and ratings as they were');
  console.assert(S.results.length === 1 && !counted().length && S.players.every(p => played(p.id) === 0 && !gamesCounted()[p.id]) && !lastOffCourt().has(cm.a[0]),
    'a cancelled game is kept in the history but counts for nobody');
  // End Session cancels whatever is on court and marks the session ended.
  fill(S.courts[0].id);
  endSession();
  console.assert(S.ended && !onCourt().size && S.results.length === 2 && !counted().length, 'End Session cancels games on court');
  // Live sessions: data saved before them marks every session but the open one ended; an All Players edit applies everywhere;
  // a session's length runs out that many hours after its first game. Nothing here is written to storage.
  {
    const keep = [sessions, currentId];
    const a = { id: 'a', date: 1, players: [{ name: 'Ana', skill: 3 }], results: [{ end: 5 }], courts: [] }, b = { id: 'b', date: 2, players: [{ name: 'ana', skill: 2 }], results: [], courts: [] };
    sessions = new Map([['a', a], ['b', b]]); currentId = 'b';
    console.assert(markEndedOnce().length === 1 && a.ended === 5 && b.ended == null, 'old saves: earlier sessions ended, the open one live');
    console.assert(editEverywhere('ANA', 'Anna', 4.2).length === 2 && [a, b].every(x => x.players[0].name === 'Anna' && x.players[0].skill === 4.2), 'an All Players edit applies everywhere');
    a.results = [{ start: 1000 }]; a.hours = 2.5;
    console.assert(endsAt(a) === 1000 + 9000000 && endsAt(b) == null, 'ends 2.5 h after the first game');
    [sessions, currentId] = keep;
  }
  // The first player added to an empty session dates it today.
  S = { date: 0, players: [], courts: [], results: [], tournament: null };
  addPlayer('A', 3);
  console.assert(new Date(S.date).toDateString() === new Date().toDateString(), 'an empty session takes the date its first player is added');
  // A 5.0 can make a similar-skill game only if the 3.0 on a win streak counts as 4.5; the game hands back real players.
  S = { players: [5, 3, 4.2, 4.2, 3, 3, 3, 3, 3, 3, 3, 3].map((sk, i) => ({ ...pl(sk, i), name: String(i), readyAt: Date.now() - 60000 + i })),
    courts: [court('C1', 'doubles')], results: [], tournament: null };
  const g1 = (id, w) => ({ a: [id], b: ['x'], winner: w ? 0 : 1, start: Date.now() - 600000 });
  S.results.push(...[1, 0, 1, 0].map(w => g1(S.players[0].id, w)), ...[1, 2, 3, 4, 5].map(() => g1(S.players[1].id, true)));
  for (const p of S.players.slice(2)) S.results.push(...[1, 0, 1, 0, 1].map(w => g1(p.id, w)));
  S.results.push({ a: ['x'], b: ['y'], winner: 0, start: Date.now() - 600000 });
  const hotGame = pick('doubles', queue());
  console.assert(names4(hotGame) === '0,1,2,3' && [...hotGame.a, ...hotGame.b].every(p => p === P(p.id)) && S.players[1].skill === 3,
    'a 5-win streak is matched 1.5 higher (3.0 plays as 4.5); real players and ratings handed back');
  // Lock + shuffle and Replace judge evenness on ratings with streak boosts: a 2.6 on 5 wins plays a 4.0 as an even singles game.
  S = { players: [{ ...pl(2.6, 0), name: 'Hot' }, { ...pl(4.0, 1), name: 'Four' }], courts: [], results: [], tournament: null };
  for (let k = 0; k < 5; k++) S.results.push({ a: [S.players[0].id], b: ['x'], winner: 0 });
  console.assert(Math.abs(unevenness([S.players[0].id], [S.players[1].id]) - 0.1) < 1e-9 && isEven([S.players[0].id], [S.players[1].id]), 'evenness uses boosted ratings');
  // Hot/cold teaming: a 3-win and a 3-loss player within 1.0 level are teammates, against even opponents.
  S = { players: [3.2, 3.6, 3.0, 3.4, 3.1, 3.3, 3.5, 3.2, 3.0, 3.4].map((sk, i) => ({ ...pl(sk, i), name: String(i), readyAt: Date.now() - 60000 + i })),
    courts: [court('C1', 'doubles')], results: [], tournament: null };
  for (let k = 0; k < 3; k++) S.results.push(g1(S.players[0].id, true), g1(S.players[5].id, false));
  for (const p of S.players) if (p.name !== '0' && p.name !== '5') S.results.push(g1(p.id, true), g1(p.id, false), g1(p.id, true));
  S.results.push({ a: ['x'], b: ['y'], winner: 0, start: Date.now() - 600000 });
  const hc = pick('doubles', queue()), hcTeam = [hc.a, hc.b].find(t => t.some(p => p.name === '0'));
  console.assert(hcTeam && hcTeam.some(p => p.name === '5') && Math.abs(sum(hc.a) - sum(hc.b)) / 2 <= HOTCOLD_SLACK + 0.5 + 1e-9, 'hot and cold teamed up');
  // Late arrivals: the first few go first, the rest join at par in arrival order; at most 2 on their first game in a game.
  S = { players: Array.from({ length: 12 }, (_, i) => ({ ...pl(3, i), name: 'R' + i, readyAt: Date.now() - 60000 + i })), courts: [court('C1', 'doubles'), court('C2', 'doubles')], results: [], tournament: null };
  for (const p of S.players) S.results.push({ a: [p.id], b: ['x'], winner: 0, start: Date.now() - 3600000 });
  for (let k = 0; k < 6; k++) addPlayer('L' + k, 3, null);
  const lineNames = queue().map(p => p.name);
  console.assert(['L0', 'L1', 'L2', 'L3'].every(n => lineNames.indexOf(n) < 4) && lineNames.indexOf('L4') > lineNames.indexOf('R0'), 'late arrivals: 4 go first, then at par');
  const lateGame = pick('doubles', queue());
  console.assert([...lateGame.a, ...lateGame.b].filter(p => p.name.startsWith('L')).length <= LATE_PER_GAME, 'at most 2 late arrivals on their first game in one game');
  // Ratings settle faster for a new player's first games, slower for regulars.
  console.assert(kFactor({ id: 'n', rated: 0 }) === NEW_K && kFactor({ id: 'n', rated: NEW_GAMES }) === REG_K && kFactor({ id: 'n', rated: null }) === REG_K, 'rating speed by experience');
  // The court names someone overdue only after 25 minutes.
  S = { players: [0, 1, 2, 3, 4, 5, 6, 7].map(i => ({ ...pl(3, i), name: 'W' + i, readyAt: Date.now() - 60000 + i })), courts: [], results: [], tournament: null };
  S.players[7].since = Date.now() - 22 * 60000; S.results.push({ winner: 0, a: [S.players[7].id], b: ['x'], start: Date.now() - 3600000 });
  const due = pick('doubles', queue());
  console.assert([...due.a, ...due.b].some(p => p.name === 'W7') && !/waited/.test(due.note || ''), 'overdue at 20 min plays next; named only after 25');
  // New session with the same players keeps locked teammates and rated-game counts.
  S = { players: [{ ...pl(3, 0), rated: 2 }, pl(3, 1), pl(3, 2)], courts: [], results: [{ a: ['p0-3'], b: ['p1-3'], winner: 0 }], tournament: null };
  setLock(S.players[0].id, S.players[1].id);
  const nx = nextSession(true);
  console.assert(nx.players[0].lock === nx.players[1].id && nx.players[1].lock === nx.players[0].id && nx.players[0].rated === 3 && nx.players[1].rated == null, 'next session keeps locks and rated counts');
  // Balanced-only below 6.25 players per court: 13 on 2 courts plays similar groups, 12 balanced.
  S = { players: Array.from({ length: 13 }, (_, i) => pl(3, i)), courts: [court('C1', 'doubles'), court('C2', 'doubles')], results: [], tournament: null };
  console.assert(!balancedOnly(), '13 players on 2 courts: similar groups'); S.players.pop(); console.assert(balancedOnly(), '12 on 2 courts: balanced');
  // Start begins the game on screen, even if someone became overdue (20 min) since the screen was drawn.
  S = { players: Array.from({ length: 9 }, (_, i) => ({ ...pl(3, i), name: 'D' + i, readyAt: Date.now() - 60000 + i })), courts: [court('C1', 'doubles')], results: [], tournament: null };
  for (const p of [...S.players, S.players[8]]) S.results.push({ a: [p.id], b: ['x'], winner: 0, start: Date.now() - 3600000 });
  S.players[8].since = Date.now() - 19.5 * 60000;
  const drawnP = nextPairing(S.courts[0]), realNow = Date.now;
  Date.now = () => realNow() + 120000;
  const afterDrift = nextPairing(S.courts[0]); fill(S.courts[0].id, drawnP);
  Date.now = realNow;
  const ids4 = g => [...g.a, ...g.b].map(p => p.id).sort().join();
  console.assert(!names4(drawnP).includes('D8') && names4(afterDrift).includes('D8') && [...S.courts[0].match.a, ...S.courts[0].match.b].sort().join() === ids4(drawnP),
    'Start begins the game on screen');
  // Even games: the four on 0 games play (a 5.0, 4.0 and two 3.0s, balanced) rather than the 4.8 on 1 game who'd make a closer
  // range, which would leave a 0-game player waiting while someone reaches 2.
  S = { players: [5.0, 4.0, 3.0, 3.0, 5.0, 4.9, 4.8].map((sk, i) => ({ ...pl(sk, i), name: String(i), readyAt: Date.now() - 60000 + i })),
    courts: [court('C1', 'doubles')], results: [], tournament: null };
  for (const p of S.players.slice(4)) S.results.push(g1(p.id, true));
  S.results.push({ a: ['x'], b: ['y'], winner: 0, start: Date.now() - 600000 });
  console.assert(!balancedOnly() && names4(pick('doubles', queue())) === '0,1,2,3', 'even games: nobody plays again while someone with fewer games waits');
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
  for (const i of [6, 7]) { S.players[i].since = Date.now() - 50 * 60000; S.results.push({ winner: 0, a: [S.players[i].id], b: ['x'], start: Date.now() - 3600000 }); }
  const od = pick('doubles', queue());
  console.assert([S.players[6].id, S.players[7].id].every(x => [...od.a, ...od.b].some(p => p.id === x)) && /waited/.test(od.note), 'overdue players play next');
  // More overdue than a court takes: fewest games first, and a late arrival counts at par (not ahead for the games they missed).
  S = { players: ["C", "D", "E", "F", "A", "Late", "G", "H"].map((nm, i) => ({ ...fresh(i), name: nm })), courts: [], results: [], tournament: null };
  for (const [i, games, mins] of [[0, 2, 25], [1, 2, 25], [2, 2, 25], [3, 2, 25], [5, 0, 27], [4, 3, 28]]) {
    S.players[i].since = Date.now() - mins * 60000;
    for (let k = 0; k < games; k++) S.results.push({ winner: 0, a: [S.players[i].id], b: ["x"], start: Date.now() - 3600000 });
  }
  S.players[5].credit = 3;
  const few = pick("doubles", queue());
  console.assert([...few.a, ...few.b].map(p => p.name).sort().join() === "C,D,E,F", "overdue: fewest games first, a late arrival at par");
  S.players[4].since=Date.now()-50*60000;S.players[5].since=Date.now()-40*60000;
  const hardWait=pick('doubles',queue());
  console.assert(['A','Late'].every(n=>[...hardWait.a,...hardWait.b].some(p=>p.name===n)), '30-minute waits take priority over the fewest-games preference');
  S = { players: [5, 4.5, 3.5, 3, 3, 3, 2, 1].map((sk, i) => ({ ...fresh(i), skill: sk })), courts: [], results: [], tournament: null };
  S.players[0].since = Date.now() - 35 * 60000; S.results.push({ winner: 0, a: [S.players[0].id], b: ['x'], start: Date.now() - 3600000 });
  const st = pick('doubles', queue()), stSk = [...st.a, ...st.b].map(p => p.skill);
  console.assert(stSk.includes(5) && Math.max(...stSk) - Math.min(...stSk) <= OVERDUE_SPREAD + 1e-9, 'an overdue game stays within 2 levels');
  // Late arrivals: behind 0-game players, ahead of everyone who has played, at par; then the normal order.
  S = { players: ['X', 'Y', 'Z'].map((n, i) => ({ ...fresh(i), name: n })), courts: [], results: [], tournament: null };
  for (let i = 0; i < 3; i++) S.results.push({ winner: 0, a: [S.players[0].id], b: [S.players[1].id], start: Date.now() - 3600000 });
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
  for (let i = 0; i < 3; i++) S.results.push({ winner: 0, a: [S.players[0].id], b: [S.players[1].id], start: Date.now() - 3600000 });
  S.players[2].readyAt = Date.now() - 10000;
  console.assert(!queue().some(p => p.name === 'W'), 'not here: out of the line');
  arrive(S.players[3].id);
  console.assert(queue().map(p => p.name).join() === 'Z,W,X,Y' && S.players[3].credit === 3, 'marked present: like a late arrival, at par');
  // Just off court: behind everyone rested even when behind on games (a late arrival's credit can leave them lowest).
  S = { players: ['A', 'B', 'C', 'D', 'E'].map((n, i) => ({ ...fresh(i), name: n })), courts: [], results: [], tournament: null };
  for (let i = 1; i <= 4; i++) for (let k = 0; k < 4; k++) S.results.push({ winner: 0, a: [S.players[i].id], b: ['x'] });
  for (let k = 0; k < 3; k++) S.results.push({ winner: 0, a: [S.players[0].id], b: ['x'] });
  console.assert(queue().map(p => p.name).join() === 'B,C,D,E,A', 'just off court waits behind everyone rested');
  const id = i => S.players[i].id;
  { // Arrivals in the first 30 minutes after the first game count as on time (no credit); later ones join at par.
    const keep = S, realNow = Date.now;
    S = { players: [...Array.from({ length: 6 }, (_, i) => ({ ...pl(3, i), name: 'L' + i, readyAt: Date.now() - 60000 + i })), { ...pl(3, 6), name: 'Early', away: true }, { ...pl(3, 7), name: 'Late', away: true }],
      courts: [court('C1', 'doubles')], results: [], tournament: null };
    for (const p of S.players.slice(0, 4)) S.results.push({ a: [p.id], b: ['x'], winner: 0, start: Date.now() - 20 * 60000 });
    arrive(S.players[6].id);
    Date.now = () => realNow() + 20 * 60000; arrive(S.players[7].id); Date.now = realNow;
    console.assert(!S.players[6].credit && S.players[7].credit === 1, 'late-arrival credit only from 30 minutes after the first game');
    // Manual mode: the chosen four are the court's game (none until every slot is filled), kept out of other courts' picks,
    // never shuffled; a finished game ends it.
    S = { players: Array.from({ length: 10 }, (_, i) => ({ ...pl(3, i), name: 'M' + i, readyAt: Date.now() - 60000 + i })), courts: [court('C1', 'doubles'), court('C2', 'doubles')], results: [], tournament: null };
    const mc = S.courts[0].id, mine = S.players.slice(-4).map(p => p.id); // the back of the line
    setManual(mc, true);
    mine.slice(0, 3).forEach((id, k) => setSlot(mc, k, id));
    const partial = nextPairing(S.courts[0]) == null;
    setSlot(mc, 3, mine[3]);
    const mg = nextPairing(S.courts[0]), mo = nextPairing(S.courts[1]);
    shuffleCourt(mc);
    const same = [...nextPairing(S.courts[0]).a, ...nextPairing(S.courts[0]).b].map(p => p.id).join() === mine.join();
    fill(mc); finish(mc, 0);
    console.assert(partial && [...mg.a, ...mg.b].map(p => p.id).join() === mine.join() && mg.options === 1 && ![...mo.a, ...mo.b].some(p => mine.includes(p.id))
      && same && S.courts[0].manual == null, 'manual mode: chosen lineup, not shuffled, back to automatic after the game');
    S = keep; }
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
  // Locked teammates: together against an equal or stronger team; after 3 wins in a row together, not teammates next game.
  S = { players: [3.0, 3.0, 3.2, 3.4, 2.6, 2.8, 3.1, 3.3, 2.9, 3.0, 3.5, 2.7].map((sk, i) => ({ ...fresh(i), skill: sk })), courts: [court('C1', 'doubles')], results: [], tournament: null };
  setLock(id(0), id(1));
  const lg = pick('doubles', queue()), lt = [lg.a, lg.b].find(t => t.some(p => p.id === id(0)));
  console.assert(lt && lt.some(p => p.id === id(1)) && realAvg((lt === lg.a ? lg.b : lg.a).map(p => p.id)) >= 3 - LOCK_EQUAL, 'locked teammates play together against an equal or stronger team');
  for (let k = 0; k < 3; k++) S.results.push({ winner: 0, a: [id(0), id(1)], b: [id(2 + k), id(5 + k)], start: Date.now() - 30 * 60000 });
  S.results.push({ winner: 0, a: [id(8), id(9)], b: [id(10), id(11)] });
  S.players[0].first = S.players[1].first = true;
  const sg = pick('doubles', queue());
  const cooldown = lockContext(queue()), sgA = sg.a.map(p => p.id), sgB = sg.b.map(p => p.id);
  console.assert(splitDue(id(0), id(1)) && !(sgA.includes(id(0)) && sgA.includes(id(1))) && !(sgB.includes(id(0)) && sgB.includes(id(1)))
    && lockMembers([id(0), id(2), id(3), id(4)], cooldown)
    && keepsLocks([id(0), id(2)], [id(3), id(4)], cooldown, true)
    && keepsLocks([id(0), id(2)], [id(1), id(3)], cooldown, true), 'cooldown players can play independently or naturally meet as opponents, but cannot team');
  S.players[0].since = S.players[1].since = Date.now() - 30 * 60000;
  const overdueSplit = pick('doubles', queue());
  console.assert(![overdueSplit.a,overdueSplit.b].some(t => [id(0),id(1)].every(id => t.some(p => p.id === id))), 'overdue cooldown players do not become teammates');
  S.results.push({ winner: 0, a: [id(0), id(2)], b: [id(3), id(4)] });
  console.assert(splitDue(id(0), id(1)), "one player's separate game does not end the other cooldown");
  S.results.push({ winner: 0, a: [id(1), id(2)], b: [id(3), id(4)] });
  console.assert(!splitDue(id(0), id(1)), 'after both play separately, locked again');
  S.players[0].since = S.players[1].since = Date.now();
  S.courts[0].match = { a: [id(1), id(5)], b: [id(6), id(7)], start: Date.now() };
  console.assert(!pick('doubles', eligible('doubles')).a.concat(pick('doubles', eligible('doubles')).b).some(p => p.id === id(0)), 'a locked player waits while their teammate is on court');
  // Two far-apart locked pairs both overdue: one of them plays (with two others), not the two pairs against each other.
  S = { players: [4.2, 2.1, 4.5, 4.3, 1.6, 1.4, 3.7, 3.3, 2.2, 1.1, 2.3, 1.7].map((sk, i) => ({ ...fresh(i), skill: sk })), courts: [court('C1', 'doubles')], results: [], tournament: null };
  setLock(id(0), id(1)); setLock(id(2), id(3));
  for (let i = 0; i < 4; i++) { S.players[i].since = Date.now() - 30 * 60000; }
  S.results.push({ winner: 0, a: [id(8), id(9)], b: [id(10), id(11)], start: Date.now() - 3600000 });
  const od2 = pick('doubles', queue()), od2ids = [...od2.a, ...od2.b].map(p => p.id);
  console.assert(od2ids.filter(x => [id(0), id(1), id(2), id(3)].includes(x)).length === 2 && keepsLocks(od2.a.map(p => p.id), od2.b.map(p => p.id), lockContext(queue()), false),
    'two overdue locked pairs: one plays, still together');
  // Regression cases shared with the native model: strict opponents, queue protection and independent cooldowns.
  S = {players:[4,4,2,2].map((skill,i)=>({...fresh(i),skill})),courts:[court('C1','doubles')],results:[],tournament:null};
  setLock(id(0),id(1));
  console.assert(!pick('doubles',queue()), 'a locked team never immediately faces weaker opponents');
  S.players[2].credit=S.players[3].credit=2;
  console.assert(pick('doubles',queue())?.note?.includes('catch up on games'), 'an unmatchable lock releases before falling further behind');
  S.players[2].credit=S.players[3].credit=null;
  for (const p of S.players) p.since = p.readyAt = Date.now()-21*60000;
  S.results.push({a:[id(2)],b:[id(3)],winner:0,start:Date.now()-21*60000});
  const released = pick('doubles',queue());
  console.assert(released && released.a.some(p=>p.id===id(0)) !== released.a.some(p=>p.id===id(1)), 'unmatchable pairs become independently eligible at the 20-minute priority');
  S = {players:[4,4,...Array(12).fill(2),4.1,4.1].map((skill,i)=>({...fresh(i),skill})),courts:[court('C1','doubles')],results:[],tournament:null};
  setLock(id(0),id(1));
  const ratingLock = lockContext(queue())[0], fullLine = lockedGame(queue(),ratingLock,[ratingLock]);
  console.assert(fullLine && fullLine.b.some(p=>p.id===id(14)) && fullLine.b.some(p=>p.id===id(15)), 'locked opponents are searched beyond twelve waiting players');
  S.results.push({a:[id(14)],b:[id(15)],winner:0,start:Date.now()});
  console.assert(!lockedGame(queue(),ratingLock,[ratingLock]), 'locked opponents keep rest protection');
  S.results=[];S.players[14].credit=S.players[15].credit=3;
  console.assert(!lockedGame(queue(),ratingLock,[ratingLock]), 'locked opponents cannot be more than one game ahead');
  S = {players:Array.from({length:9},(_,i)=>fresh(i)),courts:[court('C1','doubles')],results:[],tournament:null};
  setLock(id(0),id(1));
  for(let i=0;i<3;i++) S.results.push({a:[id(0),id(1)],b:[id(2),id(3)],winner:0,start:Date.now()-600000});
  S.courts[0].match={a:[id(0),id(2)],b:[id(3),id(4)],start:Date.now()};
  S.players[1].first=true;S.players[1].since=Date.now();
  const independent=pick('doubles',eligible('doubles'));
  console.assert(independent && [...independent.a,...independent.b].some(p=>p.id===id(1)), 'cooldown partners can play on different courts at the same time');
  for(const first of [0,2]) {
    S={players:Array.from({length:4},(_,i)=>fresh(i)),courts:[court('C1','doubles')],results:[],tournament:null};
    setLock(id(0),id(1));
    for(let i=0;i<3;i++) S.results.push({a:[id(0),id(1)],b:[id(2),id(3)],winner:0,start:Date.now()});
    S.players[first].first=true;
    const g=pick('doubles',queue());
    console.assert(g && g.a.some(p=>p.id===id(0)) !== g.a.some(p=>p.id===id(1)), 'four available players can play during cooldown regardless of queue order');
  }
  S = keep;
}

export const setS = x => { S = x; }, setSessions = x => { sessions = x; }, setCurrentId = x => { currentId = x; };
export const getS = () => S, getSessions = () => sessions, getCurrentId = () => currentId;

export function streakDots(filled, boost) {
  const clamp = x => Math.min(1, Math.max(0, x));
  const parts = [1, 2, 3, 4, 5].map(i => boost > 0 ? (i > filled ? clamp(filled + boost - (i - 1)) : 0) : boost < 0 ? (i <= filled ? clamp(i - (filled + boost)) : 0) : 0);
  return { parts, ring: boost < 0 && -boost > filled, fire: boost > 0 && filled + boost > 5 };
}

export function scheduledPenalties() {
  const n = {};
  for (const r of counted()) for (const id of [...r.a,...r.b]) {
    if (r.scheduled && (r.jumpers||[]).includes(id)) n[id]=2;
    else if (!r.scheduled) n[id]=Math.max(0,(n[id]||0)-1);
  }
  return n;
}

export function scheduledJumpers(ids) {
  const games=counted();
  return ids.filter(id=>{const last=games.filter(r=>[...r.a,...r.b].includes(id)).at(-1);return last && games.filter(r=>r.court===last.court).at(-1)===last;});
}
