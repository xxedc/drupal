#!/bin/bash
# dclili 导航 v2 | 用法: bash update-nav.sh
set -e
T=/var/www/drupal/web/themes/custom/xedc
cd "$T"
mkdir -p css js templates/includes
for f in templates/includes/xedc-header.html.twig css/xedc-navbar.css js/xedc-navbar.js; do
  [ -f "$f" ] && cp "$f" "$f.v1.bak"
done

# ---------- Twig ----------
cat > templates/includes/xedc-header.html.twig <<'TWIGEOF'
{{ attach_library('xedc/navbar') }}
{% set search_action = '/search/node' %}
{% set search_name = 'keys' %}
{% set i_search %}<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>{% endset %}
{% set i_chev %}<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>{% endset %}

<header class="xn" data-xn>
  <div class="xn-bar">
    <div class="xn-left">
      <a class="xn-logo" href="{{ path('<front>') }}" aria-label="dclili">dclili<i class="xn-dot"></i></a>
      <nav class="xn-links" aria-label="主导航">
        {% for item in xn.items|default([]) %}
          {% if item.cats %}
            <div class="xn-dd">
              <a class="xn-link" href="{{ item.url }}">{{ item.title }}</a>
              <button type="button" class="xn-dd-btn" aria-expanded="false" aria-label="展开{{ item.title }}分类">{{ i_chev }}</button>
              <div class="xn-dd-panel"><div class="xn-dd-card">
                <div class="xn-dd-grid" style="--cols: {{ min(item.cats|length, 4) }}">
                  {% for c in item.cats %}
                    <div class="xn-dd-col">
                      <a class="xn-dd-h" href="{{ c.url }}">{{ c.name }}</a>
                      {% for ch in c.children %}<a class="xn-dd-i" href="{{ ch.url }}">{{ ch.name }}</a>{% endfor %}
                    </div>
                  {% endfor %}
                </div>
                <a class="xn-dd-all" href="{{ item.url }}">查看全部{{ item.title }} →</a>
              </div></div>
            </div>
          {% else %}
            <a class="xn-link" href="{{ item.url }}">{{ item.title }}</a>
          {% endif %}
        {% endfor %}
      </nav>
    </div>

    <form class="xn-search" action="{{ search_action }}" method="get" role="search">
      {{ i_search }}
      <input type="search" name="{{ search_name }}" placeholder="搜索美图、视频、文章…" autocomplete="off">
    </form>

    <div class="xn-actions">
      <button type="button" class="xn-icon xn-only-m" data-xn-search aria-label="搜索">{{ i_search }}</button>
      <button type="button" class="xn-icon xn-theme" data-xn-theme aria-label="切换主题">
        <svg class="xn-moon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/></svg>
        <svg class="xn-sun" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2m-7.07-2.93 1.41-1.41m11.32-11.32 1.41-1.41M2 12h2m16 0h2M4.93 4.93l1.41 1.41m11.32 11.32 1.41 1.41"/></svg>
      </button>
      {% if logged_in %}
        <a class="xn-icon" href="{{ path('user.page') }}" aria-label="我的账户"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg></a>
      {% else %}
        <a class="xn-icon xn-only-m" href="{{ path('user.login') }}" aria-label="登录"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg></a>
        <a class="xn-text xn-only-d" href="{{ path('user.login') }}">登录</a>
        <a class="xn-text xn-only-d" href="{{ path('user.register') }}">注册</a>
      {% endif %}
      <button type="button" class="xn-icon xn-only-m" data-xn-open aria-label="打开菜单" aria-controls="xn-sheet">
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"/></svg>
      </button>
    </div>
  </div>

  <form class="xn-msearch" action="{{ search_action }}" method="get" role="search">
    {{ i_search }}
    <input type="search" name="{{ search_name }}" placeholder="搜索美图、视频、文章…" autocomplete="off">
  </form>
</header>

