(function () {
  'use strict';

  document.addEventListener('submit', function (event) {
    var form = event.target.closest('form.comment-form');
    if (!form) return;
    if (form.dataset.submitting === '1') {
      event.preventDefault();
      return;
    }
    form.dataset.submitting = '1';
    form.classList.add('is-submitting');
    var button = form.querySelector('.form-submit');
    if (button) button.setAttribute('aria-busy', 'true');
  }, true);
})();

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
