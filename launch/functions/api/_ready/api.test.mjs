import test from 'node:test';
import assert from 'node:assert/strict';
import { onRequestPost } from '../ready.js';

// A dry run of /api/ready with stand-ins for the database and the model.
function world({ geo, credits = 'ok', charge = 'ok' }) {
  const calls = [], state = { row: { id: 'x', deck_path: 'u1/a.pdf', linkedin: null, note: null, status: 'new', result: null } };
  const ok = (o) => new Response(JSON.stringify(o), { status: 200, headers: { 'content-type': 'application/json' } });
  const fetchStub = async (url, opt = {}) => {
    const u = String(url); calls.push(u.replace(/\?.*/, '').replace('https://db.example', ''));
    if (u.includes('/auth/v1/user')) return ok({ id: 'u1' });
    if (u.includes('/rest/v1/ready_reports') && (opt.method || 'GET') === 'GET') return ok([state.row]);
    if (u.includes('/rest/v1/ready_reports') && opt.method === 'PATCH') { Object.assign(state.row, JSON.parse(opt.body)); return new Response(null, { status: 204 }); }
    if (u.includes('/rpc/ready_credits_ok')) { state.gate = JSON.parse(opt.body); return ok({ status: credits, need: 10, left: 4 }); }
    if (u.includes('/rpc/ready_charge')) { state.charged = JSON.parse(opt.body); return ok({ status: charge }); }
    if (u.includes('/storage/v1/object/sign/')) return ok({ signedURL: '/object/sign/decks/u1/a.pdf?token=t' });
    if (u.includes('api.anthropic.com')) return ok({ content: [{ type: 'text', text: JSON.stringify({ company: { name: 'Obimy', stage: 'Seed', sector: 'Consumer', country: 'ua' }, flags: [{ n: 4, level: 'red', fix_by: 'words' }] }) }], usage: { input_tokens: 10, output_tokens: 5 } });
    if (u.includes('/rpc/v2_ready_firms_geo')) { state.geoArgs = JSON.parse(opt.body); return geo ? ok({ firms: [{ slug: 'ta', name: 'TA Ventures', fit: 0, n90: 1, geo: 'country', n_country: 2 }], then: [], country: state.geoArgs.p_country }) : new Response('{"code":"PGRST202"}', { status: 404 }); }
    if (u.includes('/rpc/v2_ready_firms')) return ok({ firms: [{ slug: 'old', name: 'Old Fund', fit: 2, n90: 1 }], then: [] });
    throw new Error('unexpected ' + u);
  };
  const ask = (body) => onRequestPost({ env: { SUPABASE_URL: 'https://db.example', SUPABASE_ANON_KEY: 'k', ANTHROPIC_API_KEY: 'k' },
    request: new Request('https://site.example/api/ready', { method: 'POST', headers: { authorization: 'Bearer t', 'content-type': 'application/json' }, body: JSON.stringify({ id: '11111111-1111-1111-1111-111111111111', ...body }) }) });
  return { calls, state, fetchStub, ask };
}

test('firms are picked for the country the deck shows; the older pick answers when the new one is not there', async () => {
  const real = globalThis.fetch;
  try {
    const a = world({ geo: true }); globalThis.fetch = a.fetchStub;
    const ra = await (await a.ask({})).json();
    assert.equal(a.state.geoArgs.p_country, 'UA'); assert.deepEqual(ra.report.firms.map((f) => f.slug), ['ta']); assert.equal(ra.report.company.country, 'UA');
    const b = world({ geo: false }); globalThis.fetch = b.fetchStub;
    const rb = await (await b.ask({})).json();
    assert.deepEqual(rb.report.firms.map((f) => f.slug), ['old']);   // the database function is missing: the report still gets its firms
  } finally { globalThis.fetch = real; }
});

test('a founder who says where they are based gets the firms picked again, and nothing else changes', async () => {
  const real = globalThis.fetch;
  try {
    const w = world({ geo: true }); globalThis.fetch = w.fetchStub;
    w.state.row = { ...w.state.row, status: 'done', result: { v: 2, company: { name: 'Obimy', stage: 'Seed', sector: 'Consumer', country: null }, scores: { deck: 5 }, verdict: 'Fix 1 thing first.', reds: [{ n: 4 }], firms: [{ slug: 'old' }], then: [] } };
    const r = await (await w.ask({ country: 'ua' })).json();
    assert.equal(w.state.geoArgs.p_country, 'UA');
    assert.deepEqual(r.report.firms.map((f) => f.slug), ['ta']); assert.equal(r.report.company.country, 'UA'); assert.equal(r.report.verdict, 'Fix 1 thing first.');
    assert.equal(w.state.row.result.company.country_from, 'founder');          // saved
    assert.ok(!w.calls.some((c) => c.includes('anthropic')));                    // the deck is not read again
    w.state.row.result.research = { v: 2 };
    const again = await (await w.ask({ country: 'us' })).json();
    assert.equal(again.report.company.country, 'UA');                           // once the research is made the firms stay
  } finally { globalThis.fetch = real; }
});

test('a report costs 10 credits: checked before the model, taken after, and a refusal costs nothing', async () => {
  const real = globalThis.fetch;
  try {
    const w = world({ geo: true }); globalThis.fetch = w.fetchStub;
    const r = await (await w.ask({})).json();
    assert.deepEqual(w.state.gate, { p_kind: 'report' });                                   // asked before the deck is read
    assert.deepEqual(w.state.charged, { p_report: '11111111-1111-1111-1111-111111111111', p_kind: 'report' });
    assert.ok(w.calls.findIndex((c) => c.includes('ready_credits_ok')) < w.calls.findIndex((c) => c.includes('anthropic')));
    assert.ok(w.calls.findIndex((c) => c.includes('anthropic')) < w.calls.findIndex((c) => c.includes('ready_charge')));
    assert.ok(r.report && w.state.row.status === 'done');

    const poor = world({ geo: true, credits: 'out' }); globalThis.fetch = poor.fetchStub;
    const res = await poor.ask({});
    assert.equal(res.status, 402); assert.deepEqual(await res.json(), { error: 'out_of_credits', need: 10, left: 4 });
    assert.ok(!poor.calls.some((c) => c.includes('anthropic') || c.includes('ready_charge')));   // the model is not asked, nothing taken
    assert.equal(poor.state.row.status, 'new');

    const cap = world({ geo: true, credits: 'limit' }); globalThis.fetch = cap.fetchStub;
    const rc = await cap.ask({}); assert.equal(rc.status, 429); assert.equal((await rc.json()).error, 'daily_limit');

    const late = world({ geo: true, charge: 'out' }); globalThis.fetch = late.fetchStub;      // credits gone while the report was made
    const rl = await late.ask({});
    assert.equal(rl.status, 402); assert.equal((await rl.json()).error, 'out_of_credits');
    assert.equal(late.state.row.status, 'failed'); assert.ok(!late.state.row.result);          // not delivered, not saved as done

    const done = world({ geo: true }); done.state.row = { ...done.state.row, status: 'done', result: { v: 2, company: {}, firms: [] } }; globalThis.fetch = done.fetchStub;
    await done.ask({});
    assert.ok(!done.calls.some((c) => c.includes('ready_credits_ok') || c.includes('ready_charge'))); // reopening a finished report is free
  } finally { globalThis.fetch = real; }
});
