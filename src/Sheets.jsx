// The sheets (iPad form sheets; full width from the bottom on phones): add, edit and replace players, standings and
// history, sessions, earlier players, everyone, teammate locks and tournament setup.
import { useRef, useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Circle, CircleCheck, History, Plus, Trash2, Trophy, UserPlus, Users, CirclePause } from 'lucide-react';
import { cn } from 'cn';
import {
  postponeScheduled, scheduleMatch, scheduledStatus, scheduledDone, scheduledPlaying, cancelScheduled, endLabel, getS, SKILL, PREFS, P, level, r1, avg, names, played, wins, score, isDupName, addPlayer, arrive, replacements, replace, courtById, clone,
  deleteResult, past, returningPlayers, registry, queue, setLock, splitDue, rankingMinimum, places,
  tournamentEntrants, buildTournament, withMatching,
} from './engine';
import { ui, save, closeModal, openModal, openEdit, confirm, switchTo, newSession, deleteSession } from './store';
import { cap, plural, row, btnRow, Dots, Rating, Section, Seg } from './bits';
import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import { Slider } from '@/components/ui/slider';
import { Switch } from '@/components/ui/switch';

const SHEETS = { addPlayer: AddPlayer, edit: EditPlayer, replace: ReplacePlayer, results: Results, sessions: Sessions, returning: Returning,
  allPlayers: AllPlayers, sessionPlayers: SessionPlayers, scheduled: ScheduledMatches, pairing: Pairing, tsetup: TournamentSetup };

export function Sheets() {
  const m = ui.modal, Sheet = m && SHEETS[m.type];
  return Sheet ? <Sheet key={m.type + (m.id || m.out || '')} m={m} /> : null;
}

/** An iPad form sheet: Cancel on the left, the title, the confirming action on the right. */
function Sheet({ title, children, left = { label: 'Cancel', run: closeModal }, right, center, bottom, full, focusInput }) {
  return (
    <Dialog open onOpenChange={o => !o && closeModal()}>
      <DialogContent showCloseButton={false} aria-describedby={undefined}
        // Typing sheets focus their text field; others focus the sheet itself, so the iPad keyboard doesn't pop up.
        onOpenAutoFocus={e => { e.preventDefault(); (focusInput && e.currentTarget.querySelector('input[type=text]') || e.currentTarget).focus(); }}
        className={cn('sheet flex flex-col gap-0 overflow-hidden border-0 p-0 shadow-2xl outline-none sm:max-w-none',
          full ? 'top-0 left-0 h-dvh w-full max-w-none translate-x-0 translate-y-0 rounded-none pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)]'
            : 'max-h-[min(86dvh,760px)] w-[min(560px,calc(100%-2rem))] max-w-none rounded-2xl max-sm:top-auto max-sm:bottom-0 max-sm:w-full max-sm:max-h-[calc(100dvh-env(safe-area-inset-top)-12px)] max-sm:translate-y-0 max-sm:rounded-b-none max-sm:pb-[env(safe-area-inset-bottom)]')}>
        <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-2 px-4 py-2">
          <span className="justify-self-start">{left && <NavButton {...left} />}</span>
          {center ?? <DialogTitle className="text-center text-[17px] font-semibold">{title}</DialogTitle>}
          <span className="justify-self-end">{right && <NavButton strong {...right} />}</span>
        </div>
        {center && <DialogTitle className="sr-only">{title}</DialogTitle>}
        <div className={cn('flex min-h-0 flex-1 flex-col gap-[22px] overflow-auto px-4 pt-1 pb-6 [&>*]:flex-none', full && '[&>*]:mx-auto [&>*]:w-full [&>*]:max-w-[820px]')}>{children}</div>
        {bottom && <div className="flex justify-center border-t px-4 py-1.5">{bottom}</div>}
      </DialogContent>
    </Dialog>
  );
}
const NavButton = ({ label, run, disabled, strong }) => (
  <button className={cn('min-h-11 px-0.5 text-[17px] text-ink disabled:text-faint', strong && 'font-semibold')} disabled={disabled} onClick={run}>{label}</button>
);
const field = 'block w-full bg-transparent outline-none placeholder:text-faint';
const select = 'max-w-[60%] bg-transparent text-right text-muted-foreground outline-none';
const Search = ({ value, onChange }) => (
  <input type="search" className="w-full rounded-[10px] bg-secondary px-3 py-2 outline-none" placeholder="Search players" aria-label="Search players" value={value} onChange={e => onChange(e.target.value)} />
);
const match = (search, name) => !search || name.toLowerCase().includes(search.toLowerCase());
const Who = ({ name, sub, subClass }) => (
  <span className="grid min-w-0"><b className="truncate font-semibold">{name}</b><small className={cn('truncate text-xs text-muted-foreground', subClass)}>{sub}</small></span>
);

