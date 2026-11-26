import test from 'node:test';
import assert from 'node:assert/strict';
import { CHECKLIST } from './checklist.js';
import { importance, score, marksOf, assemble, parseModelJson, systemPrompt, FROM_OUR_DATA, sayTo } from './rules.js';

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

test('scores run the other way: 10 is as good as it gets, a red flag is at the bottom', () => {
  assert.equal(score(4, 'red', 'Seed'), 1);                 // no ask
  assert.equal(score(107, 'red', 'Seed'), 2);
  assert.equal(score(0, 'lead', 'Seed'), 10);
  for (const st of ['Pre-seed', 'Seed']) for (const n of [1, 37, 89, 120, 160]) {
    const r = score(n, 'red', st), y = score(n, 'yellow', st), g = score(n, 'good', st);
    assert.ok(r >= 1 && r <= 4 && y >= 4 && y <= 7 && (g === 8 || g === 9) && r <= y && y < g);
  }
  const model = { company: { stage: 'Pre-seed' }, flags: [{ n: 4, level: 'red' }, { n: 125, level: 'yellow' }, { n: 51, level: 'yellow' }],
    strengths: [{ n: 37, what: 'Founders lived the problem', where: 'Slide 2', why: 'x' }, { n: 4, what: 'repeat of a flag' }, { n: 207, what: 'our data row' }, { n: 56, what: 'One named buyer', where: 'Slide 3' }],
    lead_with: { text: 'A founder sold a company in this field.', where: 'Slide 9' } };
  const a = assemble(model, null);
  assert.deepEqual(a.good.map((g) => g.n), [37, 56]);       // a row that is already a flag, and an our-data row, are dropped
  assert.equal(a.good[0].score, 9);
  assert.ok(a.scores.deck >= 1 && a.scores.deck <= 10 && a.scores.founders >= 8);   // founders: a strength, a long-bios note and the exceptional thing
  assert.equal(assemble({ company: { stage: 'Seed' }, flags: [{ n: 4, level: 'red' }] }, null).scores.founders, null);  // nothing said about the founders
  assert.deepEqual(a.scores, assemble(JSON.parse(JSON.stringify(model)), null).scores);
  assert.match(systemPrompt(), /"strengths":\[\{"n":0/);
});

test('a firm gets a mark only for what is great about it', () => {
  assert.deepEqual(marksOf({ sector_pct: 48, stage_pct: 52, n90: 3 }), ['Your field is its main field']);
  assert.deepEqual(marksOf({ sector_pct: 16, stage_pct: 84, n90: 5 }), ['Almost only first cheques', 'Investing fast right now']);
  assert.deepEqual(marksOf({ sector_pct: 10, stage_pct: 30, n90: 0 }), []);
  assert.deepEqual(assemble({ company: { stage: 'Seed' } }, { firms: [{ name: 'F', fit: 1, sector_pct: 60, stage_pct: 10, n90: 0 }] }).firms[0].marks, ['Your field is its main field']);
});

test('what is special is rare, comes from the written list, and only ever adds', () => {
  const base = { company: { stage: 'Pre-seed' }, flags: [{ n: 4, level: 'red' }, { n: 51, level: 'yellow' }] };
  const a = assemble({ ...base, special: [{ kind: 'university', what: 'PhD in dairy science at Wageningen', where: 'Slide 9', why: 'x' }, { kind: 'Age', what: 'young' }, { kind: 'University', what: 'again' },
    { kind: 'Exclusive data', what: 'Sensor data from 40 farms', where: 'Slide 5' }, { kind: 'Speed', what: 'Ships weekly' }, { kind: 'Backers', what: 'a fourth' }] }, null);
  assert.deepEqual(a.special.map((x) => x.kind), ['University', 'Exclusive data', 'Speed']);   // unknown kinds and repeats dropped; three at most
  const none = assemble(base, null);
  assert.deepEqual(none.special, []);
  assert.ok(a.scores.deck >= none.scores.deck && a.scores.founders >= none.scores.founders);    // having none costs nothing
  const p = systemPrompt();
  assert.ok(/University \| Did a founder study/.test(p) && /Never guess a founder's age/.test(p));
});
