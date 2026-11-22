// Whole rows only: a further row is shown when it fits, and never as a partial slice.
// node --test tests/tile_fill.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const copy = JSON.parse(fs.readFileSync(new URL('launch/copy.json', root), 'utf8'));
const css = fs.readFileSync(new URL('launch/style.css', root), 'utf8');
const sandbox = {
  window: { REGRET: { copy } },
  document: {
    addEventListener() {},
    getElementById() { return null; },
    body: { appendChild() {} },
    createElement() { return { className: '', hidden: true, innerHTML: '', appendChild() {} }; },
  },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('launch/js/dates.js', root), 'utf8'), sandbox, { filename: 'dates.js' });
vm.runInContext(fs.readFileSync(new URL('launch/js/company.js', root), 'utf8'), sandbox, { filename: 'company.js' });
const { extraRowsThatFit } = sandbox.window.RegretCompany;

function boxes(heights, space) {
  const n = extraRowsThatFit(heights, space);
  let y = 0;
  const out = [];
  for (let i = 0; i < n; i++) {
    out.push({ top: y, bottom: y + heights[i], h: heights[i] });
    y += heights[i];
  }
  return out;
}

test('only whole rows that fit are kept, and they do not overlap', () => {
  const placed = boxes([40, 37, 37, 37], 96);
  assert.equal(placed.length, 2);
  assert.ok(placed[placed.length - 1].bottom <= 96);
  for (let i = 1; i < placed.length; i++) assert.ok(placed[i].top >= placed[i - 1].bottom);
  assert.equal(extraRowsThatFit([46], 16), 0);
  assert.equal(extraRowsThatFit([90], 72), 0);
  assert.equal(extraRowsThatFit([68, 90], 72), 1);
  assert.equal(extraRowsThatFit([37, 37, 37], 111), 3);
});

test('legal case titles are not ellipsized', () => {
  const rule = css.slice(css.indexOf('.lgt{'), css.indexOf('}', css.indexOf('.lgt{')) + 1);
  assert.match(rule, /white-space:normal/);
  assert.doesNotMatch(rule, /text-overflow:ellipsis|white-space:nowrap/);
});

