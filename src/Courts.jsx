// A court card: its name and format, the court with this game (or the next one, dimmed), and Start / Finish.
import { motion, AnimatePresence } from 'framer-motion';
import { Ellipsis, Lock, LockOpen, Shuffle, Trash2, Undo2 } from 'lucide-react';
import { cn } from 'cn';
import { getS, NEED, players, eligible, names, champion, fill, finish, shuffleCourt, lockSide, courtById } from './engine';
import { act, save, openModal, confirm } from './store';
import { cap, Dots, Seg } from './bits';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';

export function CourtCard({ c, next }) {
  const S = getS(), t = S.tournament, m = c.match;
  const format = t ? t.format : c.format, singles = format === 'singles';
  const labelId = m?.tm ?? next?.match;
  const gameLabel = t && labelId != null ? t.matches[labelId].label : null;
  const teams = m ? [players(m.a), players(m.b)] : next ? [next.a, next.b] : null;
  const canSwap = !t && !m && next;
  const short = NEED[format] - eligible(format).length;
  const options = !t && !m ? next?.options || 0 : 0;

  const half = ps => (
    <div className={cn('relative z-10 flex min-w-0 flex-col items-center justify-center gap-2 p-2 transition-opacity', !m && 'opacity-55')}>
      <AnimatePresence mode="popLayout" initial={false}>
        {ps ? ps.map(p => {
          const body = <><span className="max-w-full truncate">{p.name}</span><Dots skill={p.skill} className="text-white" /></>;
          const cls = 'flex max-w-full flex-col items-center gap-[3px] rounded-lg px-2 py-0.5 font-semibold leading-tight text-[22px] @xs:text-[24px] @sm:text-[26px] @md:text-[28px]';
          return (
            <motion.div key={p.id} className="max-w-full" initial={{ opacity: 0, scale: 0.85 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.85 }} transition={{ duration: 0.2 }}>
              {canSwap
                ? <button className={cn(cls, 'active:bg-white/15')} onClick={() => openModal({ type: 'replace', court: c.id, out: p.id })} aria-label={`Replace ${p.name}`}>{body}</button>
                : <span className={cls}>{body}</span>}
            </motion.div>
          );
        }) : <motion.span key="empty" className="text-[15px] opacity-70" initial={{ opacity: 0 }} animate={{ opacity: 0.7 }}>{singles ? '1 v 1' : '2 v 2'}</motion.span>}
      </AnimatePresence>
    </div>
  );

  const status = next ? `Next up${gameLabel ? ' · ' + gameLabel : ''}${next.note ? ' · ' + next.note : ''}`
    : t && champion(t) != null ? 'Tournament complete' : !t && short > 0 ? `Need ${short} more for ${format}` : 'Waiting for players';

  return (
    <motion.article
      aria-label={`${c.name}${m ? ', game in progress' : ''}`}
      className="@container grid min-w-0 gap-3 rounded-[14px] bg-card py-4"
      animate={{ boxShadow: m ? '0 0 0 1.5px var(--glow), 0 0 18px var(--glow)' : '0 0 0 0px var(--glow), 0 0 0px var(--glow)' }}
      transition={{ duration: 0.4 }}
    >
      <div className="flex min-w-0 items-center gap-2.5 px-4">
        <h2 className="max-w-[45%] flex-none truncate text-xl font-bold">{c.name}</h2>
        <span className="flex-1" />
        {t ? <span className="text-[13px] font-semibold text-muted-foreground">{cap(format)}</span>
          : <Seg small label={`${c.name} format`} value={c.format} disabled={!!m} className="max-w-[200px] min-w-0 flex-[0_1_200px]"
              options={['singles', 'doubles'].map(f => ({ value: f, label: cap(f) }))}
              onChange={f => act(() => { const x = courtById(c.id); x.format = f; x.plan = null; })} />}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon-pill" className="-mr-2 text-ink" aria-label={`${c.name} options`}><Ellipsis /></Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {m && <DropdownMenuItem onSelect={() => act(() => { courtById(c.id).match = null; })}><Undo2 />Undo Start</DropdownMenuItem>}
            <DropdownMenuItem variant="destructive" disabled={!!m} onSelect={() => act(() => { S.courts = S.courts.filter(x => x.id !== c.id); })}><Trash2 />Remove {c.name}</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <div className={cn('court relative grid aspect-[2.2/1] grid-cols-2 overflow-hidden rounded-[3px] bg-court text-white', format)}>
        <i className="lines" /><i className="net" />
        {half(teams?.[0])}{half(teams?.[1])}
        {canSwap && <><LockButton c={c} side={0} /><LockButton c={c} side={1} /></>}
      </div>

      <div className="flex min-h-11 min-w-0 items-center gap-2.5 px-4 text-[15px]">
        {m ? <>
          <span className="flex-1 tabular-nums text-muted-foreground">{gameLabel ? gameLabel + ' · ' : ''}{Math.floor((Date.now() - m.start) / 60000)} min</span>
          <Button variant="go" size="pill" onClick={() => confirm({
            title: `Who won on ${c.name}?`,
            actions: [
              { label: names(m.a), run: () => act(() => finish(c.id, 0)) },
              { label: names(m.b), run: () => act(() => finish(c.id, 1)) },
              { label: 'No result', run: () => act(() => finish(c.id, null)) },
            ],
          })}>Finish Game</Button>
        </> : <>
          <span className="line-clamp-2 min-w-0 flex-1 text-muted-foreground">{status}</span>
          {options > 1 && (
            <Button variant="tinted" size="icon-pill" className="flex-none" onClick={() => act(() => shuffleCourt(c.id))}
              title={singles ? 'Shuffle Opponent' : 'Shuffle Teams'} aria-label={`${singles ? 'Try another opponent' : 'Try other fair teams'} on ${c.name}`}><Shuffle /></Button>
          )}
          <Button size="pill" className="flex-none" disabled={!next} onClick={() => act(() => fill(c.id))}>Start {cap(format)}</Button>
        </>}
      </div>
    </motion.article>
  );
}

/** Lock one side of the next game: shuffle then changes only the other side. */
function LockButton({ c, side }) {
  const on = c.locked === side, where = side === 0 ? 'left' : 'right';
  return (
    <button
      className={cn('absolute top-1 z-20 grid size-11 place-items-center', side === 0 ? 'left-1' : 'right-1')}
      aria-pressed={on} aria-label={`${on ? 'Unlock' : 'Lock'} ${where} side`}
      title={on ? 'Locked: shuffle keeps this side' : 'Lock this side when shuffling'}
      onClick={() => { lockSide(c.id, on ? null : side); save(); }}
    >
      <span className={cn('grid size-8 place-items-center rounded-full', on ? 'bg-white text-court' : 'bg-court-deep/55 text-white')}>
        {on ? <Lock className="size-[17px]" /> : <LockOpen className="size-[17px]" />}
      </span>
    </button>
  );
}
