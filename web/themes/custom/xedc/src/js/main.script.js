// * Bootstrap libraries
import './_bootstrap';

// * Any other global site-wide JavaScript should be placed below.

(() => {
  const root = document.documentElement;
  const saved = localStorage.getItem('theme');
  const preferred = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  const apply = (t) => {
    root.setAttribute('data-bs-theme', t);
    document.querySelectorAll('[data-theme-toggle]').forEach((b) => {
      b.setAttribute('aria-label', t === 'dark' ? '切换到浅色' : '切换到深色');
      b.dataset.mode = t;
    });
  };
  apply(saved || preferred);
  document.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-theme-toggle]');
    if (!btn) return;
    const next = root.getAttribute('data-bs-theme') === 'dark' ? 'light' : 'dark';
    localStorage.setItem('theme', next);
    apply(next);
  });
})();

(() => {
  const init = () => {
    const nav = document.querySelector('.xedc-nav');
    if (!nav) return;
    const burger = nav.querySelector('[data-menu-toggle]');
    const sbtn = nav.querySelector('[data-search-toggle]');
    const bar = nav.querySelector('.xedc-searchbar');
    const setMenu = (open) => {
      nav.classList.toggle('menu-open', open);
      burger.setAttribute('aria-expanded', open);
      document.body.style.overflow = open ? 'hidden' : '';
    };
    const setSearch = (open) => {
      nav.classList.toggle('search-open', open);
      sbtn.setAttribute('aria-expanded', open);
      if (open) bar.querySelector('input').focus();
    };
    burger.addEventListener('click', () => { setSearch(false); setMenu(!nav.classList.contains('menu-open')); });
    nav.querySelectorAll('[data-menu-close]').forEach((el) => el.addEventListener('click', () => setMenu(false)));
    nav.querySelectorAll('.xedc-menu a').forEach((a) => a.addEventListener('click', () => setMenu(false)));
    sbtn.addEventListener('click', () => { setMenu(false); setSearch(!nav.classList.contains('search-open')); });
    document.addEventListener('click', (e) => {
      if (!nav.classList.contains('search-open')) return;
      if (bar.contains(e.target) || sbtn.contains(e.target)) return;
      setSearch(false);
    });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { setMenu(false); setSearch(false); } });
    window.addEventListener('resize', () => { if (window.innerWidth >= 992) { setMenu(false); setSearch(false); } });
  };
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', init) : init();
})();
