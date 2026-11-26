// /badge/<slug>/<signal>-<look>.png: a badge a firm can put on its own website, deck or signature.
// Founder, 25 Nov 2026: the "capsule" approach. The badge is the Regretamin pill with the firm's logo in one half and the
// title in the other. Three looks: a round emblem on a dark ground, the same on a white ground, and the pill alone.
// Drawn when it is asked for, from the same database row as the firm share card, and only for a signal the firm has
// today. Kept for an hour. Nothing is stored.
// The renderer here cannot load fonts, so the words are drawn from letter outlines of the site's own Geist fonts
// (badge-glyphs.mjs, made by tools/badge/gen_glyphs.py).
import { Resvg, initResvg } from './lib.mjs';
import { SEMI, MONO } from './badge-glyphs.mjs';

// signal code (the firm page's own codes) -> the name, the short line that says what it is for, and the small drawing.
// A badge exists for every good signal; "Slowing down" has none. Names chosen by the founder (25 Nov). lines: the
// name as it stands in the round badge, each line with its letter size. icon: a drawing in a 24 x 24 box.
export const BADGES = {
  top: { title: 'The Magnificent 100', lines: [['Magnificent', 15], ['100', 28]], what: 'TOP 100 FIRMS', icon: 'M2.500 6.500l5 4.300L12 3.500l4.500 7.300 5-4.300-1.900 11H4.400zM4.800 19.300h14.400v2.200H4.800z' },
  lead: { title: 'Shot Caller', lines: [['Shot', 20], ['Caller', 20]], what: 'LEADS ROUNDS', icon: 'M2.500 9.200h4.300L15.500 4v16l-8.700-5.200H2.500zM6.200 16.200h3.300l1.200 5.300H7.400zM17.800 9.500h2v5h-2zM21 7.500h1.500v9H21z' },
  up: { title: 'Fast & Curious', lines: [['Fast &', 20], ['Curious', 20]], what: 'INVESTING FASTER', icon: 'M13.800 1.500L4.500 13.600h6.300L9.200 22.500l10.300-12.700h-6.600z' },
  chain: { title: 'Pathfinder', lines: [['Pathfinder', 18]], what: 'TOP FIRMS FOLLOW', icon: 'M12 2a10 10 0 110 20 10 10 0 010-20zm0 2.300a7.700 7.700 0 100 15.400 7.700 7.700 0 000-15.400zM16.400 7.600l-2.700 6.100-6.100 2.700 2.700-6.100z' },
  spec: { title: 'Laser Focus', lines: [['Laser', 20], ['Focus', 20]], what: 'ONE SECTOR FOCUS', icon: 'M12 5a7 7 0 110 14 7 7 0 010-14zm0 2.300a4.700 4.700 0 100 9.400 4.700 4.700 0 000-9.400zM12 10.200a1.800 1.800 0 110 3.600 1.800 1.800 0 010-3.600zM11 1h2v3h-2zM11 20h2v3h-2zM1 11h3v2H1zM20 11h3v2h-3z' },
  fund: { title: 'Hot & Fresh', lines: [['Hot &', 20], ['Fresh', 20]], what: 'NEW FUND RAISED', icon: 'M12.600 1.500c.700 3.900 5.600 6 5.600 11.400a6.200 6.200 0 01-12.400 0c0-2.200.900-4 2.100-5.300.300 1.800 1 2.900 2.100 3.300C9.800 7.800 10.700 4.100 12.600 1.500z' },
};
export const LOOKS = ['round-dark', 'round-light', 'pill'];
const INK = '#10201C', AMBER = '#F0861E';

// "top-round-dark.png" -> { signal: 'top', look: 'round-dark' }
export function badgeOf(file) {
  const m = /^(top|lead|up|chain|spec|fund)-(round-dark|round-light|pill)\.png$/.exec(String(file || ''));
  return m ? { signal: m[1], look: m[2] } : null;
}
export const slugOk = (s) => /^[a-z0-9][a-z0-9-]{0,119}$/.test(String(s || ''));
export const initials = (name) => String(name || '').replace(/[^A-Za-z0-9 ]/g, ' ').trim().split(/\s+/).slice(0, 2).map((w) => w[0] || '').join('').toUpperCase();

