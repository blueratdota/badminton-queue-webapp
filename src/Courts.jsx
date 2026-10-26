// A court card: its name and format, the court with this game (or the next one, dimmed), and Start / Finish.
import { useEffect, useRef } from 'react';
import { rallySeed, rallyUnit } from './rally';
import { motion, AnimatePresence } from 'framer-motion';
import { UserRound, UsersRound, Ellipsis, Lock, LockOpen, Shuffle, Trash2, Undo2 } from 'lucide-react';
import { cn } from 'cn';
import { scheduledOnCourt, postponeScheduled, cancelScheduled, getS, NEED, players, eligible, names, champion, fill, finish, shuffleCourt, lockSide, courtById, streakBoost } from './engine';
import { act, save, openModal, confirm } from './store';
import { cap, Dots, Seg } from './bits';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';

export function CourtCard({ c, next }) {
  const S = getS(), t = S.tournament, m = c.match, scheduled=scheduledOnCourt(c.id);
  const format = t ? t.format : c.format, singles = format === 'singles';
  const labelId = m?.tm ?? next?.match;
  const gameLabel = t && labelId != null ? t.matches[labelId].label : null;
  const teams = m ? [players(m.a), players(m.b)] : next ? [next.a, next.b] : null;
  const canSwap = !t && !m && next && !next.scheduled;
  const short = NEED[format] - eligible(format).length;
  const options = !t && !m ? next?.options || 0 : 0;

  const half = ps => (
    <div className={cn('relative z-10 flex min-w-0 flex-col items-center justify-center gap-2 p-2 transition-opacity')}>
      <AnimatePresence mode="popLayout" initial={false}>
        {ps ? ps.map(p => {
          const body = <><span className="max-w-full text-center [overflow-wrap:anywhere]">{p.name}</span><Dots skill={p.skill} boost={streakBoost(p.id)} className="text-white" /></>;
          const cls = 'flex max-w-full flex-col items-center gap-[3px] rounded-lg px-2 py-0.5 font-semibold leading-tight text-[22px]';
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
      className="@container grid min-w-0 gap-3.5 rounded-[14px] border border-border bg-card py-3.5"
      animate={{ borderColor: m ? 'var(--destructive)' : 'var(--border)' }}
      transition={{ duration: 0.4 }}
    >
      <div className="flex min-w-0 flex-wrap items-center gap-2 px-4">
        <h2 className="max-w-[45%] flex-none truncate text-xl font-bold">{c.name}</h2>
        <span className={cn("court-status", m ? "playing" : next ? "ready" : "waiting")}>{m ? "Playing" : S.ended!=null ? "Ended" : next?.scheduled ? "Scheduled · Locked" : next ? "Ready" : "Waiting"}</span><span className="flex-1" />
        {t ? <span className="text-[13px] font-semibold text-muted-foreground">{cap(format)}</span>
          : <Seg small label={`${c.name} format`} value={c.format} disabled={!!m||!!scheduled} className="max-w-[100px] min-w-0 flex-[0_1_100px]"
              options={['singles', 'doubles'].map(f => ({ value: f, label: <>{f === 'singles' ? <UserRound className="size-4" /> : <UsersRound className="size-4" />}<span className="sr-only">{cap(f)}</span></> }))}
              onChange={f => act(() => { const x = courtById(c.id); x.format = f; x.plan = null; })} />}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon-pill" className="-mr-2 text-ink" aria-label={`${c.name} options`}><Ellipsis /></Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {scheduled&&<><DropdownMenuItem onSelect={()=>act(()=>postponeScheduled(scheduled.id))}>Postpone 10 min</DropdownMenuItem><DropdownMenuItem variant="destructive" onSelect={()=>act(()=>cancelScheduled(scheduled.id))}>Cancel Request</DropdownMenuItem></>}
            {m && <DropdownMenuItem onSelect={() => act(() => { courtById(c.id).match = null; })}><Undo2 />Undo Start</DropdownMenuItem>}
            <DropdownMenuItem variant="destructive" disabled={!!m||!!scheduled} onSelect={() => act(() => { S.courts = S.courts.filter(x => x.id !== c.id); })}><Trash2 />Remove {c.name}</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <div className={cn('court relative grid aspect-[2.2/1] grid-cols-2 overflow-hidden rounded-[3px] bg-court text-white', format, m && 'playing')}>
        <i className="lines" /><i className="net" />
        {m && <Rally courtId={c.id} start={m.start} singles={singles} />}
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
          <Button size="pill" className="flex-none" disabled={!next || S.ended!=null} onClick={() => act(() => fill(c.id))}>Start {cap(format)}</Button>
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

/** Animate DOM transforms without re-running React or matchmaking every frame. */
function Rally({ courtId, start, singles }) {
  const shuttle = useRef(null), shadow = useRef(null);
  useEffect(() => {
    const motion = matchMedia('(prefers-reduced-motion: reduce)');
    let frame;
    const animate = () => {
      const el = shuttle.current, floor = shadow.current, court = el?.parentElement;
      if (!court || motion.matches) return;
      if (court.getClientRects().length) {
        const box = court.getBoundingClientRect(), seed = rallySeed(courtId);
        const sample = (k, ch) => rallyUnit(seed, k, ch);
        const spot = k => [box.width * (k % 2 ? 0.68 + sample(k, 0) * 0.12 : 0.2 + sample(k, 0) * 0.12),
          box.height * (singles ? 0.4 + sample(k, 1) * 0.2 : 0.3 + sample(k, 1) * 0.4)];
        const duration = 900 + sample(0, 2) * 650;
        const t = Math.max(0, Date.now() - start) / duration, k = Math.floor(t), f = t - k;
        const [ax, ay] = spot(k), [bx, by] = spot(k + 1), gx = ax + (bx - ax) * f, gy = ay + (by - ay) * f;
        const up = Math.sin(Math.PI * f), lift = box.height * (0.12 + sample(k, 3) * 0.12);
        const angle = Math.atan2(by - ay - lift * Math.PI * Math.cos(Math.PI * f), bx - ax) - Math.PI / 2;
        el.style.transform = `translate(${gx - 7}px,${gy - lift * up - 9}px) rotate(${angle}rad) scale(${1 + up * 0.4})`;
        floor.style.transform = `translate(${gx - 6}px,${gy - 2}px) scaleX(${1 - up / 3})`;
        floor.style.opacity = 0.25 - up * 0.1;
      }
      frame = requestAnimationFrame(animate);
    };
    const restart = () => { cancelAnimationFrame(frame); if (!motion.matches) frame = requestAnimationFrame(animate); };
    restart(); motion.addEventListener('change', restart);
    return () => { cancelAnimationFrame(frame); motion.removeEventListener('change', restart); };
  }, [courtId, start, singles]);
  return <><i ref={shadow} className="rally-shadow" /><svg ref={shuttle} className="rally" viewBox="0 0 24 30" aria-hidden="true">
    <path d="M8.6 21 .5 1.8Q12 4.8 23.5 1.8L15.4 21Z" fill="#e6e6e6" />
    <path d="M9.4 20.4 4.8 3M10.7 20.4 8.4 3.2M12 20.4V3.4M13.3 20.4 15.6 3.2M14.6 20.4 19.2 3M4.8 11.4Q12 13.2 19.2 11.4" stroke="#999" strokeOpacity=".7" strokeWidth=".8" fill="none" />
    <ellipse cx="12" cy="24.5" rx="5.3" ry="5.1" fill="#fff" stroke="#ccc" /></svg></>;
}
