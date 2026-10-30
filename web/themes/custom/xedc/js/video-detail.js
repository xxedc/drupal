(function () {
  function init() {
    var v = document.querySelector('.vd-player video.vd-video');
    if (!v || !window.Plyr) return;
    var hls = v.dataset.hls;
    if (hls) {
      if (v.canPlayType('application/vnd.apple.mpegurl')) { v.src = hls; }
      else if (window.Hls && Hls.isSupported()) { var h = new Hls(); h.loadSource(hls); h.attachMedia(v); }
    }
    new Plyr(v, {
      iconUrl: '/themes/custom/xedc/js/plyr.svg',
      controls: ['play-large', 'play', 'progress', 'current-time', 'duration', 'mute', 'volume', 'settings', 'pip', 'fullscreen'],
      settings: ['speed'],
      speed: { selected: 1, options: [0.5, 0.75, 1, 1.25, 1.5, 2] },
      keyboard: { focused: true, global: false },
      resetOnEnd: true,
      i18n: { play: Drupal.t('播放'), pause: Drupal.t('暂停'), mute: Drupal.t('静音'), unmute: Drupal.t('取消静音'), settings: Drupal.t('设置'), speed: Drupal.t('倍速'), normal: Drupal.t('正常'), pip: Drupal.t('画中画'), enterFullscreen: Drupal.t('全屏'), exitFullscreen: Drupal.t('退出全屏'), volume: Drupal.t('音量'), menuBack: Drupal.t('返回'), currentTime: Drupal.t('当前时间'), duration: Drupal.t('时长'), seek: Drupal.t('拖动进度') }
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
