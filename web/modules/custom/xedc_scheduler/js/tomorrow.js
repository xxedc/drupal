(function (Drupal, drupalSettings, once) {
  Drupal.behaviors.xedcSchedulerTomorrow = {
    attach(context) {
      once('xedc-scheduler-tomorrow', '.xedc-scheduler-tomorrow', context).forEach((button) => {
        button.addEventListener('click', (event) => {
          event.preventDefault();
          const settings = drupalSettings.xedcScheduler || {};
          const root = button.parentElement;
          if (!root || !settings.date) {
            return;
          }
          const date = root.querySelector('input[type="date"]');
          const time = root.querySelector('input[type="time"]');
          if (date) {
            date.value = settings.date;
            date.dispatchEvent(new Event('input', { bubbles: true }));
            date.dispatchEvent(new Event('change', { bubbles: true }));
          }
          if (time) {
            time.value = settings.time || '08:00';
            time.dispatchEvent(new Event('input', { bubbles: true }));
            time.dispatchEvent(new Event('change', { bubbles: true }));
          }
        });
      });
    },
  };
})(Drupal, drupalSettings, once);
