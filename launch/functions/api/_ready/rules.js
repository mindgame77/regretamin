// "Am I ready to pitch?": the fixed rules. The model only answers the checklist; everything here is plain arithmetic,
// so the same answers always give the same verdict and the same importance numbers (founder, 26 Nov 2026).
import { CHECKLIST } from './checklist.js';

export const BY_N = new Map(CHECKLIST.map((r) => [r[0], { n: r[0], area: r[1], q: r[2], stage: r[3], red: r[4], yellow: r[5], fix: r[6] }]));

// How much each area counts, 1 to 10, by stage. Team counts most at pre-seed; traction counts as much at seed.
export const AREA_WEIGHT = {
  'Founders and team': [10, 8], 'Problem': [8, 7], 'Market': [8, 8], 'Solution and product': [7, 7], 'Traction': [6, 10],
  'Deck itself': [7, 7], 'The round': [8, 8], 'Competition': [7, 7], 'Go-to-market': [5, 7], 'Business model': [4, 7],
  'Why now': [6, 6], 'Technology': [5, 5], 'Company basics': [5, 6], 'Cap table and investors': [5, 6],
  'Location and US presence': [5, 5], 'Risks and honesty': [6, 6], 'Virality and audience': [4, 4],
};
// Questions that sink a deck on their own: no ask, "no competitors", "1% of a huge market", claims without proof.
const CRITICAL = new Set([14, 15, 89, 107, 170, 171]);
const NO_ASK = 4;  // "Is there one clear ask?": nothing else matters until it is there
// Answered from our own data, not from the deck: never sent to the model.
export const FROM_OUR_DATA = new Set(CHECKLIST.filter((r) => r[1] === 'Investor fit').map((r) => r[0]));

export const SECTORS = ['Enterprise software', 'Fintech', 'Consumer', 'Biotech', 'Climate & Energy', 'Health', 'Commerce', 'AI agents', 'Food',
  'Digital health', 'Cybersecurity', 'Crypto', 'AI models', 'Media', 'Medtech', 'Hardware', 'Education', 'Cloud & Data', 'AI infrastructure',
  'Marketing', 'Manufacturing', 'Mobility', 'Logistics', 'Other'];

export function normStage(s) {
  const t = String(s || '').toLowerCase();
  return /pre/.test(t) ? 'Pre-seed' : /seed/.test(t) ? 'Seed' : 'Seed';
}

// Importance of one raised flag, 1 to 10. Red: 7 to 10. Yellow: 3 to 6.
export function importance(n, level, stage) {
  const it = BY_N.get(n);
  const w = (it && AREA_WEIGHT[it.area] ? AREA_WEIGHT[it.area] : [5, 5])[normStage(stage) === 'Pre-seed' ? 0 : 1];
  const base = level === 'red' ? 4 + w / 2 : 1 + w / 2;
  const v = Math.round(base) + (n === NO_ASK ? 2 : CRITICAL.has(n) ? 1 : 0);
  return level === 'red' ? Math.max(7, Math.min(10, v)) : Math.max(3, Math.min(6, v));
}

// The score shown beside each point, 1 to 10, where 10 is as good as it gets (founder, 26 Nov: "when people see 1 of 10,
// they understand they have to level it up"). A red flag scores 1 to 4, an improvement 4 to 7, a strength 8 or 9, and
// the one exceptional thing 10. It is the importance turned round, so the most important red flag has the lowest score.
export function score(n, level, stage) {
  if (level === 'lead') return 10;
  if (level === 'good') { const it = BY_N.get(n); const w = (it && AREA_WEIGHT[it.area] ? AREA_WEIGHT[it.area] : [5, 5])[normStage(stage) === 'Pre-seed' ? 0 : 1]; return w >= 8 ? 9 : 8; }
  return level === 'red' ? 11 - importance(n, 'red', stage) : 10 - importance(n, 'yellow', stage);
}
const TEAM_AREAS = new Set(['Founders and team', 'Virality and audience']);
// One number for the deck and one for the founders: the average of every point judged, each counted by how much its
// area matters at this stage. No points about the founders means no founders score (the deck says too little).
function overall(items, stage, teamOnly) {
  let sum = 0, wsum = 0;
  for (const x of items) {
    if (teamOnly && !TEAM_AREAS.has(x.area)) continue;
    const w = (AREA_WEIGHT[x.area] || [5, 5])[stage === 'Pre-seed' ? 0 : 1];
    sum += x.score * w; wsum += w;
  }
  return wsum ? Math.max(1, Math.min(10, Math.round(sum / wsum))) : null;
}

