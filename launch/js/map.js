// The map page (/map/). Reads four read-only database functions: v2_map_summary, v2_map_firms, v2_map_updates
// and, for the 'Hot right now' view, v2_map_hot (docs/map_hot_function.sql).
// (docs/map_functions.sql). Rules it follows are in the project doc claude/plans/main-map.md.
// No data is invented here: if the functions are missing, the page says the map is not available.
// The third view, 'Founders', is drawn by js/founders.js; this file only switches to it and passes on the zoom.
(function () {
  const el = document.getElementById('vm');
  if (!el) return;
  const C = window.REGRET || {}, ROOT = window.REGRET_ROOT || '';
  const MAPV = C.mapv ? '?v=' + C.mapv : '';  // map files keep their names; this changes when they do, so no browser shows an old one
  const sb = C.url && C.key && window.supabase ? window.supabase.createClient(C.url, C.key) : null;
  const qs = new URLSearchParams(location.search);
  // Local preview only: ?fixture=<saved v2_map_summary answer>&fx_firms=<saved v2_map_firms>&fx_updates=<saved v2_map_updates>.
  // Ignored on any real host.
  const LOCAL = /^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname);
  const FIXTURE = LOCAL ? qs.get('fixture') : null;
  const FX_FIRMS = FIXTURE && qs.get('fx_firms'), FX_UPDATES = FIXTURE && qs.get('fx_updates'), FX_HOT = FIXTURE && qs.get('fx_hot'), FX_DETAIL = FIXTURE && qs.get('fx_detail'), FX_PLACE = FIXTURE && qs.get('fx_place');

  // Layout (founder's choice): a grey rail on the left holds two cards, controls and news; nothing covers the map.
  // ?layout=float brings back the first layout (cards floating over the map) for comparison.
  const COL = qs.get('layout') !== 'float';
  if (COL) el.classList.add('vm-col');

  const INK = '#10201C';
  const COLORS = { 'Enterprise software': '#A9C4E8', 'Health': '#F2A7A0', 'Fintech': '#F3D98B', 'Hardware & Robotics': '#9FD4C3', 'Consumer': '#D9B5E0', 'Climate & Energy': '#BFDCA0', 'Bio': '#C59AC7', 'AI agents': '#8E9BE0', 'AI models': '#C4CCF2', 'Security': '#A8BDB5', 'Crypto': '#F7E6B5', 'Media & Gaming': '#F5C19A', 'Food & Agriculture': '#D5E0A3', 'Defense': '#B5B5BD', 'Space': '#9AA5D1', 'Mobility': '#9CC9D9', 'Education': '#EFC4D0', 'Developer tools': '#B9E0E6', 'Real estate': '#E6C9B0', 'Govtech': '#C2D6C8', 'Other': '#DADFDD' };
  const REST = '#F1F3F2';
  const SECTORS = Object.keys(COLORS).filter((s) => s !== 'Other').sort();
  const STAGES = ['Pre-seed', 'Seed', 'Series A', 'Series B', 'Series C+', 'Growth'];
  const LEVELS = [['world', 'World'], ['us', 'United States'], ['eu', 'Europe']];
  const ZOOM = { 'US West': 'us', 'US Central': 'us', 'US East': 'us', 'Europe': 'eu' };
  const HOT_MIN = 10;  // 'Hot right now': a place or a sector needs this many deals across both periods before it gets a colour
  const HOT_FAINT = 10;  // ...and a rise or fall of fewer deals than this is drawn in the lighter green or red
  const RING_DEALS = 150, RING_FIRMS = 5, DOT_DEALS = 30;  // zoomed views only; the world view always draws rings
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  const now = new Date();
  const NQ = (now.getFullYear() - 2021) * 4 + Math.floor(now.getMonth() / 3) + 1;  // quarters from 2021 Q1 to this one
  const S = { view: 'flow', days: 90, level: 'world', q0: 0, q1: NQ - 1, stages: [], sectors: [], who: 'all', unit: 'pct', pinned: null, list: null, data: null, geo: null, updates: [], playing: null };
  // "Which firms" in the Hot right now view.
  const KEEP = 'regretamin.map.view';
  const SHARE_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 15V3M8 7l4-4 4 4M5 12v8h14v-8"/></svg>';
  const TICK_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.500 4.500L19 7.500"/></svg>';
  window.REGRET_SHARE_ICON = SHARE_ICON;
  let BACK = null;  // the place (and firms list) that was open when the map was left; reopened once after the first load
  const WHO = [['all', 'All firms'], ['top', 'Top firms'], ['focused', 'Focused funds'], ['first', 'New investors'], ['fresh', 'Fresh funds']];
  // 'new' was this choice's old name ("New entrants": first deal in the picked sectors). Old links and saved views open as "New investors".
  const whoKey = (k) => (k === 'new' ? 'first' : k);
  // What each choice means. While one is picked, this takes the place of the colour key in the map's corner (founder, 23 Nov:
  // "should replace the legend on the right, not appear in a new spot"). "All firms" shows the colour key.
  // "Top firms" in the US is an outside ranking, everywhere else our own (rounds led), so its line follows the zoom.
  const whoNote = () => ({
    top: S.level === 'us' ? 'The 100 top-ranked US firms of 2026' : 'Led the most rounds in the last 3 years',
    focused: 'Most of their deals are in one sector',
    first: 'Made their first deal in this period',
    fresh: 'Raised a new fund in the last 12 months',
  })[who()] || '';
  const who = () => (S.view === 'hot' ? S.who : 'all');
  // A link can carry the view in its address (view, days, zoom, sectors, stages, firms). The page never rewrites its own address.
  (() => {
    const list = (k, ok) => (qs.get(k) || '').split('|').filter((v) => ok.includes(v)), num = (k) => (/^\d+$/.test(qs.get(k) || '') ? +qs.get(k) : null);
    if (qs.get('view') === 'hot' || qs.get('view') === 'founders') S.view = qs.get('view');
    if (qs.get('view') === 'pathfinders') S.view = 'path';
    if ([90, 180, 365].includes(num('days'))) S.days = num('days');
    if (['us', 'eu'].includes(qs.get('zoom'))) S.level = qs.get('zoom');
    S.sectors = list('sectors', SECTORS); S.stages = list('stages', STAGES);
    if (WHO.some(([k]) => k === whoKey(qs.get('firms')))) S.who = whoKey(qs.get('firms'));
    const a = num('from'), b = num('to'); if (a !== null && b !== null && a <= b && b < NQ) { S.q0 = a; S.q1 = b; }
    if (qs.get('unit') === 'num') S.unit = 'num';
    if (qs.get('place')) BACK = { p: qs.get('place'), step: null, sector: null };  // a shared link with a place pressed: it opens once the map has loaded
    // No view in the address: come back to the map as it was left in this tab (after opening a firm and closing it, say).
    if (['view', 'days', 'zoom', 'sectors', 'stages', 'firms', 'from', 'to', 'unit', 'place', 'fk', 'fm'].some((k) => qs.has(k))) return;
    try {
      const m = JSON.parse(sessionStorage.getItem(KEEP) || 'null');
      if (!m) return;
      if (m.view === 'hot' || m.view === 'flow' || m.view === 'founders' || m.view === 'path') S.view = m.view;
      if ([90, 180, 365].includes(m.days)) S.days = m.days;
      if (['world', 'us', 'eu'].includes(m.level)) S.level = m.level;
      if (Array.isArray(m.sectors)) S.sectors = m.sectors.filter((v) => SECTORS.includes(v));
      if (Array.isArray(m.stages)) S.stages = m.stages.filter((v) => STAGES.includes(v));
      if (WHO.some(([k]) => k === whoKey(m.who))) S.who = whoKey(m.who);
      if (m.unit === 'pct' || m.unit === 'num') S.unit = m.unit;
      if (Number.isInteger(m.q0) && Number.isInteger(m.q1) && m.q0 >= 0 && m.q0 <= m.q1 && m.q1 < NQ) { S.q0 = m.q0; S.q1 = m.q1; }
      if (m.open && m.open.p != null) BACK = m.open;
    } catch (e) { /* no storage: start from the default view */ }
  })();
  function remember() {
    try { sessionStorage.setItem(KEEP, JSON.stringify({ view: S.view, days: S.days, level: S.level, sectors: S.sectors, stages: S.stages, who: S.who, unit: S.unit, q0: S.q0, q1: S.q1, open: BACK || (S.list ? { p: S.list.place.p, step: S.list.step || null, sector: S.list.sector || null } : null) })); } catch (e) { /* private mode */ }
  }
  window.addEventListener('pagehide', remember);
  // Share link (founder, 25 Nov: "just press on it, share link, that's it"): one button above + and -. It copies a link
  // that opens the map as it is set up now: the view, World / US / Europe, sectors, stages, the timeline, % or #, a
  // pressed place and, in Founders, Places / Universities / Companies and Map / Blocks. On a phone it opens the
  // phone's own share sheet. The page still never rewrites its own address; the link is built when the button is pressed.
  function shareUrl() {
    const q = ['view=' + (S.view === 'path' ? 'pathfinders' : S.view)], F = window.REGRET_FOUNDERS, f = S.view === 'founders' && F && F.state ? F.state() : null, enc = (a) => a.map(encodeURIComponent).join('%7C');
    if (S.view === 'hot') { q.push('days=' + S.days); if (S.who !== 'all') q.push('firms=' + S.who); }
    if (S.level !== 'world') q.push('zoom=' + S.level);
    if (S.view !== 'founders') { if (S.sectors.length) q.push('sectors=' + enc(S.sectors)); if (S.stages.length) q.push('stages=' + enc(S.stages)); }
    if (S.view !== 'hot' && (S.q0 !== 0 || S.q1 !== NQ - 1)) q.push('from=' + S.q0, 'to=' + S.q1);
    if (S.view === 'flow' && S.unit === 'num') q.push('unit=num');
    if (S.view !== 'founders' && S.list && S.list.place) q.push('place=' + encodeURIComponent(S.list.place.p));
    if (f) { if (f.kind === 'unis' || f.kind === 'cos') q.push('fk=' + f.kind); if (f.mode === 'blocks') q.push('fm=blocks'); }
    return location.origin + location.pathname + '?' + q.join('&');
  }
  function share(btn) {
    const url = shareUrl();
    const done = () => { if (!btn) return; btn.innerHTML = TICK_ICON; clearTimeout(btn._t); btn._t = setTimeout(() => { btn.innerHTML = SHARE_ICON; }, 1600); };
    const old = () => { try { const t = document.createElement('textarea'); t.value = url; t.style.cssText = 'position:fixed;opacity:0'; document.body.appendChild(t); t.select(); document.execCommand('copy'); t.remove(); done(); } catch (e) { /* nothing to copy with */ } };
    if (navigator.share && window.matchMedia && matchMedia('(pointer:coarse)').matches) { navigator.share({ url, title: document.title }).catch(() => {}); return; }
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(done, old); else old();
  }
  window.REGRET_SHARE = share; window.REGRET_SHARE_URL = shareUrl;
  const $ = (s, r) => (r || el).querySelector(s);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const num = (n) => Number(n || 0).toLocaleString('en-US');
  const iso = (d) => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  const qStart = (q) => new Date(2021 + Math.floor(q / 4), (q % 4) * 3, 1);
  const qEnd = (q) => { const d = new Date(2021 + Math.floor(q / 4), (q % 4) * 3 + 3, 0); return d > now ? now : d; };
  const args = () => ({ p_from: iso(qStart(S.q0)), p_to: iso(qEnd(S.q1)), p_stages: S.stages.length ? S.stages : null, p_sectors: S.sectors.length ? S.sectors : null });

  // ---------- data
  const cache = new Map();
  async function summary() {
    if (S.view === 'path') {  // Pathfinders: one answer holds the places, totals and lists of all three zooms
      const a = Object.assign({ p_max_deals: null }, args()), key = 'path' + JSON.stringify(a);  // every firm that is not on the Top 100 list (founder, 25 Nov: no size limit)
      if (cache.has(key)) return cache.get(key);
      let out = null;
      if (sb && !FIXTURE) { const { data, error } = await sb.rpc('v2_map_pathfinders', a); if (!error) out = data; }
      if (out) cache.set(key, out);
      return out;
    }
    const hot = S.view === 'hot';
    const a = hot ? { p_days: S.days, p_stages: S.stages.length ? S.stages : null, p_sectors: S.sectors.length ? S.sectors : null } : args();
    if (who() !== 'all') a.p_firms = who();  // sent only when a filter is on, so the plain view keeps using the first version of the function
    const key = S.view + JSON.stringify(a);
    if (cache.has(key)) return cache.get(key);
    let out = null;
    if (FIXTURE) out = hot ? (FX_HOT ? await fetch(FX_HOT).then((r) => r.json()) : null) : await fetch(FIXTURE).then((r) => r.json());
    else if (sb) {
      // The opening view (nothing chosen yet) is read from an answer the database prepared ahead of time; it is refreshed
      // every 15 minutes. Anything else, or a missing answer, is counted live as before.
      const plain = who() === 'all' && !S.stages.length && !S.sectors.length && (hot ? S.days === 90 : S.q0 === 0 && S.q1 === NQ - 1);
      if (plain) { const r = await sb.rpc('v2_map_cached', { p_key: hot ? 'hot' : 'summary' }); if (!r.error && r.data) out = r.data; }
      if (!out) { const { data, error } = await sb.rpc(hot ? 'v2_map_hot' : 'v2_map_summary', a); if (!error) out = data; }
    }
    if (out) cache.set(key, out);
    return out;
  }
  async function firms(place, sector) {
    if (FX_FIRMS) return fetch(FX_FIRMS).then((r) => r.json());
    if (FIXTURE || !sb) return null;
    // in the 'Hot right now' view the list covers the same recent period the map is showing
    const win = S.view === 'hot' ? { p_from: iso(new Date(now.getFullYear(), now.getMonth(), now.getDate() - S.days + 1)), p_to: iso(now), p_stages: S.stages.length ? S.stages : null, p_sectors: sector ? [sector] : S.sectors.length ? S.sectors : null } : Object.assign(args(), sector ? { p_sectors: [sector] } : {});
    // The gated answer: the same firms, but only the first 5 (3 for Fresh funds) until the account has unlocked (founder, 25 Nov).
    await sb.auth.getSession();
    const { data, error } = await sb.rpc('v2_map_firms_gated', Object.assign({ p_level: S.level, p_place: place.p }, win, who() !== 'all' ? { p_firms: who() } : {}));
    return error ? null : data;
  }
  // Money flow: every sector of one clicked place for the stretch of time the timeline shows: deals and firms.
  const secCache = new Map();
  async function placeSectors(place) {
    if (FX_PLACE) return fetch(FX_PLACE).then((r) => r.json());
    if (FIXTURE || !sb) return null;
    const a = Object.assign({ p_level: S.level, p_place: place.p }, args()), key = JSON.stringify(a);
    if (secCache.has(key)) return secCache.get(key);
    const { data, error } = await sb.rpc('v2_map_place_sectors', a);
    if (error) return null;
    secCache.set(key, data); return data;
  }
  // Pathfinders, one pressed place: its most followed firms.
  async function pathPlace(place) {
    if (FIXTURE || !sb) return null;
    const a = Object.assign({ p_level: S.level, p_place: place.p, p_max_deals: null }, args()), key = 'path' + JSON.stringify(a);
    if (secCache.has(key)) return secCache.get(key);
    const { data, error } = await sb.rpc('v2_map_pathfinders', a);
    if (error) return null;
    secCache.set(key, data); return data;
  }
  // Every sector of the zoom level (place null) or of one clicked place: deals now and before, firms, and a line of the last two years.
  const detCache = new Map();
  async function detail(place) {
    if (FX_DETAIL) return fetch(FX_DETAIL).then((r) => r.json());
    if (FIXTURE || !sb) return null;
    const a = { p_firms: who(), p_level: S.level, p_place: place ? place.p : null, p_days: S.days, p_stages: S.stages.length ? S.stages : null, p_sectors: S.sectors.length ? S.sectors : null }, key = JSON.stringify(a);
    if (detCache.has(key)) return detCache.get(key);
    const { data, error } = await sb.rpc('v2_map_hot_detail', a);
    if (error) return null;
    detCache.set(key, data); return data;
  }
  // "Latest updates" follows what the map shows (founder, 24 Nov): United States or Europe when one of them is open,
  // and the sector and stage filters. The timeline does not move it: it is always the newest rounds.
  const updKey = () => [S.level === 'world' ? '' : S.level, S.sectors.join('|'), S.stages.join('|')].join('~');
  let updAsked = null;
  async function loadUpdates() {
    const key = updKey(), n = COL ? 6 : 3;
    if (key === updAsked) return;
    updAsked = key;
    const show = (d) => { if (key !== updAsked || !Array.isArray(d)) return false; S.updates = d.slice(0, n); S.updKey = key; drawSide(); draw(); return true; };
    if (FX_UPDATES) { show(await fetch(FX_UPDATES).then((r) => r.json())); return; }
    if (FIXTURE || !sb) return;
    drawSide();  // the old list fades while the new one is on its way
    // The opening view has a ready-made answer, shown at once; the live answer that follows adds the amounts.
    if (key === '~~') { const c = await sb.rpc('v2_map_cached', { p_key: 'updates' }); if (!c.error) show(c.data); }
    const r = await sb.rpc('v2_map_updates_for', { p_level: S.level === 'world' ? null : S.level, p_sectors: S.sectors.length ? S.sectors : null, p_stages: S.stages.length ? S.stages : null, p_limit: n });
    if (!r.error && show(r.data)) return;
    if (key === '~~' && S.updKey !== key) { const o = await sb.rpc('v2_map_updates', { p_limit: n }); if (!o.error) show(o.data); }
  }
  // A round's amount as it is written in news: $90M, $1.75B, €26M, ~$5M when the source gave it roughly.
  const CUR = { USD: '$', EUR: '€', GBP: '£', JPY: '¥', INR: '₹', AUD: 'A$', CAD: 'C$', SGD: 'S$', CNY: 'CN¥', KRW: '₩' };
  function roundAmount(u) {
    const a = Number(u && u.amount);
    if (!u || u.amount == null || !isFinite(a) || a < 1000) return null;
    const cut = (v, d) => String(+v.toFixed(d));
    const n = a >= 1e9 ? cut(a / 1e9, 2) + 'B' : a >= 1e6 ? cut(a / 1e6, a >= 1e8 ? 0 : 1) + 'M' : cut(a / 1e3, 0) + 'K';
    const c = u.currency || 'USD', sym = CUR[c] || c + ' ';
    // "an $8M round", "an $11M round", "an $18M round"; every other amount takes "a"
    const an = ['USD', 'EUR', 'GBP'].includes(c) && !u.approx && /^(8|11(\D|$)|18(\D|$))/.test(n);
    return { text: (u.approx ? '~' : '') + sym + n, article: an ? 'an' : 'a' };
  }
  function updateLine(u, who) {
    const m = roundAmount(u), kind = u.round && u.round !== 'Other' ? u.round + ' ' : '';  // an unnamed round is just "a round"
    return `${who} ${u.led ? 'led' : 'joined'} ${m ? m.article + ' ' + m.text + ' ' : 'a '}${kind}round in ${u.startup}`;
  }

  // ---------- page shell
  el.innerHTML = `
<div class="vm-map" id="vm-map"><div class="vm-stage" id="vm-stage"><img class="vm-bg" id="vm-bg" alt=""><div class="vm-bgz" id="vm-bgz" hidden></div><div class="vm-wave" id="vm-wave"></div><div id="vm-pls"></div><div id="vm-labs"></div></div><div class="vm-tip" id="vm-tip" hidden></div><div class="vm-pm" role="group" aria-label="Zoom the map"><button type="button" data-z="in" aria-label="Zoom in">+</button><button type="button" data-z="out" aria-label="Zoom out">−</button></div><button type="button" class="vm-sh" id="vm-sh" aria-label="Share link" title="Share link">${SHARE_ICON}</button></div>
<div class="vm-colwrap"><section class="vm-card vm-head" aria-live="polite"><h1 id="vm-h1"></h1>
  <div class="vm-picks"><div class="vm-pick" data-pick="sectors"></div><div class="vm-pick" data-pick="stages"></div><div class="vm-pick vm-who" data-pick="who"></div></div>
  <p class="vm-based" id="vm-based"></p><a class="vm-btn" id="vm-cta" href="${ROOT}investors/">See the investors</a></section>
<aside class="vm-card vm-side" id="vm-side"></aside></div>
<aside class="vm-card vm-fp" id="vm-fp" aria-label="Firms" hidden></aside>
<div class="vm-card vm-views" role="group" aria-label="View"><button type="button" data-view="flow">Money flow</button><button type="button" data-view="hot">Trends</button><button type="button" data-view="founders">Founders</button><button type="button" data-view="path">Pathfinders</button></div>
<div class="vm-card vm-zoom" role="group" aria-label="Zoom to">${LEVELS.map(([k, t]) => `<button type="button" data-level="${k}">${t}</button>`).join('')}</div>
<div class="vm-card vm-dock"><div class="vm-period" role="group" aria-label="Compare the last period with the same time before">${[[90, 'Last 90 days'], [180, 'Last 180 days'], [365, 'Last 12 months']].map(([d, t]) => `<button type="button" data-days="${d}">${t}</button>`).join('')}</div><button type="button" class="vm-play" id="vm-play" aria-label="Play"></button><button type="button" class="vm-all" id="vm-all">All years</button>
  <div class="vm-time"><div class="vm-track"><div class="vm-fill" id="vm-fill"></div>${Array.from({ length: NQ + 1 }, (_, i) => `<i class="${i % 4 ? '' : 'vm-y'}" style="left:${i / NQ * 100}%"></i>`).join('')}
    <input type="range" id="vm-q0" min="0" max="${NQ}" step="1" aria-label="From quarter"><input type="range" id="vm-q1" min="0" max="${NQ}" step="1" aria-label="To quarter"></div>
    <div class="vm-years">${Array.from({ length: Math.ceil(NQ / 4) }, (_, i) => `<span style="left:${i * 4 / NQ * 100}%;width:${Math.min(4, NQ - i * 4) / NQ * 100}%">${2021 + i}</span>`).join('')}</div></div></div>
<p class="vm-legend" id="vm-legend"></p>
<div class="vm-msg" id="vm-msg" hidden></div>`;
  const stage = $('#vm-stage'), mapBox = $('#vm-map');

  // ---------- filters (two pop-up lists of checkboxes)
  // "Hot right now": the sector named next to a place follows the unit switch. On "%" it is the biggest rise or fall in
  // percent; on "#" it is the biggest in number of deals (hotn / coldn from the database).
  const hotOf = (p) => (S.unit === 'num' && p.hotn) || p.hot;
  const coldOf = (p) => (S.unit === 'num' && p.coldn) || p.cold;
  function drawPicks() {
    [['sectors', SECTORS, 'All sectors'], ['stages', STAGES, 'All stages']].forEach(([k, all, none]) => {
      const box = $(`[data-pick="${k}"]`), on = S[k], open = box.classList.contains('vm-open');
      const label = on.length === 0 ? none : on.length === 1 ? on[0] : on.length + ' ' + k;
      box.innerHTML = `<button type="button" class="vm-pickbtn" aria-haspopup="true" aria-expanded="${open}" title="${esc(label)}"><span>${esc(label)}</span><svg aria-hidden="true" width="10" height="6" viewBox="0 0 10 6"><path d="M1 1l4 4 4-4" fill="none" stroke="${INK}" stroke-width="1.6"/></svg></button>
<div class="vm-menu" ${open ? '' : 'hidden'}><label><input type="checkbox" data-v="" ${on.length ? '' : 'checked'}>${none}</label>${all.map((v) => `<label><input type="checkbox" data-v="${esc(v)}" ${on.includes(v) ? 'checked' : ''}>${k === 'sectors' ? `<span class="vm-sw" style="background:${COLORS[v]}"></span>` : ''}${esc(v)}</label>`).join('')}</div>`;
    });
    const box = $('[data-pick="who"]'), open = box.classList.contains('vm-open');
    box.innerHTML = `<button type="button" class="vm-pickbtn" aria-haspopup="true" aria-expanded="${open}"><span>${WHO.find(([k]) => k === who())[1]}</span><svg aria-hidden="true" width="10" height="6" viewBox="0 0 10 6"><path d="M1 1l4 4 4-4" fill="none" stroke="${INK}" stroke-width="1.6"/></svg></button>
<div class="vm-menu" ${open ? '' : 'hidden'}>${WHO.map(([k, t]) => `<label><input type="radio" name="vm-who" data-who="${k}" ${k === who() ? 'checked' : ''}>${t}</label>`).join('')}</div>`;
  }
  el.addEventListener('click', (e) => {
    const pb = e.target.closest('.vm-pickbtn');
    el.querySelectorAll('.vm-pick.vm-open').forEach((b) => { if (!pb || b !== pb.parentNode) { b.classList.remove('vm-open'); if (!e.target.closest('.vm-menu')) drawPicks(); } });
    if (pb) { pb.parentNode.classList.toggle('vm-open'); drawPicks(); }
  });
  el.addEventListener('change', (e) => {
    const cb = e.target.closest('.vm-menu input'); if (!cb) return;
    const k = cb.closest('.vm-pick').dataset.pick, v = cb.dataset.v;
    if (k === 'who') { S.who = cb.dataset.who; cb.closest('.vm-pick').classList.remove('vm-open'); }
    else S[k] = !v ? [] : cb.checked ? S[k].concat(v) : S[k].filter((x) => x !== v);
    closeList(); drawPicks(); refresh().then(() => { if (!S.list) drawSide(); });
  });

  // ---------- time line
  const q0 = $('#vm-q0'), q1 = $('#vm-q1');
  function drawTime() {
    q0.value = S.q0; q1.value = S.q1 + 1;
    $('#vm-fill').style.left = S.q0 / NQ * 100 + '%'; $('#vm-fill').style.right = (1 - (S.q1 + 1) / NQ) * 100 + '%';
    const a = qStart(S.q0), b = qEnd(S.q1), today = S.q1 === NQ - 1;
    // the chosen range is read from the handles; it is also spoken for screen readers
    $('#vm-q0').setAttribute('aria-valuetext', `${MONTHS[a.getMonth()]} ${a.getFullYear()}`); $('#vm-q1').setAttribute('aria-valuetext', today ? 'today' : `${MONTHS[b.getMonth()]} ${b.getFullYear()}`);
    $('#vm-play').classList.toggle('vm-on', !!S.playing); $('#vm-play').classList.toggle('vm-x2', !!S.playing && S.speed === 2); $('#vm-play').setAttribute('aria-label', !S.playing ? 'Play' : S.speed === 2 ? 'Stop' : 'Play faster');
    // The button offers the other view: "This year" while the line shows every year, "All years" once it is narrowed (founder, 23 Nov).
    $('#vm-all').textContent = S.q0 === 0 && S.q1 === NQ - 1 ? 'This year' : 'All years';
  }
  let timer = null;
  const later = () => { clearTimeout(timer); timer = setTimeout(refresh, 180); };
  q0.addEventListener('input', () => { stop(); S.q0 = Math.min(+q0.value, S.q1); closeList(); drawTime(); later(); });
  q1.addEventListener('input', () => { stop(); S.q1 = Math.max(+q1.value - 1, S.q0); closeList(); drawTime(); later(); });
  // A click anywhere on the line (or on a year under it) moves the nearer handle there: no dragging needed (founder, 23 Nov).
  $('.vm-time').addEventListener('click', (e) => {
    if (e.target === q0 || e.target === q1) return;  // the handles themselves still drag
    const r = $('.vm-track').getBoundingClientRect(); if (!r.width) return;
    const v = Math.max(0, Math.min(NQ, Math.round((e.clientX - r.left) / r.width * NQ)));
    stop();
    if (Math.abs(v - S.q0) <= Math.abs(v - (S.q1 + 1))) S.q0 = Math.min(v, S.q1); else S.q1 = Math.max(v - 1, S.q0);
    closeList(); drawTime(); later();
  });
  $('#vm-all').addEventListener('click', () => {
    stop();
    if (S.q0 === 0 && S.q1 === NQ - 1) S.q0 = Math.min((now.getFullYear() - 2021) * 4, NQ - 1);  // from January of this year to today
    else { S.q0 = 0; S.q1 = NQ - 1; }
    closeList(); drawTime(); refresh();
  });
  function stop() { if (S.playing) { S.playing = null; S.speed = 1; hidePost(); drawTime(); } }
  // Play (founder, 25 Nov): one press plays, the next stops. While it plays, a real
  // post from X about the big tech news of the quarter pops up on the map, pinned to the place the news came from, with
  // the pill riding on it. One of the quarter's posts is picked at random each run. Pressing the post pauses Play and
  // opens it big; closing that carries on. X draws the posts (its own embed); the page only keeps their numbers.
  // A post: [X status id, the tag over it, the place on the world map, the place on the US map].
  const POSTS = {
    0: [['1354523898851823622', 'JAN 2021 · THE GAMESTOP SQUEEZE', 'US Central', 'Dallas'], ['1354474147016024069', 'JAN 2021 · THE GAMESTOP SQUEEZE', 'US Central', 'Dallas'], ['1354317599492993024', 'JAN 2021 · THE GAMESTOP SQUEEZE', 'US Central', 'Dallas']],
    1: [['1389581557980139527', 'MAY 2021 · DOGECOIN BREAKS ROBINHOOD', 'US West', 'Bay Area'], ['1389587820772302849', 'MAY 2021 · DOGECOIN BREAKS ROBINHOOD', 'US West', 'Bay Area'], ['1395157383366782978', 'MAY 2021 · THE CRYPTO CRASH', 'US West', 'Bay Area']],
    2: [['1417547103354621954', 'JUL 2021 · BEZOS FLIES TO SPACE', 'US West', 'Seattle'], ['1417545632529756165', 'JUL 2021 · BEZOS FLIES TO SPACE', 'US West', 'Seattle'], ['1417305957776990208', 'JUL 2021 · BEZOS FLIES TO SPACE', 'US West', 'Seattle']],
    3: [['1453805031463993346', 'OCT 2021 · FACEBOOK RENAMES ITSELF META', 'US West', 'Bay Area'], ['1453842753591390210', 'OCT 2021 · FACEBOOK RENAMES ITSELF META', 'US West', 'Bay Area'], ['1445114779304177664', 'OCT 2021 · FACEBOOK GOES DOWN FOR SIX HOURS', 'US West', 'Bay Area']],
    4: [['1488325589467467777', 'JAN 2022 · THE NEW YORK TIMES BUYS WORDLE', 'US East', 'New York'], ['1488272875874549761', 'JAN 2022 · THE NEW YORK TIMES BUYS WORDLE', 'US East', 'New York'], ['1493017906698862595', 'FEB 2022 · THE CRYPTO SUPER BOWL', 'US West', 'Bay Area']],
    5: [['1518622729154482178', 'APR 2022 · MUSK OFFERS TO BUY TWITTER', 'US West', 'Bay Area'], ['1518667246633058305', 'APR 2022 · MUSK OFFERS TO BUY TWITTER', 'US West', 'Bay Area'], ['1523736429729583104', 'MAY 2022 · TERRA LUNA CRASHES', '', '']],
    6: [['1545529347703971842', 'JUL 2022 · MUSK BACKS OUT OF TWITTER', 'US West', 'Bay Area'], ['1559191505369120768', 'AUG 2022 · ADAM NEUMANN IS BACK', 'US West', 'Bay Area'], ['1559236958567763970', 'AUG 2022 · ADAM NEUMANN IS BACK', 'US West', 'Bay Area']],
    7: [['1585341984679469056', 'OCT 2022 · MUSK ARRIVES WITH A SINK', 'US West', 'Bay Area'], ['1585569774209183745', 'OCT 2022 · MUSK ARRIVES WITH A SINK', 'US West', 'Bay Area'], ['1590870008380678144', 'NOV 2022 · THE $8 BLUE CHECK', 'US West', 'Bay Area']],
    8: [['1635045526042472449', 'MAR 2023 · SILICON VALLEY BANK COLLAPSES', 'US West', 'Bay Area'], ['1635053298813378561', 'MAR 2023 · SILICON VALLEY BANK COLLAPSES', 'US West', 'Bay Area'], ['1635181422679052288', 'MAR 2023 · SILICON VALLEY BANK COLLAPSES', 'US West', 'Bay Area']],
    9: [['1665799710148530176', 'JUN 2023 · APPLE VISION PRO, $3,500', 'US West', 'Bay Area'], ['1665898080095600640', 'JUN 2023 · APPLE VISION PRO, $3,500', 'US West', 'Bay Area'], ['1665982819342884866', 'JUN 2023 · APPLE VISION PRO, $3,500', 'US West', 'Bay Area']],
    10: [['1676791677598547969', 'JUL 2023 · THREADS LAUNCHES', 'US West', 'Bay Area'], ['1683289667746267137', 'JUL 2023 · TWITTER BECOMES X', 'US West', 'Bay Area'], ['1683508159942467584', 'JUL 2023 · TWITTER BECOMES X', 'US West', 'Bay Area']],
    11: [['1725794188607017221', 'NOV 2023 · OPENAI FIRES SAM ALTMAN', 'US West', 'Bay Area'], ['1727218062829781032', 'NOV 2023 · ALTMAN IS BACK', 'US West', 'Bay Area'], ['1720228976738673095', 'NOV 2023 · SAM BANKMAN-FRIED CONVICTED', 'US East', 'New York']],
    // 2024 to 2026: found the same way (news roundups that embed the posts), 25 Nov. Quarters with no entry show no post.
    12: [['1754322459460063613', 'FEB 2024 · APPLE VISION PRO IN THE WILD', 'US West', 'Bay Area'], ['1753839916948009316', 'FEB 2024 · APPLE VISION PRO IN THE WILD', 'US West', 'Bay Area'], ['1754226906356994217', 'FEB 2024 · APPLE VISION PRO IN THE WILD', 'US West', 'Bay Area']],
    13: [['1779862794449354846', 'APR 2024 · THE HUMANE AI PIN REVIEW', 'US West', 'Bay Area'], ['1790075827666796666', 'MAY 2024 · GPT-4O FINDS ITS VOICE', 'US West', 'Bay Area'], ['1800110722925646099', 'JUN 2024 · APPLE INTELLIGENCE ARRIVES', 'US West', 'Bay Area']],
    14: [['1814226663858749942', 'JUL 2024 · CROWDSTRIKE GROUNDS THE WORLD', 'US Central', 'Austin'], ['1814217315564618043', 'JUL 2024 · CROWDSTRIKE GROUNDS THE WORLD', 'US Central', 'Austin'], ['1831038357641851380', 'SEP 2024 · FOUNDER MODE', 'US West', 'Bay Area']],
    15: [['1866509455896260813', 'DEC 2024 · SORA MEETS GYMNASTICS', 'US West', 'Bay Area'], ['1866254016944255384', 'DEC 2024 · SORA MEETS GYMNASTICS', 'US West', 'Bay Area'], ['1866540422325014700', 'DEC 2024 · SORA MEETS GYMNASTICS', 'US West', 'Bay Area']],
    16: [['1883733264294396277', 'JAN 2025 · THE DEEPSEEK SHOCK', 'China, HK, Taiwan', ''], ['1886198988199600391', 'FEB 2025 · VIBE CODING IS BORN', 'US West', 'Bay Area'], ['1904965683957706846', 'MAR 2025 · THE GHIBLI IMAGE CRAZE', 'US West', 'Bay Area']],
    17: [['1938299990922674352', "JUN 2025 · META'S $100M AI OFFERS", 'US West', 'Bay Area']],
    18: [['1953513280594751495', 'AUG 2025 · GPT-5 AND THE CHART CRIME', 'US West', 'Bay Area']],
    19: [['1980350617894941179', 'OCT 2025 · AWS TAKES DOWN THE INTERNET', 'US West', 'Seattle'], ['1990945928619131082', 'NOV 2025 · CLOUDFLARE GOES DOWN TOO', 'US West', 'Bay Area'], ['1990800703007367677', 'NOV 2025 · CLOUDFLARE GOES DOWN TOO', 'US West', 'Bay Area']],
    20: [['2017407995567616058', 'JAN 2026 · MOLTBOOK, A SOCIAL NETWORK FOR BOTS', 'US West', 'Bay Area'], ['2017344281837457414', 'JAN 2026 · MOLTBOOK, A SOCIAL NETWORK FOR BOTS', 'US West', 'Bay Area'], ['2033964654603735185', 'MAR 2026 · ALTMAN THANKS THE CODERS', 'US West', 'Bay Area']],
  };
  let xReady = null, postNow = null, postHold = false;
  const xLoad = () => xReady || (xReady = new Promise((res) => {
    if (window.twttr && window.twttr.widgets) return res(true);
    const s = document.createElement('script'); s.src = 'https://platform.twitter.com/widgets.js'; s.async = true;
    s.onload = () => { const t = setInterval(() => { if (window.twttr && window.twttr.widgets) { clearInterval(t); res(true); } }, 60); setTimeout(() => { clearInterval(t); res(!!(window.twttr && window.twttr.widgets)); }, 5000); };
    s.onerror = () => res(false); document.head.appendChild(s);
  }));
  function hidePost() { postNow = null; const b = document.getElementById('vm-post'); if (b) b.hidden = true; }
  function placePost() {  // beside the circle of the place the news came from; in the middle when that place is not on this map
    const b = document.getElementById('vm-post'); if (!b || b.hidden || !postNow) return;
    const box = mapBox.getBoundingClientRect(), c = els.get(S.level + '|' + (S.level === 'us' ? postNow[3] : S.level === 'world' ? postNow[2] : ''));
    const r = c && c.getBoundingClientRect(), w = b.offsetWidth || 240, h = b.offsetHeight || 170;
    let x = r ? r.right - box.left + 26 : box.width / 2 - w / 2, y = r ? r.top + r.height / 2 - box.top - 30 : box.height / 2 - h / 2;
    x = Math.max(34, Math.min(box.width - w - 70, x)); y = Math.max(96, Math.min(box.height - h - 120, y));
    b.style.left = x + 'px'; b.style.top = y + 'px'; b.classList.toggle('vm-nopin', !r);
  }
  // A post is made ready off screen first, so the line, the map and the post can change in the same instant (founder,
  // 26 Nov). Long posts (a video plus a quoted post and the like) are not used: the next one of the quarter is tried.
  const POST_MAX = 470;
  async function preparePost(q, run) {
    const set = S.view === 'founders' ? null : POSTS[q];
    if (!set || !(await xLoad()) || S.playing !== run) return null;
    const order = set.slice().sort(() => Math.random() - 0.5);
    for (const pick of order) {
      const next = document.createElement('div'); next.className = 'vm-post-in';
      const hold = document.createElement('div'); hold.style.cssText = 'position:absolute;left:-9999px;top:0;width:300px'; document.body.appendChild(hold); hold.appendChild(next);
      try { await window.twttr.widgets.createTweet(pick[0], next, { width: 300, dnt: true, conversation: 'none' }); } catch (e) { hold.remove(); continue; }
      if (S.playing !== run) { hold.remove(); return null; }
      const fr = next.querySelector('iframe'), hh = fr ? fr.getBoundingClientRect().height : 0;
      if (!fr || hh < 60 || hh > POST_MAX) { hold.remove(); continue; }  // deleted, or too long
      const tw = next.querySelector('.twitter-tweet'); if (tw) { tw.style.marginTop = '0'; tw.style.marginBottom = '0'; }
      return { pick, next, hold, hh };
    }
    return null;
  }
  function commitPost(pp) {
    if (!pp) return hidePost();
    let b = document.getElementById('vm-post');
    if (!b) { b = document.createElement('div'); b.id = 'vm-post'; b.className = 'vm-post'; b.hidden = true; mapBox.appendChild(b); }
    b.innerHTML = `<i class="vm-post-arm"></i><span class="vm-post-pill"><i></i><i></i><u></u></span><span class="vm-post-tag">${esc(pp.pick[1])}</span><div class="vm-post-mini" style="height:${Math.round(pp.hh * 0.8)}px"></div><button type="button" class="vm-post-hit" aria-label="Open this post"></button>`;
    b.querySelector('.vm-post-mini').appendChild(pp.next); pp.hold.remove();
    postNow = pp.pick; b.hidden = false; placePost();
    b.querySelector('.vm-post-hit').onclick = () => openPost(pp.pick);
  }
  function openPost(pick) {  // the post at full size; Play waits until it is closed
    let ov = document.getElementById('postbig');
    if (!ov) {
      ov = document.createElement('div'); ov.className = 'ov'; ov.id = 'postbig'; ov.hidden = true; document.body.appendChild(ov);
      new MutationObserver(() => { if (ov.hidden) postHold = false; }).observe(ov, { attributes: true, attributeFilter: ['hidden'] });
      ov.addEventListener('click', (e) => { if (e.target === ov) ov.hidden = true; });
    }
    ov.innerHTML = '<div class="md vm-postbig" role="dialog" aria-modal="true" aria-label="Post"><button class="x" data-close aria-label="Close">×</button><div class="vm-postbig-in"></div></div>';
    postHold = true; ov.hidden = false;
    xLoad().then((ok) => { if (ok) window.twttr.widgets.createTweet(pick[0], ov.querySelector('.vm-postbig-in'), { width: 440, dnt: true }); });
  }
  $('#vm-play').addEventListener('click', async () => {
    if (S.playing) return stop();  // one press plays, the next stops and the post goes away; no speeding up (founder, 25 Nov, after trying it)
    closeList(); if (S.q1 >= NQ - 1) S.q1 = S.q0;  // play grows the range one quarter at a time, from the left handle
    const run = S.playing = {}; S.speed = 1;
    drawTime(); xLoad();
    const first = await preparePost(S.q1, run);
    if (S.playing !== run) return;
    await refresh(); commitPost(first);
    // One beat per quarter: the next quarter's numbers and its post are fetched quietly, and only when both are ready do
    // the line, the map and the post change together. Never ahead of the data.
    while (S.playing === run && S.q1 < NQ - 1) {
      const t0 = Date.now(), next = S.q1 + 1, founders = S.view === 'founders';
      S.q1 = next; const ask = founders ? null : summary(); S.q1 = next - 1;  // asks for the next quarter; nothing on screen moves yet
      const [d, pp] = await Promise.all([ask, preparePost(next, run)]);
      const left = (postNow ? 2600 : 450) - (Date.now() - t0);  // a quarter that shows a post stays long enough to read it
      if (left > 0) await new Promise((r) => setTimeout(r, left));
      while (postHold && S.playing === run) await new Promise((r) => setTimeout(r, 200));
      if (S.playing !== run) { if (pp) pp.hold.remove(); return; }
      S.q1 = next; drawTime();
      if (founders) refresh(); else if (d) { remember(); S.data = d; draw(); }
      commitPost(pp);
    }
    if (S.playing === run) { await new Promise((r) => setTimeout(r, postNow ? 2600 : 1200)); if (S.playing === run) stop(); }
  });

  // ---------- zoom
  el.querySelectorAll('[data-level]').forEach((b) => b.addEventListener('click', () => setLevel(b.dataset.level)));
  // ---------- views: Money flow (rings) and Hot right now (what is speeding up or slowing down)
  // The button reads "Trends" since 25 Nov (founder: it shows what is slowing down too). In the code, the links (?view=hot)
  // and the notes it is still 'hot' / "Hot right now".
  el.querySelectorAll('[data-view]').forEach((b) => b.addEventListener('click', () => setView(b.dataset.view)));
  el.querySelectorAll('[data-days]').forEach((b) => b.addEventListener('click', () => { S.days = +b.dataset.days; S.list = null; S.pinned = null; marks(); refresh().then(drawSide); }));
  function marks() {
    el.classList.toggle('vm-hotview', S.view === 'hot');
    el.classList.toggle('vm-fview', S.view === 'founders');
    el.classList.toggle('vm-pview', S.view === 'path');
    // in the Founders view the map underneath may not be drawn yet, so the Zoom buttons are marked here too
    el.querySelectorAll('[data-level]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.level === S.level));
    el.querySelectorAll('[data-view]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.view === S.view));
    el.querySelectorAll('[data-days]').forEach((b) => b.setAttribute('aria-pressed', +b.dataset.days === S.days));
  }
  // Founders (js/founders.js) covers the map with its own view; the two older views are drawn here.
  // The timeline is shared: Founders reads the same handles, by the day the range starts and ends (founder, 25 Nov: "let's keep consistency").
  const ymd = (d) => d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
  function span() {
    const a = qStart(S.q0), b = qEnd(S.q1), all = S.q0 === 0 && S.q1 === NQ - 1;
    return { from: ymd(a), to: ymd(b), text: all ? 'since 2021' : `from ${MONTHS[a.getMonth()]} ${a.getFullYear()} to ${S.q1 === NQ - 1 ? 'today' : MONTHS[b.getMonth()] + ' ' + b.getFullYear()}` };
  }
  function founders() { land(); const F = window.REGRET_FOUNDERS; if (F) F.show({ el, sb, root: ROOT, mapv: MAPV, level: S.level, span: span(), kind: qs.get('fk'), mode: qs.get('fm') }); }
  function setView(v) {
    if (v === S.view) return;
    stop(); S.view = v; S.list = null; S.pinned = null; zoomReset(); marks();
    if (v === 'founders') { remember(); founders(); return; }
    if (window.REGRET_FOUNDERS) window.REGRET_FOUNDERS.hide();
    drawPicks(); refresh().then(drawSide);
  }
  function setLevel(l) {
    if (l === S.level) return;
    // Zooming in from the world: remember where the parent regions sit on the page, so their places can fly out of them.
    let from = null;
    if (S.level === 'world' && stage._rows) {
      from = {}; stage._rows.forEach((p) => { if (ZOOM[p.p] === l) from[p.p] = { x: S.ox + p.x * S.k, y: S.oy + p.y * S.k }; });
    }
    S.list = null; S.pinned = null; S.level = l; zoomReset(); land(); draw(from); drawSide();
    if (S.view === 'founders' && window.REGRET_FOUNDERS) { window.REGRET_FOUNDERS.setLevel(l); marks(); remember(); }
  }

  // ---------- drawing the map
  // Room each view leaves for the cards around it: [left, right, top, bottom] in page pixels.
  const ROOM = COL ? { world: [16, 16, 84, 104], us: [24, 24, 96, 120], eu: [24, 24, 62, 100] }
    : { world: [20, 20, 62, 60], us: [340, 220, 120, 120], eu: [210, 210, 30, 105] };
  function fit() {
    const g = S.geo && S.geo[S.level]; if (!g) return;
    const r = mapBox.getBoundingClientRect();
    // On a phone the controls sit above and below the map, not over it, so the map uses its whole box.
    const narrow = r.width < 700, [l0, rt, t, b] = narrow ? [6, 6, 6, 6] : ROOM[S.level];
    // the firms panel takes the left of the map; the map moves over so the chosen place stays in view (if the window is wide enough)
    const open = S.list && S.list.step === 'firms' && r.width >= 940, l = l0 + (open ? 376 : 0);
    const k = Math.max(narrow ? 0.2 : 0.4, Math.min((r.width - l - rt) / g.w, (r.height - t - b) / g.h));
    // Zoom (+ / −, the wheel, a pinch): the same picture, drawn S.z times bigger around the point (S.zx, S.zy) of the map.
    // At rest (S.z = 1) nothing differs from before. Circles grow more slowly than the map and names keep their size on
    // the screen (see RZ and LZ), so crowded places spread apart.
    const z = S.z || 1, ox0 = l + (r.width - l - rt - g.w * k) / 2, ax = ox0 + g.w * k / 2, ay = t + g.h * k / 2, kz = k * z;
    if (z <= 1.001) { S.z = 1; S.zx = g.w / 2; S.zy = g.h / 2; }
    S.zx = Math.min(g.w - g.w / (2 * z), Math.max(g.w / (2 * z), S.zx == null ? g.w / 2 : S.zx)); S.zy = Math.min(g.h - g.h / (2 * z), Math.max(g.h / (2 * z), S.zy == null ? g.h / 2 : S.zy));
    S.k = kz; S.ox = ax - S.zx * kz; S.oy = ay - S.zy * kz; S.boxW = r.width; S.boxH = r.height;
    stage.style.width = g.w + 'px'; stage.style.height = g.h + 'px';
    S.k0 = k; stage.style.setProperty('--lz', LZ().toFixed(4));
    stage.style.transform = `translate(${S.ox}px, ${S.oy}px) scale(${kz})`;
    mapBox.classList.toggle('vm-zoomed', z > 1); sharp();
  }
  window.addEventListener('resize', fit);
  // How circles and names are sized in map units when zoomed in. Circles grow more slowly than the map. Names keep their size
  // on the screen; on a phone, where the whole map is drawn small, they first grow to their full size and then keep it.
  const RZ = () => 1 / Math.sqrt(S.z || 1), LZ = () => { const z = S.z || 1, k0 = S.k0 || 1; return (k0 < 1 ? Math.min(1, k0 * z) : k0) / (k0 * z); };
  let zraf = 0, zdraw = false;
  // Zoomed in, the land picture would show its white lines ever thicker. So the same drawing is laid over it as lines
  // that keep their thickness on the screen (fetched once, the first time a map is zoomed). At rest the picture alone shows.
  const landTxt = {};
  function sharp() {
    const bz = $('#vm-bgz'), lv = S.level; if (!bz) return;
    if (!((S.z || 1) > 1) || S.view === 'founders') { bz.hidden = true; return; }
    if (bz.dataset.l === lv) { bz.hidden = false; return; }
    if (landTxt[lv] === undefined) { landTxt[lv] = null; fetch(`${ROOT}assets/map/${lv}-land.svg${MAPV}`).then((r) => r.text()).then((t) => { landTxt[lv] = t; sharp(); }).catch(() => { delete landTxt[lv]; }); }
    if (!landTxt[lv]) { bz.hidden = true; return; }
    bz.innerHTML = landTxt[lv]; bz.dataset.l = lv;
    bz.querySelectorAll('path').forEach((p, i) => { p.style.strokeWidth = `calc(${p.getAttribute('stroke-width')}px * var(--lz, 1))`; if (!i) p.style.fill = p.style.stroke = '#CCD5D1'; });  // the picture's grey, with its touch of light
    bz.hidden = false;
  }
  let zT = 0;
  const hideTip = () => { if (!S.pinned || COL) tip(null); };
  // the buttons glide; the wheel, a pinch and a drag follow the hand with no delay
  const pace = (cls) => { stage.classList.remove('vm-ease', 'vm-live'); stage.classList.add(cls); clearTimeout(zT); zT = setTimeout(() => stage.classList.remove(cls), cls === 'vm-ease' ? 420 : 260); };
  function zoomAt(f, sx, sy) {  // f above 1 zooms in; (sx, sy) is the point on the page that stays put (the middle of the map if none)
    const g = S.geo && S.geo[S.level]; if (!g || S.view === 'founders') return;
    const r = mapBox.getBoundingClientRect(), z0 = S.z || 1, z = Math.min(8, Math.max(1, z0 * f)); if (Math.abs(z - z0) < 0.001) return;
    pace(sx == null ? 'vm-ease' : 'vm-live');
    if (sx == null) { sx = S.ox + S.zx * S.k; sy = S.oy + S.zy * S.k; } else { sx -= r.left; sy -= r.top; }
    const ux = (sx - S.ox) / S.k, uy = (sy - S.oy) / S.k, k1 = S.k / z0 * z, ax = S.ox + S.zx * S.k, ay = S.oy + S.zy * S.k;
    S.z = z; S.zx = ux - (sx - ax) / k1; S.zy = uy - (sy - ay) / k1;
    hideTip(); fit(); if (stage.classList.contains('vm-ease')) { zdraw = true; draw(); } else { cancelAnimationFrame(zraf); zraf = requestAnimationFrame(() => { zdraw = true; draw(); }); }
  }
  function panBy(dx, dy) { if ((S.z || 1) <= 1) return; pace('vm-live'); S.zx -= dx / S.k; S.zy -= dy / S.k; fit(); }
  const zoomReset = () => { S.z = 1; S.zx = S.zy = null; };
  // Guernsey, Jersey and the Isle of Man are registration addresses, not places a founder would look for: they get no dot
  // of their own (their deals stay in Europe's totals), and an update from one lights up the United Kingdom.
  const FOLD = { GG: 'GB', JE: 'GB', IM: 'GB' };
  // One rule for places and sectors: under HOT_MIN deals across both periods there is no colour; within 10% either way is steady;
  // otherwise up or down, in the lighter shade when the difference is under HOT_FAINT deals.
  const toneOf = (n, p) => {
    const pct = p ? Math.round((n - p) / p * 100) : null, few = n + p < HOT_MIN;
    const tone = few ? 'few' : pct == null ? 'up' : pct >= 10 ? 'up' : pct <= -10 ? 'down' : 'flat';
    return { pct, few, tone, lt: (tone === 'up' || tone === 'down') && Math.abs(n - p) < HOT_FAINT, diff: n - p };
  };
  const toneCls = (o) => 'vm-' + o.tone + (o.lt ? ' vm-lt' : '');
  const signed = (v) => (v > 0 ? '+' : v < 0 ? '\u2212' : '') + num(Math.abs(v));
  // the figure beside a sector, as a percentage or as a number of deals (the % / # switch)
  const figure = (o) => o.tone === 'few' ? '' : S.unit === 'num' ? signed(o.diff) : o.pct == null ? 'new' : signed(o.pct) + '%';
  const toneHtml = (p) => p.tone === 'up' ? `<span class="vm-tu">${toneText(p)}</span>` : p.tone === 'down' ? `<span class="vm-td">${toneText(p)}</span>` : toneText(p);
  const toneText = (p) => p.tone === 'few' ? 'too few to call' : p.tone === 'flat' ? 'steady' : S.unit === 'num' ? signed(p.diff) + ' deal' + (Math.abs(p.diff) === 1 ? '' : 's') : p.pct == null ? 'up from none' : (p.tone === 'up' ? 'up ' : 'down ') + Math.abs(p.pct) + '%';
  const spark = (v, tone) => {
    if (!v || v.length < 2) return '<span class="vm-spark"></span>';
    const mx = Math.max.apply(null, v), mn = Math.min.apply(null, v), w = 72, h = 22;
    const pts = v.map((y, i) => (i / (v.length - 1) * (w - 4) + 2).toFixed(1) + ',' + (h - 3 - (mx === mn ? 0.5 : (y - mn) / (mx - mn)) * (h - 6)).toFixed(1));
    const c = tone === 'up' ? '#177A49' : tone === 'down' ? '#B93A2F' : '#5E6E69', last = pts[pts.length - 1].split(',');
    return `<svg class="vm-spark" aria-hidden="true" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"><polyline points="${pts.join(' ')}" fill="none" stroke="${c}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><circle cx="${last[0]}" cy="${last[1]}" r="2.4" fill="${c}"/></svg>`;
  };
  const unitSw = () => `<span class="vm-unit" role="group" aria-label="Show change as">${[['pct', '%', 'percent'], ['num', '#', 'number of deals']].map(([k, s, l]) => `<button type="button" data-u="${k}" aria-pressed="${S.unit === k}" aria-label="${l}">${s}</button>`).join('')}</span>`;
  const sortRows = (rows) => rows.slice().sort((a, b) => a.few !== b.few ? (a.few ? 1 : -1) : S.unit === 'num' ? b.diff - a.diff : (b.pct == null ? 1e9 : b.pct) - (a.pct == null ? 1e9 : a.pct));
  const litPlace = () => { const u = S.updates[0]; return !u || S.view === 'hot' || S.view === 'path' ? null : S.level === 'world' ? u.region : u.level === S.level ? (FOLD[u.area] || u.area) : null; };
  const placesNow = () => {
    const g = S.geo[S.level].places, sector = S.sectors.length > 0;
    const rows = (S.data.places || []).filter((p) => p.l === S.level && g[p.p] && !FOLD[p.p]).map((p) => Object.assign({}, p, g[p.p], { n: g[p.p].n || p.p }));
    const max = Math.max(1, ...rows.map((p) => p.d)), hot = S.view === 'hot';
    rows.forEach((p) => {
      if (S.view === 'path') {  // one plain circle per place: the startups of its firms (those not on the Top 100 list) that a Top 100 firm later backed
        p.kind = p.d > 0 ? 'path' : null;
        p.r = S.level === 'world' ? Math.round(13 + 27 * Math.sqrt(p.d / max)) : Math.round(7 + 29 * Math.sqrt(p.d / max));
        p.ax = p.x; p.ay = p.y; return;
      }
      if (hot) {  // one plain circle per place, coloured by whether deal-making there is speeding up or slowing down
        p.pv = p.pv || 0; Object.assign(p, toneOf(p.d, p.pv));
        p.kind = S.level === 'world' || p.d + p.pv >= 10 ? 'hot' : null;
        p.r = S.level === 'world' ? Math.round(14 + 26 * Math.sqrt(p.d / max)) : Math.round(8 + 28 * Math.sqrt(p.d / max));
        p.ax = p.x; p.ay = p.y; return;
      }
      p.kind = sector ? (S.sectors.length > 1 ? 'ring' : 'plain') : (S.level === 'world' || (p.d >= RING_DEALS && p.f >= RING_FIRMS)) ? 'ring' : p.d >= DOT_DEALS ? 'dot' : null;
      p.r = p.kind === 'dot' ? 6 : S.level === 'world' ? Math.round(18 + 20 * Math.pow(p.d / max, 0.6)) : sector ? Math.round(7 + 30 * Math.sqrt(p.d / max)) : S.level === 'eu' ? Math.round(11 + 27 * Math.sqrt(p.d / max)) : Math.round(14 + 26 * Math.sqrt(p.d / max));
      p.ax = p.x; p.ay = p.y;
    });
    if (S.view === 'path' && S.level !== 'world') rows.filter((p) => p.kind).sort((a, b) => b.d - a.d).slice(24).forEach((p) => { p.kind = null; });  // the 24 biggest: the map stays readable
    rows.forEach((p) => { if (p.r) p.r *= RZ(); });
    // On the US and Europe maps the smallest places are left out so the map stays readable. With narrow filters that
    // could leave it empty while the sector list still shows deals, so when few circles remain the next largest come back.
    if (hot && S.level !== 'world' && rows.filter((p) => p.kind).length < 8) {
      rows.filter((p) => !p.kind && p.d + p.pv > 0).sort((a, b) => (b.d + b.pv) - (a.d + a.pv)).slice(0, 15 - rows.filter((p) => p.kind).length).forEach((p) => { p.kind = 'hot'; });
    }
    const out = rows.filter((p) => p.kind), big = out.filter((p) => p.kind !== 'dot');
    for (let it = 0; it < 80; it++) {  // nudge overlapping circles apart, keeping each close to its true spot
      for (let i = 0; i < big.length; i++) for (let j = i + 1; j < big.length; j++) {
        const a = big[i], b = big[j], dx = b.x - a.x, dy = b.y - a.y, d = Math.hypot(dx, dy) || 0.01, need = a.r + b.r + 3 * LZ();
        if (d < need) { const m = (need - d) / 2, wa = b.r / (a.r + b.r), wb = 1 - wa; a.x -= dx / d * m * 2 * wa; a.y -= dy / d * m * 2 * wa; b.x += dx / d * m * 2 * wb; b.y += dy / d * m * 2 * wb; }
      }
      big.forEach((p) => { p.x += (p.ax - p.x) * 0.06; p.y += (p.ay - p.y) * 0.06; });
    }
    // a small dot that would sit on top of a ring is left out (its firms are still in that ring's neighbourhood list)
    return out.filter((p) => p.kind !== 'dot' || !big.some((b) => Math.hypot(b.x - p.x, b.y - p.y) < b.r + 8 * LZ())).sort((a, b) => (a.kind === 'dot') - (b.kind === 'dot') || b.d - a.d);
  };
  // Each circle is one lasting element, so a change of numbers glides (size, position, slices) instead of jumping.
  const els = new Map();  // "level|place" -> button
  const WEST = ['Bay Area', 'Los Angeles', 'San Diego', 'Seattle', 'Portland', 'Denver', 'Salt Lake City', 'Vail', 'Aspen', 'Las Vegas', 'Phoenix', 'Santa Rosa', 'Santa Barbara', 'Sacramento', 'Jackson', 'Bend'];
  const EAST = ['New York', 'Boston', 'Washington DC', 'Miami', 'Philadelphia', 'Atlanta', 'Raleigh-Durham', 'Tampa', 'Baltimore', 'Dover', 'Princeton', 'Charleston', 'Portsmouth', 'Providence', 'Pittsburgh', 'Charlotte'];
  const parentOf = (lvl, place) => lvl === 'eu' ? 'Europe' : WEST.includes(place) ? 'US West' : EAST.includes(place) ? 'US East' : 'US Central';
  const setSlices = (b, p) => {
    const tot = p.tot || 1; let acc = 0;
    for (let k = 1; k <= 5; k++) {
      const t = (p.top || [])[k - 1];
      if (t) acc += t[1] / tot * 100;
      b.style.setProperty('--vm-c' + k, t ? (COLORS[t[0]] || COLORS.Other) : REST);
      b.style.setProperty('--vm-a' + k, Math.min(100, acc) + '%');
    }
  };
  // The grey land of the zoom we are on. Every view sits on this one picture: Money flow and Hot right now put their
  // circles on it, Founders lays its colours over it (founder, 25 Nov: the map must not change between the views).
  function land() {
    const g = S.geo && S.geo[S.level]; if (!g) return;
    const bg = $('#vm-bg');
    if (bg.dataset.l !== S.level) {
      bg.dataset.l = S.level; bg.style.opacity = 0; bg.onload = () => { bg.style.opacity = 1; };
      bg.src = `${ROOT}assets/map/${S.level}-land.svg${MAPV}`; bg.width = g.w; bg.height = g.h;  // smooth grey land, made by build.py (founder, 23 Nov)
      $('#vm-wave').style.webkitMaskImage = $('#vm-wave').style.maskImage = `url(${ROOT}assets/map/${S.level}.svg${MAPV})`;  // the dots the land dissolves into while loading
      els.forEach((b) => b.remove()); els.clear();
    }
    fit();
  }
  function draw(from) {  // from: where the new circles fly out of when zooming in ({ parentPlace: {x, y} } in page pixels)
    if (!S.data || !S.geo) return;
    const g = S.geo[S.level], rows = placesNow(), lit = litPlace(), sector = S.sectors.length > 0;
    const pls = $('#vm-pls');
    land();
    const boxes = rows.map((p) => ({ x0: p.x - p.r, y0: p.y - p.r, x1: p.x + p.r, y1: p.y + p.r }));
    const hit = (b) => b.x0 < 0 || b.x1 > g.w || boxes.some((o) => b.x0 < o.x1 && b.x1 > o.x0 && b.y0 < o.y1 && b.y1 > o.y0);
    const seen = new Set(), fresh = [];
    let labs = '';
    rows.forEach((p, i) => {
      const key = S.level + '|' + p.p; seen.add(key);
      let b = els.get(key);
      if (!b) {
        b = document.createElement('button'); b.type = 'button';
        b.style.left = p.x - p.r + 'px'; b.style.top = p.y - p.r + 'px'; b.style.width = b.style.height = p.r * 2 + 'px';
        b.className = 'vm-pl vm-in'; pls.appendChild(b); els.set(key, b); fresh.push([b, p]);
      }
      b.className = `vm-pl vm-${p.kind}${p.kind === 'hot' ? ' ' + toneCls(p) : ''}${lit === p.p ? ' vm-lit' : ''}${S.pinned === p.p ? ' vm-sel' : ''}${b.classList.contains('vm-in') ? ' vm-in' : ''}`;
      b.dataset.i = i; b.setAttribute('aria-label', S.view === 'path' ? `${p.n}: ${num(p.f)} firms` : `${p.n}: ${num(p.d)} deals, ${num(p.f)} firms`);
      b.style.left = p.x - p.r + 'px'; b.style.top = p.y - p.r + 'px'; b.style.width = b.style.height = p.r * 2 + 'px';
      if (p.kind === 'ring') { b.style.backgroundColor = ''; setSlices(b, p); }
      else if (p.kind === 'hot' || p.kind === 'path') b.style.backgroundColor = '';
      else b.style.backgroundColor = p.kind === 'plain' ? (S.sectors.length === 1 ? COLORS[S.sectors[0]] : '#C9D1CE') : (COLORS[(p.top && p.top[0] && p.top[0][0])] || '#C9D1CE');
      // label: below, else above, else right, else left; dropped if nothing fits
      const sub = p.kind === 'hot' ? (S.level === 'world' ? toneText(p) + (hotOf(p) && p.tone !== 'few' ? ' · ' + hotOf(p)[0] : '') : num(p.d) + ' · ' + toneText(p)) : num(p.d) + (S.level === 'world' && !sector && p.so ? ' · ' + p.so : ''), small = p.kind === 'dot';
      const q = LZ(), w = (Math.max(p.n.length * (small ? 5.6 : 6.6), small ? 0 : sub.length * 5.9) + 8) * q, h = (small ? 14 : 30) * q;
      const tries = small ? [[p.x + p.r + 6 * q, p.y - 7 * q, 'l'], [p.x - p.r - 6 * q - w, p.y - 7 * q, 'r']] : [[p.x - w / 2, p.y + p.r + 2 * q, 'c'], [p.x - w / 2, p.y - p.r - h - 2 * q, 'c'], [p.x + p.r + 4 * q, p.y - h / 2, 'l'], [p.x - p.r - 4 * q - w, p.y - h / 2, 'r'],
        [p.x + p.r * 0.7 + 2 * q, p.y + p.r * 0.7, 'l'], [p.x - p.r * 0.7 - 2 * q - w, p.y + p.r * 0.7, 'r'], [p.x + p.r * 0.7 + 2 * q, p.y - p.r * 0.7 - h, 'l'], [p.x - p.r * 0.7 - 2 * q - w, p.y - p.r * 0.7 - h, 'r']];
      let placed = false;
      for (const [x, y, al] of tries) {
        const bx = { x0: x, y0: y, x1: x + w, y1: y + h };
        if (!hit(bx)) { boxes.push(bx); placed = true; labs += `<span class="vm-lab ${small ? 'vm-sm' : ''}" style="left:${x}px;top:${y}px;width:${w}px;text-align:${al === 'c' ? 'center' : al === 'l' ? 'left' : 'right'}">${esc(p.n)}${small ? ' ' + num(p.d) : `<br><em>${p.kind === 'hot' ? (S.level === 'world' ? toneHtml(p) + (hotOf(p) && p.tone !== 'few' ? ' · ' + esc(hotOf(p)[0]) : '') : num(p.d) + ' · ' + toneHtml(p)) : esc(sub)}</em>`}</span>`; break; }
      }
      // No room for the full name (crowded Europe): fall back to the two-letter country code, beside the ring if it fits, else in its centre.
      if (!placed && S.level === 'eu' && !small) {
        const cw = 20 * q, ch = 13 * q, spots = [[p.x - cw / 2, p.y + p.r + q], [p.x - cw / 2, p.y - p.r - ch - q], [p.x + p.r + 2 * q, p.y - ch / 2], [p.x - p.r - 2 * q - cw, p.y - ch / 2]];
        let done = false;
        for (const [x, y] of spots) {
          const bx = { x0: x, y0: y, x1: x + cw, y1: y + ch };
          if (!hit(bx)) { boxes.push(bx); done = true; labs += `<span class="vm-lab vm-code" title="${esc(p.n)}" style="left:${x}px;top:${y}px;width:${cw}px">${esc(p.p)}</span>`; break; }
        }
        if (!done) labs += `<span class="vm-lab vm-code vm-code-in" title="${esc(p.n)}" style="left:${p.x - cw / 2}px;top:${p.y - ch / 2}px;width:${cw}px">${esc(p.p)}</span>`;
      }
    });
    els.forEach((b, key) => { if (!seen.has(key)) { els.delete(key); b.classList.add('vm-out'); setTimeout(() => b.remove(), 850); } });
    const lb = $('#vm-labs'); lb.className = from ? 'vm-late' : zdraw ? 'vm-still' : ''; zdraw = false; lb.innerHTML = labs;  // names redrawn by a zoom do not fade in again
    // New circles: either fly out of the region they belong to (zooming in), or pop in where they are.
    if (from) fresh.forEach(([b, p], n) => {
      const o = from[parentOf(S.level, p.p)]; if (!o) return;
      const cx = S.ox + p.x * S.k, cy = S.oy + p.y * S.k;
      b.classList.remove('vm-in'); b.style.transition = 'none';
      b.style.transform = `translate(${(o.x - cx) / S.k}px, ${(o.y - cy) / S.k}px) scale(0.3)`; b.style.opacity = 0.3;
      void b.offsetWidth;
      b.style.transition = ''; b.style.transitionDelay = Math.min(n * 12, 300) + 'ms'; b.style.transform = ''; b.style.opacity = '';
      setTimeout(() => { b.style.transitionDelay = ''; }, 1200);
    });
    else if (fresh.length) { void pls.offsetWidth; fresh.forEach(([b]) => b.classList.remove('vm-in')); }
    stage._rows = rows; drawHead();
    el.querySelectorAll('[data-level]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.level === S.level));
    // Floating layout: the chosen place keeps its card open. Column layout: its numbers move into the column, so the map stays clear.
    const pin = S.pinned && !COL ? rows.find((p) => p.p === S.pinned) : null; tip(pin || null);
  }
  function tip(p) {
    const t = $('#vm-tip'); if (!t) return;
    if (!p) { t.hidden = true; return; }
    if (S.view === 'path') {
      t.innerHTML = `<b>${esc(p.n)}</b><span class="vm-mu">${num(p.f)} firm${p.f === 1 ? '' : 's'}</span>`;
    } else if (S.view === 'hot') {
      const per = S.days === 365 ? '12 months' : S.days + ' days';
      // each fact on its own line, with its numbers kept together on the right so nothing breaks mid-number
      t.innerHTML = `<b>${esc(p.n)}</b><span class="vm-tr"><span class="vm-mu">${num(p.d)} deal${p.d === 1 ? '' : 's'} in the last ${per}</span></span><span class="vm-tr"><span>${toneHtml(p)}</span>${p.tone === 'few' ? '' : `<span class="vm-pc vm-mu">${num(p.pv)} before</span>`}</span>${hotOf(p) ? `<span class="vm-tr vm-rule"><span><i class="${toneCls(toneOf(hotOf(p)[1], hotOf(p)[2]))}"></i><b>${esc(hotOf(p)[0])}</b></span><span class="vm-pc">${num(hotOf(p)[1])} vs ${num(hotOf(p)[2])}</span></span>` : ''}${coldOf(p) ? `<span class="vm-tr${hotOf(p) ? '' : ' vm-rule'}"><span><i class="${toneCls(toneOf(coldOf(p)[1], coldOf(p)[2]))}"></i><b>${esc(coldOf(p)[0])}</b></span><span class="vm-pc">${num(coldOf(p)[1])} vs ${num(coldOf(p)[2])}</span></span>` : ''}`;
    } else {
    const tot = p.tot || 1, sector = S.sectors.length > 0, top = p.top || [], rest = Math.max(0, 100 - top.reduce((a, [, v]) => a + Math.round(v / tot * 100), 0));
    t.innerHTML = `<b>${esc(p.n)}</b><span class="vm-mu">${num(p.d)} ${S.sectors.length === 1 ? esc(S.sectors[0]) + ' ' : ''}deal${p.d === 1 ? '' : 's'}${S.sectors.length > 1 ? ' in the chosen sectors' : ''} · ${num(p.f)} firm${p.f === 1 ? '' : 's'}</span>
${!sector && p.so ? `<span>Stands out for <b>${esc(p.so)}</b></span>` : ''}
${S.sectors.length === 1 ? '' : top.map(([n, v], j) => `<span class="vm-tr"><i style="background:${COLORS[n] || COLORS.Other}"></i><span>${j + 1}. ${esc(n)}</span><span class="vm-pc">${Math.round(v / tot * 100)}%</span></span>`).join('') + (top.length && (rest > 0 || !sector) ? `<span class="vm-tr"><i style="background:${REST}"></i><span>${sector ? 'Other chosen sectors' : 'All other sectors'}</span><span class="vm-pc">${rest}%</span></span>` : '')}`;
    }
    t.hidden = false;
    // The card sits on the page (not inside the scaled map), beside the circle, and stays clear of the time line.
    const w = S.view === 'hot' ? 272 : 236, h = t.offsetHeight || 220, cx = S.ox + p.x * S.k, cy = S.oy + p.y * S.k, rr = p.r * S.k;
    let x = cx + rr + 10, y = cy - 30;
    if (x + w > S.boxW - (S.list && !COL ? 410 : 10)) x = cx - rr - 10 - w;
    y = Math.max(4, Math.min(S.boxH - 112 - h, y));
    t.style.left = Math.max(4, x) + 'px'; t.style.top = y + 'px';
  }
  stage.addEventListener('mouseover', (e) => { const b = e.target.closest('.vm-pl'); if (b && (!S.pinned || COL)) { clearTimeout(hideT); tip(stage._rows[+b.dataset.i]); } });
  stage.addEventListener('focusin', (e) => { const b = e.target.closest('.vm-pl'); if (b && (!S.pinned || COL)) tip(stage._rows[+b.dataset.i]); });
  let hideT = null;
  const hideSoon = () => { clearTimeout(hideT); hideT = setTimeout(() => { if (!S.pinned || COL) tip(null); }, 220); };
  stage.addEventListener('mouseout', (e) => { if (e.target.closest('.vm-pl')) hideSoon(); });
  $('#vm-tip').addEventListener('mouseenter', () => clearTimeout(hideT));
  $('#vm-tip').addEventListener('mouseleave', hideSoon);
  // Zoom and move the map: + / −, the wheel, a pinch; a drag moves it once it is zoomed in. At rest a finger still scrolls the page.
  let dragged = false, drag = null, pinch = 0; const ptrs = new Map();
  mapBox.querySelector('.vm-pm').addEventListener('click', (e) => { const b = e.target.closest('[data-z]'); if (b) zoomAt(b.dataset.z === 'in' ? 1.7 : 1 / 1.7); });
  mapBox.addEventListener('wheel', (e) => { if (S.view === 'founders') return; e.preventDefault(); zoomAt(Math.exp(-Math.max(-60, Math.min(60, e.deltaY)) * 0.004), e.clientX, e.clientY); }, { passive: false });
  $('#vm-sh').addEventListener('click', (e) => { e.stopPropagation(); share(e.currentTarget); });
  mapBox.addEventListener('pointerdown', (e) => { if (S.view === 'founders' || e.target.closest('.vm-pm,.vm-sh')) return; ptrs.set(e.pointerId, [e.clientX, e.clientY]); dragged = false; drag = ptrs.size === 1 ? [e.clientX, e.clientY] : null; if (ptrs.size === 2) { const [a, b] = [...ptrs.values()]; pinch = Math.hypot(a[0] - b[0], a[1] - b[1]); } });
  mapBox.addEventListener('pointermove', (e) => {
    if (!ptrs.has(e.pointerId)) return; ptrs.set(e.pointerId, [e.clientX, e.clientY]);
    if (ptrs.size === 2 && pinch) { const [a, b] = [...ptrs.values()], d = Math.hypot(a[0] - b[0], a[1] - b[1]); if (Math.abs(d - pinch) > 4) { zoomAt(d / pinch, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2); pinch = d; dragged = true; } return; }
    if (!drag || (S.z || 1) <= 1) return;
    const dx = e.clientX - drag[0], dy = e.clientY - drag[1]; if (!dragged && Math.hypot(dx, dy) < 5) return;
    dragged = true; drag = [e.clientX, e.clientY]; hideTip(); panBy(dx, dy);
  });
  const endPtr = (e) => { ptrs.delete(e.pointerId); if (ptrs.size < 2) pinch = 0; if (!ptrs.size) drag = null; };
  mapBox.addEventListener('dragstart', (e) => e.preventDefault());  // the map picture must not be picked up as an image
  mapBox.addEventListener('pointerup', endPtr); mapBox.addEventListener('pointercancel', endPtr); mapBox.addEventListener('pointerleave', endPtr);
  stage.addEventListener('click', (e) => {
    if (dragged) { dragged = false; return; }  // the end of a drag is not a click
    const b = e.target.closest('.vm-pl');
    // Clicking a place opens its sectors (in both views; founder, 25 Nov); clicking it again, or the empty map, closes them.
    if (b) { const p = stage._rows[+b.dataset.i]; if (S.list && S.list.place.p === p.p) closeList(); else openList(p); return; }
    if (S.list) closeList();
  });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { if (S.list && S.list.step === 'firms') { S.list.step = 'sectors'; S.list.sector = null; S.list.data = null; drawSide(); } else if (S.list) closeList(); } });

  // ---------- headline card
  // sector names inside a sentence: lower case, except the ones that start with an abbreviation
  const inSentence = (name) => (/^AI /.test(name) ? name : name.toLowerCase()), PLURAL = ['AI agents', 'AI models', 'Developer tools'];
  const perText = () => (S.days === 365 ? '12 months' : S.days + ' days');
  function drawHotHead() {
    const where = S.level === 'us' ? ' in the US' : S.level === 'eu' ? ' in Europe' : '', t = (S.data.totals || {})[S.level] || { deals: 0, prev: 0 };
    const sec = S.sectors.length === 1 ? inSentence(S.sectors[0]) : S.sectors.length ? 'these sectors' : '';
    // The head card is the same four rows in every view (founder, 25 Nov): one fixed title line, the buttons, one "Based on"
    // line, the black button. The title no longer names the place or the sector: the buttons and the list card do.
    $('#vm-h1').textContent = 'Where it is heating up.';
    S.countId = (S.countId || 0) + 1; S.shown = null;
    $('#vm-based').textContent = `Based on ${num(t.deals)} deal${t.deals === 1 ? '' : 's'} and ${num(t.firms || 0)} VC firm${t.firms === 1 ? '' : 's'}`;
    const note = whoNote();
    $('#vm-legend').innerHTML = note ? `<span class="vm-whonote"><b>${esc(WHO.find(([k]) => k === who())[1])}</b><span>${esc(note)}</span></span>` : '<span class="vm-keys"><span><i class="vm-up"></i>up 10% or more</span><span><i class="vm-flat"></i>steady</span><span><i class="vm-down"></i>down 10% or more</span><span><i class="vm-few"></i>too few to call</span></span>';
  }
  // Pathfinders: the same four rows as every view. Title and "Based on" line as in the design he approved (25 Nov).
  function drawPathHead() {
    const t = (S.data.totals || {})[S.level] || { firms: 0 };
    $('#vm-h1').textContent = 'Who the top firms follow.';
    S.countId = (S.countId || 0) + 1; S.shown = null;
    $('#vm-based').textContent = `Based on ${num(t.firms)} firm${t.firms === 1 ? '' : 's'} the Top 100 followed`;  // one line, as in every view
    $('#vm-legend').innerHTML = '';
  }
  function drawHead() {
    if (S.view === 'path') return drawPathHead();
    if (S.view === 'hot') return drawHotHead();
    const where = S.level === 'us' ? ' in the US' : S.level === 'eu' ? ' in Europe' : '', t = (S.data.totals || {})[S.level] || { deals: 0, firms: 0 };
    const sec = S.sectors.length === 1 ? inSentence(S.sectors[0]) : S.sectors.length ? 'these sectors' : '';
    $('#vm-h1').textContent = 'What VCs are investing in.';  // one fixed line, as in every view
    // the two numbers count up or down to their new values
    const a0 = S.shown || { deals: t.deals, firms: t.firms }, t0 = performance.now(), my = S.countId = (S.countId || 0) + 1;
    const still = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const step = (now) => {
      if (my !== S.countId) return;
      const k = still ? 1 : Math.min(1, (now - t0) / 500), e = 1 - Math.pow(1 - k, 3);
      const dd = Math.round(a0.deals + (t.deals - a0.deals) * e), ff = Math.round(a0.firms + (t.firms - a0.firms) * e);
      S.shown = { deals: dd, firms: ff };
      $('#vm-based').textContent = `Based on ${num(dd)} deal${dd === 1 ? '' : 's'} and ${num(ff)} VC firm${ff === 1 ? '' : 's'}`;
      if (k < 1) requestAnimationFrame(step);
    };
    step(t0);
    $('#vm-legend').innerHTML = '';  // no note over the map in this view: it only repeated what the map shows (founder, 23 Nov)
  }

  // ---------- right side: latest updates, or the firms behind a place
  const day = (s) => { const d = new Date(s + 'T00:00:00'); return isNaN(d) ? '' : MONTHS[d.getMonth()] + ' ' + d.getDate() + (d.getFullYear() === now.getFullYear() ? '' : ', ' + d.getFullYear()); };
  // The chosen place's own numbers, shown above its firms in the column layout.
  function placeFacts(p, ofSector) {
    // Hot right now has no line here: hovering the circle already says it (founder, 23 Nov: nothing that repeats what the design shows).
    if (S.view === 'hot') return '';
    const tot = p.tot || 1, top = p.top || [], one = S.sectors.length === 1, sector = S.sectors.length > 0;
    if (one || !top.length) return `<div class="vm-facts"><span class="vm-mu">${num(p.d)} deal${p.d === 1 ? '' : 's'}</span></div>`;
    const rest = Math.max(0, 100 - top.reduce((a, [, v]) => a + Math.round(v / tot * 100), 0));
    return `<div class="vm-facts"><span class="vm-mu">${num(p.d)} deal${p.d === 1 ? '' : 's'}${!sector && p.so ? ` · stands out for <b>${esc(p.so)}</b>` : ''}</span><span class="vm-bar">${top.map(([n, v]) => `<i style="width:${v / tot * 100}%;background:${COLORS[n] || COLORS.Other}" title="${esc(n)} ${Math.round(v / tot * 100)}%"></i>`).join('')}</span><span class="vm-key">${top.map(([n, v]) => `<span><i style="background:${COLORS[n] || COLORS.Other}"></i>${esc(n)} ${Math.round(v / tot * 100)}%</span>`).join('')}${rest > 0 ? `<span><i style="background:${REST}"></i>${sector ? 'Other chosen' : 'All other'} ${rest}%</span>` : ''}</span></div>`;
  }
  // The Investors list, opened with what is chosen here (place, sectors, stages) as its tags.
  function listUrl() {
    const q = [], P = S.list && S.list.place;
    if (P) {
      q.push('zoom=' + S.level, 'place=' + encodeURIComponent(P.p), 'pname=' + encodeURIComponent(P.n));
      // With a place open, the list shows the same firms this map counted: it gets the period (and the "which firms" choice) too.
      if (S.view === 'hot') q.push('days=' + S.days, 'from=' + iso(new Date(now.getFullYear(), now.getMonth(), now.getDate() - S.days + 1)), 'to=' + iso(now));
      else q.push('from=' + iso(qStart(S.q0)), 'to=' + iso(qEnd(S.q1)));
      if (who() !== 'all') q.push('who=' + who());
    } else if (S.level === 'us' || S.level === 'eu') {
      // No circle open on the US or Europe view: the list shows that whole view, the same firms this map counted (founder, 23 Nov).
      q.push('zoom=' + S.level);
      if (S.view === 'hot') q.push('days=' + S.days, 'from=' + iso(new Date(now.getFullYear(), now.getMonth(), now.getDate() - S.days + 1)), 'to=' + iso(now));
      else q.push('from=' + iso(qStart(S.q0)), 'to=' + iso(qEnd(S.q1)));
      if (who() !== 'all') q.push('who=' + who());
    }
    const sec = S.list && S.list.sector ? [S.list.sector] : S.sectors;
    if (sec.length) q.push('sectors=' + sec.map(encodeURIComponent).join('|'));
    if (S.stages.length) q.push('stages=' + S.stages.map(encodeURIComponent).join('|'));
    return ROOT + 'investors/' + (q.length ? '?' + q.join('&') : '');
  }
  function drawSide() {
    const side = $('#vm-side');
    $('#vm-cta').href = listUrl();
    const hotList = S.view === 'hot' && S.list;
    // The button names what is chosen: the place, and the sector when one is open, with the number of firms the map counted.
    // (A sector row is [name, deals, before, firms, line] in Hot right now and [name, deals, firms] in Money flow.)
    const openSec = S.list && S.list.sector && ((S.list.det || {}).sectors || []).find((r) => r[0] === S.list.sector);
    const ctaN = openSec ? openSec[hotList ? 3 : 2] : S.list ? S.list.place.f : 0;
    $('#vm-cta').textContent = S.list ? `See the ${num(ctaN)} ${openSec ? S.list.sector + ' ' : ''}investor${ctaN === 1 ? '' : 's'} in ${S.list.place.n}` : 'See the investors';
    const units = () => side.querySelectorAll('.vm-unit button').forEach((u) => u.onclick = () => { S.unit = u.dataset.u; draw(); drawSide(); });
    drawFirms();
    if (S.view === 'path') return drawPathSide(side);
    if (hotList) {  // a clicked place opens on its sectors; its firms open in their own panel beside the rail
      const L = S.list, rows = sortRows(((L.det || {}).sectors || []).map(([name, n, p, f, line]) => Object.assign({ name, n, p, f, line }, toneOf(n, p))));
      side.className = 'vm-card vm-side vm-list';
      side.innerHTML = `<div class="vm-lh"><div class="vm-chips"><button type="button" class="vm-chip" id="vm-unplace" aria-label="Remove filter ${esc(L.place.n)}">${esc(L.place.n)}<span aria-hidden="true">×</span></button></div><button type="button" class="vm-x" id="vm-close" aria-label="Close"></button></div>
${placeFacts(L.place)}<div class="vm-lh vm-lh2"><h3>Sectors here</h3>${unitSw()}</div><span class="vm-tag">last ${perText()} vs before</span>
<div class="vm-rows vm-srows">${!L.det ? '<p class="vm-mu">Loading</p>' : rows.length ? rows.map((r) => `<button type="button" class="vm-sec vm-secp${L.step === 'firms' && L.sector === r.name ? ' vm-secon' : ''}" data-s="${esc(r.name)}" title="${num(r.n)} deals, ${num(r.p)} before"><i class="${toneCls(r)}"></i><span>${esc(r.name)}</span>${spark(r.line, r.tone)}<span class="vm-pc ${r.tone === 'up' ? 'vm-tu' : r.tone === 'down' ? 'vm-td' : ''}">${figure(r)}</span><span class="vm-fl">${num(r.f)} firm${r.f === 1 ? '' : 's'}</span></button>`).join('') : '<p class="vm-mu">No deals here in this period.</p>'}</div>`;
      $('#vm-close').onclick = closeList; $('#vm-unplace').onclick = closeList; units();
      side.querySelectorAll('.vm-secp').forEach((b) => b.onclick = () => showFirms(b.dataset.s));
      return;
    }
    if (S.list) {  // Money flow works the same way (founder, 25 Nov): the place opens on all its sectors, a sector opens its firms.
      // Words: he approved these four on 25 Nov and nothing else: the place in the title, the sector in the pop-up's title,
      // the button naming what it opens, the % / # switch. Anything more is asked for first.
      const L = S.list, det = L.det, rows = (det || {}).sectors || [], tot = (det && det.tot) || 1;
      const share = (n) => { const v = n / tot * 100; return v > 0 && v < 1 ? '<1%' : Math.round(v) + '%'; };
      side.className = 'vm-card vm-side vm-list';
      side.innerHTML = `<div class="vm-lh vm-lhp"><h2>${esc(L.place.n)} · ${det ? num(det.firms) + ' firm' + (det.firms === 1 ? '' : 's') : 'Loading'}</h2>${unitSw()}<button type="button" class="vm-x" id="vm-close" aria-label="Close list"></button></div>
<div class="vm-rows vm-srows">${rows.map(([name, n, f]) => `<button type="button" class="vm-sec vm-secp vm-secf${L.step === 'firms' && L.sector === name ? ' vm-secon' : ''}" data-s="${esc(name)}" title="${num(n)} deal${n === 1 ? '' : 's'}"><i style="background:${COLORS[name] || COLORS.Other}"></i><span>${esc(name)}</span><span class="vm-pc">${S.unit === 'num' ? num(n) : share(n)}</span><span class="vm-fl">${num(f)} firm${f === 1 ? '' : 's'}</span></button>`).join('')}</div>`;
      $('#vm-close').onclick = closeList; units();
      side.querySelectorAll('.vm-secp').forEach((b) => b.onclick = () => showFirms(b.dataset.s));
      return;
    }
    side.className = 'vm-card vm-side';
    if (S.view === 'hot') {  // sectors heating up and cooling down; click one to see where
      // keep showing every sector while one is chosen: remember the full list from the last unfiltered answer for this period and stage
      const memo = S.days + '|' + S.level + '|' + S.stages.join(','); S.secMemo = S.secMemo || {};
      if (!S.sectors.length && S.data && S.data.sectors) S.secMemo[memo] = S.data.sectors[S.level] || [];
      const mk = ([name, n, p]) => Object.assign({ name, n, p }, toneOf(n, p));
      const rows = (S.secMemo[memo] || ((S.data || {}).sectors || {})[S.level] || []).map(mk).filter((r) => !r.few);
      // with sectors chosen, only those are listed (and a link back to all); otherwise every sector, strongest rise first
      const chosen = S.sectors.length ? sortRows((((S.data || {}).sectors || {})[S.level] || []).map(mk)) : [];
      const others = S.sectors.length ? [] : sortRows(rows), rest = others.length > 12 ? others.slice(0, 6).concat(others.slice(-6)) : others;
      // the small lines arrive in a second, lighter request, so the map never waits for them
      const want = JSON.stringify([S.level, S.days, S.stages, S.sectors, who()]);
      if (S.linesKey !== want && S.linesAsked !== want) {
        S.linesAsked = want;
        detail(null).then((d) => { if (S.linesAsked !== want) return; S.linesKey = want; S.lines = {}; ((d || {}).sectors || []).forEach((r) => { S.lines[r[0]] = r[4]; }); if (S.view === 'hot' && !S.list) drawSide(); });
      }
      const lines = S.linesKey === want ? S.lines : {};
      const line = (r) => `<button type="button" class="vm-sec${S.sectors.includes(r.name) ? ' vm-secon' : ''}" data-s="${esc(r.name)}" title="${num(r.n)} deals, ${num(r.p)} before"><i class="${toneCls(r)}"></i><span>${esc(r.name)}</span>${spark(lines[r.name], r.tone)}<span class="vm-pc ${r.tone === 'up' ? 'vm-tu' : r.tone === 'down' ? 'vm-td' : ''}">${figure(r)}</span></button>`;
      side.innerHTML = `<div class="vm-lh"><h2>Sectors</h2>${unitSw()}</div><span class="vm-tag">last ${perText()} vs before</span>${chosen.map(line).join('')}${S.sectors.length ? '<button type="button" class="vm-link" id="vm-allsec">Show all sectors</button>' : ''}${rest.map(line).join('')}`;
      units();
      side.querySelectorAll('.vm-sec').forEach((b) => b.onclick = () => { S.sectors = S.sectors.includes(b.dataset.s) ? S.sectors.filter((x) => x !== b.dataset.s) : [b.dataset.s]; drawPicks(); refresh().then(drawSide); });
      const all = $('#vm-allsec'); if (all) all.onclick = () => { S.sectors = []; drawPicks(); refresh().then(drawSide); };
      return;
    }
    loadUpdates();  // the zoom buttons redraw without asking the database again, so the updates are asked for from here too
    // What the list is for, under the title: the place and the filters. Nothing on the world view with no filter.
    const few = (a, word) => (a.length > 2 ? a.length + ' ' + word : a.join(', '));
    const upFor = [S.level === 'us' ? 'United States' : S.level === 'eu' ? 'Europe' : '', few(S.sectors, 'sectors'), few(S.stages, 'stages')].filter(Boolean).join(' · ');
    side.classList.toggle('vm-updwait', !FX_UPDATES && S.updKey != null && S.updKey !== updKey());
    side.innerHTML = `<div class="vm-lh"><h2>Latest updates</h2><span class="vm-tag">new rounds</span>${upFor ? `<span class="vm-tag vm-upfor">${esc(upFor)}</span>` : ''}</div>${S.updates.length ? S.updates.map((u, i) => {
      const names = (u.firms || []).map((f) => f.name), who = names.length > 1 && (u.leads > 1 || !u.led) ? names[0] + ' and ' + names[1] : names[0] || '';
      const slug = u.firms && u.firms[0] && u.firms[0].slug;
      return `<a class="${i ? '' : 'vm-first'}" href="${slug ? ROOT + 'vc/' + encodeURIComponent(slug) + '/' : '#'}"><span class="vm-tag">${i ? '' : '<i class="vm-new" title="Newest update: its place is lit up on the map"></i>'}${esc(u.level && u.area && u.level === 'us' ? u.area : u.region || '')} · ${day(u.date)}</span><span class="vm-line" title="${esc(updateLine(u, who))}">${esc(updateLine(u, who))}</span></a>`;
    }).join('') : '<p class="vm-mu">No updates to show yet.</p>'}`;
  }
  // Pathfinders: the most followed firms of the zoom, or of the pressed place (every firm not on the Top 100 list). A row is the rank, the firm's logo
  // (or its initials), its name, the top firms that came after it most, and how many of its startups a Top 100 firm
  // later backed. Which firms have a logo comes from the same list the Investors list uses, asked for once.
  let LOGOS = null;
  function logos() {
    if (LOGOS !== null || !C.flv || FIXTURE) return;
    LOGOS = false;
    fetch(ROOT + 'assets/logos/firms.json?v=' + C.flv).then((r) => r.json()).then((a) => { LOGOS = new Set(a); if (S.view === 'path') drawSide(); }).catch(() => {});
  }
  const ini2 = (s) => String(s || '').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
  function drawPathSide(side) {
    logos();
    const L = S.list, det = L && L.det, rows = L ? ((det || {}).list || []) : (((S.data || {}).lists || {})[S.level] || []);
    side.className = 'vm-card vm-side' + (L ? ' vm-list' : '');
    const head = L
      ? `<div class="vm-lh vm-lhp"><h2>${esc(L.place.n)} · ${det ? num(det.firms) + ' firm' + (det.firms === 1 ? '' : 's') : 'Loading'}</h2><button type="button" class="vm-x" id="vm-close" aria-label="Close list"></button></div>`
      : '<div class="vm-lh"><h2>Most followed</h2><span class="vm-tag">startups followed</span></div>';
    side.innerHTML = head + `<div class="vm-rows vm-pfs">${rows.map(([slug, name, n, tops], i) => `<a class="vm-pf" href="${ROOT}vc/${encodeURIComponent(slug)}/"><span class="vm-pfk">${i + 1}</span>${LOGOS && LOGOS.has(slug) ? `<img class="vm-pfl" alt="" loading="lazy" src="${ROOT}assets/logos/f-${encodeURIComponent(slug)}.png">` : `<span class="vm-pfl vm-pfi">${esc(ini2(name))}</span>`}<span class="vm-pft"><b>${esc(name)}</b><i>${esc((tops || []).map(([t, c]) => t + ' ' + c).join(' · '))}</i></span><span class="vm-pfn">${num(n)}</span></a>`).join('')}${lockedRows(L ? det : S.data, rows.length, L ? (det || {}).firms : (((S.data || {}).totals || {})[S.level] || {}).firms)}</div>`;
    const x = $('#vm-close'); if (x) x.onclick = closeList;
    side.querySelectorAll('[data-unlock]').forEach((b) => { b.onclick = openGate; });
  }

  // ---------- share to unlock (founder, 25 Nov)
  // Until an account has unlocked, the database sends only the first three firms of a list. The rest is drawn as blurred
  // stand-ins (no real names are in the page). Pressing one opens a card: the visitor's personal link, a line to post,
  // "Post on X". The card then waits until X has opened that link (X reads a link when it is posted; /p/<code> notes it),
  // and offers "Sign in". Signed in, the account takes the code and everything locked opens.
  const LINES = ["Side effects may include knowing who you're taking money from. Regretamin.", 'Take one before every investor meeting. Regretamin.',
    'For the relief of investor regret, before it starts. Regretamin.', "'We love founders' is not due diligence. Regretamin."];
  let SH = null, shLine = 0, shWait = false, shPoll = null;
  const anon = () => { try { let a = localStorage.getItem('regretamin.anon'); if (!a) { a = crypto.randomUUID(); localStorage.setItem('regretamin.anon', a); } return a; } catch (e) { return null; } };
  function lockedFirms(d) {  // the firms list behind a place: stand-ins for what the database held back
    if (!d || !d.locked || !Array.isArray(d.firms) || !(d.count > d.firms.length)) return '';
    return Array.from({ length: Math.min(6, d.count - d.firms.length) }, (_, i) => `<a href="#" class="vm-fb" data-unlock aria-label="Unlock the full list"><span><b>${'Firm name here'.slice(0, 9 + (i * 3) % 6)}</b><span class="vm-mu">${12 - i} deals</span><span class="vm-st vm-a"><i></i>Active<span class="vm-mu"> · last deal Nov 1</span></span></span><span class="vm-ck">Check</span></a>`).join('');
  }
  function lockedRows(d, shown, total) {
    if (!d || !d.locked || !(total > shown)) return '';
    return Array.from({ length: Math.min(6, total - shown) }, (_, i) => `<button type="button" class="vm-pf vm-pfb" data-unlock aria-label="Unlock the full list"><span class="vm-pfk">${shown + i + 1}</span><span class="vm-pfl vm-pfi"></span><span class="vm-pft"><b>${'Firm name here'.slice(0, 9 + (i * 3) % 6)}</b><i>Top firm 4 · Another firm 3 · One more 2</i></span><span class="vm-pfn">${9 - i}</span></button>`).join('');
  }
  async function shareState(start) {
    if (!sb || !anon()) return null;
    try { await sb.auth.getSession(); const { data } = await sb.rpc(start ? 'v2_share_start' : 'v2_share_state', { p_anon: anon() }); if (data) SH = data; return data; } catch (e) { return null; }
  }
  function opened() {  // unlocked: forget the short lists and ask again
    clearInterval(shPoll); shPoll = null; shWait = false;
    const ov = document.getElementById('unlock'); if (ov) ov.hidden = true;
    cache.clear(); secCache.clear();
    if (S.view !== 'path') { const L = S.list; if (L && L.step === 'firms') showFirms(L.sector); return; }  // the firms list is asked for again, in full
    const back = S.list && S.list.place;
    refresh().then(() => { if (back && S.view === 'path') openList(back); else drawSide(); });
  }
  function gate() {
    let ov = document.getElementById('unlock');
    if (!ov) { ov = document.createElement('div'); ov.className = 'ov'; ov.id = 'unlock'; document.body.appendChild(ov); }
    const link = SH && SH.code ? location.origin + '/p/' + SH.code : '', line = LINES[shLine % LINES.length];
    const act = !link ? '<button type="button" class="ulk-go" disabled>Loading</button>'
      : SH.seen ? '<button type="button" class="ulk-go" data-open="signup">Sign in</button>'
      : `<a class="ulk-go${shWait ? ' ulk-wait' : ''}" id="ulk-post" target="_blank" rel="noopener" href="https://x.com/intent/post?text=${encodeURIComponent(line)}&url=${encodeURIComponent(link)}">${shWait ? 'Waiting for your post' : 'Post on X'}</a>`;
    ov.innerHTML = `<div class="md ulk" role="dialog" aria-modal="true" aria-label="Post anything on X with your link"><button class="x" data-close aria-label="Close">×</button>
<h3>Post anything on X with your link</h3>
<div class="ulk-l"><span>${esc(link.replace(/^https?:\/\//, ''))}</span><button type="button" id="ulk-copy">Copy</button></div>
<div class="ulk-t"><span>Need a line? Here's one</span><button type="button" id="ulk-next">Another</button></div>
<p class="ulk-p">${esc(line)}</p>${act}</div>`;
    ov.hidden = false;
    const copy = ov.querySelector('#ulk-copy'), next = ov.querySelector('#ulk-next'), post = ov.querySelector('#ulk-post');
    if (copy) copy.onclick = () => { if (link && navigator.clipboard) navigator.clipboard.writeText(link).then(() => { copy.textContent = 'Copied'; setTimeout(() => { copy.textContent = 'Copy'; }, 1500); }, () => {}); };
    if (next) next.onclick = () => { shLine++; gate(); };
    if (post) post.addEventListener('click', () => {  // the link opens X in a new tab; this page starts waiting for X to read the link
      shWait = true; setTimeout(gate, 50);
      if (shPoll) return;
      let n = 0;
      shPoll = setInterval(async () => {
        const s = await shareState(false);
        if (s && s.unlocked) return opened();
        if ((s && s.seen) || ++n > 90) { clearInterval(shPoll); shPoll = null; if (s && s.seen) gate(); }
      }, 4000);
    });
  }
  async function openGate() {
    gate();
    const s = await shareState(true);
    if (s && s.unlocked) return opened();
    gate();
  }
  // The firms behind a place (or one of its sectors) open in a panel of their own, so the sectors stay in view.
  function drawFirms() {
    const fp = $('#vm-fp'), L = S.list;
    if (!(L && L.step === 'firms')) { if (!fp.hidden) { fp.hidden = true; fp.innerHTML = ''; fit(); } return; }
    const tags = [L.place.n].concat(L.sector ? [L.sector] : S.sectors, S.stages);
    if (fp.hidden) { fp.hidden = false; fit(); }
    fp.innerHTML = `<div class="vm-lh"><h2>${L.data ? num(L.data.count) + (S.view !== 'hot' && L.sector ? ' ' + esc(L.sector) : '') + ' firm' + (L.data.count === 1 ? '' : 's') : 'Loading'}</h2><button type="button" class="vm-x" id="vm-fpx" aria-label="Close the firms list"></button></div>
${S.view === 'hot' ? `<div class="vm-chips">${tags.map((x) => `<span class="vm-chip vm-chipst">${esc(x)}</span>`).join('')}</div>` : ''}
<div class="vm-rows">${!L.data ? '' : L.data.firms.map((f) => `<a href="${ROOT}vc/${encodeURIComponent(f.slug)}/"><span><b>${esc(f.name)}</b><span class="vm-mu">${num(f.deals)} deal${f.deals === 1 ? '' : 's'}${f.led ? ' · led ' + num(f.led) : ''}</span><span class="vm-st ${f.status === 'Active' ? 'vm-a' : f.status === 'Low activity' ? 'vm-l' : ''}"><i></i>${esc(f.status)}${f.last ? `<span class="vm-mu"> · last deal ${day(f.last)}</span>` : ''}</span></span><span class="vm-ck">Check</span></a>`).join('')}${lockedFirms(L.data)}</div>
<a class="vm-more" href="${listUrl()}"${L.data && L.data.locked ? ' data-unlock' : ''}>Open the full investors list</a>`;
    $('#vm-fpx').onclick = () => { L.step = 'sectors'; L.sector = null; L.data = null; drawSide(); };
    // locked: the blurred rows and the link to the full list both open the card instead
    fp.querySelectorAll('[data-unlock]').forEach((b) => { b.onclick = (e) => { e.preventDefault(); openGate(); }; });
  }
  async function showFirms(sector) {
    const L = S.list; if (!L) return;
    L.step = 'firms'; L.sector = sector || null; L.data = null; drawSide();
    const d = await firms(L.place, L.sector);
    if (S.list === L && L.step === 'firms' && L.sector === (sector || null)) { L.data = d || { count: 0, firms: [] }; drawFirms(); if (L.data.locked && !S.shAsked2) { S.shAsked2 = true; claim(); setTimeout(claim, 2500); setTimeout(claim, 7000); } }
  }
  async function openList(place) {
    // sectors first, in both views; the firms are one click away (a sector row, or the button in the top card)
    stop(); const L = S.list = { place, step: 'sectors', det: null, sector: null, data: null }; S.pinned = place.p; drawSide(); draw();
    const det = await (S.view === 'hot' ? detail(place) : S.view === 'path' ? pathPlace(place) : placeSectors(place));
    if (S.list === L) { L.det = det || { sectors: [] }; drawSide(); }
  }
  // Coming back to the map: the place that was open opens again, with its firms list if that was showing.
  async function reopen() {
    const b = BACK; BACK = null;
    const row = b && (stage._rows || []).find((r) => String(r.p) === String(b.p));
    if (!row) return;
    await openList(row);
    if (b.step === 'firms' && S.list && S.list.place.p === b.p) showFirms(b.sector);
  }
  function closeList() { if (S.list) { S.list = null; S.pinned = null; drawSide(); draw(); } }

  // ---------- start
  let asked = 0;
  async function refresh() {
    remember();
    if (S.view === 'founders') { if (window.REGRET_FOUNDERS) window.REGRET_FOUNDERS.setSpan(span()); return; }  // Founders counts on the page: nothing to ask for
    if (S.view !== 'hot') loadUpdates();  // asked alongside the map's numbers; does nothing when the pick has not changed
    const mine = ++asked, msg = $('#vm-msg');
    const busy = setTimeout(() => { if (mine === asked) el.classList.add('vm-busy'); }, 120);  // the scan runs only when the answer is not instant
    const d = await summary();
    clearTimeout(busy);
    if (mine !== asked) return;  // a newer question was asked while this one was on its way; drop the old answer
    el.classList.remove('vm-busy');
    if (!d) { msg.hidden = false; msg.textContent = 'The map is not available right now.'; return; }
    msg.hidden = true; S.data = d; draw();
    // Back from signing in, the page can ask before it knows the visitor is signed in: it asks again shortly after, and
    // whenever the sign-in arrives (see below), so the lists open by themselves (he had to press a blurred row, 25 Nov).
    if (S.view === 'path' && d.locked && !S.shAsked) { S.shAsked = true; claim(); setTimeout(claim, 2500); setTimeout(claim, 7000); }
  }
  function claim() {
    const short = S.view === 'path' ? S.data && S.data.locked : S.list && S.list.data && S.list.data.locked;
    if (!short || S.claiming) return;
    S.claiming = true;
    shareState(false).then((s) => { S.claiming = false; if (s && s.unlocked) opened(); }, () => { S.claiming = false; });
  }
  if (sb && sb.auth && sb.auth.onAuthStateChange) sb.auth.onAuthStateChange((ev, session) => { if (session) setTimeout(claim, 0); });
  drawPicks(); drawTime(); drawSide(); marks();
  if (S.view === 'founders') founders();
  // The map's places, its numbers and the latest updates are asked for at the same time, not one after another.
  // draw() does nothing until both the places and the numbers are in, so the order they arrive in does not matter.
  const places = fetch(ROOT + 'assets/map/places.json' + MAPV).then((r) => r.json()).then((g) => { S.geo = g; if (S.view === 'founders') land(); });
  // The side panel is drawn again once the numbers are in: the updates can arrive first and draw it empty.
  Promise.all([places, refresh()]).then(() => { draw(); if (!S.list) drawSide(); reopen(); });
  loadUpdates();
})();
