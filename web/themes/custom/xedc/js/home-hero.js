/**
 * @file
 * Scroll-snap hero: dots and autoplay. Swipe is native overflow.
 */
(function (Drupal, once) {
  Drupal.behaviors.xedcHomeHero = {
    attach(context) {
      once('xedc-hero', '[data-xedc-hero]', context).forEach((root) => {
        const track = root.querySelector('.xedc-hero__track');
        const slides = track ? [...track.querySelectorAll('.xedc-hero__slide')] : [];
        const dots = [...root.querySelectorAll('.xedc-hero__dot')];
        if (!track || slides.length < 2) {
          return;
        }
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
})(Drupal, once);
