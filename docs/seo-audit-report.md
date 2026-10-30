# XEDC SEO 审计报告

- 日期：2026-10-30
- 项目：`/var/www/drupal`（Drupal 11.4.11，主题 `web/themes/custom/xedc`）
- 线上域名：`https://gitxx.xyz`（Nginx `server_name gitxx.xyz www.gitxx.xyz`，前面有 Cloudflare）
- 站点名：`DcLili`（`config/sync/system.site.yml`）
- 范围：只读审计。未改代码、未执行 `drush cim` / `cex` / `updb` / `cr`，未提交。
- 对照：`docs/SEO-AUDIT-2026-10-25.md`、`docs/SEO-FIX-B-2026-10-25.md` 中的部分项已经落地（sitemap 可访问、文章/视频别名、详情页 description 与 OG）。本报告以当前代码、配置和线上 HTML 为准。

## 1. 项目信息与概述

这是一个以图片、视频、文章和人物（模特）页为主的中文站。图片详情、分类列表和首页是抓取与图片搜索的核心页面。

本次没有找到独立的爬虫模块 `drupal/seo_audit`。`composer.json` 里安装并启用的是：

| 包 | 作用 | 是否会爬页面 |
|---|---|---|
| `drupal/audit`（子模块 `audit_seo` 等） | 检查模块、Pathauto、Metatag、robots、图片字段配置 | 否 |
| `drupal/site_audit` | 最佳实践、内容、缓存、扩展、状态等报告 | 否 |

因此「SEO Audit 73 分」衡量的是配置完整度，不包含标题重复、alt 质量、H1、JSON-LD、www 重复这些只能在 HTML 里看到的问题。下面第 3、4 节把模块分数和线上抽查合在一起。

当前判断：抓取基础（HTTPS、sitemap 正文、详情页 canonical、搜索 noindex）已经可用，但主机名重复、分类 URL、图片展示尺寸、alt、结构化数据仍会限制图片搜索和富结果。不建议在修好 www 与 sitemap 声明之前做大规模提交。

已安装的 SEO 相关模块：Metatag（含 Open Graph、Twitter Cards、Routes、Views、Verification）、Pathauto、Simple XML Sitemap（含 Engines、Views）、Redirect（含 404、Domain）。未安装：`robotstxt`、`schema_metatag`、`drupal/seo_audit`。

线上抽查（2026-10-30，`https://gitxx.xyz`）：

| 页面 | 结果 |
|---|---|
| `/`、`/sitemap.xml` | 200。sitemap 为 `application/xml`，约 117 个 URL、约 274 条 `image:loc` |
| `/robots.txt` | 200，但内容是 Cloudflare 托管规则拼上源站 `web/robots.txt`，没有 `Sitemap:` |
| `https://www.gitxx.xyz/` | 200，无 301，canonical 指向 www |
| `/en` | 200，canonical 指向 `https://gitxx.xyz/`，英文节点译文 0 条 |
| `/bizhi/1`、文章别名、视频别名 | 200，有 description / OG / Twitter，无 JSON-LD |
| `/models/20` | 200，`<title>` 为「模特 \| DcLili」，`<h1>` 为「莉莉」，无 description |
| `/node/13` | 200，已发布测试标题，canonical 就是 `/node/13` |
| `/articles?cat=999999` | 404（10 月 25 日为 500），canonical 仍指向 `/articles` |
| `/search`、`/user/login` | noindex |

## 2. SEO Audit 与 Site Audit 模块设置评估

### 2.1 `drupal/audit`（界面里的 SEO Audit）

配置：`config/sync/audit.settings.yml`、`config/sync/audit_seo.settings.yml`、`config/sync/audit_images.settings.yml`。

2026-10-30 重新执行：

```bash
drush audit:run seo,images,url,cache,performance,twig,views,status --format=json
```

| 分析器 | 分数 | 与本站的关系 |
|---|---|---|
| seo | 73/100 C | 必要模块齐全；URL 模式 5/15；robots 缺少 Sitemap |
| images | 91/100 A | 只检查字段是否启用响应式图，看不到主题里的 alt 和 450×800 裁剪 |
| url | 98/100 A | 1 条 error：别名 `/search` 与搜索路由重叠；页面本身 200 且 noindex |
| views | 64/100 D | 首页三个视图未开缓存；列表使用泛化 `node_list` 标签 |
| performance | 77/100 C | 聚合与页面缓存已开；会员中心有 N+1 |
| cache | 33/100 F | 多个缓存 bin 在数据库；两处 `max-age: 0` |
| twig | 27/100 F | 大量「未输出 content」误报；照片相关推荐的 `drupal_entity()` 循环是真问题 |
| status | 57/100 F | 匿名用户记录缺失、待运行数据库更新、Colorbox 库未安装、IndexNow 密钥缺失 |