/** Adds people as they arrive. The sheet stays open so several can be added in a row. */
function AddPlayer() {
  const [name, setName] = useState(''), [skill, setSkill] = useState(3), [added, setAdded] = useState([]);
  const input = useRef(null);
  const nm = name.trim(), dup = isDupName(nm);
  const add = () => { if (!nm || dup) return; addPlayer(nm, skill); save(); setAdded(a => [...a, nm]); setName(''); input.current?.focus(); };
  return (
    <Sheet title="Add Player" focusInput left={{ label: 'Done', run: closeModal }} right={{ label: 'Add', run: add, disabled: !nm || dup }}>
      <form onSubmit={e => { e.preventDefault(); add(); }}>
        <Section foot={dup && <span className="text-destructive">{nm} is already in this session.</span>}>
          <div className={row}><input ref={input} type="text" className={field} placeholder="Player name" autoComplete="off" maxLength={40} aria-label="Player name" value={name} onChange={e => setName(e.target.value)} /></div>
          <label className={cn(row, 'flex items-center justify-between gap-3')}>
            <span>Skill</span>
            <select className={select} value={skill} onChange={e => setSkill(+e.target.value)}>{SKILL.map((s, i) => <option key={s} value={i + 1}>{s}</option>)}</select>
          </label>
        </Section>
      </form>
      {added.length > 0 && <Section head="Added"><div className={row}>{added.join(', ')}</div></Section>}
    </Sheet>
  );
}

function EditPlayer({ m }) {
  const p = P(m.id);
  const [name, setName] = useState(m.name), [skill, setSkill] = useState(m.skill), [pref, setPref] = useState(m.pref);
  const [paused, setPaused] = useState(m.paused), [present, setPresent] = useState(m.present);
  useEffect(() => { if (!p) closeModal(); }, [p]);
  if (!p) return null;
  const nm = name.trim(), dup = isDupName(nm, m.id);
  /** A rename also applies to this person in earlier sessions, so they stay one person in "From Earlier Sessions". */
  const saveEdit = () => {
    if (!nm || dup) return;
    const old = p.name.toLowerCase();
    p.name = nm; p.skill = Math.round(skill * 10) / 10; p.pref = pref; p.paused = paused;
    if (present) arrive(p.id); else p.away = true;
    if (old !== nm.toLowerCase()) for (const x of past()) for (const q of x.players) if (q.name.toLowerCase() === old) q.name = nm;
    save(); closeModal();
  };
  return (
    <Sheet title="Edit Player" right={{ label: 'Save', run: saveEdit, disabled: !nm || dup }}>
      <Section foot={dup && <span className="text-destructive">Another player in this session is already called {nm}.</span>}>
        <div className={row}><input type="text" className={cn(field, 'text-xl font-semibold')} value={name} maxLength={40} aria-label="Name" onChange={e => setName(e.target.value)} /></div>
      </Section>
      <Section head="Rating" foot={`Wins and losses keep adjusting this. ${played(p.id)} played · ${wins(p.id)} won this session.`}>
        <div className={cn(row, 'flex items-center justify-between gap-3')}>
          <span className="flex items-center gap-2"><Dots skill={skill} />{SKILL[level(skill) - 1]}</span>
          <span className="text-xl font-bold tabular-nums">{r1(skill)}</span>
        </div>
        <div className={cn(row, 'flex items-center gap-3')}>
          <span className="text-muted-foreground">1</span>
          <Slider min={1} max={5} step={0.1} value={[skill]} onValueChange={([v]) => setSkill(v)} aria-label="Rating" className="flex-1 py-3" />
          <span className="text-muted-foreground">5</span>
        </div>
        <div className={row}><Seg label="Set level" value={String(level(skill))} onChange={n => setSkill(+n)} options={[1, 2, 3, 4, 5].map(n => ({ value: String(n), label: n }))} /></div>
      </Section>
      <Section head="Plays" foot="Sitting out keeps their place in line; their wait clock keeps running.">
        <div className={row}><Seg label="Plays" value={pref} onChange={setPref} options={PREFS.map(v => ({ value: v, label: cap(v) }))} /></div>
        <label className={cn(row, 'flex min-h-11 items-center justify-between gap-3')}><span>Sitting out</span><Switch checked={paused} onCheckedChange={setPaused} /></label>
      </Section>
      <Section foot="Off until they arrive. Turned on, they join the line like a late arrival, with their wait starting then.">
        <label className={cn(row, 'flex min-h-11 items-center justify-between gap-3')}><span>Present</span><Switch checked={present} onCheckedChange={setPresent} /></label>
      </Section>
    </Sheet>
  );
}

