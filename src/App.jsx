// The main screen: toolbar, the courts, and the queue beside them (landscape iPad), below them (portrait iPad),
// or on their own tab (phones).
import { useEffect, useMemo, useRef, useState } from 'react';
import { CalendarDays, History, Link2, Settings, SquarePlus, Trophy, Upload, Download, UserPlus, Users, UsersRound } from 'lucide-react';
import { cn } from 'cn';
import { getS, upNext, nextPairing, withMatching, court, fill, queue } from './engine';
import { useStore, bump, act, openModal, confirm, exportData, importData, theme, setTheme } from './store';
import { CourtCard } from './Courts';
import { SidePanel } from './Queue';
import { Sheets } from './Sheets';
import { Confirm, Seg } from './bits';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';

export default function App() {
  const version = useStore();
  const [tab, setTab] = useState('courts');
  useEffect(() => { const t = setInterval(bump, 30000); return () => clearInterval(t); }, []); // wait times and the 20-minute rule move with the clock
  const S = getS();
  // One run of the matching per change, shared by every court card and Up Next (the preview is what Start begins).
  const next = useMemo(() => withMatching(() => ({ up: upNext(), byCourt: new Map(S.courts.map(c => [c.id, nextPairing(c)])) })), [version, S]);

  const canFill = S.courts.some(c => next.byCourt.get(c.id));
  const fillAll = () => act(() => S.courts.forEach(c => fill(c.id)));
  const fillButton = cls => <Button size="pill" className={cn('px-5 text-[17px]', cls)} disabled={!canFill} onClick={fillAll}>Fill Open Courts</Button>;

  return (
    <div className="flex min-h-dvh flex-col pt-[env(safe-area-inset-top)] pr-[env(safe-area-inset-right)] pl-[env(safe-area-inset-left)] lg:h-dvh">
      <header className="flex flex-wrap items-center gap-x-3.5 gap-y-2.5 px-4 py-2.5">
        <h1 className="min-w-0 flex-[1_1_220px] truncate text-[17px] font-semibold max-sm:basis-full">
          Shuttle Queue · {new Date(S.date).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}
        </h1>
        <div className="flex flex-wrap items-center gap-2.5 max-sm:w-full">
          <Toolbar />
          {fillButton('max-sm:hidden')}
        </div>
      </header>

      <main className="min-h-0 flex-1 lg:grid lg:grid-cols-[minmax(0,1fr)_340px]">
        <section aria-label="Courts" className={cn('grid content-start gap-3 px-4 pt-1 pb-6 sm:grid-cols-2 lg:grid-cols-[repeat(auto-fill,minmax(340px,1fr))] lg:overflow-auto', tab !== 'courts' && 'max-sm:hidden')}>
          {S.courts.map(c => <CourtCard key={c.id} c={c} next={next.byCourt.get(c.id)} />)}
          {!S.courts.length && <p className="flex items-center gap-1.5 px-1 py-6 text-muted-foreground">No courts yet. Add one with <SquarePlus className="size-5" /> in the toolbar.</p>}
        </section>
        <aside aria-label="Queue" className={cn('min-w-0 px-4 pt-5 pb-6 lg:overflow-auto lg:border-l lg:pt-1', tab !== 'queue' && 'max-sm:hidden')}>
          <SidePanel up={next.up} />
        </aside>
      </main>

      {/* Phones: switch between courts and queue; Fill Open Courts stays in reach. */}
      <nav className="sticky bottom-0 z-10 flex items-center gap-2 border-t bg-glass px-4 pt-2 pb-[max(8px,env(safe-area-inset-bottom))] backdrop-blur-xl sm:hidden">
        <Seg label="Show" value={tab} onChange={setTab} className="flex-1"
          options={[{ value: 'courts', label: 'Courts' }, { value: 'queue', label: `Queue · ${queue().length}` }]} />
        {fillButton('px-4 text-[15px]')}
      </nav>

      <Sheets />
      <Confirm />
    </div>
  );
}

function Toolbar() {
  const S = getS(), file = useRef(null);
  const tb = 'h-9 w-11 rounded-full text-foreground [&_svg:not([class*=size-])]:size-[22px]';
  const addCourt = () => act(() => { const n = Math.max(0, ...S.courts.map(c => +c.name.replace(/\D/g, '') || 0)) + 1; S.courts.push(court('Court ' + n, 'doubles')); });
  const onFile = async e => {
    const f = e.target.files[0]; e.target.value = '';
    if (!f) return;
    try { const n = importData(await f.text()); confirm({ title: `Imported ${n} session${n === 1 ? '' : 's'}`, noCancel: true, actions: [{ label: 'OK', strong: true, run() {} }] }); }
    catch (err) { confirm({ title: "Couldn't import that file", message: err.message, noCancel: true, actions: [{ label: 'OK', strong: true, run() {} }] }); }
  };
  return (
    <div role="toolbar" aria-label="Session tools" className="flex gap-0.5 rounded-full bg-glass px-1.5 py-1 shadow-[0_1px_4px_rgba(0,0,0,.14)] ring-1 ring-black/5 backdrop-blur-xl max-sm:flex-1 max-sm:justify-between dark:ring-white/10">
      <DropdownMenu>
        <DropdownMenuTrigger asChild><Button variant="ghost" className={tb} aria-label="Options" title="Options"><Settings /></Button></DropdownMenuTrigger>
        <DropdownMenuContent align="start" className="min-w-[230px]">
          <DropdownMenuLabel>Appearance</DropdownMenuLabel>
          <DropdownMenuRadioGroup value={theme()} onValueChange={setTheme}>
            {['system', 'light', 'dark'].map(v => <DropdownMenuRadioItem key={v} value={v}>{v[0].toUpperCase() + v.slice(1)}</DropdownMenuRadioItem>)}
          </DropdownMenuRadioGroup>
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => openModal({ type: 'sessionPlayers' })}><UsersRound />Session Players</DropdownMenuItem>
          <DropdownMenuItem onSelect={() => openModal({ type: 'allPlayers' })}><Users />All Players</DropdownMenuItem>
          <DropdownMenuItem onSelect={() => openModal({ type: 'pairing' })}><Link2 />Locked Teammates</DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={exportData}><Download />Export Data</DropdownMenuItem>
          <DropdownMenuItem onSelect={() => file.current.click()}><Upload />Import Data</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <input ref={file} type="file" accept="application/json,.json" hidden onChange={onFile} />
      <DropdownMenu>
        <DropdownMenuTrigger asChild><Button variant="ghost" className={tb} disabled={!!S.tournament} aria-label="Add Player" title="Add Player"><UserPlus /></Button></DropdownMenuTrigger>
        <DropdownMenuContent align="start">
          <DropdownMenuItem onSelect={() => openModal({ type: 'addPlayer' })}><UserPlus />New Player</DropdownMenuItem>
          <DropdownMenuItem onSelect={() => openModal({ type: 'returning' })}><History />From Earlier Sessions</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <Button variant="ghost" className={tb} aria-label="Sessions" title="Sessions" onClick={() => openModal({ type: 'sessions' })}><CalendarDays /></Button>
      <Button variant="ghost" className={tb} aria-label="Standings" title="Standings" onClick={() => openModal({ type: 'results', tab: 'standings' })}><Trophy /></Button>
      <Button variant="ghost" className={tb} aria-label="Add Court" title="Add Court" onClick={addCourt}><SquarePlus /></Button>
    </div>
  );
}