`audit_seo` 的忽略开关全部为 `false`（会检查 sitemap、robots、metatag、redirect、pathauto）。这适合生产环境，不需要为了提分去忽略。

适合本站的部分：

- 扫描目录限于 `web/modules/custom` 与 `web/themes/custom`。
- `audit_images.settings.yml` 中 `require_responsive_image: true`，能提示媒体图片未用响应式样式。
- 权重里 images / seo 为 3，performance 为 4，对图片站合理。

不适合直接放在生产并提交到 Git 的部分：

1. `audit.settings.yml` 写入了 Druscan 的 `project_api_key` 和 `environment_api_key`。密钥已进入配置库。应在 Druscan 后台轮换，并从 Git 历史中移除；密钥改放到环境变量或 `settings.php`（该文件不进库）。本报告不摘录密钥原文。
2. `audit_phpcs`、`audit_phpstan`、`audit_phpunit`、`audit_duplication` 是开发检查，PHPStan 上次为 0 分。生产环境可以只保留 seo、images、url、cache、performance、status、views。
3. `execution_timeout: 60` 对 PHPStan 全量扫描偏短。
4. 排除规则含 `*.js`、`*.css`，主题脚本不在扫描内。图片 SEO 仍要靠模板抽查，不能只看这个分数。
5. 该模块没有并发、深度、是否遵守 robots.txt 等爬虫设置。这些设置属于未安装的 `drupal/seo_audit`。

### 2.2 `drupal/site_audit`

配置：`config/sync/site_audit.settings.yml`、`config/sync/site_audit_send.settings.yml`。

- 已启用报告：best_practices、block、cache、codebase、content、cron、database、extensions、security、status、views、watchdog。
- `users: 0`：用户报告被关掉。状态报告已经报「匿名用户不存在」，这个报告应打开。
- `site_audit_report` 表行数为 0。`cron_save_interval`、`cron_send_interval` 都是 0，报告跑完不落库、不外发。`remote_url` 为空。
- 没有单独的 SEO 权重或爬虫深度。内容报告能查重复标题；本次数据库里视频标题「墨迹二班测试视频标题」有 nid 8 和 nid 9 两条。

建议：

- 把 `reports.users` 设为 `users`。
- 若要留档，把 `cron_save_interval` 设为 `86400`。不需要远程投递就保持 `remote_url` 为空。
- 生产上保留 content、status、cache、watchdog、extensions 即可。codebase 体积扫描对 SEO 没有帮助。

### 2.3 对图片站是否合适

两个模块都适合作为配置回归检查，不适合代替 Search Console 或对 HTML 的抽查。图片站还需要自己看：详情页 `<img>` 的 src 是不是未裁剪大图、alt 是否描述画面、sitemap 的 `image:loc` 是否等于页面上的 src、分类页是否有唯一的 title 和一段介绍。

## 3. 优先级总览

| 问题描述 | 严重程度 | 影响范围 | 建议优先级 |
|---|---|---|---|
| www 与非 www 都返回 200，且各自 canonical 指向自己 | Critical | 全站重复 | P0 |
| 源站 robots 未声明 Sitemap；Cloudflare 对 Baiduspider、GoogleOther 整站 `Disallow: /` | Critical | 发现与百度抓取 | P0 |
| 约 10 篇已发布美图没有别名，以 `/node/NID` 被收录，标题为测试/乱码 | High | 图片收录质量 | P0 |
| 美图详情主图使用 `images_450x800` 居中裁剪；同一封面出现 3 次且都是 `fetchpriority=high` | High | 图片搜索、LCP | P0 |
| 全站无 JSON-LD | High | 富结果、图片/视频理解 | P1 |
| 媒体图片 `alt_field: false`，现有 alt 多为「海边」「测试」「图N」 | High | 图片搜索 | P1 |
| 模特页 `<title>` 全部是「模特 \| DcLili」，无 meta description；头像 `alt=""` | High | 人物集群 | P1 |
| 视频栏目、多数文章栏目 canonical 为 `/taxonomy/term/TID` | High | 分类收录 | P1 |
| sitemap 图片 URL 多为原图 jpg/png，页面展示的是 webp/avif 样式图 | High | 图片 sitemap | P1 |
| 英文前缀 `/en` 无译文，仍出现在 sitemap 和 hreflang | Medium | 重复 URL | P1 |
| 分类页 description 依赖术语描述，`/bizhi`、`/tags`、模特页为空 | Medium | 摘要 | P2 |
| 美图 URL 为 `/栏目路径/[nid]`，路径里没有标题 | Medium | 关键词 | P2 |
| 视频重复标题；description 在分类为空时变成「标题 -」 | Medium | 视频 | P2 |
| 视频相关图 alt 为空、用原图、全部 lazy；播放器只有 `poster` | Medium | 视频图片 | P2 |
| 首页品牌混用 DcLili / XEDC；keywords 为「美女,野兽」 | Medium | 品牌与摘要 | P2 |
| 列表/首页图片无 srcset；响应式样式「宽」「窄」未使用 | Medium | CWV | P2 |
| 标签索引和登录页双 H1 | Medium | 语义 | P3 |
| 非法筛选 404 的 canonical 指向 `/articles` | Medium | 抓取 | P3 |
| 首页三个视图无缓存；照片相关推荐在 Twig 里 `drupal_entity()` | Medium | TTFB | P3 |
| 匿名用户 uid 0 不存在；`xedc_member` 有待运行更新；Colorbox 库缺失；IndexNow 无密钥 | Medium | 站点健康 | P3 |
| Audit 密钥写入 `config/sync`；开发用分析器在生产启用 | Medium | 安全与噪音 | P3 |

