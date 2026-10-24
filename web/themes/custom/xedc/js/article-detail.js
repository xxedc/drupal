(function () {
  'use strict';
  function ready(fn) {
    if (document.readyState !== 'loading') { fn(); }
    else { document.addEventListener('DOMContentLoaded', fn); }
  }
  ready(function () {
    var prose = document.getElementById('xa-prose');
    if (!prose) { return; }

    // 阅读进度条
    var bar = document.createElement('div');
    bar.className = 'xa-progress';
    document.body.appendChild(bar);
    var ticking = false;
    function update() {
      var h = document.documentElement;
      var max = h.scrollHeight - h.clientHeight;
      var p = max > 0 ? (window.pageYOffset || h.scrollTop) / max : 0;
      bar.style.transform = 'scaleX(' + Math.max(0, Math.min(1, p)) + ')';
      ticking = false;
    }
    window.addEventListener('scroll', function () {
      if (!ticking) { ticking = true; requestAnimationFrame(update); }
    }, { passive: true });
    update();

    // 目录：正文有 2 个以上 h2/h3 才显示
    var heads = prose.querySelectorAll('h2, h3');
    var toc = document.querySelector('[data-xa-toc]');
    if (toc && heads.length >= 2 && 'IntersectionObserver' in window) {
      var nav = toc.querySelector('nav');
      var links = [];
      Array.prototype.forEach.call(heads, function (h, i) {
        if (!h.id) { h.id = 'xa-h-' + (i + 1); }
        var a = document.createElement('a');
        a.href = '#' + h.id;
        a.textContent = h.textContent.trim();
        if (h.tagName === 'H3') { a.className = 'is-sub'; }
        nav.appendChild(a);
        links.push(a);
      });
      toc.hidden = false;
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            links.forEach(function (l) { l.classList.remove('is-active'); });
            var idx = Array.prototype.indexOf.call(heads, e.target);
            if (links[idx]) { links[idx].classList.add('is-active'); }
          }
        });
      }, { rootMargin: '-80px 0px -70% 0px' });
      Array.prototype.forEach.call(heads, function (h) { io.observe(h); });
    }

    // 复制链接
    var btn = document.querySelector('[data-xa-copy]');
    if (btn) {
      btn.addEventListener('click', function () {
        var url = location.href.split('#')[0];
        function done() {
          var t = btn.textContent;
          btn.textContent = '已复制';
          setTimeout(function () { btn.textContent = t; }, 1500);
        }
        function fallback() {
          var i = document.createElement('input');
          i.value = url;
          document.body.appendChild(i);
          i.select();
          try { document.execCommand('copy'); done(); } catch (e) {}
          document.body.removeChild(i);
        }
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(url).then(done, fallback);
        } else { fallback(); }
      });
    }
  });
})();

/* 手机端：用系统分享 */
(function () {
  'use strict';
  function ready(fn) {
    if (document.readyState !== 'loading') { fn(); }
    else { document.addEventListener('DOMContentLoaded', fn); }
  }
  ready(function () {
    var share = document.querySelector('[data-xa-share]');
    var copy = document.querySelector('[data-xa-copy]');
    if (share && copy && navigator.share && window.matchMedia('(pointer:coarse)').matches) {
      share.hidden = false;
      copy.hidden = true;
      share.addEventListener('click', function () {
        navigator.share({ title: document.title, url: location.href.split('#')[0] }).catch(function () {});
      });
    }
  });
})();

/* 阅读量：停留 3 秒后计一次，同一会话不重复 */
(function () {
  'use strict';
  var art = document.querySelector('.xa-article[data-xa-nid]');
  if (!art || !window.fetch) { return; }
  var nid = art.getAttribute('data-xa-nid');
  var key = 'xa_hit_' + nid;
  try { if (sessionStorage.getItem(key)) { return; } } catch (e) {}
  setTimeout(function () {
    fetch('/xa/hit/' + nid, { method: 'POST', keepalive: true, credentials: 'same-origin' })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        try { sessionStorage.setItem(key, '1'); } catch (e) {}
        var el = document.querySelector('[data-xa-views]');
        if (el && d && d.counted && d.views < 10000) { el.textContent = d.views; }
      })
      .catch(function () {});
  }, 3000);
})();

/* 回到顶部 */
(function () {
  'use strict';
  function run() {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'xa-top';
    b.setAttribute('aria-label', '回到顶部');
    b.textContent = '↑';
    document.body.appendChild(b);
    var on = false;
    window.addEventListener('scroll', function () {
      var s = (window.pageYOffset || 0) > 800;
      if (s !== on) { on = s; b.classList.toggle('is-on', on); }
    }, { passive: true });
    b.addEventListener('click', function () {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }
  if (document.readyState !== 'loading') { run(); }
  else { document.addEventListener('DOMContentLoaded', run); }
})();