function ReplacePlayer({ m }) {
  const out = P(m.out), c = courtById(m.court);
  const all = withMatching(() => replacements(m.out, m.court));
  // Best fit: keeps the game even and is close to the replaced player's level. Everyone else, closest level first.
  const gap = x => Math.abs(x.player.skill - (out?.skill ?? 3)), fits = x => x.even && gap(x) <= 1;
  const best = all.filter(fits), rest = all.filter(x => !fits(x)).sort((x, y) => gap(x) - gap(y));
  const doReplace = id => {
    const before = clone(getS());
    const k = replace(m.out, id, m.court);
    save();
    if (!k || k.even) return closeModal();
    confirm({ title: `${k.court} is now uneven`, noCancel: true,
      message: k.incoming ? `${k.lost} moved to ${c?.name ?? ''}, so ${k.incoming} joins ${k.court} instead. Nobody waiting keeps that game even.`
        : `${k.lost} moved to ${c?.name ?? ''}. Nobody else is free for ${k.court}, so it waits for players.`,
      actions: [{ label: 'Accept', run: closeModal }, { label: 'Undo', strong: true, run: () => { Object.assign(getS(), before); save(); closeModal(); } }] });
  };
  const pickRow = x => (
    <button key={x.player.id} className={cn(btnRow, 'justify-between')} onClick={() => x.even ? doReplace(x.player.id) : confirm({
      title: 'Uneven matchup', message: `With ${x.player.name} instead of ${out?.name ?? ''}, one side on ${c?.name ?? ''} is noticeably stronger.`,
      actions: [{ label: `Use ${x.player.name}`, run: () => doReplace(x.player.id) }] })}>
      <Who name={x.player.name} subClass={(x.from || !x.even) && 'text-singles'}
        sub={`${played(x.player.id)} played${x.even ? '' : ' · makes it uneven'}${x.from ? ' · next up on ' + x.from : ''}`} />
      <Rating p={x.player} />
    </button>
  );
  return (
    <Sheet title={`Replace ${out?.name ?? ''}`}>
      {!all.length && <Section><div className={cn(row, 'text-muted-foreground')}>Nobody else is waiting who can play this game.</div></Section>}
      {best.length > 0 && <Section head="Best fit · similar level, keeps the game even" foot="Fewest games first. Picking someone already lined up on another court moves them here; that court gets a replacement.">{best.map(pickRow)}</Section>}
      {rest.length > 0 && <Section head="Less of a fit · closest level first">{rest.map(pickRow)}</Section>}
    </Sheet>
  );
}

function Results({ m }) {
  const S = getS(), [tab, setTab] = useState(m.tab || 'standings');
  return (
    <Sheet full title={`${plural(S.results.length, 'game')} played`} left={null} right={{ label: 'Done', run: closeModal }}
      center={<Seg label="View" value={tab} onChange={setTab} options={[{ value: 'standings', label: 'Standings' }, { value: 'history', label: 'Match History' }]} />}>
      {tab === 'standings' ? <Standings /> : <MatchHistory />}
    </Sheet>
  );
}

let risen = false; // the podium rises the first time it shows, not on every visit to the tab
function Standings() {
  const S = getS();
  // Ranked by score; anyone yet to play goes last.
  const minimum = rankingMinimum();
  const rows = S.players.map(p => ({ p, w: wins(p.id), n: played(p.id), sc: score(p.id) }))
    .sort((a, b) => (b.n >= minimum && b.n > 0) - (a.n >= minimum && a.n > 0) || b.sc - a.sc || b.w - a.w);
  const ranks = places(rows.filter(r => r.n >= minimum && r.n > 0).map(r => r.sc));
  const top = rows.map((r, i) => ({ ...r, rank: ranks[i] })).filter(r => r.w > 0 && r.rank <= 3);
  const rise = useRef(!risen).current;
  useEffect(() => { if (top.length) risen = true; });
  if (!rows.length) return <Section><div className={cn(row, 'text-muted-foreground')}>No players yet.</div></Section>;
  const medal = ['bg-[#cc8f0d] text-white', 'bg-[#949eab] text-white', 'bg-[#9e5929] text-white'];
  const stat = (v, label) => <span><strong className="block text-[17px] font-semibold tabular-nums">{v ?? '–'}</strong><small className="text-[11px] text-muted-foreground">{label}</small></span>;
  return <>
    {top.length > 0 && <Podium top={top} rise={rise} />}
    <Section head={top.length ? 'All players' : ''} foot="Score uses wins and losses with two extra wins and two extra losses. Game length does not affect it. Equal scores share a rank. Ranking requires at least 75% of the median games played.">
      {rows.map((r, i) => (
        <div key={r.p.id} className={cn(row, 'flex items-center gap-3')}>
          <span className={cn('grid size-7 flex-none place-items-center rounded-full bg-secondary text-sm font-extrabold tabular-nums text-muted-foreground', ranks[i] && ranks[i] <= 3 && medal[ranks[i] - 1])}
            aria-label={ranks[i] ? 'Rank ' + ranks[i] : 'Not ranked yet'}>{ranks[i] || '–'}</span>
          <b className="min-w-0 flex-1 truncate font-semibold">{r.p.name}</b>
          <span className="grid grid-cols-[repeat(4,minmax(40px,auto))] gap-x-2.5 text-center sm:gap-x-4">
            {stat(r.w, 'Won')}{stat(r.n, 'Played')}{stat(r.n ? Math.round(r.w * 100 / r.n) : null, 'Win %')}{stat(r.n ? r.sc.toFixed(1) : null, 'Score')}
          </span>
        </div>
      ))}
    </Section>
  </>;
}