## 4. 详细修改建议

### P0-1 www 与非 www 同时可索引

- 来源：线上响应。`https://www.gitxx.xyz/` 为 200，`<link rel="canonical" href="https://www.gitxx.xyz/">`。`https://gitxx.xyz/` 的 canonical 指向非 www。
- 位置：`web/.htaccess` 第 106–110 行去掉 www 的规则仍被注释。站点由 Nginx 提供，这段规则不会生效。`config/sync/redirect_domain.domains.yml` 的 `domain_redirects` 为空。Metatag 使用 `[site:url]` / `[current-page:url]`，会跟着当前 Host 走。`simple_sitemap.settings.yml` 的 `base_url` 已是 `https://gitxx.xyz`。
- 修改：在 Nginx 的 www `server` 中整站 301 到非 www（不要只靠 canonical）：

```nginx
server {
    listen 443 ssl;
    server_name www.gitxx.xyz;
    return 301 https://gitxx.xyz$request_uri;
}
```

改完后抽查 `curl -sI https://www.gitxx.xyz/bizhi/1`，期望 `301` 且 `Location: https://gitxx.xyz/bizhi/1`。Cloudflare 若有自己的 Redirect Rule，与源站保持同一方向。
- 影响：合并两个主机的收录信号。在 301 生效前，www 页面会被当成另一套站点。

### P0-2 robots.txt 与 Cloudflare 爬虫策略

- 来源：`audit_seo` 警告 `ROBOTS_NO_SITEMAP`；线上 `/robots.txt` 4817 字节，源文件 `web/robots.txt` 2141 字节。
- 线上文件结构：Cloudflare「Managed content」在前面插入 `Content-Signal: search=yes,ai-train=no,use=reference`，并对一组爬虫 `Disallow: /`。源站 Drupal 默认规则附在末尾。全文没有 `Sitemap:`，也没有 `Disallow: /member`。
- 被整站禁止、且和中文站直接相关的爬虫：`Baiduspider`、`GoogleOther`。`Googlebot` 不在这份禁止名单里，主搜索仍可抓。`Bytespider`、`GPTBot`、`ClaudeBot`、`Google-Extended` 等训练爬虫也被禁止。
- 修改源站 `web/robots.txt`，在 `User-agent: *` 规则末尾增加：

```text
Disallow: /member
Disallow: /user/

Sitemap: https://gitxx.xyz/sitemap.xml
```

`/user/login` 等已经单独禁止；补上 `/user/` 可以挡住用户主页。不要 `Disallow: /node/`，因为仍有美图只存在 `/node/NID`，禁掉会让这些 URL 无法被抓，同时又已经出现在 sitemap 里。
- Cloudflare：在仪表盘的 AI Crawl Control / robots.txt 托管内容里，若需要百度收录，从禁止名单去掉 `Baiduspider`。`GoogleOther` 不负责网页排名，但会用于 Google 的其他抓取；图片站建议允许 `Googlebot` 与 `Googlebot-Image`（当前未单独禁止）。`ai-train=no` 只有在确认不想被用于模型训练时保留。
- 影响：搜索引擎才能从 robots 发现 sitemap。百度蜘蛛在规则放行之前不会抓本站。

### P0-3 下线或补齐 `/node/NID` 美图

- 来源：已发布 photo 41 篇里 10 篇没有 `path_alias`。sitemap 中有 10 条 `https://gitxx.xyz/node/` URL。抽查 `/node/13` 标题为「很多很多很好经济学家的」，200，无 noindex。
- 位置：Pathauto 模式 `config/sync/pathauto.pattern.gggg.yml`，pattern 为 `/[node:field_categories:entity:url:path]/[node:nid]`，只作用于有分类的美图。这 10 篇没有生成别名。
- 修改：
  1. 在内容后台把测试、乱码、无意义标题的美图设为未发布，或走现有审核流程撤下。不要为了「有别名」去保留垃圾页。
  2. 对需要保留的节点，确认 `field_categories` 有值后执行：

