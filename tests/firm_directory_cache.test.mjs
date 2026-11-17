// Investors directory loads one page at a time from firm_directory_page_v2.
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
    classList: {
      _s: new Set(),
      add(name) { this._s.add(name); },
      remove(name) { this._s.delete(name); },
      contains(name) { return this._s.has(name); },
    },
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

function boot(fetchImpl, regret, extra) {
  extra = extra || {};
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
    URLSearchParams,
    addEventListener() {},
    innerWidth: 1280,
    location: extra.location || { search: '', pathname: '/investors/' },
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
  sandbox.window.location = sandbox.location;
  sandbox.window.URLSearchParams = URLSearchParams;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(new URL('../launch/js/dates.js', import.meta.url), 'utf8'), sandbox, { filename: 'dates.js' });
  sandbox.RegretDate = sandbox.window.RegretDate;
  sandbox.RegretActivity = sandbox.window.RegretActivity;
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
  assert.equal(calls[0].url, 'https://db.test/rest/v1/rpc/firm_directory_page_v2');
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

test('investments column shows deals after industries and sorts like latest deal', async () => {
  const calls = [];
  const { els } = boot((url, opts) => {
    calls.push(JSON.parse(opts.body));
    return Promise.resolve(jsonResponse(200, page([
      { slug: 'a16z', name: 'Andreessen Horowitz', industries: ['AI agents', 'Fintech', 'Bio'], deals: 128, latest_company: 'OpenAI', latest_round: 'Series C', latest_deal_date: '2024-03-01', added: '2024-01-02' },
      { slug: 'zero', name: 'Zero Deals', industries: ['Health'], deals: 0, added: '2024-01-03' },
      { slug: 'nil', name: 'Missing Deals', industries: ['Climate & Energy'], added: '2024-01-04' },
    ], 3, null)));
  }, { url: 'https://db.test', key: 'anon-key', copy: { site: { pages: { investors: { col_investments: 'Investments' } } } } });
  await flush();
  const html = els['firms-list'].innerHTML;
  assert.match(html, /data-sort="deals"[^>]*>Investments/);
  assert.equal(calls[0].p_sort, 'newest');
  els['firms-list'].listeners.click[0]({
    preventDefault() {},
    target: {
      closest(sel) {
        if (sel === '.frow.h [data-sort]') return { getAttribute() { return 'deals'; } };
        return null;
      },
    },
  });
  await flush();
  assert.equal(calls[1].p_sort, 'deals');
  assert.equal(calls[1].p_asc, false);
  els['firms-list'].listeners.click[0]({
    preventDefault() {},
    target: {
      closest(sel) {
        if (sel === '.frow.h [data-sort]') return { getAttribute() { return 'deals'; } };
        return null;
      },
    },
  });
  await flush();
  assert.equal(calls[2].p_sort, 'deals');
  assert.equal(calls[2].p_asc, true);
  const a16z = html.slice(html.indexOf('Andreessen Horowitz'));
  const finds = a16z.indexOf('class="finds"');
  const finv = a16z.indexOf('class="finv">128');
  const fdeal = a16z.indexOf('class="fdeal"');
  assert.ok(finds > -1 && finv > finds && fdeal > finv);
  assert.match(a16z, /class="finv">128<\/span><span class="fact"><\/span><span class="fdeal">/);
  assert.equal((html.match(/class="finv"><\/span>/g) || []).length, 2);
});

