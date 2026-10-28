// The side panel: Queue / Tournament, Up Next for each court, then the queue (or the tournament's tables and brackets).
import { useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Ellipsis, CirclePause, Pause, Play, Pencil, ArrowUpToLine, Trash2, Trophy, UserX } from 'lucide-react';
import { cn } from 'cn';
import { scheduledPenalties, getS, queue, played, onCourt, matchingHelp, waitingMessage, waitStart, startedAt, isLocked, arrive, P, champion, tEntrant, entrantName, sidesIfReady, rrTable } from './engine';
import { act, openModal, openEdit as edit, confirm } from './store';
import { cap, plural, row, Dots, Section } from './bits';
import { Button } from '@/components/ui/button';
import { ContextMenu, ContextMenuContent, ContextMenuItem, ContextMenuSeparator, ContextMenuTrigger } from '@/components/ui/context-menu';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';

export function SidePanel({ up }) {
  const S = getS(), t = S.tournament;
  return (
    <div className="flex min-w-0 flex-col gap-[22px]">
      {t ? up.length > 0 && <Section head="Up Next">{up.map((p, i) => <UpRow key={i} label={t.matches[p.match].label} f={p.format} p={p} />)}</Section>
        : S.courts.some(c => c.match) && <div className="order-2"><Section head="After this game · projected">{S.courts.filter(c => c.match).map(c =>
            <UpRow key={c.id} label={`${c.name} · ${c.format}`} f={c.format} p={up.find(p => p.court === c.id)} />)}</Section></div>}
      {t ? <TournamentSections t={t} /> : <QueueSection />}
    </div>
  );
}

/** One court's next game: team on one line, a red VS, the other team underneath. */
const fmt = f => cn('text-[11px] font-bold uppercase tracking-wide', f === 'singles' ? 'text-singles' : 'text-ink');
function UpRow({ label, f, p }) {
  return (
    <div className={cn(row, 'grid gap-0.5')}>
      <span className={fmt(f)}>{label}</span>
      {p ? <>
        <b className="text-[15px] font-semibold [overflow-wrap:anywhere]">{p.a.map(x => x.name).join(' & ')}</b>
        <span className="text-xs font-medium text-muted-foreground">VS</span>
        <b className="text-[15px] font-semibold [overflow-wrap:anywhere]">{p.b.map(x => x.name).join(' & ')}</b>
      </> : <span className="text-[13px] text-muted-foreground">{waitingMessage()}</span>}
    </div>
  );
}

function QueueSection() {
  const S = getS(), q = queue(), away = S.players.filter(p => p.away);
  let n = 0;
  return <>
    <Section head={`Queue · ${q.length} off court · ${onCourt().size} playing`}
      foot={matchingHelp() + ' '
        + 'Fewest counted games first, then longest rested. Balanced recalls cannot be ahead in counted games. Both exact teams need another opponent before a rematch; overdue priority is paused.'}>
      <AnimatePresence initial={false}>
        {q.map(p => <QueueRow key={p.id} p={p} pos={p.paused ? null : ++n} />)}
      </AnimatePresence>
      {!q.length && <div className={cn(row, 'text-muted-foreground')}>{away.length ? 'Tap Here as players arrive.' : 'Add players as they arrive.'}</div>}
    </Section>
    {away.length > 0 && (
      <Section head={`Not Here Yet · ${away.length}`} foot="Tap Here when they arrive. Before the first game they line up in the order they arrive; after that, like a late arrival.">
        {away.map(p => (
          <div key={p.id} className={cn(row, 'flex items-center justify-between gap-3')}>
            <button className="min-h-11 min-w-0 flex-1 truncate text-left font-semibold" onClick={() => edit(p)} aria-label={`${p.name}, not here yet. Edit player`}>{p.name}</button>
            <Dots skill={p.skill} />
            <Button variant="tinted" size="pill" onClick={() => act(() => arrive(p.id))} aria-label={`${p.name} is here`}>Here</Button>
          </div>
        ))}
      </Section>
    )}
  </>;
}