/** The top three on a podium in an arena at night (floodlights, net and posts, court lines in perspective, a shuttle's flight). */
function Podium({ top, rise }) {
  const order = top.map((_, i) => i).sort((a, b) => [1, 0, 2][top[a].rank - 1] - [1, 0, 2][top[b].rank - 1]);
  const initials = n => n.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase();
  const floor = [-48, 36, 300, 564, 648].map(x => `M${x} 300L${(x + (300 - x) * 0.239).toFixed(1)} 168`).join('');
  const height = ['h-[130px] text-[52px]', 'h-24 text-[40px]', 'h-[74px] text-[40px]'];
  const delay = [0.3, 0.15, 0];
  return (
    <div className="relative overflow-hidden rounded-[20px] bg-court-deep px-3.5 pt-[30px]">
      <svg className="absolute inset-0 size-full" viewBox="0 0 600 300" preserveAspectRatio="none" aria-hidden="true">
        <defs>
          <linearGradient id="ag" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#0a2119" /><stop offset=".55" stopColor="#144530" /><stop offset="1" stopColor="#2e7a54" /></linearGradient>
          <radialGradient id="al"><stop offset="0" stopColor="#fff" stopOpacity=".2" /><stop offset="1" stopColor="#fff" stopOpacity="0" /></radialGradient>
          <pattern id="am" width="7" height="7" patternUnits="userSpaceOnUse"><path d="M7 0V7M0 7H7" stroke="#fff" strokeOpacity=".09" strokeWidth=".6" /></pattern>
        </defs>
        <rect width="600" height="300" fill="url(#ag)" /><circle cx="60" cy="-15" r="260" fill="url(#al)" /><circle cx="540" cy="-15" r="260" fill="url(#al)" />
        <path d={`${floor}M0 210H600M0 258H600M0 168H600`} stroke="#fff" strokeOpacity=".16" strokeWidth="1.5" vectorEffect="non-scaling-stroke" fill="none" />
        <rect x="30" y="108" width="540" height="60" fill="url(#am)" /><rect x="30" y="108" width="540" height="3" fill="#fff" fillOpacity=".75" />
        <rect x="27" y="102" width="4" height="72" rx="2" fill="#fff" fillOpacity=".6" /><rect x="569" y="102" width="4" height="72" rx="2" fill="#fff" fillOpacity=".6" />
        <path d="M60 98Q240 -18 528 36" stroke="#fff" strokeOpacity=".3" strokeWidth="1.5" strokeDasharray="3 6" strokeLinecap="round" vectorEffect="non-scaling-stroke" fill="none" />
        <ellipse cx="528" cy="36" rx="3" ry="3" fill="#fff" fillOpacity=".85" />
      </svg>
      <svg className="absolute top-[4%] left-1/2 w-[min(34%,210px)] -translate-x-1/2 opacity-[.13]" viewBox="-100 -130 200 200" aria-hidden="true">
        <defs><pattern id="as" width="6" height="6" patternUnits="userSpaceOnUse"><path d="M6 0V6M0 6H6" stroke="#fff" strokeWidth=".7" /></pattern></defs>
        {[-31.5, 31.5].map(a => <g key={a} transform={`rotate(${a})`}><ellipse cx="0" cy="-62" rx="24" ry="31" fill="url(#as)" stroke="#fff" strokeWidth="3" /><path d="M0 -31V30" stroke="#fff" strokeWidth="2.5" /><rect x="-3.5" y="30" width="7" height="28" rx="3" fill="#fff" /></g>)}
      </svg>
      <div className="relative z-10 grid items-end gap-2.5" style={{ gridTemplateColumns: `repeat(${order.length},1fr)` }}>
        {order.map(i => { const r = top[i], step = r.rank - 1;
          return (
            <motion.div key={r.p.id} className={cn(`p${r.rank}`, 'grid min-w-0 justify-items-center gap-1.5 text-center text-white')} role="img"
              aria-label={`Place ${r.rank}: ${r.p.name}, ${r.w} of ${r.n} won, score ${r.sc.toFixed(1)}`}
              initial={rise && { opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.5, delay: delay[step] }}>
              {/* A gold shuttlecock above the winner (cork down: feather skirt with ribs and a thread band, white cork). */}
              <svg className={cn('h-[35px] w-7 drop-shadow-[0_0_6px_rgba(255,214,89,.8)]', step && 'invisible')} viewBox="0 0 24 30" aria-hidden="true">
                <defs><linearGradient id="cg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#ffd659" /><stop offset="1" stopColor="#cc8f0d" /></linearGradient></defs>
                <path d="M8.6 21 .5 1.8Q12 4.8 23.5 1.8L15.4 21Z" fill="url(#cg)" />
                <path d="M9.4 20.4 4.8 3M10.7 20.4 8.4 3.2M12 20.4V3.4M13.3 20.4 15.6 3.2M14.6 20.4 19.2 3M4.8 11.4Q12 13.2 19.2 11.4" stroke="#fff" strokeOpacity=".7" strokeWidth=".8" fill="none" />
                <ellipse cx="12" cy="24.5" rx="5.3" ry="5.1" fill="#fff" stroke="#cc8f0d" />
              </svg>
              <span aria-hidden="true" className={cn('grid place-items-center rounded-full border-[3px] border-white/90 bg-[linear-gradient(135deg,var(--m1),var(--m2))] font-round font-extrabold [text-shadow:0_1px_1px_rgba(0,0,0,.25)]',
                step ? 'size-[58px] text-[21px] shadow-[0_0_12px_var(--m1)]' : 'size-[70px] text-[26px] shadow-[0_0_22px_var(--m1)]')}>{initials(r.p.name)}</span>
              <b aria-hidden="true" className="max-w-full truncate text-[17px] font-semibold" title={r.p.name}>{r.p.name}</b>
              <span aria-hidden="true" className="flex gap-1.5 text-xs font-semibold tabular-nums opacity-85"><span>{r.w}–{r.n - r.w}</span><span className="rounded-full bg-white/20 px-[7px]">{r.sc.toFixed(1)}</span></span>
              <motion.div aria-hidden="true" style={{ originY: 1 }} initial={rise && { scaleY: 0.02 }} animate={{ scaleY: 1 }} transition={{ duration: 0.6, delay: delay[step], ease: [0.3, 1.4, 0.5, 1] }}
                className={cn('relative w-full rounded-t-xl bg-[linear-gradient(var(--m1),var(--m2))] pt-3.5 font-round leading-none font-black [text-shadow:0_2px_2px_rgba(0,0,0,.25)]', height[step],
                  'before:absolute before:top-1.5 before:right-3.5 before:left-3.5 before:h-[5px] before:rounded-full before:bg-white/45')}>{r.rank}</motion.div>
            </motion.div>
          ); })}
      </div>
    </div>
  );
}

