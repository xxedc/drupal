(function (Drupal) {
  'use strict';

  var savedY = null;

  function restoreScroll() {
    if (savedY === null) {
      return;
    }
    var y = savedY;
    window.scrollTo(0, y);
    window.requestAnimationFrame(function () {
      window.scrollTo(0, y);
    });
  }

  function resetFormState(form) {
    if (!form) {
      return;
    }
    delete form.dataset.submitting;
    form.classList.remove('is-submitting');
    var button = form.querySelector('[data-drupal-selector="edit-submit"], .form-submit');
    if (button) {
      button.disabled = false;
      button.removeAttribute('aria-busy');
    }
  }

  if (window.jQuery) {
    window.jQuery.fn.xedcCommentDone = function () {
      var form = this.get(0);
      var holder = form ? form.closest('.cm-reply-hold') : null;
      var field = document.querySelector('.img-detail__comments .field--name-field-comment')
        || document.querySelector('.img-detail__comments');
      if (form && holder && field) {
        var parent = holder.parentElement;
        while (holder.firstChild && holder.firstChild !== form) {
          parent.insertBefore(holder.firstChild, holder);
        }
        field.appendChild(form);
        holder.remove();
      }
      if (form) {
        var pid = form.querySelector('input[name="pid"]');
        if (pid) {
          pid.value = '0';
        }
        var area = form.querySelector('textarea');
        if (area) {
          area.placeholder = '写下你的评论…';
        }
      }
      resetFormState(form);
      restoreScroll();
      return this;
    };
  }

  document.addEventListener('submit', function (event) {
    var form = event.target.closest('form.comment-form');
    if (!form) return;
    if (form.classList.contains('comment-form--edit')) {
      return;
    }
    savedY = window.scrollY || document.documentElement.scrollTop || 0;
    if (form.dataset.submitting === '1') {
      event.preventDefault();
      return;
    }
    form.dataset.submitting = '1';
    form.classList.add('is-submitting');
    var button = form.querySelector('[data-drupal-selector="edit-submit"], .form-submit');
    if (button) button.setAttribute('aria-busy', 'true');
  }, true);

  if (window.jQuery) {
    window.jQuery(document).on('ajaxComplete', function (event, xhr, settings) {
      var extra = settings && settings.extraData;
      var formId = extra && (extra.form_id || '');
      if (!formId || String(formId).indexOf('comment') === -1) {
        return;
      }
      window.setTimeout(function () {
        document.querySelectorAll('form.comment-form.is-submitting').forEach(resetFormState);
        restoreScroll();
      }, 0);
    });
  }

})(Drupal);

(function () {
  'use strict';

  function placeError() {
    var form = document.querySelector('form.comment-form');
    var alert = document.querySelector('.alert-danger, .messages--error');
    if (!form || !alert || form.querySelector('.comment-form__error')) return;
    var invalid = form.querySelector('.form-textarea.is-invalid, .form-textarea[aria-invalid="true"], .form-control.is-invalid');
    var item = invalid && invalid.closest('.form-item');
    if (!item) return;
    var copy = alert.cloneNode(true);
    copy.querySelectorAll('.visually-hidden, .btn-close').forEach(function (node) { node.remove(); });
    var text = (copy.textContent || '').replace(/\s+/g, ' ').trim();
    if (!text) return;
    var box = document.createElement('div');
    box.className = 'comment-form__error';
    box.setAttribute('role', 'alert');
    box.textContent = text;
    item.appendChild(box);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', placeError);
  }
  else {
    placeError();
  }
})();
