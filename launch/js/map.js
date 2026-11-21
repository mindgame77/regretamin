// The map page (/map/). Reads four read-only database functions: v2_map_summary, v2_map_firms, v2_map_updates
// and, for the 'Hot right now' view, v2_map_hot (docs/map_hot_function.sql).
// (docs/map_functions.sql). Rules it follows are in the project doc claude/plans/main-map.md.
// No data is invented here: if the functions are missing, the page says the map is not available.
(function () {
  const el = document.getElementById('vm');
  if (!el) return;
  const C = window.REGRET || {}, ROOT = window.REGRET_ROOT || '';
  const sb = C.url && C.key && window.supabase ? window.supabase.createClient(C.url, C.key) : null;
  const qs = new URLSearchParams(location.search);
  // Local preview only: ?fixture=<saved v2_map_summary answer>&fx_firms=<saved v2_map_firms>&fx_updates=<saved v2_map_updates>.
  // Ignored on any real host.
  const LOCAL = /^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname);
  const FIXTURE = LOCAL ? qs.get('fixture') : null;
  const FX_FIRMS = FIXTURE && qs.get('fx_firms'), FX_UPDATES = FIXTURE && qs.get('fx_updates'), FX_HOT = FIXTURE && qs.get('fx_hot');

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
  const HOT_MIN = 40;  // 'Hot right now': a place needs this many deals across both periods before it gets a colour
  const RING_DEALS = 150, RING_FIRMS = 5, DOT_DEALS = 30;  // zoomed views only; the world view always draws rings
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  const now = new Date();
  const NQ = (now.getFullYear() - 2021) * 4 + Math.floor(now.getMonth() / 3) + 1;  // quarters from 2021 Q1 to this one
  const S = { view: 'flow', days: 90, level: 'world', q0: 0, q1: NQ - 1, stages: [], sectors: [], pinned: null, list: null, data: null, geo: null, updates: [], playing: null };
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
    const a = hot ? { p_days: S.days, p_stages: S.stages.length ? S.stages : null, p_sectors: S.sectors.length ? S.sectors : null } : args(), key = S.view + JSON.stringify(a);
    if (cache.has(key)) return cache.get(key);
    let out = null;
    if (FIXTURE) out = hot ? (FX_HOT ? await fetch(FX_HOT).then((r) => r.json()) : null) : await fetch(FIXTURE).then((r) => r.json());
    else if (sb) { const { data, error } = await sb.rpc(hot ? 'v2_map_hot' : 'v2_map_summary', a); if (!error) out = data; }
    if (out) cache.set(key, out);
    return out;
  }
  async function firms(place) {
    if (FX_FIRMS) return fetch(FX_FIRMS).then((r) => r.json());
    if (FIXTURE || !sb) return null;
    // in the 'Hot right now' view the list covers the same recent period the map is showing
    const win = S.view === 'hot' ? { p_from: iso(new Date(now.getFullYear(), now.getMonth(), now.getDate() - S.days + 1)), p_to: iso(now), p_stages: S.stages.length ? S.stages : null, p_sectors: S.sectors.length ? S.sectors : null } : args();
    const { data, error } = await sb.rpc('v2_map_firms', Object.assign({ p_level: S.level, p_place: place.p }, win));
    return error ? null : data;
  }
  async function loadUpdates() {
    let data = null;
    if (FX_UPDATES) data = await fetch(FX_UPDATES).then((r) => r.json());
    else if (!FIXTURE && sb) { const r = await sb.rpc('v2_map_updates', { p_limit: COL ? 6 : 3 }); if (!r.error) data = r.data; }
    if (Array.isArray(data)) { S.updates = data.slice(0, COL ? 6 : 3); drawSide(); draw(); }
  }

  // ---------- page shell
  el.innerHTML = `
<div class="vm-map" id="vm-map"><div class="vm-stage" id="vm-stage"><img class="vm-bg" id="vm-bg" alt=""><div class="vm-wave" id="vm-wave"></div><div id="vm-pls"></div><div id="vm-labs"></div></div><div class="vm-tip" id="vm-tip" hidden></div></div>
<div class="vm-colwrap"><section class="vm-card vm-head" aria-live="polite"><h1 id="vm-h1"></h1>
  <div class="vm-picks"><div class="vm-pick" data-pick="sectors"></div><div class="vm-pick" data-pick="stages"></div></div>
  <p class="vm-based" id="vm-based"></p><a class="vm-btn" id="vm-cta" href="${ROOT}investors/">See the investors</a></section>
<aside class="vm-card vm-side" id="vm-side"></aside></div>
<div class="vm-card vm-views" role="group" aria-label="View"><button type="button" data-view="flow">Money flow</button><button type="button" data-view="hot">Hot right now</button></div>
<div class="vm-card vm-zoom" role="group" aria-label="Zoom to">${LEVELS.map(([k, t]) => `<button type="button" data-level="${k}">${t}</button>`).join('')}</div>
<div class="vm-card vm-dock"><div class="vm-period" role="group" aria-label="Compare"><span>Compare the last</span>${[[90, '90 days'], [180, '180 days'], [365, 'year']].map(([d, t]) => `<button type="button" data-days="${d}">${t}</button>`).join('')}<span>with the same time before</span></div><button type="button" class="vm-play" id="vm-play" aria-label="Play"></button><button type="button" class="vm-all" id="vm-all">All years</button>
  <div class="vm-time"><div class="vm-track"><div class="vm-fill" id="vm-fill"></div>${Array.from({ length: NQ + 1 }, (_, i) => `<i class="${i % 4 ? '' : 'vm-y'}" style="left:${i / NQ * 100}%"></i>`).join('')}
    <input type="range" id="vm-q0" min="0" max="${NQ}" step="1" aria-label="From quarter"><input type="range" id="vm-q1" min="0" max="${NQ}" step="1" aria-label="To quarter"></div>
    <div class="vm-years">${Array.from({ length: Math.ceil(NQ / 4) }, (_, i) => `<span style="left:${i * 4 / NQ * 100}%;width:${Math.min(4, NQ - i * 4) / NQ * 100}%">${2021 + i}</span>`).join('')}</div></div></div>
<p class="vm-legend" id="vm-legend"></p>
<div class="vm-msg" id="vm-msg" hidden></div>`;
  const stage = $('#vm-stage'), mapBox = $('#vm-map');

  // ---------- filters (two pop-up lists of checkboxes)
  function drawPicks() {
    [['sectors', SECTORS, 'All sectors'], ['stages', STAGES, 'All stages']].forEach(([k, all, none]) => {
      const box = $(`[data-pick="${k}"]`), on = S[k], open = box.classList.contains('vm-open');
      const label = on.length === 0 ? none : on.length === 1 ? on[0] : on.length + ' ' + k;
      box.innerHTML = `<button type="button" class="vm-pickbtn" aria-haspopup="true" aria-expanded="${open}">${esc(label)}<svg aria-hidden="true" width="10" height="6" viewBox="0 0 10 6"><path d="M1 1l4 4 4-4" fill="none" stroke="${INK}" stroke-width="1.6"/></svg></button>
<div class="vm-menu" ${open ? '' : 'hidden'}><label><input type="checkbox" data-v="" ${on.length ? '' : 'checked'}>${none}</label>${all.map((v) => `<label><input type="checkbox" data-v="${esc(v)}" ${on.includes(v) ? 'checked' : ''}>${k === 'sectors' ? `<span class="vm-sw" style="background:${COLORS[v]}"></span>` : ''}${esc(v)}</label>`).join('')}</div>`;
    });
  }
  el.addEventListener('click', (e) => {
    const pb = e.target.closest('.vm-pickbtn');
    el.querySelectorAll('.vm-pick.vm-open').forEach((b) => { if (!pb || b !== pb.parentNode) { b.classList.remove('vm-open'); if (!e.target.closest('.vm-menu')) drawPicks(); } });
    if (pb) { pb.parentNode.classList.toggle('vm-open'); drawPicks(); }
  });
  el.addEventListener('change', (e) => {
    const cb = e.target.closest('.vm-menu input'); if (!cb) return;
    const k = cb.closest('.vm-pick').dataset.pick, v = cb.dataset.v;
    S[k] = !v ? [] : cb.checked ? S[k].concat(v) : S[k].filter((x) => x !== v);
    closeList(); drawPicks(); refresh();
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
  }
  let timer = null;
  const later = () => { clearTimeout(timer); timer = setTimeout(refresh, 180); };
  q0.addEventListener('input', () => { stop(); S.q0 = Math.min(+q0.value, S.q1); closeList(); drawTime(); later(); });
  q1.addEventListener('input', () => { stop(); S.q1 = Math.max(+q1.value - 1, S.q0); closeList(); drawTime(); later(); });
  $('#vm-all').addEventListener('click', () => { stop(); S.q0 = 0; S.q1 = NQ - 1; closeList(); drawTime(); refresh(); });
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
    el.querySelectorAll('[data-view]').forEach((b) => b.setAttribute('aria-pressed', b.dataset.view === S.view));
    el.querySelectorAll('[data-days]').forEach((b) => b.setAttribute('aria-pressed', +b.dataset.days === S.days));
  }
  function setView(v) { if (v === S.view) return; stop(); S.view = v; S.list = null; S.pinned = null; marks(); refresh().then(drawSide); }
  function setLevel(l) {
    if (l === S.level) return;
    // Zooming in from the world: remember where the parent regions sit on the page, so their places can fly out of them.
    let from = null;
    if (S.level === 'world' && stage._rows) {
      from = {}; stage._rows.forEach((p) => { if (ZOOM[p.p] === l) from[p.p] = { x: S.ox + p.x * S.k, y: S.oy + p.y * S.k }; });
    }
    S.list = null; S.pinned = null; S.level = l; draw(from); drawSide();
  }

  // ---------- drawing the map
  // Room each view leaves for the cards around it: [left, right, top, bottom] in page pixels.
  const ROOM = COL ? { world: [16, 16, 84, 104], us: [24, 24, 96, 120], eu: [24, 24, 62, 100] }
    : { world: [20, 20, 62, 60], us: [340, 220, 120, 120], eu: [210, 210, 30, 105] };
  function fit() {
    const g = S.geo && S.geo[S.level]; if (!g) return;
    const r = mapBox.getBoundingClientRect(), [l, rt, t, b] = ROOM[S.level];
    const k = Math.max(0.4, Math.min((r.width - l - rt) / g.w, (r.height - t - b) / g.h));
    S.k = k; S.ox = l + (r.width - l - rt - g.w * k) / 2; S.oy = t; S.boxW = r.width; S.boxH = r.height;
    stage.style.width = g.w + 'px'; stage.style.height = g.h + 'px';
    stage.style.transform = `translate(${l + (r.width - l - rt - g.w * k) / 2}px, ${t}px) scale(${k})`;
  }
  window.addEventListener('resize', fit);
  // Guernsey, Jersey and the Isle of Man are registration addresses, not places a founder would look for: they get no dot
  // of their own (their deals stay in Europe's totals), and an update from one lights up the United Kingdom.
  const FOLD = { GG: 'GB', JE: 'GB', IM: 'GB' };
  const toneText = (p) => p.tone === 'few' ? 'too few to call' : p.tone === 'up' ? 'up ' + p.pct + '%' : p.tone === 'down' ? 'down ' + (-p.pct) + '%' : 'steady';
  const litPlace = () => { const u = S.updates[0]; return !u || S.view === 'hot' ? null : S.level === 'world' ? u.region : u.level === S.level ? (FOLD[u.area] || u.area) : null; };
  const placesNow = () => {
    const g = S.geo[S.level].places, sector = S.sectors.length > 0;
    const rows = (S.data.places || []).filter((p) => p.l === S.level && g[p.p] && !FOLD[p.p]).map((p) => Object.assign({}, p, g[p.p], { n: g[p.p].n || p.p }));
    const max = Math.max(1, ...rows.map((p) => p.d)), hot = S.view === 'hot';
    rows.forEach((p) => {
      if (hot) {  // one plain circle per place, coloured by whether deal-making there is speeding up or slowing down
        p.pv = p.pv || 0; p.few = p.d + p.pv < HOT_MIN; p.pct = p.pv ? Math.round((p.d - p.pv) / p.pv * 100) : null;
        p.tone = p.few || p.pct == null ? 'few' : p.pct >= 10 ? 'up' : p.pct <= -10 ? 'down' : 'flat';
        p.kind = S.level === 'world' || p.d + p.pv >= 10 ? 'hot' : null;
        p.r = S.level === 'world' ? Math.round(14 + 26 * Math.sqrt(p.d / max)) : Math.round(8 + 28 * Math.sqrt(p.d / max));
        p.ax = p.x; p.ay = p.y; return;
      }
      p.kind = sector ? (S.sectors.length > 1 ? 'ring' : 'plain') : (S.level === 'world' || (p.d >= RING_DEALS && p.f >= RING_FIRMS)) ? 'ring' : p.d >= DOT_DEALS ? 'dot' : null;
      p.r = p.kind === 'dot' ? 6 : S.level === 'world' ? Math.round(18 + 20 * Math.pow(p.d / max, 0.6)) : sector ? Math.round(7 + 30 * Math.sqrt(p.d / max)) : S.level === 'eu' ? Math.round(11 + 27 * Math.sqrt(p.d / max)) : Math.round(14 + 26 * Math.sqrt(p.d / max));
      p.ax = p.x; p.ay = p.y;
    });
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
  function draw(from) {  // from: where the new circles fly out of when zooming in ({ parentPlace: {x, y} } in page pixels)
    if (!S.data || !S.geo) return;
    const g = S.geo[S.level], rows = placesNow(), lit = litPlace(), sector = S.sectors.length > 0;
    const bg = $('#vm-bg'), pls = $('#vm-pls'), src = `${ROOT}assets/map/${S.level}.svg`;
    if (bg.dataset.l !== S.level) {
      bg.dataset.l = S.level; bg.style.opacity = 0; bg.onload = () => { bg.style.opacity = 1; };
      bg.src = src; bg.width = g.w; bg.height = g.h;
      $('#vm-wave').style.webkitMaskImage = $('#vm-wave').style.maskImage = `url(${src})`;
      els.forEach((b) => b.remove()); els.clear();
    }
    fit();
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
      b.className = `vm-pl vm-${p.kind}${p.kind === 'hot' ? ' vm-' + p.tone : ''}${lit === p.p ? ' vm-lit' : ''}${S.pinned === p.p ? ' vm-sel' : ''}${b.classList.contains('vm-in') ? ' vm-in' : ''}`;
      b.dataset.i = i; b.setAttribute('aria-label', `${p.n}: ${num(p.d)} deals, ${num(p.f)} firms`);
      b.style.left = p.x - p.r + 'px'; b.style.top = p.y - p.r + 'px'; b.style.width = b.style.height = p.r * 2 + 'px';
      if (p.kind === 'ring') { b.style.backgroundColor = ''; setSlices(b, p); }
      else if (p.kind === 'hot') b.style.backgroundColor = '';
      else b.style.backgroundColor = p.kind === 'plain' ? (S.sectors.length === 1 ? COLORS[S.sectors[0]] : '#C9D1CE') : (COLORS[(p.top && p.top[0] && p.top[0][0])] || '#C9D1CE');
      // label: below, else above, else right, else left; dropped if nothing fits
      const sub = p.kind === 'hot' ? (S.level === 'world' ? toneText(p) + (p.hot && p.tone !== 'few' ? ' · ' + p.hot[0] : '') : num(p.d) + ' · ' + toneText(p)) : num(p.d) + (S.level === 'world' && !sector && p.so ? ' · ' + p.so : ''), small = p.kind === 'dot';
      const w = Math.max(p.n.length * (small ? 5.6 : 6.6), small ? 0 : sub.length * 5.9) + 8, h = small ? 14 : 30;
      const tries = small ? [[p.x + p.r + 6, p.y - 7, 'l'], [p.x - p.r - 6 - w, p.y - 7, 'r']] : [[p.x - w / 2, p.y + p.r + 2, 'c'], [p.x - w / 2, p.y - p.r - h - 2, 'c'], [p.x + p.r + 4, p.y - h / 2, 'l'], [p.x - p.r - 4 - w, p.y - h / 2, 'r'],
        [p.x + p.r * 0.7 + 2, p.y + p.r * 0.7, 'l'], [p.x - p.r * 0.7 - 2 - w, p.y + p.r * 0.7, 'r'], [p.x + p.r * 0.7 + 2, p.y - p.r * 0.7 - h, 'l'], [p.x - p.r * 0.7 - 2 - w, p.y - p.r * 0.7 - h, 'r']];
      let placed = false;
      for (const [x, y, al] of tries) {
        const bx = { x0: x, y0: y, x1: x + w, y1: y + h };
        if (!hit(bx)) { boxes.push(bx); placed = true; labs += `<span class="vm-lab ${small ? 'vm-sm' : ''}" style="left:${x}px;top:${y}px;width:${w}px;text-align:${al === 'c' ? 'center' : al === 'l' ? 'left' : 'right'}">${esc(p.n)}${small ? ' ' + num(p.d) : `<br><em>${esc(sub)}</em>`}</span>`; break; }
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
      const per = S.days === 365 ? 'year' : S.days + ' days';
      t.innerHTML = `<b>${esc(p.n)}</b><span class="vm-mu">${num(p.d)} deal${p.d === 1 ? '' : 's'} in the last ${per} · ${toneText(p)}${p.tone === 'few' ? '' : ` (${num(p.pv)} before)`}</span>${p.hot ? `<span>Heating up: <b>${esc(p.hot[0])}</b> <span class="vm-pc">${num(p.hot[1])} vs ${num(p.hot[2])}</span></span>` : ''}${p.cold ? `<span>Cooling down: <b>${esc(p.cold[0])}</b> <span class="vm-pc">${num(p.cold[1])} vs ${num(p.cold[2])}</span></span>` : ''}`;
    } else {
    const tot = p.tot || 1, sector = S.sectors.length > 0, top = p.top || [], rest = Math.max(0, 100 - top.reduce((a, [, v]) => a + Math.round(v / tot * 100), 0));
    t.innerHTML = `<b>${esc(p.n)}</b><span class="vm-mu">${num(p.d)} ${S.sectors.length === 1 ? esc(S.sectors[0]) + ' ' : ''}deal${p.d === 1 ? '' : 's'}${S.sectors.length > 1 ? ' in the chosen sectors' : ''} · ${num(p.f)} firm${p.f === 1 ? '' : 's'}</span>
${!sector && p.so ? `<span>Stands out for <b>${esc(p.so)}</b></span>` : ''}
${S.sectors.length === 1 ? '' : top.map(([n, v], j) => `<span class="vm-tr"><i style="background:${COLORS[n] || COLORS.Other}"></i><span>${j + 1}. ${esc(n)}</span><span class="vm-pc">${Math.round(v / tot * 100)}%</span></span>`).join('') + (top.length && (rest > 0 || !sector) ? `<span class="vm-tr"><i style="background:${REST}"></i><span>${sector ? 'Other chosen sectors' : 'All other sectors'}</span><span class="vm-pc">${rest}%</span></span>` : '')}`;
    }
    t.hidden = false;
    // The card sits on the page (not inside the scaled map), beside the circle, and stays clear of the time line.
    const w = 236, h = t.offsetHeight || 220, cx = S.ox + p.x * S.k, cy = S.oy + p.y * S.k, rr = p.r * S.k;
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
    // Clicking a place opens the firms behind it straight away; clicking it again, or the empty map, closes them.
    if (b) { const p = stage._rows[+b.dataset.i]; if (S.list && S.list.place.p === p.p) closeList(); else openList(p); return; }
    if (S.list) closeList();
  });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { if (S.list) closeList(); } });

  // ---------- headline card
  const perText = () => (S.days === 365 ? 'year' : S.days + ' days');
  function drawHotHead() {
    const where = S.level === 'us' ? ' in the US' : S.level === 'eu' ? ' in Europe' : '', t = (S.data.totals || {})[S.level] || { deals: 0, prev: 0 };
    const sec = S.sectors.length === 1 ? S.sectors[0].toLowerCase() : S.sectors.length ? 'these sectors' : '';
    $('#vm-h1').textContent = sec ? `Where ${sec} ${S.sectors.length === 1 ? 'is' : 'are'} heating up${where}.` : `Where it is heating up${where}.`;
    S.countId = (S.countId || 0) + 1; S.shown = null;
    $('#vm-based').textContent = `${num(t.deals)} deals in the last ${perText()}, ${num(t.prev)} in the ${perText()} before`;
    // one plain sentence about the biggest move among places with enough deals to trust
    const big = (stage._rows || []).filter((p) => (p.tone === 'up' || p.tone === 'down') && p.d + p.pv >= 100).sort((a, b) => Math.abs(b.pct) - Math.abs(a.pct))[0];
    $('#vm-legend').innerHTML = (big ? `<b>${esc(big.n)} is ${big.tone} ${Math.abs(big.pct)}%${big.tone === 'up' && big.hot ? ', led by ' + esc(big.hot[0]) : big.tone === 'down' && big.cold ? ', led by ' + esc(big.cold[0]) : ''}.</b> ` : '')
      + `<span class="vm-keys"><i class="vm-up"></i>up 10% or more <i class="vm-flat"></i>steady <i class="vm-down"></i>down 10% or more <i class="vm-few"></i>too few to call</span>`;
  }
  function drawHead() {
    if (S.view === 'hot') return drawHotHead();
    const where = S.level === 'us' ? ' in the US' : S.level === 'eu' ? ' in Europe' : '', t = (S.data.totals || {})[S.level] || { deals: 0, firms: 0 };
    const sec = S.sectors.length === 1 ? S.sectors[0].toLowerCase() : S.sectors.length ? 'these sectors' : '';
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
    $('#vm-legend').innerHTML = S.sectors.length > 1 ? 'Rings: split among the sectors you chose (top 5, the rest together). Size: their deals by VCs based there.' : sec ? 'Circle size: deals in the chosen sector by VCs based there.' : S.level === 'world' ? 'Rings: each place&#39;s own top 5 sectors. Size: share of all deals in the period.' : `Ring: ${RING_DEALS}+ deals from ${RING_FIRMS}+ firms. Small dot: ${DOT_DEALS} to ${RING_DEALS - 1} deals, in the colour of its biggest sector.`;
  }

  // ---------- right side: latest updates, or the firms behind a place
  const day = (s) => { const d = new Date(s + 'T00:00:00'); return isNaN(d) ? '' : MONTHS[d.getMonth()] + ' ' + d.getDate() + (d.getFullYear() === now.getFullYear() ? '' : ', ' + d.getFullYear()); };
  // The chosen place's own numbers, shown above its firms in the column layout.
  function placeFacts(p) {
    if (S.view === 'hot') return `<div class="vm-facts"><span class="vm-mu">${num(p.d)} deal${p.d === 1 ? '' : 's'} in the last ${perText()} · ${toneText(p)}${p.hot ? ` · heating up: <b>${esc(p.hot[0])}</b>` : ''}</span></div>`;
    const tot = p.tot || 1, top = p.top || [], one = S.sectors.length === 1, sector = S.sectors.length > 0;
    if (one || !top.length) return `<div class="vm-facts"><span class="vm-mu">${num(p.d)} deal${p.d === 1 ? '' : 's'}</span></div>`;
    const rest = Math.max(0, 100 - top.reduce((a, [, v]) => a + Math.round(v / tot * 100), 0));
    return `<div class="vm-facts"><span class="vm-mu">${num(p.d)} deal${p.d === 1 ? '' : 's'}${!sector && p.so ? ` · stands out for <b>${esc(p.so)}</b>` : ''}</span><span class="vm-bar">${top.map(([n, v]) => `<i style="width:${v / tot * 100}%;background:${COLORS[n] || COLORS.Other}" title="${esc(n)} ${Math.round(v / tot * 100)}%"></i>`).join('')}</span><span class="vm-key">${top.map(([n, v]) => `<span><i style="background:${COLORS[n] || COLORS.Other}"></i>${esc(n)} ${Math.round(v / tot * 100)}%</span>`).join('')}${rest > 0 ? `<span><i style="background:${REST}"></i>${sector ? 'Other chosen' : 'All other'} ${rest}%</span>` : ''}</span></div>`;
  }
  function drawSide() {
    const side = $('#vm-side');
    if (S.list) {
      const L = S.list, chips = [[L.place.n, 'place']].concat(S.sectors.map((s) => [s, 'sector']), S.stages.map((s) => [s, 'stage']));
      side.className = 'vm-card vm-side vm-list';
      side.innerHTML = `<div class="vm-lh"><h2>${L.data ? num(L.data.count) + ' firm' + (L.data.count === 1 ? '' : 's') : 'Loading'}</h2><button type="button" class="vm-x" id="vm-close" aria-label="Close list"></button></div>
<div class="vm-chips">${chips.map(([t, k]) => `<button type="button" class="vm-chip" data-k="${k}" data-v="${esc(t)}" aria-label="Remove filter ${esc(t)}">${esc(t)}<span aria-hidden="true">×</span></button>`).join('')}</div>
${COL ? placeFacts(L.place) : ''}<div class="vm-rows">${!L.data ? '' : L.data.firms.map((f) => `<a href="${ROOT}vc/${encodeURIComponent(f.slug)}/"><span><b>${esc(f.name)}</b><span class="vm-mu">${num(f.deals)} deal${f.deals === 1 ? '' : 's'}${f.led ? ' · led ' + num(f.led) : ''}</span><span class="vm-st ${f.status === 'Active' ? 'vm-a' : f.status === 'Low activity' ? 'vm-l' : ''}"><i></i>${esc(f.status)}${f.last ? `<span class="vm-mu"> · last deal ${day(f.last)}</span>` : ''}</span></span><span class="vm-ck">Check</span></a>`).join('')}</div>
<a class="vm-more" href="${ROOT}investors/">Open the full investors list</a>`;
      $('#vm-close').onclick = closeList;
      side.querySelectorAll('.vm-chip').forEach((c) => c.onclick = () => {
        if (c.dataset.k === 'place') return closeList();
        const k = c.dataset.k === 'sector' ? 'sectors' : 'stages'; S[k] = S[k].filter((x) => x !== c.dataset.v);
        const place = S.list.place; drawPicks(); refresh().then(() => openList(place));
      });
      return;
    }
    side.className = 'vm-card vm-side';
    if (S.view === 'hot') {  // sectors heating up and cooling down; click one to see where
      // keep showing every sector while one is chosen: remember the full list from the last unfiltered answer for this period and stage
      const memo = S.days + '|' + S.level + '|' + S.stages.join(','); S.secMemo = S.secMemo || {};
      if (!S.sectors.length && S.data && S.data.sectors) S.secMemo[memo] = S.data.sectors[S.level] || [];
      const rows = (S.secMemo[memo] || ((S.data || {}).sectors || {})[S.level] || []).filter(([, n, p]) => n + p >= 20 && p > 0).map(([name, n, p]) => ({ name, n, p, pct: Math.round((n - p) / p * 100) }));
      const up = rows.filter((r) => r.pct > 0).sort((a, b) => b.pct - a.pct).slice(0, 6), down = rows.filter((r) => r.pct < 0).sort((a, b) => a.pct - b.pct).slice(0, 6);
      const line = (r) => `<button type="button" class="vm-sec${S.sectors.includes(r.name) ? ' vm-secon' : ''}" data-s="${esc(r.name)}"><i class="${r.pct > 0 ? 'vm-up' : 'vm-down'}"></i><span>${esc(r.name)}</span><span class="vm-pc vm-mu">${num(r.n)} vs ${num(r.p)}</span><span class="vm-pc">${r.pct > 0 ? '+' : '−'}${Math.abs(r.pct)}%</span></button>`;
      side.innerHTML = `<div class="vm-lh"><h2>Sectors</h2><span class="vm-tag">last ${perText()} vs before</span></div>${S.sectors.length ? '<button type="button" class="vm-link" id="vm-allsec">Show all sectors</button>' : ''}
<span class="vm-mu vm-sub">Heating up</span>${up.map(line).join('') || '<span class="vm-mu">Nothing clear.</span>'}<span class="vm-mu vm-sub">Cooling down</span>${down.map(line).join('') || '<span class="vm-mu">Nothing clear.</span>'}`;
      side.querySelectorAll('.vm-sec').forEach((b) => b.onclick = () => { S.sectors = S.sectors.length === 1 && S.sectors[0] === b.dataset.s ? [] : [b.dataset.s]; drawPicks(); refresh().then(drawSide); });
      const all = $('#vm-allsec'); if (all) all.onclick = () => { S.sectors = []; drawPicks(); refresh().then(drawSide); };
      return;
    }
    side.innerHTML = `<div class="vm-lh"><h2>Latest updates</h2><span class="vm-tag">new rounds</span></div>${S.updates.length ? S.updates.map((u, i) => {
      const names = (u.firms || []).map((f) => f.name), who = names.length > 1 && (u.leads > 1 || !u.led) ? names[0] + ' and ' + names[1] : names[0] || '';
      const slug = u.firms && u.firms[0] && u.firms[0].slug;
      return `<a class="${i ? '' : 'vm-first'}" href="${slug ? ROOT + 'vc/' + encodeURIComponent(slug) + '/' : '#'}"><span class="vm-tag">${i ? '' : '<i class="vm-new" title="Newest update: its place is lit up on the map"></i>'}${esc(u.level && u.area && u.level === 'us' ? u.area : u.region || '')} · ${day(u.date)}</span><span class="vm-line" title="${esc(who)} ${u.led ? 'led' : 'joined'} a ${esc(u.round)} round in ${esc(u.startup)}">${esc(who)} ${u.led ? 'led' : 'joined'} a ${esc(u.round)} round in ${esc(u.startup)}</span></a>`;
    }).join('') : '<p class="vm-mu">No updates to show yet.</p>'}`;
  }
  async function openList(place) {
    stop(); S.list = { place, data: null }; S.pinned = place.p; drawSide(); draw();
    const d = await firms(place);
    if (S.list && S.list.place.p === place.p) { S.list.data = d || { count: place.f, firms: [] }; drawSide(); }
  }
  function closeList() { if (S.list) { S.list = null; S.pinned = null; drawSide(); draw(); } }

  // ---------- start
  let asked = 0;
  async function refresh() {
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
  fetch(ROOT + 'assets/map/places.json').then((r) => r.json()).then((g) => { S.geo = g; return refresh(); }).then(loadUpdates);
})();
