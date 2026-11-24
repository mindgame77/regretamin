// node --test launch/edge/card/card.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { cardTree, nameSize, day, SIGNALS } from './card.mjs';
import { COLORS, SUB_PARENT, sectorColor } from './sectors.mjs';
import { slugOf, cardData, drawCard, shareCard, FALLBACK } from './share.mjs';

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const read = (p) => fs.readFileSync(here(p));
const wasm = { yoga: read('./yoga.wasm'), resvg: read('./resvg.wasm') };
const fontList = [['Geist', 400, 'Geist-Regular.ttf'], ['Geist', 600, 'Geist-SemiBold.ttf'], ['Geist Mono', 400, 'GeistMono-Regular.ttf']]
  .map(([name, weight, f]) => ({ name, weight, style: 'normal', data: read('../../assets/fonts/' + f) }));
const A16Z = { name: 'Andreessen Horowitz', hq: 'Menlo Park, CA', status: 'Active', last_deal: '2026-11-21', deals_year: 128, deals_all: 254,
  signals: ['up', 'top', 'chain'], sectors: ['AI models', 'AI infrastructure', 'Biotech'] };

test('sector colours and parents are the ones the pages use', () => {
  const map = fs.readFileSync(here('../../js/map.js'), 'utf8'), co = fs.readFileSync(here('../../js/company.js'), 'utf8');
  const colors = Function('return ' + /COLORS = (\{[^}]*\})/.exec(map)[1])();
  assert.deepEqual(COLORS, colors);
  const parents = Function('return ' + /const SUB_PARENT = (\{[^}]*\})/.exec(co)[1])();
  assert.deepEqual(SUB_PARENT, parents);
  assert.equal(sectorColor('Biotech'), COLORS.Bio);
  assert.equal(sectorColor('Nothing we know'), COLORS.Other);
});

test('signal words are the ones on the firm page', () => {
  const co = fs.readFileSync(here('../../js/company.js'), 'utf8');
  for (const [code, text] of SIGNALS) assert.ok(co.includes(`['${code}', `) && co.includes(`'${text}']`), code);
});

test('the address names one firm and nothing else', () => {
  assert.equal(slugOf('a16z.png'), 'a16z');
  assert.equal(slugOf('founders-fund.png'), 'founders-fund');
  for (const bad of ['a16z', 'a16z.jpg', '../x.png', 'A16Z.png', '.png', 'a b.png', '']) assert.equal(slugOf(bad), null, bad);
});

test('a row becomes card data; a missing firm becomes nothing', () => {
  const d = cardData(A16Z);
  assert.equal(d.sectors.length, 3);
  assert.equal(d.sectors[1].color, COLORS['AI models']);
  assert.equal(cardData(null), null);
  assert.equal(cardData({}), null);
  assert.equal(day('2026-11-21'), 'Nov 21, 2026');
  assert.ok(nameSize('Tokyo University of Science Innovation Capital') < nameSize('Sequoia'));
});

test('a firm with no deals shows no deal numbers', () => {
  const text = JSON.stringify(cardTree(cardData({ name: 'Quiet Capital', hq: 'Austin, TX', status: 'Not checked yet' })));
  assert.ok(!text.includes('deals this year'));
  assert.ok(text.includes('Quiet Capital'));
});

test('the card is drawn as a 1200x630 PNG', async () => {
  const png = await drawCard(cardData(A16Z), { wasm, fontList });
  assert.deepEqual([...png.slice(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
  const view = new DataView(png.buffer, png.byteOffset);
  assert.equal(view.getUint32(16), 1200);
  assert.equal(view.getUint32(20), 630);
  assert.ok(png.length > 20000);
});

test('the function answers with the card, or sends to the general picture when it cannot', async () => {
  const assets = { fetch: async (u) => new Response(read('../..' + new URL(u).pathname)) };
  const env = { SUPABASE_URL: 'https://db.test', SUPABASE_ANON_KEY: 'k' };
  const call = (param, reply) => shareCard({ request: new Request('https://regretamin.com/share/vc/' + param), env, assets, param, wasm, fetchImpl: async () => reply });
  const ok = await call('a16z.png', new Response(JSON.stringify(A16Z)));
  assert.equal(ok.status, 200);
  assert.equal(ok.headers.get('content-type'), 'image/png');
  const none = await call('nobody.png', new Response('null'));
  assert.equal(none.status, 302);
  assert.ok(none.headers.get('location').endsWith(FALLBACK));
  const down = await call('a16z.png', new Response('x', { status: 500 }));
  assert.equal(down.status, 302);
  assert.equal((await call('a16z.jpg', new Response('null'))).status, 404);
});