```bash
drush pathauto:aliases-generate update node --bundle=photo
```

  3. 再生成 sitemap：

```bash
drush simple-sitemap:generate
```

  4. 抽查 sitemap 中不再出现这些 `/node/NID`。若旧 URL 已被抓取，用 Redirect 模块做 301，`default_status_code` 已经是 301。
- 影响：减少软垃圾页进入索引，把抓取预算留给 `/bizhi/1` 这类正式详情。

### P0-4 美图详情不要用 450×800 裁剪图当主图

- 来源：`https://gitxx.xyz/bizhi/1` 的画廊 `<img>`。
- 位置：
  - `config/sync/core.entity_view_display.media.image.default.yml`：样式 `images_450x800`，`image_loading: lazy`。
  - `config/sync/image.style.images_450x800.yml`：`image_scale_and_crop` 450×800，再转 webp。
  - `config/sync/core.entity_view_display.node.photo.default.yml`：`field_cover_image` 与 `field_images` 都用媒体的 `default` 显示模式。
  - `web/themes/custom/xedc/templates/content/node--photo--full.html.twig`：输出上述字段；相关推荐第 98 行 `drupal_entity('media', ...)` 再次用 default 模式。
  - 同一封面 `IMG_3009.jpeg.webp` 在 HTML 里出现 3 次，每次都是 `width="450" height="800"`、`loading="eager"`、`fetchpriority="high"`。alt 为「海边」。
  - 灯箱缩略图在 `templates/includes/photo-all-sheet.html.twig` 使用 `max_650x650`，线上 URL 为 `.avif`，`alt=""`。
- 修改：
  1. 新建媒体显示模式 `gallery`（不要改 default，卡片仍可使用 450×800）。
  2. 该模式使用不裁剪的样式。可复制 `max_1300x1300`，确认转换结果与文件名一致。当前 `image.style.max_650x650.yml` 写的是 `extension: webp`，线上衍生物却是 `.avif`，先在「配置 > 媒体 > 图片样式」里对一张原图生成一次，确认扩展名后再写进模板。
  3. 美图显示模式里，`field_images` / `field_cover_image` 改为 `gallery`。
  4. 模板里封面与 `field_images` 只输出一套。相关推荐改用已有卡片（`meitu-card`），`loading="lazy"`，不要 `fetchpriority="high"`。
  5. 主图 alt 使用「节点标题 + 序号 + 画面描述」，灯箱按钮已有 `aria-label`，缩略图保持 `alt=""` 即可，避免同一张图被算两次。
  6. 第一张 `loading="eager"` 且 `fetchpriority="high"`，其余 `lazy`。
- 示例（画廊只渲染预处理好的数组，而不是再打印字段）：

```twig
{% for item in gallery %}
  <img
    src="{{ item.full }}"
    alt="{{ item.alt }}"
    width="{{ item.width }}"
    height="{{ item.height }}"
    {% if loop.first %}loading="eager" fetchpriority="high"{% else %}loading="lazy"{% endif %}
    decoding="async">
{% endfor %}
```

`_xedc_photo_gallery_items()` 已经准备了 `full` / `thumb` / `alt`，补上宽高即可。
- 影响：Google 图片搜索收录的是 `<img src>`。现在收录的是居中裁掉主体的手机壁纸比例，而且三张重复的高优先级图会干扰 LCP。

### P1-1 补 JSON-LD

- 来源：首页、美图、文章、视频的 HTML 中 `application/ld+json` 数量为 0。未安装 `schema_metatag`。
- 修改：安装 `drupal/schema_metatag` 后为各 bundle 配 Metatag，或在主题 `hook_page_attachments()` 里按路由输出一段 JSON-LD。图片站优先这四类：

| 页面 | 类型 |
|---|---|
| 首页 | `WebSite` + `SearchAction`，`Organization` |
| 美图详情 | `ImageGallery`，`image` 为 `ImageObject`，`contentUrl` 用画廊主图绝对 URL |
| 文章 | `Article`，`image`、`datePublished`、`headline` |
| 视频 | `VideoObject`，`thumbnailUrl`、`uploadDate`、`contentUrl` 或 `embedUrl` |
| 有面包屑的页面 | `BreadcrumbList` |

首页示例（域名和搜索路径按实际路由改）：

```json
{
  "@context": "https://schema.org",
  "@type": "WebSite",
  "name": "DcLili",
  "url": "https://gitxx.xyz/",
  "potentialAction": {
    "@type": "SearchAction",
    "target": "https://gitxx.xyz/search?q={search_term_string}",
    "query-input": "required name=search_term_string"
  }
}
```

