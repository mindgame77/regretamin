// Activity year: January through May counts the previous UTC year and the current
// UTC year. June 1 onward counts only the current UTC year.
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
const { activityYear, countThisYear, rank, label } = sandbox.window.RegretActivity;
const utc = (y, m, d, h) => new Date(Date.UTC(y, m - 1, d, h || 0));

test('January through May 31 count both years, June 1 counts only the current year', () => {
  assert.equal(activityYear(utc(2027, 1, 15, 12)), '2026');
  assert.equal(activityYear(utc(2027, 5, 31, 23)), '2026');
  assert.equal(activityYear(utc(2027, 6, 1, 0)), '2027');
  assert.equal(activityYear(utc(2026, 11, 15, 12)), '2026');
  const deals = [{ date: '2025-06-01' }, { date: '2026-01-01' }, { date: '2027-03-02' }];
  assert.equal(countThisYear(deals, utc(2027, 1, 15, 12)), 2);
  assert.equal(countThisYear(deals, utc(2027, 5, 31, 23)), 2);
  assert.equal(countThisYear(deals, utc(2027, 6, 1, 0)), 1);
  assert.equal(countThisYear(deals, utc(2026, 11, 15, 12)), 1);
});

test('nothing in the window is Not active when research is done or any deal is on record', () => {
  assert.equal(rank(4, 4, 0, false), 3);
  assert.equal(rank(1, 0, 9, true), 2);
  assert.equal(rank(0, 6, 6, false), 1);
  assert.equal(rank(0, 0, 12, false), 1);
  assert.equal(rank(0, 0, 0, true), 1);
  assert.equal(rank(0, 0, 0, false), 0);
  assert.equal(label(0, 0, 440, true).text, 'Not active');
  assert.equal(label(0, 0, 0, true).text, 'Not active');
  assert.equal(label(0, 0, 0, false).text, 'Not checked yet');
  assert.equal(label(3, 3, 0, true).text, 'Active');
});
