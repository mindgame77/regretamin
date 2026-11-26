import test from 'node:test';
import assert from 'node:assert/strict';
import { CHECKLIST } from './checklist.js';
import { importance, assemble, parseModelJson, systemPrompt, FROM_OUR_DATA, sayTo } from './rules.js';

test('the checklist holds the 216 questions of the sheet', () => {
  assert.equal(CHECKLIST.length, 216);
  assert.deepEqual(CHECKLIST.map((r) => r[0]), Array.from({ length: 216 }, (_, i) => i + 1));
  assert.equal(CHECKLIST[3][2], 'Is there one clear ask?');
});

test('importance is fixed: red 7 to 10, yellow 3 to 6, and follows the stage', () => {
  assert.equal(importance(4, 'red', 'Seed'), 10);          // no ask: critical
  assert.equal(importance(107, 'red', 'Seed'), 9);         // "we have no competitors": critical
  assert.equal(importance(51, 'red', 'Seed'), 8);          // an ordinary team-slide flag
  assert.ok(importance(120, 'red', 'Seed') > importance(120, 'red', 'Pre-seed') || importance(121, 'red', 'Seed') >= 9); // traction counts more at seed
  for (const r of CHECKLIST) for (const st of ['Pre-seed', 'Seed']) {
    const a = importance(r[0], 'red', st), b = importance(r[0], 'yellow', st);
    assert.ok(a >= 7 && a <= 10 && b >= 3 && b <= 6);
    assert.equal(a, importance(r[0], 'red', st));
  }
});

test('the same answers always give the same report', () => {
  const model = { company: { name: 'Example', stage: 'Seed', sector: 'Fintech', ask_usd: 3000000, slides: 19 },
    flags: [{ n: 89, level: 'red', what: 'Market size is 1% of a huge market', where: 'Slide 6', why: 'x', fix: 'y' }, { n: 4, level: 'red' },
      { n: 125, level: 'yellow', what: 'Cumulative chart' }, { n: 207, level: 'red' }, { n: 9999, level: 'red' }, { n: 4, level: 'red' }, { n: 1, level: 'red' }],
    lead_with: null };
  const a = assemble(model, { firms: [{ name: 'F', fit: 2, stage_pct: 80, sector_pct: 10, n90: 1 }], then: [] });
  assert.deepEqual(a, assemble(JSON.parse(JSON.stringify(model)), { firms: [{ name: 'F', fit: 2, stage_pct: 80, sector_pct: 10, n90: 1 }], then: [] }));
  assert.equal(a.verdict, 'Fix 2 things first.');
  assert.deepEqual(a.reds.map((f) => f.n), [4, 89]);       // most important first; unknown, repeated, our-data and other-stage rows dropped
  assert.equal(a.reds[0].what, 'No amount and no round named');
  assert.equal(a.yellows.length, 1);
  assert.equal(a.firms[0].say, 'Almost only first cheques. Keep the ask at seed size.');
  assert.equal(assemble({ company: { stage: 'Pre-seed' }, flags: [] }, null).verdict, 'Ready to send.');
});

test('the model is not asked what only our data can answer, and its answer is read out of any wrapping', () => {
  const p = systemPrompt();
  assert.ok(FROM_OUR_DATA.size === 9 && !/\n207 \| /.test(p) && /\n4 \| Deck itself \| Is there one clear ask\?/.test(p));
  assert.deepEqual(parseModelJson('Here it is:\n```json\n{"a":1}\n```'), { a: 1 });
  assert.equal(parseModelJson('no json'), null);
  assert.match(sayTo({ fit: 1, stage_pct: 10, sector_pct: 5, n90: 0 }, 'Seed', 'Fintech'), /1 seed deal in your field/);
});
