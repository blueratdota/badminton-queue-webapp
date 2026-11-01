import { encodeTransfer, decodeTransfer } from './transfer';
// The app's state around the engine: which sessions exist and which is open, saving them in this browser,
// what sheet or confirmation is showing, and the theme. Components re-render through useStore().
import { useSyncExternalStore } from 'react';
import { refreshSchedule, normalizeEnd, LS_KEY, THEME_KEY, blankSession, nextSession, past, getS, setS, getSessions, setSessions, getCurrentId, setCurrentId } from './engine';

// ---------- re-rendering ----------
let version = 0;
const subs = new Set();
/** Redraw everything that reads the store (and the engine's session). */
export const bump = () => { version++; subs.forEach(f => f()); };
export const useStore = () => useSyncExternalStore(f => (subs.add(f), () => subs.delete(f)), () => version);

// ---------- what's showing ----------
export const ui = { modal: null, confirm: null };
/** Opening a sheet from Session Players brings you back to it when the new sheet closes. */
export function openModal(m) { ui.modal = ui.modal?.type === 'sessionPlayers' && m.type !== 'sessionPlayers' ? { ...m, back: ui.modal } : m; bump(); }
export const openEdit = p => openModal({ type: 'edit', id: p.id, skill: p.skill, name: p.name, pref: p.pref, paused: !!p.paused, present: !p.away });
export function closeModal() { ui.modal = ui.modal?.back || null; bump(); }
/** A confirmation: title, optional message, and buttons ({ label, danger, run }). Cancel is always offered. */
export function confirm(c) { ui.confirm = c; bump(); }
export function closeConfirm() { ui.confirm = null; bump(); }

// ---------- saving: everything in this browser's localStorage, as one JSON value ----------
let warned = false;
function persist() {
  try { localStorage.setItem(LS_KEY, JSON.stringify({ currentId: getCurrentId(), sessions: [...getSessions().values()] })); }
  catch (e) { // full or blocked (private browsing): say so once, so nobody loses a night without knowing
    console.warn('Save failed', e);
    if (!warned) { warned = true; confirm({ title: "Couldn't save on this device", message: 'Changes will be lost when this page closes. Export Data (⚙︎) keeps a copy.', noCancel: true, actions: [{ label: 'OK', strong: true, run() {} }] }); }
  }
}

/** Save the open session and redraw: what every change to it ends with. */
export function save() { refreshSchedule(); persist(); bump(); }
/** Run a change to the open session, then save it. */
export const act = fn => { fn(); save(); };
export function switchTo(id) { setCurrentId(id); setS(getSessions().get(id)); persist(); bump(); }
export function newSession(keepPlayers) { const x = nextSession(keepPlayers); getSessions().set(x.id, x); switchTo(x.id); }
export function deleteSession(id) {
  if (id === getS().id) {
    const latest = past()[0], next = latest || blankSession();
    if (!latest) getSessions().set(next.id, next);
    getSessions().delete(id); switchTo(next.id);
  } else { getSessions().delete(id); save(); }
}

/** A copyable snapshot in the same format used by iPad and the original web app. */
export function exportData() { return encodeTransfer([...getSessions().values()], getCurrentId()); }
/** Validate the complete code before changing saved sessions. */
export function importData(text) {
  const d = decodeTransfer(text), list = d.sessions;
  for (const x of list) {
    normalizeEnd(x);
    for (const id of getSessions().keys()) if(id.toLowerCase() === x.id.toLowerCase()) getSessions().delete(id);
    getSessions().set(x.id, x);
  }
  switchTo(getSessions().has(d.currentId) ? d.currentId : [...list].sort((a,b)=>b.date-a.date)[0].id);
  return list.length;
}

// ---------- start: load what this browser saved, or begin with a blank session ----------
function load() {
  try { const d = JSON.parse(localStorage.getItem(LS_KEY)); if (d?.sessions?.length) { setSessions(new Map(d.sessions.map(x => [x.id, x]))); setCurrentId(d.currentId); } } catch {}
  if (!getSessions().has(getCurrentId())) { const x = getSessions().size ? [...getSessions().values()].sort((a, b) => b.date - a.date)[0] : blankSession(); getSessions().set(x.id, x); setCurrentId(x.id); persist(); }
  for (const x of getSessions().values()) normalizeEnd(x);
  setS(getSessions().get(getCurrentId()));
  refreshSchedule(); persist();
}
load();
// Another tab of the app saved: show its data, so this tab doesn't overwrite it with an older copy.
addEventListener('storage', e => { if (e.key === LS_KEY) { setSessions(new Map()); setCurrentId(null); load(); bump(); } });

// ---------- theme: per viewer ----------
export const theme = () => { try { return localStorage.getItem(THEME_KEY) || 'system'; } catch { return 'system'; } };
const dark = matchMedia('(prefers-color-scheme: dark)');
const applyTheme = () => { const v = theme(); document.documentElement.classList.toggle('dark', v === 'dark' || (v === 'system' && dark.matches)); };
export function setTheme(v) { try { localStorage.setItem(THEME_KEY, v); } catch {} applyTheme(); bump(); }
dark.addEventListener('change', applyTheme);
applyTheme();

// Reservations expire and rejoin the ordinary rotation while the app is open.
setInterval(() => { const s=getS(), before=JSON.stringify([s.scheduled,s.scheduledActive]); refreshSchedule(); if (before!==JSON.stringify([s.scheduled,s.scheduledActive])) save(); }, 5000);
