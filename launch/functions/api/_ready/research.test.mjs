import test from 'node:test';
import assert from 'node:assert/strict';
import { researchPrompt, researchAsk, normUrl, domainOf, pagesSeen, checkSource, answerText, vetted, buildResearch, askLine } from './research.js';
import { onRequestPost } from '../research.js';

const CONTENT = [
  { type: 'text', text: 'I will search.' },
  { type: 'server_tool_use', id: 's1', name: 'web_search', input: { query: 'cow collar startups' } },
  { type: 'web_search_tool_result', tool_use_id: 's1', content: [
    { type: 'web_search_result', url: 'https://www.news.example/halter-raises-100m/', title: 'Halter raises $100M Series D' },
    { type: 'web_search_result', url: 'https://nofence.no/about', title: 'About Nofence' },
    { type: 'web_search_result', url: 'https://blog.example/why-cowlar-closed', title: 'Why Cowlar closed' }] },
  { type: 'text', text: '{"competitors":[' +
    '{"name":"Halter","website":"https://www.halterhq.com/","what":"Solar collars that fence and track dairy cows","raised":"$100M Series D, 2025","backers":["Bessemer"],"your_move":"Say your collars cost a third as much and need no base station.","source":"https://news.example/halter-raises-100m","strengths":[{"what":"Collars on 300,000 cows in three countries","source":"https://news.example/halter-raises-100m"},{"what":"Invented strength","source":"https://made-up.example/x"}],"news":[{"what":"Raised a $100M Series D in 2025","source":"https://www.news.example/halter-raises-100m/"},{"what":"Bought a rival in 2024","source":"https://made-up.example/halter-buys"}]},' +
    '{"name":"Nofence","website":"nofence.no","what":"Virtual fencing for grazing animals","raised":"","backers":[],"your_move":"","source":"https://nofence.no/press/funding-2024"},' +
    '{"name":"Ghost Co","website":"ghost.example","what":"Invented","raised":"$9M","backers":["Nobody"],"your_move":"","source":"https://made-up.example/ghost"}],' +
    '"tried_before":[{"name":"Cowlar","years":"2016 to 2020","outcome":"shut down","what_happened":"Shut down after its funding ran out.","founders":["A. Founder"],"source":"https://blog.example/why-cowlar-closed"},' +
    '{"name":"Nobody Inc","years":"2010","what_happened":"Unknown.","founders":[],"source":""}]}' }];

test('addresses are compared by page, and a website becomes a bare domain', () => {
  assert.equal(normUrl('https://WWW.News.example/a/b/?utm=1#x'), 'news.example/a/b');
  assert.equal(normUrl('javascript:alert(1)'), '');
  assert.equal(domainOf('https://www.halterhq.com/about'), 'halterhq.com');
  assert.equal(domainOf('nofence.no'), 'nofence.no');
  assert.equal(domainOf('not a site'), '');
});

test('a looked-up row is kept only with a source the search really returned', () => {
  const seen = pagesSeen(CONTENT);
  assert.equal(seen.size, 3);
  assert.equal(checkSource('https://news.example/halter-raises-100m', 'Halter', seen), 'https://www.news.example/halter-raises-100m/');   // same page, written differently
  assert.equal(checkSource('https://nofence.no/press/funding-2024', 'Nofence', seen), 'https://nofence.no/about');   // another page of the same site that names the company
  assert.equal(checkSource('https://nofence.no/press/funding-2024', 'Halter', seen), '');   // same site, but it does not name this company
  assert.equal(checkSource('https://made-up.example/ghost', 'Ghost Co', seen), '');
  const rows = vetted(JSON.parse(answerText(CONTENT)), seen);
  assert.deepEqual(rows.competitors.map((c) => c.name), ['Halter', 'Nofence']);   // the invented one is gone
  assert.deepEqual(rows.tried.map((t) => t.name), ['Cowlar']);                      // the one with no source is gone
  assert.equal(rows.competitors[0].site, 'halterhq.com');
  assert.deepEqual(rows.competitors[0].news, [{ what: 'Raised a $100M Series D in 2025', src: 'https://www.news.example/halter-raises-100m/' }]);   // the news item with an invented page is gone
  assert.equal(rows.tried[0].outcome, 'Shut down');
  assert.deepEqual(rows.competitors[0].strong, [{ what: 'Collars on 300,000 cows in three countries', src: 'https://www.news.example/halter-raises-100m/' }]);
  assert.equal(rows.competitors[0].move, 'Say your collars cost a third as much and need no base station.');
});

