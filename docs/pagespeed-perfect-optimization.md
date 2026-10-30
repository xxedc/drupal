# PageSpeed 完善优化说明

站点：https://gitxx.xyz  
主题：`web/themes/custom/xedc`  
品牌：DcLili  
日期：2026-10-30

本次只改主题资源加载、首页轮播图的同源缩放，以及确认不再调用 jQuery 的统计脚本。视觉尺寸、裁切锚点和交互未改。

PageSpeed Insights API 返回配额用尽（HTTP 429），没有新的实验室分数。下列体积来自本机 `curl --resolve gitxx.xyz:443:127.0.0.1` 对线上 HTML 和衍生图的测量。

## 已完成

### 1. 收掉未使用的 Bootstrap 组件和响应式工具类

`src/scss/_bootstrap.scss` 不再引入 `button-group`、`navbar`、`badge`、`progress`、`list-group`。公开模板使用自有顶栏，不用这些组件。

在 `utilities/api` 之前把全部工具类的 `responsive` 和 `print` 设为 `false`。基础类保留：`py-5`、`mb-3`、`mt-3`、`d-flex`、`d-none`、`d-inline-flex`、`container`、`col-md-10`、`offset-md-2`、`btn-primary`、`form-control`、`pagination`、`visually-hidden` 等。栅格断点仍在 grid 组件里，不受这次开关影响。

构建后 `build/css/main.style.css` 为 193393 字节。首页 CSS 聚合约 238506 字节（1384 + 237122）。上一轮首页聚合约 315KB，渲染阻塞 CSS 大约少 77KB。

### 2. 首页不再下载 jQuery

Matomo 的页面浏览仍由头部内联脚本完成（`matomo.js` 本身已是 defer + async）。`js/matomo.js` 只做 mailto 和 Colorbox，已换成 `js/matomo-lite.js`：

- mailto 用原生 `mousedown` / `keyup` / `touchstart`
- Colorbox 仅在页面已经有 jQuery 时绑定

节点统计 `statistics.js` 换成 `js/statistics-lite.js`，用 `fetch` POST，不再用 `$.ajax`。

`libraries-override` 能替换脚本路径，不能按名字删掉列表形式的依赖。去掉 jQuery 的逻辑在 `xedc_library_info_alter()`。评论表单库 `xedc/comment-form` 仍依赖 `core/jquery`。

测量：

| 页面 | jquery.min.js | 说明 |
| --- | --- | --- |
| `/` | 无 | 页脚脚本约 78492 字节，含 matomo-lite |
| `/meitu`、`/articles`、`/video`、`/models`、`/about`、`/user/login`、`/search` | 无 | |
| `/xiuren/130` | 有 | 评论表单、`core/drupal.ajax` |
| 文章全文、视频全文 | 有 | `xedc_member/member` 依赖 `core/drupal.ajax`，Ajax 需要 jQuery |

首页少一次约 79KB 的 jQuery。

### 3. 首页轮播增加 840 宽候选，不改裁切

新增图片样式 `xa_hero_840`：`image_scale` 宽 840、不放大、再转 WebP。与现有 `xa_hero`（宽 1200）同一比例。

`HomeCards` 只给 `xa_hero` 输出 `srcset`：`840w, 1200w`。首图 `loading=eager`、`fetchpriority=high`，其余 `loading=lazy`。`<link rel=preload>` 带上 `imagesrcset` 和 `imagesizes`。`sizes` 为 `(min-width: 1200px) 1200px, 100vw`。图片上没有加 width/height，避免把 cover 图缩进轨道、露出底色。

比例抽查：

| 文件 | 1200 样式 | 840 样式 |
| --- | --- | --- |
| IMG_3224（LCP） | 1200×1800，60514 字节 | 840×1260，37070 字节 |
| IMG_3008（后续懒加载） | 1200×2608，651154 字节 | 840×1826，272672 字节 |

宽屏仍选 1200。约 400 CSS 像素、2x 的手机可选 840，LCP 图大约少 23KB，那张高图大约少 378KB。

### 4. legal.css 只在有正文的完整节点上加载

`xedc/legal` 已从 `xedc.info.yml` 的全局库移除。`xedc_preprocess_node()` 在 `view_mode=full` 且节点有 `field_body` 时再附加。该字段在 article、page、video 上。首页 CSS 聚合不再包含这约 9.6KB。抽查 `/about` 和文章、视频全文仍带 `xedc/legal`。

