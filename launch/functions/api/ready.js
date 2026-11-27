// POST /api/ready  { id }  with the visitor's own sign-in token: reads their deck, returns their report.
// "Am I ready to pitch?", first working version (founder, 26 Nov 2026: "just do it so we could test it, then credits").
// One request does everything while the page waits: no queue, no email yet. A report costs 10 credits, taken only once it is made
// (ready_credits_ok before the model is asked, ready_charge after): a run that fails costs nothing.
//   1. who is asking (their Supabase session), and their report row (they can only read their own);
//   2. a link to their deck that works for 15 minutes, handed to the model with the checklist;
//   3. fixed rules turn the model's answers into the verdict and the importance numbers (./_ready/rules.js);
//   4. firms that fit, from our own database (v2_ready_firms);
//   5. the report is saved on their row and sent back.
// Secrets live in Cloudflare (the founder puts them there): ANTHROPIC_API_KEY (used first) and GEMINI_API_KEY (the spare; founder, 26 Nov: "let's try Gemini ...
// Neon"). READY_MODEL may name another model of the same maker.
import { systemPrompt, parseModelJson, assemble, reFirm } from './_ready/rules.js';

const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

export async function onRequestPost(ctx) {
  const env = ctx.env || {};
  const SB = env.SUPABASE_URL, ANON = env.SUPABASE_ANON_KEY;
  if (!SB || !ANON) return json({ error: 'not_configured' }, 503);
  if (!env.GEMINI_API_KEY && !env.ANTHROPIC_API_KEY) return json({ error: 'no_key' }, 503);
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
  // The firms to pitch: firms that invest where the founder is come first (founder, 26 Nov: "you're a Ukrainian startup, here is
  // the fund that invests in Ukraine"). Until that database function exists, or if it fails, the older pick answers.
  const pick = async (co, country) => {
    const args = { p_stage: String(co.stage || 'Seed'), p_sector: String(co.sector || 'Other'), p_limit: 6 };
    const ask = async (fn, a) => { try { const fr = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: mine, body: JSON.stringify(a) }); return fr.ok ? await fr.json() : null; } catch (e) { return null; } };
    return (await ask('v2_ready_firms_geo', { ...args, p_country: country || null })) || (await ask('v2_ready_firms', args));
  };
  // The founder says where they are based (asked only when the deck did not say): pick the firms again. Not once the research is made.
  const country = body && typeof body.country === 'string' && /^[A-Za-z]{2}$/.test(body.country) ? body.country.toUpperCase() : null;
  if (country && row.status === 'done' && row.result && !row.result.research) {
    const firms = await pick(row.result.company || {}, country);
    if (!firms) return json({ error: 'firms_unavailable' }, 502);
    const report = reFirm(row.result, firms, country);
    await fetch(`${SB}/rest/v1/ready_reports?id=eq.${id}`, { method: 'PATCH', headers: { ...mine, prefer: 'return=minimal' }, body: JSON.stringify({ result: report }) }).catch(() => {});
    return json({ report, id });
  }
  if (row.status === 'done' && row.result) return json({ report: row.result, id });
  if (!String(row.deck_path || '').startsWith(`${user.id}/`)) return json({ error: 'not_found' }, 404);

  // 10 credits for a report (the database decides the amount). Enough credits are checked before the model is asked; they are taken after.
  const rpc = async (fn, args) => {
    try { const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: mine, body: JSON.stringify(args) }); return r.ok ? await r.json() : null; } catch (e) { return null; }
  };
  const gate = await rpc('ready_credits_ok', { p_kind: 'report' });
  if (!gate) return json({ error: 'credits_unavailable' }, 503);
  if (gate.status === 'out') return json({ error: 'out_of_credits', need: gate.need, left: gate.left }, 402);
  if (gate.status === 'limit') return json({ error: 'daily_limit' }, 429);
  if (gate.status !== 'ok') return json({ error: 'sign_in' }, 401);

  const save = (patch) => fetch(`${SB}/rest/v1/ready_reports?id=eq.${id}`, { method: 'PATCH', headers: { ...mine, prefer: 'return=minimal' }, body: JSON.stringify(patch) }).catch(() => {});
  const fail = async (error, status = 502) => { await save({ status: 'failed', error: String(error).slice(0, 1200), finished_at: new Date().toISOString() }); return json({ error: String(error).split(':')[0] }, status); };
  await save({ status: 'working', error: null });

  const path = String(row.deck_path).split('/').map(encodeURIComponent).join('/');
  const sg = await fetch(`${SB}/storage/v1/object/sign/decks/${path}`, { method: 'POST', headers: mine, body: JSON.stringify({ expiresIn: 900 }) });
  const signed = sg.ok ? await sg.json() : null;
  const link = signed && (signed.signedURL || signed.signedUrl);
  if (!link) return fail('deck_missing', 404);

  const note = [row.note ? `The founder's note:\n${String(row.note).slice(0, 8000)}` : '', row.linkedin ? `The founder's LinkedIn (cannot be opened): ${String(row.linkedin).slice(0, 200)}` : '']
    .filter(Boolean).join('\n\n') || 'The founder sent the deck only.';
  const deckUrl = `${SB}/storage/v1${link}`;
  const ask = `${note}\n\nReview this deck. Answer with the JSON object only.`;
  // Claude first (founder, 26 Nov: Gemini kept answering "quota", which cost time on every report); Gemini is the spare when both keys are set.
  const both = !!(env.GEMINI_API_KEY && env.ANTHROPIC_API_KEY);
  const [first_, spare_] = env.ANTHROPIC_API_KEY ? [askClaude, askGemini] : [askGemini, askClaude];
  let got = await first_(env, deckUrl, ask);
  if (both && (got.error || !parseModelJson(got.text))) {
    const first = got.error || 'model_answer_unreadable';
    got = await spare_(env, deckUrl, ask);
    if (got.error) got.error = `${first}; then ${got.error}`;
  }
  // Whether the last model asked refused for lack of credit: the page then says so instead of blaming the deck.
  if (got.error) return fail(/credit balance|quota|billing/i.test(got.error.split('; then ').pop()) ? `model_no_credit: ${got.error}` : got.error);
  const { model, text, usage } = got;
  const answers = parseModelJson(text);
  if (!answers) return fail('model_answer_unreadable');

  const firms = await pick(answers.company || {}, /^[A-Za-z]{2}$/.test(String((answers.company || {}).country || '').trim()) ? String(answers.company.country).trim().toUpperCase() : null);

  const report = assemble(answers, firms);
  const paid = await rpc('ready_charge', { p_report: id, p_kind: 'report' });
  if (!paid || paid.status !== 'ok') return fail(paid ? 'out_of_credits' : 'credits_unavailable', paid ? 402 : 503); // not delivered, not charged
  await save({ status: 'done', result: report, model, tokens_in: usage.in || null, tokens_out: usage.out || null, finished_at: new Date().toISOString(), error: null });
  return json({ report, id });
}

