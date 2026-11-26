// The full research behind step 3 of "Am I ready to pitch?" (founder, 26 Nov 2026: "What's next? Full research.").
// Two sources, kept apart and labelled in the report:
//   - looked up: the model searches the web for competitors and for companies that tried the idea before;
//   - our data: who funded those competitors, which listed firms hold one, firms to pitch instead, and the range of
//     rounds like the founder's (v2_ready_research and v2_ready_firms).
// Rules that hold whatever the model says:
//   - a looked-up row is shown only with a source address that the search really returned (no invented sources);
//   - nothing here says the founder will or will not raise, and nothing tells them to drop the idea;
//   - "you have" is taken from the founder's own deck, never a claim that a competitor lacks something.

const clip = (s, n) => { s = String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s; };

export const SEARCHES = 8;   // the most web searches one research may run

// What the model is told.
export function researchPrompt() {
  return `You research the market for an early-stage startup founder, using web search. You are careful and literal: you report only what a page from your search results states.

You get a short description of the startup taken from its pitch deck. Search the web, then answer.

1. COMPETITORS: up to 6 companies a buyer would compare this startup with (same buyer, same problem). Prefer funded startups. Include a large incumbent only when it is what buyers use today. Check the competitors the deck names and include the real ones.
   For each: "name"; "website" (its domain, for example acme.com); "what" (what it does, 16 words or fewer, neutral); "raised" (its latest round or total as the source reports it, for example "$12M Series A, 2025"; "" when no source reports it); "backers" (investor names exactly as the source lists them, 5 at most; [] when none are reported); "you_have" (ONE thing from the founder's own facts below that matters against this competitor, 14 words or fewer, copied in meaning from the facts; never claim the competitor lacks it; "" when nothing fits); "source" (the address of a page from your search results that states the funding or describes the company).
2. TRIED BEFORE: up to 4 companies that tried substantially the same idea earlier and then shut down, were sold, or moved away from it. Only when a source says so.
   For each: "name"; "years" (for example "2016 to 2020"); "what_happened" (one sentence, only what the source reports, no judgement); "founders" (names as the source gives them, 3 at most; [] when it names none); "source" (the address of the page that reports it).

Rules:
- Every row needs a "source" copied exactly from your search results. A row without one is thrown away.
- Never invent a company, a number, a person or an address. When you are not sure, leave the row out. Empty lists are a correct answer.
- Report facts about companies only. No opinions about people. No quotes.
- Never say the startup will or will not raise money. Never advise dropping the idea.
- Use at most ${SEARCHES} searches.

When you have finished searching, answer with ONE JSON object and nothing else, in exactly this shape:
{"competitors":[{"name":"","website":"","what":"","raised":"","backers":[""],"you_have":"","source":""}],
"tried_before":[{"name":"","years":"","what_happened":"","founders":[""],"source":""}]}`;
}

// The question for one report: built from what the report already holds, so the deck is not read a second time.
export function researchAsk(report) {
  const r = report && typeof report === 'object' ? report : {};
  const co = r.company || {};
  const facts = (Array.isArray(r.facts) ? r.facts : []).slice(0, 14).map((f) => `- ${clip(f && f.claim, 140)}`).filter((t) => t.length > 3);
  const named = (Array.isArray(r.competitors_named) ? r.competitors_named : []).filter(Boolean).slice(0, 10);
  const special = (Array.isArray(r.special) ? r.special : []).map((x) => `- ${clip(x.what, 120)}`);
  return [
    `Startup: ${clip(co.name, 60) || 'not named'}`,
    `What it does: ${clip(co.one_line, 160) || 'not stated'}`,
    `Stage: ${co.stage || 'unknown'}. Field: ${co.sector || 'unknown'}.${co.based_in ? ' Based in: ' + clip(co.based_in, 60) + '.' : ''}`,
    named.length ? `Competitors the deck names: ${named.join(', ')}` : 'The deck names no competitors.',
    facts.length || special.length ? `The founder's own facts (from the deck):\n${[...special, ...facts].join('\n')}` : '',
    'Search the web, then answer with the JSON object only.',
  ].filter(Boolean).join('\n\n');
}

// An address reduced to what identifies the page: host without www, path without a trailing slash, no query, no fragment.
export function normUrl(u) {
  try {
    const x = new URL(String(u).trim());
    if (!/^https?:$/.test(x.protocol)) return '';
    return x.hostname.toLowerCase().replace(/^www\./, '') + x.pathname.replace(/\/+$/, '');
  } catch (e) { return ''; }
}
export const hostOf = (u) => normUrl(u).split('/')[0];

