(function () {
  'use strict';

  document.addEventListener('DOMContentLoaded', function () {
    var view = document.querySelector('.xedc-view-photos');
    if (!view) return;

    view.querySelectorAll('.views-field-field-cover-image img').forEach(function (img) {
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
  });
})();