// The model is one replaceable part: each maker's call takes the deck's link and the question, and gives back the text.
async function askClaude(env, deckUrl, ask) {
  const model = /^claude/.test(env.READY_MODEL || '') ? env.READY_MODEL : 'claude-opus-5-5';
  let r;
  try {
    r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({ model, max_tokens: 16000, system: systemPrompt(),  // no temperature: Opus 5.5 refuses the setting (26 Nov)
        messages: [{ role: 'user', content: [{ type: 'document', source: { type: 'url', url: deckUrl } }, { type: 'text', text: ask }] }] }),
    });
  } catch (e) { return { error: 'model_unreachable' }; }
  if (!r.ok) return { error: `model_${r.status}: ${(await r.text().catch(() => '')).slice(0, 500)}` };
  const out = await r.json(), u = out.usage || {};
  return { model, text: (out.content || []).filter((c) => c.type === 'text').map((c) => c.text).join(''), usage: { in: u.input_tokens, out: u.output_tokens } };
}

// Gemini: the deck goes by its link (the maker fetches files up to 15 MB itself); if that is refused, the file is sent inside the request.
async function askGemini(env, deckUrl, ask) {
  const model = /^gemini/.test(env.READY_MODEL || '') ? env.READY_MODEL : 'gemini-4-neon';
  const call = (filePart) => fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
    method: 'POST',
    headers: { 'x-goog-api-key': env.GEMINI_API_KEY, 'content-type': 'application/json' },
    body: JSON.stringify({ systemInstruction: { parts: [{ text: systemPrompt() }] },
      contents: [{ role: 'user', parts: [filePart, { text: ask }] }],
      generationConfig: { maxOutputTokens: 16000, responseMimeType: 'application/json' } }),
  });
  let r;
  try {
    r = await call({ fileData: { mimeType: 'application/pdf', fileUri: deckUrl } });
    if (!r.ok && r.status !== 401 && r.status !== 429) {
      const deck = await fetch(deckUrl);
      if (!deck.ok) return { error: 'deck_missing' };
      r = await call({ inlineData: { mimeType: 'application/pdf', data: base64(new Uint8Array(await deck.arrayBuffer())) } });
    }
  } catch (e) { return { error: 'model_unreachable' }; }
  if (!r.ok) return { error: `model_${r.status}: ${(await r.text().catch(() => '')).slice(0, 500)}` };
  const out = await r.json(), u = out.usageMetadata || {};
  const parts = (((out.candidates || [])[0] || {}).content || {}).parts || [];
  return { model, text: parts.filter((x) => typeof x.text === 'string' && !x.thought).map((x) => x.text).join(''),
    usage: { in: u.promptTokenCount, out: (u.candidatesTokenCount || 0) + (u.thoughtsTokenCount || 0) } };
}

function base64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
