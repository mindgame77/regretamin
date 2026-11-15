// Activity year: previous UTC year through May 31, current UTC year from June 1.
// node --test tests/activity_year.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const sandbox = { Date, console, window: {} };
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('../launch/js/dates.js', import.meta.url), 'utf8'), sandbox, { filename: 'dates.js' });
const { activityYear, countThisYear } = sandbox.window.RegretActivity;
const utc = (y, m, d, h) => new Date(Date.UTC(y, m - 1, d, h || 0));

test('January through May 31 use the previous year, June 1 uses the current year', () => {
  assert.equal(activityYear(utc(2027, 1, 15, 12)), '2026');
  assert.equal(activityYear(utc(2027, 5, 31, 23)), '2026');
  assert.equal(activityYear(utc(2027, 6, 1, 0)), '2027');
  assert.equal(activityYear(utc(2026, 11, 15, 12)), '2026');
  const deals = [{ date: '2026-01-01' }, { date: '2027-03-02' }];
  assert.equal(countThisYear(deals, utc(2027, 2, 1, 12)), 1);
  assert.equal(countThisYear(deals, utc(2027, 5, 31, 23)), 1);
  assert.equal(countThisYear(deals, utc(2027, 6, 1, 0)), 1);
});