function MatchHistory() {
  const S = getS();
  if (!S.results.length) return <Section><div className={cn(row, 'text-muted-foreground')}>Finished games show up here.</div></Section>;
  const team = (ids, won) => <span className={won ? 'font-bold' : 'text-muted-foreground'}>{won && <Trophy className="mr-1 inline size-4 fill-current text-singles" />}{names(ids)}</span>;
  return (
    <Section foot="Deleting a game entered by mistake also undoes its rating change.">
      {S.results.map((r, i) => ({ r, i })).reverse().map(({ r, i }) => { const f = r.a.length === 1 ? 'singles' : 'doubles';
        return (
          <div key={i} className={cn(row, 'grid gap-1.5')}>
            <div className="flex min-w-0 items-center gap-2 text-xs">
              <span className={cn('text-[11px] font-bold uppercase tracking-wide', f === 'singles' ? 'text-singles' : 'text-ink')}>{f}</span>
              <span className="truncate tabular-nums text-muted-foreground">{r.court}{r.label ? ' · ' + r.label : ''} · {new Date(r.end).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })} · {Math.floor((r.end - r.start) / 60000)} min</span>
              <span className="flex-1" /><span className="whitespace-nowrap tabular-nums text-muted-foreground">Game {i + 1}</span>
              <button className="-my-2 grid size-11 place-items-center text-destructive" aria-label={`Delete game ${i + 1}`} title="Delete game" onClick={() => { deleteResult(i); save(); }}><Trash2 className="size-[19px]" /></button>
            </div>
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[15px]">{team(r.a, r.winner === 0)}<span className="text-[13px] text-muted-foreground">vs</span>{team(r.b, r.winner === 1)}{r.winner == null && <span className="text-[13px] text-muted-foreground">No result</span>}</div>
          </div>
        ); })}
    </Section>
  );
}