// ---- words as outlines ----
const n2 = (v) => +v.toFixed(2);
const widthOf = (font, text, size, gap = 0) => [...text].reduce((w, ch) => w + (font.adv[ch] || font.adv[' ']) * size / font.upm + gap, 0) - gap;
// A straight line of text. anchor: 'start' or 'middle'. y is the baseline.
function line(font, text, size, x, y, { gap = 0, anchor = 'start', fill = INK } = {}) {
  const k = size / font.upm; let cx = anchor === 'middle' ? x - widthOf(font, text, size, gap) / 2 : x, out = '';
  for (const ch of text) {
    const d = font.d[ch];
    if (d) out += `<path transform="translate(${n2(cx)} ${n2(y)}) scale(${n2(k * 1000) / 1000} ${-n2(k * 1000) / 1000})" d="${d}"/>`;
    cx += (font.adv[ch] || font.adv[' ']) * k + gap;
  }
  return `<g fill="${fill}">${out}</g>`;
}
// Text running once around a circle, clockwise from the left, letters upright at the top.
function ring(font, text, size, c, R, fill) {
  const k = size / font.upm, chars = [...text], per = (2 * Math.PI * R) / chars.length; let out = '';
  chars.forEach((ch, i) => {
    const d = font.d[ch]; if (!d) return;
    const w = (font.adv[ch] || 0) * k, a = Math.PI + (i * per + (per - w) / 2) / R;  // where the letter's left edge sits
    const x = c + R * Math.cos(a), y = c + R * Math.sin(a), rot = (a * 180) / Math.PI + 90;
    out += `<path transform="translate(${n2(x)} ${n2(y)}) rotate(${n2(rot)}) scale(${n2(k * 1000) / 1000} ${-n2(k * 1000) / 1000})" d="${d}"/>`;
  });
  return `<g fill="${fill}">${out}</g>`;
}
// The firm's mark for the white half: its logo when it has one, otherwise its initials on a grey tile.
function mark(x, y, s, logo, ini, id) {
  const r = s * 0.22;
  if (logo) return `<clipPath id="${id}"><rect x="${x}" y="${y}" width="${s}" height="${s}" rx="${r}"/></clipPath><rect x="${x}" y="${y}" width="${s}" height="${s}" rx="${r}" fill="#fff"/><image href="${logo}" x="${x}" y="${y}" width="${s}" height="${s}" clip-path="url(#${id})" preserveAspectRatio="xMidYMid meet"/>`;
  return `<rect x="${x}" y="${y}" width="${s}" height="${s}" rx="${r}" fill="#E2E7E5"/>${line(SEMI, ini, s * 0.4, x + s / 2, y + s / 2 + s * 0.14, { anchor: 'middle', fill: '#586964' })}`;
}
const drawing = (d, x, y, s, fill) => `<path transform="translate(${n2(x)} ${n2(y)}) scale(${n2(s / 24 * 1000) / 1000})" d="${d}" fill="${fill}" fill-rule="evenodd"/>`;
// The capsule: a white half with the firm's mark, an amber half with the title (one or two lines) and, on the pill,
// one small line under it and the badge's drawing at the far end.
function capsule(x, y, w, h, left, edge, edgeW, { logo, ini, id, title, lines, size, small, icon }) {
  const r = h / 2, s = h * 0.62, tx = x + left + (w - left - r * 0.25) / 2;
  const room = w - left - r * 0.25 - 12;  // a line that is too long gets smaller letters, never a longer pill
  const rows = small ? [] : lines.map(([t, sz]) => { const wd = widthOf(SEMI, t, sz, -sz * 0.03); return [t, wd > room ? sz * room / wd : sz]; });
  let top = y + h / 2 - rows.reduce((a, [, sz]) => a + sz * 1.04, 0) / 2;
  const words = small
    ? line(SEMI, title, size, x + left + 14, y + h / 2 - 1, { gap: -size * 0.02 }) + line(MONO, small, 8.5, x + left + 14, y + h / 2 + 14, { gap: 1.3 }) + (icon ? drawing(icon, x + w - 20 - 22, y + (h - 22) / 2, 22, INK) : '')
    : rows.map(([t, sz]) => { const out = line(SEMI, t, sz, tx, top + sz * 0.88, { gap: -sz * 0.03, anchor: 'middle' }); top += sz * 1.04; return out; }).join('');
  return `<clipPath id="${id}c"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}"/></clipPath>
<g clip-path="url(#${id}c)"><rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${AMBER}"/><rect x="${x}" y="${y}" width="${left}" height="${h}" fill="#fff"/><rect x="${x + left - edgeW / 2}" y="${y}" width="${edgeW}" height="${h}" fill="${edge}"/></g>
<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="none" stroke="${edge}" stroke-width="${edgeW}"/>
${mark(x + (left - s) / 2 + edgeW / 2, y + (h - s) / 2, s, logo, ini, id + 'm')}${words}`;
}

