(function () {
  'use strict';

  function init() {
    var page = document.querySelector('.sr-page');
    if (!page) return;

    page.querySelectorAll('.sr-img').forEach(function (img) {
      if (img.complete) return;
      img.classList.add('is-pending');
      var reveal = function () {
        img.classList.remove('is-pending');
        img.removeEventListener('load', reveal);
        img.removeEventListener('error', reveal);
      };
      img.addEventListener('load', reveal);
      img.addEventListener('error', reveal);
    });

    var input = page.querySelector('.sr-input');
    var clear = page.querySelector('[data-sr-clear]');
    if (!input || !clear) return;

    var sync = function () {
      clear.hidden = input.value.length === 0;
    };
    sync();
    input.addEventListener('input', sync);
    clear.addEventListener('click', function () {
      input.value = '';
      input.focus();
      sync();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  }
  else {
    init();
  }
})();
