/**
 * @file
 * Mailto and Colorbox tracking without a jQuery dependency.
 *
 * Page views and file downloads stay in Matomo's inline snippet.
 * Colorbox is only bound when jQuery is already on the page.
 */
(function (drupalSettings, _paq) {
  var settings = drupalSettings.matomo || {};

  if (settings.trackMailto) {
    var trackMailto = function (event) {
      var el = event.target && event.target.closest ? event.target.closest('a,area') : null;
      if (!el) {
        return;
      }
      var href = el.getAttribute('href') || '';
      if (href.indexOf('mailto:') === 0) {
        _paq.push(['trackEvent', 'Mails', 'Click', href.substring(7)]);
      }
    };
    document.addEventListener('mousedown', trackMailto);
    document.addEventListener('keyup', trackMailto);
    document.addEventListener('touchstart', trackMailto);
  }

  if (settings.trackColorbox) {
    document.addEventListener('DOMContentLoaded', function () {
      if (!window.jQuery || !window.jQuery.colorbox) {
        return;
      }
      window.jQuery(document).on('cbox_complete', function () {
        var href = window.jQuery.colorbox.element().attr('href');
        if (!href) {
          return;
        }
        _paq.push(['setCustomUrl', href]);
        if (settings.disableCookies) {
          _paq.push(['disableCookies']);
        }
        _paq.push(['trackPageView']);
      });
    });
  }
})(drupalSettings, window._paq);
