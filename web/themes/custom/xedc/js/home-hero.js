/**
 * @file
 * Scroll-snap hero: dots and autoplay. Swipe is native overflow.
 */
(function (Drupal, once) {
  function lockHeroSlides(track) {
    const width = track.clientWidth;
    const height = track.clientHeight;
    if (!width || !height) {
      return;
    }
    const basis = `0 0 ${width}px`;
    const size = `${width}px`;
    const tall = `${height}px`;
    track.querySelectorAll('.xedc-hero__slide').forEach((slide) => {
      if (slide.style.flexBasis === size && slide.style.height === tall) {
        return;
      }
      slide.style.flex = basis;
      slide.style.width = size;
      slide.style.minWidth = size;
      slide.style.maxWidth = size;
      slide.style.height = tall;
    });
  }

  function bindSlideDragGuard(root) {
    root.querySelectorAll('.xedc-hero__slide, .xedc-hero__slide img').forEach((node) => {
      node.setAttribute('draggable', 'false');
      node.addEventListener('dragstart', (event) => event.preventDefault());
    });
  }

  // Horizontal swipe is scripted and clamped so it cannot rubber-band past the slides.
  // Snap is off while the finger is down; otherwise mandatory snap jumps back to 0.
  // Vertical movement is left to the page (touch-action: pan-y).
  function bindEdgeClamp(track) {
    let startX = 0;
    let startY = 0;
    let startLeft = 0;
    let axis = '';

    function snapToNearest() {
      if (axis !== 'x') {
        return;
      }
      const width = track.clientWidth || 1;
      const slides = track.querySelectorAll('.xedc-hero__slide').length || 1;
      const index = Math.max(0, Math.min(slides - 1, Math.round(track.scrollLeft / width)));
      axis = '';
      track.style.scrollSnapType = '';
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      track.scrollTo({
        left: index * width,
        behavior: reduce ? 'auto' : 'smooth',
      });
    }

    track.addEventListener('touchstart', (event) => {
      if (event.touches.length !== 1) {
        return;
      }
      startX = event.touches[0].clientX;
      startY = event.touches[0].clientY;
      startLeft = track.scrollLeft;
      axis = '';
    }, {passive: true});

    track.addEventListener('touchmove', (event) => {
      if (event.touches.length !== 1) {
        return;
      }
      const x = event.touches[0].clientX;
      const y = event.touches[0].clientY;
      if (!axis) {
        const dx = Math.abs(x - startX);
        const dy = Math.abs(y - startY);
        if (dx < 6 && dy < 6) {
          return;
        }
        axis = dx >= dy ? 'x' : 'y';
        if (axis === 'x') {
          track.style.scrollSnapType = 'none';
        }
      }
      if (axis !== 'x') {
        return;
      }
      const max = Math.max(0, track.scrollWidth - track.clientWidth);
      track.scrollLeft = Math.min(max, Math.max(0, startLeft - (x - startX)));
      if (event.cancelable) {
        event.preventDefault();
      }
    }, {passive: false});

    track.addEventListener('touchend', snapToNearest);
    track.addEventListener('touchcancel', snapToNearest);
  }

  Drupal.behaviors.xedcHomeHero = {
    attach(context) {
      once('xedc-hero', '[data-xedc-hero]', context).forEach((root) => {
        const track = root.querySelector('.xedc-hero__track');
        const slides = track ? [...track.querySelectorAll('.xedc-hero__slide')] : [];
        const dots = [...root.querySelectorAll('.xedc-hero__dot')];
        if (!track) {
          return;
        }
        bindSlideDragGuard(root);
        const relock = () => lockHeroSlides(track);
        relock();
        window.requestAnimationFrame(relock);
        window.addEventListener('resize', relock);
        if (window.ResizeObserver) {
          const observer = new ResizeObserver(relock);
          observer.observe(track);
        }
        if (slides.length < 2) {
          return;
        }
        bindEdgeClamp(track);
        const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        let index = 0;
        let timer = 0;
        let scrollTimer = 0;

        function paint(i) {
          index = (i + slides.length) % slides.length;
          dots.forEach((dot, n) => {
            const on = n === index;
            dot.classList.toggle('is-active', on);
            dot.setAttribute('aria-current', on ? 'true' : 'false');
          });
        }

        function go(i) {
          paint(i);
          track.scrollTo({
            left: index * track.clientWidth,
            behavior: reduce ? 'auto' : 'smooth',
          });
        }

        function stop() {
          if (timer) {
            window.clearInterval(timer);
            timer = 0;
          }
        }

        function start() {
          if (reduce || document.hidden) {
            return;
          }
          stop();
          timer = window.setInterval(() => go(index + 1), 5000);
        }

        dots.forEach((dot, n) => {
          dot.addEventListener('click', () => {
            go(n);
            start();
          });
        });

        const prev = root.querySelector('.xedc-hero__nav--prev');
        const next = root.querySelector('.xedc-hero__nav--next');
        if (prev) {
          prev.addEventListener('click', () => {
            go(index - 1);
            start();
          });
        }
        if (next) {
          next.addEventListener('click', () => {
            go(index + 1);
            start();
          });
        }

        track.addEventListener('scroll', () => {
          window.clearTimeout(scrollTimer);
          scrollTimer = window.setTimeout(() => {
            const width = track.clientWidth || 1;
            const next = Math.round(track.scrollLeft / width);
            if (next !== index && next >= 0 && next < slides.length) {
              paint(next);
            }
          }, 80);
        }, {passive: true});

        root.addEventListener('mouseenter', stop);
        root.addEventListener('mouseleave', start);
        root.addEventListener('focusin', stop);
        root.addEventListener('focusout', (event) => {
          if (!root.contains(event.relatedTarget)) {
            start();
          }
        });
        document.addEventListener('visibilitychange', () => {
          if (document.hidden) {
            stop();
          }
          else {
            start();
          }
        });
        start();
      });
    },
  };

  Drupal.behaviors.xedcHomeTax = {
    attach(context) {
      once('xedc-tax', '[data-xedc-tax]', context).forEach((root) => {
        const button = root.querySelector('.xedc-tax__more');
        const list = root.querySelector('.xedc-tax__list');
        if (!button || !list) {
          return;
        }
        const mq = window.matchMedia('(max-width: 991.98px)');

        function twoRowLimit() {
          const styles = getComputedStyle(root);
          const chipH = parseFloat(styles.getPropertyValue('--xedc-chip-h')) || 34;
          const gap = parseFloat(getComputedStyle(list).rowGap);
          const rowGap = Number.isFinite(gap) ? gap : (parseFloat(styles.getPropertyValue('--xedc-tax-gap')) || 8);
          return chipH * 2 + rowGap;
        }

        function sync() {
          if (!mq.matches) {
            root.classList.remove('is-collapsible', 'is-open');
            button.setAttribute('aria-expanded', 'false');
            button.textContent = '更多';
            return;
          }
          const overflow = list.scrollHeight > twoRowLimit() + 2;
          root.classList.toggle('is-collapsible', overflow);
          if (!overflow) {
            root.classList.remove('is-open');
            button.setAttribute('aria-expanded', 'false');
            button.textContent = '更多';
          }
        }

        button.addEventListener('click', () => {
          if (!root.classList.contains('is-collapsible')) {
            return;
          }
          const open = root.classList.toggle('is-open');
          button.setAttribute('aria-expanded', open ? 'true' : 'false');
          button.textContent = open ? '收起' : '更多';
        });

        sync();
        let frame = 0;
        const schedule = () => {
          window.cancelAnimationFrame(frame);
          frame = window.requestAnimationFrame(sync);
        };
        if (typeof mq.addEventListener === 'function') {
          mq.addEventListener('change', schedule);
        }
        window.addEventListener('resize', schedule);
        if (window.ResizeObserver) {
          const observer = new ResizeObserver(schedule);
          observer.observe(list);
        }
      });
    },
  };
})(Drupal, once);