美图页的 `ImageObject.contentUrl` 必须和页面主图 `src` 一致，不要写 450×800 裁剪图，也不要写 sitemap 里那张未展示的原图。
- 验证：用 Google Rich Results Test 测一篇美图、一篇文章、一篇视频。本报告没有代跑该测试。
- 影响：图片与视频有机会获得更明确的类型识别。没有 JSON-LD 时，只靠标题和 alt。

### P1-2 打开 alt 并重写无意义文本

- 来源：`audit_seo` 的 `IMAGE_ALT_DISABLED`。`config/sync/field.field.media.image.field_media_image.yml` 中 `alt_field: false`（`alt_field_required` 却是 `true`）。用户头像同样关闭。
- 数据库：`media__field_media_image` 74 行，空 alt 为 0，但内容是「海边」「测试」「jfjf」「nxnx」「cos」或「标题 - 图N」。详情页能输出这些短 alt，是因为库里有值，编辑界面不能改。
- 修改：

```yaml
# field.field.media.image.field_media_image.yml settings
alt_field: true
alt_field_required: true
title_field: false
```

导入配置后，让编辑按画面写 alt（人物、服装、场景、风格），不要只写序号。已有短 alt 用视图或一次性脚本列出 `CHAR_LENGTH(field_media_image_alt) < 8` 的媒体，人工改。不要用文件名填充。
- 头像 `user_picture` 可以继续关闭 alt，前台装饰图用 `alt=""`。
- 影响：图片搜索用 alt 理解画面。序号 alt 几乎没有查询价值。

### P1-3 模特页标题、描述和头像

- 来源：`/models/20` 的 `<title>` 为「模特 \| DcLili」，`<h1>` 为「莉莉」，没有 meta description。全部模特路由共用 `_title: 模特`。
- 位置：
  - `web/modules/custom/xedc_models/xedc_models.routing.yml` 的 `xedc_models.detail`
  - `src/Controller/ModelsController.php` 返回了 `#title`（所以 H1 是人名），但文档标题仍走路由上的「模特」
  - `templates/xedc-models-detail.html.twig` 第 3 行头像 `alt=""`
  - `config/sync/metatag.metatag_defaults.taxonomy_term__models.yml` 不会作用在这条自定义路由上
- 修改：路由改为标题回调，返回术语名。

```yaml
xedc_models.detail:
  path: '/models/{taxonomy_term}'
  defaults:
    _controller: '\Drupal\xedc_models\Controller\ModelsController::detail'
    _title_callback: '\Drupal\xedc_models\Controller\ModelsController::detailTitle'
```

```php
public function detailTitle(TermInterface $taxonomy_term): string {
  return $taxonomy_term->label();
}
```

再用 Metatag 的路由默认值（`metatag_routes` 已启用）为该路由设置：

```yaml
title: '[current-page:title] 作品 | [site:name]'
description: '[current-page:title] 的图片与视频合集'
robots: 'index, follow, max-image-preview:large'
```

保存前在 Metatag 界面确认 token 能解析出人名。头像改为 `alt="{{ term_name }} 头像"`，列表图保留作品标题作为 alt。
- 影响：现在所有人物页在搜索结果里都叫「模特」，无法按人名建立集群。

### P1-4 分类别名

- 来源：`audit_seo` 对 `article_category`、`photo_category`、`video_category`、`models` 报 `PATHAUTO_PATTERN_MISSING`。模特已有自定义路径 `/models/{tid}`，这条可以不建 Pathauto。图片栏目多数已有手工别名（`/bizhi`、`/cosplay`）。
- 线上仍是系统路径的例子：`/taxonomy/term/55`（短视频，title 已是「短视频 - 视频分类」）、`/taxonomy/term/10`（文章栏目「墨迹」）。
- 修改：新增模式，例如：

```yaml
# pathauto.pattern.video_category.yml
id: video_category
label: '视频栏目 URL'
type: 'canonical_entities:taxonomy_term'
pattern: '/videos/category/[term:name]'
selection_criteria:
  -
    id: 'entity_bundle:taxonomy_term'
    bundles:
      video_category: video_category
```

文章栏目可用 `/articles/category/[term:name]`。图片栏目若继续手工维护别名，就不要再套一层自动模式，避免把 `/cosplay` 改掉。生成后检查旧 `/taxonomy/term/TID` 是否 301 到新别名（Redirect 的 `auto_redirect: true` 已开启）。
- `models` 不要再建一套 Pathauto，以免和 `/models/{tid}` 冲突。
- 媒体（图像、视频、文档）和用户不必做公开别名，审计的对应警告可以忽略。
- 影响：去掉索引里的 `/taxonomy/term/55` 这类无关键词 URL。

### P1-5 sitemap 图片地址与页面一致

