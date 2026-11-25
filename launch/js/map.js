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
    if ([90, 180, 365].includes(num('days'))) S.days = num('days');
    if (['us', 'eu'].includes(qs.get('zoom'))) S.level = qs.get('zoom');
    S.sectors = list('sectors', SECTORS); S.stages = list('stages', STAGES);
    if (WHO.some(([k]) => k === whoKey(qs.get('firms')))) S.who = whoKey(qs.get('firms'));
    const a = num('from'), b = num('to'); if (a !== null && b !== null && a <= b && b < NQ) { S.q0 = a; S.q1 = b; }
    // No view in the address: come back to the map as it was left in this tab (after opening a firm and closing it, say).
    if (['view', 'days', 'zoom', 'sectors', 'stages', 'firms', 'from', 'to'].some((k) => qs.has(k))) return;
    try {
      const m = JSON.parse(sessionStorage.getItem(KEEP) || 'null');
      if (!m) return;
      if (m.view === 'hot' || m.view === 'flow' || m.view === 'founders') S.view = m.view;
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
    const { data, error } = await sb.rpc('v2_map_firms', Object.assign({ p_level: S.level, p_place: place.p }, win, who() !== 'all' ? { p_firms: who() } : {}));
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
<div class="vm-map" id="vm-map"><div class="vm-stage" id="vm-stage"><img class="vm-bg" id="vm-bg" alt=""><div class="vm-wave" id="vm-wave"></div><div id="vm-pls"></div><div id="vm-labs"></div></div><div class="vm-tip" id="vm-tip" hidden></div></div>
<div class="vm-colwrap"><section class="vm-card vm-head" aria-live="polite"><h1 id="vm-h1"></h1>
  <div class="vm-picks"><div class="vm-pick" data-pick="sectors"></div><div class="vm-pick" data-pick="stages"></div><div class="vm-pick vm-who" data-pick="who"></div></div>
  <p class="vm-based" id="vm-based"></p><a class="vm-btn" id="vm-cta" href="${ROOT}investors/">See the investors</a></section>
<aside class="vm-card vm-side" id="vm-side"></aside></div>
<aside class="vm-card vm-fp" id="vm-fp" aria-label="Firms" hidden></aside>
<div class="vm-card vm-views" role="group" aria-label="View"><button type="button" data-view="flow">Money flow</button><button type="button" data-view="hot">Hot right now</button><button type="button" data-view="founders">Founders</button></div>
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
    $('#vm-play').classList.toggle('vm-on', !!S.playing); $('#vm-play').setAttribute('aria-label', S.playing ? 'Pause' : 'Play');
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
  function stop() { if (S.playing) { S.playing = null; drawTime(); } }
  $('#vm-play').addEventListener('click', async () => {
    if (S.playing) return stop();
    closeList(); if (S.q1 >= NQ - 1) S.q1 = S.q0;  // play grows the range one quarter at a time, from the left handle
    const run = S.playing = {};
    drawTime(); await refresh();
    // One step at a time: wait for the numbers, show them, pause, then move on. Never ahead of the data.
    while (S.playing === run && S.q1 < NQ - 1) {
      await new Promise((r) => setTimeout(r, 450));
      if (S.playing !== run) return;
      S.q1 += 1; drawTime(); await refresh();
    }
    if (S.playing === run) stop();
  });

  // ---------- zoom
  el.querySelectorAll('[data-level]').forEach((b) => b.addEventListener('click', () => setLevel(b.dataset.level)));
  // ---------- views: Money flow (rings) and Hot right now (what is speeding up or slowing down)
  el.querySelectorAll('[data-view]').forEach((b) => b.addEventListener('click', () => setView(b.dataset.view)));
  el.querySelectorAll('[data-days]').forEach((b) => b.addEventListener('click', () => { S.days = +b.dataset.days; S.list = null; S.pinned = null; marks(); refresh().then(drawSide); }));
  function marks() {
    el.classList.toggle('vm-hotview', S.view === 'hot');
    el.classList.toggle('vm-fview', S.view === 'founders');
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
  function founders() { land(); const F = window.REGRET_FOUNDERS; if (F) F.show({ el, sb, root: ROOT, mapv: MAPV, level: S.level, span: span() }); }
  function setView(v) {
    if (v === S.view) return;
    stop(); S.view = v; S.list = null; S.pinned = null; marks();
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
    S.list = null; S.pinned = null; S.level = l; land(); draw(from); drawSide();
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
    S.k = k; S.ox = l + (r.width - l - rt - g.w * k) / 2; S.oy = t; S.boxW = r.width; S.boxH = r.height;
    stage.style.width = g.w + 'px'; stage.style.height = g.h + 'px';
    stage.style.transform = `translate(${l + (r.width - l - rt - g.w * k) / 2}px, ${t}px) scale(${k})`;
  }
  window.addEventListener('resize', fit);
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
  const litPlace = () => { const u = S.updates[0]; return !u || S.view === 'hot' ? null : S.level === 'world' ? u.region : u.level === S.level ? (FOLD[u.area] || u.area) : null; };
  const placesNow = () => {
    const g = S.geo[S.level].places, sector = S.sectors.length > 0;
    const rows = (S.data.places || []).filter((p) => p.l === S.level && g[p.p] && !FOLD[p.p]).map((p) => Object.assign({}, p, g[p.p], { n: g[p.p].n || p.p }));
    const max = Math.max(1, ...rows.map((p) => p.d)), hot = S.view === 'hot';
    rows.forEach((p) => {
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
    // On the US and Europe maps the smallest places are left out so the map stays readable. With narrow filters that
    // could leave it empty while the sector list still shows deals, so when few circles remain the next largest come back.
    if (hot && S.level !== 'world' && rows.filter((p) => p.kind).length < 8) {
      rows.filter((p) => !p.kind && p.d + p.pv > 0).sort((a, b) => (b.d + b.pv) - (a.d + a.pv)).slice(0, 15 - rows.filter((p) => p.kind).length).forEach((p) => { p.kind = 'hot'; });
    }
    const out = rows.filter((p) => p.kind), big = out.filter((p) => p.kind !== 'dot');
    for (let it = 0; it < 80; it++) {  // nudge overlapping circles apart, keeping each close to its true spot
      for (let i = 0; i < big.length; i++) for (let j = i + 1; j < big.length; j++) {
        const a = big[i], b = big[j], dx = b.x - a.x, dy = b.y - a.y, d = Math.hypot(dx, dy) || 0.01, need = a.r + b.r + 3;
        if (d < need) { const m = (need - d) / 2, wa = b.r / (a.r + b.r), wb = 1 - wa; a.x -= dx / d * m * 2 * wa; a.y -= dy / d * m * 2 * wa; b.x += dx / d * m * 2 * wb; b.y += dy / d * m * 2 * wb; }
      }
      big.forEach((p) => { p.x += (p.ax - p.x) * 0.06; p.y += (p.ay - p.y) * 0.06; });
    }
    // a small dot that would sit on top of a ring is left out (its firms are still in that ring's neighbourhood list)
    return out.filter((p) => p.kind !== 'dot' || !big.some((b) => Math.hypot(b.x - p.x, b.y - p.y) < b.r + 8)).sort((a, b) => (a.kind === 'dot') - (b.kind === 'dot') || b.d - a.d);
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
      b.dataset.i = i; b.setAttribute('aria-label', `${p.n}: ${num(p.d)} deals, ${num(p.f)} firms`);
      b.style.left = p.x - p.r + 'px'; b.style.top = p.y - p.r + 'px'; b.style.width = b.style.height = p.r * 2 + 'px';
      if (p.kind === 'ring') { b.style.backgroundColor = ''; setSlices(b, p); }
      else if (p.kind === 'hot') b.style.backgroundColor = '';
      else b.style.backgroundColor = p.kind === 'plain' ? (S.sectors.length === 1 ? COLORS[S.sectors[0]] : '#C9D1CE') : (COLORS[(p.top && p.top[0] && p.top[0][0])] || '#C9D1CE');
      // label: below, else above, else right, else left; dropped if nothing fits
      const sub = p.kind === 'hot' ? (S.level === 'world' ? toneText(p) + (hotOf(p) && p.tone !== 'few' ? ' · ' + hotOf(p)[0] : '') : num(p.d) + ' · ' + toneText(p)) : num(p.d) + (S.level === 'world' && !sector && p.so ? ' · ' + p.so : ''), small = p.kind === 'dot';
      const w = Math.max(p.n.length * (small ? 5.6 : 6.6), small ? 0 : sub.length * 5.9) + 8, h = small ? 14 : 30;
      const tries = small ? [[p.x + p.r + 6, p.y - 7, 'l'], [p.x - p.r - 6 - w, p.y - 7, 'r']] : [[p.x - w / 2, p.y + p.r + 2, 'c'], [p.x - w / 2, p.y - p.r - h - 2, 'c'], [p.x + p.r + 4, p.y - h / 2, 'l'], [p.x - p.r - 4 - w, p.y - h / 2, 'r'],
        [p.x + p.r * 0.7 + 2, p.y + p.r * 0.7, 'l'], [p.x - p.r * 0.7 - 2 - w, p.y + p.r * 0.7, 'r'], [p.x + p.r * 0.7 + 2, p.y - p.r * 0.7 - h, 'l'], [p.x - p.r * 0.7 - 2 - w, p.y - p.r * 0.7 - h, 'r']];
      let placed = false;
      for (const [x, y, al] of tries) {
        const bx = { x0: x, y0: y, x1: x + w, y1: y + h };
        if (!hit(bx)) { boxes.push(bx); placed = true; labs += `<span class="vm-lab ${small ? 'vm-sm' : ''}" style="left:${x}px;top:${y}px;width:${w}px;text-align:${al === 'c' ? 'center' : al === 'l' ? 'left' : 'right'}">${esc(p.n)}${small ? ' ' + num(p.d) : `<br><em>${p.kind === 'hot' ? (S.level === 'world' ? toneHtml(p) + (hotOf(p) && p.tone !== 'few' ? ' · ' + esc(hotOf(p)[0]) : '') : num(p.d) + ' · ' + toneHtml(p)) : esc(sub)}</em>`}</span>`; break; }
      }
      // No room for the full name (crowded Europe): fall back to the two-letter country code, beside the ring if it fits, else in its centre.
      if (!placed && S.level === 'eu' && !small) {
        const cw = 20, ch = 13, spots = [[p.x - cw / 2, p.y + p.r + 1], [p.x - cw / 2, p.y - p.r - ch - 1], [p.x + p.r + 2, p.y - ch / 2], [p.x - p.r - 2 - cw, p.y - ch / 2]];
        let done = false;
        for (const [x, y] of spots) {
          const bx = { x0: x, y0: y, x1: x + cw, y1: y + ch };
          if (!hit(bx)) { boxes.push(bx); done = true; labs += `<span class="vm-lab vm-code" title="${esc(p.n)}" style="left:${x}px;top:${y}px;width:${cw}px">${esc(p.p)}</span>`; break; }
        }
        if (!done) labs += `<span class="vm-lab vm-code vm-code-in" title="${esc(p.n)}" style="left:${p.x - cw / 2}px;top:${p.y - ch / 2}px;width:${cw}px">${esc(p.p)}</span>`;
      }
    });
    els.forEach((b, key) => { if (!seen.has(key)) { els.delete(key); b.classList.add('vm-out'); setTimeout(() => b.remove(), 850); } });
    const lb = $('#vm-labs'); lb.className = from ? 'vm-late' : ''; lb.innerHTML = labs;
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
    if (S.view === 'hot') {
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
  stage.addEventListener('click', (e) => {
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
    $('#vm-h1').textContent = sec ? `Where ${sec} ${S.sectors.length === 1 && !PLURAL.includes(S.sectors[0]) ? 'is' : 'are'} heating up${where}.` : `Where it is heating up${where}.`;
    S.countId = (S.countId || 0) + 1; S.shown = null;
    $('#vm-based').textContent = '';  // no text under the filters in this view (founder); a question mark may come later
    const note = whoNote();
    $('#vm-legend').innerHTML = note ? `<span class="vm-whonote"><b>${esc(WHO.find(([k]) => k === who())[1])}</b><span>${esc(note)}</span></span>` : '<span class="vm-keys"><span><i class="vm-up"></i>up 10% or more</span><span><i class="vm-flat"></i>steady</span><span><i class="vm-down"></i>down 10% or more</span><span><i class="vm-few"></i>too few to call</span></span>';
  }
  function drawHead() {
    if (S.view === 'hot') return drawHotHead();
    const where = S.level === 'us' ? ' in the US' : S.level === 'eu' ? ' in Europe' : '', t = (S.data.totals || {})[S.level] || { deals: 0, firms: 0 };
    const sec = S.sectors.length === 1 ? inSentence(S.sectors[0]) : S.sectors.length ? 'these sectors' : '';
    $('#vm-h1').textContent = sec ? `Who backs ${sec}${where}.` : S.level === 'us' ? 'What US investors are backing.' : S.level === 'eu' ? 'What European investors are backing.' : 'What VCs are investing in.';
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
    if (S.list) {  // Money flow works the same way (founder, 25 Nov): the place opens on all its sectors, a sector opens its firms
      const L = S.list, det = L.det, rows = (det || {}).sectors || [], tot = (det && det.tot) || 1, p = L.place;
      const share = (n) => { const v = n / tot * 100; return v > 0 && v < 1 ? '<1%' : Math.round(v) + '%'; };
      side.className = 'vm-card vm-side vm-list';
      side.innerHTML = `<div class="vm-lh"><div class="vm-chips"><button type="button" class="vm-chip" id="vm-unplace" aria-label="Remove filter ${esc(p.n)}">${esc(p.n)}<span aria-hidden="true">×</span></button></div><button type="button" class="vm-x" id="vm-close" aria-label="Close"></button></div>
<div class="vm-facts"><span class="vm-mu">${num(p.d)} deal${p.d === 1 ? '' : 's'}${!S.sectors.length && p.so ? ` · stands out for <b>${esc(p.so)}</b>` : ''}</span></div><div class="vm-lh vm-lh2"><h3>Sectors here</h3>${unitSw()}</div><span class="vm-tag">${S.unit === 'num' ? 'deals' : 'share of deals'}</span>
<div class="vm-rows vm-srows">${!det ? '<p class="vm-mu">Loading</p>' : rows.length ? rows.map(([name, n, f]) => `<button type="button" class="vm-sec vm-secp vm-secf${L.step === 'firms' && L.sector === name ? ' vm-secon' : ''}" data-s="${esc(name)}" title="${num(n)} deal${n === 1 ? '' : 's'}"><i style="background:${COLORS[name] || COLORS.Other}"></i><span>${esc(name)}</span><span class="vm-pc">${S.unit === 'num' ? num(n) : share(n)}</span><span class="vm-fl">${num(f)} firm${f === 1 ? '' : 's'}</span></button>`).join('') : '<p class="vm-mu">No deals here in this period.</p>'}</div>`;
      $('#vm-close').onclick = closeList; $('#vm-unplace').onclick = closeList; units();
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
  // The firms behind a place (or one of its sectors) open in a panel of their own, so the sectors stay in view.
  function drawFirms() {
    const fp = $('#vm-fp'), L = S.list;
    if (!(L && L.step === 'firms')) { if (!fp.hidden) { fp.hidden = true; fp.innerHTML = ''; fit(); } return; }
    const tags = [L.place.n].concat(L.sector ? [L.sector] : S.sectors, S.stages);
    if (fp.hidden) { fp.hidden = false; fit(); }
    fp.innerHTML = `<div class="vm-lh"><h2>${L.data ? num(L.data.count) + ' firm' + (L.data.count === 1 ? '' : 's') : 'Loading'}</h2><button type="button" class="vm-x" id="vm-fpx" aria-label="Close the firms list"></button></div>
<div class="vm-chips">${tags.map((x) => `<span class="vm-chip vm-chipst">${esc(x)}</span>`).join('')}</div>
<div class="vm-rows">${!L.data ? '' : L.data.firms.map((f) => `<a href="${ROOT}vc/${encodeURIComponent(f.slug)}/"><span><b>${esc(f.name)}</b><span class="vm-mu">${num(f.deals)} deal${f.deals === 1 ? '' : 's'}${f.led ? ' · led ' + num(f.led) : ''}</span><span class="vm-st ${f.status === 'Active' ? 'vm-a' : f.status === 'Low activity' ? 'vm-l' : ''}"><i></i>${esc(f.status)}${f.last ? `<span class="vm-mu"> · last deal ${day(f.last)}</span>` : ''}</span></span><span class="vm-ck">Check</span></a>`).join('')}</div>
<a class="vm-more" href="${listUrl()}">Open the full investors list</a>`;
    $('#vm-fpx').onclick = () => { L.step = 'sectors'; L.sector = null; L.data = null; drawSide(); };
  }
  async function showFirms(sector) {
    const L = S.list; if (!L) return;
    L.step = 'firms'; L.sector = sector || null; L.data = null; drawSide();
    const d = await firms(L.place, L.sector);
    if (S.list === L && L.step === 'firms' && L.sector === (sector || null)) { L.data = d || { count: 0, firms: [] }; drawFirms(); }
  }
  async function openList(place) {
    // sectors first, in both views; the firms are one click away (a sector row, or the button in the top card)
    stop(); const L = S.list = { place, step: 'sectors', det: null, sector: null, data: null }; S.pinned = place.p; drawSide(); draw();
    const det = await (S.view === 'hot' ? detail(place) : placeSectors(place));
    if (S.list === L) { L.det = det || { sectors: [] }; drawSide(); }
  }
  // Coming back to the map: the place that was open opens again, with its firms list if that was showing.
  async function reopen() {
    const b = BACK; BACK = null;
    const row = b && (stage._rows || []).find((r) => r.p === b.p);
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
  }
  drawPicks(); drawTime(); drawSide(); marks();
  if (S.view === 'founders') founders();
  // The map's places, its numbers and the latest updates are asked for at the same time, not one after another.
  // draw() does nothing until both the places and the numbers are in, so the order they arrive in does not matter.
  const places = fetch(ROOT + 'assets/map/places.json' + MAPV).then((r) => r.json()).then((g) => { S.geo = g; if (S.view === 'founders') land(); });
  // The side panel is drawn again once the numbers are in: the updates can arrive first and draw it empty.
  Promise.all([places, refresh()]).then(() => { draw(); if (!S.list) drawSide(); reopen(); });
  loadUpdates();
})();