### 5. 统计域预连接

`xedc_page_attachments_alter()` 增加一条 `<link rel="preconnect" href="https://x.gitxx.xyz">`。这是本站 Matomo，头部内联脚本会请求它。只加这一条，避免过多 preconnect。

### 6. 字体

主题字体栈是系统字体（`-apple-system`、`BlinkMacSystemFont`、`Inter`、`PingFang SC`、`Noto Sans SC`）。没有 `@font-face`，也没有 Google Fonts 请求。Inter 不会被下载。无需 `font-display`。

## 未处理及原因

- **图片衍生图没有 Cache-Control。** CSS/JS 聚合已是长期缓存。样式目录由 Nginx 直接送出，没有缓存头。规则禁止改 Nginx / PHP-FPM。要加 `Cache-Control` 需在服务器配置里做。
- **不把首屏 CSS 改成 `media=print` 再切回，也不内联关键 CSS。** 主样式在 head 里阻塞渲染，但推迟它会造成无样式闪动和布局偏移。这次用缩小文件来降低阻塞体积。
- **不给页脚 Drupal 聚合加 defer。** 设置脚本和聚合脚本的顺序要保持。拆开聚合可能改变行为。
- **不降低全局 WebP 质量（当前 JPEG 质量 75 同时作用于 GD WebP）。** 再压会改变观感。
- **不把轮播裁成 4:3 或 16:9。** 轨道是 `object-fit: cover`，焦点在 32% / 38%。核心 `image_scale_and_crop` 对不齐这个焦点，裁切会改变画面。
- **宽屏上 IMG_3008 仍是 1200×2608、约 651KB。** 它是懒加载的后续幻灯，不是 LCP。手机走 840 候选（约 273KB）。再缩小就要改裁切。
- **评论页和带会员 Ajax 的全文页仍加载 jQuery。** 这些脚本在用它。
- **没有新的 PageSpeed 分数。** API 配额为 0。
- **没有像素级截图对比。** 本机没有 Chrome / Chromium。

## 验证

已执行：

- `php -l`：`xedc.theme`、`HomeCards.php` 通过
- `node --check`：`matomo-lite.js`、`statistics-lite.js` 通过
- 主题目录 `npm run build`：退出码 0。Stylelint 1945 条既有警告、0 错误。`build/` 相对仓库 HEAD 只有 `main.style.css` 与 `main.script.js`；`main.script.js` 体积仍为 41592 字节
- `drush cr` 成功
- 图片样式 `xa_hero_840` 已写入运行中的配置，`config/sync/image.style.xa_hero_840.yml` 的 uuid 与运行配置一致

页面均为 200，标题带 DcLili：

`/`、`/meitu`、`/xiuren/130`、`/articles`、文章全文、`/video`、视频全文、`/user/login`、`/search?q=cos`、`/models`、`/sitemap`、`/about`、`/cosplay`

首页确认：无 `jquery.min.js`；首图 `srcset` 含 `840w` 与 `1200w`，`loading=eager`，`fetchpriority=high`；preload 含 `imagesrcset`；有指向 `x.gitxx.xyz` 的 preconnect；内联 Matomo 仍 `trackPageView`。文章全文脚本含 `URLSearchParams`（统计）和 mailto 的 `closest`（matomo-lite）。`/meitu` 的脚本仍含图集标题栏逻辑。构建后的 CSS 仍含 `.py-5`、`.mb-3`、`.container`、`.col-md-10`、`.btn-primary`、`.form-control`、`.visually-hidden`，不含 `.navbar-expand` 和 `.d-md-none`。

## 建议再人工看一眼

- 桌面和手机各看一次首页轮播，确认首图和后续高图的构图与改前一致（比例已核对，焦点未改）
- 打开一篇带评论的图集，发一条评论，确认 jQuery 表单仍可用
- 点一个 `mailto:` 链接，在 Matomo 里看是否还有 Mails / Click
- 若有 Colorbox 页面，打开后看是否仍记一次浏览
- 登录后看文章页会员相关 Ajax 是否正常
- 若要给 `/sites/default/files/styles/` 加缓存头，在 Nginx 单独配置，不要改主题
