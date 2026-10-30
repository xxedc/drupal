// * Bootstrap libraries
import './_bootstrap';

// * Any other global site-wide JavaScript should be placed below.

(() => {
  const root = document.documentElement;
  const saved = localStorage.getItem('theme');
  const preferred = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  const apply = (t) => {
    root.setAttribute('data-bs-theme', t);
    document.querySelectorAll('[data-theme-toggle]').forEach((b) => {
      b.setAttribute('aria-label', t === 'dark' ? '切换到浅色' : '切换到深色');
      b.dataset.mode = t;
    });
  };
  apply(saved || preferred);
  document.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-theme-toggle]');
    if (!btn) return;
    const next = root.getAttribute('data-bs-theme') === 'dark' ? 'light' : 'dark';
    localStorage.setItem('theme', next);
    apply(next);
  });
})();

(() => {
  const init = () => {
    const nav = document.querySelector('.xedc-nav');
    if (!nav) return;
    const burger = nav.querySelector('[data-menu-toggle]');
    const sbtn = nav.querySelector('[data-search-toggle]');
    const bar = nav.querySelector('.xedc-searchbar');
    const setMenu = (open) => {
      nav.classList.toggle('menu-open', open);
      burger.setAttribute('aria-expanded', open);
      document.body.style.overflow = open ? 'hidden' : '';
    };
    const setSearch = (open) => {
      nav.classList.toggle('search-open', open);
      sbtn.setAttribute('aria-expanded', open);
      if (open) bar.querySelector('input').focus();
    };
    burger.addEventListener('click', () => { setSearch(false); setMenu(!nav.classList.contains('menu-open')); });
    nav.querySelectorAll('[data-menu-close]').forEach((el) => el.addEventListener('click', () => setMenu(false)));
    nav.querySelectorAll('.xedc-menu a').forEach((a) => a.addEventListener('click', () => setMenu(false)));
    sbtn.addEventListener('click', () => { setMenu(false); setSearch(!nav.classList.contains('search-open')); });
    document.addEventListener('click', (e) => {
      if (!nav.classList.contains('search-open')) return;
      if (bar.contains(e.target) || sbtn.contains(e.target)) return;
      setSearch(false);
    });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { setMenu(false); setSearch(false); } });
    window.addEventListener('resize', () => { if (window.innerWidth >= 992) { setMenu(false); setSearch(false); } });
  };
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', init) : init();
})();
;(function () {
  function run() {
    var h = document.querySelector('.xedc-view-photos .view-header');
    var t = document.querySelector('.block-page-title-block h1') || document.querySelector('h1');
    if (!h || !t || document.querySelector('.photo-titlebar')) return;
    var s = document.createElement('span');
    s.className = 'photo-count';
    s.textContent = h.textContent.trim();
    var w = document.createElement('div');
    w.className = 'photo-titlebar';
    t.parentNode.insertBefore(w, t);
    w.appendChild(t);
    w.appendChild(s);
    h.style.display = 'none';
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run);
  else run();
})();

document.querySelectorAll('.cm__avatar:not(:has(img))').forEach(function (el) {
  var n = el.dataset.name || '', h = 0;
  for (var i = 0; i < n.length; i++) h = (h * 31 + n.charCodeAt(i)) % 360;
  el.style.background = 'hsl(' + h + ',55%,88%)';
  el.style.color = 'hsl(' + h + ',45%,32%)';
});