/** A queue row: tap to edit; press and hold (or right-click) for sit out, move to front, not here and remove. */
function QueueRow({ p, pos }) {
  const S = getS();
  const start = useRef(null), menuOpened = useRef(false);
  const actions = (Item, Separator) => <>
        <Item onSelect={() => edit(p)}><Pencil />Edit Name or Rating</Item>
        <Item onSelect={() => act(() => { P(p.id).paused = !p.paused; })}>{p.paused ? <Play /> : <Pause />}{p.paused ? 'Back In' : 'Sit Out'}</Item>
        <Item onSelect={() => act(() => { const x = P(p.id); x.readyAt = Math.min(...S.players.map(y => y.readyAt)) - 1000; x.first = true; })}><ArrowUpToLine />Move to Front</Item>
        <Item onSelect={() => act(() => { P(p.id).away = true; })}><UserX />Not Here</Item>
        <Separator />
        <Item variant="destructive" onSelect={() => confirm({ title: `Remove ${p.name}?`, message: "They leave this session's queue. Games they played stay in the history.",
          actions: [{ label: `Remove ${p.name}`, danger: true, run: () => act(() => { S.players = S.players.filter(x => x.id !== p.id); }) }] })}><Trash2 />Remove from Session</Item>
      </>;
  return (
    <ContextMenu onOpenChange={o => { if (o) menuOpened.current = true; }}>
      <ContextMenuTrigger asChild
        // Radix cancels a long press on any finger movement; allow the 10px a resting finger drifts, as the iPad app does.
        onPointerDown={e => { start.current = [e.clientX, e.clientY]; menuOpened.current = false; }}
        onPointerMove={e => { if (start.current && Math.hypot(e.clientX - start.current[0], e.clientY - start.current[1]) <= 10) e.preventDefault(); }}>
        <motion.div layout="position" initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }}
          transition={{ duration: 0.25 }} className={cn(row, 'hold flex items-center gap-2.5 bg-card', p.paused && 'opacity-50')}>
          {/* The click that ends a long press would also open the editor; swallow it. */}
          <button className="flex min-h-11 min-w-0 flex-1 items-center gap-2.5 text-left" onClick={() => { if (menuOpened.current) { menuOpened.current = false; return; } edit(p); }}
            aria-label={`${p.name}, ${pos ? 'number ' + pos : 'sitting out'}. Edit name or rating. Press and hold for more.`}>
            <span className="flex min-w-7 justify-end font-semibold tabular-nums text-muted-foreground">{pos ?? <CirclePause className="size-5" />}</span>
            <span className="grid min-w-0">
              <b className="font-semibold [overflow-wrap:anywhere]">{p.name}</b>
              <small className="text-[13px] text-muted-foreground">{played(p.id)} played{scheduledPenalties()[p.id] ? ` · priority cooldown ${scheduledPenalties()[p.id]}` : ''}{isLocked(p) ? ` · with ${P(p.lock).name}` : ''}{startedAt() != null && S.ended == null ? ` · ${Math.max(0, Math.floor((Date.now() - waitStart(p)) / 60000))} min` : ''}</small>
            </span>
          </button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild><Button variant="ghost" size="icon-pill" aria-label={`Actions for ${p.name}`}><Ellipsis /></Button></DropdownMenuTrigger>
            <DropdownMenuContent>{actions(DropdownMenuItem, DropdownMenuSeparator)}</DropdownMenuContent>
          </DropdownMenu>
        </motion.div>
      </ContextMenuTrigger>
      <ContextMenuContent className="min-w-[230px]">{actions(ContextMenuItem, ContextMenuSeparator)}</ContextMenuContent>
    </ContextMenu>
  );
}

function TournamentSections({ t }) {
  const S = getS(), ch = champion(t), rr = t.matches.filter(m => m.stage === 'roundRobin');
  const ph = s => s[0] === 's' ? `Seed ${s[1] + 1}` : s[0] === 'w' ? `Winner, ${t.matches[s[1]].label}` : s[0] === 'l' ? `Loser, ${t.matches[s[1]].label}` : '';
  const side = (s, won) => { const e = tEntrant(t, s); return e == null ? <span className="italic text-muted-foreground">{ph(s)}</span>
    : <span className={cn(won && 'font-bold')}>{won && <Trophy className="mr-1 inline size-4 fill-current text-singles" />}{entrantName(e)}</span>; };
  const status = m => { const c = S.courts.find(c => c.match?.tm === m.id); return c ? `On ${c.name}` : m.winner == null && sidesIfReady(t, m) ? 'Ready' : ''; };
  const bracket = (stage, title) => (
    <Section head={title}>
      {t.matches.filter(m => m.stage === stage).map(m => (
        <div key={m.id} className={cn(row, 'grid gap-[3px]')}>
          <div className="flex justify-between gap-3 text-[13px] font-semibold"><span className="text-muted-foreground">{m.label}</span><span className="text-ink">{status(m)}</span></div>
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[15px]">{side(m.a, m.winner === 0)}<span className="text-[13px] text-muted-foreground">vs</span>{side(m.b, m.winner === 1)}</div>
        </div>
      ))}
    </Section>
  );
  return <>
    {ch != null && <Section><div className={cn(row, 'flex items-center gap-2 font-semibold text-singles')}><Trophy className="size-5 fill-current" />{entrantName(ch)} won the tournament</div></Section>}
    <Section head={`Round Robin · ${rr.filter(m => m.winner != null).length} of ${rr.length} played`} foot={`Top ${t.advance} (green) go to the bracket. Ties go to the higher-rated side.`}>
      {rrTable(t).map((r, i) => (
        <div key={r.e} className={cn(row, 'flex items-center justify-between gap-3')}>
          <span className="flex min-w-0 items-center gap-2.5">
            <span className={cn('min-w-6 text-right font-semibold tabular-nums', i < t.advance ? 'text-ink' : 'text-muted-foreground')}>{i + 1}</span>
            <span className={cn('truncate', i < t.advance && 'font-semibold')}>{entrantName(r.e)}</span>
          </span>
          <strong className="tabular-nums">{r.w}–{r.l}</strong>
        </div>
      ))}
    </Section>
    {bracket('upper', 'Upper Bracket')}{bracket('lower', 'Lower Bracket')}{bracket('final', 'Final')}
  </>;
}
