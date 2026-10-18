(function (Drupal, once) {
  Drupal.behaviors.xedcTagsIndex = {
    attach(context) {
      once('xt-index', '[data-xt-index]', context).forEach((root) => {
        const list = root.querySelector('.xt-tags');
        const items = Array.from(list.children);
        const input = root.querySelector('.xt-search input');
        const empty = root.querySelector('.xt-empty');
        const moreWrap = root.querySelector('.xt-more-wrap');
        const moreBtn = root.querySelector('.xt-more');
        const btns = Array.from(root.querySelectorAll('.xt-seg button'));
        const coll = new Intl.Collator('zh-Hans-CN');
        const num = (el, k) => Number(el.dataset[k]) || 0;
        const sorters = {
          hot: (a, b) => num(b, 'count') - num(a, 'count') || coll.compare(a.dataset.name, b.dataset.name),
          new: (a, b) => num(b, 'latest') - num(a, 'latest'),
          name: (a, b) => coll.compare(a.dataset.name, b.dataset.name),
        };
        let sort = 'hot';
        let expanded = false;
        const limit = () => (window.matchMedia('(min-width: 768px)').matches ? 40 : 24);

        const render = () => {
          const q = input.value.trim().toLowerCase();
          items.sort(sorters[sort]);
          const matched = items.filter((li) => !q || li.dataset.name.includes(q));
          const max = limit();
          const collapse = !q && !expanded && matched.length > max;
          items.forEach((li) => { li.hidden = true; list.appendChild(li); });
          matched.forEach((li, i) => { li.hidden = collapse && i >= max; });
          empty.hidden = matched.length > 0;
          const canToggle = !q && matched.length > max;
          moreWrap.hidden = !canToggle;
          if (canToggle) {
            moreBtn.textContent = expanded ? '收起' : '展开更多（还有 ' + (matched.length - max) + ' 个）';
          }
        };

        btns.forEach((b) => b.addEventListener('click', () => {
          sort = b.dataset.sort;
          btns.forEach((x) => x.classList.toggle('is-active', x === b));
          render();
        }));
        input.addEventListener('input', render);
        moreBtn.addEventListener('click', () => {
          expanded = !expanded;
          render();
          if (!expanded) list.scrollIntoView({ block: 'start' });
        });
        window.matchMedia('(min-width: 768px)').addEventListener('change', render);
        render();
      });
    },
  };
})(Drupal, once);
