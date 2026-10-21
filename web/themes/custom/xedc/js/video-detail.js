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
      i18n: { play: '播放', pause: '暂停', mute: '静音', unmute: '取消静音', settings: '设置', speed: '倍速', normal: '正常', pip: '画中画', enterFullscreen: '全屏', exitFullscreen: '退出全屏', volume: '音量', menuBack: '返回', currentTime: '当前时间', duration: '时长', seek: '拖动进度' }
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