- 来源：`simple_sitemap` 已生成。`custom_links_include_images: true`，photo/article/video 的 `include_images: true`。抽查 `image:loc` 含 `IMG_1204.png` 这类原图；详情页 src 是 `styles/images_450x800/...webp`。
- 位置：`config/sync/simple_sitemap.settings.yml`、`simple_sitemap.bundle_settings.default.node.*.yml`。
- 修改：主图改成大图样式之后，让 sitemap 收录同一条样式 URL，而不是原始上传文件。Simple XML Sitemap 的图片来自实体字段显示；把公开显示模式调到 `gallery` 后执行：

```bash
drush simple-sitemap:generate
```

然后确认某篇美图的 `image:loc` 与 HTML `img src` 的绝对地址一致，并且是 https。分类术语的 `include_images` 保持 false 即可，列表页不是图片落地页。
- 英文：`language.entity.en.yml` 启用了英语，节点译文为 0。sitemap 仍有 `https://gitxx.xyz/en`，首页带 `hreflang="en"`。若站点只做中文，卸载英语或在语言设置里去掉 URL 前缀，并设置 `disable_language_hreflang: true`。`/en` 的 canonical 已经指向首页，但 sitemap 仍在提交这个 URL。
- IndexNow：状态报告「Verification key not available」。在 Simple XML Sitemap Engines 里生成密钥；生产环境按模块说明写入 `settings.php`。`index_now_on_entity_save` 目前是 false，密钥就绪后再开。
- 影响：图片 sitemap 与页面不一致时，图片搜索会忽略或抓取错误文件。

### P2-1 描述、URL 关键词与重复视频

- 美图/文章 description 模板（`metatag.metatag_defaults.node__photo.yml` 等）是 `[node:field_summary] [node:title] - [node:field_categories:entity:name]`。摘要为空时，description 几乎等于标题。`/bizhi/1` 的 description 为「海边风景手机壁纸 测试 - 壁纸」。视频分类为空时，`/videos/shipinlanmuziduandeceshineirong` 的 description 为「视频栏目字段的测试内容 -」。
- 建议：摘要为空时不要拼接空段。可用 Metatag 的条件或在保存时把 `field_summary` 写成 50–120 字的画面说明。视频 `og_type` 从 `website` 改为不硬编码；有 `VideoObject` 后社交卡片仍可用 `summary_large_image`。OG 图不要用 `images_450x800`，改用横向大图（文章已用 `xa_hero`，这是对的）。
- 美图 Pathauto 保持 `/[栏目]/[nid]` 可以避免改 URL 造成外链丢失。新内容若要带关键词，应新开模式并配 301，不要直接改 `gggg` 的 pattern。模式 id `gggg` 只影响机器名，可以以后重命名配置，不必为改名批量更新别名。
- 视频 nid 8 与 nid 9 标题相同，别名分别为 `/videos/mojierbanceshishipinbiaoti` 和 `...biaoti0`。合并或撤下其中一篇，给保留的一篇写唯一标题。
- `/bizhi` 无 meta description（术语描述为空）。`/cosplay` 有「cosplay 高清美图合集，每日更新」。给每个图片栏目的术语描述写 1–2 句介绍，Metatag 父级 `taxonomy_term` 的 `description: '[term:description]'` 就会输出。`taxonomy_term__photo_category.yml` 的 `tags` 是空的，不会覆盖父级，这是预期行为。
- `/tags` 没有 description。可在标签索引路由上加一条 Metatag：说明这是标签目录，并 `noindex` 过薄的标签（只有 1 篇内容的词）。

### P2-2 视频页图片

- 位置：`templates/node/node--video--full.html.twig`。本地视频用 `<video poster>`，没有对应的 `<img>`。侧栏和相关推荐的封面 `alt=""`，`loading="lazy"`，src 指向 `/sites/default/files/gallery/...jpg` 和原始 png，没有图片样式。
- 抽查页 11 张图全部空 alt、全部 lazy。封面 eager 的分支只在 iframe/纯图时出现，本地视频走不到。
- 修改：相关推荐 `alt="{{ v.title }}"`，封面走 `video_cover` 或 `xa_hero` 的 webp，并带宽高。本地视频若希望图片搜索看到封面，在播放器旁放一张与 `poster` 相同 URL 的 `<img>`（可用 CSS 只给爬虫/无脚本，或作为播放器后备），alt 用视频标题。不要把 11 张原图都设成 eager。
- 影响：视频页目前对图片搜索几乎没有有效信号。

### P2-3 品牌与首页元数据

