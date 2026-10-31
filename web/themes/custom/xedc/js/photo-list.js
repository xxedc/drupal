(function () {
  'use strict';

  document.addEventListener('DOMContentLoaded', function () {
    var view = document.querySelector('.xedc-view-photos');
    if (!view) return;

    var header = view.querySelector('.view-header');
    var title = document.querySelector('.block-page-title-block h1') || document.querySelector('h1');
    if (header && title && !document.querySelector('.photo-titlebar')) {
      var count = document.createElement('span');
      count.className = 'photo-count';
      count.textContent = header.textContent.trim();
      var bar = document.createElement('div');
      bar.className = 'photo-titlebar';
      title.parentNode.insertBefore(bar, title);
      bar.appendChild(title);
      bar.appendChild(count);
      header.style.display = 'none';
    }

    view.querySelectorAll('.meitu-card__img').forEach(function (img) {
      if (img.complete) return;
      img.classList.add('xedc-img-pending');
      var reveal = function () {
        img.classList.remove('xedc-img-pending');
        img.removeEventListener('load', reveal);
        img.removeEventListener('error', reveal);
      };
      img.addEventListener('load', reveal);
      img.addEventListener('error', reveal);
    });

    var backtop = document.createElement('button');
    backtop.type = 'button';
    backtop.className = 'xedc-backtop';
    backtop.setAttribute('aria-label', Drupal.t('回到顶部'));
    backtop.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5"/><path d="m5 12 7-7 7 7"/></svg>';
    backtop.addEventListener('click', function () {
      var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      window.scrollTo({ top: 0, behavior: reduce ? 'auto' : 'smooth' });
    });
    document.body.appendChild(backtop);

    function updateBacktop() {
      backtop.classList.toggle('is-visible', window.scrollY > 600);
    }
    updateBacktop();
    window.addEventListener('scroll', updateBacktop, { passive: true });

    var bar = view.querySelector('.photo-bar');
    var nav = bar && bar.querySelector('.photo-tabs');
    var opener = view.querySelector('.photo-more');
    var drop = view.querySelector('.photo-drop');
    var rule = view.querySelector('.photo-rule');
    var pills = nav ? Array.prototype.slice.call(nav.querySelectorAll(':scope > a.xedc-pill')) : [];
    var input = drop && drop.querySelector('.photo-drop__search input');
    var empty = drop && drop.querySelector('.photo-drop__empty');
    var links = drop ? Array.prototype.slice.call(drop.querySelectorAll('.photo-drop__link')) : [];
    var fittedWidth = -1;

    function gapOf(el) {
      if (!el) return 0;
      var style = window.getComputedStyle(el);
      var value = parseFloat(style.columnGap || style.gap);
      return isNaN(value) ? 0 : value;
    }

    function rowWidth(widths, indexes, gap) {
      var total = 0;
      indexes.forEach(function (index, order) {
        total += widths[index] + (order ? gap : 0);
      });
      return total;
    }

    function chooseVisible(widths, available, gap) {
      var active = -1;
      pills.forEach(function (pill, index) {
        if (pill.classList.contains('is-active')) active = index;
      });
      var chosen = [];
      if (active >= 0 && widths[active] <= available) chosen.push(active);
      widths.forEach(function (width, index) {
        if (index === active) return;
        var trial = chosen.concat(index).sort(function (a, b) { return a - b; });
        if (rowWidth(widths, trial, gap) <= available + 0.5) chosen = trial;
      });
      if (!chosen.length) {
        widths.some(function (width, index) {
          if (width <= available + 0.5) {
            chosen = [index];
            return true;
          }
          return false;
        });
      }
      return chosen;
    }

    function filterLinks() {
      var q = (input && input.value ? input.value : '').trim().toLowerCase();
      var count = 0;
      links.forEach(function (link) {
        var show = link.getAttribute('data-photo-id') !== '0' && (!q || link.textContent.toLowerCase().indexOf(q) !== -1);
        link.hidden = !show;
        if (show) count += 1;
      });
      if (empty) empty.hidden = count > 0;
    }

    function fitPills() {
      if (!bar || !pills.length) return;
      var barWidth = bar.clientWidth;
      if (!barWidth || barWidth === fittedWidth) return;
      fittedWidth = barWidth;
      pills.forEach(function (pill) { pill.hidden = false; });
      var widths = pills.map(function (pill) { return pill.getBoundingClientRect().width; });
      var pillGap = gapOf(nav);
      if (!rule || !opener) return;
      rule.hidden = false;
      var reserve = parseFloat(window.getComputedStyle(rule).paddingLeft) || 0;
      var available = barWidth - opener.getBoundingClientRect().width - reserve;
      var visible = {};
      if (available > 0) {
        chooseVisible(widths, Math.max(0, available - 1), pillGap).forEach(function (index) {
          visible[index] = true;
        });
      }
      pills.forEach(function (pill, index) {
        pill.hidden = !visible[index];
      });
    }

    function openDrop() {
      drop.hidden = false;
      opener.setAttribute('aria-expanded', 'true');
      filterLinks();
      window.setTimeout(function () {
        if (input) input.focus();
      }, 0);
    }

    function closeDrop() {
      if (drop.hidden) return;
      drop.hidden = true;
      opener.setAttribute('aria-expanded', 'false');
      if (input) input.value = '';
      filterLinks();
    }

    fitPills();
    if (bar && window.ResizeObserver) {
      new ResizeObserver(function () { fitPills(); }).observe(bar);
    }
    else {
      window.addEventListener('resize', fitPills);
    }
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(function () {
        fittedWidth = -1;
        fitPills();
      });
    }
    if (!opener || !drop || !rule) return;

    opener.addEventListener('click', function (event) {
      event.preventDefault();
      event.stopPropagation();
      if (drop.hidden) openDrop();
      else closeDrop();
    });
    if (input) {
      input.addEventListener('input', filterLinks);
      input.addEventListener('keydown', function (event) {
        if (event.key === 'Enter') event.preventDefault();
      });
    }
    document.addEventListener('click', function (event) {
      if (drop.hidden || rule.contains(event.target)) return;
      closeDrop();
    });
    document.addEventListener('keydown', function (event) {
      if (drop.hidden || event.key !== 'Escape') return;
      event.preventDefault();
      closeDrop();
      opener.focus();
    });
  });
})();
