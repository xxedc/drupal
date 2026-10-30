/**
 * @file
 * Node view counter without a jQuery dependency.
 */
(function (drupalSettings) {
  window.setTimeout(function () {
    var statistics = drupalSettings.statistics;
    if (!statistics || !statistics.url) {
      return;
    }
    var body = new URLSearchParams(statistics.data || {});
    window.fetch(statistics.url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
      body: body.toString(),
      cache: 'no-store',
    });
  });
})(drupalSettings);