test('our data replaces looked-up funding where we hold the company, and firms that hold a competitor are not offered', () => {
  const rows = vetted(JSON.parse(answerText(CONTENT)), pagesSeen(CONTENT));
  const ours = { competitors: [{ asked: 'Halter', name: 'Halter', round: 'Series D', date: '2025-06-01', amount: 100000000, currency: 'USD', backers: [{ slug: 'bessemer-venture-partners', name: 'Bessemer Venture Partners' }], founders: 2, worked_at: ['Rocket Lab'], studied_at: ['Auckland'], built_before: [{ name: 'Farm Co', outcome: 'acquired', acquirer: 'Big Ag' }, { name: 'Other Co', outcome: 'shut_down', acquirer: null }] }],
    skip: [{ slug: 'bessemer-venture-partners', name: 'Bessemer Venture Partners', backed: ['Halter'] }], rounds: { n: 14, p25: 1325000, p50: 1500000, p75: 2012500, p90: 4265000 }, stage: 'Pre-seed', sector_known: true };
  const r = buildResearch(rows, ours, { company: { stage: 'Pre-seed', sector: 'Hardware', ask_usd: 1200000 } }, { at: '2026-11-26T22:00:00Z', searches: 6, model: 'claude-opus-5-5', tokens_in: 1, tokens_out: 2 });
  assert.deepEqual(r.competitors[0].raised, { ours: true, text: '$100M Series D', date: '2025-06-01' });
  assert.equal(r.competitors[0].backers.ours, true);
  assert.equal(r.competitors[1].raised, null);                       // nothing reported, nothing shown
  assert.deepEqual(r.competitors[1].backers, { ours: false, list: [] });
  assert.deepEqual(r.skip.map((s) => s.slug), ['bessemer-venture-partners']);
  assert.ok(!('instead' in r));   // the firms to pitch are step 4 of the report; the research does not repeat them
  assert.equal(r.rounds.n, 14);
  assert.equal(r.rounds.line, 'Your ask is below most rounds like yours. Announced rounds lean large, so the true middle is lower than $1.5M.');
  assert.equal(r.tried[0].src, 'https://blog.example/why-cowlar-closed');
  assert.equal(r.v, 2);
  assert.deepEqual(r.competitors[0].team, ['Founders worked at Rocket Lab', 'Founders studied at Auckland', 'A founder built Farm Co before (acquired by Big Ag)', 'A founder built Other Co before (shut down)']);
  assert.deepEqual(r.competitors[1].team, []);   // a competitor we do not hold: nothing is said about its founders from our side
  assert.deepEqual(r.now, { competitors: '2 companies an investor will compare you with.', firms: '1 firm we list already holds one of them.', tried: '1 company tried this before you.' });
  assert.deepEqual(r.todo, { competitors: 'Put these on your competition slide. Have your answer ready for each one.', firms: 'Take these off your target list. The firms to pitch are in step 4.',
    tried: 'Message one of these founders this week. Ask the three questions.', ask: 'Be ready to defend your number against these rounds.' });
  assert.equal(buildResearch({ competitors: [], tried: [] }, { rounds: ours.rounds }, { company: {} }, {}).todo.ask, 'Add your ask to the deck: the amount and what it pays for.');
});

