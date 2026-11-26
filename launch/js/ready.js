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
  let file = null, timer = 0;

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
    draw(j.report);
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
    const path = session.user.id + '/' + Date.now() + '-' + safe;
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
  const rows = (list, cls) => list.map((f) => `<div class="rd-row"><i class="rd-dot ${cls}"></i><b>${esc(f.what)}</b><span class="rd-wh">${esc(f.where)}</span><span class="rd-imp">${f.matters}<i>/10</i></span><span>${esc(f.why)}</span><span>${esc(f.fix)}</span></div>`).join('');
  const head = (fix) => `<div class="rd-row rd-hd"><span></span><span>What</span><span>Where</span><span>Matters</span><span>Why it matters</span><span>${fix}</span></div>`;
  const step = (n, body, last) => `<div class="rd-step"><div class="rd-rail"><span>${n}</span>${last ? '' : '<i></i>'}</div><div class="rd-box">${body}</div></div>`;

  function firmRow(f, i) {
    const place = [f.city, f.country].filter(Boolean).join(', ');
    const why = [`${f.n12} deal${f.n12 === 1 ? '' : 's'} in the last 12 months${f.n90 ? ', ' + f.n90 + ' in the last 90 days' : ''}.`, f.last_deal ? `Last deal ${day(f.last_deal)}.` : '',
      `${f.stage_pct}% of its deals are at your stage.`, Number(f.sector_pct) ? `${f.sector_pct}% are in your field.` : ''].filter(Boolean).join(' ');
    const sum = f.summary && f.summary.text ? `<div class="rd-sum"><span>Summary:</span> ${esc(f.summary.text)} <em>${esc([f.summary.who, f.summary.title, f.summary.year].filter(Boolean).join(' · '))}</em></div>` : '';
    const ini = esc(String(f.name || '').slice(0, 2));
    return `<div class="rd-frow"><span class="rd-ord">${i + 1}</span><span class="rd-lg"><img src="/assets/logos/f-${encodeURIComponent(f.slug)}.png" alt="" onerror="this.parentNode.textContent='${ini}'"></span>`
      + `<div><a class="rd-nm" href="/vc/${encodeURIComponent(f.slug)}/">${esc(f.name)}</a><div class="rd-pl">${esc(place)}</div></div><div class="rd-why">${esc(why)}</div><div class="rd-say">${sum}${esc(f.say || '')}</div></div>`;
  }

  function draw(r) {
    const co = r.company || {};
    const line = [co.name, co.stage ? co.stage.toLowerCase() : '', co.sector && co.sector !== 'Other' ? co.sector : '', co.ask_usd ? 'raising ' + money(co.ask_usd) : '', co.based_in].filter(Boolean).join(' · ');
    const reds = r.reds || [], yel = r.yellows || [], firms = r.firms || [], then = r.then || [];
    const lead = r.lead ? `<div class="rd-lead"><i></i><div><b>Lead with this.</b> ${esc(r.lead.text)}${r.lead.where ? ' <span class="rd-wh">' + esc(r.lead.where) + '</span>' : ''}</div></div>` : '';
    const blur = '<div class="rd-row"><i class="rd-dot"></i><b>Company name, city</b><span class="rd-wh">Series A</span><span></span><span>$00M · backed by Firm name, Firm name</span><span>2026</span></div>'.repeat(3);
    res.innerHTML = `<div class="rd-bar"><h1>Your raise report</h1><span class="rd-who">${esc(line)}</span><button type="button" class="rd-btn rd-k" id="rd-pdf">Download PDF</button><button type="button" class="rd-btn" id="rd-again">Upload a new version</button></div>`
      + `<div class="rd-verdict"><div><p class="rd-cap">Verdict</p><h2>${esc(r.verdict)}</h2></div><div class="rd-plan"><span>1 Remove the red flags</span><i>→</i><span>2 Improve</span><i>→</i><span>3 Know your competitors</span><i>→</i><span>4 Pitch</span></div></div>`
      + step(1, `<h2>Get rid of the red flags <small>${reds.length ? reds.length + ' · most important first' : 'none found'}</small></h2>${reds.length ? head('How to fix it') + rows(reds, 'rd-red') : ''}`)
      + step(2, `<h2>Improve these <small>${yel.length ? yel.length + ' · not deal-breakers, but investors will notice' : 'nothing stood out'}</small></h2>${yel.length ? head('How to improve it') + rows(yel, 'rd-yel') : ''}${lead}`)
      + step(3, `<h2>Know your competitors</h2><div class="rd-lock"><div class="rd-blur">${blur}</div><div class="rd-offer"><div><b>Full research</b><p>Your competitors and who funded them. Who tried this before, and the founders to ask. The firms to skip.</p></div><span class="rd-pr">10 credits</span><button type="button" class="rd-buy" disabled>Get the full research</button></div></div>`)
      + step(4, `<h2>Pitch these firms, in this order</h2>${firms.length ? `<div class="rd-sub"><span class="rd-tag">Start here</span><span>They fit your stage and field and are writing cheques now.</span></div><div class="rd-frow rd-hd"><span></span><span></span><span>Firm</span><span>Why it fits</span><span>What to say to this firm</span></div>${firms.map(firmRow).join('')}` : '<p class="rd-none">We found no firm with a recent deal at your stage in your field.</p>'}`
        + (then.length ? `<div class="rd-sub rd-sub2"><span class="rd-tag rd-tag2">Then these</span><span>After the first cheque is in: big firms that later invested where the firms above went first.</span></div><div class="rd-then">${then.map((t) => `<a href="/vc/${encodeURIComponent(t.slug)}/"><b>${esc(t.name)}</b><span>after ${esc(t.after)}${t.n > 1 ? ', ' + t.n + ' startups' : ''}</span></a>`).join('')}</div>` : ''), true);
    show(res);
    $('rd-pdf').addEventListener('click', () => window.print());
    $('rd-again').addEventListener('click', () => { try { history.replaceState(null, '', location.pathname); } catch (e) {} show(up); });
  }

  window.REGRET_READY_DRAW = draw;  // for tests and design checks

  // A saved report opens by its address: /ready/?report=<id>
  (async function open() {
    const id = new URLSearchParams(location.search).get('report');
    if (!sb || !id || !/^[0-9a-f-]{36}$/i.test(id)) return;
    const { data } = await sb.auth.getSession();
    if (!data || !data.session) return;
    const got = await sb.from('ready_reports').select('result,status').eq('id', id).maybeSingle();
    if (got.data && got.data.result) draw(got.data.result);
  })();
})();
