// Our own visit counting (28 Nov 2026, claude/plans/admin-analytics.md): page opened, where the visitor came from, which map view they are on and for how long.
// Read only by the admin page. Sent to one database function (track_visit) that caps what it takes. No cookie: the anonymous visitor id is the one
// app.js already keeps in localStorage ("regretamin.anon"). A heartbeat every 15 s while the tab is visible; it stops when the tab is hidden and after 30 min without a touch.
(function () {
  var C = window.REGRET || {};
  if (!C.url || !C.key || !window.fetch) return;
  var ANON = 'regretamin.anon', path = location.pathname, LS = null;
  try { LS = window.localStorage; } catch (e) { return; }
  var anon = LS.getItem(ANON);
  if (!anon) { try { anon = crypto.randomUUID(); LS.setItem(ANON, anon); } catch (e) { return; } }
  if (/^\/admin(\/|$)/.test(path)) return;   // the admin page does not count itself

  function token() {   // a signed-in visitor's own key, so the database can tell it is an admin and leave the visit out
    try {
      for (var i = 0; i < LS.length; i++) {
        var k = LS.key(i);
        if (/^sb-.+-auth-token$/.test(k)) {
          var v = JSON.parse(LS.getItem(k) || 'null'), t = v && (v.access_token || (v[0] && v[0].access_token));
          if (t) return t;
        }
      }
    } catch (e) { /* no session */ }
    return C.key;
  }
  var buf = [];
  function send() {
    if (!buf.length) return;
    var ev = buf.splice(0, 10);
    try {
      fetch(C.url + '/rest/v1/rpc/track_visit', { method: 'POST', keepalive: true, headers: { 'Content-Type': 'application/json', apikey: C.key, Authorization: 'Bearer ' + token() },
        body: JSON.stringify({ p_anon: anon, p_events: ev }) }).catch(function () {});
    } catch (e) { /* never break the page */ }
  }
  function add(e) { e.p = path; buf.push(e); if (buf.length >= 10) send(); else setTimeout(send, 400); }

  var qs = new URLSearchParams(location.search), ref = '';
  try { ref = document.referrer ? new URL(document.referrer).hostname.replace(/^www\./, '') : ''; } catch (e) { ref = ''; }
  if (ref === location.hostname.replace(/^www\./, '')) ref = '';
  var src = (qs.get('utm_source') || ref || 'direct').toLowerCase();
  var m = path.match(/^\/p\/([^/]+)/), code = (m && m[1]) || qs.get('invite') || qs.get('ref') || '';
  add({ k: 'view', s: src, c: code, d: window.matchMedia && matchMedia('(max-width: 760px)').matches ? 'phone' : 'computer' });

  var MAPV = { hot: 'trends', path: 'pathfinders', pathfinders: 'pathfinders', flow: 'flow', founders: 'founders', top: 'top', trends: 'trends' };
  var view = null;
  function mapView() {
    var b = document.querySelector('.vm-views [aria-pressed="true"]');
    if (b) return MAPV[b.dataset.view] || b.dataset.view;
    return MAPV[qs.get('view')] || 'trends';
  }
  var isMap = /^\/map(\/|$)/.test(path);
  function now() { return isMap ? (view = mapView()) : null; }

  var orig = window.REGRET_TRACK;   // ga.js made it; we listen to the same calls
  window.REGRET_TRACK = function (name, params) {
    if (orig) orig.apply(this, arguments);
    try {
      if (name === 'map_view' && params && params.view) { view = MAPV[params.view] || params.view; add({ k: 'map', v: view }); }
      else if (name === 'top100_chart' && params && params.chart) add({ k: 'chart', v: params.chart });
    } catch (e) { /* ignore */ }
  };

  var last = Date.now(), idle = 30 * 60 * 1000;
  ['pointerdown', 'keydown', 'scroll', 'touchstart'].forEach(function (t) { addEventListener(t, function () { last = Date.now(); }, { passive: true }); });
  setInterval(function () {
    if (document.hidden || Date.now() - last > idle) return;
    add({ k: 'beat', v: now(), t: 15 });
  }, 15000);
  document.addEventListener('visibilitychange', function () { if (document.hidden) send(); });
})();