<div class="xn-overlay" data-xn-close></div>
<aside class="xn-sheet" id="xn-sheet" aria-hidden="true" aria-label="菜单">
  <div class="xn-sheet-head">
    <a class="xn-logo" href="{{ path('<front>') }}">dclili<i class="xn-dot"></i></a>
    <button type="button" class="xn-icon" data-xn-close aria-label="关闭菜单"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"/></svg></button>
  </div>
  <nav class="xn-sheet-nav">
    {% for item in xn.items|default([]) %}
      {% if item.cats %}
        <div class="xn-acc">
          <div class="xn-row">
            <a class="xn-m-link" href="{{ item.url }}">{{ item.title }}</a>
            <button type="button" class="xn-chev" aria-expanded="false" aria-label="展开分类">{{ i_chev }}</button>
          </div>
          <div class="xn-panel"><div>
            <a class="xn-m-sub" href="{{ item.url }}">全部{{ item.title }}</a>
            {% for c in item.cats %}
              {% if c.children %}
                <div class="xn-acc">
                  <div class="xn-row">
                    <a class="xn-m-sub" href="{{ c.url }}">{{ c.name }}</a>
                    <button type="button" class="xn-chev" aria-expanded="false" aria-label="展开二级分类">{{ i_chev }}</button>
                  </div>
                  <div class="xn-panel"><div>
                    {% for ch in c.children %}<a class="xn-m-sub xn-m-sub2" href="{{ ch.url }}">{{ ch.name }}</a>{% endfor %}
                  </div></div>
                </div>
              {% else %}
                <a class="xn-m-sub" href="{{ c.url }}">{{ c.name }}</a>
              {% endif %}
            {% endfor %}
          </div></div>
        </div>
      {% else %}
        <div class="xn-row"><a class="xn-m-link" href="{{ item.url }}">{{ item.title }}</a></div>
      {% endif %}
    {% endfor %}
  </nav>
  <div class="xn-sheet-foot">
    {% if logged_in %}
      <a class="xn-btn xn-btn-ghost" href="{{ path('user.page') }}">我的账户</a>
      <a class="xn-btn xn-btn-primary" href="{{ path('user.logout') }}">退出</a>
    {% else %}
      <a class="xn-btn xn-btn-ghost" href="{{ path('user.login') }}">登录</a>
      <a class="xn-btn xn-btn-primary" href="{{ path('user.register') }}">注册</a>
    {% endif %}
  </div>
</aside>
TWIGEOF

