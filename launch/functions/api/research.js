// POST /api/research  { id }  with the visitor's own sign-in token: the full research for their finished report.
// Step 3 of "Am I ready to pitch?" (founder, 26 Nov 2026). One request while the page waits; the result is saved on the
// report (result.research), so it is made once per report and reopens with it. Costs 25 credits, taken once the research is made (ready_credits_ok before, ready_charge after): a run that fails costs nothing.
//   1. who is asking, and their own finished report;
//   2. the model searches the web (Claude's own web search tool) for competitors and for who tried the idea before;
//   3. rows without a source the search really returned are dropped (./_ready/research.js);
//   4. our database adds who funded the competitors, what we know about their founders, the firms that hold one, and the
//      range of rounds like the founder's (v2_ready_research), and tips about the firms to pitch (v2_ready_firm_tips).
// Needs the Cloudflare secret ANTHROPIC_API_KEY (the search tool is Claude's). READY_MODEL may name another Claude model.
import { parseModelJson } from './_ready/rules.js';
import { researchPrompt, researchAsk, pagesSeen, answerText, vetted, buildResearch, SEARCHES } from './_ready/research.js';

const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

export async function onRequestPost(ctx) {
  const env = ctx.env || {};
  const SB = env.SUPABASE_URL, ANON = env.SUPABASE_ANON_KEY;
  if (!SB || !ANON) return json({ error: 'not_configured' }, 503);
  if (!env.ANTHROPIC_API_KEY) return json({ error: 'no_key' }, 503);
  const token = (ctx.request.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  let body = null;
  try { body = await ctx.request.json(); } catch (e) { body = null; }
  const id = body && typeof body.id === 'string' && /^[0-9a-f-]{36}$/i.test(body.id) ? body.id : null;
  if (!token || !id) return json({ error: 'bad_request' }, 400);
  const mine = { apikey: ANON, authorization: `Bearer ${token}`, 'content-type': 'application/json' };

  const who = await fetch(`${SB}/auth/v1/user`, { headers: mine });
  if (!who.ok) return json({ error: 'sign_in' }, 401);

  const rr = await fetch(`${SB}/rest/v1/ready_reports?id=eq.${id}&select=id,status,result`, { headers: mine });
  const row = rr.ok ? (await rr.json())[0] : null;
  if (!row || row.status !== 'done' || !row.result) return json({ error: 'not_found' }, 404);
  if (row.result.research) return json({ research: row.result.research, id });

  const rpcw = async (fn, args) => {
    try { const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: mine, body: JSON.stringify(args) }); return r.ok ? await r.json() : null; } catch (e) { return null; }
  };
  const gate = await rpcw('ready_credits_ok', { p_kind: 'research' });
  if (!gate) return json({ error: 'credits_unavailable' }, 503);
  if (gate.status === 'out') return json({ error: 'out_of_credits', need: gate.need, left: gate.left }, 402);
  if (gate.status === 'limit') return json({ error: 'daily_limit' }, 429);
  if (gate.status !== 'ok') return json({ error: 'sign_in' }, 401);

  const save = (patch) => fetch(`${SB}/rest/v1/ready_reports?id=eq.${id}`, { method: 'PATCH', headers: { ...mine, prefer: 'return=minimal' }, body: JSON.stringify(patch) }).catch(() => {});
  // A failed research leaves the report as it is; the reason is kept on the row so it can be read later.
  const fail = async (error, status = 502) => { await save({ error: `research: ${String(error).slice(0, 1100)}` }); return json({ error: String(error).split(':')[0] }, status); };

  const got = await search(env, researchAsk(row.result));
  if (got.error) return fail(/credit balance|quota|billing/i.test(got.error) ? `model_no_credit: ${got.error}` : got.error);
  const answer = parseModelJson(answerText(got.content));
  if (!answer) return fail('model_answer_unreadable');
  const rows = vetted(answer, pagesSeen(got.content));

  const co = row.result.company || {};
  const rpc = async (fn, args) => {
    try { const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: mine, body: JSON.stringify(args) }); return r.ok ? await r.json() : null; } catch (e) { return null; }
  };
  const [ours, tips, peers] = await Promise.all([
    rpc('v2_ready_research', { p_names: rows.competitors.map((c) => c.name), p_domains: rows.competitors.map((c) => c.site || null), p_stage: String(co.stage || 'Seed'), p_sector: String(co.sector || 'Other') }),
    rpc('v2_ready_firm_tips', { p_slugs: (Array.isArray(row.result.firms) ? row.result.firms : []).map((f) => f && f.slug).filter(Boolean).slice(0, 12) }),
    Number(co.ask_usd) > 0 ? rpc('v2_ready_ask_peers', { p_stage: String(co.stage || 'Seed'), p_sector: String(co.sector || 'Other'), p_ask: Number(co.ask_usd) }) : null,
  ]);

  // The badges the site already awards each of those firms (the same read the firm pages use).
  const slugs = (Array.isArray(row.result.firms) ? row.result.firms : []).map((f) => f && f.slug).filter(Boolean).slice(0, 6);
  const signals = {};
  await Promise.all(slugs.map(async (slug) => { const g = await rpc('v2_firm_signals_for', { p_slug: slug }); if (g && Array.isArray(g.signals)) signals[slug] = g.signals; }));

  const research = buildResearch(rows, ours, row.result, { at: new Date().toISOString(), searches: got.searches, model: got.model, tokens_in: got.usage.in, tokens_out: got.usage.out }, tips, signals, peers);
  const paid = await rpcw('ready_charge', { p_report: id, p_kind: 'research' });
  if (!paid || paid.status !== 'ok') return fail(paid ? 'out_of_credits' : 'credits_unavailable', paid ? 402 : 503); // not delivered, not charged
  await save({ result: { ...row.result, research }, error: null });
  return json({ research, id });
}

// The model with its web search tool. A long search can come back paused: the same conversation is sent again to carry on.
async function search(env, ask) {
  const model = /^claude/.test(env.READY_MODEL || '') ? env.READY_MODEL : 'claude-opus-5-5';
  const content = [], usage = { in: 0, out: 0 };
  let searches = 0;
  for (let turn = 0; turn < 5; turn++) {
    const messages = [{ role: 'user', content: ask }];
    if (content.length) messages.push({ role: 'assistant', content });
    let r;
    try {
      r = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'x-api-key': env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
        body: JSON.stringify({ model, max_tokens: 8000, system: researchPrompt(), messages,   // no temperature: Opus 5.5 refuses the setting
          tools: [{ type: 'web_search_20250305', name: 'web_search', max_uses: SEARCHES }] }),
      });
    } catch (e) { return { error: 'model_unreachable' }; }
    if (!r.ok) return { error: `model_${r.status}: ${(await r.text().catch(() => '')).slice(0, 500)}` };
    const out = await r.json(), u = out.usage || {};
    content.push(...(out.content || []));
    usage.in += u.input_tokens || 0; usage.out += u.output_tokens || 0;
    searches += (u.server_tool_use && u.server_tool_use.web_search_requests) || 0;
    if (out.stop_reason !== 'pause_turn') break;
  }
  return { model, content, usage, searches };
}
