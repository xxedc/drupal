(function (Drupal) {
  'use strict';

  function initImages(context) {
    var images = context.querySelectorAll('.img-detail__gallery img');
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
  }

  function initRelated(context) {
    var images = context.querySelectorAll('.img-rel__c img');
    images.forEach(function (image) {
      image.loading = 'eager';
      image.setAttribute('fetchpriority', 'low');
    });
  }

  function initDesc(context) {
    var desc = context.querySelector('.img-detail__desc');
    var toggle = context.querySelector('.img-detail__desc-toggle');
    if (!desc || !toggle || desc.dataset.collapsible === '1') {
      return;
    }

    desc.dataset.collapsible = '1';
    var lineHeight = parseFloat(window.getComputedStyle(desc).lineHeight) || 24;
    var fullHeight = desc.scrollHeight;
    var threshold = lineHeight * (window.matchMedia('(min-width: 992px)').matches ? 6 : 5);
    if (fullHeight <= threshold) {
      return;
    }

    desc.classList.add('is-collapsed');
    toggle.hidden = false;
    toggle.textContent = '展开';
    toggle.setAttribute('aria-expanded', 'false');

    toggle.addEventListener('click', function () {
      var collapsed = desc.classList.toggle('is-collapsed');
      toggle.textContent = collapsed ? '展开' : '收起';
      toggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
    });
  }

  function initFavorite(context) {
    var forms = context.querySelectorAll('.img-detail__fav form.xedc-favorite-form');
    forms.forEach(function (form) {
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

  Drupal.behaviors.xedcPhotoDetail = {
    attach: function (context) {
      initImages(context);
      initRelated(context);
      initDesc(context);
      initFavorite(context);
    }
  };
})(Drupal);
