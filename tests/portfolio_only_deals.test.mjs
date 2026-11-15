// Undated portfolio companies list under Recent deals and in Sectors (all time).
// They stay out of Activity labels, deals this year, Rounds and Announced.
// node --test tests/portfolio_only_deals.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const js = read('launch/js/company.js');

function el() {
  const node = {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    attrs: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute(k, v) { node.attrs[k] = v; },
    getAttribute(k) { return node.attrs[k]; },
    remove() {},
    insertAdjacentElement() {},
  };
  return node;
}
function mainEl() {
  const kids = {};
  const main = el();
  main.querySelector = (sel) => kids[sel] || null;
  main.querySelectorAll = () => [];
  main.set = (sel, child) => { kids[sel] = child; return child; };
  return main;
}
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement: () => el(), body: { appendChild() {} } },
  console, URL, Intl, Date,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(js, sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

const dated = [
  { company: 'Old Co', date: '2022-01-15', sector: 'Fintech', round: 'Seed', amount: 4000000, currency: 'USD', url: 'https://techcrunch.com/old', website_url: 'https://old.example' },
];
const portfolio = [
  { company: 'Attribute', portfolio_only: true, sector: 'Developer tools', industry_name: 'Cloud & Data', url: 'https://www.menschvc.com/our-portfolio', website_url: 'https://attrb.io' },
  { company: 'Bare Co', date: null, amount: null, url: 'https://www.menschvc.com/our-portfolio', website_url: 'https://bare.example' },
];

function paint(extra) {
  const main = mainEl();
  const actw = main.set('.actw', el());
  const pmain = main.set('.pmain', el());
  render(main, {
    open: true, checks: [], sections: [],
    firm: { name: 'Mensch Capital Partners', slug: 'mensch-capital-partners' },
    activity: {
      lazy: false,
      deals: dated,
      portfolio_only: portfolio,
      counts: { deals: dated.length, reviews: 0 },
      deals_12m: 0,
      ...extra,
    },
  });
  return { html: pmain.innerHTML, act: actw.innerHTML };
}

test('undated portfolio rows sit below dated deals, with dashes and the source link', () => {
  const { html } = paint();
  const table = html.slice(html.indexOf('class="dtable"'), html.indexOf('class="dcards"'));
  assert.ok(table.indexOf('Old Co') < table.indexOf('Also in the portfolio'));
  assert.ok(table.indexOf('Also in the portfolio') < table.indexOf('Attribute'));
  assert.ok(table.indexOf('Attribute') < table.indexOf('Bare Co'));
  assert.match(table, /Seed · \$4M/);
  assert.match(table, /Jan 15, 2022/);
  assert.match(table, /href="https:\/\/www\.menschvc\.com\/our-portfolio"[^>]*>menschvc\.com/);
  assert.match(table, /class="arty"[^>]*>Cloud &amp; Data</);
  assert.doesNotMatch(table, /Bare Co[\s\S]{0,180}class="arty"/);
  assert.equal((table.match(/class="nd">—<\/span>/g) || []).length, 5);
  assert.doesNotMatch(table, /Attribute[\s\S]{0,200}Seed|Attribute[\s\S]{0,200}Jan /);
});

test('portfolio-only rows do not change the Activity label or deals this year', () => {
  const { html, act } = paint();
  assert.match(act, /Not active/);
  assert.doesNotMatch(act, /Active(?! )/);
  assert.doesNotMatch(act, />20<|>2</);
  assert.match(js, /rule\.countThisYear\(allDeals\), allDeals\.length\)/);
  assert.match(js, /k === 's' \? sectorsDs/);
  assert.match(js, /CHART_PERIOD === 'all' \? allTime\.concat\(port\) : ranged/);
  assert.match(js, /k === 'd' \? allTime : k === 's'/);
  assert.match(js, /some\(isPortfolioOnly\) \? 'startups' : 'deals'/);
  assert.doesNotMatch(js, /periodDeals\(all\.concat\(port\)/);
  assert.ok(html.includes('id="sectors"'));
  assert.ok(html.includes('id="rounds"'));
  assert.ok(html.includes('id="announced"'));
});

test('a firm with only undated portfolio companies still gets Recent deals and Sectors, not Rounds', () => {
  const main = mainEl();
  const actw = main.set('.actw', el());
  const pmain = main.set('.pmain', el());
  render(main, {
    open: true, checks: [], sections: [],
    firm: { name: 'Example', slug: 'example' },
    activity: {
      lazy: false,
      deals: [],
      portfolio_only: portfolio,
      counts: { deals: 0, reviews: 0 },
      deals_12m: 0,
    },
  });
  assert.match(pmain.innerHTML, /id="deals"/);
  assert.match(pmain.innerHTML, /Attribute/);
  assert.match(pmain.innerHTML, /id="sectors"/);
  assert.doesNotMatch(pmain.innerHTML, /id="rounds"|id="announced"/);
  assert.doesNotMatch(actw.innerHTML, /<b>2<\/b>|<b>20<\/b>/);
});

test('a bare portfolio row is hidden when that startup already has a dated deal', () => {
  const main = mainEl();
  main.set('.actw', el());
  const pmain = main.set('.pmain', el());
  render(main, {
    open: true, checks: [], sections: [],
    firm: { name: 'Example', slug: 'example' },
    activity: {
      lazy: false,
      deals: [
        { company: 'Ledgy', date: '2024-03-01', sector: 'Fintech', round: 'Series A', amount: 20000000, currency: 'USD', website_url: 'https://ledgy.com' },
      ],
      portfolio_only: [
        { company: 'Ledgy', portfolio_only: true, url: 'https://example.com/portfolio', website_url: 'https://ledgy.com' },
        { company: 'Attribute', portfolio_only: true, sector: 'Developer tools', industry_name: 'Cloud & Data', url: 'https://www.menschvc.com/our-portfolio', website_url: 'https://attrb.io' },
      ],
      counts: { deals: 1, reviews: 0 },
      deals_12m: 0,
    },
  });
  const html = pmain.innerHTML;
  const table = html.slice(html.indexOf('class="dtable"'), html.indexOf('class="dcards"'));
  assert.equal((table.match(/Ledgy/g) || []).length, 1);
  assert.match(table, /Series A/);
  assert.match(table, /Attribute/);
  assert.ok(table.indexOf('Also in the portfolio') < table.indexOf('Attribute'));
});
