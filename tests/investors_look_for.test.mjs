// What investors look for: after Thesis, before Team. Five summary rows.
// Show all opens the same list popup as the other sections, with every quote.
// node --test tests/investors_look_for.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const css = read('launch/style.css');
const icon = read('launch/assets/icons/link-simple.svg');
const iconPath = icon.match(/d="([^"]+)"/)[1];

const clicks = [];
const made = {};
function el() {
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', id: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
    remove() {},
    insertAdjacentElement() { return null; },
    getAttribute() { return null; },
  };
}
function resetModals() { for (const k of Object.keys(made)) delete made[k]; }
function mainEl() {
  const kids = {};
  const main = el();
  main.querySelector = (sel) => kids[sel] || null;
  main.set = (sel, child) => { kids[sel] = child; return child; };
  return main;
}
const sandbox = {
  window: { REGRET: { copy } },
  document: {
    body: { appendChild(n) { made[n.id] = n; } },
    addEventListener(type, fn) { if (type === 'click') clicks.push(fn); },
    getElementById(id) { return made[id] || null; },
    createElement: () => el(),
  },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(read('launch/js/company.js'), sandbox, { filename: 'company.js' });
const { pageSecs, render, investorsHtml } = sandbox.window.RegretCompany;

function row(n, extra) {
  return Object.assign({
    investor_name: 'Investor ' + n,
    investor_title: 'General Partner',
    summary: 'Summary line ' + n + ' stays a takeaway.',
    quote: 'Exact quote body ' + n + ' is longer than the summary and is not the summary.',
    published_at: '2016-05-30',
    source_url: 'https://a16z.com/quote-' + n,
    role_source_url: 'https://a16z.com/team/investor-' + n,
  }, extra || {});
}
const people = { key: 'people', items: [{ head: 'Marc Andreessen', kind: 'team', role: 'Cofounder and General Partner' }] };
const thesis = { key: 'overview', items: [{ label: 'thesis', value: 'We back technical founders.' }] };

function page(items, checks, extra) {
  return {
    open: true,
    checks: checks || [],
    firm: { name: 'Andreessen Horowitz', slug: 'a16z', short_name: 'a16z' },
    sections: [thesis, { key: 'investors', items }, people].concat(extra || []),
  };
}
function popup(id) {
  const ov = made[id];
  assert.ok(ov, id + ' popup');
  assert.equal(ov.className, 'ov tall');
  assert.equal(ov.hidden, true);
  assert.match(ov.innerHTML, /class="md w amd" role="dialog" aria-modal="true"/);
  assert.match(ov.innerHTML, /<button class="x" data-close aria-label="Close">/);
  assert.match(ov.innerHTML, /<div class="amh">/);
  assert.match(ov.innerHTML, /<div class="amb">/);
  return ov.innerHTML;
}
function draw(P) {
  resetModals();
  const main = mainEl();
  main.set('.actw', el());
  const pmain = main.set('.pmain', el());
  const spl = main.set('.spl', el());
  const toc = main.set('.toc', el());
  main.set('.m', el());
  render(main, P);
  return { body: pmain.innerHTML, chips: spl.innerHTML, nav: toc.innerHTML };
}
function between(html, start, end) {
  const a = html.indexOf(start);
  const b = end ? html.indexOf(end, a + start.length) : html.length;
  assert.ok(a >= 0 && b > a, start + ' .. ' + end);
  return html.slice(a, b);
}
const count = (html, needle) => (html.match(new RegExp(needle, 'g')) || []).length;

test('no rows: no section, chip, or nav entry', () => {
  for (const items of [
    undefined,
    [],
    [row(1, { summary: '   ', quote: 'A real quote that is not empty.' })],
    [row(1, { quote: 'Summary line 1 stays a takeaway.' })],
    [row(1, { source_url: 'http://a16z.com/not-https' })],
    [row(1, { source_url: 'notaurl' })],
    [row(1, { investor_name: '  ' })],
  ]) {
    const secs = items === undefined
      ? pageSecs({ sections: [thesis, people] })
      : pageSecs(page(items));
    assert.equal(secs.find(s => s.key === 'investors'), undefined);
    const html = draw(items === undefined ? { open: true, checks: [], firm: { name: 'Andreessen Horowitz', slug: 'a16z' }, sections: [thesis, people] } : page(items)).body;
    assert.doesNotMatch(html, /id="investors"|What investors look for|class="ipr"/);
  }
});

const openPage = { open: true, firm: { name: 'Andreessen Horowitz', slug: 'a16z' } };
function quotesInPopup(items) {
  resetModals();
  const pageHtml = investorsHtml(items, openPage);
  const open = popup('actinvestors');
  return { pageHtml, open };
}

test('a quote with no date shows no year; a dated quote still shows its year', () => {
  const { pageHtml, open } = quotesInPopup([
    row(1, { published_at: null }),
    row(2, { published_at: '2016-05-30' }),
  ]);
  assert.match(pageHtml, /Investor 1 · General Partner</);
  assert.doesNotMatch(pageHtml, /Investor 1 · General Partner · /);
  assert.match(pageHtml, /Investor 2 · General Partner · 2016/);
  assert.match(open, /Investor 1 · General Partner</);
  assert.doesNotMatch(open, /Investor 1 · General Partner · /);
  assert.match(open, /Investor 2 · General Partner · 2016/);
});

test('attribution can wrap and nothing in the row is cropped', () => {
  assert.match(css, /\.ipa\{[^}]*flex-wrap:wrap/);
  assert.match(css, /\.ipwho\{[^}]*overflow-wrap:anywhere/);
  assert.match(css, /\.ips\{[^}]*overflow-wrap:anywhere/);
  assert.match(css, /\.ipq\{[^}]*overflow-wrap:anywhere/);
  assert.match(css, /\.iplab\{[^}]*text-transform:uppercase[^}]*color:var\(--mute\)/);
  assert.match(css, /\.ipi svg\{width:12px;height:12px/);
  assert.doesNotMatch(css, /\.ips\{[^}]*line-clamp|\.ipq\{[^}]*line-clamp|\.ipr\{[^}]*overflow:hidden|\.ipr\{[^}]*cursor:pointer/);
});
