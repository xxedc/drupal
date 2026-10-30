(function (Drupal, once) {
  Drupal.behaviors.xedcModels = {
    attach(ctx) {
      once('xm', '[data-xm]', ctx).forEach((root) => {
        const input = root.querySelector('[data-xm-input]');
        const cards = [...root.querySelectorAll('.xm-card')];
        const empty = root.querySelector('.xm-empty');
        const cnt = root.querySelector('[data-xm-count]');
        const total = cards.length;
        input.addEventListener('input', () => {
          const q = input.value.trim().toLowerCase();
          let n = 0;
          cards.forEach((c) => {
            const ok = !q || c.dataset.name.includes(q);
            c.hidden = !ok;
            if (ok) n++;
          });
          empty.hidden = n > 0;
          cnt.textContent = Drupal.t('共 @count 位模特', {'@count': q ? n + ' / ' + total : String(total)});
        });
      });
    },
  };
})(Drupal, once);
