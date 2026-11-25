// The "Founders" view of the home page map (the third button next to Money flow and Hot right now).
// What founders are building, three ways: by where they live (Places), where they studied (Universities) and where
// they worked before (Companies); as a map or as blocks sized by cash raised. Founder's decisions, 24 to 25 Nov 2026:
// a place needs only one startup to get a colour; rounds of $1B or more are left out of the cash of universities and companies (places count everything); pressing a state or country does not move the map; circles in one
// city sit beside each other; a logo on a filled or white square is cut round and fills its circle.
// Data: one read-only database function, v2_founders_data (kept 30 minutes); the page does all the counting, so the
// years, the pressed place and the two switches answer at once. Map shapes, positions and logos come with the site
// (launch/assets/founders/, launch/assets/logos/; made by tools/map/gen_founders.cjs).
// Everything is drawn inside its own shadow root, so its styles and the rest of the site never meet.
(function () {
  const COLORS = { 'Enterprise software': '#A9C4E8', 'Health': '#F2A7A0', 'Fintech': '#F3D98B', 'Hardware & Robotics': '#9FD4C3', 'Consumer': '#D9B5E0', 'Climate & Energy': '#BFDCA0', 'Bio': '#C59AC7', 'AI agents': '#8E9BE0', 'AI models': '#C4CCF2', 'Security': '#A8BDB5', 'Crypto': '#F7E6B5', 'Media & Gaming': '#F5C19A', 'Food & Agriculture': '#D5E0A3', 'Defense': '#B5B5BD', 'Space': '#9AA5D1', 'Mobility': '#9CC9D9', 'Education': '#EFC4D0', 'Developer tools': '#B9E0E6', 'Real estate': '#E6C9B0', 'Govtech': '#C2D6C8', 'Other': '#DADFDD' };
  const VC = window.REGRET_VC_BASE || '/vc/';
  // A round this big ($M) is left out of the cash of a university or a company, and only there: 83 such rounds are
  // nearly half of all the money, and each would be counted under every university and former employer of that
  // startup's founders (OpenAI alone put Google at $388B). A place counts every round: the money did land there.
  // The startup itself always counts and is listed with its real round. Founder's call, 25 Nov 2026.
  const BIG = 1000;
  // Local preview only: ?fx_founders=<saved v2_founders_data answer>. Ignored on any real host.
  const LOCAL = /^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname);
  const FIX = LOCAL ? new URLSearchParams(location.search).get('fx_founders') : null;
  const CSS = `:host{
  --paper:#FFFFFF; --wash:#F3F5F4; --ink:#10201C; --soft:#586964; --line:#C9D1CE; --hair:#E2E7E5; --land:#E3E8E6; --accent:#F0861E;
  --sans:'Geist',system-ui,-apple-system,'Segoe UI',sans-serif; --mono:'Geist Mono',ui-monospace,SFMono-Regular,Menlo,monospace;
  display:block;position:absolute;inset:0;background:var(--paper);color:var(--ink);font-family:var(--sans);font-size:15px;line-height:1.35}
:host([hidden]){display:none}
*{box-sizing:border-box}
button{font:inherit;color:inherit;cursor:pointer}
button:focus-visible,[tabindex]:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
a{color:inherit}
.app{height:100%;display:grid;grid-template-columns:424px minmax(0,1fr)}
.side{min-height:0;display:flex;flex-direction:column;gap:16px;padding:20px;background:var(--wash);border-right:1px solid var(--hair)}
.card{background:var(--paper);border:1px solid var(--hair);border-radius:16px;padding:18px 20px}
.head h1{margin:0 0 10px;font-size:26px;line-height:1.08;letter-spacing:-.02em;font-weight:600;text-wrap:balance}
.head p{margin:0;font:13px/1.45 var(--mono);color:var(--soft)}
.key{display:flex;flex-wrap:wrap;gap:6px 14px;margin-top:14px;font-size:13px}
.key h4{flex:1 0 100%;margin:0 0 2px;font:600 12px var(--mono);letter-spacing:.06em;text-transform:uppercase;color:var(--soft)}
.key span{display:flex;align-items:center;gap:6px;white-space:nowrap}
.sw{width:12px;height:12px;border-radius:4px;flex:none;display:inline-block}
.panel{flex:1;min-height:0;overflow:auto;padding-top:14px}
.panel h2{margin:0 0 8px;font-size:19px;font-weight:600;letter-spacing:-.01em}
.panel h3{margin:18px 0 4px;font:600 12px var(--mono);letter-spacing:.06em;text-transform:uppercase;color:var(--soft)}
.row{display:grid;grid-template-columns:14px minmax(0,1fr) auto;column-gap:10px;align-items:center;width:100%;padding:9px 0;border:0;border-top:1px solid var(--hair);background:none;text-align:left}
button.row:hover b{text-decoration:underline}
.row b{display:block;font-size:15px;font-weight:600;overflow-wrap:anywhere}
.row small{display:block;font-size:13px;color:var(--soft)}
.row strong{font-size:15px;font-weight:600;font-variant-numeric:tabular-nums;white-space:nowrap}
.row .sw{width:14px;height:14px;border-radius:5px}
.back{height:36px;padding:0 12px;border:1px solid #8A9893;border-radius:10px;background:var(--paper);font-weight:600;font-size:14px;margin-bottom:12px}
.stat{font-size:15px;margin:0 0 12px}
.bar{display:flex;gap:2px;height:26px}
.bar i{border-radius:5px;min-width:3px}
.note{margin:14px 0 0;font-size:13px;color:var(--soft)}
.more{display:block;width:100%;height:40px;margin:12px 0 8px;border:1px solid #8A9893;border-radius:10px;background:#fff;font-size:14px}
.main{min-width:0;min-height:0;display:flex;flex-direction:column;padding:88px 24px 112px;gap:12px}  /* room is left at the top for the page's own View and Zoom buttons and at the bottom for its timeline */
.ctl{flex:none;display:flex;flex-wrap:wrap;gap:10px;align-items:center}
.ctl .sp{flex:1}
.seg{display:inline-flex;gap:4px;padding:4px;border:1px solid #8A9893;border-radius:12px;background:var(--paper)}
.seg button{height:32px;padding:0 12px;border:0;border-radius:8px;background:none;font-size:14px;white-space:nowrap}
.seg button[aria-pressed="true"]{background:var(--ink);color:#fff;font-weight:600}
.stage{flex:1;min-height:0;position:relative;background:var(--paper);border:1px solid var(--hair);border-radius:16px;overflow:hidden}
.row a{text-decoration:none}.row a:hover b{text-decoration:underline}
.stage svg{position:absolute;inset:0;width:100%;height:100%;cursor:grab;touch-action:none}
.zoom{position:absolute;right:12px;bottom:12px;display:flex;flex-direction:column;gap:6px;align-items:flex-end}
.zoom button{width:38px;height:38px;border:1px solid #8A9893;border-radius:10px;background:var(--paper);font-size:20px;font-weight:600;line-height:1}
.zoom .zr{width:auto;padding:0 10px;font-size:13px}
.dot{vector-effect:non-scaling-stroke}
.shp{stroke:#fff;stroke-width:1;vector-effect:non-scaling-stroke}
.shp.has,.pin,.dot{cursor:pointer}
.dot:hover{stroke:var(--ink);stroke-width:1.5}
.ring{fill:none;stroke:var(--ink);stroke-width:2;stroke-linejoin:round;vector-effect:non-scaling-stroke;pointer-events:none}
.ring.hov{stroke-width:1.5}
.dim .shp.has:not(.on),.dim .pin:not(.on),.dim .dot:not(.on){opacity:.35}
.dot.on{stroke:var(--ink);stroke-width:2}
.pin circle{stroke:none;vector-effect:non-scaling-stroke}
.pin.on circle{stroke:var(--ink);stroke-width:3}
.pin:hover circle{stroke:var(--ink);stroke-width:1.5}
.pin circle.in,.pin.on circle.in,.pin:hover circle.in{stroke:none}
.pin image{pointer-events:none}
.lgi{vertical-align:-4px;margin-right:7px;border-radius:4px;object-fit:contain}
.bkh .lgi{margin-right:0;flex:none}
/* no box around a pressed shape or circle: it only gets the dark outline */
.stage svg [tabindex]:focus,.stage svg [tabindex]:focus-visible{outline:none}
.stage svg .shp.has:focus-visible,.stage svg .dot:focus-visible{stroke:var(--ink);stroke-width:2}
.stage svg .pin:focus-visible circle{stroke:var(--ink);stroke-width:3}
.stage svg .pin:focus-visible circle.in{stroke:none}
.areaon .pin.off{opacity:.22}
.areaon.dim .pin:not(.on):not(.off){opacity:.5}
.lab{font-family:var(--sans);text-anchor:middle;pointer-events:none;fill:var(--ink)}
.lab .n{font-weight:600}
.lab .c{fill:#33443F}
.blocks{position:absolute;inset:10px}
.bk{position:absolute;padding:3px;border:0;background:none;text-align:left}
.bk>div{position:relative;width:100%;height:100%;border:1.5px solid var(--ink);border-radius:10px;overflow:hidden;background:var(--paper)}
.bk.on>div{border-width:3px}
.blocks.dim .bk:not(.on){opacity:.4}
.bkh{position:absolute;left:0;right:0;top:0;height:30px;display:flex;align-items:center;gap:7px;padding:0 8px;font-size:13px;white-space:nowrap;overflow:hidden}
.bkh b{font-weight:600;font-size:14px}.bkh span{color:var(--soft)}
.lg{flex:none;width:20px;height:20px;border-radius:6px;background:#EEF1F0;border:1px solid var(--line);color:var(--soft);font:600 9px/18px var(--sans);text-align:center}
.bk i{position:absolute;border-radius:5px;padding:5px 6px;font-style:normal;overflow:hidden;font-size:12px;line-height:1.15}
.bk i b{display:block;font-weight:600}.bk i span{color:#33443F}
.empty{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:var(--soft);padding:24px;text-align:center}
.dock{flex:none;display:flex;flex-wrap:wrap;gap:10px 18px;align-items:center}
.dock label{display:flex;align-items:center;gap:8px;font-size:14px}
.dock input{width:16px;height:16px;accent-color:var(--ink)}
#tip{position:fixed;z-index:20;pointer-events:none;background:var(--ink);color:#fff;border-radius:10px;padding:8px 11px;font-size:13px;line-height:1.35;max-width:260px;display:none}
#tip b{display:block;font-size:14px}
@media (max-width:900px){
  :host{position:static;background:none}
  .app{display:flex;flex-direction:column-reverse;height:auto}
  .side{padding:0;background:none;border:0;margin-top:12px}
  .main{padding:0}
  .stage{flex:none;height:72vw;min-height:260px}
  .panel{overflow:visible}
  .ctl .seg{max-width:100%;overflow-x:auto}
  .stage svg{touch-action:pan-y}  /* on a phone a finger moving up or down scrolls the page; zoom with the buttons */
}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
/* ---- The same look as Money flow and Hot right now (founder, 25 Nov: "unify all 3 maps in size and design"). ----
   Values are the site's own (style.css: .vm-card, .vm-head, .vm-side, .vm-lh, .vm-unit, .vm-tip, .vm-views). */
:host{--mi:#10201C;--mm:#586964;--ml:#E2E7E5;--ms:#F3F5F4;background:transparent}
.side{gap:16px;padding:20px;background:var(--ms);border-right:1px solid var(--ml)}
.card{border:1px solid var(--ml);border-radius:16px;padding:20px;background:#fff}
.head{display:flex;flex-direction:column;gap:12px}
.head h1{margin:0;font-size:27px;font-weight:600;letter-spacing:-.05em;line-height:1.02}
.head p{margin:0;font:13px/1.35 var(--mono);color:var(--mm)}
/* the three choices look like the site's own drop-down buttons (.vm-pickbtn) and sit where Money flow has them: under the title */
.picks{display:flex;gap:6px;flex-wrap:wrap}
.cta{display:block;height:44px;line-height:44px;padding:0 16px;border-radius:10px;background:var(--mi);color:#fff;font-weight:600;text-align:center;text-decoration:none;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mapnote{position:absolute;right:72px;bottom:108px;width:176px;margin:0;font-size:12px;line-height:1.35;color:var(--mm);text-align:right;text-wrap:balance;pointer-events:none}
.picks button{height:44px;padding:0 12px;border-radius:10px;border:1px solid #8A9893;background:#fff;font-size:14px;white-space:nowrap}
.picks button[aria-pressed="true"]{background:var(--mi);border-color:var(--mi);color:#fff;font-weight:600}
.panel{padding:16px 20px 8px;display:flex;flex-direction:column;overflow:hidden}
.lh{display:flex;justify-content:space-between;align-items:center;gap:10px;flex:none;padding-bottom:10px}
.lh h2{margin:0;font-size:20px;font-weight:600;letter-spacing:0;min-width:0;overflow-wrap:anywhere}
#panel{flex:1;min-height:0;overflow:auto}
.unit{display:inline-flex;border:1px solid #8A9893;border-radius:8px;overflow:hidden;flex:none}
.unit button{height:28px;padding:0 10px;border:0;background:#fff;color:var(--mi);font-size:13px}
.unit button[aria-pressed="true"]{background:var(--mi);color:#fff;font-weight:600}
.unit button:focus-visible{outline:2px solid var(--mi);outline-offset:-2px}
.row{padding:10px 0;border-top:1px solid var(--ml)}
.row b{font-size:14px}.row small{font-size:13px}.row strong{font-size:14px}
.main{padding:0;position:relative}
.stage{position:absolute;inset:0;flex:none;border:0;border-radius:0;background:transparent}
/* ---- One map for every view (founder, 25 Nov: "why we cannot use the same map?"). ----
   At rest the land is the page's own picture (#vm-bg, the one Money flow and Hot right now use): this view only lays its
   colours and circles over it, so nothing moves or blinks when the view changes. It draws its own land (".own") only where
   that picture cannot follow: zoomed in, something pressed (the rest goes pale), Blocks, and on a phone. */
.stage.own{background:#fff}
.shp{stroke-width:var(--lw,1px)}
.shp.plain{fill:transparent;stroke:none}
.stage.own .shp.plain{fill:#CCD5D1;stroke:#fff}
@keyframes tint{from{fill-opacity:0;stroke-opacity:0}to{fill-opacity:1;stroke-opacity:1}}
@keyframes fadein{from{opacity:0}to{opacity:1}}
.soft .shp.tint{animation:tint .6s ease both}  /* countries and states softly take their sector colour */
.soft #marks{animation:fadein .6s ease both}
@media (prefers-reduced-motion:reduce){.soft .shp.tint,.soft #marks{animation:none}}
.blocks{inset:96px 24px 112px 24px}
.zoom{right:24px;bottom:108px}
.zoom button{border:1px solid var(--ml);border-radius:12px;box-shadow:0 8px 28px rgba(16,32,28,.08)}
.lab{paint-order:stroke;stroke:#fff;stroke-width:calc(3px * var(--k));stroke-linejoin:round}
.pin .lab{stroke:none}
#tip{width:236px;max-width:236px;box-sizing:border-box;background:#fff;color:var(--mi);border:1.5px solid var(--mi);border-radius:12px;padding:10px 12px;font-size:12px;line-height:1.35;flex-direction:column;gap:4px}
#tip>b{display:block;font-size:14px;font-weight:600}
#tip .mu{color:var(--mm)}
#tip .tr{display:flex;align-items:center;gap:7px}
#tip .tr i{width:10px;height:10px;border-radius:3px;flex:none}
#tip .tr span:nth-child(2){flex:1}
#tip .pc{font-family:var(--mono)}
@media (max-width:900px){
  .side{padding:0;background:none;border:0;margin-top:12px}
  .main{height:72vw;min-height:260px;border:1px solid var(--ml);border-radius:16px;overflow:hidden}
  .panel{overflow:visible}#panel{overflow:visible}
  .blocks{inset:6px}
  .zoom{right:10px;bottom:10px}
  .mapnote{right:58px;bottom:10px;width:150px}
}
`;
  const HTML = `<div class="app">
  <aside class="side">
    <section class="card head"><h1 id="h1">Loading…</h1>
      <div class="picks" id="seg-kind" role="group" aria-label="What to show"><button data-v="places">Places</button><button data-v="unis">Universities</button><button data-v="cos">Companies</button></div>
      <p id="based"></p><a class="cta" id="cta" href="#">See the investors</a></section>
    <section class="card panel"><div class="lh"><h2 id="ptitle"></h2><span class="unit" id="seg-mode" role="group" aria-label="Show as"><button data-v="map">Map</button><button data-v="blocks">Blocks</button></span></div><div id="panel"></div></section>
  </aside>
  <section class="main"><div class="stage" id="stage"></div></section>
</div>
<div id="tip"></div>`;
  let host = null, root = null, want = 'us', span = null;
  const api = {};
  window.REGRET_FOUNDERS = {
    // o: { el: the map's <main>, sb: the database client, root: the site root, mapv: '?v=…' for the map files, level }
    show(o) {
      want = o.level || want; if (o.span) span = o.span;
      if (!host) {
        host = document.createElement('div'); host.id = 'vf'; o.el.appendChild(host);
        root = host.attachShadow({ mode: 'open' }); root.innerHTML = '<style>' + CSS + '</style>' + HTML;
        boot(o);
      } else { host.hidden = false; if (api.setLevel) api.setLevel(want); if (span && api.setSpan) api.setSpan(span); if (api.redraw) api.redraw(); }
    },
    hide() { if (host) host.hidden = true; },
    setSpan(sp) { span = sp; if (api.setSpan) api.setSpan(sp); },
    setLevel(l) { want = l; if (api.setLevel) api.setLevel(l); },
  };

async function boot(O) {
  const $ = (s) => root.querySelector(s);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  // The map shapes and where each university and company sits come with the site; the numbers come from the database.
  let M, ST;
  try {
    const [geo, orgs, got] = await Promise.all([
      fetch(O.root + 'assets/founders/geo.json' + O.mapv).then((r) => r.json()),
      fetch(O.root + 'assets/founders/orgs.json' + O.mapv).then((r) => r.json()),
      FIX ? fetch(FIX).then((r) => r.json()).then((d) => ({ data: d })) : O.sb.rpc('v2_founders_data')]);
    if (got.error || !got.data) throw new Error('no data');
    const D = got.data, info = (list, names) => { const by = {}; for (const o of list) by[o.n] = o; return names.map((n) => { const o = by[n] || {}; return { n, p: o.p || {}, a: o.a || [null, null], c: o.c || '', fb: o.fb || 0, lg: o.lg ? O.root + 'assets/logos/' + o.lg + O.mapv : null }; }); };
    const sectors = []; for (const [id, n] of Object.entries(D.sectors || {})) sectors[+id] = n;
    M = { views: geo.views, shapes: geo.shapes, dots: geo.dots, europe: geo.europe, colors: COLORS, sectors, firms: D.firms || [], unis: info(orgs.unis, D.unis || []), cos: info(orgs.cos, D.cos || []) };
    ST = D.startups || [];
  } catch (e) { $('#h1').textContent = 'This view is not available right now.'; $('#based').textContent = 'Reload the page to try again.'; return; }
  const S = { kind: 'places', mode: 'map', level: ['world', 'us', 'eu'].includes(want) ? want : 'us', from: (O.span || {}).from || 0, to: (O.span || {}).to || 99999999, when: (O.span || {}).text || 'since 2021', sel: null, area: null };
  const EU = new Set(M.europe), OTHER = 18;
  const col = (sid) => M.colors[M.sectors[sid]] || '#DADFDD', sname = (sid) => M.sectors[sid] || 'Other';
  const num = (n) => n.toLocaleString('en-US');
  const money = (m) => m >= 1000 ? '$' + (+(m / 1000).toFixed(1)) + 'B' : m >= 10 ? '$' + Math.round(m) + 'M' : m > 0 ? '$' + (+m.toFixed(1)) + 'M' : '';
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const day = (d) => (d % 100) + ' ' + MON[Math.floor(d / 100) % 100 - 1] + ' ' + Math.floor(d / 10000);
  const names = {}; for (const v of ['world', 'eu', 'us']) for (const s of M.shapes[v]) if (s.k && !names[s.k]) names[s.k] = s.n;
  for (const [k, d] of Object.entries(M.dots)) names[k] = d.n;
  const ent = () => S.kind === 'unis' ? M.unis : M.cos, isPlace = () => S.kind === 'places';
  const label = (key) => !isPlace() ? ent()[key].n : (names[key] || String(key).toUpperCase());
  // a university's or company's own logo where we have one, else nothing
  const logo = (key, px) => !isPlace() && ent()[key].lg ? `<img class="lgi" src="${ent()[key].lg}" width="${px}" height="${px}" alt="">` : '';
  // the country flag of a university, shown on the World and Europe views
  const flag = (key) => S.kind === 'unis' && S.level !== 'us' && M.unis[key].c ? ' ' + String.fromCodePoint(...[...M.unis[key].c.toUpperCase()].map((ch) => 127397 + ch.charCodeAt(0))) : '';
  const initials = (n) => { const w = n.replace(/[^A-Za-zÀ-ÿ ]/g, '').split(/\s+/).filter(Boolean); return (w.length > 1 ? w[0][0] + w[1][0] : n.slice(0, 2)).toUpperCase(); };

  // the state (US view) or country a university or company sits in, and the same id for a shape on the map
  const entArea = (e) => S.level === 'us' ? e.a[1] : e.a[0];
  const shapeArea = (s) => S.level === 'us' ? s.k : s.n;
  const inArea = (key) => S.area == null || entArea(ent()[key]) === S.area;
  const areaName = () => S.level === 'us' ? (names[S.area] || S.area) : S.area;
  const shown = () => isPlace() ? [...C.agg.values()] : [...C.agg.values()].filter((a) => inArea(a.k));
  // which keys belong to the current choice
  function keysOf(st) {
    if (!isPlace()) return (st[S.kind === 'unis' ? 3 : 6] || []).filter((u) => S.level === 'world' || ent()[u].p[S.level]);
    if (S.level === 'us') return st[2].filter((k) => k.startsWith('US-'));
    if (S.level === 'eu') return st[2].filter((k) => k.length === 2 && EU.has(k));
    return st[2].filter((k) => k.length === 2);
  }
  // one pass over the startups for the chosen years
  function compute() {
    const agg = new Map(); let total = 0;
    ST.forEach((st, i) => {
      let cash = 0, hit = false, last = null;
      for (const r of st[4]) { if (r[0] < S.from || r[0] > S.to) continue; hit = true; if (r[1] && (isPlace() || r[1] < BIG)) cash += r[1]; if (!last || r[0] > last[0]) last = r; }
      if (!hit) return;
      const ks = keysOf(st); if (!ks.length) return; total++;
      for (const k of ks) {
        let a = agg.get(k); if (!a) agg.set(k, a = { k, n: 0, cash: 0, sec: new Map(), list: [] });
        a.n++; a.cash += cash; const s = a.sec.get(st[1]) || { n: 0, cash: 0 }; s.n++; s.cash += cash; a.sec.set(st[1], s); a.list.push([i, last, cash]);
      }
    });
    for (const a of agg.values()) {
      const secs = [...a.sec.entries()].sort((x, y) => y[1].n - x[1].n || y[1].cash - x[1].cash);
      a.order = secs.filter((s) => s[0] !== OTHER).concat(secs.filter((s) => s[0] === OTHER)).map((s) => s[0]); a.top = a.order[0];
    }
    return { agg, total };
  }
  let C = null;

  function squarify(items, x, y, w, h) {
    const out = []; items = items.filter((i) => i[1] > 0); const total = items.reduce((s, i) => s + i[1], 0);
    if (!items.length || w <= 0 || h <= 0) return out;
    const scale = w * h / total; let vals = items.map((i) => [i[0], i[1] * scale]);
    const worst = (row, side) => { const s = row.reduce((a, r) => a + r[1], 0), mx = Math.max(...row.map((r) => r[1])), mn = Math.min(...row.map((r) => r[1])); return Math.max(side * side * mx / (s * s), s * s / (side * side * mn)); };
    while (vals.length) {
      const side = Math.min(w, h); let row = [vals[0]], i = 1;
      while (i < vals.length && worst(row.concat([vals[i]]), side) <= worst(row, side)) { row.push(vals[i]); i++; }
      const s = row.reduce((a, r) => a + r[1], 0);
      if (w >= h) { const cw = s / h; let cy = y; for (const r of row) { const ch = r[1] / cw; out.push([r[0], x, cy, cw, ch]); cy += ch; } x += cw; w -= cw; }
      else { const ch = s / w; let cx = x; for (const r of row) { const cw = r[1] / ch; out.push([r[0], cx, y, cw, ch]); cx += cw; } y += ch; h -= ch; }
      vals = vals.slice(i);
    }
    return out;
  }

  // ---------- the map ----------
  // The map sits exactly where the main map sits: the same room is left for the buttons above it and the timeline below
  // (map.js: ROOM), so switching views does not make the map jump. Zoom and position are kept per region.
  const NOW = new Date(), TODAY = NOW.getFullYear() * 10000 + (NOW.getMonth() + 1) * 100 + NOW.getDate();
  const ROOM = { world: [16, 16, 84, 104], us: [24, 24, 96, 120], eu: [24, 24, 62, 100] };
  const Z = {};
  const LINE = { world: 1.1, us: 1.5, eu: 1.3 };  // width of the white border lines in map units, as build.py draws them into <level>-land.svg
  const NARROW = matchMedia('(max-width:900px)');  // on a phone this view is a block of its own, not a layer over the page's map
  let fresh = true;  // the colours fade in when the view, the zoom or the choice changes, not on every count
  const view = () => M.views[S.level];
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  function base() {  // the whole map at rest, in map units, for the box it is drawn in
    const st = $('#stage'), W = st.clientWidth || 1, H = st.clientHeight || 1, V = view(), [l, r, t, b] = W < 700 ? [6, 6, 6, 6] : ROOM[S.level];
    const k = Math.max(0.2, Math.min((W - l - r) / V.w, (H - t - b) / V.h)), ox = l + (W - l - r - V.w * k) / 2;
    return { W, x: -ox / k, y: -t / k, w: W / k, h: H / k };
  }
  function vbox() {
    const B = base(), s = Z[S.level] || (Z[S.level] = { z: 1, cx: 0, cy: 0 }), w = B.w / s.z, h = B.h / s.z;
    if (s.z <= 1.0001) { s.z = 1; s.cx = B.x + B.w / 2; s.cy = B.y + B.h / 2; }
    s.cx = clamp(s.cx, B.x + w / 2, B.x + B.w - w / 2); s.cy = clamp(s.cy, B.y + h / 2, B.y + B.h - h / 2);
    return { v: [s.cx - w / 2, s.cy - h / 2, w, h], k: w / B.W, z: s.z };  // k: map units per pixel on screen
  }
  function drawMap() {
    const st = $('#stage'), agg = C.agg, places = isPlace(); let h = '', selD = '';
    const live = new Set(); if (!places) for (const a of agg.values()) { const e = ent()[a.k]; if (e.p[S.level] && entArea(e)) live.add(entArea(e)); }
    for (const s of M.shapes[S.level]) {
      const a = places && s.k ? agg.get(s.k) : null;
      if (S.level === 'eu' && s.k && !EU.has(s.k)) { h += `<path class="shp plain" d="${s.d}"/>`; continue; }
      if (!places && live.has(shapeArea(s))) { const id = shapeArea(s); if (S.area === id) selD = s.d; h += `<path class="shp has${S.area === id ? ' on" fill="#B1BDB8' : ' plain'}" d="${s.d}" data-a="${esc(id)}" tabindex="0" role="button" aria-label="${esc(s.n)}"/>`; continue; }
      if (a && S.sel === s.k) selD = s.d;
      h += `<path class="shp${a ? ' has tint' : ' plain'}${a && S.sel === s.k ? ' on' : ''}" d="${s.d}"${a ? ` fill="${col(a.top)}"` : ''}${a ? ` data-k="${s.k}" tabindex="0" role="button" aria-label="${esc(s.n)}"` : ''}/>`;
    }
    st.innerHTML = `<svg preserveAspectRatio="xMidYMid meet" width="100%" height="100%" class="${S.sel != null && (places || S.area == null) ? 'dim' : ''}${!places && S.area != null ? ' areaon' : ''}${fresh ? ' soft' : ''}" style="--k:1"><style>.lab{font-size:calc(12px * var(--k))}</style><defs><clipPath id="round" clipPathUnits="objectBoundingBox"><circle cx=".5" cy=".5" r=".5"/></clipPath><clipPath id="frame"><rect width="${view().w}" height="${view().h}"/></clipPath></defs><g clip-path="url(#frame)">${h}</g><path class="ring sel" d="${selD}"/><path class="ring hov" d=""/><g id="marks"></g></svg><div class="zoom"><button data-z="in" aria-label="Zoom in">+</button><button data-z="out" aria-label="Zoom out">−</button></div>${places ? '' : '<p class="mapnote">Rounds of $1B or more are not counted in the cash here.</p>'}`;
    fresh = false; applyView();
  }
  function applyView() {
    const svg = $('#stage svg'); if (!svg) return; const { v, k, z } = vbox();
    // its own land only where the page's picture cannot follow; the white lines are as thick as the picture's
    $('#stage').classList.toggle('own', NARROW.matches || z > 1 || S.sel != null || S.area != null);
    svg.style.setProperty('--lw', (LINE[S.level] / (k * z)).toFixed(2) + 'px');
    svg.setAttribute('viewBox', v.map((n) => +n.toFixed(2)).join(' ')); svg.style.setProperty('--k', k); drawMarks(k, z);
  }
  // everything that keeps its size on screen while the map is zoomed: numbers, small-country circles, university and company circles
  function drawMarks(k, z) {  // k: map units per pixel, so a size times k stays that many pixels; z: how far the map is zoomed in
    const agg = C.agg, lv = S.level; let h = '';
    const marker = (x, y, key, name, a) => {
      h += `<circle class="dot${S.sel === key ? ' on' : ''}" cx="${x}" cy="${y}" r="${(5.5 * Math.sqrt(z) * k).toFixed(2)}" fill="${col(a.top)}" stroke="#10201C" stroke-width="1" data-k="${key}" tabindex="0" role="button" aria-label="${esc(name)}"/>`;
      if (a.n >= 20 || z >= 2) h += `<text class="lab" style="text-anchor:start" x="${(x + (5.5 * Math.sqrt(z) + 4) * k).toFixed(1)}" y="${y}" dy="0.35em">${a.n >= 100 || z >= 2 ? `<tspan class="n">${esc(name)} </tspan>` : ''}<tspan class="c">${num(a.n)}</tspan></text>`;
    };
    if (isPlace()) {
      for (const s of M.shapes[lv]) {
        const a = s.k ? agg.get(s.k) : null; if (!a || (lv === 'eu' && !EU.has(s.k))) continue;
        const seen = s.a / (k * k);  // how big the shape is on screen
        if (seen < 70) { marker(s.x, s.y, s.k, s.n, a); continue; }  // too small to see: a circle with its number
        if (seen <= (lv === 'us' ? 700 : lv === 'eu' ? 450 : 1300)) continue;
        const short = lv === 'us' ? s.k.slice(3) : s.k === 'gb' ? 'UK' : s.k === 'us' ? 'US' : seen > (lv === 'eu' ? 2600 : 5200) ? s.n : lv === 'eu' ? s.k.toUpperCase() : '';
        h += `<text class="lab" x="${s.x}" y="${s.y}">${short ? `<tspan class="n" x="${s.x}" dy="-0.15em">${esc(short)}</tspan><tspan class="c" x="${s.x}" dy="1.1em">${num(a.n)}</tspan>` : `<tspan class="c" x="${s.x}" dy="0.35em">${num(a.n)}</tspan>`}</text>`;
      }
      for (const [key, d] of Object.entries(M.dots)) { const p = d[lv], a = agg.get(key); if (p && a && (lv !== 'eu' || EU.has(key))) marker(p[0], p[1], key, d.n, a); }
    } else {
      const g = Math.sqrt(z);  // circles grow as the map is zoomed in
      const pins = [...agg.values()].filter((a) => ent()[a.k].p[lv]).sort((x, y) => y.cash - x.cash), mx = Math.max(1, ...pins.map((a) => a.cash)), big = lv === 'world' ? 26 : 34, put = [];
      for (const a of pins) {
        const p = ent()[a.k].p[lv], rs = Math.min(64, Math.max(5.5, Math.sqrt(a.cash / mx) * big) * g), r = rs * k, n = ent()[a.k].n;
        // circles that share a city: the bigger one keeps its spot, the next one moves to the nearest free spot beside it
        let x = p[0], y = p[1];
        for (let t = 1; t < 3000 && put.some((q) => Math.hypot(q[0] - x, q[1] - y) < q[2] + r + 1.5 * k); t++) { const d = 0.55 * r * Math.sqrt(t), an = t * 2.39996; x = p[0] + d * Math.cos(an); y = p[1] + d * Math.sin(an); }
        put.push([x, y, r]);
        const fits = rs >= 20 && n.length * 6.6 < rs * 2 - 8, off = !inArea(a.k), lg = ent()[a.k].lg, q = lg && ent()[a.k].fb ? 0.82 : 0.6;  // a logo on a filled or white square is cut round and fills the circle; a logo on a clear ground sits whole inside it
        h += `<g class="pin${S.sel === a.k ? ' on' : ''}${off ? ' off' : ''}" data-k="${a.k}" tabindex="0" role="button" aria-label="${esc(n)}"><circle cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="${r.toFixed(2)}" fill="${col(a.top)}"/>${lg && rs >= 9 ? `<circle class="in" cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="${(r * 0.82).toFixed(2)}" fill="#fff"/><image href="${lg}"${ent()[a.k].fb ? ' clip-path="url(#round)"' : ''} x="${(x - r * q).toFixed(2)}" y="${(y - r * q).toFixed(2)}" width="${(r * q * 2).toFixed(2)}" height="${(r * q * 2).toFixed(2)}"/>` : rs >= 13 ? `<text class="lab" x="${x.toFixed(2)}" y="${y.toFixed(2)}" dy="0.35em" style="font-size:${((fits ? 12 : Math.min(13, rs * 0.62)) * k).toFixed(2)}px;font-weight:600">${esc(fits ? n : initials(n))}</text>` : ''}</g>`;
      }
    }
    $('#marks').innerHTML = h;
  }
  function zoomAt(f, ux, uy) {  // f below 1 zooms in; (ux, uy) is the point that stays put, in map units
    vbox(); const s = Z[S.level], z = clamp(s.z / f, 1, 16), r = s.z / z;
    if (ux == null) { ux = s.cx; uy = s.cy; }
    s.cx = ux - (ux - s.cx) * r; s.cy = uy - (uy - s.cy) * r; s.z = z; applyView();
  }
  const toUser = (x, y) => { const m = $('#stage svg').getScreenCTM(); return [(x - m.e) / m.a, (y - m.f) / m.d]; };
  // ---------- the blocks ----------
  function drawBlocks() {
    const st = $('#stage'); st.classList.add('own'); st.innerHTML = '<div class="blocks"></div>'; const W = st.firstChild.clientWidth, H = st.firstChild.clientHeight;
    const items = shown().filter((a) => a.cash > 0).sort((x, y) => y.cash - x.cash).slice(0, 18);
    if (!items.length) { st.innerHTML = '<div class="empty">No rounds with a known amount for this choice. Try a longer stretch of time.</div>'; return; }
    let h = '';
    for (const [k, x, y, w, hh] of squarify(items.map((a) => [a.k, a.cash]), 0, 0, W, H)) {
      const a = C.agg.get(k), hd = hh > 64 ? 30 : 0, n = label(k);
      const secs = [...a.sec.entries()].filter((s) => s[1].cash > 0).sort((p, q) => q[1].cash - p[1].cash), area = w * hh, keep = area > 90000 ? 10 : area > 45000 ? 6 : area > 22000 ? 4 : area > 9000 ? 2 : 1, topS = secs.slice(0, keep), rest = area > 4500 ? secs.slice(keep).reduce((s, e) => s + e[1].cash, 0) : 0;
      const parts = area > 4500 ? topS.map((s) => [s[0], s[1].cash]).concat(rest > 0 ? [[OTHER + 100, rest]] : []) : [[topS[0][0], a.cash]];
      let inner = '';
      for (const [sid, sx, sy, sw, sh] of squarify(parts, 0, hd, w - 9, hh - 9 - hd)) { const id = sid > 100 ? OTHER : sid, v = parts.find((p) => p[0] === sid)[1];
        inner += `<i style="left:${(sx + 1).toFixed(1)}px;top:${(sy + 1).toFixed(1)}px;width:${Math.max(sw - 2, 0).toFixed(1)}px;height:${Math.max(sh - 2, 0).toFixed(1)}px;background:${sid > 100 ? '#ECEFEE' : col(id)}">${sw > 92 && sh > 40 ? `<b>${esc(sid > 100 ? 'Everything else' : M.sectors[id])}</b><span>${money(v)}</span>` : sw > 74 && sh > 22 ? `<b>${esc(sid > 100 ? 'Rest' : M.sectors[id])}</b>` : ''}</i>`; }
      h += `<button class="bk${S.sel === k ? ' on' : ''}" data-k="${k}" style="left:${x.toFixed(1)}px;top:${y.toFixed(1)}px;width:${w.toFixed(1)}px;height:${hh.toFixed(1)}px" aria-label="${esc(n)}"><div>${hd ? `<span class="bkh">${!isPlace() ? (logo(k, 20) || `<span class="lg">${esc(initials(n))}</span>`) : ''}<b>${esc(n)}${flag(k)}</b><span>${money(a.cash)}</span></span>` : ''}${inner}</div></button>`;
    }
    st.innerHTML = `<div class="blocks${S.sel != null ? ' dim' : ''}">${h}</div>`;
  }

  // ---------- the left side ----------
  const where = () => S.level === 'us' ? 'the US' : S.level === 'eu' ? 'Europe' : 'a country we know';
  // The head card is the same four rows in every view (founder, 25 Nov): one fixed title line, the three choices, one
  // "Based on" line, the black button. What is pressed is named by the list card, not by the title.
  const iso = (d) => `${Math.floor(d / 10000)}-${String(Math.floor(d / 100) % 100).padStart(2, '0')}-${String(d % 100).padStart(2, '0')}`;
  const keyOf = (k) => isPlace() ? String(k) : ent()[k].n;  // how the Investors list is told what the map shows
  function listUrl() {  // the firms that backed the startups shown: the pressed one, or everything in the list
    const a = S.sel != null ? C.agg.get(S.sel) : null, all = shown(), n = all.length;
    const group = isPlace() ? (S.level === 'us' ? 'United States' : S.level === 'eu' ? 'Europe' : 'all countries')
      : `${num(n)} ${S.kind === 'unis' ? (n === 1 ? 'university' : 'universities') : (n === 1 ? 'company' : 'companies')}${S.area != null ? ' in ' + areaName() : ''}`;
    const q = ['zoom=' + (isPlace() ? 'fplace' : S.kind === 'unis' ? 'funi' : 'fco'),
      'place=' + encodeURIComponent(a ? keyOf(S.sel) : all.map((x) => keyOf(x.k)).join('|')),
      'pname=' + encodeURIComponent('Founders: ' + (a ? label(S.sel) : group)),
      'from=' + iso(Math.max(S.from, 20210101)), 'to=' + iso(Math.min(S.to, TODAY))];
    return O.root + 'investors/?' + q.join('&');
  }
  function drawHead() {
    $('#h1').textContent = 'What founders are building.';
    $('#cta').href = listUrl();
    const n = shown().length, ids = new Set(); for (const x of shown()) for (const l of x.list) ids.add(l[0]);
    const things = isPlace() ? (S.level === 'us' ? (n === 1 ? 'state' : 'states') : (n === 1 ? 'country' : 'countries')) : S.kind === 'unis' ? (n === 1 ? 'university' : 'universities') : (n === 1 ? 'company' : 'companies');
    $('#based').textContent = `Based on ${num(isPlace() ? C.total : ids.size)} startups, ${num(n)} ${things}`;
  }
  let showRest = () => '';
  function drawPanel() {
    const p = $('#panel'), unit = S.kind === 'unis' ? 'Universities' : S.kind === 'cos' ? 'Companies' : S.level === 'us' ? 'States' : 'Countries';
    if (S.sel == null || !C.agg.get(S.sel)) {
      const rows = shown().sort((x, y) => !isPlace() || S.mode === 'blocks' ? y.cash - x.cash || y.n - x.n : y.n - x.n || y.cash - x.cash);
      const byCash = !isPlace() || S.mode === 'blocks';
      $('#ptitle').innerHTML = S.area != null && !isPlace() ? unit + ' in ' + esc(areaName()) : unit;
      p.innerHTML = (S.area != null && !isPlace() ? `<button class="back" id="backarea">← All ${unit.toLowerCase()}</button>` : '') + (rows.length ? rows.slice(0, 60).map((a) => `<button class="row" data-k="${a.k}"><i class="sw" style="background:${col(a.top)}"></i><span><b>${logo(a.k, 20)}${esc(label(a.k))}${flag(a.k)}</b><small>${esc(M.sectors[a.top])}${a.order[1] ? ' · ' + esc(M.sectors[a.order[1]]) : ''} · ${byCash ? num(a.n) + (a.n === 1 ? ' startup' : ' startups') : (money(a.cash) || 'amount not known')}</small></span><strong>${byCash ? (money(a.cash) || '–') : num(a.n)}</strong></button>`).join('') : '<p class="note">Nothing for this choice. Try a longer stretch of time.</p>');
      p.scrollTop = 0; return;
    }
    const a = C.agg.get(S.sel), n = label(S.sel);
    const firms = new Map(); for (const [i] of a.list) for (const f of ST[i][5]) firms.set(f, (firms.get(f) || 0) + 1);
    const topF = [...firms.entries()].sort((x, y) => y[1] - x[1]).slice(0, 10);
    const all = a.list.slice().sort((x, y) => y[1][0] - x[1][0]), list = all.slice(0, 25);
    const srow = ([i, last]) => `<div class="row"><i class="sw" style="background:${col(ST[i][1])}"></i><span><b>${esc(ST[i][0])}</b><small>${esc(M.sectors[ST[i][1]])}${last[2] ? ' · ' + esc(last[2]) : ''} · ${day(last[0])}</small></span><strong>${last[1] ? money(last[1]) : ''}</strong></div>`;
    showRest = () => all.slice(25).map(srow).join('');  // the rest of the list, drawn when asked for (founder, 25 Nov)
    $('#ptitle').innerHTML = `${logo(S.sel, 24)}${esc(n)}${flag(S.sel)}`;
    p.innerHTML = `<button class="back" id="back">← ${S.area != null && !isPlace() ? unit + ' in ' + esc(areaName()) : 'All ' + unit.toLowerCase()}</button>
      <p class="stat"><b>${num(a.n)}</b> ${a.n === 1 ? 'startup' : 'startups'}${a.cash ? ` · <b>${money(a.cash)}</b> raised` : ''}</p>
      <div class="bar">${a.order.map((s) => `<i style="flex:${a.sec.get(s).n};background:${col(s)}" title="${esc(M.sectors[s])}: ${a.sec.get(s).n}"></i>`).join('')}</div>
      <div class="key" style="margin-top:10px">${a.order.slice(0, 6).map((s) => `<span><i class="sw" style="background:${col(s)}"></i>${esc(M.sectors[s])} ${a.sec.get(s).n}</span>`).join('')}</div>
      <h3>Who invested</h3>${topF.length ? topF.map(([f, c]) => `<div class="row"><i></i><span>${M.firms[f][1] ? `<a href="${VC}${encodeURIComponent(M.firms[f][1])}/"><b>${esc(M.firms[f][0])}</b></a>` : `<b>${esc(M.firms[f][0])}</b>`}</span><strong>${num(c)} ${c === 1 ? 'startup' : 'startups'}</strong></div>`).join('') : '<p class="note">No investor on record.</p>'}
      <p class="note">${num(firms.size)} firms in total.</p>
      <h3>Startups, newest round first</h3>${list.map(srow).join('')}
      ${all.length > list.length ? `<button class="more" id="more">Show all ${num(all.length)} startups</button>` : ''}`;
    p.scrollTop = 0;
  }
  function segs() {
    for (const [id, v] of [['#seg-kind', S.kind], ['#seg-mode', S.mode]]) for (const b of root.querySelectorAll(id + ' button')) b.setAttribute('aria-pressed', String(b.dataset.v === v));
  }
  function render() { C = compute(); if (S.sel != null && !C.agg.get(S.sel)) S.sel = null; if (isPlace()) S.area = null; segs(); drawHead(); drawPanel(); if (S.mode === 'map') drawMap(); else drawBlocks(); }
  function select(k) { if (k == null) S.sel = null; else { k = !isPlace() ? Number(k) : k; S.sel = S.sel === k ? null : k; } hideTip(); render(); }

  // ---------- events ----------
  for (const [id, key] of [['#seg-kind', 'kind'], ['#seg-mode', 'mode']]) $(id).addEventListener('click', (e) => { const b = e.target.closest('button'); if (!b) return; const v = b.dataset.v; if (S[key] === v) return; S[key] = v; fresh = true; if (key === 'kind' || key === 'level') S.sel = null; if (key === 'level') S.area = null; render(); });
  $('#panel').addEventListener('click', (e) => { const m = e.target.closest('#more'); if (m) { m.outerHTML = showRest(); return; } if (e.target.closest('#backarea')) { S.area = null; return render(); } if (e.target.closest('#back')) return select(null); const r = e.target.closest('button.row'); if (r) select(r.dataset.k); });
  let dragged = false, drag = null, pinch = 0; const ptrs = new Map();
  $('#stage').addEventListener('click', (e) => {
    if (dragged) { dragged = false; return; }
    const zb = e.target.closest('[data-z]'); if (zb) { zoomAt(zb.dataset.z === 'in' ? 1 / 1.7 : 1.7); return; }
    const t = e.target.closest('[data-k]'); if (t) return select(t.dataset.k);
    const ar = e.target.closest('[data-a]'); if (ar) { S.area = S.area === ar.dataset.a ? null : ar.dataset.a; S.sel = null; hideTip(); return render(); }
    if (S.sel != null) select(null);
  });
  $('#stage').addEventListener('wheel', (e) => { if (S.mode !== 'map' || !$('#stage svg')) return; e.preventDefault(); const [x, y] = toUser(e.clientX, e.clientY); zoomAt(Math.exp(clamp(e.deltaY, -60, 60) * 0.004), x, y); hideTip(); }, { passive: false });
  $('#stage').addEventListener('pointerdown', (e) => {
    if (S.mode !== 'map' || e.target.closest('.zoom')) return; ptrs.set(e.pointerId, [e.clientX, e.clientY]);
    if (ptrs.size === 1) { vbox(); drag = { x: e.clientX, y: e.clientY, cx: Z[S.level].cx, cy: Z[S.level].cy }; dragged = false; }
    else if (ptrs.size === 2) { const p = [...ptrs.values()]; pinch = Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]); drag = null; dragged = true; }
  });
  addEventListener('pointermove', (e) => {
    if (!ptrs.has(e.pointerId) || !$('#stage svg')) return; ptrs.set(e.pointerId, [e.clientX, e.clientY]);
    if (ptrs.size === 2) { const p = [...ptrs.values()], d = Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]); if (pinch && d) { const m = toUser((p[0][0] + p[1][0]) / 2, (p[0][1] + p[1][1]) / 2); zoomAt(pinch / d, m[0], m[1]); pinch = d; } return; }
    if (!drag) return; const dx = e.clientX - drag.x, dy = e.clientY - drag.y; if (!dragged && Math.hypot(dx, dy) < 5) return; dragged = true;
    const m = $('#stage svg').getScreenCTM(), z0 = Z[S.level]; z0.cx = drag.cx - dx / m.a; z0.cy = drag.cy - dy / m.d; applyView(); hideTip();
  });
  const endPtr = (e) => { ptrs.delete(e.pointerId); if (ptrs.size < 2) pinch = 0; if (!ptrs.size) drag = null; };
  addEventListener('pointerup', endPtr); addEventListener('pointercancel', endPtr);
  $('#stage').addEventListener('keydown', (e) => { if (e.key !== 'Enter' && e.key !== ' ') return; const t = e.target.closest('[data-k]'), ar = e.target.closest('[data-a]'); if (t) { e.preventDefault(); select(t.dataset.k); } else if (ar) { e.preventDefault(); S.area = S.area === ar.dataset.a ? null : ar.dataset.a; S.sel = null; render(); } });
  const tip = $('#tip'); function hideTip() { tip.style.display = 'none'; }
  $('#stage').addEventListener('mousemove', (e) => {
    const hv = $('#stage .ring.hov'); if (hv) { const sh = e.target.closest('.shp.has'), d = sh && !sh.classList.contains('on') && !(drag && dragged) ? sh.getAttribute('d') : ''; if (hv.getAttribute('d') !== d) hv.setAttribute('d', d); }
    const t = e.target.closest('[data-k]'), place = (html) => { tip.innerHTML = html; tip.style.display = 'flex'; const w = tip.offsetWidth, hh = tip.offsetHeight; tip.style.left = Math.min(innerWidth - w - 8, e.clientX + 14) + 'px'; tip.style.top = Math.max(8, e.clientY - hh - 12) + 'px'; };
    if (!t) { const ar = e.target.closest('[data-a]'); if (!ar || drag && dragged) return hideTip(); const id = ar.dataset.a, c = [...C.agg.values()].filter((x) => ent()[x.k].p[S.level] && entArea(ent()[x.k]) === id).length; return place(`<b>${esc(S.level === 'us' ? (names[id] || id) : id)}</b><span class="mu">${num(c)} ${S.kind === 'unis' ? (c === 1 ? 'university' : 'universities') : (c === 1 ? 'company' : 'companies')}</span><span>Press to list them</span>`); }
    const k = !isPlace() ? Number(t.dataset.k) : t.dataset.k, a = C.agg.get(k); if (!a) return hideTip();
    // the sectors with their share of the startups there, as on the main map's hover card
    let used = 0; const tot = a.n || 1, top = a.order.slice(0, 5).map((sid, n2) => { const pc = Math.round(a.sec.get(sid).n / tot * 100); used += pc; return `<span class="tr"><i style="background:${col(sid)}"></i><span>${n2 + 1}. ${esc(sname(sid))}</span><span class="pc">${pc}%</span></span>`; }).join('');
    place(`<b>${logo(k, 18)}${esc(label(k))}${flag(k)}</b><span class="mu">${num(a.n)} ${a.n === 1 ? 'startup' : 'startups'}${a.cash ? ' · ' + money(a.cash) : ''}</span>${top}${a.order.length > 5 ? `<span class="tr"><i style="background:#EEF1F0"></i><span>All other sectors</span><span class="pc">${Math.max(0, 100 - used)}%</span></span>` : ''}`);
  });
  $('#stage').addEventListener('mouseleave', () => { hideTip(); const hv = $('#stage .ring.hov'); if (hv) hv.setAttribute('d', ''); });
  let rz = 0; addEventListener('resize', () => { clearTimeout(rz); rz = setTimeout(() => { if (host.hidden) return; if (S.mode === 'blocks') drawBlocks(); else applyView(); }, 150); });
  api.setLevel = (l) => { if (!['world', 'us', 'eu'].includes(l) || l === S.level) return; S.level = l; S.sel = null; S.area = null; fresh = true; hideTip(); render(); };
  // shown again after another view: the map at rest, nothing pressed, so it is the very map the visitor was looking at
  api.redraw = () => { for (const k of Object.keys(Z)) delete Z[k]; S.sel = null; S.area = null; fresh = true; hideTip(); render(); };
  // the page's timeline moved: count again for that stretch of time
  api.setSpan = (sp) => { if (!sp || (sp.from === S.from && sp.to === S.to)) return; S.from = sp.from; S.to = sp.to; S.when = sp.text; hideTip(); render(); };
  if (['world', 'us', 'eu'].includes(want) && want !== S.level) S.level = want;
  if (span) { S.from = span.from; S.to = span.to; S.when = span.text; }  // the timeline may have moved while the data was loading
  render();
  if (window.REGRET_TRACK) window.REGRET_TRACK('founders_view', { level: S.level });
}
})();