function Sessions() {
  const S = getS();
  const when = x => new Date(x.date).toLocaleString(undefined, { weekday: 'long', month: 'long', day: 'numeric', hour: 'numeric', minute: '2-digit' });
  const sub = x => `${x.tournament ? 'Tournament · ' : ''}${plural(x.players.length, 'player')} · ${plural(x.results.length, 'game')}${x.ended!=null?' · Ended '+endLabel(x):''}`;
  const askDelete = x => confirm({ title: 'Delete this session and its results?',
    message: `${new Date(x.date).toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' })} · ${plural(x.results.length, 'game')}. This can't be undone.`,
    actions: [{ label: 'Delete Session', danger: true, run: () => deleteSession(x.id) }] });
  const sessionRow = (x, open) => (
    <div key={x.id} className={cn(row, 'flex items-center gap-2 py-1.5')}>
      <button className="grid min-h-11 min-w-0 flex-1 gap-0.5 text-left disabled:cursor-default" disabled={!open} onClick={() => { switchTo(x.id); closeModal(); }}>
        <b className="font-semibold">{when(x)}</b><small className="text-xs text-muted-foreground">{sub(x)}</small>
      </button>
      <button className="grid size-11 place-items-center text-destructive" aria-label={`Delete session from ${when(x)}`} title="Delete session" onClick={() => askDelete(x)}><Trash2 className="size-[19px]" /></button>
    </div>
  );
  return (
    <Sheet title="Sessions" left={null} right={{ label: 'Done', run: closeModal }}>
      <Section>
        <button className={cn(btnRow, 'text-ink')} onClick={() => { newSession(true); closeModal(); }}><Users className="size-5" />New Session with Same Players</button>
        <button className={cn(btnRow, 'text-ink')} onClick={() => { newSession(false); closeModal(); }}><Plus className="size-5" />New Empty Session</button>
      </Section>
      <Section head="Current">{sessionRow(S, false)}</Section>
      {past().length > 0 && <Section head="Earlier">{past().map(x => sessionRow(x, true))}</Section>}
    </Sheet>
  );
}

function Returning() {
  const [search, setSearch] = useState(''), [picked, setPicked] = useState([]);
  const all = returningPlayers(), shown = all.filter(p => match(search, p.name));
  const add = () => { for (const n of picked) { const p = all.find(x => x.name === n); if (p) addPlayer(p.name, p.skill, p.rated ?? null); } save(); closeModal(); };
  return (
    <Sheet title="Earlier Players" right={{ label: picked.length ? 'Add ' + picked.length : 'Add', run: add, disabled: !picked.length }}
      bottom={all.length > 0 && <NavButton label={picked.length === all.length ? 'Clear All' : 'Select All'} run={() => setPicked(picked.length === all.length ? [] : all.map(p => p.name))} />}>
      <Search value={search} onChange={setSearch} />
      <Section>
        {!all.length ? <div className={cn(row, 'text-muted-foreground')}>{past().length ? 'Everyone from earlier sessions is already in this one.' : 'No earlier sessions yet. Players you add today will show up here next time.'}</div>
          : shown.map(p => { const on = picked.includes(p.name);
            return (
              <button key={p.name} className={btnRow} aria-pressed={on} onClick={() => setPicked(on ? picked.filter(x => x !== p.name) : [...picked, p.name])}>
                {on ? <CircleCheck className="size-6 fill-ink text-card" /> : <Circle className="size-6 text-faint" />}
                <b className="flex-1 truncate font-semibold">{p.name}</b><Dots skill={p.skill} /><small className="text-[11px] tabular-nums text-muted-foreground">{r1(p.skill)}</small>
              </button>
            ); })}
        {all.length > 0 && !shown.length && <div className={cn(row, 'text-muted-foreground')}>No matches.</div>}
      </Section>
    </Sheet>
  );
}

function AllPlayers() {
  const [search, setSearch] = useState('');
  const all = registry(), shown = all.filter(r => match(search, r.name));
  return (
    <Sheet title={`All Players · ${all.length}`} left={null} right={{ label: 'Done', run: closeModal }}>
      <Search value={search} onChange={setSearch} />
      <Section>
        {shown.map(r => (
          <div key={r.name} className={cn(row, 'flex items-center justify-between gap-3')}>
            <Who name={r.name} sub={`${plural(r.sessions, 'session')} · ${r.played} played · ${r.won} won · last ${new Date(r.last).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}`} />
            <Rating p={r} />
          </div>
        ))}
        {!shown.length && <div className={cn(row, 'text-muted-foreground')}>{all.length ? 'No matches.' : 'No players yet.'}</div>}
      </Section>
    </Sheet>
  );
}

