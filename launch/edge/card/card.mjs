// The picture a messenger shows for a shared firm link (og:image), 1200x630.
// Drawn on request from the database, so it always shows today's numbers. Design approved by the founder, 23 Nov 2026.
import ICONS from './signal-icons.mjs';

export const W = 1200, H = 630;
const INK = '#10201C', MUTE = '#586964', AMBER = '#F0861E';
// Same order and words as SIGNALS in js/company.js.
export const SIGNALS = [['up', 'Speeding up'], ['down', 'Slowing down'], ['top', 'Top 100'], ['chain', 'Top firms follow it'],
  ['lead', 'Leads rounds'], ['spec', 'Specialist'], ['fund', 'Fresh fund']];
const STATUS_DOT = { 'Active': '#2FA36B', 'Low activity': '#E0A526', 'Not active': '#9AA5A1', 'Not checked yet': '#C9D1CE' };
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const el = (type, style, children, extra) => ({ type, props: Object.assign({ style, children }, extra || {}) });
const num = (n) => Number(n || 0).toLocaleString('en-US');
export function day(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ''));
  return m ? `${MON[+m[2] - 1]} ${+m[3]}, ${m[1]}` : '';
}
// A long name gets a smaller size so it stays on two lines at most.
export function nameSize(name) {
  const n = String(name || '').length;
  return n <= 20 ? 88 : n <= 28 ? 72 : n <= 40 ? 58 : 46;
}

// d: { name, hq, status, last_deal, deals_year, deals_all, signals: [code], sectors: [{ name, color }] }
export function cardTree(d) {
  const signals = SIGNALS.filter(([k]) => (d.signals || []).includes(k)).slice(0, 3);
  const sectors = (d.sectors || []).slice(0, 3);
  const last = day(d.last_deal);
  const hasDeals = Number(d.deals_all) > 0;
  const label = { fontFamily: 'Geist Mono', fontSize: 18, letterSpacing: 1.1, textTransform: 'uppercase', color: MUTE };
  return el('div', { width: W, height: H, display: 'flex', backgroundColor: '#F3F5F4', padding: 36, fontFamily: 'Geist', color: INK }, [
    el('div', { flex: 1, display: 'flex', flexDirection: 'column', backgroundColor: '#fff', border: `2px solid ${INK}`, borderRadius: 28, padding: '44px 52px' }, [
      el('div', { display: 'flex', justifyContent: 'space-between', alignItems: 'center' }, [
        el('div', { display: 'flex', alignItems: 'center', fontSize: 34, fontWeight: 600, letterSpacing: -1.4 }, [
          el('div', { width: 42, height: 27, marginRight: 14, borderRadius: 99, border: `3px solid ${INK}`, backgroundImage: `linear-gradient(90deg, ${AMBER} 50%, #fff 50%)`, transform: 'rotate(35deg)' }),
          'regretamin']),
        el('div', Object.assign({}, label, { fontSize: 20 }), ['VC firm', d.hq ? ' · ' + d.hq : ''].join(''))]),
      el('div', { display: 'flex', marginTop: 60, fontSize: nameSize(d.name), fontWeight: 600, letterSpacing: -nameSize(d.name) * 0.045, lineHeight: 1.02 }, String(d.name || '')),
      el('div', { display: 'flex', alignItems: 'center', marginTop: 26, fontSize: 28 }, [
        el('div', { width: 14, height: 14, borderRadius: 7, marginRight: 10, backgroundColor: STATUS_DOT[d.status] || STATUS_DOT['Not checked yet'] }),
        el('div', { display: 'flex', fontWeight: 600 }, String(d.status || 'Not checked yet')),
        last ? el('div', { display: 'flex', marginLeft: 12, color: MUTE }, '· last deal ' + last) : null]),
      signals.length ? el('div', { display: 'flex', marginTop: 26 }, signals.map(([k, text]) =>
        el('div', { display: 'flex', alignItems: 'center', marginRight: 12, fontSize: 24, fontWeight: 600, border: `2px solid ${INK}`, borderRadius: 99, padding: '8px 18px' }, [
          el('img', { width: 26, height: 26, marginRight: 8 }, undefined, { src: ICONS[k], width: 26, height: 26 }), text]))) : null,
      el('div', { display: 'flex', alignItems: 'flex-end', marginTop: 'auto' }, [
        hasDeals ? el('div', { display: 'flex', flexDirection: 'column', marginRight: 56 }, [
          el('div', { display: 'flex', fontSize: 64, fontWeight: 600, letterSpacing: -2.6, lineHeight: 1 }, num(d.deals_year)),
          el('div', label, 'deals this year')]) : null,
        hasDeals ? el('div', { display: 'flex', flexDirection: 'column' }, [
          el('div', { display: 'flex', fontSize: 64, fontWeight: 600, letterSpacing: -2.6, lineHeight: 1 }, num(d.deals_all)),
          el('div', label, 'deals since 2021')]) : null,
        el('div', { display: 'flex', marginLeft: 'auto' }, sectors.map((s, i) =>
          el('div', { display: 'flex', marginLeft: i ? 10 : 0, fontSize: 22, fontWeight: 600, borderRadius: 10, padding: '8px 14px', backgroundColor: s.color || '#DADFDD' }, s.name)))])])]);
}
