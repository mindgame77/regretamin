import test from 'node:test';
import assert from 'node:assert/strict';
import { isPresentation, toPdf } from './convert.js';

const ok = (body, status = 200) => async () => ({ ok: status < 400, status, json: async () => body, text: async () => JSON.stringify(body) });

test('which stored decks are presentations', () => {
  for (const p of ['u/a-1-deck.pptx', 'u/a-1-deck.PPT', 'u/x.ppsx', 'u/x.key', 'u/x.potx']) assert.equal(isPresentation(p), true, p);
  for (const p of ['u/a-1-deck.pdf', 'u/key.pdf', 'u/keynote', '', null, undefined]) assert.equal(isPresentation(p), false, String(p));
});

test('without the key nothing is sent and the page can say so', async () => {
  let called = false;
  const r = await toPdf({}, 'https://x/deck', 'u/a.pptx', async () => { called = true; });
  assert.deepEqual(r, { error: 'convert_not_configured' });
  assert.equal(called, false);
});

test('one job: import the link, convert to pdf, give back the pdf link; the key stays in the header', async () => {
  let seen = null;
  const fetchFn = async (url, opts) => { seen = { url, opts }; return ok({ data: { status: 'finished', tasks: [
    { operation: 'import/url', status: 'finished' }, { operation: 'convert', status: 'finished' },
    { operation: 'export/url', status: 'finished', result: { files: [{ filename: 'deck.pdf', url: 'https://storage.cloudconvert.com/x/deck.pdf' }] } }] } })(); };
  const r = await toPdf({ CLOUDCONVERT_API_KEY: 'secret-key' }, 'https://sb/storage/v1/object/sign/decks/u/a.key?token=t', 'u/a.KEY', fetchFn);
  assert.deepEqual(r, { url: 'https://storage.cloudconvert.com/x/deck.pdf' });
  assert.equal(seen.url, 'https://sync.api.cloudconvert.com/v2/jobs');
  assert.equal(seen.opts.headers.authorization, 'Bearer secret-key');
  const body = JSON.parse(seen.opts.body);
  assert.equal(body.tasks.deck.url, 'https://sb/storage/v1/object/sign/decks/u/a.key?token=t');
  assert.equal(body.tasks.deck.filename, 'deck.key');
  assert.equal(body.tasks.pdf.input_format, 'key');
  assert.equal(body.tasks.pdf.output_format, 'pdf');
  assert.ok(!seen.opts.body.includes('secret-key'));
});

test('a refused file, an error from the service and a broken answer each give a plain error', async () => {
  const bad = await toPdf({ CLOUDCONVERT_API_KEY: 'k' }, 'u', 'a.pptx', ok({ data: { status: 'error', tasks: [{ operation: 'convert', status: 'error', message: 'Password protected' }] } }));
  assert.match(bad.error, /^convert_failed: Password protected/);
  const http = await toPdf({ CLOUDCONVERT_API_KEY: 'k' }, 'u', 'a.pptx', ok({ message: 'Unauthenticated' }, 401));
  assert.match(http.error, /^convert_401/);
  const empty = await toPdf({ CLOUDCONVERT_API_KEY: 'k' }, 'u', 'a.pptx', ok({ data: { status: 'finished', tasks: [] } }));
  assert.match(empty.error, /^convert_failed/);
  const down = await toPdf({ CLOUDCONVERT_API_KEY: 'k' }, 'u', 'a.pptx', async () => { throw new Error('net'); });
  assert.deepEqual(down, { error: 'convert_unreachable' });
});