/** Everyone in this session at a glance: where they are, games, what they play and rating. Tap one to edit. */
function SessionPlayers() {
  const S = getS(), [search, setSearch] = useState('');
  const line = queue().filter(p => !p.paused).map(p => p.id);
  const on = {}; for (const c of S.courts) if (c.match) [...c.match.a, ...c.match.b].forEach(id => { on[id] = on[id] || c.name; });
  const all = [...S.players].sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
  const shown = all.filter(p => match(search, p.name));
  const sitting = S.players.filter(p => p.paused && !p.away && !on[p.id]).length, away = S.players.filter(p => p.away && !on[p.id]).length;
  return (
    <Sheet title="Session Players" left={null} right={{ label: 'Done', run: closeModal }}>
      {!S.tournament && (
        <Section>
          <button className={cn(btnRow, 'text-ink')} onClick={() => openModal({ type: 'addPlayer' })}><UserPlus className="size-5" />New Player</button>
          <button className={cn(btnRow, 'text-ink')} onClick={() => openModal({ type: 'returning' })}><History className="size-5" />From Earlier Sessions</button>
        </Section>
      )}
      <Search value={search} onChange={setSearch} />
      <Section head={`${all.length} players · ${Object.keys(on).length} playing · ${line.length} waiting · ${sitting} sitting out${away ? ` · ${away} not here` : ''}`}
        foot="Tap a player to edit their name, rating, what they play, sit them out, or mark them present.">
        {shown.map(p => {
          const status = on[p.id] ? `On ${on[p.id]}` : p.away ? 'Not here' : p.paused ? 'Sitting out' : line.includes(p.id) ? `Waiting · #${line.indexOf(p.id) + 1}` : 'Waiting';
          return (
            <button key={p.id} className={cn(btnRow, 'justify-between', (p.paused || p.away) && !on[p.id] && 'opacity-60')} onClick={() => openEdit(p)} aria-label={`${p.name}, ${status}. Edit player`}>
              <Who name={p.name} sub={`${status} · ${played(p.id)} played · ${wins(p.id)} won`} subClass={on[p.id] && 'text-ink'} />
              <span className="flex-1" />
              <span className={cn('text-[11px] font-bold uppercase tracking-wide', p.pref === 'singles' ? 'text-singles' : p.pref === 'doubles' ? 'text-ink' : 'text-muted-foreground')}>{p.pref}</span>
              <Rating p={p} />
            </button>
          );
        })}
        {!shown.length && <div className={cn(row, 'text-muted-foreground')}>{all.length ? 'No matches.' : 'No players in this session yet.'}</div>}
      </Section>
    </Sheet>
  );
}

