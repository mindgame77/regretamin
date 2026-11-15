// Startup names in a deal list take their color from st_status. No status tag.
// node --test tests/startup_status.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const css = read('launch/style.css');
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

function dealsHtml(deals) {
  const main = mainEl();
  main.set('.actw', el());
  const pmain = main.set('.pmain', el());
  render(main, {
    open: true, checks: [], sections: [],
    firm: { name: 'Example', slug: 'example' },
    activity: { deals, counts: { deals: deals.length } },
  });
  return pmain.innerHTML;
}

test('shut down is red text, acquired is green text, and everything else is unchanged', () => {
  const html = dealsHtml([
    { company: 'Gone Co', st_status: 'Shut down', website_url: 'https://gone.example', date: '2024-01-02', sector: 'Fintech', round: 'Seed' },
    { company: 'Sold Co', st_status: 'Acquired', domain: 'sold.example', date: '2024-02-02', sector: 'Health', round: 'Series A' },
    { company: 'Live Co', st_status: null, website_url: 'https://live.example', date: '2024-03-02', sector: 'Security', round: 'Seed' },
    { company: 'Open Co', st_status: 'Operating', date: '2024-04-02', sector: 'Bio', round: 'Seed' },
    { company: 'Quiet Exit', st_status: 'Shut down', date: '2023-05-02', sector: 'Fintech', round: 'Seed' },
    { company: '<img>', st_status: 'Acquired', date: '2023-06-02', sector: 'Health', round: 'Seed' },
  ]);
  assert.match(html, /<a class="co st-down" href="https:\/\/gone\.example"/);
  assert.match(html, /class="co st-down"[^>]*>Gone Co</);
  assert.match(html, /<a class="co st-acq" href="https:\/\/sold\.example"/);
  assert.match(html, /class="co st-acq"[^>]*>Sold Co</);
  assert.match(html, /<a class="co" href="https:\/\/live\.example"[^>]*>Live Co</);
  assert.match(html, /<span class="co">Open Co</);
  assert.match(html, /<span class="co st-down">Quiet Exit</);
  assert.match(html, /<span class="co st-acq">&lt;img&gt;</);
  assert.doesNotMatch(html, /class="co st-down st-acq|class="co st-acq st-down|Shut down|Acquired|>Operating</);
  assert.equal((html.match(/class="dcard"/g) || []).length, 6);
  const table = html.slice(html.indexOf('class="dtable"'), html.indexOf('class="dcards"'));
  const cards = html.slice(html.indexOf('class="dcards"'));
  ['Gone Co', 'Sold Co', 'Live Co', 'Quiet Exit'].forEach(name => {
    assert.ok(table.includes(name), name);
    assert.ok(cards.includes(name), name);
  });
});

test('status color reuses the existing red and green, with no badge', () => {
  const rules = css.split('\n').filter(line => line.includes('.st-down') || line.includes('.st-acq'));
  assert.equal(rules.length, 2);
  assert.match(rules[0], /\.dcard \.dname a\.co\.st-down/);
  assert.match(rules[0], /\{color:var\(--rev\)\}$/);
  assert.match(rules[1], /\.dcard \.dname a\.co\.st-acq/);
  assert.match(rules[1], /\{color:#0F7A3A\}$/);
  assert.doesNotMatch(rules.join('\n'), /border-radius|badge|pill|content:/);
  assert.match(js, /s === 'Shut down'/);
  assert.match(js, /s === 'Acquired'/);
});