// One badge as an SVG drawing. look: 'round-dark' | 'round-light' | 'pill'. logo: a data: address of the picture, or null.
export function badgeSvg({ signal, look, year, logo = null, name = '' }) {
  const b = BADGES[signal]; if (!b || !LOOKS.includes(look)) return null;
  const ini = initials(name) || '?';
  if (look === 'pill') {
    const size = 19, W = Math.ceil(74 + 14 + Math.max(widthOf(SEMI, b.title, size, -size * 0.02), widthOf(MONO, `REGRETAMIN ${year}`, 8.5, 1.3)) + 16 + 22 + 22) + 4, H = 60;
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${capsule(2, 2, W - 4, H - 4, 74, INK, 2, { logo, ini, id: 'p', title: b.title, lines: b.lines, size, small: `REGRETAMIN ${year}`, icon: b.icon })}</svg>`;
  }
  const dark = look === 'round-dark', S = 260, c = S / 2, cw = 172;  // the pill must stay inside the ring of words
  const ink = dark ? '#fff' : INK;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
<circle cx="${c}" cy="${c}" r="${dark ? 128 : 126.5}" fill="${dark ? INK : '#fff'}"${dark ? '' : ` stroke="${INK}" stroke-width="3"`}/>
${ring(MONO, `REGRETAMIN · ${year} · `.repeat(4), 10.5, c, 101, ink)}
${drawing(b.icon, c - 12, 47, 24, dark ? AMBER : INK)}
<g transform="rotate(-12 ${c} ${c})">${capsule(c - cw / 2, c - 38, cw, 72, 66, ink, 3, { logo, ini, id: 'r', lines: b.lines })}
${line(MONO, b.what, 9.5, c, c + 58, { gap: 1.4, anchor: 'middle', fill: dark ? AMBER : INK })}</g></svg>`;
}

let ready = null;
function engine(wasm) {
  if (!ready) ready = initResvg(wasm.resvg).catch((e) => { if (!/already/i.test(String(e && e.message))) { ready = null; throw e; } });
  return ready;
}
// SVG -> PNG at twice the drawn size, so it stays sharp on a phone.
export async function drawBadge(svg, { wasm }) {
  await engine(wasm);
  const w = Number(/width="(\d+)"/.exec(svg)[1]);
  return new Resvg(svg, { fitTo: { mode: 'width', value: w * 2 } }).render().asPng();
}
function b64(buf) { let s = ''; const u = new Uint8Array(buf); for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000)); return btoa(s); }

export async function badgeResponse({ request, env, assets, slug, file, wasm, fetchImpl = fetch, now = new Date() }) {
  const url = new URL(request.url), want = badgeOf(file);
  const no = () => new Response('Not found', { status: 404, headers: { 'cache-control': 'public, max-age=300' } });
  if (!want || !slugOk(slug)) return no();
  try {
    const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/v2_firm_share_card`, {
      method: 'POST',
      headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, 'content-type': 'application/json' },
      body: JSON.stringify({ p_slug: slug }),
    });
    if (!r.ok) return no();
    const row = await r.json();
    // only a signal the firm has today
    if (!row || !row.name || !Array.isArray(row.signals) || !row.signals.includes(want.signal)) return no();
    let logo = null;
    const lr = await assets.fetch(new URL(`/assets/logos/f-${slug}.png`, url.origin));
    if (lr.ok && /image\/png/.test(lr.headers.get('content-type') || '')) logo = 'data:image/png;base64,' + b64(await lr.arrayBuffer());
    const svg = badgeSvg({ signal: want.signal, look: want.look, year: now.getUTCFullYear(), logo, name: row.name });
    const png = await drawBadge(svg, { wasm });
    return new Response(png, { headers: { 'content-type': 'image/png', 'cache-control': 'public, max-age=3600', 'access-control-allow-origin': '*' } });
  } catch (e) {
    return no();
  }
}
