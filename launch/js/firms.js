/* /investors/ directory. Columns are the v3 grid. Filters reuse the
   firm-directory concept-2-filters facet sidebar (Region, Industries,
   Investment stages, Investor status) from /workspace/regretamin-design/firm-directory.
   Legal records and Recorded information are not in the menu. */
(function () {
  // Same parent hues as launch/js/company.js. A sub-industry uses its parent. Other stays slate.
  const SECTOR_PALETTE = ['#A9C4E8', '#F2A7A0', '#F3D98B', '#9FD4C3', '#D9B5E0', '#BFDCA0', '#C59AC7', '#8E9BE0', '#C4CCF2', '#A8BDB5', '#F7E6B5', '#F5C19A', '#D5E0A3', '#9CC9D9', '#EFC4D0', '#B9E0E6', '#E6C9B0'];
  const SECTOR_COLORS = {
    // One colour per industry, the same as on the map (launch/js/map.js COLORS). A sub-industry shows in its parent's colour.
    'Enterprise software': '#A9C4E8',
    'Health': '#F2A7A0',
    'Fintech': '#F3D98B',
    'Hardware & Robotics': '#9FD4C3',
    'Consumer': '#D9B5E0',
    'Climate & Energy': '#BFDCA0',
    'Bio': '#C59AC7',
    'AI agents': '#8E9BE0',
    'AI models': '#C4CCF2',
    'Security': '#A8BDB5',
    'Crypto': '#F7E6B5',
    'Media & Gaming': '#F5C19A',
    'Food & Agriculture': '#D5E0A3',
    'Defense': '#B5B5BD',
    'Space': '#9AA5D1',
    'Mobility': '#9CC9D9',
    'Education': '#EFC4D0',
    'Developer tools': '#B9E0E6',
    'Real estate': '#E6C9B0',
    'Govtech': '#C2D6C8',
    'Other': '#DADFDD'
  };
  const SUB_PARENT = {
    'AI infrastructure': 'AI models', 'Payments': 'Fintech', 'Insurtech': 'Fintech', 'Wealth': 'Fintech',
    'Digital health': 'Health', 'Medtech': 'Health', 'Wellness': 'Health', 'Biotech': 'Bio',
    'Commerce': 'Consumer', 'Travel': 'Consumer', 'Sports': 'Consumer',
    'HR Tech': 'Enterprise software', 'Legal Tech': 'Enterprise software', 'Marketing': 'Enterprise software',
    'Cloud & Data': 'Developer tools', 'Cybersecurity': 'Security',
    'Hardware': 'Hardware & Robotics', 'Robotics': 'Hardware & Robotics', 'Semiconductors': 'Hardware & Robotics',
    'Manufacturing': 'Hardware & Robotics', 'Materials': 'Hardware & Robotics', 'Deep tech': 'Hardware & Robotics',
    'Telecom': 'Hardware & Robotics', 'Logistics': 'Mobility', 'Construction': 'Real estate',
    'Media': 'Media & Gaming', 'Gaming': 'Media & Gaming', 'Food': 'Food & Agriculture', 'Agriculture': 'Food & Agriculture'
  };
  const PARENT_OF = {};
  Object.keys(SECTOR_COLORS).forEach(function (name) { PARENT_OF[name.toLowerCase()] = name; });
  Object.keys(SUB_PARENT).forEach(function (name) { PARENT_OF[name.toLowerCase()] = SUB_PARENT[name]; });
  function parentIndustry(name) {
    const s = String(name || '').trim();
    if (!s) return '';
    return PARENT_OF[s.toLowerCase()] || s;
  }
  function sectorColor(name) {
    const s = parentIndustry(name);
    if (!s || /^other$/i.test(s)) return SECTOR_COLORS.Other;
    if (Object.prototype.hasOwnProperty.call(SECTOR_COLORS, s)) return SECTOR_COLORS[s];
    const found = Object.keys(SECTOR_COLORS).find(function (k) { return k.toLowerCase() === s.toLowerCase(); });
    if (found) return SECTOR_COLORS[found];
    const hues = SECTOR_PALETTE.slice(0, 17);
    let h = 2166136261;
    const n = s.toLowerCase();
    for (let i = 0; i < n.length; i++) h = Math.imul(h ^ n.charCodeAt(i), 16777619);
    return hues[(h >>> 0) % hues.length];
  }
  window.RegretSectors = { parentIndustry: parentIndustry, sectorColor: sectorColor };

  const list = document.getElementById('firms-list');
  if (!list) return;

  const root = window.REGRET_ROOT || '';
  const copy = ((window.REGRET || {}).copy || {}).site || {};
  const pageCopy = (copy.pages || {}).investors || {};

  const COUNTRY = { US: 'United States', GB: 'United Kingdom', CH: 'Switzerland', KY: 'Cayman Islands' };
  const REGION = {
    US: 'north_america', CA: 'north_america', MX: 'north_america', GL: 'north_america', PM: 'north_america',
    AD: 'europe', AL: 'europe', AT: 'europe', AX: 'europe', BA: 'europe', BE: 'europe',
    BG: 'europe', BV: 'europe', BY: 'europe', CH: 'europe', CY: 'europe', CZ: 'europe',
    DE: 'europe', DK: 'europe', EE: 'europe', ES: 'europe', FI: 'europe', FO: 'europe',
    FR: 'europe', GB: 'europe', GG: 'europe', GI: 'europe', GR: 'europe', HR: 'europe',
    HU: 'europe', IE: 'europe', IM: 'europe', IS: 'europe', IT: 'europe', JE: 'europe',
    LI: 'europe', LT: 'europe', LU: 'europe', LV: 'europe', MC: 'europe', MD: 'europe',
    ME: 'europe', MK: 'europe', MT: 'europe', NL: 'europe', NO: 'europe', PL: 'europe',
    PT: 'europe', RO: 'europe', RS: 'europe', RU: 'europe', SE: 'europe', SI: 'europe',
    SJ: 'europe', SK: 'europe', SM: 'europe', UA: 'europe', VA: 'europe', XK: 'europe',
    AG: 'latam', AI: 'latam', AR: 'latam', AW: 'latam', BB: 'latam', BL: 'latam',
    BM: 'latam', BO: 'latam', BQ: 'latam', BR: 'latam', BS: 'latam', BZ: 'latam',
    CL: 'latam', CO: 'latam', CR: 'latam', CU: 'latam', CW: 'latam', DM: 'latam',
    DO: 'latam', EC: 'latam', FK: 'latam', GD: 'latam', GF: 'latam', GP: 'latam',
    GS: 'latam', GT: 'latam', GY: 'latam', HN: 'latam', HT: 'latam', JM: 'latam',
    KN: 'latam', KY: 'latam', LC: 'latam', MF: 'latam', MQ: 'latam', MS: 'latam',
    NI: 'latam', PA: 'latam', PE: 'latam', PR: 'latam', PY: 'latam', SR: 'latam',
    SV: 'latam', SX: 'latam', TC: 'latam', TT: 'latam', UY: 'latam', VC: 'latam',
    VE: 'latam', VG: 'latam', VI: 'latam',
    AF: 'asia', AM: 'asia', AZ: 'asia', BD: 'asia', BN: 'asia', BT: 'asia',
    CN: 'asia', GE: 'asia', HK: 'asia', ID: 'asia', IN: 'asia', IO: 'asia',
    JP: 'asia', KG: 'asia', KH: 'asia', KP: 'asia', KR: 'asia', KZ: 'asia',
    LA: 'asia', LK: 'asia', MM: 'asia', MN: 'asia', MO: 'asia', MV: 'asia',
    MY: 'asia', NP: 'asia', PH: 'asia', PK: 'asia', SG: 'asia', TH: 'asia',
    TJ: 'asia', TL: 'asia', TM: 'asia', TW: 'asia', UZ: 'asia', VN: 'asia',
    AE: 'middle_east', BH: 'middle_east', IL: 'middle_east', IQ: 'middle_east', IR: 'middle_east', JO: 'middle_east',
    KW: 'middle_east', LB: 'middle_east', OM: 'middle_east', PS: 'middle_east', QA: 'middle_east', SA: 'middle_east',
    SY: 'middle_east', TR: 'middle_east', YE: 'middle_east',
    AO: 'africa', BF: 'africa', BI: 'africa', BJ: 'africa', BW: 'africa', CD: 'africa',
    CF: 'africa', CG: 'africa', CI: 'africa', CM: 'africa', CV: 'africa', DJ: 'africa',
    DZ: 'africa', EG: 'africa', EH: 'africa', ER: 'africa', ET: 'africa', GA: 'africa',
    GH: 'africa', GM: 'africa', GN: 'africa', GQ: 'africa', GW: 'africa', KE: 'africa',
    KM: 'africa', LR: 'africa', LS: 'africa', LY: 'africa', MA: 'africa', MG: 'africa',
    ML: 'africa', MR: 'africa', MU: 'africa', MW: 'africa', MZ: 'africa', NA: 'africa',
    NE: 'africa', NG: 'africa', RE: 'africa', RW: 'africa', SC: 'africa', SD: 'africa',
    SH: 'africa', SL: 'africa', SN: 'africa', SO: 'africa', SS: 'africa', ST: 'africa',
    SZ: 'africa', TD: 'africa', TF: 'africa', TG: 'africa', TN: 'africa', TZ: 'africa',
    UG: 'africa', YT: 'africa', ZA: 'africa', ZM: 'africa', ZW: 'africa',
    AS: 'oceania', AU: 'oceania', CC: 'oceania', CK: 'oceania', CX: 'oceania', FJ: 'oceania',
    FM: 'oceania', GU: 'oceania', HM: 'oceania', KI: 'oceania', MH: 'oceania', MP: 'oceania',
    NC: 'oceania', NF: 'oceania', NR: 'oceania', NU: 'oceania', NZ: 'oceania', PF: 'oceania',
    PG: 'oceania', PN: 'oceania', PW: 'oceania', SB: 'oceania', TK: 'oceania', TO: 'oceania',
    TV: 'oceania', UM: 'oceania', VU: 'oceania', WF: 'oceania', WS: 'oceania',
  };
  const REGION_OPTIONS = [
    ['north_america', 'US / North America'],
    ['europe', 'Europe'],
    ['asia', 'Asia'],
    ['latam', 'LatAm'],
    ['africa', 'Africa'],
    ['middle_east', 'Middle East'],
    ['oceania', 'Australia & Oceania'],
    ['unknown', 'Not disclosed']
  ];

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  function fmtDate(v) {
    return (window.RegretDate && RegretDate.format(v)) || '';
  }
  function stamp(v) {
    return (window.RegretDate && RegretDate.stamp(v)) || 0;
  }
  function roundName(r) {
    return String(r || '').replace(/^stage tag:\s*/i, '').trim();
  }
  function prettyCity(s) {
    const t = String(s || '').trim();
    if (!t) return '';
    if (t === t.toUpperCase() && t.length > 3) {
      return t.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
    }
    return t;
  }
  function cityLabel(f) {
    return prettyCity(f.city) || COUNTRY[f.country] || '';
  }
  function regionOf(f) {
    return REGION[f.country] || (f.country ? 'unknown' : 'unknown');
  }
  function keyOf(s) {
    return String(s || '').trim().toLowerCase();
  }
  function sortNewest(rows) {
    return rows.slice().sort((a, b) => (stamp(b.added) - stamp(a.added)) || String(a.name || '').localeCompare(String(b.name || '')));
  }
  function href(slug) { return (window.REGRET_VC_BASE || '/vc/') + encodeURIComponent(slug) + '/'; }
  function invests(f, max) {
    const rows = Array.isArray(f.industries) ? f.industries.filter(Boolean) : [];
    if (!rows.length) return '';
    const n = max || 2;
    const shown = rows.slice(0, n);
    const more = rows.length - shown.length;
    return shown.map(function (name) {
      return '<span class="find"><i style="background:' + sectorColor(name) + '"></i>' + esc(name) + '</span>';
    }).join('') + (more > 0 ? '<span class="fmore">+' + more + '</span>' : '');
  }
  // Total investments: dated shown deals + undated portfolio-only rows.
  // firm_directory_page returns that as `investments` and keeps `deals` dated-only
  // for the Activity label. Zero and null stay blank.
  function investmentCount(f) {
    const raw = (f && f.investments != null && f.investments !== '') ? f.investments : (f && f.deals);
    const n = Number(raw);
    if (!Number.isFinite(n) || n <= 0) return '';
    return Math.trunc(n).toLocaleString('en-US');
  }
  function activityOf(f) {
    const rule = window.RegretActivity;
    if (!rule) return null;
    const stored = f && rule.fromText(f.activity);
    return stored || rule.label(f && f.deals_this_year, f && f.deals, f && f.investments, f && f.researched);
  }
  // Same rank the Activity column shows. Blank when that column is blank.
  function activityValue(f) {
    const rule = window.RegretActivity;
    const lab = rule ? activityOf(f) : null;
    if (!lab) return '';
    return String(lab.rank != null ? lab.rank : rule.rank(f && f.deals_this_year, f && f.deals, f && f.investments, f && f.researched));
  }
  // The four labels come from RegretActivity, in the same order as its ranks.
  function activityOptions(counts) {
    const rule = window.RegretActivity;
    return [3, 2, 1, 0].map(function (rank) {
      const year = rank > 1 ? rank : 0;
      const deals = rank === 1 ? 1 : 0;
      const labeled = rule ? rule.label(year, deals) : null;
      return {
        value: String(rank),
        label: labeled ? labeled.text : '',
        count: Number(counts && counts[String(rank)]) || 0
      };
    });
  }
  function activityHtml(f) {
    const a = activityOf(f);
    if (!a) return '<span class="fact"></span>';
    return '<span class="fact"><span class="alab ' + a.cls + '">' + esc(a.text) + '</span>' + signalsHtml(f) + '</span>';
  }
  // Signals shown as icons in the Activity column. Rules: project doc claude/plans/investors-list.md.
  // The numbers come from v2_firm_signals, refreshed once a day.
  const SIGNALS = [
    ['up', '🚀', 'Speeding up', 'At least 10 more deals in the last 12 months than in the 12 months before.'],
    ['down', '📉', 'Slowing down', 'At least 10 fewer deals in the last 12 months than in the 12 months before.'],
    ['top', '💯', 'Top 100', 'On the Regretamin Top Firms list for the year.'],
    ['chain', '🔗', 'Top firms follow it', 'Five or more top-100 firms invested after it, at least twice each.'],
    ['lead', '🏆', 'Leads rounds', 'Led at least half of its deals in the last 12 months (10 deals or more).'],
    ['spec', '🎯', 'Specialist', 'More than half of its deals are in one sector.'],
    ['fund', '💰', 'Fresh fund', 'Closed a new fund in the last 12 months.']
  ];
  const DEALS_YEAR = [['lt5', 'Fewer than 5 deals this year'], ['5', '5 or more deals this year'], ['10', '10 or more deals this year'], ['25', '25 or more deals this year']];
  function signalIcon(key) {
    const g = SIGNALS.filter(function (x) { return x[0] === key; })[0];
    if (!g) return '';
    return g[1] ? '<span class="fsig" aria-hidden="true">' + g[1] + '</span>' : '<span class="fsig f100" aria-hidden="true">100</span>';
  }
  function signalsHtml(f) {
    const have = Array.isArray(f && f.signals) ? f.signals : [];
    return SIGNALS.filter(function (g) { return have.indexOf(g[0]) !== -1; }).map(function (g) {
      let tip = g[2] + '. ' + g[3];
      if ((g[0] === 'up' || g[0] === 'down') && f.deals_now != null) tip = g[2] + ': ' + f.deals_now + ' deals in the last 12 months, ' + f.deals_prev + ' in the 12 before.';
      if (g[0] === 'lead' && f.deals_now != null) tip = g[2] + ': led ' + f.led_now + ' of its ' + f.deals_now + ' deals in the last 12 months.';
      return '<span class="fsigw" role="img" aria-label="' + esc(g[2]) + '" title="' + esc(tip) + '">' + signalIcon(g[0]) + '</span>';
    }).join('');
  }
  // Country flag from the two-letter country code. No flag when the country is unknown.
  function flagOf(f) {
    const cc = String((f && (f.country || f.hq_country)) || '').trim().toUpperCase();
    if (!/^[A-Z]{2}$/.test(cc)) return '';
    const name = COUNTRY[cc] || cc;
    return '<span class="fflag" role="img" aria-label="' + esc(name) + '" title="' + esc(name) + '">'
      + String.fromCodePoint(0x1F1E6 + cc.charCodeAt(0) - 65, 0x1F1E6 + cc.charCodeAt(1) - 65) + '</span>';
  }
  function row(f) {
    const date = fmtDate(f.added);
    const city = cityLabel(f);
    const inds = invests(f, window.innerWidth < 1200 ? 1 : 2);  // a narrow window has room for one sector and the "+N"
    const investments = investmentCount(f);
    const dealMain = (f.latest_company && f.latest_deal_date)
      ? [f.latest_company, roundName(f.latest_round)].filter(Boolean).join(' · ') : '';
    const dealDate = (f.latest_company && f.latest_deal_date) ? fmtDate(f.latest_deal_date) : '';
    const dealHtml = dealMain
      ? esc(dealMain) + (dealDate ? ' · <span class="dwhen">' + esc(dealDate) + '</span>' : '')
      : '';
    return '<a class="frow" href="' + href(f.slug) + '">'
      + '<span class="fnm"><b>' + esc(f.name) + '</b></span>'
      + '<span class="fcity">' + (city ? flagOf(f) : '') + esc(city) + '</span>'
      + '<span class="finds">' + inds + '</span>'
      + '<span class="finv">' + esc(investments) + '</span>'
      + activityHtml(f)
      + '<span class="fdeal">' + dealHtml + '</span>'
      + (date ? '<span class="rdt">' + esc(date) + '</span>' : '<span class="rdt"></span>')
      + '</a>';
  }
  function searchMatch(f, query) {
    if (!query) return true;
    const name = String(f.name || '').toLowerCase();
    const short = String(f.short_name || '').toLowerCase();
    const site = String(f.website || '').toLowerCase();
    return name.indexOf(query) !== -1 || (short && short.indexOf(query) !== -1) || (site && site.indexOf(query) !== -1);
  }
  function optionMatch(arr, value) {
    const want = keyOf(value);
    return (arr || []).some(function (v) { return keyOf(v) === want; });
  }
  function countBy(arr, pick) {
    const c = {};
    arr.forEach(function (f) {
      const v = pick(f);
      c[v] = (c[v] || 0) + 1;
    });
    return c;
  }
  function uniqueOptions(firms, valuesOf, labelOf, valueOf) {
    const labels = {};
    const counts = {};
    firms.forEach(function (f) {
      const seen = {};
      valuesOf(f).forEach(function (raw) {
        if (!raw) return;
        const k = keyOf(typeof raw === 'string' ? raw : valueOf(raw));
        if (!k || seen[k]) return;
        seen[k] = true;
        counts[k] = (counts[k] || 0) + 1;
        const label = typeof raw === 'string' ? raw : labelOf(raw);
        if (!labels[k]) labels[k] = label;
        else if (label !== label.toLowerCase() && labels[k] === labels[k].toLowerCase()) labels[k] = label;
        else if (label.length > labels[k].length) { /* keep existing unless current is clearly preferred */ }
      });
    });
    return Object.keys(counts).map(function (k) {
      return { value: k, label: labels[k], count: counts[k] };
    }).sort(function (a, b) { return (b.count - a.count) || a.label.localeCompare(b.label); });
  }

  // Live data: firm_directory_page(), 100 firms at a time. Search, filters and sort
  // are arguments, so a firm that is not on screen yet can still be found.
  // Builds without Supabase config fall back to the build-time firms.json.
  const C = window.REGRET || {};
  function loadFirms() {
    if (C.url && C.key) return Promise.resolve({ remote: true, firms: [] });
    return fetch(root + 'firms.json', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('firms.json'); return r.json(); });
  }
  loadFirms()
    .then(function (data) {
      const remote = !!(data && data.remote);
      const firms = (data && data.firms) || [];
      const q = document.getElementById('firms-q');
      const none = document.getElementById('firms-none');
      const sidebar = document.getElementById('firms-sidebar');
      const groupsEl = document.getElementById('facet-groups');
      const panel = document.getElementById('facet-panel');
      const pageRoot = document.querySelector('.firms-pg');
      const backdrop = document.getElementById('filters-backdrop');
      const openBtn = document.getElementById('filters-open');
      const openBadge = document.getElementById('filters-open-badge');
      let sort = 'newest';
      let asc = false;
      let panelKey = null;
      let menuKey = null;
      let draft = [];
      const active = { region: [], industry: [], stage: [], status: [], signal: [], dealsyear: [] };
      // A place on the map ("US West", "Bay Area"), set only by the map's "See the investors" link. Shown as a tag; × removes it.
      let place = null;
      // True once the database offers the map's regions (US West, Caribbean, ...) for the Region filter; until then the eight big regions are used.
      let mapRegions = false;
      // Set only by the map's link when a place was open there: the list then shows the firms the map counted, by deals done
      // in that period, instead of by what a firm's profile says. Shown as one more tag ("Last 90 days"); its × ends it.
      let deal = null;
      let typedLive = false;
      const DEAL_STAGE = { 'pre-seed': 'Pre-seed', 'seed': 'Seed', 'series a': 'Series A', 'series b': 'Series B', 'series c': 'Series C+', 'series d': 'Series C+', 'series e': 'Series C+', 'series f': 'Series C+', 'growth': 'Growth' };
      function dealOn() { return !!(deal && place && place.level !== 'city'); }

      // Older links put legal, info, or firm_status in the query string.
      // Those groups are gone. Ignore the params so the page still loads.
      function ignoreRemovedFilterParams() {
        try {
          const search = window.location && window.location.search;
          if (!search) return;
          const params = new URLSearchParams(search);
          ['legal', 'info', 'p_legal', 'p_info', 'status', 'p_status'].forEach(function (key) {
            params.getAll(key);
          });
        } catch (e) { /* a bad query string never blocks the list */ }
      }
      ignoreRemovedFilterParams();

      let regionOpts, industryOpts, stageOpts, statusOpts;
      if (remote) {
        regionOpts = REGION_OPTIONS.map(function (pair) {
          return { value: pair[0], label: pair[1], count: 0 };
        });
        industryOpts = [];
        stageOpts = [];
        statusOpts = activityOptions({});
      } else {
        const regionCounts = countBy(firms, regionOf);
        regionOpts = REGION_OPTIONS.map(function (pair) {
          return { value: pair[0], label: pair[1], count: regionCounts[pair[0]] || 0 };
        }).sort(function (a, b) { return (b.count - a.count) || a.label.localeCompare(b.label); });
        industryOpts = uniqueOptions(firms, function (f) { return f.industries || []; });
        stageOpts = uniqueOptions(firms, function (f) { return f.stages || []; });
        const statusCounts = {};
        firms.forEach(function (f) {
          const v = activityValue(f);
          if (!v) return;
          statusCounts[v] = (statusCounts[v] || 0) + 1;
        });
        statusOpts = activityOptions(statusCounts);
      }

      const GROUPS = {
        region: { title: 'Region', singular: 'regions', options: regionOpts },
        industry: { title: 'Industries', singular: 'industries', options: industryOpts },
        stage: { title: 'Investment stages', singular: 'stages', options: stageOpts },
        status: { title: pageCopy.filter_status || 'Investor status', singular: 'statuses', options: statusOpts },
        // Signals is the filter and the explanation: every icon with its rule. Ticking several keeps firms that have all of them.
        signal: { title: 'Signals', singular: 'signals', all: true, options: SIGNALS.map(function (g) {
          return { value: g[0], label: g[2], icon: signalIcon(g[0]), desc: g[3], tag: (g[1] ? g[1] + ' ' : '') + g[2], count: 0 };
        }) },
        // One choice at a time. Counted over the same 12 months the icons use.
        dealsyear: { title: 'Deals this year', singular: 'choices', all: true, single: true, options: DEALS_YEAR.map(function (d) {
          return { value: d[0], label: d[1].replace(' deals this year', ''), tag: d[1], count: 0 };
        }) }
      };
      const INLINE_OPTIONS = 5;

      function selectedCount() {
        return Object.keys(active).reduce(function (n, k) { return n + active[k].length; }, 0);
      }
      function facetOption(o, key, inPanel) {
        const checked = (inPanel ? draft : active[key]).indexOf(o.value) !== -1;
        const color = key === 'industry' ? sectorColor(o.label) : '';
        return '<label class="' + (checked ? 'checked' : '') + '" data-facet="' + esc(key) + '" data-value="' + esc(o.value) + '">'
          + '<input type="checkbox"' + (checked ? ' checked' : '') + (inPanel ? ' data-draft="1"' : '') + '>'
          + '<span class="optlabel"' + (color ? ' style="color:' + color + '"' : '') + (o.desc ? '' : ' title="' + esc(o.label) + '"') + '>' + (o.icon || '') + esc(o.label)
          + (o.desc ? '<small class="optdesc">' + esc(o.desc) + '</small>' : '') + '</span>'
          + '<span class="optcount">' + Number(o.count || 0).toLocaleString('en-US') + '</span></label>';
      }
      // One drop-down per filter group, in a row under the search bar. The menu lists the five biggest options;
      // "Show all" opens the full, searchable panel.
      function renderFacets() {
        groupsEl.innerHTML = Object.keys(GROUPS).map(function (key) {
          const g = GROUPS[key];
          const open = panel && !panel.hidden && key === panelKey;
          const shown = g.all ? g.options : g.options.slice(0, INLINE_OPTIONS);
          const more = g.options.length > shown.length;
          const n = active[key].length;
          const menuOpen = menuKey === key;
          return '<section class="facet' + (n ? ' on' : '') + (menuOpen || open ? ' open' : '') + '" id="facet-' + key + '">'
            + '<button type="button" class="fdrop" data-drop="' + esc(key) + '" aria-haspopup="true" aria-expanded="' + (menuOpen ? 'true' : 'false') + '">'
            + esc(g.title) + (n ? '<span class="facet-badge">' + n + '</span>' : '') + '<span class="fdrop-caret" aria-hidden="true">▾</span></button>'
            + '<div class="fmenu"' + (menuOpen ? '' : ' hidden') + '><h4>' + esc(g.title)
            + (n ? '<span class="facet-badge">' + n + '</span>' : '') + '</h4>'
            + shown.map(function (o) { return facetOption(o, key, false); }).join('')
            + (more
              ? '<button type="button" class="show-all" data-open="' + esc(key) + '" aria-expanded="' + (open ? 'true' : 'false') + '">Show all (' + g.options.length + ')</button>'
              : '')
            + '</div></section>';
        }).join('');
      }
      function paintCount() {
        const el = document.getElementById('firms-count');
        if (!el) return;
        el.textContent = total > 0 ? total.toLocaleString('en-US') + (total === 1 ? ' firm' : ' firms') : '';
      }
      function updateBadge() {
        const n = selectedCount();
        if (openBadge) {
          openBadge.hidden = !n;
          openBadge.textContent = n ? String(n) : '';
        }
        renderChips();
      }
      function matchesFilters(f) {
        if (active.region.length && active.region.indexOf(regionOf(f)) === -1) return false;
        if (active.industry.length && !active.industry.some(function (x) { return optionMatch(f.industries, x); })) return false;
        if (active.stage.length && !active.stage.some(function (x) { return optionMatch(f.stages, x); })) return false;
        if (active.status.length && active.status.indexOf(activityValue(f)) === -1) return false;
        if (active.signal.length && !active.signal.every(function (x) { return (f.signals || []).indexOf(x) !== -1; })) return false;
        if (active.dealsyear.length) {
          const n = Number(f.deals_now) || 0, want = active.dealsyear[0];
          if (want === 'lt5' ? n >= 5 : n < Number(want)) return false;
        }
        return true;
      }
      function cmpBlankLast(av, bv) {
        const aEmpty = !av;
        const bEmpty = !bv;
        if (aEmpty && bEmpty) return 0;
        if (aEmpty) return 1;
        if (bEmpty) return -1;
        return 0;
      }
      function sorted(rows) {
        const dir = asc ? 1 : -1;
        return rows.slice().sort(function (a, b) {
          if (sort === 'city') {
            const blank = cmpBlankLast(cityLabel(a), cityLabel(b));
            if (blank) return blank;
            const d = cityLabel(a).localeCompare(cityLabel(b));
            return d ? d * dir : String(a.name || '').localeCompare(String(b.name || ''));
          }
          if (sort === 'deal') {
            const blank = cmpBlankLast(a.latest_deal_date, b.latest_deal_date);
            if (blank) return blank;
            const d = stamp(a.latest_deal_date) - stamp(b.latest_deal_date);
            return d ? d * dir : String(a.name || '').localeCompare(String(b.name || ''));
          }
          if (sort === 'deals') {
            const count = function (row) {
              const raw = (row && row.investments != null && row.investments !== '') ? row.investments : (row && row.deals);
              const n = Number(raw);
              return Number.isFinite(n) && n > 0 ? n : null;
            };
            const blank = cmpBlankLast(count(a), count(b));
            if (blank) return blank;
            const d = count(a) - count(b);
            return d ? d * dir : String(a.name || '').localeCompare(String(b.name || ''));
          }
          if (sort === 'activity') {
            const pack = function (row) {
              if (!row || row.deals_this_year == null || row.deals_this_year === '') return null;
              const rule = window.RegretActivity;
              if (!rule) return null;
              const yearN = Number(row.deals_this_year);
              // Tiebreak stays the dated deal count. Investments and finished
              // research only move a firm with nothing in the window to Not active.
              const totalN = Number(row.deals);
              const invN = Number(row.investments);
              const year = Number.isFinite(yearN) && yearN > 0 ? Math.trunc(yearN) : 0;
              const deals = Number.isFinite(totalN) && totalN > 0 ? Math.trunc(totalN) : 0;
              const investments = Number.isFinite(invN) && invN > 0 ? Math.trunc(invN) : 0;
              const stored = rule.fromText(row.activity);
              return { rank: stored ? stored.rank : rule.rank(year, deals, investments, row.researched), year: year, deals: deals };
            };
            const ap = pack(a);
            const bp = pack(b);
            if (!ap || !bp) {
              if (ap === bp) return String(a.name || '').localeCompare(String(b.name || ''));
              return ap ? -1 : 1;
            }
            let d = ap.rank - bp.rank;
            if (!d) d = ap.year - bp.year;
            if (!d) d = ap.deals - bp.deals;
            if (d) return d * dir;
            return String(a.name || '').localeCompare(String(b.name || '')) * dir;
          }
          let d = 0;
          if (sort === 'name') d = String(a.name || '').localeCompare(String(b.name || ''));
          else {
            d = stamp(a.added) - stamp(b.added);
          }
          if (!d) d = String(a.name || '').localeCompare(String(b.name || ''));
          return d * dir;
        });
      }
      function headerCell(key, label) {
        const on = sort === key;
        const arrow = on ? (asc ? '↑' : '↓') : '';
        return '<button type="button" data-sort="' + key + '" class="' + (on ? 'sorted' : '') + '" aria-sort="'
          + (on ? (asc ? 'ascending' : 'descending') : 'none') + '">'
          + esc(label) + (arrow ? '<span class="arrow">' + arrow + '</span>' : '') + '</button>';
      }
      function headHtml() {
        return '<div class="frow h" role="row">'
          + headerCell('name', pageCopy.col_firm || 'Investor')
          + headerCell('city', pageCopy.col_city || 'Based in')
          + '<span class="hunsortable">' + esc(pageCopy.col_invests || 'Invests in') + '</span>'
          + headerCell('deals', pageCopy.col_investments || 'Deals')
          + headerCell('activity', pageCopy.col_activity || 'Activity')
          + headerCell('deal', pageCopy.col_deal || 'Latest deal')
          + headerCell('newest', pageCopy.col_added || 'Added')
          + '</div>';
      }

      let chips = [];
      const placeholder = (q && q.getAttribute('placeholder')) || '';
      const miss = document.getElementById('firms-miss');
      const missForm = document.getElementById('firms-miss-form');
      const missMsg = document.getElementById('firms-miss-msg');
      const noneText = none ? none.textContent : '';
      const missOut = (miss && miss.getAttribute('data-out')) || '';
      const missIn = (miss && miss.getAttribute('data-in')) || '';
      const jsCopy = (C.copy && C.copy.js) || {};
      const watched = new Set();
      let signedIn = false;
      let idleTimer = null;
      const sb = C.url && C.key && window.supabase ? window.supabase.createClient(C.url, C.key) : null;

      function anonKey() {
        const k = 'regretamin.anon';
        let a = localStorage.getItem(k);
        if (!a) { a = crypto.randomUUID(); localStorage.setItem(k, a); }
        return a;
      }
      function cachedToken() {
        try {
          const ref = (String(C.url || '').match(/https:\/\/([^.]+)/) || [])[1];
          if (!ref) return '';
          const raw = localStorage.getItem('sb-' + ref + '-auth-token');
          if (!raw) return '';
          return (JSON.parse(raw) || {}).access_token || '';
        } catch (e) { return ''; }
      }
      const loggedTerms = new Set();
      let lastResult = null;
      let wantLog = null;
      let missTerms = [];
      function setMissMsg(text, bad) {
        if (!missMsg) return;
        missMsg.textContent = text || '';
        if (missMsg.classList && typeof missMsg.classList.toggle === 'function') missMsg.classList.toggle('err', !!bad);
      }
      function watchTerm(term, email) {
        const key = String(term || '').trim().toLowerCase();
        if (!key || key.length < 2 || !C.url || !C.key) return Promise.resolve(null);
        if (!email && watched.has(key)) return Promise.resolve({ status: 'ok', already: true });
        const token = cachedToken();
        return fetch(C.url + '/rest/v1/rpc/v2_watch_firm', {
          method: 'POST',
          headers: { apikey: C.key, Authorization: 'Bearer ' + (token || C.key), 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_term: String(term || '').trim().slice(0, 100), p_email: email || null, p_anon: anonKey() })
        }).then(function (r) {
          return r.json().then(function (data) {
            if (r.ok && data && data.status === 'ok' && !email) watched.add(key);
            return r.ok ? data : null;
          }).catch(function () { return null; });
        }).catch(function () { return null; });
      }
      function filtersOn() {
        return !!place || Object.keys(active).some(function (k) { return active[k].length; });
      }
      function rawTerms() {
        const terms = chips.map(function (c) { return String(c || '').trim(); }).filter(Boolean);
        const typed = q && q.value ? q.value.trim() : '';
        if (typed) terms.push(typed);
        return terms;
      }
      function searchKey() {
        return searchTerms().join('\n');
      }
      function paintSearch(totalCount) {
        const terms = rawTerms().filter(function (t) { return t.length >= 2; });
        const show = terms.length > 0 && totalCount === 0 && !filtersOn();
        missTerms = show ? terms : [];
        if (none) {
          none.hidden = totalCount !== 0;
          none.textContent = show ? (signedIn ? missIn : missOut) : noneText;
        }
        if (missForm) missForm.hidden = !show || signedIn;
        if (miss) miss.hidden = (!show || signedIn) && !(missMsg && missMsg.textContent);
        if (!show) setMissMsg('');
        if (show && signedIn) terms.forEach(function (t) { watchTerm(t); });
      }
      function flushLog(result) {
        if (!wantLog || !result || wantLog.key !== result.key) return;
        const terms = wantLog.terms;
        wantLog = null;
        const log = window.RegretSearch && window.RegretSearch.logSearch;
        terms.forEach(function (term) {
          const key = term.toLowerCase();
          if (loggedTerms.has(key)) return;
          loggedTerms.add(key);
          if (!log) return;
          try { log(term, location.pathname || '/', result.total, result.slug); } catch (e) {}
        });
      }
      function armLog() {
        const terms = rawTerms().filter(function (t) { return t.length >= 2 && !loggedTerms.has(t.toLowerCase()); });
        if (!terms.length) return;
        wantLog = { key: searchKey(), terms: terms };
        if (lastResult && lastResult.key === wantLog.key) flushLog(lastResult);
      }
      function queueSettle() {
        clearTimeout(idleTimer);
        const typed = q && q.value ? q.value.trim() : '';
        if (typed.length < 2) return;
        idleTimer = setTimeout(function () {
          if (!q || q.value.trim() !== typed) return;
          if (!remote) { armLog(); return; }
          const t = typed.toLowerCase();
          if (firmFor !== t) return;  // the hints for this text have not come back
          const m = hintMatches(t);
          if (m.places.length || m.sectors.length || m.firms.length) { logTyped(typed); return; }
          typedLive = true;  // nothing to choose from: search the list for it, which shows the "not here yet" message
          hideHints();
          armLog();
          draw();
        }, 1500);
      }
      function notePageResult(key, totalCount, slug) {
        lastResult = { key: key, total: totalCount, slug: slug || null };
        flushLog(lastResult);
        paintSearch(totalCount);
      }

      function searchTerms() {
        const terms = chips.map(function (c) { return c.toLowerCase(); });
        // With the list on the server, typed text is not a search until Enter makes it a tag. One exception (typedLive):
        // a name that matches no firm, place or sector is searched after a pause, so "we don't have this firm yet" still shows.
        const typed = (!remote || typedLive) && q && q.value ? q.value.trim().toLowerCase() : '';
        if (typed) terms.push(typed);
        return terms;
      }
      function filterLabel(key, val) {
        const o = (GROUPS[key].options || []).filter(function (x) { return x.value === val; })[0];
        return (o && (o.tag || o.label)) || val;
      }
      function renderChips() {
        const el = document.getElementById('firms-chips');
        if (!el) return;
        const tags = [];
        if (place) tags.push('<span class="firms-chip firms-tag"><span class="firms-chip-text">' + esc(place.name) + '</span>'
          + '<button type="button" data-place-x aria-label="Remove ' + esc(place.name) + '">×</button></span>');
        if (dealOn()) tags.push('<span class="firms-chip firms-tag"><span class="firms-chip-text">' + esc(deal.label) + '</span>'
          + '<button type="button" data-deal-x aria-label="Remove ' + esc(deal.label) + '">×</button></span>');
        Object.keys(active).forEach(function (key) {
          active[key].forEach(function (val) {
            const label = filterLabel(key, val);
            tags.push('<span class="firms-chip firms-tag"><span class="firms-chip-text">' + esc(label) + '</span>'
              + '<button type="button" data-tag-key="' + esc(key) + '" data-tag-val="' + esc(val) + '" aria-label="Remove ' + esc(label) + '">×</button></span>');
          });
        });
        el.innerHTML = tags.join('') + chips.map(function (c, i) {
          return '<span class="firms-chip"><span class="firms-chip-text">' + esc(c) + '</span>'
            + '<button type="button" data-chip-x="' + i + '" aria-label="Remove ' + esc(c) + '">×</button></span>';
        }).join('');
        if (q) q.placeholder = (chips.length || tags.length) ? '' : placeholder;
        paintClear();
      }
      function paintClear() {
        const btn = document.getElementById('firms-clear');
        if (btn) btn.hidden = !(chips.length || filtersOn() || (q && q.value.trim()));
      }
      function clearAll() {
        chips = [];
        menuKey = null;
        if (q) q.value = '';
        typedLive = false;
        Object.keys(active).forEach(function (key) { active[key] = []; });
        place = null;
        deal = null;
        closePanel();
        updateBadge();
        draw();
      }
      function addChip(raw) {
        const t = String(raw || '').trim();
        if (!t) return false;
        const key = t.toLowerCase();
        if (chips.some(function (c) { return c.toLowerCase() === key; })) return false;
        chips.push(t);
        if (q) q.value = '';
        renderChips();
        return true;
      }
      function removeChip(i) {
        if (i < 0 || i >= chips.length) return;
        chips.splice(i, 1);
        renderChips();
      }
      function commitTyped() {
        if (!q) return;
        const parts = q.value.split(',');
        let added = false;
        parts.forEach(function (part) { if (addChip(part)) added = true; });
        if (q) q.value = '';
        if (added) renderChips();
      }
      const PAGE = 100;
      let offset = 0;
      let total = 0;
      let loading = false;
      let done = false;
      let gen = 0;
      let seen = {};
      let localShown = [];
      let searchTimer = 0;
      const moreEl = document.getElementById('firms-more');
      const loadingText = (moreEl && moreEl.getAttribute('data-loading')) || pageCopy.loading || 'Loading more investors';
      const endText = (moreEl && moreEl.getAttribute('data-end')) || pageCopy.end || 'End of the list';
      function showStatus() {
        if (!moreEl) return;
        if (loading) {
          moreEl.hidden = false;
          moreEl.textContent = loadingText;
        } else if (done && total > 0) {
          moreEl.hidden = false;
          moreEl.textContent = endText;
        } else {
          moreEl.hidden = true;
          moreEl.textContent = '';
        }
      }
      function appendRows(rows) {
        const html = rows.filter(function (f) {
          const slug = f && f.slug;
          if (!slug || seen[slug]) return false;
          seen[slug] = true;
          return true;
        }).map(row).join('');
        if (rows.some(function (f) { return f && f.deals_this_year != null && f.deals_this_year !== ''; })) {
          list.classList.add('has-activity');
        }
        if (!html) return;
        if (typeof list.insertAdjacentHTML === 'function') list.insertAdjacentHTML('beforeend', html);
        else list.innerHTML += html;
      }
      function nearBottom() {
        const el = document.getElementById('firms-sentinel');
        if (!el || typeof el.getBoundingClientRect !== 'function') return false;
        const r = el.getBoundingClientRect();
        if (!r || (!r.top && !r.bottom && !r.height)) return false;
        return r.top < (window.innerHeight || 800) + 240;
      }
      function byCount(a, b) { return (b.count - a.count) || String(a.label || '').localeCompare(String(b.label || '')); }
      function applyFacets(facets) {
        const regionCounts = {};
        (facets.region || []).forEach(function (o) { regionCounts[o.value] = Number(o.count) || 0; });
        if (Array.isArray(facets.map_region) && facets.map_region.length) {
          // The Region filter speaks the map's language. A region that arrived from the map as a tag becomes an ordinary choice.
          if (!mapRegions) {
            const had = active.region.length;
            mapRegions = true;
            active.region = [];
            if (place && place.level === 'world' && !deal) { active.region = [place.p]; place = null; }
            if (had) setTimeout(draw, 0);
          }
          GROUPS.region.options = facets.map_region.map(function (o) {
            return { value: String(o.value), label: String(o.value), count: Number(o.count) || 0 };
          }).sort(byCount);
        } else {
          GROUPS.region.options = REGION_OPTIONS.map(function (pair) {
            return { value: pair[0], label: pair[1], count: regionCounts[pair[0]] || 0 };
          }).sort(byCount);
        }
        function opts(list) {
          return (list || []).map(function (o) {
            return { value: o.value, label: o.label || o.value, count: Number(o.count) || 0 };
          }).sort(byCount);
        }
        GROUPS.industry.options = opts(facets.industry);
        GROUPS.stage.options = opts(facets.stage);
        const statusCounts = {};
        (facets.status || []).forEach(function (o) {
          const v = String(o.value);
          if (v === '0' || v === '1' || v === '2' || v === '3') statusCounts[v] = Number(o.count) || 0;
        });
        GROUPS.status.options = activityOptions(statusCounts);
        [['signal', facets.signals], ['dealsyear', facets.deals_year]].forEach(function (pair) {
          const counts = {};
          (pair[1] || []).forEach(function (o) { counts[String(o.value)] = Number(o.count) || 0; });
          GROUPS[pair[0]].options.forEach(function (o) { o.count = counts[o.value] || 0; });
        });
        renderFacets();
        if (panel && !panel.hidden && panelKey) renderPanel();
      }
      function fetchPage(token) {
        const pageOffset = offset;
        const key = searchKey();
        const body = {
          p_limit: PAGE,
          p_offset: offset,
          p_sort: sort,
          p_asc: asc,
          p_search: searchTerms(),
          p_region: mapRegions ? [] : active.region,
          p_industry: active.industry,
          p_stage: active.stage,
          p_legal: [],
          p_info: [],
          p_status: active.status,
          p_signals: active.signal,
          p_deals_year: active.dealsyear[0] || null,
          p_place_level: place && place.level !== 'city' ? place.level : null,
          p_place: place && place.level !== 'city' ? place.p : null,
          p_city: place && place.level === 'city' ? [place.p] : []
        };
        if (dealOn()) {
          // The map's rule: firms based in the place that did deals in these sectors and stages in the period.
          body.p_industry = [];
          body.p_stage = [];
          body.p_deal_from = deal.from;
          body.p_deal_to = deal.to;
          body.p_deal_firms = deal.who;
          body.p_deal_sectors = active.industry.map(function (v) { return deal.names[v] || filterLabel('industry', v); });
          body.p_deal_stages = Array.from(new Set(active.stage.map(function (v) { return DEAL_STAGE[v] || v; })));
        }
        if (mapRegions) body.p_map_region = active.region;
        loading = true;
        showStatus();
        fetch(C.url + '/rest/v1/rpc/firm_directory_page_v5', {
          method: 'POST',
          headers: { apikey: C.key, Authorization: 'Bearer ' + C.key, 'Content-Type': 'application/json' },
          body: JSON.stringify(body)
        }).then(function (r) {
          if (!r.ok) throw new Error('firm_directory_page');
          return r.json();
        }).then(function (payload) {
          if (token !== gen) return;
          const data = typeof payload === 'string' ? JSON.parse(payload) : (payload || {});
          const rows = Array.isArray(data.rows) ? data.rows : [];
          total = Number(data.total) || 0;
          paintCount();
          if (data.facets) { applyFacets(data.facets); renderChips(); }
          appendRows(rows);
          offset += rows.length;
          done = rows.length === 0 || offset >= total;
          loading = false;
          if (pageOffset === 0) notePageResult(key, total, rows[0] && rows[0].slug);
          else if (none) none.hidden = total !== 0;
          showStatus();
          if (!done && nearBottom()) more();
        }).catch(function () {
          if (token !== gen) return;
          loading = false;
          done = true;
          showStatus();
        });
      }
      function appendLocal() {
        const first = offset === 0;
        const key = searchKey();
        const slice = localShown.slice(offset, offset + PAGE);
        appendRows(slice);
        offset += slice.length;
        done = offset >= total;
        loading = false;
        if (first) notePageResult(key, total, localShown[0] && localShown[0].slug);
        else if (none) none.hidden = total !== 0;
        showStatus();
        if (!done && slice.length && nearBottom()) appendLocal();
      }
      function more() {
        if (loading || done) return;
        if (remote) fetchPage(gen);
        else appendLocal();
      }
      function draw() {
        clearTimeout(searchTimer);
        seen = {};
        offset = 0;
        done = false;
        list.classList.remove('has-activity');
        list.innerHTML = headHtml();
        if (none) none.hidden = true;
        if (remote) {
          const token = ++gen;
          total = 0;
          fetchPage(token);
          return;
        }
        const terms = searchTerms();
        localShown = sorted(firms.filter(function (f) {
          return matchesFilters(f) && (!terms.length || terms.some(function (t) { return searchMatch(f, t); }));
        }));
        total = localShown.length;
        paintCount();
        loading = false;
        gen += 1;
        appendLocal();
      }
      function watchScroll() {
        const el = document.getElementById('firms-sentinel');
        if (!el || typeof window.IntersectionObserver !== 'function') return;
        const io = new window.IntersectionObserver(function (entries) {
          if (entries.some(function (e) { return e.isIntersecting; })) more();
        }, { rootMargin: '0px 0px 240px 0px' });
        io.observe(el);
      }
      function toggleFacet(key, val, on) {
        active[key] = GROUPS[key].single
          ? (on ? [val] : [])
          : on
            ? Array.from(new Set(active[key].concat([val])))
            : active[key].filter(function (x) { return x !== val; });
        renderFacets();
        updateBadge();
        draw();
      }
      function boxRect(el) {
        if (!el || typeof el.getBoundingClientRect !== 'function') return { top: 8, right: 8, bottom: 8, left: 8 };
        return el.getBoundingClientRect();
      }
      function positionPanel() {
        if (!panel || !panelKey) return;
        const box = (panel.querySelector && panel.querySelector('.facet-panel-box')) || panel;
        const margin = 8;
        const vh = window.innerHeight || 800;
        const vw = window.innerWidth || 1280;
        if (vw <= 900) {
          panel.style.left = '8px';
          panel.style.right = '8px';
          panel.style.top = 'auto';
          panel.style.bottom = '8px';
          panel.style.width = 'auto';
          panel.style.maxHeight = '';
          if (box.style) box.style.maxHeight = 'calc(100dvh - 16px)';
          return;
        }
        const facet = document.getElementById('facet-' + panelKey);
        if (!facet) return;
        const f = boxRect(facet);
        const pw = Math.min(420, vw - 24);
        let left = f.left;
        if (left + pw > vw - margin) left = Math.max(margin, vw - pw - margin);
        panel.style.right = 'auto';
        panel.style.bottom = 'auto';
        panel.style.width = pw + 'px';
        panel.style.maxHeight = '';
        panel.style.left = left + 'px';
        const top = Math.max(margin, f.bottom + 6);
        panel.style.top = top + 'px';
        if (box.style) box.style.maxHeight = Math.max(200, Math.min(520, vh - margin - top)) + 'px';
      }
      function renderPanel() {
        if (!panelKey) return;
        const opts = GROUPS[panelKey].options;
        const query = (document.getElementById('facet-search').value || '').toLowerCase();
        const selected = opts.filter(function (o) { return draft.indexOf(o.value) !== -1; });
        const remaining = opts.filter(function (o) {
          return draft.indexOf(o.value) === -1 && o.label.toLowerCase().indexOf(query) !== -1;
        });
        // Show all for Industries only. The sidebar stays top 5 by count.
        if (panelKey === 'industry') {
          const byLabel = function (a, b) {
            return String(a.label || '').localeCompare(String(b.label || ''), undefined, { sensitivity: 'base' });
          };
          selected.sort(byLabel);
          remaining.sort(byLabel);
        }
        document.getElementById('pinned-options').innerHTML = selected.length
          ? '<div class="list-caption">SELECTED <span>' + selected.length + '</span></div><div class="panel-option-grid">'
            + selected.map(function (o) { return facetOption(o, panelKey, true); }).join('') + '</div>'
          : '';
        document.getElementById('remaining-label').textContent = query
          ? 'MATCHING OPTIONS · ' + remaining.length
          : 'ALL ' + GROUPS[panelKey].title.toUpperCase() + ' · ' + remaining.length;
        document.getElementById('full-options').innerHTML = remaining.length
          ? remaining.map(function (o) { return facetOption(o, panelKey, true); }).join('')
          : '<p class="empty-options">No matching options</p>';
        document.getElementById('draft-count').textContent = draft.length + ' selected';
      }
      function openPanel(key) {
        panelKey = key;
        draft = active[key].slice();
        panel.hidden = false;
        document.getElementById('facet-search').value = '';
        document.getElementById('panel-title').textContent = GROUPS[key].title;
        document.getElementById('panel-total').textContent = GROUPS[key].options.length + ' options';
        document.getElementById('facet-search').placeholder = 'Search ' + GROUPS[key].singular;
        renderFacets();
        renderPanel();
        positionPanel();
      }
      function closePanel() {
        if (panel) panel.hidden = true;
        panelKey = null;
        renderFacets();
      }
      function applyPanel() {
        if (!panelKey) return;
        active[panelKey] = draft.slice();
        closePanel();
        updateBadge();
        draw();
      }
      function openMobile() {
        if (pageRoot) pageRoot.classList.add('filters-open');
        if (backdrop) backdrop.hidden = false;
        if (openBtn) openBtn.setAttribute('aria-expanded', 'true');
      }
      function closeMobile() {
        if (pageRoot) pageRoot.classList.remove('filters-open');
        if (backdrop) backdrop.hidden = true;
        if (openBtn) openBtn.setAttribute('aria-expanded', 'false');
      }

      groupsEl.addEventListener('change', function (e) {
        const input = e.target.closest('input[type="checkbox"]');
        if (!input) return;
        const label = input.closest('label');
        if (!label) return;
        toggleFacet(label.getAttribute('data-facet'), label.getAttribute('data-value'), input.checked);
      });
      groupsEl.addEventListener('click', function (e) {
        const btn = e.target.closest('.show-all');
        if (btn) {
          menuKey = null;
          openPanel(btn.getAttribute('data-open'));
          return;
        }
        const drop = e.target.closest('.fdrop');
        if (!drop) return;
        const key = drop.getAttribute('data-drop');
        if (panel && !panel.hidden) closePanel();
        menuKey = menuKey === key ? null : key;
        renderFacets();
      });
      panel.addEventListener('change', function (e) {
        const input = e.target.closest('input[type="checkbox"]');
        if (!input || !input.hasAttribute('data-draft')) return;
        const label = input.closest('label');
        const val = label.getAttribute('data-value');
        draft = input.checked
          ? Array.from(new Set(draft.concat([val])))
          : draft.filter(function (x) { return x !== val; });
        renderPanel();
      });
      document.getElementById('panel-close').addEventListener('click', closePanel);
      document.getElementById('panel-clear').addEventListener('click', function () { draft = []; renderPanel(); });
      document.getElementById('panel-apply').addEventListener('click', applyPanel);
      document.getElementById('facet-search').addEventListener('input', renderPanel);
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') { menuKey = null; closePanel(); closeMobile(); }
      });
      document.addEventListener('mousedown', function (e) {
        if (panel && !panel.hidden && !panel.contains(e.target) && !e.target.closest('.show-all')) closePanel();
        if (menuKey && !e.target.closest('#facet-groups')) { menuKey = null; renderFacets(); }
      });
      if (openBtn) openBtn.addEventListener('click', function () {
        if (pageRoot && pageRoot.classList.contains('filters-open')) closeMobile();
        else openMobile();
      });
      if (backdrop) backdrop.addEventListener('click', closeMobile);
      window.addEventListener('resize', function () {
        if (panel && !panel.hidden) positionPanel();
        if (window.innerWidth > 900) closeMobile();
      });
      window.addEventListener('scroll', function () {
        if (panel && !panel.hidden) positionPanel();
      }, { passive: true });
      const clearBtn = document.getElementById('firms-clear');
      if (clearBtn) clearBtn.addEventListener('click', function (e) {
        e.preventDefault();
        clearAll();
        if (q) q.focus();
      });
      list.addEventListener('click', function (e) {
        const btn = e.target.closest('.frow.h [data-sort]');
        if (!btn) return;
        e.preventDefault();
        const key = btn.getAttribute('data-sort');
        if (sort === key) asc = !asc;
        else {
          sort = key;
          asc = (key === 'name' || key === 'city');
        }
        draw();
      });
      // ---- Hints under the search bar: the places, sectors and firms that match what is typed. Nothing in the list moves
      // until one is chosen, or until Enter turns the typed word into a tag (founder, 23 Nov).
      let hintBox = null, hintItems = [], hintAt = -1, hintTimer = 0, hintSeq = 0, placeList = null, placesAsked = false, firmHits = [], firmFor = '';
      const PIN = '<svg class="fh-ic" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21s7-6.1 7-11.5A7 7 0 0 0 5 9.5C5 14.9 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.4"/></svg>';
      const BLD = '<svg class="fh-ic" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="3" width="16" height="18" rx="2"/><path d="M9 8h1M14 8h1M9 12h1M14 12h1M10 21v-4h4v4"/></svg>';
      function rpc(name, args) {
        return fetch(C.url + '/rest/v1/rpc/' + name, { method: 'POST', headers: { apikey: C.key, Authorization: 'Bearer ' + C.key, 'Content-Type': 'application/json' }, body: JSON.stringify(args) })
          .then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; });
      }
      // Every place that has a firm (the map's regions and US areas, and the cities on firm profiles), fetched once.
      function loadPlaces() {
        if (placesAsked || !remote) return;
        placesAsked = true;
        rpc('firm_place_suggest', { p_q: '', p_limit: 3000 }).then(function (d) {
          placeList = Array.isArray(d) ? d : [];
          // Countries arrive as two-letter codes; the browser knows their names.
          let names = null;
          try { names = new Intl.DisplayNames(['en'], { type: 'region' }); } catch (e) {}
          placeList.forEach(function (x) {
            if (x.kind !== 'country') return;
            let n = '';
            try { n = names ? names.of(x.p) : ''; } catch (e) {}
            x.name = n && n !== x.p ? n : x.p;
          });
          if (hintBox && !hintBox.hidden) paintHints();
        });
      }
      function hintRank(name, t) { const n = String(name || '').toLowerCase(); return n.indexOf(t) === 0 ? 2 : n.indexOf(' ' + t) !== -1 ? 1 : 0; }
      function hintMark(name, t) {
        const n = String(name || ''), i = n.toLowerCase().indexOf(t);
        return i === -1 ? esc(n) : esc(n.slice(0, i)) + '<mark>' + esc(n.slice(i, i + t.length)) + '</mark>' + esc(n.slice(i + t.length));
      }
      function firmsWord(n) { return Number(n || 0).toLocaleString('en-US') + (Number(n) === 1 ? ' firm' : ' firms'); }
      function hintMatches(t) {
        const top = function (list, nameOf, max) {
          return list.map(function (x) { return [hintRank(nameOf(x), t), x]; }).filter(function (p) { return p[0]; })
            .sort(function (a, b) { return b[0] - a[0] || (b[1].count || 0) - (a[1].count || 0); }).slice(0, max).map(function (p) { return p[1]; });
        };
        return {
          places: top(placeList || [], function (x) { return x.name; }, 3),
          sectors: top((GROUPS.industry.options || []).filter(function (o) { return active.industry.indexOf(o.value) === -1; }), function (o) { return o.label; }, 3),
          firms: firmFor === t ? firmHits.slice(0, 4) : []
        };
      }
      // Search demand is still recorded for a typed name that had hints (as the search bar on other pages does).
      function logTyped(typed) {
        const key = typed.toLowerCase();
        if (loggedTerms.has(key)) return;
        loggedTerms.add(key);
        const log = window.RegretSearch && window.RegretSearch.logSearch;
        if (!log) return;
        try { log(typed, location.pathname || '/', firmHits.length, firmHits[0] ? firmHits[0].slug : null); } catch (e) {}
      }
      function hideHints() { if (hintBox) hintBox.hidden = true; hintItems = []; hintAt = -1; if (q) q.setAttribute('aria-expanded', 'false'); }
      function paintHints() {
        const t = q.value.trim().toLowerCase();
        if (!hintBox || t.length < 2) return hideHints();
        const m = hintMatches(t), places = m.places, sectors = m.sectors, firms = m.firms;
        hintItems = [];
        const row = function (item, icon, name, right) {
          const i = hintItems.push(item) - 1;
          return '<button type="button" role="option" class="fh-row' + (i === hintAt ? ' on' : '') + '" data-hint="' + i + '">' + icon + '<b>' + hintMark(name, t) + '</b><span class="fh-r">' + esc(right) + '</span></button>';
        };
        const parts = [];
        if (places.length) parts.push('<h5>Places <span>adds a filter</span></h5>' + places.map(function (x) { return row({ type: 'place', place: x }, PIN, x.name, firmsWord(x.count)); }).join(''));
        if (sectors.length) parts.push('<h5>Sectors <span>adds a filter</span></h5>' + sectors.map(function (o) { return row({ type: 'sector', value: o.value }, '<i class="fh-dot" style="background:' + sectorColor(o.label) + '"></i>', o.label, firmsWord(o.count)); }).join(''));
        if (firms.length) parts.push('<h5>Firms <span>opens the firm</span></h5>' + firms.map(function (f) { return row({ type: 'firm', slug: f.slug }, BLD, f.name, f.hq || ''); }).join(''));
        parts.push('<div class="fh-foot"><kbd>Enter</kbd> shows every firm with “' + esc(q.value.trim()) + '” in its name</div>');
        hintBox.innerHTML = parts.join('<hr>');
        hintBox.hidden = false;
        q.setAttribute('aria-expanded', 'true');
      }
      function askHints() {
        const t = q.value.trim().toLowerCase();
        if (t.length < 2) return hideHints();
        hintAt = -1;
        if (!typedLive) paintHints();
        const n = ++hintSeq;
        rpc('firm_suggest', { q: t }).then(function (d) {
          if (n !== hintSeq) return;
          firmHits = Array.isArray(d) ? d : [];
          firmFor = t;
          if (q.value.trim().toLowerCase() === t && !typedLive && document.activeElement === q) paintHints();
        });
      }
      function pickHint(item) {
        if (!item) return;
        if (item.type === 'firm') { location.href = href(item.slug); return; }
        if (item.type === 'sector') {
          if (active.industry.indexOf(item.value) === -1) active.industry = active.industry.concat([item.value]);
        } else {
          const x = item.place;
          deal = null;  // a place chosen by hand is an ordinary filter, not the map's deals view
          if (x.kind === 'region' && mapRegions) { place = null; if (active.region.indexOf(x.p) === -1) active.region = active.region.concat([x.p]); }
          else place = { level: x.level, p: x.p, name: x.name };
        }
        q.value = '';
        hideHints();
        renderFacets();
        updateBadge();
        renderChips();
        draw();
      }
      if (q && remote && typeof document.createElement === 'function') {
        hintBox = document.createElement('div');
        hintBox.className = 'fhints';
        hintBox.id = 'firms-hints';
        hintBox.setAttribute('role', 'listbox');
        hintBox.hidden = true;
        const holder = q.closest ? q.closest('.firms-search-hero') : null;
        if (holder) holder.appendChild(hintBox); else hintBox = null;
        if (hintBox) {
          q.setAttribute('aria-controls', 'firms-hints');
          q.setAttribute('aria-expanded', 'false');
          hintBox.addEventListener('mousedown', function (e) { e.preventDefault(); });  // keep the cursor in the bar
          hintBox.addEventListener('click', function (e) {
            const b = e.target.closest('[data-hint]');
            if (b) pickHint(hintItems[Number(b.getAttribute('data-hint'))]);
          });
          q.addEventListener('focus', function () { loadPlaces(); if (q.value.trim().length >= 2) askHints(); });
          q.addEventListener('blur', function () { setTimeout(hideHints, 150); });
        }
      }
      if (q) {
        q.addEventListener('input', function () {
          let chipsChanged = false;
          if (q.value.indexOf(',') !== -1) {
            const parts = q.value.split(',');
            const rest = parts.pop();
            let added = false;
            parts.forEach(function (part) { if (addChip(part)) added = true; });
            q.value = rest.replace(/^\s+/, '');
            if (added) { renderChips(); chipsChanged = true; }
          }
          queueSettle();
          paintClear();
          clearTimeout(searchTimer);
          if (chipsChanged) armLog();
          if (chipsChanged || !remote) draw();
          // With the list on the server, typing only brings hints; the rows wait for a choice or for Enter.
          if (remote) {
            if (typedLive) { typedLive = false; draw(); }  // the text changed: the list goes back to what the tags say
            clearTimeout(hintTimer);
            hintTimer = setTimeout(askHints, 120);
          }
        });
        q.addEventListener('keydown', function (e) {
          if (e.isComposing || e.keyCode === 229) return;
          if (hintBox && !hintBox.hidden) {
            if (e.key === 'Escape') { hideHints(); return; }
            if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && hintItems.length) {
              e.preventDefault();
              hintAt = e.key === 'ArrowDown' ? (hintAt + 1) % hintItems.length : (hintAt <= 0 ? hintItems.length : hintAt) - 1;
              paintHints();
              return;
            }
            if (e.key === 'Enter' && hintAt >= 0) { e.preventDefault(); clearTimeout(hintTimer); pickHint(hintItems[hintAt]); return; }
          }
          if (e.key === 'Enter') {
            e.preventDefault();
            clearTimeout(idleTimer);
            clearTimeout(searchTimer);
            clearTimeout(hintTimer);
            hideHints();
            typedLive = false;
            if (q.value.trim()) {
              commitTyped();
              armLog();
              draw();
            }
          } else if (e.key === 'Backspace' && !q.value && chips.length) {
            e.preventDefault();
            removeChip(chips.length - 1);
            if (q) q.focus();
            draw();
          }
        });
      }
      const chipBox = document.getElementById('firms-chips');
      if (chipBox) chipBox.addEventListener('click', function (e) {
        if (e.target.closest('[data-deal-x]')) {
          e.preventDefault();
          e.stopPropagation();
          deal = null;
          if (place && place.level === 'world' && mapRegions) { active.region = [place.p]; place = null; renderFacets(); }
          updateBadge();
          draw();
          return;
        }
        if (e.target.closest('[data-place-x]')) {
          e.preventDefault();
          e.stopPropagation();
          place = null;
          deal = null;
          updateBadge();
          draw();
          return;
        }
        const tag = e.target.closest('[data-tag-key]');
        if (tag) {
          e.preventDefault();
          e.stopPropagation();
          toggleFacet(tag.getAttribute('data-tag-key'), tag.getAttribute('data-tag-val'), false);
          return;
        }
        const btn = e.target.closest('[data-chip-x]');
        if (!btn) return;
        e.preventDefault();
        e.stopPropagation();
        removeChip(Number(btn.getAttribute('data-chip-x')));
        if (q) q.focus();
        draw();
      });

      if (missForm) missForm.addEventListener('submit', function (e) {
        e.preventDefault();
        const email = missForm.email.value.trim();
        const terms = missTerms.slice();
        const btn = missForm.querySelector('button');
        if (!terms.length || !email) return;
        if (btn) btn.disabled = true;
        Promise.all(terms.map(function (t) { return watchTerm(t, email); })).then(function (rows) {
          const data = rows.filter(Boolean);
          const st = (data.find(function (r) { return r.status && r.status !== 'ok'; }) || data[0] || {}).status || '';
          const allAlready = data.length > 0 && data.every(function (r) { return r.status === 'ok' && r.already; });
          const bad = !data.length || st === 'bad_email' || st === 'rate_limited' || st === 'ignored';
          const text = bad ? (st === 'bad_email' ? jsCopy.req_bad_email : st === 'rate_limited' ? jsCopy.req_rate : jsCopy.error)
            : allAlready ? jsCopy.req_dup
            : jsCopy.notify_ok;
          setMissMsg(text || jsCopy.error, bad);
          if (miss) miss.hidden = false;
          if (btn) btn.disabled = false;
        });
      });
      if (sb) {
        sb.auth.getSession().then(function (res) {
          signedIn = !!(res && res.data && res.data.session);
          if (signedIn && lastResult && lastResult.total === 0) paintSearch(0);
        }).catch(function () {});
        sb.auth.onAuthStateChange(function (_ev, session) {
          signedIn = !!session;
          if (signedIn && lastResult && lastResult.total === 0) paintSearch(0);
        });
      }

      // A firm page's search bar sends the typed name here as ?q=, so typing carries on in this bar.
      try {
        const typed = new URLSearchParams(location.search).get('q');
        if (typed && q) {
          q.value = typed.slice(0, 80);
          if (q.focus) q.focus();
          if (q.setSelectionRange) q.setSelectionRange(q.value.length, q.value.length);
        }
      } catch (e) { /* no address to read: start with an empty bar */ }
      // The map's "See the investors" link carries what was chosen there: the place, the sectors and the stages.
      // They arrive as ordinary filters, so each shows as a tag in the bar and comes off with its ×.
      try {
        const from = new URLSearchParams(location.search);
        const many = function (k) { return (from.get(k) || '').split('|').map(function (v) { return v.trim().slice(0, 60); }).filter(Boolean).slice(0, 25); };
        const zoom = from.get('zoom'), at = (from.get('place') || '').trim().slice(0, 80);
        if (remote && at && ['world', 'us', 'eu'].indexOf(zoom) !== -1) place = { level: zoom, p: at, name: (from.get('pname') || at).trim().slice(0, 80) };
        if (remote) {
          active.industry = many('sectors').map(function (v) { return v.toLowerCase(); });
          const stages = [];
          many('stages').forEach(function (v) {
            if (v === 'Series C+') ['series c', 'series d', 'series e', 'series f'].forEach(function (x) { stages.push(x); });
            else stages.push(v.toLowerCase());
          });
          active.stage = stages;
          const day = /^\d{4}-\d{2}-\d{2}$/, df = from.get('from') || '', dt = from.get('to') || '', days = parseInt(from.get('days'), 10);
          if (place && day.test(df) && day.test(dt)) {
            const mon = function (d) { return new Date(d + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', year: 'numeric' }); };
            const names = {};
            many('sectors').forEach(function (v) { names[v.toLowerCase()] = v; });
            const who = from.get('who');
            deal = { from: df, to: dt, names: names, who: ['top', 'focused', 'new'].indexOf(who) !== -1 ? who : null,
              label: days > 0 && days < 1000 ? 'Last ' + days + ' days' : mon(df) + ' – ' + mon(dt) };
          }
        }
      } catch (e) { /* no address to read: start with no filters */ }
      renderFacets();
      updateBadge();
      watchScroll();
      draw();
    })
    .catch(function () { /* keep the empty list if firms.json is missing */ });
})();

/* Filters scroll with the page. When the sidebar is taller than the window, its sticky
   top is negative so it stops once its bottom (the last filter group) is in view, and the list
   keeps scrolling. Phones (900px or less) use the drawer instead. */
(function () {
  function fit() {
    const s = document.getElementById('firms-sidebar');
    if (!s) return;
    if (innerWidth <= 900) { s.style.top = ''; return; }
    const h = s.offsetHeight;
    s.style.top = (h + 32 > innerHeight ? innerHeight - h - 16 : 16) + 'px';
  }
  addEventListener('resize', fit);
  addEventListener('load', fit);
  document.addEventListener('DOMContentLoaded', fit);
  if (window.ResizeObserver) {
    const ro = new ResizeObserver(fit);
    ro.observe(document.documentElement);
    const s = document.getElementById('firms-sidebar');
    if (s) ro.observe(s);
  }
})();