test('the ask is placed in plain words, never as a forecast, and not at all on thin data', () => {
  const r = { n: 262, p25: 3e6, p50: 5e6, p75: 8.1e6, p90: 15e6 };
  assert.match(askLine(3e6, r), /at the low end of the usual range/);
  assert.match(askLine(7e6, r), /at the high end of the usual range/);
  assert.match(askLine(2e7, r), /above most rounds like yours/);
  assert.equal(askLine(null, r), 'Your deck names no ask, so we cannot place it.');
  assert.equal(askLine(3e6, { ...r, n: 3 }), '');
  assert.equal(buildResearch({ competitors: [], tried: [] }, { rounds: { n: 3 } }, {}, {}).rounds, null);
  for (const t of [3e6, 7e6, 2e7]) assert.ok(!/will|won't|cannot raise|too much|too little/i.test(askLine(t, r)));
});

test('the model is asked for sources and told what never to say', () => {
  const p = researchPrompt();
  assert.ok(/Every row needs a "source"/.test(p) && /Never invent a company, a number, a person or an address/.test(p));
  assert.ok(/Never say the startup will or will not raise money\. Never advise dropping the idea\./.test(p));
  const ask = researchAsk({ company: { name: 'HEFT', one_line: 'Collars for dairy cows', stage: 'Pre-seed', sector: 'Hardware' }, facts: [{ claim: 'Three farms pay monthly' }], competitors_named: ['Halter'] });
  assert.ok(/HEFT/.test(ask) && /Collars for dairy cows/.test(ask) && /Competitors the deck names: Halter/.test(ask) && /Three farms pay monthly/.test(ask));
});

test('the function: only the owner of a finished report, made once, saved on the report', async () => {
  const calls = [];
  let saved = null;
  const report = { v: 2, company: { name: 'HEFT', one_line: 'Collars for dairy cows', stage: 'Pre-seed', sector: 'Hardware', ask_usd: 1200000 }, facts: [], reds: [] };
  const real = globalThis.fetch;
  globalThis.fetch = async (url, opt = {}) => {
    const u = String(url); calls.push(u.replace(/\?.*/, ''));
    const ok = (o) => new Response(JSON.stringify(o), { status: 200, headers: { 'content-type': 'application/json' } });
    if (u.includes('/auth/v1/user')) return opt.headers.authorization === 'Bearer good' ? ok({ id: 'u1' }) : new Response('{}', { status: 401 });
    if (u.includes('/rest/v1/ready_reports') && (opt.method || 'GET') === 'GET') return ok([{ id: 'x', status: 'done', result: saved ? { ...report, research: saved } : report }]);
    if (u.includes('/rest/v1/ready_reports') && opt.method === 'PATCH') { const b = JSON.parse(opt.body); if (b.result) saved = b.result.research; return new Response(null, { status: 204 }); }
    if (u.includes('api.anthropic.com')) {
      const b = JSON.parse(opt.body);
      assert.equal(b.tools[0].type, 'web_search_20250305'); assert.equal(b.tools[0].max_uses, 8); assert.ok(!('temperature' in b));
      if (b.messages.length === 1) return ok({ stop_reason: 'pause_turn', content: CONTENT.slice(0, 3), usage: { input_tokens: 100, output_tokens: 10, server_tool_use: { web_search_requests: 1 } } });
      assert.equal(b.messages[1].role, 'assistant'); assert.equal(b.messages[1].content.length, 3);   // the paused answer goes back unchanged
      return ok({ stop_reason: 'end_turn', content: CONTENT.slice(3), usage: { input_tokens: 200, output_tokens: 300 } });
    }
    if (u.includes('/rpc/v2_ready_research')) { const b = JSON.parse(opt.body); assert.deepEqual(b.p_names, ['Halter', 'Nofence']); assert.deepEqual(b.p_domains, ['halterhq.com', 'nofence.no']); return ok({ competitors: [], skip: [], rounds: { n: 14, p25: 1325000, p50: 1500000, p75: 2012500, p90: 4265000 }, stage: 'Pre-seed', sector_known: true }); }
    throw new Error('unexpected ' + u);
  };
  const ask = (token) => onRequestPost({ env: { SUPABASE_URL: 'https://db.example', SUPABASE_ANON_KEY: 'k', ANTHROPIC_API_KEY: 'k' },
    request: new Request('https://site.example/api/research', { method: 'POST', headers: { authorization: 'Bearer ' + token, 'content-type': 'application/json' }, body: JSON.stringify({ id: '11111111-1111-1111-1111-111111111111' }) }) });
  try {
    assert.equal((await ask('bad')).status, 401);
    const a = await (await ask('good')).json();
    assert.deepEqual(a.research.competitors.map((c) => c.name), ['Halter', 'Nofence']);
    assert.equal(a.research.searches, 1); assert.equal(a.research.tokens_in, 300);
    assert.ok(saved && saved.tried.length === 1);
    const before = calls.filter((c) => c.includes('anthropic')).length;
    const b = await (await ask('good')).json();                                  // asked again: the saved one, no second search
    assert.equal(calls.filter((c) => c.includes('anthropic')).length, before);
    assert.deepEqual(b.research.competitors.map((c) => c.name), ['Halter', 'Nofence']);
  } finally { globalThis.fetch = real; }
});

test('five competitors at most', () => {
  const seen = new Map(Array.from({ length: 8 }, (_, i) => ['site.example/c' + i, { url: 'https://site.example/c' + i, title: 'C' + i }]));
  const rows = vetted({ competitors: Array.from({ length: 8 }, (_, i) => ({ name: 'C' + i, source: 'https://site.example/c' + i })) }, seen);
  assert.equal(rows.competitors.length, 5);
  assert.ok(/5 at most/.test(researchPrompt()));
});
