// node --test launch/edge/card/badge.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { BADGES, LOOKS, badgeOf, slugOk, initials, badgeSvg, drawBadge, badgeResponse } from './badge.mjs';

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const wasm = { resvg: fs.readFileSync(here('./resvg.wasm')) };
const PNG = [0x89, 0x50, 0x4e, 0x47];
const logoBytes = fs.readFileSync(here('../../assets/logos/f-sequoia.png'));

test('a badge address names a signal and a look, nothing else', () => {
  assert.deepEqual(badgeOf('top-round-dark.png'), { signal: 'top', look: 'round-dark' });
  assert.deepEqual(badgeOf('lead-pill.png'), { signal: 'lead', look: 'pill' });
  for (const bad of ['down-pill.png', 'top-square.png', 'top-pill.svg', '../top-pill.png', '']) assert.equal(badgeOf(bad), null);
  assert.ok(slugOk('sequoia') && !slugOk('../etc') && !slugOk('A16Z'));
  assert.equal(initials('Bessemer Venture Partners'), 'BV');
});

test('every badge is one the firm page offers, under the same name, and "Slowing down" has none', () => {
  const co = fs.readFileSync(here('../../js/company.js'), 'utf8');
  for (const [code, b] of Object.entries(BADGES)) assert.ok(co.includes(`['${code}', '${b.title}']`), code);
  assert.deepEqual(Object.keys(BADGES), ['top', 'lead', 'up', 'chain', 'spec', 'fund']);
  assert.equal(badgeOf('down-pill.png'), null);
});

test('every badge draws as a picture with its words as outlines (the renderer loads no fonts)', async () => {
  const logo = 'data:image/png;base64,' + logoBytes.toString('base64');
  for (const signal of Object.keys(BADGES)) for (const look of LOOKS) {
    const svg = badgeSvg({ signal, look, year: 2026, logo, name: 'Sequoia Capital' });
    assert.ok(svg && !svg.includes('<text') && svg.includes('<image'), signal + ' ' + look);
    const png = await drawBadge(svg, { wasm });
    assert.deepEqual([...png.slice(0, 4)], PNG);
    assert.ok(png.length > 6000, `${signal} ${look} is ${png.length} bytes`);
  }
  // a firm without a logo gets its initials
  const svg = badgeSvg({ signal: 'top', look: 'pill', year: 2026, logo: null, name: 'Toba Capital' });
  assert.ok(!svg.includes('<image') && svg.includes('#E2E7E5'));
});

test('a badge is only given for a signal the firm has today', async () => {
  const env = { SUPABASE_URL: 'https://db.example', SUPABASE_ANON_KEY: 'k' };
  const assets = { fetch: async (u) => (String(u).endsWith('/assets/logos/f-sequoia.png') ? new Response(logoBytes, { headers: { 'content-type': 'image/png' } }) : new Response('no', { status: 404 })) };
  const db = (row) => async () => new Response(JSON.stringify(row), { headers: { 'content-type': 'application/json' } });
  const ask = (file, row) => badgeResponse({ request: new Request('https://regretamin.com/badge/sequoia/' + file), env, assets, slug: 'sequoia', file, wasm, fetchImpl: db(row), now: new Date('2026-11-25T00:00:00Z') });
  const yes = await ask('top-round-light.png', { name: 'Sequoia Capital', signals: ['up', 'top'] });
  assert.equal(yes.status, 200); assert.equal(yes.headers.get('content-type'), 'image/png');
  assert.deepEqual([...new Uint8Array(await yes.arrayBuffer()).slice(0, 4)], PNG);
  assert.equal((await ask('lead-pill.png', { name: 'Sequoia Capital', signals: ['up', 'top'] })).status, 404);
  assert.equal((await ask('top-pill.png', null)).status, 404);
  assert.equal((await ask('top-huge.png', { name: 'Sequoia Capital', signals: ['top'] })).status, 404);
});