(function () {
  var E = '😀 😁 😂 🤣 😊 😍 😘 😎 🤔 😅 😭 😡 👍 👏 🙏 💪 ❤️ 🔥 🎉 🌹 😴 🤗 😏 🥰 😱 🙈 💯 ✨ 👀 🤝'.split(' ');
  var ICON = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><path d="M9 9h.01M15 9h.01"/></svg>';
  function mount() {
    document.querySelectorAll('form.comment-form').forEach(function (f) {
      var ta = f.querySelector('textarea');
      if (!ta || f.querySelector('.cm-emoji')) return;
      var w = document.createElement('div');
      w.className = 'cm-emoji';
      w.innerHTML = '<button type="button" class="cm-emoji__btn" aria-label="表情">' + ICON + '</button><div class="cm-emoji__panel" hidden></div>';
      var p = w.querySelector('.cm-emoji__panel');
      E.forEach(function (e) {
        var b = document.createElement('button');
        b.type = 'button'; b.textContent = e; p.appendChild(b);
      });
      w.querySelector('.cm-emoji__btn').onclick = function (ev) { ev.preventDefault(); p.hidden = !p.hidden; };
      p.onclick = function (ev) {
        if (ev.target.tagName !== 'BUTTON') return;
        ta.setRangeText(ev.target.textContent, ta.selectionStart, ta.selectionEnd, 'end');
        ta.focus(); p.hidden = true;
      };
      f.appendChild(w);
    });
  }
  document.addEventListener('click', function (e) {
    var a = e.target.closest('.cm__links a[href*="/comment/reply/"]');
    if (!a) return;
    var form = document.querySelector('form.comment-form');
    var art = a.closest('article.cm');
    var m = a.getAttribute('href').match(/\/comment\/reply\/node\/\d+\/field_comment\/(\d+)/);
    if (!form || !art || !m) return;
    e.preventDefault();
    var holder = document.querySelector('.cm-reply-hold');
    if (!holder) { holder = document.createElement('div'); holder.className = 'cm-reply-hold'; }
    var ta = form.querySelector('textarea');
    ta.placeholder = '回复 @' + art.querySelector('.cm__head b').textContent;
    form.action = a.getAttribute('href');
    var pid = form.querySelector('input[name="pid"]');
    if (pid) pid.value = m[1];
    art.querySelector('.cm__main').appendChild(holder);
    holder.appendChild(form);
    ta.focus();
  });
  document.addEventListener('DOMContentLoaded', mount);
  [300, 1000, 2500].forEach(function (t) { setTimeout(mount, t); });
})();

(function () {
  var box;
  function open(src) {
    if (!box) {
      box = document.createElement('div');
      box.className = 'cm-lightbox';
      box.onclick = function () { box.hidden = true; };
      document.body.appendChild(box);
    }
    box.innerHTML = '<img src="' + src + '" alt="">';
    box.hidden = false;
  }
  document.addEventListener('click', function (e) {
    var img = e.target.closest('.cm__main .field--name-field-comment-image img');
    if (!img) return;
    e.preventDefault();
    var a = img.closest('a');
    open(a ? a.href : img.src);
  });
})();

(function () {
  var PER = 10;
  function init() {
    var box = document.querySelector('.img-detail__gallery .field--name-field-images');
    if (!box || box.dataset.pg) return;
    var items = box.querySelectorAll(':scope > .field__item');
    if (items.length <= PER) return;
    box.dataset.pg = 1;
    var shown = PER;
    items.forEach(function (el, i) { if (i >= PER) el.classList.add('is-hidden'); });
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'xedc-pill img-more';
    function label() { btn.textContent = '加载更多（还剩 ' + (items.length - shown) + ' 张）'; }
    label();
    btn.onclick = function () {
      var end = Math.min(shown + PER, items.length);
      for (var i = shown; i < end; i++) items[i].classList.remove('is-hidden');
      shown = end;
      if (shown >= items.length) btn.remove(); else label();
    };
    box.parentNode.insertBefore(btn, box.nextSibling);
  }
  document.addEventListener('DOMContentLoaded', init);
})();

(function () {
  var lb, list = [], idx = 0;
  function show() {
    lb.querySelector('img').src = list[idx];
    lb.querySelector('.gl__n').textContent = (idx + 1) + ' / ' + list.length;
  }
  function open(i) {
    if (!lb) {
      lb = document.createElement('div');
      lb.className = 'gl';
      lb.hidden = true;
      lb.innerHTML = '<span class="gl__n"></span><button class="gl__x" type="button">×</button><button class="gl__p" type="button">‹</button><img alt=""><button class="gl__f" type="button">›</button>';
      document.body.appendChild(lb);
      lb.onclick = function (e) {
        if (e.target.classList.contains('gl__p')) { idx = (idx - 1 + list.length) % list.length; show(); }
        else if (e.target.classList.contains('gl__f')) { idx = (idx + 1) % list.length; show(); }
        else lb.hidden = true;
      };
    }
    idx = i; lb.hidden = false; show();
  }
  document.addEventListener('click', function (e) {
    var img = e.target.closest('.img-detail__gallery img');
    if (!img) return;
    e.preventDefault();
    var all = Array.prototype.slice.call(document.querySelectorAll('.img-detail__gallery img'));
    list = all.map(function (im) { var a = im.closest('a'); return a ? a.href : im.src; });
    open(all.indexOf(img));
  });
  document.addEventListener('keydown', function (e) {
    if (!lb || lb.hidden) return;
    if (e.key === 'Escape') lb.hidden = true;
    if (e.key === 'ArrowLeft') { idx = (idx - 1 + list.length) % list.length; show(); }
    if (e.key === 'ArrowRight') { idx = (idx + 1) % list.length; show(); }
  });
})();
