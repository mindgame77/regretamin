// The "Top 100" view of the home page map (the fifth button, after Pathfinders). Founder's design, 26 Nov 2026
// (claude/plans/top-100-view.md): each list is a chart of 100 firms, like 100 songs. The map is replaced by a Skyline:
// 100 bars in four rows of 25, a logo on top of each bar, the number inside it, the rank and its move underneath, and a
// dashed outline at last year's value. The left card lists the same 100. Pressing a bar or a row opens that firm's page.
// The black button in the head card opens one YouTube video per chart, as an icebreaker (the lines are the founder's words).
// Data: one read-only database function per chart. Only "Most active" (v2_top100_active) exists so far; the other four
// charts plug into CHARTS below when their functions do. No number is made up here: if the answer is missing, the view says so.
// Everything is drawn inside its own shadow root, like js/founders.js, so its styles and the rest of the site never meet.
(function () {
  const INK = '#10201C', SOFT = '#586964', LINE = '#E2E7E5';
  const MOVE = { up: ['#5CBB8A', '#1E8E5A'], dn: ['#E8877D', '#B3261E'], nu: ['#F0861E', '#C06A0C'], eq: ['#B9C4C0', '#586964'] };
  const KEY = { up: 'up', dn: 'down', nu: 'new', eq: 'same' };
  // One video per chart (founder, 26 Nov 2026). The line is the button's whole text; the link opens in a new tab.
  const VIDEOS = {
    active: { line: 'Feeling down? Press play', url: 'https://youtu.be/0tBw8cB553E' },
    social: { line: 'Great work is made of small details', url: 'https://youtu.be/atXpy2CkNMY' },
    first: { line: 'Raising is a grind. Take a breather', url: 'https://youtu.be/fpIKuufm_WM' },
    funds: { line: 'Meanwhile, in ancient Rome', url: 'https://www.youtube.com/watch?v=_t0uGbCPaf0' },
    rounds: { line: 'How top founders pitch big rounds', url: 'https://www.youtube.com/watch?v=z6gH_v0buUc' },
  };
  // The charts that are ready. Each one turns its database answer into rows: [slug, name, value, last year's value or null, last year's rank or null].
  const CHARTS = [
    { key: 'active', label: 'Most active', rpc: 'v2_top100_active', args: { p_n: 100 }, fx: 'fx_top100',
      unit: (n) => n + (n === 1 ? ' startup' : ' startups') },
  ];
  const LOCAL = /^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname);
  const QS = new URLSearchParams(location.search);
  const num = (n) => Number(n || 0).toLocaleString('en-US');
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const ord = (n) => n + (n % 100 >= 11 && n % 100 <= 13 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' }[n % 10] || 'th'));
  const ini = (n) => String(n || '').replace(/&/g, '').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
  // How a firm's place changed: up and down against last year's rank; "new" when it was not on last year's list of 100.
  function move(rank, prev) {
    if (prev == null || prev > 100) return { k: 'nu', t: 'new' };
    if (prev > rank) return { k: 'up', t: '▲ ' + (prev - rank) };
    if (prev < rank) return { k: 'dn', t: '▼ ' + (rank - prev) };
    return { k: 'eq', t: '–' };
  }

  const CSS = `:host{--ink:${INK};--mm:${SOFT};--ml:${LINE};--ms:#F3F5F4;--sans:'Geist',system-ui,-apple-system,'Segoe UI',sans-serif;--mono:'Geist Mono',ui-monospace,SFMono-Regular,Menlo,monospace;
  display:block;position:absolute;inset:0;background:#fff;color:var(--ink);font-family:var(--sans);font-size:15px;line-height:1.35}
:host([hidden]){display:none}
*{box-sizing:border-box}
button{font:inherit;color:inherit;cursor:pointer}
a{color:inherit;text-decoration:none}
button:focus-visible,a:focus-visible{outline:2px solid var(--ink);outline-offset:2px}
.app{height:100%;display:grid;grid-template-columns:424px minmax(0,1fr)}
.side{min-height:0;display:flex;flex-direction:column;gap:16px;padding:20px;background:var(--ms);border-right:1px solid var(--ml)}
.card{background:#fff;border:1px solid var(--ml);border-radius:16px;padding:20px}
.head{display:flex;flex-direction:column;gap:12px;flex:none}
.head h1{margin:0;font-size:27px;font-weight:600;letter-spacing:-.05em;line-height:1.02}
.based{margin:0;font:13px/1.35 var(--mono);color:var(--mm)}
.pick{position:relative}
.pickbtn{display:flex;align-items:center;justify-content:space-between;width:100%;height:44px;padding:0 14px;border:1px solid #8A9893;border-radius:10px;background:#fff;font-size:15px;text-align:left}
.pickbtn svg{flex:none}
.menu{position:absolute;left:0;right:0;top:48px;z-index:30;background:#fff;border:1px solid #8A9893;border-radius:10px;padding:6px;box-shadow:0 8px 28px rgba(16,32,28,.12)}
.menu[hidden]{display:none}
.menu button{display:block;width:100%;height:38px;padding:0 10px;border:0;border-radius:8px;background:none;text-align:left;font-size:15px}
.menu button:hover,.menu button[aria-checked="true"]{background:var(--ms)}
.menu button[aria-checked="true"]{font-weight:600}
.cta{display:flex;align-items:center;justify-content:center;height:44px;padding:0 8px;border-radius:10px;background:var(--ink);color:#fff;font-weight:600;font-size:16px;white-space:nowrap;overflow:hidden}
.cta .yt{display:inline-flex;align-items:center;justify-content:center;flex:none;width:34px;height:24px;margin-right:14px;border-radius:6px;background:#ff0000}
.cta:hover{background:#000}
.panel{flex:1;min-height:0;display:flex;flex-direction:column;padding:16px 20px 8px;overflow:hidden}
.lh{display:flex;justify-content:space-between;align-items:center;gap:10px;flex:none;padding-bottom:10px}
.lh h2{margin:0;font-size:20px;font-weight:600;min-width:0}
.unit{display:inline-flex;border:1px solid #8A9893;border-radius:8px;overflow:hidden;flex:none}
.unit button{height:28px;padding:0 12px;border:0;background:#fff;color:var(--ink);font-size:13px;white-space:nowrap}
.unit button[aria-pressed="true"]{background:var(--ink);color:#fff;font-weight:600}
.rows{flex:1;min-height:0;overflow:auto;margin:0 -8px}
.row{display:flex;align-items:center;gap:10px;padding:8px;border-top:1px solid var(--ml);border-radius:0}
.row:first-child{border-top:0}
.row.on{background:var(--ms);border-radius:10px}
.rk{width:46px;flex:none}
.rk b{display:block;font-size:16px;font-weight:600;line-height:1.1;font-variant-numeric:tabular-nums}
.rk em{font-style:normal;font-size:11px;font-weight:700}
.lg{flex:none;width:28px;height:28px;border-radius:8px;border:1px solid var(--ml);background:#fff;object-fit:contain;display:flex;align-items:center;justify-content:center;font-size:10px;font-weight:600;color:var(--mm)}
.nm{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-size:15px}
.vv{font-weight:600;text-align:right;line-height:1.15;font-variant-numeric:tabular-nums}
.vv small{display:block;font-weight:400;font-size:11px;color:var(--mm)}
.main{position:relative;min-width:0;min-height:0;overflow:hidden}
.sky{position:absolute;left:24px;right:24px;top:96px;bottom:104px}
.sky svg{display:block;width:100%;height:100%;overflow:visible}
.b{cursor:pointer}
.b:focus{outline:none}
.legend{position:absolute;left:0;right:0;bottom:24px;display:flex;justify-content:center;pointer-events:none}
.legend div{display:flex;align-items:center;gap:26px;height:52px;padding:0 26px;background:#fff;border:1px solid var(--ml);border-radius:16px;box-shadow:0 6px 24px rgba(16,32,28,.08);white-space:nowrap;font-size:13px}
.legend span{display:flex;align-items:center;gap:8px}
.legend i{width:12px;height:12px;border-radius:4px;display:inline-block}
.legend i.d{border:1.4px dashed var(--ink);background:none}
.tip{position:fixed;z-index:20;pointer-events:none;display:none;background:var(--ink);color:#fff;border-radius:12px;padding:10px 12px;font-size:13px;line-height:1.35;box-shadow:0 6px 20px rgba(16,32,28,.28);white-space:nowrap}
.tip small{display:block;color:#C9D3CF;font-size:12px}
.tip small.u{color:#7FD6A5}
.msg{position:absolute;inset:96px 24px 104px;display:flex;align-items:center;justify-content:center;text-align:center;color:var(--mm);padding:24px}
@media (max-width:900px){
  :host{position:static;background:none}
  .app{display:flex;flex-direction:column;height:auto}
  .side{padding:0;background:none;border:0;margin-top:12px}
  .main{display:none}  /* the phone layout is simpler and comes later (founder, 26 Nov): for now the phone gets the list only */
  .rows{overflow:visible}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}`;

  const HTML = `<div class="app">
  <aside class="side">
    <section class="card head"><h1>The Top 100.</h1>
      <div class="pick" id="pick"></div>
      <p class="based" id="based"></p>
      <a class="cta" id="cta" target="_blank" rel="noopener noreferrer" href="#"></a></section>
    <section class="card panel"><div class="lh"><h2 id="ptitle"></h2><span class="unit" role="group" aria-label="Show as"><button type="button" data-v="map" aria-pressed="false">Map</button><button type="button" data-v="sky" aria-pressed="true">Skyline</button></span></div><div class="rows" id="rows"></div></section>
  </aside>
  <section class="main"><div class="sky" id="sky"></div><div class="legend" id="legend"></div></section>
</div>
<div class="tip" id="tip"></div>`;

  let host = null, root = null, O = null, chart = CHARTS[0], logos = null;
  const cache = new Map();
  const $ = (s) => root.querySelector(s);

  async function load(c) {
    if (cache.has(c.key)) return cache.get(c.key);
    let d = null;
    const fx = LOCAL && QS.get(c.fx);
    try {
      if (fx) d = await fetch(fx).then((r) => r.json());
      else if (O.sb) { const r = await O.sb.rpc(c.rpc, c.args); if (!r.error) d = r.data; }
    } catch (e) { d = null; }
    if (d && Array.isArray(d.firms) && d.firms.length) { cache.set(c.key, d); return d; }
    return null;
  }
  function loadLogos() {
    if (logos) return Promise.resolve();
    logos = new Set();
    const v = (window.REGRET && window.REGRET.flv) ? '?v=' + window.REGRET.flv : '';
    return fetch(O.root + 'assets/logos/firms.json' + v).then((r) => r.json()).then((a) => { logos = new Set(a); }).catch(() => {});
  }
  const logoUrl = (slug) => O.root + 'assets/logos/f-' + encodeURIComponent(slug) + '.png';
  const firmUrl = (slug) => O.root + 'vc/' + encodeURIComponent(slug) + '/';

  // rows: one object per firm, in rank order
  function shape(d) {
    return d.firms.map(([slug, name, v, p, prev], i) => ({ i: i + 1, slug, name, v: +v, p: p == null ? null : +p, prev: prev == null ? null : +prev, mv: move(i + 1, prev == null ? null : +prev) }));
  }
  function tipHtml(r) {
    const lines = ['<b>' + r.i + ' · ' + esc(r.name) + '</b>',
      '<small>' + esc(chart.unit(r.v)) + ' · ' + (r.p ? num(r.p) + ' last year' : 'none last year') + '</small>'];
    const t = r.mv.k === 'nu' ? '▲ new to the Top 100' + (r.prev ? ' · was ' + ord(r.prev) : ' · not ranked last year')
      : r.mv.k === 'eq' ? 'same place as last year' : 'was ' + ord(r.prev);
    lines.push('<small class="' + (r.mv.k === 'up' || r.mv.k === 'nu' ? 'u' : '') + '">' + esc(t) + '</small>');
    return lines.join('');
  }
  let ROWS = [], hov = 0;
  function mark(i) {
    hov = i;
    root.querySelectorAll('.row.on').forEach((e) => e.classList.remove('on'));
    root.querySelectorAll('.b rect.hl').forEach((e) => { e.removeAttribute('stroke'); e.removeAttribute('stroke-width'); });
    if (!i) return;
    const row = root.querySelector('.row[data-i="' + i + '"]'); if (row) row.classList.add('on');
    const rc = root.querySelector('.b[data-i="' + i + '"] rect.hl'); if (rc) { rc.setAttribute('stroke', INK); rc.setAttribute('stroke-width', '2.5'); }
  }
  function showTip(i, ev, anchor) {
    const r = ROWS[i - 1], tip = $('#tip'); if (!r) return;
    tip.innerHTML = tipHtml(r); tip.style.display = 'block';
    const a = anchor.getBoundingClientRect(), w = tip.offsetWidth, h = tip.offsetHeight;
    let x = a.left + a.width / 2 - w / 2, y = a.top - h - 10;
    if (y < 8) y = a.bottom + 10;
    x = Math.max(8, Math.min(innerWidth - w - 8, x));
    tip.style.left = x + 'px'; tip.style.top = y + 'px';
  }
  function hideTip() { $('#tip').style.display = 'none'; }

  function drawRows() {
    $('#rows').innerHTML = ROWS.map((r) => {
      const lg = logos && logos.has(r.slug) ? `<img class="lg" alt="" loading="lazy" src="${logoUrl(r.slug)}">` : `<span class="lg">${esc(ini(r.name))}</span>`;
      return `<a class="row" data-i="${r.i}" href="${firmUrl(r.slug)}"><span class="rk"><b>${r.i}</b><em style="color:${MOVE[r.mv.k][1]}">${esc(r.mv.t)}</em></span>${lg}<span class="nm">${esc(r.name)}</span><span class="vv">${num(r.v)}<small>${r.p ? num(r.p) + ' last year' : 'none last year'}</small></span></a>`;
    }).join('');
  }
  function drawLegend() {
    const c = { up: 0, dn: 0, nu: 0, eq: 0 }; ROWS.forEach((r) => { c[r.mv.k]++; });
    $('#legend').innerHTML = '<div>' + ['up', 'dn', 'nu', 'eq'].map((k) => `<span><i style="background:${MOVE[k][0]}"></i>${KEY[k]} · ${c[k]}</span>`).join('') + '<span><i class="d"></i>last year</span></div>';
  }
  // The Skyline: four rows of 25. A row is as tall as its tallest bar (this year's or last year's); one scale for all
  // four rows, shrunk until the four rows fit the box.
  function drawSky() {
    const box = $('#sky'), W = box.clientWidth, H = box.clientHeight;
    if (!W || !H || !ROWS.length) return;
    const SLOT = W / 25, BW = Math.max(10, Math.min(30, SLOT * 0.62)), L = Math.max(16, Math.min(24, SLOT * 0.5)), GAP = 40, TOPPAD = L + 12;
    const rowsOf = [0, 1, 2, 3].map((k) => ROWS.slice(k * 25, k * 25 + 25));
    const mx = rowsOf.map((rs) => Math.max(1, ...rs.map((r) => Math.max(r.v, r.p || 0))));
    let K = 1.6;
    const total = (k) => mx.reduce((a, m) => a + m * k + TOPPAD + GAP, 0);
    while (total(K) > H && K > 0.02) K *= 0.99;
    let y = 0, g = '', defs = '';
    const bases = mx.map((m) => { y += m * K + TOPPAD; const b = y; y += GAP; return b; });
    bases.forEach((b) => { g += `<line x1="0" x2="${W}" y1="${b}" y2="${b}" stroke="${LINE}"/>`; });
    ROWS.forEach((r) => {
      const ri = Math.floor((r.i - 1) / 25), ci = (r.i - 1) % 25, base = bases[ri];
      const x = ci * SLOT + (SLOT - BW) / 2, h = Math.max(2, r.v * K), top = base - h, gh = (r.p || 0) * K, col = MOVE[r.mv.k][0];
      const yt = gh ? Math.min(top, base - gh) : top, ly = yt - L - 5, lx = x + (BW - L) / 2, cx = x + BW / 2;
      const lg = logos && logos.has(r.slug)
        ? `<image href="${logoUrl(r.slug)}" x="${lx}" y="${ly}" width="${L}" height="${L}" clip-path="url(#c${r.i})" preserveAspectRatio="xMidYMid slice"/><rect x="${lx}" y="${ly}" width="${L}" height="${L}" rx="6" fill="none" stroke="rgba(16,32,28,.14)"/>`
        : `<rect x="${lx}" y="${ly}" width="${L}" height="${L}" rx="6" fill="#fff" stroke="${LINE}"/><text x="${cx}" y="${ly + L * 0.66}" font-size="10" font-weight="600" fill="${SOFT}" text-anchor="middle">${esc(ini(r.name))}</text>`;
      defs += `<clipPath id="c${r.i}"><rect x="${lx}" y="${ly}" width="${L}" height="${L}" rx="6"/></clipPath>`;
      g += `<a class="b" data-i="${r.i}" href="${firmUrl(r.slug)}" aria-label="${esc(r.i + '. ' + r.name + ', ' + chart.unit(r.v) + ', ' + (r.mv.k === 'nu' ? 'new to the Top 100' : r.mv.k === 'eq' ? 'same place as last year' : 'was ' + ord(r.prev)))}">`
        + `<rect x="${x - 4}" y="${Math.min(ly, top) - 4}" width="${BW + 8}" height="${base - Math.min(ly, top) + 34}" fill="transparent"/>`
        + (gh ? `<rect x="${x - 1.5}" y="${base - gh}" width="${BW + 3}" height="${gh}" rx="5" fill="none" stroke="${INK}" stroke-opacity=".6" stroke-width="1.4" stroke-dasharray="3 2.5"/>` : '')
        + `<rect class="hl" x="${x}" y="${top}" width="${BW}" height="${h}" rx="5" fill="${col}"/>`
        + (h >= 22 ? `<text x="${cx}" y="${top + 15}" font-size="11" font-weight="700" fill="${INK}" stroke="${col}" stroke-width="4" stroke-linejoin="round" paint-order="stroke" text-anchor="middle">${r.v}</text>` : '')
        + lg
        + `<text x="${cx}" y="${base + 14}" font-size="10" fill="${INK}" text-anchor="middle" font-family="Geist Mono,monospace">${r.i}</text>`
        + `<text x="${cx}" y="${base + 26}" font-size="9" font-weight="700" fill="${MOVE[r.mv.k][1]}" text-anchor="middle">${esc(r.mv.t)}</text></a>`;
    });
    box.innerHTML = `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="group" aria-label="${esc(chart.label)}: the 100 firms as bars"><defs>${defs}</defs>${g}</svg>`;
    box.querySelectorAll('.b').forEach((a) => {
      const i = +a.dataset.i;
      a.addEventListener('pointerenter', (ev) => { mark(i); showTip(i, ev, a.querySelector('rect.hl')); });
      a.addEventListener('pointerleave', () => { mark(0); hideTip(); });
      a.addEventListener('focus', (ev) => { mark(i); showTip(i, ev, a.querySelector('rect.hl')); });
      a.addEventListener('blur', () => { mark(0); hideTip(); });
    });
    if (hov) mark(hov);
  }
  function drawHead() {
    const v = VIDEOS[chart.key], c = $('#cta');
    $('#ptitle').textContent = chart.label;
    if (v) { c.hidden = false; c.href = v.url; c.innerHTML = `<span class="yt"><svg width="12" height="13" viewBox="0 0 12 13" aria-hidden="true"><path d="M1 1L11 6.500 1 12Z" fill="#fff"/></svg></span><span>${esc(v.line)}</span>`; } else c.hidden = true;
    const menu = CHARTS.map((x) => `<button type="button" role="menuitemradio" aria-checked="${x.key === chart.key}" data-k="${x.key}">${esc(x.label)}</button>`).join('');
    $('#pick').innerHTML = `<button type="button" class="pickbtn" aria-haspopup="true" aria-expanded="false"><span>${esc(chart.label)}</span><svg aria-hidden="true" width="10" height="6" viewBox="0 0 10 6"><path d="M1 1l4 4 4-4" fill="none" stroke="${INK}" stroke-width="1.6"/></svg></button><div class="menu" role="menu" hidden>${menu}</div>`;
  }
  async function show(c) {
    chart = c || chart; drawHead(); hideTip();
    $('#rows').innerHTML = ''; $('#sky').innerHTML = ''; $('#legend').innerHTML = '';
    const d = await load(chart); await loadLogos();
    if (!d) { $('#based').textContent = ''; $('#sky').innerHTML = '<div class="msg">The Top 100 is not available right now. Try again in a moment.</div>'; return; }
    ROWS = shape(d);
    $('#based').textContent = 'Based on ' + num(d.rounds) + ' rounds';
    drawRows(); drawLegend(); drawSky();
  }

  function boot() {
    drawHead();
    const pick = $('#pick');
    pick.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      const menu = pick.querySelector('.menu');
      if (b.dataset.k) { menu.hidden = true; const c = CHARTS.find((x) => x.key === b.dataset.k); if (c && c !== chart) show(c); else drawHead(); return; }
      menu.hidden = !menu.hidden; b.setAttribute('aria-expanded', String(!menu.hidden));
    });
    root.addEventListener('click', (e) => { if (!e.target.closest('#pick')) { const m = pick.querySelector('.menu'); if (m) m.hidden = true; } });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { const m = pick.querySelector('.menu'); if (m) m.hidden = true; } });
    root.querySelector('.unit').addEventListener('click', (e) => { const b = e.target.closest('button'); if (b && b.dataset.v === 'map' && O.onMap) O.onMap(); });
    root.querySelector('#rows').addEventListener('pointerover', (e) => { const r = e.target.closest('.row'); if (r) mark(+r.dataset.i); });
    root.querySelector('#rows').addEventListener('pointerleave', () => mark(0));
    let rz = 0; addEventListener('resize', () => { clearTimeout(rz); rz = setTimeout(() => { if (!host.hidden) drawSky(); }, 150); });
    show(chart);
  }

  window.REGRET_TOP = {
    // o: { el: the map's <main>, sb: the database client, root: the site root, onMap: called when "Map" is pressed }
    show(o) {
      O = o;
      if (!host) {
        host = document.createElement('div'); host.id = 'vt'; o.el.appendChild(host);
        root = host.attachShadow({ mode: 'open' }); root.innerHTML = '<style>' + CSS + '</style>' + HTML;
        boot();
      } else { host.hidden = false; drawSky(); }
    },
    hide() { if (host) { host.hidden = true; if (root) hideTip(); } },
  };
})();
