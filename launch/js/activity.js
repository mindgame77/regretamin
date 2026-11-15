/* One activity rule for the Investors list and the firm-page tile.
   A deal counts for a year when extract(year from deal_date) matches
   extract(year from current_date). The database clock is UTC, and a
   year-only deal is stored as YYYY-01-01, so that date counts for YYYY. */
(function () {
  function yearOf(date) {
    const m = String(date || '').match(/(\d{4})/);
    return m ? m[1] : '';
  }
  function currentYear() {
    return String(new Date().getUTCFullYear());
  }
  function countThisYear(deals) {
    const y = currentYear();
    return (deals || []).filter(function (d) { return yearOf(d && d.date) === y; }).length;
  }
  function label(dealsThisYear, totalDeals) {
    if (dealsThisYear == null || dealsThisYear === '') return null;
    const year = Number(dealsThisYear);
    if (!Number.isFinite(year) || year < 0) return null;
    const total = Number(totalDeals);
    const hasDeals = Number.isFinite(total) && total > 0;
    if (year >= 3) return { cls: 'act-on', text: 'Active' };
    if (year >= 1) return { cls: 'act-low', text: 'Low activity' };
    if (hasDeals) return { cls: 'act-off', text: 'Not active' };
    return { cls: 'act-new', text: 'Not checked yet' };
  }
  window.RegretActivity = { yearOf: yearOf, currentYear: currentYear, countThisYear: countThisYear, label: label };
})();
