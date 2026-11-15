// Investors directory loads one page at a time from firm_directory_page.
// node --test tests/firm_directory_cache.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const src = fs.readFileSync(new URL('../launch/js/firms.js', import.meta.url), 'utf8');

function el() {
  return {
    innerHTML: '',
    hidden: true,
    style: {},
    value: '',
    textContent: '',
    classList: { add() {}, remove() {}, contains() { return false; } },
    attrs: {},
    listeners: {},
    getAttribute(name) { return this.attrs[name] || ''; },
    setAttribute(name, value) { this.attrs[name] = String(value); },
    addEventListener(type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); },
    querySelector() { return null; },
    closest() { return null; },
    contains() { return false; },
    insertAdjacentHTML(_pos, html) { this.innerHTML += html; },
  };
}

function boot(fetchImpl, regret) {
  const els = {};
  let observer = null;
  function IntersectionObserver(cb) {
    observer = cb;
    this.observe = function () {};
    this.disconnect = function () {};
  }
  const sandbox = {
    console,
    setTimeout,
    clearTimeout,
    addEventListener() {},
    innerWidth: 1280,
    document: {
      addEventListener() {},
      querySelector() { return null; },
      getElementById(id) {
        if (!els[id]) els[id] = el();
        return els[id];
      },
    },
    fetch: fetchImpl,
    window: {
      REGRET: regret,
      REGRET_ROOT: '/',
      addEventListener() {},
      innerWidth: 1280,
      innerHeight: 800,
      IntersectionObserver,
    },
  };
  sandbox.window.window = sandbox.window;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(src, sandbox, { filename: 'firms.js' });
  return { els, intersect() { if (observer) observer([{ isIntersecting: true }]); } };
}

function jsonResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json() { return Promise.resolve(body); },
  };
}

async function flush() {
  for (let i = 0; i < 8; i++) await new Promise((resolve) => setTimeout(resolve, 0));
}

function page(rows, total, facets) {
  return { rows, total, facets: facets === undefined ? null : facets };
}

function many(n, name, slug) {
  return Array.from({ length: n }, (_, i) => ({
    slug: slug + (i ? '-' + i : ''),
    name: i ? name + ' ' + i : name,
    added: '2024-01-02',
  }));
}

test('the first request is 100 firms, newest first, and renders that page', async () => {
  const calls = [];
  const { els } = boot((url, opts) => {
    calls.push({ url: String(url), body: JSON.parse(opts.body) });
    return Promise.resolve(jsonResponse(200, page(
      many(100, 'Andreessen Horowitz', 'a16z'),
      150,
      { region: [{ value: 'europe', count: 4 }], industry: [], stage: [], legal: [], info: [], status: [] }
    )));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://db.test/rest/v1/rpc/firm_directory_page');
  assert.equal(calls[0].body.p_limit, 100);
  assert.equal(calls[0].body.p_offset, 0);
  assert.equal(calls[0].body.p_sort, 'newest');
  assert.equal(calls[0].body.p_asc, false);
  assert.deepEqual(calls[0].body.p_search, []);
  assert.match(els['firms-list'].innerHTML, /Andreessen Horowitz/);
  assert.equal(els['firms-none'].hidden, true);
  assert.equal(els['firms-more'].hidden, true);
  assert.match(els['facet-groups'].innerHTML, /Europe/);
  assert.match(els['facet-groups'].innerHTML, />4</);
});

test('scrolling near the bottom loads the next 100 and keeps the first rows', async () => {
  const calls = [];
  const { els, intersect } = boot((url, opts) => {
    const body = JSON.parse(opts.body);
    calls.push(body);
    const rows = body.p_offset === 0
      ? many(100, 'Andreessen Horowitz', 'a16z')
      : [{ slug: 'sequoia', name: 'Sequoia', added: '2024-03-03' }];
    return Promise.resolve(jsonResponse(200, page(rows, 150, null)));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  intersect();
  await flush();
  assert.equal(calls.length, 2);
  assert.equal(calls[1].p_offset, 100);
  assert.equal(calls[1].p_limit, 100);
  assert.match(els['firms-list'].innerHTML, /Andreessen Horowitz/);
  assert.match(els['firms-list'].innerHTML, /Sequoia/);
});

test('the last page shows the end of the list and does not ask for another', async () => {
  const calls = [];
  const { els, intersect } = boot((url, opts) => {
    calls.push(JSON.parse(opts.body));
    return Promise.resolve(jsonResponse(200, page(
      [{ slug: 'yc', name: 'Y Combinator', added: '2024-02-02' }],
      1,
      null
    )));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  intersect();
  await flush();
  assert.equal(calls.length, 1);
  assert.equal(els['firms-more'].hidden, false);
  assert.equal(els['firms-more'].textContent, 'End of the list');
  assert.match(els['firms-list'].innerHTML, /Y Combinator/);
});

test('a filter change asks the server again from the first page', async () => {
  const calls = [];
  const { els } = boot((url, opts) => {
    calls.push(JSON.parse(opts.body));
    return Promise.resolve(jsonResponse(200, page(
      [{ slug: 'a16z', name: 'Andreessen Horowitz', added: '2024-01-02' }],
      1,
      null
    )));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  const input = {
    checked: true,
    closest(sel) {
      if (sel === 'input[type="checkbox"]') return input;
      if (sel === 'label') return { getAttribute(name) { return name === 'data-facet' ? 'region' : 'europe'; } };
      return null;
    },
  };
  els['facet-groups'].listeners.change[0]({ target: input });
  await flush();
  assert.equal(calls.length, 2);
  assert.equal(calls[1].p_offset, 0);
  assert.deepEqual(calls[1].p_region, ['europe']);
});

test('typing a search waits, then asks the server from the first page', async () => {
  const calls = [];
  const { els } = boot((url, opts) => {
    calls.push(JSON.parse(opts.body));
    return Promise.resolve(jsonResponse(200, page([], 0, null)));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  const q = els['firms-q'];
  q.value = 'sequoia';
  q.listeners.input[0]();
  await flush();
  assert.equal(calls.length, 1);
  await new Promise((resolve) => setTimeout(resolve, 300));
  assert.equal(calls.length, 2);
  assert.equal(calls[1].p_offset, 0);
  assert.deepEqual(calls[1].p_search, ['sequoia']);
  assert.equal(els['firms-none'].hidden, false);
});

test('sorting by name asks the server and starts ascending', async () => {
  const calls = [];
  const { els } = boot((url, opts) => {
    calls.push(JSON.parse(opts.body));
    return Promise.resolve(jsonResponse(200, page(
      [{ slug: 'a16z', name: 'Andreessen Horowitz', added: '2024-01-02' }],
      1,
      null
    )));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  els['firms-list'].listeners.click[0]({
    preventDefault() {},
    target: {
      closest(sel) {
        if (sel === '.frow.h [data-sort]') return { getAttribute() { return 'name'; } };
        return null;
      },
    },
  });
  await flush();
  assert.equal(calls[1].p_sort, 'name');
  assert.equal(calls[1].p_asc, true);
  assert.equal(calls[1].p_offset, 0);
});

test('no Supabase config still reads firms.json', async () => {
  const calls = [];
  boot((url) => {
    calls.push(String(url));
    return Promise.resolve(jsonResponse(200, { firms: [] }));
  }, { copy: {} });
  await flush();
  assert.deepEqual(calls, ['/firms.json']);
});