- 位置：`config/sync/metatag.metatag_defaults.front.yml`。
- 现状：`<title>` 和 `og:site_name` 为 DcLili；description 开头是「在 XEDC 浏览…」；`rights` 为「Copyright © 2026 XEDC」；`keywords` 为「美女,野兽」；首页 H1（`templates/includes/home-sections.html.twig` 第 1 行，`visually-hidden`）仍是「XEDC - …」；`og:image` 是主题 `screenshot.png`。
- 修改：全文统一为 DcLili（若品牌最终定为别的名字，只改这一处配置和这一处 H1）。删除 `keywords`。`og:image` 换成一张 1200×630 以上的真实预览图，绝对 URL 使用 `https://gitxx.xyz/...`。首页第一张幻灯已经是 `loading="eager"` + `fetchpriority="high"`，保持；第 89 行文章封面 `alt=""` 改为文章标题。
- 影响：搜索结果和社交预览不再出现两套站名。`keywords` 对 Google 无作用，留着只会暴露过时堆词。

### P2-4 响应式图与列表缓存

- `responsive_image` 已启用，样式「宽」「窄」没有被任何图片字段使用（`audit_images` 的 `UNUSED_RESPONSIVE_STYLE`）。全站抽查 `srcset` 为 0。
- 卡片可以继续用固定样式加宽高（`meitu-card` 已经支持 width/height）。详情大图至少提供 650 与 1300 两档 srcset。没有 srcset 不会阻止收录，但会让移动端下载过大的图。
- 首页视图「最新文章」「最新美图」「热门视频」被 `audit_views` 标为 `NO_CACHE`。列表视图使用泛化 `node_list`。改为 `node_list:photo` / `node_list:article` / `node_list:video`，并打开基于标签的缓存。
- 照片相关推荐：`node--photo--full.html.twig` 在循环里调用 `drupal_entity()`。在预处理里组装卡片 URL 和图片，模板只打印 `<img>`。
- 页面缓存配置是 `system.performance.yml` 的 `max_age: 86400`。线上首页响应为 `cache-control: max-age=3600, public`，更像 Cloudflare 的边缘 TTL。源站与 Cloudflare 对齐即可，不必为了分数把 Drupal 改成 3600。

### P3 其余项