// A website as the model wrote it ("https://www.acme.com/about", "acme.com") -> "acme.com".
export function domainOf(site) {
  const t = String(site || '').trim().toLowerCase();
  if (!t) return '';
  const h = hostOf(/^https?:\/\//.test(t) ? t : 'https://' + t);
  return /^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(h) ? h : '';
}

// Every page the search really returned, from the model's answer blocks: [{ url, title }].
export function pagesSeen(content) {
  const out = new Map();
  const add = (url, title) => { const k = normUrl(url); if (k && !out.has(k)) out.set(k, { url: String(url), title: String(title || '') }); };
  for (const b of Array.isArray(content) ? content : []) {
    if (!b || typeof b !== 'object') continue;
    if (b.type === 'web_search_tool_result' && Array.isArray(b.content)) for (const r of b.content) if (r && r.type === 'web_search_result') add(r.url, r.title);
    if (b.type === 'text' && Array.isArray(b.citations)) for (const c of b.citations) if (c && c.url) add(c.url, c.title);
  }
  return out;
}

// The source a row may show: the address itself when the search returned that page; otherwise a returned page on the same
// site whose title names the company; otherwise nothing, and the row is dropped.
export function checkSource(src, name, seen) {
  const k = normUrl(src);
  if (!k) return '';
  if (seen.has(k)) return seen.get(k).url;
  const host = k.split('/')[0], nm = String(name || '').toLowerCase().trim();
  if (!nm) return '';
  for (const [key, page] of seen) if (key.split('/')[0] === host && page.title.toLowerCase().includes(nm)) return page.url;
  return '';
}

// The model's last words after its searches: the JSON object.
export function answerText(content) {
  const blocks = Array.isArray(content) ? content : [];
  let last = -1;
  blocks.forEach((b, i) => { if (b && b.type === 'web_search_tool_result') last = i; });
  return blocks.slice(last + 1).filter((b) => b && b.type === 'text').map((b) => b.text).join('');
}

// The looked-up rows that survive the source check.
export function vetted(model, seen) {
  const m = model && typeof model === 'object' ? model : {};
  const names = new Set();
  const competitors = (Array.isArray(m.competitors) ? m.competitors : []).map((c) => {
    const name = clip(c && c.name, 60), src = name ? checkSource(c.source, name, seen) : '';
    if (!name || !src || names.has(name.toLowerCase())) return null;
    names.add(name.toLowerCase());
    return { name, site: domainOf(c.website), what: clip(c.what, 130), raised: clip(c.raised, 60),
      backers: (Array.isArray(c.backers) ? c.backers : []).map((b) => clip(b, 50)).filter(Boolean).slice(0, 5), you: clip(c.you_have, 110), src };
  }).filter(Boolean).slice(0, 6);
  const tried = (Array.isArray(m.tried_before) ? m.tried_before : []).map((t) => {
    const name = clip(t && t.name, 60), src = name ? checkSource(t.source, name, seen) : '';
    if (!name || !src || !t.what_happened) return null;
    return { name, years: clip(t.years, 24), happened: clip(t.what_happened, 180),
      founders: (Array.isArray(t.founders) ? t.founders : []).map((f) => clip(f, 50)).filter(Boolean).slice(0, 3), src };
  }).filter(Boolean).slice(0, 4);
  return { competitors, tried };
}

const usd = (n) => (n >= 1e9 ? '$' + (n / 1e9).toFixed(n % 1e9 ? 1 : 0) + 'B' : n >= 1e6 ? '$' + (n / 1e6).toFixed(n % 1e6 ? 1 : 0).replace(/\.0$/, '') + 'M' : '$' + Math.round(n / 1e3) + 'K');

// Where the ask sits among rounds like it, in plain words. Facts only; never a forecast.
export function askLine(ask, r) {
  if (!r || !(r.n >= 5)) return '';
  if (!(ask > 0)) return 'Your deck names no ask, so we cannot place it.';
  const where = ask < r.p25 ? 'below most rounds like yours' : ask <= r.p50 ? 'at the low end of the usual range' : ask <= r.p75 ? 'at the high end of the usual range' : 'above most rounds like yours';
  return `Your ask is ${where}. Announced rounds lean large, so the true middle is lower than ${usd(r.p50)}.`;
}

// Looked-up rows + our data -> what step 3 of the report draws.
//   ours: the answer of v2_ready_research; fit: the answer of v2_ready_firms (asked with a longer list).
export function buildResearch(rows, ours, fit, report, meta) {
  const o = ours && typeof ours === 'object' ? ours : {};
  const co = (report && report.company) || {};
  const held = new Map((Array.isArray(o.competitors) ? o.competitors : []).map((c) => [String(c.asked || '').toLowerCase(), c]));
  const competitors = rows.competitors.map((c) => {
    const h = held.get(c.name.toLowerCase());
    const mine = h && h.amount > 0 && h.currency === 'USD';
    const backers = h && Array.isArray(h.backers) && h.backers.length ? { ours: true, list: h.backers.slice(0, 6).map((b) => ({ name: b.name, slug: b.slug })) } : { ours: false, list: c.backers.map((b) => ({ name: b })) };
    return { name: c.name, site: c.site, what: c.what, you: c.you, src: c.src,
      raised: mine ? { ours: true, text: `${usd(Number(h.amount))} ${h.round || 'round'}`, date: h.date || null } : c.raised ? { ours: false, text: c.raised } : null,
      backers };
  });
  const skip = (Array.isArray(o.skip) ? o.skip : []).map((s) => ({ slug: s.slug, name: s.name, backed: (Array.isArray(s.backed) ? s.backed : []).slice(0, 3) })).slice(0, 8);
  const skipped = new Set(skip.map((s) => s.slug));
  const stage = o.stage || co.stage || 'Seed';
  const instead = ((fit && Array.isArray(fit.firms)) ? fit.firms : []).filter((f) => !skipped.has(f.slug)).slice(0, 6)
    .map((f) => ({ slug: f.slug, name: f.name, fit: Number(f.fit) || 0, city: f.city || '', country: f.country || '' }));
  const r = o.rounds && Number(o.rounds.n) >= 5 ? { n: Number(o.rounds.n), p25: Number(o.rounds.p25), p50: Number(o.rounds.p50), p75: Number(o.rounds.p75), p90: Number(o.rounds.p90) } : null;
  const ask = Number(co.ask_usd) > 0 ? Number(co.ask_usd) : null;
  return { v: 1, at: (meta && meta.at) || null, competitors, skip, instead, tried: rows.tried,
    rounds: r ? { ...r, ask, stage, sector: o.sector_known ? co.sector || null : null, line: askLine(ask, r) } : null,
    stage, sector: co.sector || null,
    searches: (meta && meta.searches) || 0, model: (meta && meta.model) || null, tokens_in: (meta && meta.tokens_in) || null, tokens_out: (meta && meta.tokens_out) || null };
}