# ---------- CSS ----------
cat > css/xedc-navbar.css <<'CSSEOF'
:root{--xn-bg:#fff;--xn-fg:#09090b;--xn-muted:#71717a;--xn-border:#e4e4e7;--xn-accent:#f4f4f5;--xn-pri:#18181b;--xn-pri-fg:#fafafa;--xn-bgrgb:255,255,255;--xn-shadow:0 1px 2px rgba(0,0,0,.05),0 8px 20px -8px rgba(0,0,0,.14)}
[data-bs-theme=dark],[data-theme=dark]{--xn-bg:#09090b;--xn-fg:#fafafa;--xn-muted:#a1a1aa;--xn-border:#27272a;--xn-accent:#18181b;--xn-pri:#fafafa;--xn-pri-fg:#18181b;--xn-bgrgb:9,9,11;--xn-shadow:0 1px 2px rgba(0,0,0,.4),0 8px 20px -8px rgba(0,0,0,.6)}
.xn,.xn-sheet,.xn-overlay{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Inter","PingFang SC","Microsoft YaHei",sans-serif;-webkit-tap-highlight-color:transparent}
.xn svg,.xn-sheet svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round;flex:none}

/* header：边框 + 阴影，与下方内容区分 */
.xn{position:sticky;top:0;z-index:1030;background:rgba(var(--xn-bgrgb),.92);-webkit-backdrop-filter:saturate(180%) blur(12px);backdrop-filter:saturate(180%) blur(12px);border-bottom:1px solid var(--xn-border);box-shadow:var(--xn-shadow);color:var(--xn-fg)}
.xn-bar{display:flex;align-items:center;gap:20px;height:58px;max-width:1440px;margin:0 auto;padding:0 20px}
.xn-left{display:flex;align-items:center;gap:20px;min-width:0}

/* logo */
.xn-logo{display:inline-flex;align-items:baseline;font-size:22px;font-weight:800;letter-spacing:-.055em;line-height:1;color:var(--xn-fg);text-decoration:none;flex:none}
.xn-logo:hover{color:var(--xn-fg)}
.xn-dot{display:inline-block;width:.3em;height:.3em;margin-left:.07em;border-radius:50%;background:linear-gradient(135deg,#f472b6,#8b5cf6)}

/* links */
.xn-links{display:flex;align-items:center;gap:2px}
.xn-link{padding:6px 12px;border-radius:6px;font-size:14px;font-weight:500;color:var(--xn-muted);text-decoration:none;transition:background .15s,color .15s}
.xn-link:hover{background:var(--xn-accent);color:var(--xn-fg)}
.xn-link[aria-current]{color:var(--xn-fg)}

/* 下拉（PC 美图二级） */
.xn-dd{position:relative;display:flex;align-items:center;border-radius:6px;transition:background .15s}
.xn-dd:hover,.xn-dd.open{background:var(--xn-accent)}
.xn-dd>.xn-link{padding-right:2px;background:none}
.xn-dd:hover>.xn-link,.xn-dd.open>.xn-link{color:var(--xn-fg)}
.xn .xn-dd-btn{display:inline-flex;align-items:center;justify-content:center;width:22px;height:30px;margin-right:6px;padding:0;border:0;background:none;color:var(--xn-muted);cursor:pointer}
.xn .xn-dd-btn svg{width:14px;height:14px;transition:transform .2s}
.xn-dd:hover .xn-dd-btn svg,.xn-dd.open .xn-dd-btn svg{transform:rotate(180deg)}
.xn-dd-panel{position:absolute;top:100%;left:0;padding-top:10px;opacity:0;visibility:hidden;transform:translateY(-4px);transition:opacity .15s,transform .15s,visibility 0s .15s;z-index:5}
.xn-dd:hover .xn-dd-panel,.xn-dd.open .xn-dd-panel{opacity:1;visibility:visible;transform:none;transition-delay:0s}
.xn-dd-card{min-width:240px;padding:12px;background:var(--xn-bg);border:1px solid var(--xn-border);border-radius:10px;box-shadow:0 12px 32px -8px rgba(0,0,0,.2)}
.xn-dd-grid{display:grid;grid-template-columns:repeat(var(--cols,3),minmax(130px,1fr));gap:6px 12px}
.xn-dd-col{display:flex;flex-direction:column}
.xn-dd-h,.xn-dd-i{display:block;padding:6px 8px;border-radius:6px;text-decoration:none;white-space:nowrap;transition:background .15s,color .15s}
.xn-dd-h{font-size:14px;font-weight:600;color:var(--xn-fg)}
.xn-dd-i{font-size:13px;color:var(--xn-muted)}
.xn-dd-h:hover,.xn-dd-i:hover{background:var(--xn-accent);color:var(--xn-fg)}
.xn-dd-all{display:block;margin-top:10px;padding:10px 8px 2px;border-top:1px solid var(--xn-border);font-size:13px;color:var(--xn-muted);text-decoration:none}
.xn-dd-all:hover{color:var(--xn-fg)}

/* search */
.xn-search,.xn-msearch{position:relative;display:flex;align-items:center}
.xn-search svg,.xn-msearch svg{position:absolute;left:10px;width:16px;height:16px;color:var(--xn-muted);pointer-events:none}
.xn-search input,.xn-msearch input{width:100%;height:36px;padding:0 12px 0 32px;border:1px solid var(--xn-border);border-radius:6px;background:transparent;color:var(--xn-fg);font-size:14px;outline:0;-webkit-appearance:none;appearance:none;transition:box-shadow .15s,border-color .15s}
.xn-search input::placeholder,.xn-msearch input::placeholder{color:var(--xn-muted)}
.xn-search input:focus,.xn-msearch input:focus{border-color:var(--xn-muted);box-shadow:0 0 0 3px rgba(113,113,122,.18)}
.xn-msearch{display:none;padding:0 20px 12px}
.xn-msearch svg{left:30px;top:10px}
.xn-msearch input{font-size:16px}
.xn-search-open .xn-msearch{display:flex}

/* actions */
.xn-actions{display:flex;align-items:center;gap:4px}
.xn-icon{display:inline-flex;align-items:center;justify-content:center;width:36px;height:36px;padding:0;border:0;border-radius:6px;background:transparent;color:var(--xn-fg);cursor:pointer;text-decoration:none;transition:background .15s}
.xn-icon:hover{background:var(--xn-accent);color:var(--xn-fg)}
.xn-text{display:inline-flex;align-items:center;padding:6px 10px;border-radius:6px;font-size:14px;font-weight:500;color:var(--xn-muted);text-decoration:none;transition:color .15s,background .15s}
.xn-text:hover{color:var(--xn-fg);background:var(--xn-accent)}
.xn-btn{display:inline-flex;align-items:center;justify-content:center;height:36px;padding:0 14px;border-radius:6px;font-size:14px;font-weight:500;text-decoration:none;border:1px solid transparent;transition:background .15s,opacity .15s}
.xn-btn-ghost{color:var(--xn-fg)}
.xn-btn-ghost:hover{background:var(--xn-accent);color:var(--xn-fg)}
.xn-btn-primary{background:var(--xn-pri);color:var(--xn-pri-fg)}
.xn-btn-primary:hover{opacity:.9;color:var(--xn-pri-fg)}
.xn-sun{display:none}
[data-bs-theme=dark] .xn-sun,[data-theme=dark] .xn-sun{display:block}
[data-bs-theme=dark] .xn-moon,[data-theme=dark] .xn-moon{display:none}

.xn-only-m{display:none}

/* 桌面 */
@media (min-width:992px){
  .xn-search{flex:1;max-width:420px;margin:0 auto}
  .xn-actions .xn-theme{order:9}
  .xn-actions{margin-left:0}
  .xn-sheet,.xn-overlay{display:none}
}
@media (min-width:1200px){
  .xn-bar{display:grid;grid-template-columns:1fr minmax(300px,420px) 1fr}
  .xn-search{max-width:none;margin:0}
  .xn-actions{justify-self:end}
}

/* 手机 */
@media (max-width:991.98px){
  .xn-links,.xn-search,.xn-only-d{display:none}
  .xn-only-m{display:inline-flex}
  .xn-actions{margin-left:auto}
  .xn-bar{gap:8px;padding:0 12px 0 16px}
}

/* 右侧抽屉 */
.xn-overlay{position:fixed;inset:0;z-index:1040;background:rgba(0,0,0,.45);opacity:0;visibility:hidden;transition:opacity .25s,visibility 0s .25s}
.xn-sheet{position:fixed;top:0;right:0;left:auto;bottom:0;z-index:1050;display:flex;flex-direction:column;width:min(72vw,280px);background:var(--xn-bg);color:var(--xn-fg);border-left:1px solid var(--xn-border);box-shadow:-8px 0 30px rgba(0,0,0,.1);transform:translate3d(100%,0,0);visibility:hidden;transition:transform .3s cubic-bezier(.32,.72,0,1),visibility 0s .3s}
html.xn-open{overflow:hidden}
html.xn-open .xn-overlay{opacity:1;visibility:visible;transition-delay:0s}
html.xn-open .xn-sheet{transform:none;visibility:visible;transition-delay:0s}
.xn-sheet-head{display:flex;align-items:center;justify-content:space-between;height:58px;padding:0 10px 0 18px;border-bottom:1px solid var(--xn-border);flex:none}
.xn-sheet-nav{flex:1;overflow-y:auto;padding:8px;-webkit-overflow-scrolling:touch}
.xn-row{display:flex;align-items:center}
.xn-row>a{flex:1}
.xn-m-link,.xn-m-sub{display:block;padding:11px 12px;border-radius:6px;font-size:15px;font-weight:500;color:var(--xn-fg);text-decoration:none}
.xn-m-link:active,.xn-m-sub:active,.xn-m-link:hover,.xn-m-sub:hover{background:var(--xn-accent);color:var(--xn-fg)}
.xn-m-link[aria-current]{background:var(--xn-accent)}
.xn-m-sub{font-size:14px;font-weight:400;color:var(--xn-muted)}
.xn-m-sub[aria-current]{color:var(--xn-fg);font-weight:500}
.xn-m-sub2{padding-left:14px}
.xn-chev{display:inline-flex;align-items:center;justify-content:center;width:40px;height:40px;border:0;border-radius:6px;background:transparent;color:var(--xn-muted);cursor:pointer}
.xn-chev svg{transition:transform .2s}
.xn-acc.open>.xn-row>.xn-chev svg{transform:rotate(180deg)}
.xn-panel{display:grid;grid-template-rows:0fr;transition:grid-template-rows .25s ease}
.xn-panel>div{overflow:hidden;visibility:hidden;min-height:0;margin-left:12px;padding-left:8px;border-left:1px solid var(--xn-border);transition:visibility 0s .25s}
.xn-acc.open>.xn-panel{grid-template-rows:1fr}
.xn-acc.open>.xn-panel>div{visibility:visible;transition-delay:0s}
.xn-sheet-foot{display:flex;gap:8px;padding:12px 14px calc(12px + env(safe-area-inset-bottom));border-top:1px solid var(--xn-border);flex:none}
.xn-sheet-foot .xn-btn{flex:1;border-color:var(--xn-border)}
.xn-sheet-foot .xn-btn-primary{border-color:transparent}
CSSEOF

# ---------- JS ----------
cat > js/xedc-navbar.js <<'JSEOF'
(function () {
  var d = document, h = d.documentElement;
  function qa(s, r) { return Array.prototype.slice.call((r || d).querySelectorAll(s)); }

  // 主题
  function setTheme(t) {
    h.setAttribute('data-bs-theme', t); h.setAttribute('data-theme', t);
    try { localStorage.setItem('theme', t); } catch (e) {}
  }
  try { var s = localStorage.getItem('theme'); if (s === 'dark' || s === 'light') setTheme(s); } catch (e) {}
  qa('[data-xn-theme]').forEach(function (b) {
    b.addEventListener('click', function () {
      setTheme(h.getAttribute('data-bs-theme') === 'dark' ? 'light' : 'dark');
    });
  });

  // 抽屉与遮罩挂到 body，避免被父级 transform 影响 fixed 定位
  var sheet = d.getElementById('xn-sheet');
  var overlay = d.querySelector('.xn-overlay');
  if (overlay) d.body.appendChild(overlay);
  if (sheet) d.body.appendChild(sheet);

  function openSheet() { h.classList.add('xn-open'); if (sheet) sheet.setAttribute('aria-hidden', 'false'); }
  function closeSheet() { h.classList.remove('xn-open'); if (sheet) sheet.setAttribute('aria-hidden', 'true'); }
  qa('[data-xn-open]').forEach(function (b) { b.addEventListener('click', openSheet); });
  qa('[data-xn-close]').forEach(function (b) { b.addEventListener('click', closeSheet); });

  // 抽屉手风琴（默认收起）
  qa('.xn-chev').forEach(function (b) {
    b.addEventListener('click', function () {
      var acc = b.closest('.xn-acc');
      var on = acc.classList.toggle('open');
      b.setAttribute('aria-expanded', on ? 'true' : 'false');
    });
  });

  // PC 下拉：悬停（CSS）或点击箭头
  var dds = qa('.xn-dd');
  function closeDD() {
    dds.forEach(function (x) {
      x.classList.remove('open');
      x.querySelector('.xn-dd-btn').setAttribute('aria-expanded', 'false');
    });
  }
  dds.forEach(function (dd) {
    var b = dd.querySelector('.xn-dd-btn');
    b.addEventListener('click', function (e) {
      e.stopPropagation();
      var on = !dd.classList.contains('open');
      closeDD();
      if (on) { dd.classList.add('open'); b.setAttribute('aria-expanded', 'true'); }
    });
  });
  d.addEventListener('click', function (e) { if (!e.target.closest('.xn-dd')) closeDD(); });
  d.addEventListener('keydown', function (e) { if (e.key === 'Escape') { closeSheet(); closeDD(); } });
  window.addEventListener('resize', function () { if (window.innerWidth >= 992) closeSheet(); });

  // 手机搜索
  var hd = d.querySelector('[data-xn]');
  qa('[data-xn-search]').forEach(function (b) {
    b.addEventListener('click', function () {
      var on = hd.classList.toggle('xn-search-open');
      if (on) { var i = hd.querySelector('.xn-msearch input'); if (i) i.focus(); }
    });
  });

  // 当前页高亮
  var cur = location.pathname.replace(/\/$/, '') || '/';
  qa('.xn-link,.xn-m-link,.xn-m-sub').forEach(function (a) {
    var p = a.pathname.replace(/\/$/, '') || '/';
    if (p === cur || (p !== '/' && cur.indexOf(p + '/') === 0)) a.setAttribute('aria-current', 'page');
  });
})();
JSEOF

cd /var/www/drupal && vendor/bin/drush cr
echo "OK 已更新并清缓存，刷新页面（手机建议强制刷新/关掉标签重开）"
