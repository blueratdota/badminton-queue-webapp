// Small pieces shared by every screen: skill dots, inset-grouped list sections, the segmented control, confirmations.
import { cn } from 'cn';
import { level, r1, SKILL, streakDots, streakBoost } from './engine';
import { ui, closeConfirm } from './store';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group';
import { AlertDialog, AlertDialogContent, AlertDialogTitle, AlertDialogDescription } from '@/components/ui/alert-dialog';

export const cap = s => s[0].toUpperCase() + s.slice(1);
export const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
/** One list row's padding; rows inside a Section get separators between them. */
export const row = 'relative min-w-0 px-4 py-[11px]';
export const btnRow = cn(row, 'flex w-full min-h-11 items-center gap-2.5 text-left active:bg-accent disabled:text-faint');

export function Dots({ skill, boost = 0, className }) {
  const filled = level(skill), { parts, ring, fire } = streakDots(filled, boost);
  const dir = boost > 0 ? 'win' : 'loss';
  return <span role={boost ? 'img' : undefined} aria-label={boost ? `Temporary rating ${boost > 0 ? 'buff' : 'debuff'}` : undefined}
    aria-hidden={!boost || undefined} className={cn('rating-dots text-ink', boost && dir, className)}>
    {[1, 2, 3, 4, 5].map(i => <i key={i} className={cn(i <= filled && 'on', ring && i <= filled && 'ring', parts[i - 1] && `${dir} p${parts[i - 1] * 2}`)} />)}
    {fire && <span className="fire" aria-hidden="true">🔥</span>}
  </span>;
}

/** Dots over the rating number; a button when it does something. */
export function Rating({ p, onClick, label }) {
  const Comp = onClick ? 'button' : 'span';
  return (
    <Comp onClick={onClick} className="flex flex-none flex-col items-center gap-0.5" aria-label={label ?? `Skill ${SKILL[level(p.skill) - 1]}, rating ${r1(p.skill)}`}>
      <Dots skill={p.skill} boost={p.id ? streakBoost(p.id) : 0} /><small className="text-[11px] tabular-nums text-muted-foreground">{r1(p.skill)}</small>
    </Comp>
  );
}

/** An inset-grouped list section: optional header, rows on a rounded card, optional footer. */
export const Section = ({ head, foot, children, className }) => (
  <section className={cn('grid min-w-0 gap-[7px]', className)}>
    {head && <h2 className="px-4 text-[17px] font-semibold text-muted-foreground">{head}</h2>}
    <div className="min-w-0 divide-y overflow-hidden rounded-2xl bg-card">{children}</div>
    {foot && <p className="px-4 text-[13px] leading-snug text-muted-foreground">{foot}</p>}
  </section>
);

/** The iOS segmented control; always has one choice on. */
export const Seg = ({ value, onChange, options, small, label, disabled, className }) => (
  <ToggleGroup type="single" value={value} onValueChange={v => v && onChange(v)} aria-label={label} className={cn('seg', small && 'small', className)}>
    {options.map(o => <ToggleGroupItem key={o.value} value={o.value} disabled={disabled || o.disabled}>{o.label}</ToggleGroupItem>)}
  </ToggleGroup>
);

/** The confirmation showing (ui.confirm): stacked buttons as on iOS, Cancel last. */
export function Confirm() {
  const c = ui.confirm;
  const btn = 'min-h-11 w-full border-t px-3 py-3 text-[17px] text-ink active:bg-accent';
  return (
    <AlertDialog open={!!c} onOpenChange={o => !o && closeConfirm()}>
      <AlertDialogContent className="w-[min(300px,calc(100%-2rem))] max-w-none gap-0 overflow-hidden rounded-2xl border-0 bg-popover p-0 text-center sm:max-w-none">
        <AlertDialogTitle className="mx-4 mt-[18px] mb-1 text-center text-[17px] font-semibold">{c?.title}</AlertDialogTitle>
        <AlertDialogDescription className={cn('mx-4 mb-4 text-center text-[13px]', !c?.message && 'sr-only')}>{c?.message || c?.title}</AlertDialogDescription>
        {c?.actions.map(a => (
          <button key={a.label} className={cn(btn, a.danger && 'text-destructive', a.strong && 'font-semibold')} onClick={() => { closeConfirm(); a.run(); }}>{a.label}</button>
        ))}
        {!c?.noCancel && <button className={cn(btn, 'font-semibold')} onClick={closeConfirm}>Cancel</button>}
      </AlertDialogContent>
    </AlertDialog>
  );
}
