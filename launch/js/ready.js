/* "Am I ready to pitch?" (founder, 26 Nov 2026). One page, three states: upload, wait, report.
   First working version: the deck goes to private storage, /api/ready reads it with the model and our checklist and
   answers with the report. No credits, no email, PDF only; the page has to stay open while it works. */
(function () {
  const C = window.REGRET || {};
  const sb = C.url && C.key && window.supabase ? window.supabase.createClient(C.url, C.key) : null;
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  const up = $('rd-up'), wait = $('rd-wait'), res = $('rd-res');
  if (!up || !wait || !res) return;
  const MAX = 20 * 1024 * 1024, WORDS = 1000;
  let file = null, timer = 0, REPORT = null;   // REPORT: the id of the report on screen (the full research is asked for by it)

  const show = (el) => { for (const s of [up, wait, res]) s.hidden = s !== el; window.scrollTo(0, 0); };
  const say = (t) => { $('rd-msg').textContent = t || ''; };
  const words = (t) => (String(t).trim().match(/\S+/g) || []).length;

  function pick(f) {
    if (!f) return;
    if (!/\.pdf$/i.test(f.name) && f.type !== 'application/pdf') { file = null; return say('PDF only for now. Export your deck as a PDF.'); }
    if (f.size > MAX) { file = null; return say('That file is over 20 MB. Export a smaller PDF.'); }
    file = f; say('');
    $('rd-dropb').textContent = f.name;
    $('rd-drops').textContent = (f.size / 1048576).toFixed(1) + ' MB · press to change';
    $('rd-drop').classList.add('rd-has');
  }
  $('rd-file').addEventListener('change', (e) => pick(e.target.files && e.target.files[0]));
  const drop = $('rd-drop');
  for (const ev of ['dragenter', 'dragover']) drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add('rd-over'); });
  for (const ev of ['dragleave', 'drop']) drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.remove('rd-over'); });
  drop.addEventListener('drop', (e) => pick(e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0]));
  $('rd-note').addEventListener('input', (e) => {
    const n = words(e.target.value);
    $('rd-count').textContent = n.toLocaleString('en-US') + ' / 1,000 words';
    $('rd-count').classList.toggle('rd-over', n > WORDS);
  });

  function tick() {  // the steps are a clock in this version: the work is one request, so it cannot report real progress yet
    const items = Array.from($('rd-prog').children);
    let i = 0;
    const paint = () => items.forEach((li, k) => { li.className = k < i ? 'rd-done' : k === i ? 'rd-now' : ''; });
    paint(); clearInterval(timer);
    timer = setInterval(() => { if (i < items.length - 1) { i++; paint(); } }, 14000);
  }

  const WHY = { no_key: 'The model key is not set on this address yet.', model_no_credit: 'The model account has no credit. Nothing is wrong with your deck.', sign_in: 'Please sign in again.', not_configured: 'This address is not set up yet.' };
  async function run(id, token) {
    show(wait); tick();
    let r = null, j = null;
    try {
      r = await fetch('/api/ready', { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + token }, body: JSON.stringify({ id }) });
      j = await r.json();
    } catch (e) { j = null; }
    clearInterval(timer);
    if (!r || !r.ok || !j || !j.report) { show(up); return say(WHY[j && j.error] || 'Something went wrong reading the deck. Nothing was charged. Try again.'); }
    try { history.replaceState(null, '', '?report=' + encodeURIComponent(id)); } catch (e) {}
    REPORT = id; draw(j.report);
  }

  // The deck's fingerprint: the same file always gives the same letters. It goes into the stored file's name, so the
  // same deck sent again is found among the founder's own reports (founder, 26 Nov: "you already sent us this deck. Here is the result").
  async function fingerprint(f) {
    try {
      const d = await crypto.subtle.digest('SHA-256', await f.arrayBuffer());
      return Array.from(new Uint8Array(d)).slice(0, 16).map((b) => b.toString(16).padStart(2, '0')).join('');
    } catch (e) { return ''; }
  }

  $('rd-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!sb) return say('This page is not connected.');
    if (!file) return say('Add your deck first.');
    const note = $('rd-note').value.trim();
    if (words(note) > WORDS) return say('Keep the text under 1,000 words.');
    const { data } = await sb.auth.getSession();
    const session = data && data.session;
    if (!session) { say('Sign in first. It takes a few seconds.'); return $('rd-signin').click(); }
    const go = $('rd-go'); go.disabled = true; say('Uploading…');
    const safe = file.name.replace(/[^A-Za-z0-9._-]+/g, '-').slice(-80) || 'deck.pdf';
    const mark = await fingerprint(file);
    if (mark) {   // the same deck again: no second reading, the saved report is shown
      const old = await sb.from('ready_reports').select('id,result').eq('status', 'done').like('deck_path', session.user.id + '/' + mark + '-%').order('created_at', { ascending: false }).limit(1);
      const hit = old.data && old.data[0];
      if (hit && hit.result) {
        go.disabled = false; say('');
        try { history.replaceState(null, '', '?report=' + encodeURIComponent(hit.id)); } catch (e) {}
        REPORT = hit.id; return draw(hit.result, true);
      }
    }
    const path = session.user.id + '/' + (mark ? mark + '-' : '') + Date.now() + '-' + safe;
    const upl = await sb.storage.from('decks').upload(path, file, { contentType: 'application/pdf', upsert: false });
    if (upl.error) { go.disabled = false; return say('The upload did not go through. Try again.'); }
    const ins = await sb.from('ready_reports').insert({ deck_path: path, deck_name: file.name.slice(0, 200), linkedin: $('rd-li').value.trim().slice(0, 200) || null, note: note || null }).select('id').single();
    go.disabled = false;
    if (ins.error || !ins.data) return say('Could not start the report. Try again.');
    say('');
    run(ins.data.id, session.access_token);
  });

  const money = (n) => (n >= 1e6 ? '$' + (n / 1e6).toFixed(n % 1e6 ? 1 : 0) + 'M' : '$' + Math.round(n / 1e3) + 'K');
  const day = (d) => { const t = new Date(d + 'T00:00:00Z'); return isNaN(t) ? '' : t.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }); };
  const sc = (f) => (f.score != null ? f.score : 11 - f.matters);   // reports saved before the scores were turned round
  const rows = (list, cls) => list.map((f) => `<div class="rd-row"><i class="rd-dot ${cls}"></i><b>${esc(f.what)}</b><span class="rd-wh">${esc(f.where)}</span><span class="rd-imp ${cls}">${sc(f)}<i>/10</i></span><span>${esc(f.why)}</span><span>${f.by ? `<i class="rd-fk${f.by === 'proof' ? ' rd-earn' : ''}">${f.by === 'proof' ? 'Earn it' : 'Rewrite'}</i>` : ''}${esc(f.fix)}</span></div>`).join('');
  const head = (fix) => `<div class="rd-row rd-hd"><span></span><span>What</span><span>Where</span><span>Score</span><span>Why it matters</span><span>${fix}</span></div>`;
  // The mark for what is great: a small cup, our own drawing (no emoji).
  const CUP = '<svg class="rd-cup" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 4h8v5a4 4 0 0 1-8 0V4z"/><path d="M8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4"/><path d="M12 13v4M9 20h6M10 17h4"/></svg>';
  // The mark for what is special in this field: a flame, our own drawing.
  const FIRE = '<svg class="rd-fire" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M12.5 2c.6 3.400 4.500 5.200 4.500 10.200A5 5 0 0 1 7 12.200c0-1.700.700-3 1.700-4 .2 1.500.9 2.400 1.900 2.900C10.300 8.200 11 4.600 12.500 2z" fill="#E8501E"/><path d="M12 13.500c1 .9 1.900 1.900 1.900 3.300a1.900 1.900 0 0 1-3.800 0c0-1.300.9-2.300 1.900-3.300z" fill="#FFD36B"/></svg>';
  const tile = (label, n) => `<div class="rd-score"><span>${label}</span><b>${n == null ? '–' : n}<i>/10</i></b></div>`;
  const step = (n, body, last, id, cls) => `<div class="rd-step${cls ? ' ' + cls : ''}"${id ? ` id="${id}"` : ''}><div class="rd-rail"><span>${n}</span>${last ? '' : '<i></i>'}</div><div class="rd-box">${body}</div></div>`;
  // The paid part looks different from the free report (founder, 26 Nov: "paid background on a paid thing should be different,
  // should be orange ... hey, this thing is different, so you paid for it"), and once it is there step 4 is gone: its firms are in part B.
  const PAID_H = '<h2>Full research <span class="rd-tag">Paid</span></h2>';

  // Step 4 of the free report shows the first two firms: who they are. Why each one fits, what to say and how to get in are
  // in the full research (founder, 26 Nov: "on the first step we should show 2 VCs, and here we should show reasoning").
  const FREE_FIRMS = 2;
  function firmRow(f, i) {
    const place = [f.city, f.country].filter(Boolean).join(', ');
    const ini = esc(String(f.name || '').slice(0, 2));
    return `<div class="rd-frow rd-f2"><span class="rd-ord">${i + 1}</span><span class="rd-lg"><img src="/assets/logos/f-${encodeURIComponent(f.slug)}.png" alt="" onerror="this.parentNode.textContent='${ini}'"></span>`
      + `<div><a class="rd-nm" target="_blank" rel="noopener" href="/vc/${encodeURIComponent(f.slug)}/">${esc(f.name)}</a><div class="rd-pl">${esc(place)}</div></div><div class="rd-why">${f.n12} deal${f.n12 === 1 ? '' : 's'} in the last 12 months</div></div>`;
  }
  // The deck did not say where the company is based: the founder is asked, and the firms are picked again for that country
  // (founder, 26 Nov: "If he doesn't have a location, we can ask him or her"). Country names come from the browser.
  const CODES = 'US GB CA DE FR NL SE NO DK FI IE ES PT IT CH AT BE PL CZ EE LV LT UA RO BG GR TR IL AE SA IN PK SG ID VN TH MY PH JP KR CN HK TW AU NZ BR MX AR CL CO NG KE ZA EG GH'.split(' ');
  function whereBox(r) {
    if (r.research || !REPORT || (r.company && r.company.country)) return '';
    let names; try { names = new Intl.DisplayNames(['en'], { type: 'region' }); } catch (e) { names = null; }
    const opts = CODES.map((c) => [c, names ? names.of(c) : c]).sort((a, b) => a[1].localeCompare(b[1])).map(([c, n]) => `<option value="${c}">${esc(n)}</option>`).join('');
    return `<div class="rd-where"><span>Your deck does not say where you are based. Where are you based?</span><select id="rd-cty" aria-label="Where are you based?"><option value="">Choose a country</option>${opts}</select><button type="button" class="rd-btn" id="rd-ctygo">Update the firms</button><span id="rd-ctymsg"></span></div>`;
  }
  async function setCountry(r) {
    const c = $('rd-cty') && $('rd-cty').value, msg = $('rd-ctymsg');
    if (!c || !sb || !REPORT) return;
    const { data } = await sb.auth.getSession();
    if (!data || !data.session) return $('rd-signin').click();
    $('rd-ctygo').disabled = true; msg.textContent = 'Looking…';
    let out = null;
    try { const q = await fetch('/api/ready', { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + data.session.access_token }, body: JSON.stringify({ id: REPORT, country: c }) }); out = q.ok ? await q.json() : null; } catch (e) { out = null; }
    if (!out || !out.report) { $('rd-ctygo').disabled = false; msg.textContent = 'That did not go through. Try again.'; return; }
    const y = window.scrollY; draw(out.report); window.scrollTo(0, y);
  }
  function moreFirms(r) {
    const n = (r.firms || []).length, rest = n - FREE_FIRMS;
    if (rest <= 0) return '';
    return `<div class="rd-lock rd-l4"><div class="rd-blur">${'<div class="rd-frow rd-f2"><span class="rd-ord">0</span><span class="rd-lg">Fi</span><div><b class="rd-nm">Firm name</b><div class="rd-pl">City, country</div></div><div class="rd-why">00 deals in the last 12 months</div></div>'.repeat(Math.min(rest, 3))}</div><p class="rd-more rd-over4">${rest} more firm${rest === 1 ? '' : 's'}, and why each one fits you, in the full research.</p></div>`;
  }


  // The full research (step 3). Every figure is marked: from our own data, or looked up on the web with its source.
  const usd = (n) => (n >= 1e9 ? '$' + (n / 1e9).toFixed(1).replace(/\.0$/, '') + 'B' : n >= 1e6 ? '$' + (n / 1e6).toFixed(1).replace(/\.0$/, '') + 'M' : '$' + Math.round(n / 1e3) + 'K');
  const OURS = '<span class="rd-from rd-o">Our data</span>', WEB = '<span class="rd-from">Looked up</span>';
  const firmA = (f) => `<a target="_blank" rel="noopener" href="/vc/${encodeURIComponent(f.slug)}/">${esc(f.name)}</a>`;
  // A link that leaves the site says so with an arrow and opens in a new page.
  const ext = (u, label, cls) => `<a class="rd-x${cls ? ' ' + cls : ''}" target="_blank" rel="noopener nofollow" href="${esc(u)}">${esc(label)}<span aria-hidden="true"> ↗</span></a>`;
  // Icons, our own drawings in a 24 x 24 box. The first six are the firm badges' own (launch/edge/card/badge.mjs).
  const ICON = {
    top: 'M2.5 6.5l5 4.3L12 3.5l4.5 7.3 5-4.3-1.9 11H4.4zM4.8 19.3h14.4v2.200H4.8z',
    lead: 'M2.5 9.2h4.3L15.5 4v16l-8.700-5.200H2.5zM6.200 16.200h3.300l1.200 5.300H7.400zM17.800 9.500h2v5h-2zM21 7.500h1.500v9H21z',
    up: 'M13.800 1.500L4.500 13.600h6.300L9.200 22.500l10.300-12.700h-6.600z',
    chain: 'M12 2a10 10 0 110 20 10 10 0 010-20zm0 2.300a7.700 7.700 0 100 15.400 7.700 7.700 0 000-15.400zM16.400 7.600l-2.700 6.100-6.100 2.700 2.700-6.100z',
    spec: 'M12 5a7 7 0 110 14 7 7 0 010-14zm0 2.300a4.700 4.700 0 100 9.400 4.700 4.700 0 000-9.400zM12 10.200a1.800 1.800 0 110 3.600 1.800 1.800 0 010-3.600zM11 1h2v3h-2zM11 20h2v3h-2zM1 11h3v2H1zM20 11h3v2h-3z',
    fund: 'M12.600 1.500c.700 3.900 5.600 6 5.600 11.400a6.200 6.200 0 01-12.400 0c0-2.200.900-4 2.100-5.300.300 1.800 1 2.900 2.100 3.300C9.800 7.800 10.700 4.100 12.600 1.500z',
    aud: 'M12 8.500a3 3 0 110 6 3 3 0 010-6zM6.300 5.800a8 8 0 000 11.400l1.500-1.500a5.900 5.900 0 010-8.400zM17.700 5.800l-1.500 1.500a5.900 5.900 0 010 8.400l1.500 1.500a8 8 0 000-11.400zM3.200 2.700a12.400 12.400 0 000 17.600l1.500-1.500a10.300 10.300 0 010-14.600zM20.800 2.700l-1.500 1.500a10.300 10.300 0 010 14.600l1.500 1.500a12.400 12.400 0 000-17.600z',
    chq: 'M12 2a10 10 0 110 20 10 10 0 010-20zm1 3.800h-2v1.700a3.100 3.100 0 00.300 6.200h1.400a1 1 0 010 2H9v2.100h2v1.400h2v-1.500a3.100 3.100 0 00-.300-6.100h-1.400a1 1 0 010-2H15V7.500h-2z',
    work: 'M9 3h6a2 2 0 012 2v2h3a2 2 0 012 2v9a2 2 0 01-2 2H4a2 2 0 01-2-2V9a2 2 0 012-2h3V5a2 2 0 012-2zm0 4h6V5H9z',
    study: 'M12 3l11 6-11 6L1 9zM5 12.900V17c2 2 4.500 3 7 3s5-1 7-3v-4.100l-7 3.800zM21 10.500h1.500V16H21z',
    built: 'M5 2h2v20H5zM8.500 3H20l-2.800 4.500L20 12H8.500z',
    web: 'M12 2a10 10 0 110 20 10 10 0 010-20zM9.800 11h4.400c-.2-2.900-1-5.200-2.200-6.800-1.200 1.600-2 3.900-2.200 6.800zm-5.500 0h3.500c.1-2.300.6-4.300 1.400-5.900A7.800 7.800 0 004.300 11zm0 2a7.800 7.800 0 004.900 5.900c-.8-1.600-1.300-3.600-1.400-5.900zm5.500 0c.2 2.900 1 5.200 2.200 6.800 1.200-1.600 2-3.900 2.200-6.800zm6.400 0c-.1 2.300-.6 4.300-1.400 5.900a7.800 7.800 0 004.900-5.900zm3.500-2a7.800 7.800 0 00-4.900-5.900c.8 1.600 1.300 3.600 1.400 5.900z',
    news: 'M3 4h14v14a2 2 0 002 2H5a2 2 0 01-2-2zm16 4h2v10a1 1 0 01-2 0zM6 7h8v3H6zm0 5h8v1.500H6zm0 3h8v1.500H6z',
    move: 'M4 11h11.200l-4.600-4.600L12 5l7 7-7 7-1.400-1.400 4.600-4.600H4z',
    cal: 'M6 2h2v2h8V2h2v2h3v18H3V4h3zm13 8H5v10h14zM5 8h14V6H5z',
    shut: 'M12 2a10 10 0 110 20 10 10 0 010-20zM8.500 7.100L7.100 8.500l3.500 3.500-3.500 3.500 1.400 1.400 3.500-3.500 3.500 3.500 1.400-1.400-3.500-3.500 3.500-3.500-1.400-1.400-3.500 3.500z',
    acq: 'M3 5h5.500l4 6H18l-2.600-2.600L16.800 7l5.200 5-5.200 5-1.400-1.400L18 13h-5.500l-4 6H3v-2h4.400l3.400-5-3.400-5H3z',
    turn: 'M5 20v-8a5 5 0 015-5h5.200l-2.600-2.600L14 3l5 5-5 5-1.400-1.400L15.200 9H10a3 3 0 00-3 3v8z',
  };
  const ico = (k, px) => `<svg viewBox="0 0 24 24" width="${px || 15}" height="${px || 15}" fill="currentColor" fill-rule="evenodd" aria-hidden="true"><path d="${ICON[k] || ICON.web}"/></svg>`;
  // A badge in the shape of the firm badges: an icon half and a text half. Dark half = our data; light half = looked up.
  const bdg = (k, v, n, ours, url) => { const inner = `<i>${ico(k)}</i><span><b>${esc(v)}${url ? '<span aria-hidden="true" class="rd-ar"> ↗</span>' : ''}</b>${n ? `<em>${esc(n)}</em>` : ''}</span>`;
    return url ? `<a class="rd-bg${ours ? ' rd-o' : ''}" target="_blank" rel="noopener nofollow" href="${esc(url)}">${inner}</a>` : `<span class="rd-bg${ours ? ' rd-o' : ''}">${inner}</span>`; };
  // A plain fact: an icon tile and two lines of text. Dark tile = our data; light tile = looked up.
  // (Founder, 26 Nov: "the block system looks good, icons looks good, pill system no ... make this pill like something special".)
  const fact = (k, v, n, ours, url) => `<div class="rd-ft${ours ? ' rd-o' : ''}"><i>${ico(k, 16)}</i><span><b>${url ? ext(url, v) : esc(v)}</b>${n ? `<em>${esc(n)}</em>` : ''}</span></div>`;
  // The pill is kept for one thing only: a badge the site has awarded the firm.
  const AWARDED = ['The Magnificent 100', 'Shot Caller', 'Fast & Curious', 'Pathfinder', 'Laser Focus', 'Hot & Fresh'];
  const logo = (f) => `<span class="rd-lg"><img src="/assets/logos/f-${encodeURIComponent(f.slug)}.png" alt="" onerror="this.parentNode.textContent='${esc(String(f.name || '?').replace(/[^A-Za-z0-9]/g, '').slice(0, 2) || '?')}'"></span>`;
  // One lettered part: what is going on, the facts, and one thing to do next (founder, 26 Nov: "the actionable map").
  const part = (letter, title, tags, now, body, next) => `<div class="rd-ab"><div class="rd-abh"><span class="rd-let">${letter}</span><h3>${title}</h3>${tags}</div>${now ? `<p class="rd-rs">${esc(now)}</p>` : ''}${body}${next ? `<div class="rd-next"><span class="rd-tag">Do this next</span><span>${esc(next)}</span></div>` : ''}</div>`;
  const OUT = { 'Shut down': 'shut', Acquired: 'acq', 'Changed direction': 'turn' };
  function researchHtml(x, r) {
    const comp = x.competitors || [], skip = x.skip || [], tried = x.tried || [], rr = x.rounds, now = x.now || {}, todo = x.todo || {};
    const deck = r && r.scores ? r.scores.deck : null, ready = deck == null || deck >= 8;   // no "go now" while the deck is not ready
    const fresh = (g) => { const ys = (String(g.what || '').match(/\b(19|20)\d{2}\b/g) || []).map(Number); return !ys.length || Math.max(...ys) >= new Date().getFullYear() - 10; };   // no news older than ten years
    const letters = 'ABCD'.split(''); const parts = [];
    const has = (c) => [
      c.raised ? fact('chq', c.raised.text, c.raised.date ? 'Raised · ' + day(c.raised.date) : 'Raised', c.raised.ours) : '',
      ...(c.facts || []).map((f) => fact(f.k, f.v, f.n, true)),
      ...(c.strong || []).map((g) => fact('web', g.what, '', false, g.src)),
    ].join('');
    const cards = comp.map((c) => `<div class="rd-cc"><div class="rd-cch"><span class="rd-ci">${esc((c.name || '?').slice(0, 1).toUpperCase())}</span><div>${c.site ? ext('https://' + c.site, c.name, 'rd-cn') : `<b class="rd-cn">${esc(c.name)}</b>`}<p>${esc(c.what)}</p></div>${ext(c.src, 'Source', 'rd-src')}</div>`
      + `<div class="rd-ccb"><div><p class="rd-cap">They have</p><div class="rd-fts">${has(c) || '<span class="rd-pl">Nothing we could check.</span>'}</div>${c.backers && c.backers.list.length ? `<p class="rd-bk"><i class="rd-d${c.backers.ours ? ' rd-o' : ''}"></i>Backed by ${c.backers.list.map((b) => (b.slug ? firmA(b) : esc(b.name))).join(', ')}</p>` : ''}</div>`
      + `<div><p class="rd-cap">In the news</p><div class="rd-fts rd-col">${(c.news || []).filter(fresh).map((g) => fact('news', g.what, '', false, g.src)).join('') || '<span class="rd-pl">Nothing found.</span>'}</div></div></div>`
      + (c.move || c.you ? `<div class="rd-move"><i>${ico('move', 16)}</i><span class="rd-cap">Your move</span><b>${esc(c.move || c.you)}</b></div>` : '') + '</div>').join('');
    parts.push(['Your competitors', OURS + WEB, now.competitors, comp.length ? cards : '<p class="rd-none">None found with a source we could check.</p>', todo.competitors]);
    // Part B: every firm the report picked, with the reasoning (founder, 26 Nov: the free report shows two firms; "here we can
    // show why we suggest those VCs").
    const picks = (r && r.firms) || [], tipOf = new Map((x.investors || []).map((f) => [f.slug, f])), then = (r && r.then) || [];
    const stageW = String(x.stage || (r && r.company && r.company.stage) || '').toLowerCase();
    const firmBlock = (f, i) => {
      const t = tipOf.get(f.slug) || {}, bs = t.badges || [], place = [f.city, f.country].filter(Boolean).join(', ');
      const why = [
        Number(f.fit) ? fact('spec', `${f.fit} ${stageW} deal${Number(f.fit) === 1 ? '' : 's'} in your field`, 'In the last 12 months', true) : '',
        f.n12 != null ? fact('up', `${f.n12} deal${Number(f.n12) === 1 ? '' : 's'} in the last 12 months`, [Number(f.n90) ? f.n90 + ' in the last 90 days' : '', f.last_deal ? 'last deal ' + day(f.last_deal) : ''].filter(Boolean).join(' · '), true) : '',
        f.stage_pct != null ? fact('built', `${f.stage_pct}% of its deals are at your stage`, Number(f.sector_pct) ? f.sector_pct + '% are in your field' : '', true) : '',
        f.geo === 'country' ? fact('chain', Number(f.n_country) ? `Backed ${f.n_country} startup${Number(f.n_country) === 1 ? '' : 's'} from your country` : 'Based in your country', Number(f.n_country) && f.hq_same ? 'and it is based there' : 'It invests where you are', true)
          : f.geo === 'region' ? fact('chain', 'Based in your region', 'No firm tie to your country on record', true) : '',
      ].join('');
      const size = f.rounds && f.rounds.n >= 5 ? fact('chq', `Usually joins rounds of ${usd(f.rounds.lo)} to ${usd(f.rounds.hi)}`, `The middle half of its ${f.rounds.n} ${stageW} rounds in the last 3 years`, true) : '';
      const sum = f.summary && f.summary.text ? `<div class="rd-sum"><span>Summary:</span> ${esc(f.summary.text)} <em>${esc([f.summary.who, f.summary.title, f.summary.year].filter(Boolean).join(' · '))}</em></div>` : '';
      const pill = bs.filter((b) => AWARDED.includes(b.v)).map((b) => bdg(b.k, b.v, b.n, true)).join('');
      const way = bs.filter((b) => !AWARDED.includes(b.v)).map((b) => fact(b.k, b.v, b.n, true)).join('');
      return `<div class="rd-cc"><div class="rd-cch"><span class="rd-ord">${i + 1}</span>${logo(f)}<div>${firmA(f)}<p>${esc(place)}</p>${(f.marks || []).map((m) => `<span class="rd-mark">${CUP}${esc(m)}</span>`).join('')}</div>${pill}${t.apply ? `<a class="rd-pb" target="_blank" rel="noopener nofollow" href="${esc(t.apply)}">Pitch<span aria-hidden="true"> ↗</span></a>` : ''}</div>`
        + `<div class="rd-ccb"><div><p class="rd-cap">Why we suggest it</p><div class="rd-fts">${why}</div>${sum}</div><div><p class="rd-cap">How to get in</p><div class="rd-fts rd-col">${way + size || '<span class="rd-pl">Nothing on record yet.</span>'}</div></div></div>`
        + (f.say ? `<div class="rd-move"><i>${ico('move', 16)}</i><span class="rd-cap">What to say</span><b>${esc(ready ? f.say : String(f.say).replace(/\s*Go now\.$/, ' Fix your red flags first, then go.'))}</b></div>` : '') + '</div>';
    };
    if (picks.length || skip.length) parts.push(['Your investors', OURS, now.firms,
      picks.map(firmBlock).join('')
      + (then.length ? `<p class="rd-cap rd-skipc">Then these: big firms that later invested where the firms above went first</p><div class="rd-cc rd-skips">${then.map((t) => `<div class="rd-fl">${firmA(t)}<span>after ${esc(t.after)}${t.n > 1 ? ', ' + t.n + ' startups' : ''}</span></div>`).join('')}</div>` : '')
      + (skip.length ? `<p class="rd-cap rd-skipc">Skip these firms: they hold one of your competitors</p><div class="rd-cc rd-skips">${skip.map((f) => `<div class="rd-fl">${firmA(f)}<span>backed ${esc((f.backed || []).join(', '))}</span></div>`).join('')}</div>` : ''), !ready && picks.length ? 'Fix the red flags in step 1 first. Then press Pitch.' : todo.firms]);
    const who = (t) => (t.founders || []).map((f) => ext('https://www.linkedin.com/search/results/people/?keywords=' + encodeURIComponent(f + ' ' + t.name), f + ' on LinkedIn', 'rd-lb')).join('');
    parts.push(['Who tried this before', WEB, now.tried, tried.length
      ? `<div class="rd-tg">${tried.map((t) => `<div class="rd-cc rd-tc"><div class="rd-cch"><div><b class="rd-cn">${esc(t.name)}</b><p>${esc(t.happened)}</p></div></div><div class="rd-fts rd-col">${fact(OUT[t.outcome] || 'turn', t.outcome || 'Earlier attempt', t.years, false)}</div><div class="rd-lbs">${ext(t.src, 'Read what happened', 'rd-lb')}${who(t)}</div></div>`).join('')}</div>`
        + '<div class="rd-q3"><b>Three questions to ask them</b><ol><li>What ended it, in one sentence?</li><li>If you started again, what would you do in the first six months?</li><li>Which investors understood it, and which wasted your time?</li></ol></div>'
      : '<p class="rd-none">None found with a source we could check.</p>', todo.tried]);
    if (rr) {
      const top = Math.max(rr.p90 * 1.12, (rr.ask || 0) * 1.12), at = (v) => Math.max(0, Math.min(100, (100 * v) / top)).toFixed(1) + '%';
      parts.push(['Your ask against similar rounds', OURS, `${rr.n.toLocaleString('en-US')} ${rr.sector ? rr.sector.toLowerCase() + ' ' : ''}${String(rr.stage).toLowerCase()} rounds in the last 24 months with a known amount.`,
        `<div class="rd-cc"><div class="rd-track"><i class="rd-band" style="left:${at(rr.p25)};width:calc(${at(rr.p75)} - ${at(rr.p25)})"></i><i class="rd-mid" style="left:${at(rr.p50)}"></i><i class="rd-p90" style="left:${at(rr.p90)}"></i>${rr.ask ? `<span class="rd-you" style="left:${at(rr.ask)}">You: ${usd(rr.ask)}</span>` : ''}</div>`
        + `<div class="rd-qs"><div><b>${usd(rr.p25)}</b><span>a quarter raised less</span></div><div><b>${usd(rr.p50)}</b><span>the middle</span></div><div><b>${usd(rr.p75)}</b><span>a quarter raised more</span></div><div><b>${usd(rr.p90)}</b><span>top tenth</span></div></div>`
        + (rr.line ? `<p class="rd-rl">${esc(rr.line)}</p>` : '') + '</div>'
        + (rr.peers ? `<div class="rd-cc"><p class="rd-cap">What the founders who raised ${usd(rr.ask)} or more had</p><div class="rd-fts">`
          + fact('study', `${rr.peers.uni}% had a founder from a top university`, rr.peers.unis && rr.peers.unis.length ? 'Most often ' + rr.peers.unis.join(', ') : '', true)
          + fact('work', `${rr.peers.co}% had a founder from a known company`, rr.peers.cos && rr.peers.cos.length ? 'Most often ' + rr.peers.cos.join(', ') : '', true)
          + fact('built', `${rr.peers.built}% had a founder who built a company before`, `Of the ${rr.peers.known} such rounds where we know the founders`, true)
          + `</div>${rr.peers.line ? `<div class="rd-move"><i>${ico('move', 16)}</i><b>${esc(rr.peers.line)}</b></div>` : ''}</div>` : ''), todo.ask]);
    }
    return parts.map((p, n) => part(letters[n] || '', p[0], p[1], p[2], p[3], p[4])).join('');
  }
  const LOCK = (on) => `<div class="rd-lock"><div class="rd-blur">${'<div class="rd-row"><i class="rd-dot"></i><b>Company name, city</b><span class="rd-wh">Series A</span><span></span><span>$00M · backed by Firm name, Firm name</span><span>2026</span></div>'.repeat(3)}</div><div class="rd-offer"><div><b>Full research</b><p id="rd-rmsg">Your competitors and who funded them. Who tried this before, and the founders to ask. The firms to skip.</p></div><span class="rd-pr">10 credits</span><button type="button" class="rd-buy" id="rd-buy"${on ? '' : ' disabled'}>Get the full research</button></div></div>`;
  const WHYR = { no_key: 'The model key is not set on this address yet.', model_no_credit: 'The model account has no credit. Try again later.', sign_in: 'Please sign in again.' };
  async function research(r) {
    const b = $('rd-buy'), msg = $('rd-rmsg');
    if (!sb || !REPORT || !b) return;
    const { data } = await sb.auth.getSession();
    if (!data || !data.session) return $('rd-signin').click();
    b.disabled = true; b.textContent = 'Researching…'; msg.textContent = 'Searching the web and our data. Ready in a few minutes. Keep this page open.';
    let res2 = null, j = null;
    try {
      res2 = await fetch('/api/research', { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + data.session.access_token }, body: JSON.stringify({ id: REPORT }) });
      j = await res2.json();
    } catch (e) { j = null; }
    if (!res2 || !res2.ok || !j || !j.research) {
      b.disabled = false; b.textContent = 'Get the full research';
      msg.textContent = WHYR[j && j.error] || 'The research did not go through. Try again.';
      return;
    }
    r.research = j.research;
    $('rd-s3').innerHTML = researchHtml(j.research, r);
    const st3 = $('rd-st3'), st4 = $('rd-st4');
    if (st3) { st3.classList.add('rd-paid'); const h = st3.querySelector('h2'); if (h) h.outerHTML = PAID_H; const line = st3.querySelector('.rd-rail i'); if (line) line.remove(); }
    if (st4) st4.remove();
  }

  // The report as plain text with an instruction on top, for the founder to hand to an AI together with the deck
  // (founder, 26 Nov: "everyone should give it to AI. They will not change their pitch deck").
  const AI_ASK = 'Here is my pitch deck and its review from Regretamin. Rewrite my slides to fix every point marked REWRITE, slide by slide. Do not invent numbers, customers or facts. For the points marked EARN IT, do not rewrite anything: list them as things I still have to do, each with a first step.';
  function forAI(r) {
    const co = r.company || {}, L = [AI_ASK, '', `REVIEW OF: ${[co.name, co.stage, co.sector].filter(Boolean).join(', ')}`, `VERDICT: ${r.verdict || ''}${r.scores && r.scores.deck != null ? ' Deck score: ' + r.scores.deck + '/10.' : ''}`];
    const tag = (f) => (f.by === 'proof' ? 'EARN IT' : 'REWRITE');
    const flags = (title, list) => { if (!list.length) return; L.push('', title); list.forEach((f, i) => L.push(`${i + 1}. [${tag(f)}] ${f.what}${f.where ? ' (' + f.where + ')' : ''}. Why it matters: ${f.why} Fix: ${f.fix}`)); };
    if (r.lead) L.push('', `LEAD WITH THIS: ${r.lead.text}${r.lead.where ? ' (' + r.lead.where + ')' : ''}`);
    if ((r.special || []).length) { L.push('', 'SPECIAL IN MY FIELD (keep and move up):'); r.special.forEach((x) => L.push(`- ${x.what}${x.where ? ' (' + x.where + ')' : ''}`)); }
    if ((r.good || []).length) { L.push('', 'WHAT IS GOOD (keep):'); r.good.forEach((g) => L.push(`- ${g.what}${g.where ? ' (' + g.where + ')' : ''}`)); }
    flags('RED FLAGS (fix first):', r.reds || []); flags('IMPROVE:', r.yellows || []);
    const x = r.research;
    if (x && (x.competitors || []).length) { L.push('', 'COMPETITORS AND WHAT TO SAY ABOUT EACH:'); x.competitors.forEach((c) => L.push(`- ${c.name}: ${c.what}${c.move ? ' My answer: ' + c.move : ''}`)); }
    if (x && x.rounds && x.rounds.line) L.push('', `MY ASK: ${x.rounds.line}`);
    return L.join('\n');
  }
  const FEEDBACK = '<div class="rd-fb" id="rd-fb" hidden><h2>Feedback</h2><div class="rd-fbg"><label>What\'s good?<textarea id="rd-fb1" maxlength="4000"></textarea></label><label>What\'s missing?<textarea id="rd-fb2" maxlength="4000"></textarea></label><label>What\'s wrong?<textarea id="rd-fb3" maxlength="4000"></textarea></label></div><button type="button" class="rd-btn rd-k" id="rd-fbgo">Send feedback</button><span id="rd-fbmsg"></span></div>';
  async function feedback() {
    const box = $('rd-fb'); if (!box || !sb) return;
    const probe = await sb.from('ready_feedback').select('id').limit(1);   // the box shows only once its table is there
    if (probe.error) return;
    box.hidden = false;
    $('rd-fbgo').addEventListener('click', async () => {
      const v = (id) => $(id).value.trim().slice(0, 4000) || null, row = { report_id: REPORT, good: v('rd-fb1'), missing: v('rd-fb2'), wrong: v('rd-fb3') };
      if (!row.good && !row.missing && !row.wrong) return;
      $('rd-fbgo').disabled = true;
      const ins = await sb.from('ready_feedback').insert(row);
      if (ins.error) { $('rd-fbgo').disabled = false; $('rd-fbmsg').textContent = 'That did not go through. Try again.'; return; }
      box.innerHTML = '<h2>Feedback</h2><p>Thank you. We read every one.</p>';
    });
  }

  function draw(r, same) {
    const co = r.company || {};
    const line = [co.name, co.stage ? co.stage.toLowerCase() : '', co.sector && co.sector !== 'Other' ? co.sector : '', co.ask_usd ? 'raising ' + money(co.ask_usd) : '', co.based_in].filter(Boolean).join(' · ');
    const reds = r.reds || [], yel = r.yellows || [], firms = r.firms || [], then = r.then || [];
    const lead = r.lead ? `<div class="rd-lead">${CUP}<div><b>Lead with this.</b> ${esc(r.lead.text)}${r.lead.where ? ' <span class="rd-wh">' + esc(r.lead.where) + '</span>' : ''}</div><span class="rd-imp rd-ten">10<i>/10</i></span></div>` : '';
    const good = r.good || [], scores = r.scores || null;
    const special = r.special || [];
    const fire = special.map((x) => `<div class="rd-sp">${FIRE}<div><span class="rd-kind">${esc(x.kind)}</span><b>${esc(x.what)}</b>${x.where ? ' <span class="rd-wh">' + esc(x.where) + '</span>' : ''}<p>${esc(x.why)}</p></div><span class="rd-imp rd-hot">12<i>/10</i></span></div>`).join('');
    const goodBox = good.length || lead || fire ? `<div class="rd-good"><h2>What's good</h2>${fire ? `<p class="rd-cap rd-spcap">Special in your field</p>${fire}` : ''}${good.length ? `<div class="rd-row rd-g rd-hd"><span></span><span>What</span><span>Where</span><span>Score</span><span>Why investors like it</span></div>` + good.map((g) => `<div class="rd-row rd-g">${g.score >= 9 ? CUP : '<i class="rd-dot rd-grn"></i>'}<b>${esc(g.what)}</b><span class="rd-wh">${esc(g.where)}</span><span class="rd-imp rd-grn">${g.score}<i>/10</i></span><span>${esc(g.why)}</span></div>`).join('') : ''}${lead}</div>` : '';
    res.innerHTML = '<p class="rd-made"><img src="/logo.svg" alt="">Made with Regretamin · regretamin.com</p>'   // shown only in the PDF (founder, 26 Nov)
      + (same ? '<p class="rd-same">You already sent us this deck. Here is the result.</p>' : '') + `<div class="rd-bar"><h1>Your raise report</h1><span class="rd-who">${esc(line)}</span><button type="button" class="rd-btn rd-k" id="rd-pdf">Download PDF</button><button type="button" class="rd-btn" id="rd-ai">Copy for AI</button><button type="button" class="rd-btn" id="rd-again">Upload a new version</button></div>`
      + `<div class="rd-verdict"><div><p class="rd-cap">Verdict</p><h2>${esc(r.verdict)}</h2></div>${scores ? tile('Deck', scores.deck) : ''}</div>`   // founder, 26 Nov: the founders score is kept on the report (scores.founders) but not shown; the four-step strip is gone
      + goodBox
      + step(1, `<h2>Get rid of the red flags <small>${reds.length ? reds.length + ' · most important first' : 'none found'}</small></h2>${reds.length ? head('How to fix it') + rows(reds, 'rd-red') : ''}`)
      + step(2, `<h2>Improve these <small>${yel.length ? yel.length + ' · not deal-breakers, but investors will notice' : 'nothing stood out'}</small></h2>${yel.length ? head('How to improve it') + rows(yel, 'rd-yel') : ''}`)
      + (r.research
        ? step(3, `${PAID_H}<div id="rd-s3">${researchHtml(r.research, r)}</div>`, true, 'rd-st3', 'rd-paid')
        : step(3, `<h2>Know your competitors</h2><div id="rd-s3">${LOCK(!!REPORT)}</div>`, false, 'rd-st3')
          + step(4, `<h2>Pitch these firms, in this order</h2>${firms.length ? `<div class="rd-sub"><span class="rd-tag">Start here</span><span>They fit your stage and field and are writing cheques now.</span></div>${whereBox(r)}${firms.slice(0, FREE_FIRMS).map(firmRow).join('')}<div id="rd-f4">${moreFirms(r)}</div>` : '<p class="rd-none">We found no firm with a recent deal at your stage in your field.</p>'}`, true, 'rd-st4'));
    res.insertAdjacentHTML('beforeend', `<p class="rd-aip"><b>Hand this to your AI, with your deck:</b> ${esc(AI_ASK)}</p>` + FEEDBACK);
    show(res);
    $('rd-pdf').addEventListener('click', () => window.print());
    $('rd-ai').addEventListener('click', async () => { const b = $('rd-ai'); try { await navigator.clipboard.writeText(forAI(r)); b.textContent = 'Copied'; } catch (e) { b.textContent = 'Copy failed'; } setTimeout(() => { b.textContent = 'Copy for AI'; }, 1800); });
    if ($('rd-ctygo')) $('rd-ctygo').addEventListener('click', () => setCountry(r));
    feedback();
    if ($('rd-buy')) $('rd-buy').addEventListener('click', () => research(r));
    $('rd-again').addEventListener('click', () => { try { history.replaceState(null, '', location.pathname); } catch (e) {} show(up); });
  }

  window.REGRET_READY_DRAW = draw; window.REGRET_READY_AI = forAI;  // for tests and design checks

  // A saved report opens by its address: /ready/?report=<id>
  (async function open() {
    const id = new URLSearchParams(location.search).get('report');
    if (!sb || !id || !/^[0-9a-f-]{36}$/i.test(id)) return;
    const { data } = await sb.auth.getSession();
    if (!data || !data.session) return;
    const got = await sb.from('ready_reports').select('result,status').eq('id', id).maybeSingle();
    if (got.data && got.data.result) { REPORT = id; draw(got.data.result); if (new URLSearchParams(location.search).get('pdf')) setTimeout(() => window.print(), 600); }   // "Download PDF" on My score
  })();
})();