test('industry color comes from the name, and the donut is a filled ring', () => {
  const { sectorColor } = sandbox.window.RegretCompany;
  const palette = ['#A9C4E8', '#F2A7A0', '#F3D98B', '#9FD4C3', '#D9B5E0', '#BFDCA0', '#C59AC7', '#8E9BE0', '#C4CCF2', '#A8BDB5', '#F7E6B5', '#F5C19A', '#D5E0A3', '#9CC9D9', '#EFC4D0', '#B9E0E6', '#E6C9B0'];
  const js = fs.readFileSync(new URL('launch/js/company.js', root), 'utf8');
  palette.forEach(hex => assert.match(js, new RegExp(hex, 'i')));
  assert.equal(sectorColor('AI agents'), '#8E9BE0');
  assert.equal(sectorColor('Enterprise software'), '#A9C4E8');
  assert.equal(sectorColor('Health'), '#F2A7A0');
  assert.equal(sectorColor('Security'), '#A8BDB5');
  assert.equal(sectorColor('Other'), '#DADFDD');
  assert.equal(sectorColor('other'), '#DADFDD');
  assert.equal(sectorColor('Health'), sectorColor('health'));
  assert.equal(sectorColor('Cloud & Data'), sectorColor('Developer tools'));
  assert.equal(sectorColor('Cybersecurity'), sectorColor('Security'));
  assert.equal(sectorColor('Biotech'), sectorColor('Bio'));
  assert.equal(sectorColor('Payments'), sectorColor('Fintech'));
  assert.equal(sectorColor('Robotics'), '#9FD4C3');
  assert.equal(sectorColor('Defense'), '#B5B5BD');
  assert.equal(sectorColor('Space'), '#9AA5D1');
  assert.equal(sectorColor('Govtech'), '#C2D6C8');
  assert.equal(sectorColor('Defense'), sectorColor('defense'));
  const { parentIndustry, dealLabel, dealParent } = sandbox.window.RegretCompany;
  assert.equal(parentIndustry('Gaming'), 'Media & Gaming');
  assert.equal(parentIndustry('Food'), 'Food & Agriculture');
  assert.equal(dealLabel({ sector: 'Developer tools', industry_name: 'Cloud & Data' }), 'Cloud & Data');
  assert.equal(dealLabel({ sector: 'Security', industry_name: null }), 'Security');
  assert.equal(dealLabel({ sector: 'Bio' }), 'Bio');
  assert.equal(dealParent({ sector: 'Developer tools', industry_name: 'Cloud & Data' }), 'Developer tools');
  assert.equal(dealParent({ sector: 'Hardware', industry_name: 'Robotics' }), 'Hardware & Robotics');
  assert.equal(dealParent({ sector: 'Space', industry_name: 'Space' }), 'Space');
  const future = sectorColor('Quantum widgets');
  assert.equal(future, sectorColor('Quantum widgets'));
  assert.notEqual(future, '#A7A2C2');
  assert.ok(palette.slice(0, 17).includes(future));
  assert.ok(!palette.includes('#B5B5BD'));
  sandbox.addEventListener = function () {};
  vm.runInContext(fs.readFileSync(new URL('launch/js/firms.js', root), 'utf8'), sandbox, { filename: 'firms.js' });
  const dir = sandbox.window.RegretSectors;
  ['Cloud & Data', 'Cybersecurity', 'Biotech', 'Defense', 'Space', 'Govtech', 'Payments', 'Gaming', 'Food', 'Other', 'Quantum widgets'].forEach(name => {
    assert.equal(dir.sectorColor(name), sectorColor(name), name);
    assert.equal(dir.parentIndustry(name), parentIndustry(name), name);
  });
  assert.doesNotMatch(js, /PAL\[/);
  assert.doesNotMatch(js, /stroke-dashoffset/);
  assert.match(js, /function ringSlice/);
  assert.match(js, /fill="' \+ sectorColor/);
});

test('LP tile has no commitment count, investors and legal drop row rules', () => {
  const js = fs.readFileSync(new URL('launch/js/company.js', root), 'utf8');
  assert.doesNotMatch(js, /COPY\.commitments/);
  assert.match(js, /oneSource \? src\.slice\(0, 1\)/);
  assert.match(css, /\.bento #investors \.ipr,\.ov \.ipr\{border-top:0/);
  assert.match(css, /\.ipr-a\{background:#E4F2FF\}/);
  assert.match(css, /\.ipr-b\{background:#F1F0F5\}/);
  assert.match(css, /\.lgline\.st-act\{background:#FFE3DE\}/);
  assert.match(css, /\.lgline\.st-dis\{background:#F1F0F5\}/);
  assert.match(css, /\.lgline\.st-set\{background:#E3F8EE\}/);
  assert.match(css, /\.ips \.iplab\{font-weight:700/);
  assert.match(css, /\.prof \.ips\{font:700 15px/);
  assert.match(css, /\.prof \.ipa,\.prof \.arat\{font:400/);
  assert.match(css, /\.bento #lps \.lpl \.rt\{[^}]*text-overflow:ellipsis/);
  const legal = css.slice(css.indexOf('.lglines .lgline{'), css.indexOf('}', css.indexOf('.lglines .lgline{')) + 1);
  assert.match(legal, /border-bottom:0/);
  assert.doesNotMatch(legal, /border-bottom:1px/);
});

test('desktop pairs share the Deals announced / Videos height, recent deals does not', () => {
  const at = css.indexOf('@media (min-width:801px)');
  assert.ok(at > 0);
  const rule = css.slice(at, css.indexOf('}', css.indexOf('.bento .mod:not(.span2)', at)) + 1);
  assert.match(rule, /height:323px/);
  assert.match(rule, /:not\(\.span2\)/);
  const js = fs.readFileSync(new URL('launch/js/company.js', root), 'utf8');
  assert.match(js, /bentoCard\('lps', esc\(by\.lps\.title\),/);
  assert.doesNotMatch(js, /by\.lps\.count/);
  const block = css.slice(at, css.indexOf('@media', at + 8) === -1 ? css.length : css.indexOf('@media', at + 8));
  assert.match(block, /#sectors \.cc,#rounds \.cc\{margin-top:auto;margin-bottom:auto\}/);
  assert.match(block, /#sectors \.ash\{margin-top:0/);
  assert.doesNotMatch(block, /#announced \.cc/);
});
