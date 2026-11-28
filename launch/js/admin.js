// Admin analytics page (28 Nov 2026, claude/plans/admin-analytics.md). Shows "page not found" to everyone except an admin account.
// The lock is in the database: analytics_is_admin() and admin_report() answer false / nothing to anyone else. This file only draws the answer.
(function () {
  const C = window.REGRET || {};
  const sb = C.url && C.key && window.supabase ? window.supabase.createClient(C.url, C.key) : null;
  const host = document.getElementById('adm'), notfound = document.getElementById('adm404');
  if (!sb || !host) return;
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  const AMBER = '#C77700', INK = '#14112B';
  const MAPS = [['trends', 'Trends'], ['top', 'Top 100'], ['flow', 'Money flow'], ['founders', 'Founders'], ['pathfinders', 'Pathfinders']];
  let DAYS = 7, TOKEN = 0;

  const fmt = (n) => Number(n || 0).toLocaleString('en-US');
  const usd = (cents) => '$' + (Number(cents || 0) / 100).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  const when = (t) => { const d = new Date(t); return isNaN(d) ? '' : d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }); };
  const dur = (s) => { s = Math.round(s || 0); return s >= 60 ? Math.floor(s / 60) + 'm ' + String(s % 60).padStart(2, '0') + 's' : s + 's'; };
  const change = (a, b) => {
    if (!b) return a ? '<span class="up">new</span>' : '<span class="fl">no change</span>';
    const p = Math.round((a - b) / b * 100);
    return p === 0 ? '<span class="fl">0%</span>' : `<span class="${p > 0 ? 'up' : 'dn'}">${p > 0 ? '+' : ''}${p}%</span>`;
  };
  const scoreCls = (s) => (s == null || s === '' ? '' : Number(s) >= 8 ? 'g' : Number(s) >= 5 ? 'a' : 'r');

  const CSS = `<style>
  .adm{max-width:1120px;margin:0 auto;padding:32px 32px 80px;color:${INK}}
  .adm h1{font:600 32px 'Geist',sans-serif;letter-spacing:-.5px}.adm h2{font:600 16px 'Geist',sans-serif;margin:0 0 12px}
  .adm .top{display:flex;justify-content:space-between;align-items:center;margin-bottom:24px}
  .adm .sw{display:flex;border:1px solid var(--line)}.adm .sw button{border:0;background:#fff;padding:9px 16px;font:500 14px 'Geist',sans-serif;cursor:pointer;color:var(--ink2)}
  .adm .sw button[aria-pressed=true]{background:${AMBER};color:#fff}
  .adm .nums{display:grid;grid-template-columns:repeat(6,1fr);border:1px solid var(--line);margin-bottom:24px}
  .adm .nums div{padding:16px;border-right:1px solid var(--line)}.adm .nums div:last-child{border:0}
  .adm .nums b{display:block;font:600 28px 'Geist',sans-serif}.adm .nums small{color:var(--mute);font-size:13px;display:block;margin-bottom:6px}
  .adm .up{color:#1F9D55}.adm .dn{color:#C4281C}.adm .fl{color:var(--mute)}.adm .nums span{font-size:13px}
  .adm .box{border:1px solid var(--line);padding:20px;margin-bottom:24px;min-width:0}
  .adm .two{display:grid;grid-template-columns:1fr 1fr;gap:24px}.adm .two .box{margin-bottom:0}.adm .gap{margin-bottom:24px}
  .adm table{width:100%;border-collapse:collapse;font-size:14px}.adm th{text-align:left;font-weight:500;color:var(--mute);padding:6px 8px;border-bottom:1px solid var(--line)}
  .adm td{padding:8px;border-bottom:1px solid var(--line);vertical-align:top;overflow-wrap:anywhere}.adm td.n,.adm th.n{text-align:right}
  .adm .sc{display:inline-block;min-width:28px;padding:2px 6px;text-align:center;font-weight:600;color:#fff;background:var(--mute)}.adm .sc.g{background:#1F9D55}.adm .sc.a{background:#D99A00}.adm .sc.r{background:#C4281C}
  .adm .bar{height:10px;background:${AMBER};display:block}.adm .bar.f{background:#EFE3CC}
  .adm .none{color:var(--mute);font-size:14px}.adm .legend{display:flex;gap:16px;font-size:13px;color:var(--ink2);margin-top:8px}.adm .legend i{display:inline-block;width:14px;height:5px;margin-right:6px;vertical-align:middle}
  .adm .scroll{overflow-x:auto}
  @media(max-width:860px){.adm .nums{grid-template-columns:repeat(2,1fr)}.adm .two{grid-template-columns:1fr}.adm{padding:20px 16px 60px}}
  </style>`;

  function worm(rows, hourly) {
    const W = 1000, H = 220, P = 28, n = rows.length;
    if (!n) return '<p class="none">No data yet.</p>';
    const max = Math.max(1, ...rows.map((r) => Math.max(r.visitors, r.registrations)));
    const x = (i) => P + (n === 1 ? 0 : i * (W - 2 * P) / (n - 1)), y = (v) => H - P - v * (H - 2 * P) / max;
    const path = (k) => rows.map((r, i) => (i ? 'L' : 'M') + x(i).toFixed(1) + ',' + y(r[k]).toFixed(1)).join('');
    const step = Math.max(1, Math.ceil(n / 8));
    const lab = rows.map((r, i) => (i % step ? '' : `<text x="${x(i)}" y="${H - 6}" text-anchor="middle" font-size="12" fill="#586964">${esc(hourly ? new Date(r.t).toLocaleTimeString('en-US', { hour: 'numeric' }) : new Date(r.t).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }))}</text>`)).join('');
    return `<svg viewBox="0 0 ${W} ${H}" width="100%" role="img" aria-label="Visitors and registrations over time"><line x1="${P}" x2="${W - P}" y1="${H - P}" y2="${H - P}" stroke="#E2E7E5"/>`
      + `<path d="${path('visitors')}" fill="none" stroke="${AMBER}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>`
      + `<path d="${path('registrations')}" fill="none" stroke="${INK}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>${lab}</svg>`
      + `<div class="legend"><span><i style="background:${AMBER}"></i>Visitors (top ${fmt(max)})</span><span><i style="background:${INK}"></i>Registrations</span></div>`;
  }

  const table = (head, rows, empty) => rows.length ? `<div class="scroll"><table><tr>${head.map((h) => `<th${h[1] ? ' class="n"' : ''}>${h[0]}</th>`).join('')}</tr>${rows.join('')}</table></div>` : `<p class="none">${empty}</p>`;

  function draw(r) {
    const N = r.numbers, hourly = r.days === 1;
    const tile = (label, k, money) => `<div><small>${label}</small><b>${money ? usd(N[k][0]) : fmt(N[k][0])}</b><span>${change(N[k][0], N[k][1])}</span></div>`;
    const mp = {}; (r.maps || []).forEach((m) => { mp[m.view] = m; });
    const tot = Object.values(mp).reduce((a, m) => a + (m.secs || 0), 0);
    const maps = MAPS.map(([k, name]) => { const m = mp[k]; return `<tr><td>${name}</td><td class="n">${tot && m ? Math.round(m.secs * 100 / tot) + '%' : '0%'}</td><td class="n">${m && m.visits ? dur(m.secs / m.visits) : '·'}</td></tr>`; }).join('');
    const src = (r.sources || []).map((s) => `<tr><td>${esc(s.source)}</td><td class="n">${fmt(s.visitors)}</td><td class="n">${fmt(s.registered)}</td></tr>`);
    const F = r.funnel, top = Math.max(1, F.visited, F.registered, F.opened, F.deck, F.paid);
    const fun = [['Visited', F.visited], ['Registered', F.registered], ['Opened a firm', F.opened], ['Uploaded a deck', F.deck], ['Paid', F.paid]]
      .map(([l, v]) => `<tr><td style="width:150px">${l}</td><td><span class="bar" style="width:${Math.max(2, v * 100 / top)}%"></span></td><td class="n" style="width:70px">${fmt(v)}</td></tr>`).join('');
    const reg = (r.registrations || []).map((u) => `<tr><td>${esc(when(u.at))}</td><td>${esc(u.email)}</td><td>${esc(u.src || 'unknown')}</td><td>${u.invite ? esc(u.invite) : '·'}</td>`
      + `<td>${[u.opened ? 'opened ' + u.opened + ' firm' + (u.opened > 1 ? 's' : '') : '', u.decks ? u.decks + ' deck' + (u.decks > 1 ? 's' : '') : '', u.paid ? 'paid ' + usd(u.paid) : ''].filter(Boolean).join(', ') || 'nothing yet'}</td></tr>`);
    const decks = (r.deckrows || []).map((d) => `<tr><td>${esc(when(d.at))}</td><td>${esc(d.email)}</td><td>${esc(d.file || '')}</td><td>${esc([d.stage, d.sector].filter(Boolean).join(' · '))}</td>`
      + `<td>${d.score != null && d.score !== '' ? `<span class="sc ${scoreCls(d.score)}">${esc(d.score)}</span>` : (d.status === 'failed' ? 'failed' : '·')}</td><td>${esc(d.verdict || '')}</td><td>${d.research ? 'yes' : 'no'}</td></tr>`);
    const inv = (r.invites || []).map((i) => `<tr><td>${esc(i.by)}</td><td>${esc(i.who)}</td><td class="n">${fmt(i.credits)}</td></tr>`);
    const asks = (r.requests || []).map((q) => `<tr><td>${esc(q.firm)}</td><td>${esc(when(q.at))}</td><td>${esc(q.by)}</td></tr>`);
    const firms = (r.firms || []).map((f) => `<tr><td>${esc(f.firm)}</td><td class="n">${fmt(f.opens)}</td></tr>`);
    const K = r.cost;
    host.innerHTML = CSS
      + `<div class="top"><h1>Analytics</h1><div class="sw" role="group" aria-label="Period">${[[1, '1 day'], [7, '7 days'], [30, '30 days']].map(([d, l]) => `<button type="button" data-d="${d}" aria-pressed="${d === r.days}">${l}</button>`).join('')}</div></div>`
      + `<div class="nums">${tile('Visitors', 'visitors')}${tile('New registrations', 'registrations')}${tile('Through an invite', 'invites')}${tile('Deck uploads', 'decks')}${tile('Full researches', 'researches')}${tile('Revenue', 'revenue', 1)}</div>`
      + `<div class="box"><h2>Visitors and registrations ${hourly ? 'per hour' : 'per day'}</h2>${worm(r.chart || [], hourly)}</div>`
      + `<div class="two gap"><div class="box"><h2>Time on each map</h2><table><tr><th>Map</th><th class="n">Share of time</th><th class="n">Average visit</th></tr>${maps}</table></div>`
      + `<div class="box"><h2>Where people come from</h2>${table([['Source'], ['Visitors', 1], ['Registered', 1]], src, 'No visits counted yet.')}</div></div>`
      + `<div class="box"><h2>From visit to payment</h2><table>${fun}</table></div>`
      + `<div class="box"><h2>New registrations</h2>${table([['When'], ['Email'], ['From'], ['Invite'], ['Since']], reg, 'No new registrations in this period.')}</div>`
      + `<div class="box"><h2>New deck uploads</h2>${table([['When'], ['Email'], ['Deck'], ['Stage and field'], ['Deck score'], ['Verdict'], ['Full research']], decks, 'No decks in this period.')}</div>`
      + `<div class="two gap"><div class="box"><h2>Registrations through an invite</h2>${table([['Invited by'], ['Who joined'], ['Credits', 1]], inv, 'No invites yet.')}</div>`
      + `<div class="box"><h2>Firms people asked for</h2>${table([['Firm'], ['When'], ['By whom']], asks, 'Nobody asked for a firm in this period.')}</div></div>`
      + `<div class="two"><div class="box"><h2>Most opened firms</h2>${table([['Firm'], ['Opened', 1]], firms, 'No firm opened in this period.')}</div>`
      + `<div class="box"><h2>What it cost us</h2><table><tr><td>Pitch reports made</td><td class="n">${fmt(K.reports)}</td></tr><tr><td>Full researches</td><td class="n">${fmt(K.researches)}</td></tr>`
      + `<tr><td>Model cost (tokens, without web searches)</td><td class="n">$${Number(K.model_usd || 0).toFixed(2)}</td></tr><tr><td>Revenue</td><td class="n">$${Number(K.revenue_usd || 0).toFixed(2)}</td></tr></table></div></div>`;
    host.querySelectorAll('[data-d]').forEach((b) => b.addEventListener('click', () => load(+b.dataset.d)));
  }

  async function load(d) {
    DAYS = d; const me = ++TOKEN;
    if (!host.hidden) host.style.opacity = '.5';
    const { data, error } = await sb.rpc('admin_report', { p_days: d });
    if (me !== TOKEN) return;
    if (error || !data) { host.hidden = true; if (notfound) notfound.hidden = false; return; }   // not an admin (or the call failed): back to "page not found"
    host.style.opacity = ''; if (notfound) notfound.hidden = true; host.hidden = false;
    document.title = 'Analytics · Regretamin'; draw(data);
  }

  (async () => {
    try {
      const { data: s } = await sb.auth.getSession();
      if (!s || !s.session) return;
      const { data: ok } = await sb.rpc('analytics_is_admin');
      if (ok === true) load(DAYS);
    } catch (e) { /* stays on "page not found" */ }
  })();
})();
