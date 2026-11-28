// The "Top 100" view of the home page map (the fifth button, after Pathfinders). Founder's design, 26 Nov 2026
// (claude/plans/top-100-view.md): each list is a chart of 100 firms, like 100 songs. The map is replaced by a Skyline:
// 100 bars in four rows of 25, a logo on top of each bar, the number inside it, the plain rank underneath, and a
// dashed outline at last year's value. The left card lists the same 100. Pressing a bar or a row opens that firm's page.
// The black button in the head card opens one YouTube video per chart, as an icebreaker (the lines are the founder's words).
// Data: one read-only database function per chart. "Most active" (v2_top100_active) and "First in" (v2_top100_first) and "Biggest new funds" (v2_top100_funds) and "Most social reach" (v2_top100_social) exist so far; the other one
// charts plug into CHARTS below when their functions do. No number is made up here: if the answer is missing, the view says so.
// The list's "Map" button swaps the Skyline for a map: one circle per place, sized by the chart's number added up over the Top 100 firms based there
// (founder, 27 Nov). The World / United States / Europe buttons are the page's own zoom card (js/map.js), which tells this view the level.
// Everything is drawn inside its own shadow root, like js/founders.js, so its styles and the rest of the site never meet.
(function () {
  const INK = '#10201C', SOFT = '#586964', LINE = '#E2E7E5';
  const MOVE = { up: ['#5CBB8A', '#1E8E5A'], dn: ['#E8877D', '#B3261E'], nu: ['#F0861E', '#C06A0C'], eq: ['#B9C4C0', '#586964'], na: ['#B9C4C0', '#586964'] };
  const KEY = { up: 'up', dn: 'down', nu: 'new', eq: 'same', na: 'no earlier fund on record' };
  // Dollar amounts the way the Biggest new funds chart shows them: $10B, $5.8B, $850M, $56.6M (short() leaves the dollar sign off, for inside a bar)
  const short = (v) => { const a = Math.abs(v); const f = (x, d) => String(+x.toFixed(d)); return a >= 1e9 ? f(v / 1e9, 1) + 'B' : a >= 1e7 ? f(v / 1e6, 0) + 'M' : a >= 1e6 ? f(v / 1e6, 1) + 'M' : a >= 1e3 ? f(v / 1e3, 0) + 'K' : f(v, 0); };
  const usd = (v) => '$' + short(v);
  // Most social reach: a bar is stacked by platform (X at the bottom), each segment the platform's share of the firm's followers
  const fol = (v) => (v >= 1e6 ? (v / 1e6).toFixed(1) + 'M' : v >= 1e3 ? Math.round(v / 1e3) + 'k' : String(v));  // followers: 2.7M, 789k
  const PLAT = [['X', '#10201C'], ['LinkedIn', '#2F6DB5'], ['YouTube', '#D9483B'], ['Instagram', '#B8509E'], ['Substack', '#8C6A4A']];
  const platsOf = (r) => PLAT.filter(([k]) => r.parts && r.parts[k] > 0).map(([k, c]) => ({ k, c, n: +r.parts[k] }));
  // Biggest rounds: a bar is coloured by the round's industry group (the function's `g`); the Other group is grey, so its lettering is dark
  const GROUPS = [['AI', '#5B55D6'], ['Hardware', '#0E8A8A'], ['Defense & security', '#8C5A3C'], ['Climate', '#6BA83B'], ['Bio & health', '#D9507C'], ['Fintech & crypto', '#E0A81C'], ['Software', '#3472C4'], ['Other', '#9AA5A1']];
  const gCol = (r) => (GROUPS.find(([k]) => r.parts && k === r.parts.g) || GROUPS[7])[1];
  const gInk = (r) => (r.parts && r.parts.g && r.parts.g !== 'Other' ? '#fff' : INK);
  const FLAME = 'M0 -9C1 -5 5 -3 5 2C5 6 2.500 8 0 8C-2.500 8 -5 6 -5 2C-5 -1 -3 -2 -2 -5C-1 -3 0 -4 0 -9Z';
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const dayMon = (s) => { const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s || ''); return m ? (+m[3]) + ' ' + MON[+m[2] - 1] : ''; };
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
    { key: 'active', label: 'Most active', rpc: 'v2_top100_active', args: { p_n: 100 }, fx: 'fx_top100', about: 'Firms backing the most startups this year', dot: '#D9483B', short: 'Most active', emoji: '⚡',
      unit: (n) => num(n) + (n === 1 ? ' startup' : ' startups') },
    // First in: startups where the firm held the earliest shown deal (v2_top100_first); same window and row shape as Most active
    { key: 'first', label: 'First in', rpc: 'v2_top100_first', args: { p_n: 100 }, fx: 'fx_top100_first', about: 'Most startups backed before anyone else', dot: '#3F9E4A', short: 'First in', emoji: '🏁',
      unit: (n) => 'First in on ' + num(n) + (n === 1 ? ' startup' : ' startups') },
    // Most social reach: followers added up over X, LinkedIn, YouTube, Instagram and Substack (v2_top100_social). Only one reading per account so far, so no last year and no moves.
    { key: 'social', label: 'Most social reach', rpc: 'v2_top100_social', args: { p_n: 100 }, fx: 'fx_top100_social', about: 'Most followers across social media', dot: '#7B5CD6', short: 'Social reach', emoji: '📣', noPrev: true, stack: true, scale: Math.sqrt,
      unit: (n) => fol(n) + ' followers', bar: null, circle: fol,
      row: (r) => { const t = platsOf(r).sort((a, b) => b.n - a.n)[0]; return { v: fol(r.v), s: t ? 'mostly ' + t.k : '' }; },
      under: (r) => fol(r.v),
      tip: (r) => ['<small>' + esc(fol(r.v)) + ' followers</small>', '<small>' + platsOf(r).sort((a, b) => b.n - a.n).map((x) => esc(x.k) + ' ' + fol(x.n)).join(' · ') + '</small>'],
      legend: 'platforms' },
    // Biggest new funds: each firm's biggest fund announced in the last 12 months against the 12 before (v2_top100_funds). The row's seventh item is the announcement date.
    // A firm with no fund in the earlier 12 months has nothing to compare with: grey, no move ("no earlier fund on record").
    { key: 'funds', label: 'Biggest new funds', rpc: 'v2_top100_funds', args: { p_n: 100 }, fx: 'fx_top100_funds', about: 'Biggest funds of the past 12 months', dot: '#2F6FDB', short: 'New funds', emoji: '💰', noPrev: true,
      unit: usd, bar: short, circle: usd,
      row: (r) => ({ v: usd(r.v), s: dayMon(r.dt) }),
      under: (r) => usd(r.v),
      tip: (r) => ['<small>' + esc(usd(r.v)) + (r.dt ? ' · announced ' + esc(dayMon(r.dt)) : '') + '</small>', '<small>' + (r.p ? 'was ' + esc(usd(r.p)) + ' last year' : 'no earlier fund on record') + '</small>'],
      legend: ['up', 'dn', 'nu', 'eq', 'na'], counts: false },
    // Biggest rounds: the 100 biggest rounds of the year so far (v2_top100_rounds). A row is a round, not a firm: no firm page to open, no last year. Its Map places each round by its STARTUP's country / city
    // (founder, 27 Nov: "startup country"); a round whose startup has no place on record is in the list but not on the map.
    // Seventh item: { r: round name, d: date, i: sector, n: investors we hold in it, h: in the last 30 days, g: industry group, c: startup country, p: world region, l: 'us' | 'eu', a: place on that zoom }.
    { key: 'rounds', label: 'Biggest rounds', rpc: 'v2_top100_rounds', args: { p_n: 100 }, fx: 'fx_top100_rounds', about: 'The 100 largest rounds this year so far', dot: '#D13C8C', short: 'Big rounds', emoji: '🦄', noPrev: true, noLink: true, startups: true, scale: Math.sqrt, noun: 'round',
      placeOf: (r, lvl) => { const x = r.parts || {}; return lvl === 'world' ? x.p : x.l === lvl ? x.a : null; },  // the Map: a round sits where its startup is (the function's p / l / a)
      unit: usd, bar: (v) => (v >= 1e9 ? short(v) : ''), under: (r) => usd(r.v), color: gCol, ink: gInk, flame: (r) => !!(r.parts && r.parts.h),
      row: (r) => ({ v: usd(r.v), s: [r.parts && r.parts.r, dayMon(r.parts && r.parts.d)].filter(Boolean).join(' · ') }),
      tip: (r) => { const x = r.parts || {}; return ['<small>' + [x.g, x.r, dayMon(x.d)].filter(Boolean).map(esc).join(' · ') + '</small>', '<small>' + esc(usd(r.v)) + (x.n ? ' · ' + x.n + (x.n === 1 ? ' investor' : ' investors') + ' we hold' : '') + '</small>']; },
      legend: 'groups' },
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
:host(.map){background:transparent;pointer-events:none}  /* Map mode: the page's own map is underneath; only the left side takes the pointer */
:host(.map) .side{pointer-events:auto}
:host(.map) .main{display:none}
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
.head h1{white-space:nowrap}
.pick{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px}
.stk{display:flex;align-items:center;justify-content:center;aspect-ratio:1;width:100%;padding:0;border:2px solid var(--c);border-radius:12px;background:var(--ms);cursor:pointer}
.stk[aria-pressed="true"]{background:var(--c);box-shadow:0 3px 0 rgba(16,32,28,.25)}
.stk span{display:block;font-size:36px;line-height:1;text-shadow:1.50px 0.00px 0 #fff, 1.39px 0.57px 0 #fff, 1.06px 1.06px 0 #fff, 0.57px 1.39px 0 #fff, 0.00px 1.50px 0 #fff, -0.57px 1.39px 0 #fff, -1.06px 1.06px 0 #fff, -1.39px 0.57px 0 #fff, -1.50px 0.00px 0 #fff, -1.39px -0.57px 0 #fff, -1.06px -1.06px 0 #fff, -0.57px -1.39px 0 #fff, -0.00px -1.50px 0 #fff, 0.57px -1.39px 0 #fff, 1.06px -1.06px 0 #fff, 1.39px -0.57px 0 #fff;filter:drop-shadow(0 2px 2px rgba(16,32,28,.3))}
.cta{display:flex;align-items:center;justify-content:center;height:44px;padding:0 8px;border-radius:10px;background:var(--ink);color:#fff;font-weight:600;font-size:16px;white-space:nowrap;overflow:hidden}
.cta .yt{display:inline-flex;align-items:center;justify-content:center;flex:none;width:34px;height:24px;margin-right:14px;border-radius:6px;background:#ff0000}
.cta:hover{background:#000}
.panel{flex:1;min-height:0;display:flex;flex-direction:column;padding:16px 20px 8px;overflow:hidden}
.lh{display:flex;justify-content:space-between;align-items:center;gap:10px;flex:none;padding-bottom:10px}
.lh h2{margin:0;font-size:20px;font-weight:600;min-width:0}
.unit{display:inline-flex;border:1px solid #8A9893;border-radius:8px;overflow:hidden;flex:none}
.unit[hidden]{display:none}
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
.legend span.note{color:var(--mm)}
.legend .g{gap:18px;padding:0 20px}
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
    <section class="card head"><h1>Top 100 <span id="h1n"></span></h1>
      <div class="pick" id="pick" role="group" aria-label="Choose a chart"></div>
      <p class="based" id="about"></p>
      <a class="cta" id="cta" target="_blank" rel="noopener noreferrer" href="#"></a></section>
    <section class="card panel"><div class="lh"><h2 id="ptitle"></h2><span class="unit" role="group" aria-label="Show as"><button type="button" data-v="map" aria-pressed="false">Map</button><button type="button" data-v="sky" aria-pressed="true">Skyline</button></span></div><div class="rows" id="rows"></div></section>
  </aside>
  <section class="main"><div class="sky" id="sky"></div><div class="legend" id="legend"></div></section>
</div>
<div class="tip" id="tip"></div>`;

  let host = null, root = null, O = null, chart = CHARTS[0], logos = null, slogos = {};
  const cache = new Map();
  const $ = (s) => root.querySelector(s);
  // Back from a firm page (founder, 27 Nov): the view comes back as it was left, in this tab: the same chart, Map or Skyline, and the list where it was scrolled.
  // The page (js/map.js) already brings back the Top 100 itself; this is what is inside it. Kept in sessionStorage, so a shared link never carries it to someone else.
  const KEEP = 'regretamin.top100';
  let scrollTo = 0;
  function keep() {
    try { sessionStorage.setItem(KEEP, JSON.stringify({ k: chart.key, m: mode, s: root && $('#rows') ? Math.round($('#rows').scrollTop) : 0 })); } catch (e) { /* private mode */ }
  }
  function restore() {
    try {
      const m = JSON.parse(sessionStorage.getItem(KEEP) || 'null'); if (!m) return;
      const c = CHARTS.find((x) => x.key === m.k); if (c) chart = c;
      if (m.m === 'map' && !chart.noMap) mode = 'map';
      if (Number.isFinite(m.s) && m.s > 0) scrollTo = m.s;
    } catch (e) { /* nothing kept */ }
  }
  addEventListener('pagehide', () => { if (host && !host.hidden) keep(); });

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
    // startup logos (the Biggest rounds chart): assets/logos/startups.json = { startup name in lower case: startup id }, pictures assets/logos/s-<id>.png
    const st = fetch(O.root + 'assets/logos/startups.json' + v).then((r) => r.json()).then((o) => { slogos = o; }).catch(() => {});
    return Promise.all([fetch(O.root + 'assets/logos/firms.json' + v).then((r) => r.json()).then((a) => { logos = new Set(a); }).catch(() => {}), st]);
  }
  const logoSrc = (r) => {  // the picture of a firm, or of a startup on the rounds chart; null when there is none
    if (chart.startups) { const id = slogos[String(r.name || '').trim().toLowerCase()]; return id ? O.root + 'assets/logos/s-' + encodeURIComponent(id) + '.png' : null; }
    return !chart.color && logos && logos.has(r.slug) ? logoUrl(r.slug) : null;
  };
  const logoUrl = (slug) => O.root + 'assets/logos/f-' + encodeURIComponent(slug) + '.png';
  const firmUrl = (slug) => O.root + 'vc/' + encodeURIComponent(slug) + '/';
  // a firm's headquarters country as a small flag picture (assets/flags/<code>.png); no picture when the country is not known
  const flagUrl = (cc) => O.root + 'assets/flags/' + cc.toLowerCase() + '.png';
  const cleanCC = (v) => (typeof v === 'string' && /^[A-Za-z]{2}$/.test(v) ? v.toLowerCase() : null);

  // rows: one object per firm, in rank order
  function shape(d) {
    return d.firms.map(([slug, name, v, p, prev, cc, ex], i) => {
      const pv = p == null ? null : +p, pr = prev == null ? null : +prev;
      return { i: i + 1, slug, name, cc: cleanCC(cc) || (ex && typeof ex === 'object' ? cleanCC(ex.c) : null), v: +v, p: pv, prev: pr, dt: typeof ex === 'string' ? ex : null, parts: ex && typeof ex === 'object' ? ex : null, mv: chart.noPrev && pv == null ? { k: 'na', t: '' } : move(i + 1, pr) };
    });
  }
  function tipHtml(r) {
    if (chart.tip) return '<b>' + r.i + ' · ' + esc(r.name) + '</b>' + chart.tip(r).join('');
    const lines = ['<b>' + r.i + ' · ' + esc(r.name) + '</b>',
      '<small>' + esc(chart.unit(r.v)) + ' · ' + (r.p ? num(r.p) + ' last year' : 'none last year') + '</small>'];
    const t = r.mv.k === 'nu' ? '▲ new to the Top 100' + (r.prev ? ' · was ' + ord(r.prev) : ' · not ranked last year')
      : r.mv.k === 'eq' ? 'same place as last year' : 'was ' + ord(r.prev);
    lines.push('<small class="' + (r.mv.k === 'up' || r.mv.k === 'nu' ? 'u' : '') + '">' + esc(t) + '</small>');
    return lines.join('');
  }
  let ROWS = [], hov = 0;
  // The map mode: which level is showing, where each firm sits, and the page's own place positions.
  let mode = 'sky', level = 'world', PL = null;
  const FOLD = { GG: 'GB', JE: 'GB', IM: 'GB' };  // the same islands the map folds into the United Kingdom
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
    placeTip(tip, anchor.getBoundingClientRect(), 10);
  }
  // The hover card goes above its bar. It must stay below the top of the chart area: the page's own view tabs (Money flow, Trends...) sit above it and would hide it.
  // When the bar is too tall for that, the card goes beside the bar instead (right, or left when there is no room), level with the top of the chart area.
  function placeTip(tip, a, gap) {
    const w = tip.offsetWidth, h = tip.offsetHeight, minY = Math.max(8, $('#sky').getBoundingClientRect().top);
    let x = a.left + a.width / 2 - w / 2, y = a.top - h - gap;
    if (y < minY) {
      y = Math.max(minY, a.top);
      x = a.right + gap; if (x + w > innerWidth - 8) x = a.left - w - gap;
    }
    tip.style.left = Math.max(8, Math.min(innerWidth - w - 8, x)) + 'px'; tip.style.top = y + 'px';
  }
  function hideTip() { $('#tip').style.display = 'none'; }

  // the right-hand end of a list row: the number and, under it, last year's (or the date, for the funds chart)
  const rowTxt = (r) => { if (chart.row) { const x = chart.row(r); return x.v + '<small>' + esc(x.s) + '</small>'; } return num(r.v) + '<small>' + (r.p ? num(r.p) + ' last year' : 'none last year') + '</small>'; };
  // A circle pressed on the Map (founder, 28 Nov): the list shows only that place's rows, and the card's title names the place and counts them,
  // the way Money flow's card does ("Bay Area · 656 firms"). PICK: { p: place, l: level, n: its name on the map }, or null for all 100.
  let PICK = null;
  const inPick = (r) => {
    if (!PICK) return true;
    if (chart.placeOf) return chart.placeOf(r, PICK.l) === PICK.p;
    const f = PL && PL.by[r.slug]; if (!f) return false;
    return (PICK.l === 'world' ? f.region : f.lv === PICK.l ? (FOLD[f.area] || f.area) : null) === PICK.p;
  };
  function drawTitle() {
    if (!PICK) { $('#ptitle').textContent = chart.label; return; }
    const k = ROWS.filter(inPick).length, noun = chart.noun || 'firm';
    $('#ptitle').textContent = `${PICK.n} · ${k} ${noun}${k === 1 ? '' : 's'}`;
  }
  function setPick(o) { PICK = o; drawTitle(); drawRows(); $('#rows').scrollTop = 0; }
  function drawRows() {
    $('#rows').innerHTML = ROWS.filter(inPick).map((r) => {
      const src = logoSrc(r);
      const lg = src ? `<img class="lg" alt="" loading="lazy" src="${src}">` : chart.color ? `<span class="lg" style="background:${chart.color(r)};border-color:${chart.color(r)};color:${chart.ink(r)}">${esc(ini(r.name))}</span>` : `<span class="lg">${esc(ini(r.name))}</span>`;
      const tag = chart.noLink ? 'div' : 'a', href = chart.noLink ? '' : ` href="${firmUrl(r.slug)}"`;
      return `<${tag} class="row" data-i="${r.i}"${href}><span class="rk"><b>${r.i}</b></span>${lg}<span class="nm">${esc(r.name)}</span><span class="vv">${rowTxt(r)}</span></${tag}>`;
    }).join('');
  }
  function drawLegend() {
    if (chart.legend === 'platforms') { $('#legend').innerHTML = '<div>' + PLAT.map(([k, c]) => `<span><i style="background:${c}"></i>${k}</span>`).join('') + '<span class="note">bar height is scaled, segments = share of followers</span></div>'; return; }
    if (chart.legend === 'groups') {
      const hot = ROWS.filter((r) => chart.flame(r)).length;
      $('#legend').innerHTML = '<div class="g">' + GROUPS.map(([k, c]) => `<span><i style="background:${c}"></i>${esc(k)}</span>`).join('') + `<span><svg width="12" height="16" viewBox="-6 -10 12 19" aria-hidden="true"><path d="${FLAME}" fill="#F0861E"/></svg>last 30 days · ${hot}</span></div>`; return;
    }
    const c = { up: 0, dn: 0, nu: 0, eq: 0, na: 0 }; ROWS.forEach((r) => { c[r.mv.k]++; });
    const keys = (chart.legend || ['up', 'dn', 'nu', 'eq']).filter((k) => c[k] > 0 || !chart.legend);
    $('#legend').innerHTML = '<div>' + keys.map((k) => `<span><i style="background:${MOVE[k][0]}"></i>${KEY[k]}${chart.counts === false ? '' : ' · ' + c[k]}</span>`).join('') + '<span><i class="d"></i>last year</span></div>';
  }
  // a bar made of one segment per platform, X at the bottom; the whole bar is one rounded shape, and rect.hl is its outline for the hover
  function stackSvg(r, x, top, h, BW) {
    const ps = platsOf(r), tot = ps.reduce((a, b) => a + b.n, 0) || 1; let y = top + h, g = '';
    ps.forEach((p) => { const sh = h * p.n / tot; y -= sh; g += `<rect x="${x}" y="${y}" width="${BW}" height="${sh}" fill="${p.c}"/>`; });
    return `<g clip-path="url(#k${r.i})">${g}</g><rect class="hl" x="${x}" y="${top}" width="${BW}" height="${h}" rx="5" fill="none"/>`;
  }
  // The Skyline: four rows of 25. A row is as tall as its tallest bar (this year's or last year's); one scale for all
  // four rows, shrunk until the four rows fit the box.
  function drawSky() {
    const box = $('#sky'), W = box.clientWidth, H = box.clientHeight;
    if (!W || !H || !ROWS.length) return;
    const SLOT = W / 25, BW = Math.max(10, Math.min(30, SLOT * 0.62)), L = Math.max(16, Math.min(24, SLOT * 0.5)), GAP = chart.under ? 48 : 38, TOPPAD = L + 12;  // under each bar: the rank, the flag right under it (founder, 28 Nov), then the chart's own line where it has one
    const rowsOf = [0, 1, 2, 3].map((k) => ROWS.slice(k * 25, k * 25 + 25));
    const sq = chart.scale || ((x) => x);  // social reach draws bar heights on a square-root scale: 2.7M against 56k would otherwise leave the small bars invisible
    const mx = rowsOf.map((rs) => Math.max(sq(1), ...rs.map((r) => Math.max(sq(r.v), sq(r.p || 0)))));
    let K = 1.6;
    const total = (k) => mx.reduce((a, m) => a + m * k + TOPPAD + GAP, 0);
    while (total(K) > H && K > 1e-12) K *= 0.99;  // the bars are in whatever unit the chart has (startups, dollars), so there is no fixed floor
    let y = 0, g = '', defs = '';
    const bases = mx.map((m) => { y += m * K + TOPPAD; const b = y; y += GAP; return b; });
    bases.forEach((b) => { g += `<line x1="0" x2="${W}" y1="${b}" y2="${b}" stroke="${LINE}"/>`; });
    ROWS.forEach((r) => {
      const ri = Math.floor((r.i - 1) / 25), ci = (r.i - 1) % 25, base = bases[ri];
      const x = ci * SLOT + (SLOT - BW) / 2, h = Math.max(2, sq(r.v) * K), top = base - h, gh = sq(r.p || 0) * K, col = chart.color ? chart.color(r) : MOVE[r.mv.k][0];
      const yt = gh ? Math.min(top, base - gh) : top, ly = yt - L - 5, lx = x + (BW - L) / 2, cx = x + BW / 2;
      const fx = cx - 8, fy = base + (chart.under ? 32 : 18);  // the flag: centred, right under the rank; where the chart has its own line under the rank (social reach, new funds, big rounds), under that line as before
      const src = logoSrc(r);
      const lg = src
        ? `<image href="${src}" x="${lx}" y="${ly}" width="${L}" height="${L}" clip-path="url(#c${r.i})" preserveAspectRatio="xMidYMid slice"/><rect x="${lx}" y="${ly}" width="${L}" height="${L}" rx="6" fill="none" stroke="rgba(16,32,28,.14)"/>`
        : chart.color ? `<rect x="${lx}" y="${ly}" width="${L}" height="${L}" rx="6" fill="${col}"/><text x="${cx}" y="${ly + L * 0.66}" font-size="10" font-weight="700" fill="${chart.ink(r)}" text-anchor="middle">${esc(ini(r.name))}</text>`
        : `<rect x="${lx}" y="${ly}" width="${L}" height="${L}" rx="6" fill="#fff" stroke="${LINE}"/><text x="${cx}" y="${ly + L * 0.66}" font-size="10" font-weight="600" fill="${SOFT}" text-anchor="middle">${esc(ini(r.name))}</text>`;
      defs += `<clipPath id="c${r.i}"><rect x="${lx}" y="${ly}" width="${L}" height="${L}" rx="6"/></clipPath>` + (chart.stack ? `<clipPath id="k${r.i}"><rect x="${x}" y="${top}" width="${BW}" height="${h}" rx="5"/></clipPath>` : '') + `<clipPath id="f${r.i}"><rect x="${fx}" y="${fy}" width="16" height="12" rx="2"/></clipPath>`;
      g += `<a class="b" data-i="${r.i}"${chart.noLink ? ' tabindex="0" style="cursor:default"' : ` href="${firmUrl(r.slug)}"`} aria-label="${esc(r.i + '. ' + r.name + ', ' + chart.unit(r.v) + ', ' + (r.mv.k === 'nu' ? 'new to the Top 100' : r.mv.k === 'eq' ? 'same place as last year' : r.mv.k === 'na' ? (chart.noLink ? 'biggest rounds of the year' : KEY.na) : 'was ' + ord(r.prev)))}">`
        + `<rect x="${x - 4}" y="${Math.min(ly, top) - 4}" width="${BW + 8}" height="${base - Math.min(ly, top) + 46}" fill="transparent"/>`
        + (gh ? `<rect x="${x - 1.5}" y="${base - gh}" width="${BW + 3}" height="${gh}" rx="5" fill="none" stroke="${INK}" stroke-opacity=".6" stroke-width="1.4" stroke-dasharray="3 2.5"/>` : '')
        + (chart.stack ? stackSvg(r, x, top, h, BW) : `<rect class="hl" x="${x}" y="${top}" width="${BW}" height="${h}" rx="5" fill="${col}"/>`)
        + (h >= 22 && chart.bar !== null && (chart.bar ? chart.bar(r.v) : true) !== '' ? `<text x="${cx}" y="${top + 15}" font-size="11" font-weight="700" fill="${chart.ink ? chart.ink(r) : INK}" stroke="${col}" stroke-width="4" stroke-linejoin="round" paint-order="stroke" text-anchor="middle">${chart.bar ? chart.bar(r.v) : r.v}</text>` : '')
        + lg
        + (chart.flame && chart.flame(r) ? `<path d="${FLAME}" transform="translate(${lx + L - 1} ${ly + 1})" fill="#F0861E" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/>` : '')
        + `<text x="${cx}" y="${base + 14}" font-size="10" fill="${INK}" text-anchor="middle" font-family="Geist Mono,monospace">${r.i}</text>`
        + `<text x="${cx}" y="${base + 26}" font-size="9" font-weight="700" fill="${MOVE[r.mv.k][1]}" text-anchor="middle">${esc(chart.under ? chart.under(r) : '')}</text>`
        + (r.cc ? `<image href="${flagUrl(r.cc)}" x="${fx}" y="${fy}" width="16" height="12" clip-path="url(#f${r.i})" preserveAspectRatio="xMidYMid slice"/><rect x="${fx}" y="${fy}" width="16" height="12" rx="2" fill="none" stroke="rgba(16,32,28,.25)"/>` : '') + `</a>`;
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

  async function loadPlaces() {
    const slugs = ROWS.map((r) => r.slug).join(',');
    if (PL && PL.key === slugs) return PL.by;
    let d = null;
    const fx = LOCAL && QS.get('fx_top100_places');
    try {
      if (fx) d = await fetch(fx).then((r) => r.json());
      else if (O.sb) { const r = await O.sb.rpc('v2_top100_places', { p_slugs: ROWS.map((x) => x.slug) }); if (!r.error) d = r.data; }
    } catch (e) { d = null; }
    const by = {}; (Array.isArray(d) ? d : []).forEach(([slug, lv, region, area]) => { by[slug] = { lv, region, area }; });
    PL = { key: slugs, by }; return by;
  }
  // One circle per place: the chart's number added up over the firms of that place. World: the region; United States: the
  // city; Europe: the country. A firm outside the zoom shown is left out of it.
  function placesFor(lvl, by) {
    const out = {};
    ROWS.forEach((r) => {
      const f = by[r.slug]; if (!f) return;
      const k = lvl === 'world' ? f.region : f.lv === lvl ? (FOLD[f.area] || f.area) : null;
      if (!k) return;
      const o = out[k] || (out[k] = { k, v: 0, firms: 0 }); o.v += r.v; o.firms++;
    });
    return Object.values(out).filter((o) => o.v > 0).sort((a, b) => b.v - a.v);
  }
  // The Map is drawn by the page itself (js/map.js: the same circles, names, hover card, zoom card and + / - as Pathfinders). This view only hands over one row
  // per place, for all three zoom levels: { p: place, l: 'world' | 'us' | 'eu', d: the chart's number added up, f: firms, v: that number as text }.
  async function drawMap() {
    const by = chart.placeOf ? null : await loadPlaces();
    if (mode !== 'map') return;
    $('#legend').innerHTML = ''; $('#sky').innerHTML = '';
    const rows = [];
    if (chart.placeOf) {  // a chart of rounds: each round sits where its startup is; the circle adds up the rounds there
      ['world', 'us', 'eu'].forEach((l) => {
        const at = {};
        ROWS.forEach((r) => { const k = chart.placeOf(r, l); if (!k) return; const o = at[k] || (at[k] = { v: 0, f: 0 }); o.v += r.v; o.f++; });
        Object.entries(at).forEach(([k, o]) => rows.push({ p: k, l, d: o.v, f: o.f, v: chart.unit(o.v), u: chart.noun, c: chart.dot }));
      });
    } else {
      ['world', 'us', 'eu'].forEach((l) => placesFor(l, by).forEach((o) => rows.push({ p: o.k, l, d: o.v, f: o.firms, v: chart.unit(o.v), c: chart.dot })));
    }
    if (O.places) O.places(rows);
  }
  // the right picture for the mode: the Skyline, or the map at the level the zoom card shows
  function draw() {
    const box = $('#sky');
    if (chart.noMap) mode = 'sky';  // a round has no firm, so no place on a map
    root.querySelector('.unit').hidden = !!chart.noMap;
    root.querySelectorAll('.unit button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.v === mode)));
    if (O.onMode) O.onMode(mode);
    hideTip();
    if (PICK) setPick(null);  // a new picture (another chart, Map or Skyline, the view opened again) starts with all 100
    host.classList.toggle('map', mode === 'map');  // in Map mode this view is see-through on the right: the page's own map shows there
    if (mode === 'map') { drawMap(); return; }
    drawLegend(); drawSky();
  }
  function drawHead() {
    const v = VIDEOS[chart.key], c = $('#cta');
    PICK = null; drawTitle();
    $('#about').textContent = chart.about || '';  // one line under the five chart buttons: what this chart is (40 characters or fewer, so it never wraps)
    if (v) { c.hidden = false; c.href = v.url; c.innerHTML = `<span class="yt"><svg width="12" height="13" viewBox="0 0 12 13" aria-hidden="true"><path d="M1 1L11 6.500 1 12Z" fill="#fff"/></svg></span><span>${esc(v.line)}</span>`; } else c.hidden = true;
    const n = $('#h1n'); n.textContent = '· ' + chart.short; n.style.color = chart.dot;
    $('#pick').innerHTML = CHARTS.map((x) => `<button type="button" class="stk" style="--c:${x.dot}" data-k="${x.key}" aria-pressed="${x.key === chart.key}" aria-label="${esc(x.label)}" title="${esc(x.label)}"><span aria-hidden="true">${x.emoji}</span></button>`).join('');
  }
  async function show(c) {
    chart = c || chart; drawHead(); hideTip();
    if (window.REGRET_TRACK) window.REGRET_TRACK('top100_chart', { chart: chart.key });
    $('#rows').innerHTML = ''; $('#sky').innerHTML = ''; $('#legend').innerHTML = '';
    const d = await load(chart); await loadLogos();
    if (!d) { $('#sky').innerHTML = '<div class="msg">The Top 100 is not available right now. Try again in a moment.</div>'; return; }
    ROWS = shape(d);
    drawRows(); draw();
    if (scrollTo) { $('#rows').scrollTop = scrollTo; scrollTo = 0; }
    keep();
  }

  function boot() {
    restore(); drawHead();
    $('#pick').addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      const c = CHARTS.find((x) => x.key === b.dataset.k); if (c && c !== chart) show(c);
    });
    root.querySelector('.unit').addEventListener('click', (e) => { const b = e.target.closest('button'); if (b && b.dataset.v && b.dataset.v !== mode && ROWS.length) { mode = b.dataset.v; draw(); keep(); } });
    root.querySelector('#rows').addEventListener('pointerover', (e) => { const r = e.target.closest('.row'); if (r) mark(+r.dataset.i); });
    root.querySelector('#rows').addEventListener('pointerleave', () => mark(0));
    let rz = 0; addEventListener('resize', () => { clearTimeout(rz); rz = setTimeout(() => { if (!host.hidden) draw(); }, 150); });
    show(chart);
  }

  window.REGRET_TOP = {
    // o: { el: the map's <main>, sb: the database client, root: the site root, mapv: '?v=…' for the map files, level: the zoom level now, onMode: called with 'map' or 'sky' so the page can show its zoom card }
    show(o) {
      O = o; if (o.level) level = o.level;
      if (!host) {
        host = document.createElement('div'); host.id = 'vt'; o.el.appendChild(host);
        root = host.attachShadow({ mode: 'open' }); root.innerHTML = '<style>' + CSS + '</style>' + HTML;
        boot();
      } else { host.hidden = false; if (ROWS.length) draw(); }
    },
    // the page's zoom card changed the level (World, United States, Europe)
    setLevel(l) { level = l; if (PICK && root) setPick(null); },
    // the page tells this view which circle is pressed on the Map (null: none)
    pick(o) { if (root && ROWS.length) setPick(o && o.p ? o : null); },  // the page redraws its own map when the zoom card is pressed
    hide() { if (host) { host.hidden = true; if (root) hideTip(); if (O && O.onMode) O.onMode('sky'); } },
  };
})();
