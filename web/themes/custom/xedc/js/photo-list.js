(function () {
  'use strict';

  document.addEventListener('DOMContentLoaded', function () {
    var view = document.querySelector('.xedc-view-photos');
    if (!view) return;

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
    backtop.setAttribute('aria-label', '回到顶部');
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

    view.querySelectorAll('.photo-tabs-scroll').forEach(function (scroll) {
      var nav = scroll.querySelector('.photo-tabs');
      var fade = scroll.querySelector('.photo-tabs-fade');
      if (!nav || !fade) return;
      var sync = function () {
        var overflow = nav.scrollWidth - nav.clientWidth > 2;
        var atEnd = nav.scrollLeft + nav.clientWidth >= nav.scrollWidth - 2;
        fade.hidden = !overflow || atEnd;
      };
      sync();
      nav.addEventListener('scroll', sync, { passive: true });
      window.addEventListener('resize', sync);
    });

    var opener = view.querySelector('.photo-more');
    var sheet = view.querySelector('.photo-sheet');
    if (!opener || !sheet) return;
    var panel = sheet.querySelector('.photo-sheet__panel');
    var input = sheet.querySelector('.photo-sheet__search input');
    var empty = sheet.querySelector('.photo-sheet__empty');
    var links = sheet.querySelectorAll('.photo-sheet__grid a');
    var bodyOverflow = '';

    if (sheet.parentElement !== document.body) {
      document.body.appendChild(sheet);
    }

    function filterPills() {
      var q = (input.value || '').trim().toLowerCase();
      var count = 0;
      links.forEach(function (link) {
        var show = !q || link.textContent.toLowerCase().indexOf(q) !== -1;
        link.hidden = !show;
        if (show) count += 1;
      });
      empty.hidden = count > 0;
    }

    function openSheet() {
      bodyOverflow = document.body.style.overflow;
      sheet.hidden = false;
      opener.setAttribute('aria-expanded', 'true');
      document.body.style.overflow = 'hidden';
      filterPills();
      window.setTimeout(function () {
        if (input) input.focus();
      }, 0);
    }

    function closeSheet() {
      if (sheet.hidden) return;
      sheet.hidden = true;
      opener.setAttribute('aria-expanded', 'false');
      document.body.style.overflow = bodyOverflow;
      opener.focus();
    }

    opener.addEventListener('click', openSheet);
    sheet.querySelectorAll('[data-photo-sheet-close]').forEach(function (el) {
      el.addEventListener('click', closeSheet);
    });
    if (input) input.addEventListener('input', filterPills);
    document.addEventListener('keydown', function (event) {
      if (sheet.hidden) return;
      if (event.key === 'Escape') {
        event.preventDefault();
        closeSheet();
        return;
      }
      if (event.key !== 'Tab' || !panel) return;
      var focusable = panel.querySelectorAll('a:not([hidden]), button, input');
      if (!focusable.length) return;
      var first = focusable[0];
      var last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      }
      else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    });
  });
})();