test('activity header sorts like latest deal, active group first', async () => {
  const calls = [];
  const { els } = boot((url, opts) => {
    calls.push(JSON.parse(opts.body));
    return Promise.resolve(jsonResponse(200, page([
      { slug: 'new', name: 'Unchecked', deals: 0, deals_this_year: 0 },
      { slug: 'low', name: 'Low', deals: 4, deals_this_year: 1 },
      { slug: 'on', name: 'Busy', deals: 9, deals_this_year: 4 },
      { slug: 'off', name: 'Quiet', deals: 6, deals_this_year: 0 },
    ], 4, null)));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  assert.match(els['firms-list'].innerHTML, /data-sort="activity"[^>]*>Activity/);
  function click() {
    els['firms-list'].listeners.click[0]({
      preventDefault() {},
      target: { closest(sel) { return sel === '.frow.h [data-sort]' ? { getAttribute() { return 'activity'; } } : null; } },
    });
  }
  click();
  await flush();
  assert.equal(calls[1].p_sort, 'activity');
  assert.equal(calls[1].p_asc, false);
  click();
  await flush();
  assert.equal(calls[2].p_asc, true);
});

test('undated startups or finished research with nothing in the window are Not active', async () => {
  const { els } = boot(() => Promise.resolve(jsonResponse(200, page([
    { slug: 'sfc-capital', name: 'SFC Capital', deals: 0, deals_this_year: 0, investments: 440, researched: true },
    { slug: 'done', name: 'Research Done', deals: 0, deals_this_year: 0, investments: 0, researched: true },
    { slug: 'po', name: 'Portfolio Only', deals: 0, deals_this_year: 0, investments: 12, researched: false },
    { slug: 'new', name: 'Unchecked', deals: 0, deals_this_year: 0, investments: 0, researched: false },
    { slug: 'on', name: 'Busy', deals: 9, deals_this_year: 4, investments: 20, researched: true },
  ], 5, null))), { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  const html = els['firms-list'].innerHTML;
  function rowOf(name) {
    const start = html.indexOf(name);
    const next = html.indexOf('<a class="frow"', start);
    return html.slice(start, next === -1 ? undefined : next);
  }
  for (const name of ['SFC Capital', 'Research Done', 'Portfolio Only']) {
    assert.match(rowOf(name), /act-off">Not active/);
    assert.doesNotMatch(rowOf(name), /act-new">Not checked yet/);
  }
  assert.match(rowOf('Unchecked'), /act-new">Not checked yet/);
  assert.doesNotMatch(rowOf('Unchecked'), /act-off">Not active/);
  assert.match(rowOf('Busy'), /act-on">Active/);
});

test('activity label follows deals this year and stays blank without that field', async () => {
  const { els } = boot((url, opts) => {
    return Promise.resolve(jsonResponse(200, page([
      { slug: 'on', name: 'Active Firm', deals: 10, deals_this_year: 4 },
      { slug: 'low', name: 'Low Firm', deals: 6, deals_this_year: 2 },
      { slug: 'off', name: 'Quiet Firm', deals: 5, deals_this_year: 0 },
      { slug: 'new', name: 'Unchecked Firm', deals: 0, deals_this_year: 0 },
      { slug: 'old', name: 'Missing Field', deals: 3 },
    ], 5, null)));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  const html = els['firms-list'].innerHTML;
  assert.match(html, /act-on">Active</);
  assert.match(html, /act-low">Low activity</);
  assert.match(html, /act-off">Not active</);
  assert.match(html, /act-new">Not checked yet</);
  const missing = html.slice(html.indexOf('Missing Field'));
  assert.match(missing, /class="fact"><\/span>/);
  assert.equal(els['firms-list'].classList.contains('has-activity'), true);
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

test('show all is only offered when a group has more options than the five on screen', async () => {
  const { els } = boot(() => Promise.resolve(jsonResponse(200, page(
    [{ slug: 'a16z', name: 'Andreessen Horowitz', deals: 4, deals_this_year: 4 }],
    1,
    {
      region: [],
      industry: ['AI agents', 'Bio', 'Climate & Energy', 'Consumer', 'Crypto', 'Fintech'].map((name, i) => ({ value: name.toLowerCase(), label: name, count: 6 - i })),
      stage: ['Seed', 'Series A', 'Series B'].map((name) => ({ value: name.toLowerCase(), label: name, count: 1 })),
      status: [
        { value: '3', count: 10 },
        { value: '2', count: 4 },
        { value: '1', count: 7 },
        { value: '0', count: 2 },
        { value: 'Active', count: 999 },
      ],
    }
  ))), { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  const html = els['facet-groups'].innerHTML;
  assert.doesNotMatch(html, /Legal records|Recorded information|Deals in last 12 months|Legal \/ regulatory/);
  assert.match(html, /Investor status/);
  assert.match(html, /act-on|Active/);
  const status = html.slice(html.indexOf('id="facet-status"'), html.indexOf('id="facet-status"') + 800);
  assert.match(status, /Active/);
  assert.match(status, /Low activity/);
  assert.match(status, /Not active/);
  assert.match(status, /Not checked yet/);
  assert.equal((status.match(/show-all/g) || []).length, 0);
  assert.match(status, />10</);
  assert.doesNotMatch(status, />999</);
  const industry = html.slice(html.indexOf('id="facet-industry"'), html.indexOf('id="facet-stage"'));
  assert.match(industry, /Show all \(6\)/);
  const stage = html.slice(html.indexOf('id="facet-stage"'), html.indexOf('id="facet-status"'));
  assert.equal((stage.match(/show-all/g) || []).length, 0);
  const region = html.slice(html.indexOf('id="facet-region"'), html.indexOf('id="facet-industry"'));
  assert.match(region, /Show all \(7\)/);
});

test('an activity status filters with that rank and old filter urls are ignored', async () => {
  const calls = [];
  const { els } = boot((url, opts) => {
    calls.push(JSON.parse(opts.body));
    return Promise.resolve(jsonResponse(200, page(
      [{ slug: 'a16z', name: 'Andreessen Horowitz', deals: 4, deals_this_year: 4 }],
      1,
      null
    )));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} }, {
    location: { search: '?legal=has&info=deals&status=Active&p_status=Active', pathname: '/investors/' },
  });
  await flush();
  assert.deepEqual(calls[0].p_status, []);
  assert.deepEqual(calls[0].p_legal, []);
  assert.deepEqual(calls[0].p_info, []);
  assert.match(els['firms-list'].innerHTML, /Andreessen Horowitz/);
  const input = {
    checked: true,
    closest(sel) {
      if (sel === 'input[type="checkbox"]') return input;
      if (sel === 'label') return { getAttribute(name) { return name === 'data-facet' ? 'status' : '3'; } };
      return null;
    },
  };
  els['facet-groups'].listeners.change[0]({ target: input });
  await flush();
  assert.deepEqual(calls[1].p_status, ['3']);
  assert.deepEqual(calls[1].p_legal, []);
  assert.deepEqual(calls[1].p_info, []);
});

test('a local list filters with the same activity labels as the column', async () => {
  const firms = [
    { slug: 'on', name: 'Busy', deals: 9, deals_this_year: 4, country: 'US' },
    { slug: 'low', name: 'Low', deals: 4, deals_this_year: 1, country: 'US' },
    { slug: 'off', name: 'Quiet', deals: 6, deals_this_year: 0, country: 'US' },
    { slug: 'new', name: 'Unchecked', deals: 0, deals_this_year: 0, country: 'US' },
    { slug: 'blank', name: 'Missing', deals: 3, country: 'US' },
  ];
  const { els } = boot(() => Promise.resolve(jsonResponse(200, { firms })), { copy: {} });
  await flush();
  const html = els['firms-list'].innerHTML;
  assert.match(html, /act-on">Active/);
  assert.match(html, /act-low">Low activity/);
  assert.match(html, /act-off">Not active/);
  assert.match(html, /act-new">Not checked yet/);
  const missing = html.slice(html.indexOf('Missing'));
  assert.match(missing, /class="fact"><\/span>/);
  const menu = els['facet-groups'].innerHTML;
  assert.match(menu, /Active[\s\S]*?>1</);
  function click(value) {
    const input = {
      checked: true,
      closest(sel) {
        if (sel === 'input[type="checkbox"]') return input;
        if (sel === 'label') return { getAttribute(name) { return name === 'data-facet' ? 'status' : value; } };
        return null;
      },
    };
    els['facet-groups'].listeners.change[0]({ target: input });
  }
  click('3');
  assert.match(els['firms-list'].innerHTML, /Busy/);
  assert.doesNotMatch(els['firms-list'].innerHTML, /Low|Quiet|Unchecked|Missing/);
  click('0');
  const both = els['firms-list'].innerHTML;
  assert.match(both, /Busy/);
  assert.match(both, /Unchecked/);
  assert.doesNotMatch(both, /Missing/);
});

test('the local activity filter uses the same Not active rule as the column', async () => {
  const firms = [
    { slug: 'on', name: 'Busy', deals: 9, deals_this_year: 4, investments: 9, researched: true, country: 'US' },
    { slug: 'po', name: 'Portfolio Only', deals: 0, deals_this_year: 0, investments: 12, researched: false, country: 'US' },
    { slug: 'done', name: 'Research Done', deals: 0, deals_this_year: 0, investments: 0, researched: true, country: 'US' },
    { slug: 'new', name: 'Unchecked', deals: 0, deals_this_year: 0, investments: 0, researched: false, country: 'US' },
  ];
  const { els } = boot(() => Promise.resolve(jsonResponse(200, { firms })), { copy: {} });
  await flush();
  const menu = els['facet-groups'].innerHTML;
  const status = menu.slice(menu.indexOf('id="facet-status"'));
  assert.match(status, /Not active[\s\S]*?>2</);
  assert.match(status, /Not checked yet[\s\S]*?>1</);
  function click(value) {
    const input = {
      checked: true,
      closest(sel) {
        if (sel === 'input[type="checkbox"]') return input;
        if (sel === 'label') return { getAttribute(name) { return name === 'data-facet' ? 'status' : value; } };
        return null;
      },
    };
    els['facet-groups'].listeners.change[0]({ target: input });
  }
  click('1');
  const notActive = els['firms-list'].innerHTML;
  assert.match(notActive, /Portfolio Only/);
  assert.match(notActive, /Research Done/);
  assert.match(notActive, /act-off">Not active/);
  assert.doesNotMatch(notActive, /Unchecked|Busy/);
});

test('the industry show-all popup lists options alphabetically and the sidebar stays by count', async () => {
  const industries = [
    { value: 'zebra', label: 'Zebra', count: 3 },
    { value: 'apple', label: 'apple', count: 4 },
    { value: 'mango', label: 'Mango', count: 2 },
    { value: 'fintech', label: 'fintech', count: 90 },
    { value: 'ai', label: 'AI agents', count: 80 },
    { value: 'bio', label: 'Bio', count: 60 },
    { value: 'climate', label: 'Climate', count: 50 },
    { value: 'consumer', label: 'Consumer', count: 40 },
    { value: 'crypto', label: 'Crypto', count: 10 },
  ];
  const { els } = boot((url, opts) => {
    const body = JSON.parse(opts.body);
    const facets = body.p_offset === 0 && !body.p_industry.length ? {
      region: [
        { value: 'europe', count: 1 },
        { value: 'asia', count: 50 },
        { value: 'latam', count: 40 },
        { value: 'africa', count: 30 },
        { value: 'middle_east', count: 20 },
        { value: 'north_america', count: 10 },
        { value: 'unknown', count: 5 },
      ],
      industry: industries,
      stage: [],
      status: [],
    } : null;
    return Promise.resolve(jsonResponse(200, page(
      [{ slug: 'a16z', name: 'Andreessen Horowitz', added: '2024-01-02' }],
      1,
      facets
    )));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();

  function optionLabels(html) {
    return [...html.matchAll(/class="optlabel"[^>]*>([^<]*)</g)].map((m) => m[1]);
  }
  function pick(facet, value) {
    const input = {
      checked: true,
      closest(sel) {
        if (sel === 'input[type="checkbox"]') return input;
        if (sel === 'label') {
          return { getAttribute(name) { return name === 'data-facet' ? facet : value; } };
        }
        return null;
      },
    };
    els['facet-groups'].listeners.change[0]({ target: input });
  }
  function openShowAll(key) {
    els['facet-groups'].listeners.click[0]({
      target: {
        closest(sel) {
          if (sel === '.show-all') return { getAttribute() { return key; } };
          return null;
        },
      },
    });
  }

  // Selection order is not alphabetical. ASCII would put Mango and Zebra before apple.
  pick('industry', 'zebra');
  pick('industry', 'mango');
  pick('industry', 'apple');
  await flush();

  const menu = els['facet-groups'].innerHTML;
  const sidebar = optionLabels(menu.slice(menu.indexOf('id="facet-industry"'), menu.indexOf('id="facet-stage"')));
  assert.deepEqual(sidebar.slice(0, 5), ['fintech', 'AI agents', 'Bio', 'Climate', 'Consumer']);

  openShowAll('industry');
  const byLabel = (a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' });
  const selected = optionLabels(els['pinned-options'].innerHTML);
  const remaining = optionLabels(els['full-options'].innerHTML);
  assert.deepEqual(selected, ['apple', 'Mango', 'Zebra']);
  assert.deepEqual(selected, ['apple', 'Mango', 'Zebra'].slice().sort(byLabel));
  assert.notDeepEqual(selected, ['Mango', 'Zebra', 'apple']);
  assert.deepEqual(remaining, ['AI agents', 'Bio', 'Climate', 'Consumer', 'Crypto', 'fintech']);
  assert.deepEqual(remaining, remaining.slice().sort(byLabel));
  assert.notDeepEqual(remaining, ['fintech', 'AI agents', 'Bio', 'Climate', 'Consumer', 'Crypto']);

  const menuAfter = els['facet-groups'].innerHTML;
  const sidebarAfter = optionLabels(menuAfter.slice(menuAfter.indexOf('id="facet-industry"'), menuAfter.indexOf('id="facet-stage"')));
  assert.deepEqual(sidebarAfter.slice(0, 5), ['fintech', 'AI agents', 'Bio', 'Climate', 'Consumer']);

  openShowAll('region');
  const regions = optionLabels(els['full-options'].innerHTML);
  assert.deepEqual(regions, ['Asia', 'LatAm', 'Africa', 'Middle East', 'US / North America', 'Not disclosed', 'Europe']);
  assert.equal(els['pinned-options'].innerHTML, '');
});

test('the show-all popup keeps its footer inside the viewport', () => {
  const css = fs.readFileSync(new URL('../launch/style.css', import.meta.url), 'utf8');
  assert.match(css, /\.facet-panel-box\{[^}]*max-height:calc\(100dvh - 16px\)/);
  assert.match(css, /\.facet-panel-box\{[^}]*grid-template-rows:[^}]*minmax\(0,344px\)/);
  assert.match(css, /\.panel-bottom\{[^}]*position:sticky;bottom:0/);
  assert.doesNotMatch(css, /\.facet-panel\{[^}]*overflow:auto/);
  const page = fs.readFileSync(new URL('../launch/pages/firms.py', import.meta.url), 'utf8');
  assert.match(page, /facet-panel-box/);
  assert.match(page, /id="panel-apply"/);
});