/** Discreet: only existing requests are listed; players are picked in the add step. */
function Pairing() {
  const S = getS(), [adding, setAdding] = useState(false), [a, setA] = useState(''), [b, setB] = useState('');
  const mutual = p => p.lock && P(p.lock)?.lock === p.id;
  if (adding) {
    const free = S.players.filter(p => p.pref !== 'singles' && !mutual(p));
    const pickOne = (label, val, set, other) => (
      <label className={cn(row, 'flex min-h-11 items-center justify-between gap-3')}><span>{label}</span>
        <select className={select} value={val} onChange={e => set(e.target.value)}>
          <option value="">Choose</option>{free.filter(p => p.id !== other).map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
      </label>
    );
    return (
      <Sheet title="Lock Teammates" left={{ label: 'Back', run: () => setAdding(false) }} right={{ label: 'Add', disabled: !(a && b), run: () => { setLock(a, b); save(); setAdding(false); } }}>
        <Section foot={free.length < 2 && 'Everyone who plays doubles already has a teammate lock.'}>{pickOne('Player', a, setA, b)}{pickOne('Partner', b, setB, a)}</Section>
      </Sheet>
    );
  }
  const pairs = S.players.filter(p => mutual(p) && p.id < p.lock).map(p => [p, P(p.lock)]);
  return (
    <Sheet title="Locked Teammates" left={null} right={{ label: 'Done', run: closeModal }}>
      <Section foot="Locked teams face real-average opponents from 0.50 lower through 1.25 higher. Unmatchable pairs wait 30 minutes before playing separately, even if a court is idle. After three wins together, each plays once with a different teammate; they need not face each other.">
        {pairs.map(([x, y]) => (
          <div key={x.id} className={cn(row, 'flex items-center justify-between gap-3 py-1.5')}>
            <Who name={`${x.name} & ${y.name}`} sub={splitDue(x.id, y.id) ? 'Cooldown · different teammates' : 'Locked together'} />
            <button className="grid size-11 place-items-center text-destructive" aria-label={`Remove teammate lock for ${x.name} and ${y.name}`} title="Remove" onClick={() => { setLock(x.id, null); save(); }}><Trash2 className="size-[19px]" /></button>
          </div>
        ))}
        {!pairs.length && <div className={cn(row, 'text-muted-foreground')}>No teammate locks.</div>}
        <button className={cn(btnRow, 'text-ink')} onClick={() => { setA(''); setB(''); setAdding(true); }}><Plus className="size-5" />Lock Teammates</button>
      </Section>
    </Sheet>
  );
}

function TournamentSetup({ m }) {
  const S = getS(), [format, setFormat] = useState(m.format), [advance, setAdvance] = useState(m.advance);
  const { entrants, out } = tournamentEntrants(format);
  const n = entrants.length, size = n >= 8 ? advance : 4, unit = format === 'doubles' ? 'teams' : 'players';
  const start = () => {
    if (n < 4) return;
    S.tournament = buildTournament(format, entrants, size);
    S.courts.forEach(c => { c.plan = null; c.shuffles = 0; });
    save(); closeModal();
  };
  return (
    <Sheet title="New Tournament" right={{ label: 'Start', run: start, disabled: n < 4 }}>
      <Section foot={format === 'doubles' ? 'Teams pair the strongest player with the newest, so teams are even.' : 'Every player plays every other player once.'}>
        <div className={row}><Seg label="Format" value={format} onChange={setFormat} options={['singles', 'doubles'].map(f => ({ value: f, label: cap(f) }))} /></div>
      </Section>
      <Section head="Bracket" foot="Double elimination: a side is out after two losses. The upper-bracket winner meets the lower-bracket winner in the Grand Final.">
        <div className={row}><Seg label="Go to the bracket" value={String(size)} onChange={v => setAdvance(+v)} options={[{ value: '4', label: 'Top 4' }, { value: '8', label: 'Top 8', disabled: n < 8 }]} /></div>
      </Section>
      <Section head={`${n} ${unit} · ${n * (n - 1) / 2} round-robin games + ${size === 8 ? 14 : 6} bracket games`}
        foot={n < 4 ? `A tournament needs at least 4 ${unit}.` : out.length ? `Sitting out: ${out.map(p => p.name).join(', ')}` : ''}>
        {entrants.map(ids => <div key={ids.join()} className={cn(row, 'flex items-center justify-between gap-3')}><b className="font-semibold">{names(ids)}</b><Dots skill={avg(ids)} /></div>)}
        {!n && <div className={cn(row, 'text-muted-foreground')}>No players yet.</div>}
      </Section>
    </Sheet>
  );
}

function ScheduledMatches() {
  const S = getS(), [adding,setAdding] = useState(false), [format,setFormat] = useState('doubles');
  const [slots,setSlots] = useState(['','','','']), [hours,setHours] = useState(S.hours ?? ''), [error,setError] = useState('');
  const saveRequest = () => {
    try {
      const h=Number(hours); if (!Number.isFinite(h)||h<=0) throw new Error('Enter a positive session length in hours.');
      const previous=S.hours; S.hours=h;
      try { scheduleMatch(format,slots.slice(0,slots.length/2),slots.slice(slots.length/2)); } catch(e) { S.hours=previous; throw e; }
      save(); setAdding(false); setError('');
    } catch(e) { setError(e.message); }
  };
  const valid=slots.every(Boolean)&&new Set(slots).size===slots.length&&Number(hours)>0;
  if (adding) return <Sheet title="Schedule a Match" left={{label:'Back',run:()=>setAdding(false)}} right={{label:'Save',disabled:!valid,run:saveRequest}}>
    <Section head="Session">
      <label className={cn(row,'flex justify-between gap-2')}>Length (hours)<input aria-label="Session length (hours)" type="number" min="0.5" step="0.5" value={hours} onChange={e=>setHours(e.target.value)} className="w-24 text-right" /></label>
      <div className={row}><Seg label="Scheduled match format" value={format} onChange={f=>{setFormat(f);setSlots(Array(f==='singles'?2:4).fill(''));}} options={['singles','doubles'].map(f=>({value:f,label:cap(f)}))} /></div>
    </Section>
    {[0,1].map(side=><Section key={side} head={side?'Team B':'Team A'}>{Array.from({length:slots.length/2},(_,n)=>{
      const k=side*slots.length/2+n;
      return <label key={k} className={cn(row,'flex justify-between gap-2')}>Player {n+1}<select aria-label={`Team ${side?'B':'A'} player ${n+1}`} value={slots[k]} onChange={e=>setSlots(slots.map((v,i)=>i===k?e.target.value:v))}>
        <option value="">Choose</option>{S.players.filter(p=>slots[k]===p.id||!slots.includes(p.id)).map(p=><option key={p.id} value={p.id}>{p.name}</option>)}
      </select></label>;
    })}</Section>)}
    {error&&<p role="alert">{error}</p>}
    <p className="text-sm text-muted-foreground">Each participant must have completed one game. Available participants wait for the others. Exact teams override locks and matching rules; you still press Start. Immediate returners get a temporary two-game queue-priority penalty and need one ordinary game before another scheduled match. An idle court may use held players once per request.</p>
  </Sheet>;
  return <Sheet title="Scheduled Matches" left={null} right={{label:'Done',run:closeModal}}>
    <Section foot="A match must have time to finish before the session ends. Typical duration uses the last ten completed games (12 minutes without history).">
      {(S.scheduled||[]).map(r=><div key={r.id} className={cn(row,'grid gap-2')}>
        <b>{names(r.a)} vs {names(r.b)}</b><small>{cap(r.format)} · {scheduledStatus(r)}</small>
        {!scheduledDone(r)&&!scheduledPlaying(r)&&<><button className="text-left" onClick={()=>act(()=>postponeScheduled(r.id))}>Postpone 10 min</button><button className="text-left text-destructive" onClick={()=>{cancelScheduled(r.id);save();}}>Cancel Request</button></>}
      </div>)}
      {!S.scheduled?.length&&<div className={cn(row,'text-muted-foreground')}>No scheduled matches.</div>}
      <button className={btnRow} disabled={!!S.tournament||S.ended!=null} onClick={()=>{setSlots(['','','','']);setFormat('doubles');setAdding(true);}}>Schedule a Match</button>
    </Section>
  </Sheet>;
}