const clip = (s, n) => { s = String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s; };

// The model's text is JSON, sometimes wrapped in a code fence or a sentence.
export function parseModelJson(text) {
  const t = String(text || '');
  const a = t.indexOf('{'), b = t.lastIndexOf('}');
  if (a < 0 || b <= a) return null;
  try { return JSON.parse(t.slice(a, b + 1)); } catch (e) { return null; }
}

// Model answers + matched firms -> the report the page draws.
export function assemble(model, firms) {
  const m = model && typeof model === 'object' ? model : {};
  const co = m.company && typeof m.company === 'object' ? m.company : {};
  const stage = normStage(co.stage);
  const seen = new Set();
  const flags = (Array.isArray(m.flags) ? m.flags : []).map((f) => {
    const n = Number(f && f.n), it = BY_N.get(n), level = f && f.level === 'red' ? 'red' : f && f.level === 'yellow' ? 'yellow' : null;
    if (!it || !level || FROM_OUR_DATA.has(n) || seen.has(n)) return null;
    if (it.stage !== 'Both' && it.stage !== stage) return null;
    seen.add(n);
    return { n, level, area: it.area, what: clip(f.what || (level === 'red' ? it.red : it.yellow), 110), where: clip(f.where || '', 24),
      why: clip(f.why || '', 150), fix: clip(f.fix || it.fix, 170), matters: importance(n, level, stage), score: score(n, level, stage) };
  }).filter(Boolean).sort((x, y) => y.matters - x.matters || x.n - y.n);
  const reds = flags.filter((f) => f.level === 'red').slice(0, 8), yellows = flags.filter((f) => f.level === 'yellow').slice(0, 6);
  const lead = m.lead_with && m.lead_with.text ? { text: clip(m.lead_with.text, 220), where: clip(m.lead_with.where || '', 24) } : null;
  const good = (Array.isArray(m.strengths) ? m.strengths : []).map((g) => {
    const n = Number(g && g.n), it = BY_N.get(n);
    if (!it || FROM_OUR_DATA.has(n) || seen.has(n) || !g.what) return null;
    seen.add(n);
    return { n, level: 'good', area: it.area, what: clip(g.what, 110), where: clip(g.where || '', 24), why: clip(g.why || '', 150), score: score(n, 'good', stage) };
  }).filter(Boolean).sort((x, y) => y.score - x.score || x.n - y.n).slice(0, 5);
  const judged = [...reds, ...yellows, ...good, ...(lead ? [{ area: 'Founders and team', score: 10 }] : [])];
  const f = firms && typeof firms === 'object' ? firms : {};
  return {
    v: 2,
    company: { name: clip(co.name, 60), one_line: clip(co.one_line, 140), stage, stage_stated: !!co.stage && !/unknown/i.test(String(co.stage)),
      sector: SECTORS.includes(co.sector) ? co.sector : 'Other', ask_usd: Number(co.ask_usd) > 0 ? Math.round(Number(co.ask_usd)) : null,
      based_in: clip(co.based_in, 60), slides: Number(co.slides) > 0 ? Math.round(Number(co.slides)) : null },
    verdict: reds.length ? `Fix ${reds.length} thing${reds.length === 1 ? '' : 's'} first.` : 'Ready to send.',
    reds, yellows, lead, good,
    scores: { deck: overall(judged, stage, false), founders: overall(judged, stage, true) },
    facts: (Array.isArray(m.facts) ? m.facts : []).slice(0, 20).map((x) => ({ claim: clip(x && x.claim, 140), proof: ['proven', 'shown', 'claimed', 'assumed'].includes(x && x.proof) ? x.proof : 'claimed', where: clip(x && x.where, 24) })),
    competitors_named: (Array.isArray(m.competitors_named) ? m.competitors_named : []).slice(0, 10).map((x) => clip(x, 60)),
    firms: (Array.isArray(f.firms) ? f.firms : []).map((x) => ({ ...x, say: sayTo(x, stage, co.sector) })),
    then: Array.isArray(f.then) ? f.then : [],
  };
}

