(function () {
  'use strict';
  function closeAll(except) {
    document.querySelectorAll('[data-usermenu]').forEach(function (m) {
      if (m === except) { return; }
      m.querySelector('.xedc-usermenu__panel').hidden = true;
      m.querySelector('[data-usermenu-toggle]').setAttribute('aria-expanded', 'false');
    });
  }
  document.addEventListener('click', function (e) {
    var t = e.target.closest && e.target.closest('[data-usermenu-toggle]');
    if (t) {
      var m = t.closest('[data-usermenu]');
      var p = m.querySelector('.xedc-usermenu__panel');
      var open = p.hidden;
      closeAll(m);
      p.hidden = !open;
      t.setAttribute('aria-expanded', open ? 'true' : 'false');
      return;
    }
    if (!(e.target.closest && e.target.closest('[data-usermenu]'))) { closeAll(); }
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { closeAll(); } });
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('[data-usermenu] a[href*="/user/logout"]');
    if (!a || /\/user(\/|$)/.test(location.pathname)) { return; }
    var u = new URL(a.href, location.href);
    u.searchParams.set('destination', location.pathname + location.search);
    a.href = u.toString();
  });
})();
