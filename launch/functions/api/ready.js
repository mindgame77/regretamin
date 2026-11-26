// POST /api/ready  { id }  with the visitor's own sign-in token: reads their deck, returns their report.
// "Am I ready to pitch?", first working version (founder, 26 Nov 2026: "just do it so we could test it, then credits").
// One request does everything while the page waits: no queue, no credits, no email yet.
//   1. who is asking (their Supabase session), and their report row (they can only read their own);
//   2. a link to their deck that works for 15 minutes, handed to the model with the checklist;
//   3. fixed rules turn the model's answers into the verdict and the importance numbers (./_ready/rules.js);
//   4. firms that fit, from our own database (v2_ready_firms);
//   5. the report is saved on their row and sent back.
// Secrets: ANTHROPIC_API_KEY lives in Cloudflare (the founder puts it there). READY_MODEL may name another model.
import { systemPrompt, parseModelJson, assemble } from './_ready/rules.js';

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
  const user = await who.json();

  const rr = await fetch(`${SB}/rest/v1/ready_reports?id=eq.${id}&select=id,deck_path,linkedin,note,status,result`, { headers: mine });
  const row = rr.ok ? (await rr.json())[0] : null;
  if (!row) return json({ error: 'not_found' }, 404);
  if (row.status === 'done' && row.result) return json({ report: row.result, id });
  if (!String(row.deck_path || '').startsWith(`${user.id}/`)) return json({ error: 'not_found' }, 404);

  const save = (patch) => fetch(`${SB}/rest/v1/ready_reports?id=eq.${id}`, { method: 'PATCH', headers: { ...mine, prefer: 'return=minimal' }, body: JSON.stringify(patch) }).catch(() => {});
  const fail = async (error, status = 502) => { await save({ status: 'failed', error: String(error).slice(0, 300), finished_at: new Date().toISOString() }); return json({ error }, status); };
  await save({ status: 'working', error: null });

  const path = String(row.deck_path).split('/').map(encodeURIComponent).join('/');
  const sg = await fetch(`${SB}/storage/v1/object/sign/decks/${path}`, { method: 'POST', headers: mine, body: JSON.stringify({ expiresIn: 900 }) });
  const signed = sg.ok ? await sg.json() : null;
  const link = signed && (signed.signedURL || signed.signedUrl);
  if (!link) return fail('deck_missing', 404);

  const note = [row.note ? `The founder's note:\n${String(row.note).slice(0, 8000)}` : '', row.linkedin ? `The founder's LinkedIn (cannot be opened): ${String(row.linkedin).slice(0, 200)}` : '']
    .filter(Boolean).join('\n\n') || 'The founder sent the deck only.';
  const model = env.READY_MODEL || 'claude-opus-5-5'  /* founder, 26 Nov: "let's try Opus 5.5"; about 26 cents a report by estimate */;
  let ai;
  try {
    ai = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({ model, max_tokens: 6000, temperature: 0, system: systemPrompt(),
        messages: [{ role: 'user', content: [{ type: 'document', source: { type: 'url', url: `${SB}/storage/v1${link}` } }, { type: 'text', text: `${note}\n\nReview this deck. Answer with the JSON object only.` }] }] }),
    });
  } catch (e) { return fail('model_unreachable'); }
  if (!ai.ok) { const t = await ai.text().catch(() => ''); return fail(`model_${ai.status}: ${t.slice(0, 200)}`); }
  const out = await ai.json();
  const text = (out.content || []).filter((c) => c.type === 'text').map((c) => c.text).join('');
  const answers = parseModelJson(text);
  if (!answers) return fail('model_answer_unreadable');

  let firms = null;
  try {
    const co = answers.company || {};
    const fr = await fetch(`${SB}/rest/v1/rpc/v2_ready_firms`, { method: 'POST', headers: mine, body: JSON.stringify({ p_stage: String(co.stage || 'Seed'), p_sector: String(co.sector || 'Other'), p_limit: 6 }) });
    firms = fr.ok ? await fr.json() : null;
  } catch (e) { firms = null; }

  const report = assemble(answers, firms);
  const usage = out.usage || {};
  await save({ status: 'done', result: report, model, tokens_in: usage.input_tokens || null, tokens_out: usage.output_tokens || null, finished_at: new Date().toISOString(), error: null });
  return json({ report, id });
}
