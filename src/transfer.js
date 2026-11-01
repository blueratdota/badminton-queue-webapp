// Copy/paste uses the existing JSON format; parse it as data, never executable code.
export function encodeTransfer(sessions, currentId) {
  return JSON.stringify({ currentId, sessions });
}
export function decodeTransfer(text) {
  let d;
  try { d = JSON.parse(text.trim()); } catch { throw new Error('Invalid data code. Copy the entire code from Export Data.'); }
  const validId = x => typeof x === 'string' && x.length > 0;
  const unique = xs => new Set(xs.map(x => x.id.toLowerCase())).size === xs.length;
  const team = x => Array.isArray(x) && x.every(validId);
  const match = (x, timed=true) => x && team(x.a) && team(x.b) && (!timed || Number.isFinite(x.start));
  const session = x => x && validId(x.id) && Number.isFinite(x.date)
    && Array.isArray(x.players) && unique(x.players.filter(p => p && validId(p.id)))
    && x.players.every(p => p && validId(p.id) && typeof p.name === 'string' && p.name.trim() && Number.isFinite(p.skill) && ['any','singles','doubles'].includes(p.pref ?? 'any'))
    && Array.isArray(x.courts) && unique(x.courts.filter(c => c && validId(c.id)))
    && x.courts.every(c => c && validId(c.id) && typeof c.name === 'string' && ['singles','doubles'].includes(c.format) && (!c.match || match(c.match)) && (!c.plan || match(c.plan,false)) && (c.manual == null || Array.isArray(c.manual) && c.manual.every(id => id == null || validId(id))))
    && Array.isArray(x.results) && x.results.every(r => match(r) && Number.isFinite(r.end) && (r.winner == null || r.winner === 0 || r.winner === 1))
    && (x.scheduled == null || Array.isArray(x.scheduled) && x.scheduled.every(r => r && validId(r.id) && ['singles','doubles'].includes(r.format) && team(r.a) && team(r.b)))
    && (x.tournament == null || ['singles','doubles'].includes(x.tournament.format) && Array.isArray(x.tournament.entrants) && x.tournament.entrants.every(team) && [4,8].includes(x.tournament.advance) && Array.isArray(x.tournament.matches) && x.tournament.matches.every(m => m && Number.isInteger(m.id) && ['a','b'].every(k => Array.isArray(m[k]) && m[k].length === 2 && ['e','s','w','l'].includes(m[k][0]) && Number.isInteger(m[k][1]))));
  if (!d || !Array.isArray(d.sessions) || !d.sessions.length || !d.sessions.every(session) || !unique(d.sessions)) throw new Error('Invalid or incomplete data code. Nothing was imported.');
  return d;
}
