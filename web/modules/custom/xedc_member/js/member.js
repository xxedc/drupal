(function () {
  'use strict';

  var loadingTimers = new WeakMap();

  function endFavorite(form) {
    if (!form) return;
    delete form.dataset.xedcFavoriteLoading;
    form.removeAttribute('aria-busy');
    var timer = loadingTimers.get(form);
    if (timer) {
      window.clearTimeout(timer);
      loadingTimers.delete(form);
    }
  }

  function beginFavorite(form) {
    if (form.dataset.xedcFavoriteLoading === '1') return false;
    form.dataset.xedcFavoriteLoading = '1';
    form.setAttribute('aria-busy', 'true');
    loadingTimers.set(form, window.setTimeout(function () {
      loadingTimers.delete(form);
      endFavorite(form);
    }, 15000));
    return true;
  }

  document.addEventListener('click', function (event) {
    var button = event.target.closest('.xedc-favorite-btn');
    if (!button) return;
    var form = button.closest('form.xedc-favorite-form');
    if (!form) return;
    if (form.dataset.xedcFavoriteLoading === '1') {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    beginFavorite(form);
  }, true);

  document.addEventListener('submit', function (event) {
    var form = event.target.closest('form.xedc-favorite-form');
    if (!form) return;
    if (form.dataset.xedcFavoriteLoading === '1') {
      event.preventDefault();
      return;
    }
    beginFavorite(form);
  }, true);

  if (window.jQuery) {
    window.jQuery(document).on('ajaxComplete', function (event, xhr, settings) {
      var data = typeof settings.data === 'string' ? settings.data : '';
      if (data.indexOf('xedc_member_favorite_toggle') === -1) return;
      document.querySelectorAll('form.xedc-favorite-form[data-xedc-favorite-loading]').forEach(endFavorite);
    });
  }

  var messageTimers = new WeakMap();

  function scheduleMessage(element) {
    if (!element || element.nodeType !== 1) return;
    var isStatus = element.matches('[data-drupal-message-type="status"], .alert-success, .messages--status');
    if (!isStatus) return;
    if (messageTimers.has(element)) return;
    if (!/收藏|取消收藏/.test(element.textContent || '')) return;
    messageTimers.set(element, window.setTimeout(function () {
      messageTimers.delete(element);
      element.classList.add('is-xedc-autohide');
      window.setTimeout(function () {
        if (element.parentNode) element.parentNode.removeChild(element);
      }, 250);
    }, 3000));
  }

  function scanMessages(node) {
    if (!node || node.nodeType !== 1) return;
    if (node.matches && node.matches('[data-drupal-message-type="status"], .alert-success, .messages--status')) scheduleMessage(node);
    if (node.querySelectorAll) node.querySelectorAll('[data-drupal-message-type="status"], .alert-success, .messages--status').forEach(scheduleMessage);
  }

  document.addEventListener('DOMContentLoaded', function () {
    var observer = new MutationObserver(function (mutations) {
      mutations.forEach(function (mutation) {
        mutation.addedNodes.forEach(scanMessages);
      });
    });
    observer.observe(document.body, { childList: true, subtree: true });
  });
})();
