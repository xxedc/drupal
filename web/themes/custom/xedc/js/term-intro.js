document.addEventListener('DOMContentLoaded', function () {
  document.querySelectorAll('.term-intro').forEach(function (wrap) {
    var text = wrap.querySelector('.term-intro__text');
    var button = wrap.querySelector('.term-intro__toggle');
    if (!text || !button) return;

    var update = function () {
      if (wrap.classList.contains('is-open')) return;
      button.hidden = text.scrollHeight <= text.clientHeight + 2;
    };

    update();
    window.addEventListener('resize', update);

    button.addEventListener('click', function () {
      var open = wrap.classList.toggle('is-open');
      button.textContent = open ? '收起' : '展开';
      button.setAttribute('aria-expanded', open ? 'true' : 'false');
      if (!open) update();
    });
  });
});
