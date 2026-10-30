(function (Drupal, once) {
  'use strict';

  var GRID_SVG = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>';

  var lb = null;
  var sheet = null;
  var idx = 0;
  var sheetOpener = null;
  var locked = false;
  var scrollY = 0;

  function gallery() {
    return document.querySelector('.img-detail__gallery');
  }

  function items() {
    var box = gallery();
    if (!box) {
      return [];
    }
    try {
      var data = JSON.parse(box.getAttribute('data-img-gallery') || '[]');
      if (!Array.isArray(data)) {
        return [];
      }
      return data.map(function (item) {
        var thumb = item && item.thumb ? item.thumb : '';
        var full = item && (item.full || item.thumb) ? (item.full || item.thumb) : '';
        return {
          thumb: thumb,
          full: full,
          original: item && (item.original || item.full) ? (item.original || item.full) : '',
          alt: item && item.alt ? item.alt : ''
        };
      });
    }
    catch (e) {
      return [];
    }
  }

  function indexOfImg(img) {
    var box = gallery();
    if (!box || !img) {
      return 0;
    }
    var all = box.querySelectorAll('img');
    var i = Array.prototype.indexOf.call(all, img);
    return i < 0 ? 0 : i;
  }

  function overlayOn() {
    return (lb && lb.classList.contains('is-open')) || (sheet && !sheet.hidden);
  }

  function lock(on) {
    if (on === locked) {
      return;
    }
    var root = document.documentElement;
    var body = document.body;
    if (on) {
      scrollY = window.scrollY || root.scrollTop || 0;
      var gap = Math.max(0, window.innerWidth - root.clientWidth);
      body.style.position = 'fixed';
      body.style.top = '-' + scrollY + 'px';
      body.style.left = '0';
      body.style.right = '0';
      if (gap > 0) {
        body.style.paddingRight = gap + 'px';
      }
      root.classList.add('img-overlay-open');
      locked = true;
      return;
    }
    var y = scrollY;
    root.classList.remove('img-overlay-open');
    body.style.position = '';
    body.style.top = '';
    body.style.left = '';
    body.style.right = '';
    body.style.paddingRight = '';
    locked = false;
    window.scrollTo(0, y);
    window.requestAnimationFrame(function () {
      window.scrollTo(0, y);
    });
  }

  function syncLock() {
    lock(overlayOn());
  }

  function ensureLb() {
    if (lb) {
      return lb;
    }
    lb = document.createElement('div');
    lb.className = 'img-lb';
    lb.setAttribute('role', 'dialog');
    lb.setAttribute('aria-modal', 'true');
    lb.setAttribute('aria-label', '图片预览');
    lb.setAttribute('aria-hidden', 'true');
    lb.innerHTML = '<div class="img-lb__bar"><span class="img-lb__count"></span><div class="img-lb__actions"><button type="button" class="xedc-pill img-lb__all" data-img-all aria-haspopup="dialog" aria-controls="img-sheet" aria-expanded="false">' + GRID_SVG + '<span>全部</span></button><button type="button" class="img-lb__close" aria-label="关闭">×</button></div></div><button type="button" class="img-lb__nav img-lb__prev" aria-label="上一张">‹</button><img class="img-lb__img" alt=""><button type="button" class="img-lb__nav img-lb__next" aria-label="下一张">›</button>';
    document.body.appendChild(lb);
    var img = lb.querySelector('.img-lb__img');
    img.addEventListener('error', function () {
      var list = items();
      var item = list[idx];
      if (!item || img.dataset.fb === '1') {
        return;
      }
      if (img.getAttribute('src') !== item.thumb) {
        img.dataset.fb = '1';
        img.src = item.thumb;
      }
    });
    lb.querySelector('.img-lb__close').addEventListener('click', closeLb);
    lb.querySelector('.img-lb__prev').addEventListener('click', function () { step(-1); });
    lb.querySelector('.img-lb__next').addEventListener('click', function () { step(1); });
    lb.addEventListener('click', function (e) {
      if (e.target === lb) {
        closeLb();
      }
    });
    var startX = 0;
    var startY = 0;
    lb.addEventListener('touchstart', function (e) {
      if (!e.touches || e.touches.length !== 1) {
        return;
      }
      startX = e.touches[0].clientX;
      startY = e.touches[0].clientY;
    }, { passive: true });
    lb.addEventListener('touchend', function (e) {
      if (sheet && !sheet.hidden) {
        return;
      }
      var t = e.changedTouches && e.changedTouches[0];
      if (!t) {
        return;
      }
      var dx = t.clientX - startX;
      var dy = t.clientY - startY;
      if (Math.abs(dx) < 48 || Math.abs(dx) < Math.abs(dy)) {
        return;
      }
      step(dx < 0 ? 1 : -1);
    }, { passive: true });
    return lb;
  }

  function ensureSheet() {
    if (sheet && document.body.contains(sheet)) {
      return sheet;
    }
    sheet = document.getElementById('img-sheet');
    if (!sheet) {
      return null;
    }
    if (sheet.parentElement !== document.body) {
      document.body.appendChild(sheet);
    }
    return sheet;
  }

  function setExpanded(on) {
    document.querySelectorAll('[data-img-all]').forEach(function (btn) {
      btn.setAttribute('aria-expanded', on ? 'true' : 'false');
    });
  }

  function markActive(index) {
    if (!sheet) {
      return;
    }
    sheet.querySelectorAll('.img-sheet__item').forEach(function (btn) {
      var current = parseInt(btn.getAttribute('data-img-index'), 10);
      var on = current === index;
      btn.classList.toggle('is-active', on);
      if (on) {
        btn.setAttribute('aria-current', 'true');
      }
      else {
        btn.removeAttribute('aria-current');
      }
    });
  }

  function scrollActive() {
    if (!sheet) {
      return;
    }
    var grid = sheet.querySelector('.img-sheet__grid');
    var active = sheet.querySelector('.img-sheet__item.is-active');
    if (!grid || !active) {
      return;
    }
    var top = active.offsetTop;
    var bottom = top + active.offsetHeight;
    if (top < grid.scrollTop) {
      grid.scrollTop = Math.max(0, top - 8);
    }
    else if (bottom > grid.scrollTop + grid.clientHeight) {
      grid.scrollTop = bottom - grid.clientHeight + 8;
    }
  }

  function show(i) {
    var list = items();
    if (!list.length || !lb) {
      return;
    }
    idx = (i + list.length) % list.length;
    var item = list[idx];
    lb.querySelector('.img-lb__count').textContent = (idx + 1) + ' / ' + list.length;
    var img = lb.querySelector('.img-lb__img');
    var apply = function () {
      img.dataset.fb = '';
      img.alt = item.alt;
      img.src = item.full;
    };
    if (!img.getAttribute('src') || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      img.classList.remove('is-fading');
      apply();
      return;
    }
    img.classList.add('is-fading');
    window.setTimeout(function () {
      apply();
      if (img.complete) {
        img.classList.remove('is-fading');
      }
      else {
        img.addEventListener('load', function () {
          img.classList.remove('is-fading');
        }, { once: true });
      }
    }, 140);
  }

  function step(delta) {
    show(idx + delta);
  }

  function openLb(i) {
    ensureLb();
    lb.classList.add('is-open');
    lb.setAttribute('aria-hidden', 'false');
    show(i);
    syncLock();
  }

  function closeLb() {
    if (!lb) {
      return;
    }
    lb.classList.remove('is-open');
    lb.setAttribute('aria-hidden', 'true');
    syncLock();
  }

  function visibleIndex() {
    var box = gallery();
    if (!box) {
      return -1;
    }
    var images = box.querySelectorAll('img');
    var best = -1;
    var bestScore = 0;
    var viewH = window.innerHeight || document.documentElement.clientHeight;
    for (var i = 0; i < images.length; i++) {
      var rect = images[i].getBoundingClientRect();
      var top = Math.max(rect.top, 0);
      var bottom = Math.min(rect.bottom, viewH);
      var score = bottom - top;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  function openSheet(opener) {
    if (!items().length || !ensureSheet()) {
      return;
    }
    sheetOpener = opener || null;
    markActive(lb && lb.classList.contains('is-open') ? idx : visibleIndex());
    sheet.hidden = false;
    sheet.setAttribute('aria-hidden', 'false');
    setExpanded(true);
    syncLock();
    var close = sheet.querySelector('.img-sheet__close');
    if (close) {
      close.focus();
    }
    window.requestAnimationFrame(scrollActive);
  }

  function closeSheet(restore, keepLock) {
    if (!sheet || sheet.hidden) {
      return;
    }
    sheet.hidden = true;
    sheet.setAttribute('aria-hidden', 'true');
    setExpanded(false);
    if (!keepLock) {
      syncLock();
    }
    if (restore && sheetOpener && typeof sheetOpener.focus === 'function') {
      sheetOpener.focus();
    }
  }

  function trapFocus(e) {
    if (!sheet || sheet.hidden || e.key !== 'Tab') {
      return;
    }
    var nodes = sheet.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
    var list = Array.prototype.filter.call(nodes, function (el) {
      return !el.hidden && el.getAttribute('aria-hidden') !== 'true';
    });
    if (!list.length) {
      return;
    }
    var first = list[0];
    var last = list[list.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    }
    else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }

  document.addEventListener('click', function (e) {
    if (!document.querySelector('.img-detail')) {
      return;
    }
    if (e.target.closest('[data-img-sheet-close]')) {
      e.preventDefault();
      closeSheet(true);
      return;
    }
    var thumb = e.target.closest('.img-sheet__item');
    if (thumb && sheet && sheet.contains(thumb)) {
      e.preventDefault();
      var index = parseInt(thumb.getAttribute('data-img-index'), 10);
      if (!isFinite(index)) {
        index = 0;
      }
      closeSheet(false, true);
      openLb(index);
      return;
    }
    var all = e.target.closest('[data-img-all]');
    if (all) {
      e.preventDefault();
      e.stopPropagation();
      openSheet(all);
      return;
    }
    var img = e.target.closest('.img-detail__gallery img');
    if (!img) {
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    openLb(indexOfImg(img));
  }, true);

  document.addEventListener('keydown', function (e) {
    if (sheet && !sheet.hidden) {
      if (e.key === 'Escape') {
        e.preventDefault();
        closeSheet(true);
        return;
      }
      trapFocus(e);
      return;
    }
    if (!lb || !lb.classList.contains('is-open')) {
      return;
    }
    var tag = (e.target && e.target.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || (e.target && e.target.isContentEditable)) {
      return;
    }
    if (e.key === 'Escape') {
      e.preventDefault();
      closeLb();
    }
    else if (e.key === 'ArrowLeft') {
      e.preventDefault();
      step(-1);
    }
    else if (e.key === 'ArrowRight') {
      e.preventDefault();
      step(1);
    }
  });

  function initImages(context) {
    once('xedc-photo-images', '.img-detail__gallery', context).forEach(function (box) {
      var images = box.querySelectorAll('img');
      images.forEach(function (image, index) {
        image.loading = index === 0 ? 'eager' : 'lazy';
        if (index === 0) {
          image.setAttribute('fetchpriority', 'high');
        }
        else {
          image.removeAttribute('fetchpriority');
        }
        var width = parseInt(image.getAttribute('width'), 10);
        var height = parseInt(image.getAttribute('height'), 10);
        if (width > 0 && height > 0) {
          image.style.aspectRatio = width + ' / ' + height;
        }
      });
    });
  }

  function initRelated(context) {
    once('xedc-photo-related', '.img-rel__c img', context).forEach(function (image) {
      image.loading = 'eager';
      image.setAttribute('fetchpriority', 'low');
    });
  }

  function measureDesc(desc, toggle) {
    var style = window.getComputedStyle(desc);
    var lineHeight = parseFloat(style.lineHeight);
    if (!lineHeight || !isFinite(lineHeight)) {
      var fontSize = parseFloat(style.fontSize) || 14;
      lineHeight = fontSize * 1.65;
    }
    var opened = toggle.dataset.user === 'open';
    desc.classList.remove('is-collapsed');
    var fullHeight = desc.scrollHeight;
    if (fullHeight <= lineHeight * 3 + 2) {
      toggle.hidden = true;
      toggle.setAttribute('aria-expanded', 'true');
      return;
    }
    toggle.hidden = false;
    if (!opened) {
      desc.classList.add('is-collapsed');
      toggle.textContent = '展开';
      toggle.setAttribute('aria-expanded', 'false');
    }
    else {
      toggle.textContent = '收起';
      toggle.setAttribute('aria-expanded', 'true');
    }
  }

  function initDesc(context) {
    once('xedc-photo-desc', '.img-detail__desc', context).forEach(function (desc) {
      var group = desc.closest('.img-detail__desc-group');
      var toggle = group ? group.querySelector('.img-detail__desc-toggle') : null;
      if (!toggle) {
        return;
      }
      var run = function () {
        measureDesc(desc, toggle);
      };
      toggle.addEventListener('click', function () {
        var collapsed = desc.classList.toggle('is-collapsed');
        toggle.dataset.user = collapsed ? '' : 'open';
        toggle.textContent = collapsed ? '展开' : '收起';
        toggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
      });
      window.requestAnimationFrame(run);
      if (document.fonts && document.fonts.ready) {
        document.fonts.ready.then(run);
      }
    });
  }

  function initFavorite(context) {
    context.querySelectorAll('.img-detail__fav form.xedc-favorite-form').forEach(function (form) {
      if (form.dataset.loadingBound === '1') {
        return;
      }
      form.dataset.loadingBound = '1';
      var markLoading = function (disable) {
        var button = form.querySelector('.xedc-favorite-btn');
        if (!button) {
          return;
        }
        if (button.dataset.loading === '1') {
          if (disable) {
            button.disabled = true;
          }
          return;
        }
        button.dataset.loading = '1';
        button.classList.add('is-loading');
        button.setAttribute('aria-busy', 'true');
        if (disable) {
          button.disabled = true;
        }
        var observer = null;
        var reset = function () {
          if (observer) {
            observer.disconnect();
            observer = null;
          }
          if (!document.body.contains(button)) {
            return;
          }
          delete button.dataset.loading;
          button.disabled = false;
          button.classList.remove('is-loading');
          button.removeAttribute('aria-busy');
        };
        observer = new MutationObserver(function () {
          if (!button.disabled) {
            reset();
          }
        });
        observer.observe(button, { attributes: true, attributeFilter: ['disabled'] });
        window.setTimeout(reset, 8000);
      };
      form.addEventListener('pointerdown', function (event) {
        if (!event.target.closest('.xedc-favorite-btn')) {
          return;
        }
        var button = form.querySelector('.xedc-favorite-btn');
        if (button && button.dataset.loading === '1') {
          event.preventDefault();
          event.stopImmediatePropagation();
          return;
        }
        markLoading(false);
      }, true);
      form.addEventListener('click', function (event) {
        if (event.target.closest('.xedc-favorite-btn')) {
          markLoading(true);
        }
      });
      form.addEventListener('submit', function () {
        markLoading(true);
      });
    });
  }

  function styleMore(context) {
    var root = context && context.querySelectorAll ? context : document;
    root.querySelectorAll('.img-more').forEach(function (button) {
      button.classList.add('xedc-pill');
    });
  }

  function watchMore(box) {
    styleMore(box);
    if (!window.MutationObserver || box.dataset.moreWatch === '1') {
      return;
    }
    box.dataset.moreWatch = '1';
    var observer = new MutationObserver(function () {
      styleMore(box);
    });
    observer.observe(box, { childList: true, subtree: true });
  }

  function boot(root) {
    ensureSheet();
    if (!items().length) {
      var all = root.querySelector('[data-img-all]');
      if (all) {
        all.hidden = true;
      }
    }
  }

  Drupal.behaviors.xedcPhotoDetail = {
    attach: function (context) {
      initImages(context);
      initRelated(context);
      initDesc(context);
      initFavorite(context);
      styleMore(context);
      once('xedc-photo-detail', '.img-detail__gallery', context).forEach(watchMore);
      once('xedc-photo-detail', '.img-detail', context).forEach(boot);
    }
  };
})(Drupal, once);