// One line of advice per firm, from its own numbers only.
export function sayTo(x, stage, sector) {
  const out = [];
  if (Number(x.stage_pct) >= 70) out.push(`Almost only first cheques. Keep the ask at ${stage.toLowerCase()} size.`);
  if (Number(x.sector_pct) >= 40 && sector) out.push(`${sector} is its main field. Skip the basics and go deep.`);
  if (Number(x.n90) >= 5) out.push('It is investing fast right now. Go now.');
  if (!out.length) out.push(`It has done ${x.fit} ${stage.toLowerCase()} deal${Number(x.fit) === 1 ? '' : 's'} in your field in the last 12 months. Say why you are the next.`);
  return out.slice(0, 2).join(' ');
}

// What the model is told. The checklist rows for the other stage and the "our data" rows are left out.
export function systemPrompt() {
  const rows = CHECKLIST.filter((r) => !FROM_OUR_DATA.has(r[0])).map((r) => `${r[0]} | ${r[1]} | ${r[2]} | ${r[3]} | RED: ${r[4] || '-'} | YELLOW: ${r[5] || '-'}`).join('\n');
  return `You review an early-stage startup pitch deck the way an experienced pre-seed and seed investor reads it. You are careful and literal: you report only what the deck (and the founder's note) actually shows.

You get the deck as a PDF, and sometimes a note from the founder and a LinkedIn link (you cannot open links).

Work in this order:
1. Read every slide. Work out the company, its stage (Pre-seed or Seed; if the deck does not say, judge from the ask and traction and say "unknown" only if you truly cannot tell), its sector, the ask in US dollars, and where it is based.
2. List the main factual claims and how well each is proven: "proven" (a document, a named customer, a public source shown), "shown" (a screenshot, chart or link), "claimed" (the deck says so, nothing more), "assumed" (a forecast or a guess).
3. Go through the checklist below. Raise a flag ONLY where the deck gives real evidence that the RED or YELLOW description applies. Skip rows that the deck gives you no basis to judge, rows for the other stage, and rows where the deck is fine. Most rows will be skipped. Never raise more than 8 red and 6 yellow flags: keep the ones an investor would notice first.
4. List what is good: 3 to 5 checklist rows where the deck clearly does well, with the evidence on a slide. Be as strict as with the flags. If the deck has fewer real strengths, list fewer; never pad.
5. Find at most one truly exceptional strength (the kind an investor repeats to a partner, for example a founder who built and sold a company in this field). If there is none, use null. Ordinary good things are not exceptional, and the exceptional one is not repeated among the strengths.

For every flag write, about THIS deck, in plain words:
- "what": what is wrong, in 12 words or fewer.
- "where": "Slide N", or "Not in the deck".
- "why": one sentence on why an investor cares.
- "fix": one concrete instruction the founder can act on today.
For every strength write "what" (what is good, 12 words or fewer), "where" and "why" (one sentence on why an investor likes it).

Never say the company will or will not raise money. Never tell the founder to drop the idea. Do not flatter.

Answer with ONE JSON object and nothing else, in exactly this shape:
{"company":{"name":"","one_line":"","stage":"Pre-seed|Seed|unknown","sector":"one of: ${SECTORS.join(', ')}","ask_usd":0,"based_in":"","slides":0},
"facts":[{"claim":"","proof":"proven|shown|claimed|assumed","where":"Slide N"}],
"flags":[{"n":0,"level":"red|yellow","what":"","where":"","why":"","fix":""}],
"strengths":[{"n":0,"what":"","where":"Slide N","why":""}],
"lead_with":{"text":"","where":"Slide N"},
"competitors_named":[""]}
"n" is the checklist number. Use null for "ask_usd", "based_in" or "lead_with" when not known.

CHECKLIST (number | area | question | stage | red | yellow):
${rows}`;
}