- 标签索引 `xedc-tags-index.html.twig` 有一个 H1「全部标签」，页面标题区块再输出一个。登录页同样是两个「登录」（已 noindex）。去掉模板里的 H1，或在对应路由把 `page_title` 区块隐藏。标签术语页 `xedc-tags-term.html.twig` 的 H1 是「#名称」；`xedc_preprocess_page_title()` 已对 tags 清空页面标题，抽查索引页时不要和术语页混在一起。
- `/articles?cat=999999` 已是 404，不再是 500。响应里的 canonical 仍是 `https://gitxx.xyz/articles`。404 不应把权重交回列表。在返回 404 的分支不要附加该视图的 canonical。`metatag.metatag_defaults.404.yml` 本身没有 canonical，问题出在这条请求仍套用了文章列表路由。
- `/bizhi?page=1` 的 canonical 是带 `page=1` 的自身 URL，标题带「第 2 页」。这一项比 10 月 25 日的抽查更好，保持。
- 别名 `/search` → `/search/node` 被 URL 审计标为 error（`ALIAS_ROUTE_SHADOW`）。线上 `/search` 为 200 且 noindex。保留别名即可，不要把它加入 sitemap。
- 匿名用户：`users` 表从 uid 1 开始，没有 uid 0。状态报告给出了错误。匿名访问首页仍然 200。按 [Drupal 文档](https://www.drupal.org/node/1029506) 在备份后恢复该记录，再打开 Site Audit 的 users 报告。
- 待运行更新只有 `xedc_member_update_10009`。Colorbox 模块已启用，但 `/libraries/colorbox` 不存在。美图灯箱是主题自己的实现；若前台不用 Colorbox，卸载模块即可去掉这条状态错误。
- `hook_page_attachments` 与会员中心的 `max-age: 0` 只影响动态页面，不要用在图片详情上。图片详情应继续进入页面缓存。

## 5. 缺失但推荐的模块/配置

| 项 | 建议 | 原因 |
|---|---|---|
| `drupal/schema_metatag` | 安装并配置 WebSite、ImageGallery、Article、VideoObject、BreadcrumbList | 现在没有任何 JSON-LD |
| `drupal/robotstxt` | 可选。若继续用物理文件 `web/robots.txt`，就不要同时启用，避免两套规则 | Cloudflare 已经在源文件外再包一层 |
| `drupal/seo_audit` | 只有在需要「按深度爬自己的站、检查每个 URL 的 title/H1」时再装 | 当前 audit 模块不爬页面 |
| IndexNow 密钥 | 在 Simple XML Sitemap Engines 生成，并写入 `settings.php` | 状态报告已警告；有利于 Bing 尽快看到更新 |
| 英语 | 若无英文内容，删除 `en` 语言并关闭 hreflang | `/en` 与首页重复 |
| www 301 | Nginx / Cloudflare，不依赖 `.htaccess` | Apache 规则在本环境不执行 |
| 媒体显示模式 `gallery` | 配置，不必新模块 | 把详情图从 450×800 裁剪里拆出来 |
| Redis | 可选，缓存 bin 现在在数据库 | 内容量上来之后再上，不是当前收录的阻塞项 |

不建议为了审计分数安装 ImageAPI Optimize，除非服务器上已经有 jpegoptim / pngquant / avifenc。现有图片样式已经在做 WebP/AVIF 转换，优先把「用哪一个衍生物」理顺。

## 6. 后续优化建议

性能：

- 详情第一张图保留宽高、eager、高优先级；列表和相关推荐全部 lazy，并带宽高，避免 CLS。
- 首页幻灯第一张已是 eager。文章列表封面补 alt 和宽高。
- 页面缓存已经对匿名用户公开。把首页三个视图改成按 bundle 的缓存标签，避免任意节点保存就清空整站列表。
- 会员中心的逐条 `load()` 与 SEO 抓取无关，可另开任务改成 `loadMultiple()`。

结构化数据与图片搜索：

- 每篇美图至少有：唯一 H1（已有）、一段可见描述（`field_summary` 有值才显示）、主图 `ImageObject`、分类和人物的文字链接（模板里已有）。
- alt 描述画面，标题描述作品名，两者不要复制同一句短词。
- sitemap、OG、页面 `img src` 使用同一张未裁剪大图。
- 文件名仍有 `IMG_1204.png`、`piyiercishangchuandian-001.jpg`。新上传按作品名拼音或英文短语命名；旧文件改名需要重定向，收益低于改 alt 和主图样式。

内链：

- 美图已链到分类、模特、标签、上一篇/下一篇、相关推荐。保持这些链接为 `<a href>`。
- 人物页、标签页、视频栏目补上唯一 title 和一段介绍后，才适合作为集群枢纽。薄标签（1 条内容）用 noindex,follow。
- 撤下测试节点后，在 Search Console 提交更新过的 sitemap。

GEO / AEO：

- 首页和分类页用完整句子写清站点提供什么（图片类型、更新方式），放在可见段落里，而不只放在 meta description。隐藏 H1 可以保留一个与 `<title>` 一致的 DcLili 句子。
- `Content-Signal: ai-train=no` 会拒绝训练用途，`search=yes` 仍允许建立搜索索引。这不影响 Google 网页排名，但会影响部分 AI 答案引擎是否引用本站。若希望作品被 AI 搜索引用，把 `ai-input` 设为允许；若要禁止训练，保持 `ai-train=no`。这项在 Cloudflare，不在 Drupal 配置里。
- 文章正文保持可抓取的 HTML。视频不要把唯一说明只放在播放器里。

## 7. 需要你确认的事项

1. 正式主机是否就是 `https://gitxx.xyz`（无 www）。本报告的 301 建议按这个方向写。
2. 是否需要百度收录。需要的话，必须在 Cloudflare 放行 `Baiduspider`。
3. 训练爬虫保持禁止，还是允许 AI 搜索引用（`ai-input`）。
4. 英语 `/en` 是否还要保留。
5. nid 13–22 一带的测试美图，以及重复的视频 nid 8/9，哪些可以撤下。
6. 品牌最终用 DcLili 还是 XEDC。配置与首页 H1 需要同一名称。

## 8. 本次已核对、暂不改动的项

- Simple XML Sitemap 已生成，`/sitemap.xml` 返回 XML，包含图片命名空间。
- 文章、视频、基础页已有 Pathauto；抽查文章和视频详情有 description、OG、Twitter Card。
- 搜索页与登录页为 `noindex,follow`。`/member` 会跳到登录页。
- 非法 `cat` 参数返回 404，不再返回 500。
- 美图、文章、视频详情抽查各有一个 H1。首页有一个视觉隐藏 H1。
- Redirect 默认 301，`auto_redirect` 与路由规范化已开。抽查的别名冲突为 0。
- 图片样式已配置 WebP 转换；缩略图线上可见 AVIF。缺的是详情页没有用这些大图。
- CSS/JS 聚合已开启。

## 9. 建议落地顺序

1. Nginx/Cloudflare：www → 非 www 301；按需放行 Baiduspider；源站 robots 加上 Sitemap。
2. 撤下测试节点并重新生成 sitemap，确认 `/node/` 从 sitemap 消失。
3. 美图详情改为未裁剪大图，只保留一张高优先级主图，打开并重写 alt。
4. 模特路由标题、视频/文章栏目别名、JSON-LD。
5. 统一品牌文案、首页 OG 图、视图缓存和 IndexNow 密钥。
