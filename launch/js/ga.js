// Google Analytics (property "Regretamin", G-FXL880RJHX). The tag itself loads from the page head (build.py GA_HEAD)
// with every Google storage set to "denied", so nothing is stored until a visitor presses Accept here.
// Without consent Google receives cookieless pings only. The choice is kept in localStorage ("rg.consent": yes / no).
// This file: the cookie bar, and the clicks we count (see EVENTS below).
(function () {
  var KEY = 'rg.consent';
  function gtag() { (window.dataLayer = window.dataLayer || []).push(arguments); }
  function get() { try { return localStorage.getItem(KEY); } catch (e) { return 'no'; } }
  function set(v) { try { localStorage.setItem(KEY, v); } catch (e) { /* private mode: ask again next visit */ } }
  function track(name, params) { gtag('event', name, params || {}); }
  window.REGRET_TRACK = track;

  function bar() {
    if (get() || document.getElementById('ckbar')) return;
    var b = document.createElement('div');
    b.id = 'ckbar';
    b.className = 'ckbar';
    b.setAttribute('role', 'region');
    b.setAttribute('aria-label', 'Cookies');
    b.innerHTML = '<p>We use Google Analytics cookies to count visits and see which pages help. No ads. '
      + '<a href="' + (window.REGRET_ROOT || '/') + 'privacy/">Privacy</a></p>'
      + '<div class="ckb"><button type="button" class="ckno">Decline</button><button type="button" class="ckyes">Accept</button></div>';
    document.body.appendChild(b);
    b.querySelector('.ckyes').addEventListener('click', function () {
      set('yes'); gtag('consent', 'update', { analytics_storage: 'granted' }); b.remove();
    });
    b.querySelector('.ckno').addEventListener('click', function () { set('no'); b.remove(); });
  }

  // Clicks we count. [selector, event name, extra params from the element]
  var slug = function () { var m = document.querySelector('main[data-firm]'); return m ? m.dataset.firm : undefined; };
  var EVENTS = [
    ['#vm-cta', 'see_investors', function () { return { from: 'map' }; }],
    ['.vm-more', 'see_investors', function () { return { from: 'map_panel' }; }],
    ['#readybtn', 'ready_click', function () { return { firm: slug() }; }],
    ['[data-save]', 'save_firm', function () { return { firm: slug() }; }]
  ];
  document.addEventListener('click', function (e) {
    var t = e.target;
    if (!t || !t.closest) return;
    for (var i = 0; i < EVENTS.length; i++) {
      var el = t.closest(EVENTS[i][0]);
      if (el) { track(EVENTS[i][1], EVENTS[i][2](el)); return; }
    }
  }, true);
  document.addEventListener('submit', function (e) {
    var f = e.target;
    if (f && f.classList && f.classList.contains('readyform')) track('ready_email', { firm: slug() });
  }, true);

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bar); else bar();
})();
