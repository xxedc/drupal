# SEO 修复说明

站点：https://gitxx.xyz  
范围：代码、配置、主题。Nginx / Cloudflare 只列操作，没有改服务器。

运行中的配置目录由 `settings.php` 的 `config_sync_directory` 指定，和仓库 `config/sync` 不是同一个目录。本次已把下面列出的 YAML 写入当前启用配置，并复制到运行中的同步目录，避免下次从旧目录导入时把这些项盖回去。

## 已修改的文件与配置

### 美图详情（P0-4、P1-5、P2-4）

- `config/sync/image.style.photo_gallery_1300.yml`、`image.style.photo_gallery_650.yml`：等比缩小，不裁剪，转 webp。
- `config/sync/core.entity_view_mode.media.gallery.yml`、`core.entity_view_display.media.image.gallery.yml`
- `config/sync/core.entity_view_display.node.photo.default.yml`：`field_images` / `field_cover_image` 使用 `gallery`
- `web/themes/custom/xedc/templates/content/node--photo--full.html.twig`：画廊只输出一套图；第一张 `loading="eager"` + `fetchpriority="high"`，其余 `lazy`；带 650/1300 `srcset`
- `web/themes/custom/xedc/xedc.theme`：`_xedc_photo_gallery_items()` 生成与页面一致的 URL；alt 为「标题 - 图N - 画面描述」；相关推荐在预处理里组装卡片，模板不再循环调用 `drupal_entity()`
- `web/modules/custom/xedc_home/xedc_home.module`：`hook_simple_sitemap_links_alter()` 把美图 `image:loc` 改成 `photo_gallery_1300`，并使用同一套 alt

抽查 `/bizhi/1`：页面 `img src` 与 sitemap `image:loc` 都是  
`https://gitxx.xyz/sites/default/files/styles/photo_gallery_1300/public/2026-10/IMG_3009.jpeg.webp?itok=sx0sKoT2`

### 无别名测试美图（P0-3）

已发布但没有 `path_alias` 的 photo：nid 13–22，标题为乱码/测试句，且都有分类。已在审核流中新增状态「已撤下」（`archived`，未发布且为默认修订），并把这 10 篇设为已撤下。

- `config/sync/workflows.workflow.xedc_editorial.yml`：状态 `archived`，流转「撤下」

重新生成 sitemap 后，不再包含 `/node/13` 至 `/node/22`。这些是垃圾页，没有做 301 到正式详情。匿名访问 `/node/13` 当前为 **403**（内容审核下线后的访问拒绝），不是 404。

已有正式别名（如 `/bizhi`、`/cosplay`）没有改写。图片栏目没有加 Pathauto 模式。

### JSON-LD（P1-1）

已安装并启用 `schema_metatag` 及 `schema_web_site`、`schema_organization`、`schema_article`、`schema_video_object`、`schema_web_page`、`schema_image_object`。

- 首页：`WebSite` + `SearchAction`（`/search?q={search_term_string}`）+ `Organization`（DcLili）
- 文章：`Article`（headline、description、`xa_hero` 图片、日期、作者）
- 视频：`VideoObject`（名称、描述、`uploadDate`、`thumbnailUrl` 与封面一致，本地文件带 `contentUrl`）
- 美图：主题输出 `ImageGallery` + `ImageObject`，`contentUrl` 与 `<img src>` 一致，并带 `BreadcrumbList`
- 文章、视频、栏目、模特、标签、`/sitemap`：另有 `BreadcrumbList`

配置：

- `config/sync/metatag.metatag_defaults.front.yml`
- `config/sync/metatag.metatag_defaults.node__article.yml`
- `config/sync/metatag.metatag_defaults.node__video.yml`
- `web/modules/custom/xedc_home/xedc_home.module`（文章/视频结构化数据、模特标题）
- `web/themes/custom/xedc/xedc.theme`（美图画廊与各页面包屑）

`metatag_routes` 对带参数的路由会把参数哈希进配置 ID，`metatag.metatag_defaults.xedc_models.detail.yml` 因此匹配不到 `/models/{tid}`。模特标题和描述改在 `xedc_home_metatags_alter()` 里按术语名输出。抽查 `/models/20`：`<title>` 为「莉莉 作品 | DcLili」，description 为「莉莉 的图片与视频作品合集，在 DcLili 浏览。」

### alt（P1-2）

`config/sync/field.field.media.image.field_media_image.yml`：`alt_field: true`，`alt_field_required: true`。用户头像仍关闭 alt。

详情主图 alt 由主题拼接，不把文件名写入 alt。库里过短 alt 需要在编辑界面改，不要用文件名填充。列出字符数小于 8 的媒体：

```sql
SELECT entity_id, field_media_image_alt, CHAR_LENGTH(field_media_image_alt) AS len
FROM media__field_media_image
WHERE CHAR_LENGTH(field_media_image_alt) < 8
ORDER BY len, entity_id;
```

当前约 15 条，例如「海边」「测试」「jfjf」「cos」。

### 分类别名（P1-4）

- `config/sync/pathauto.pattern.video_category.yml`：`/video/category/[term:name]`（列表页是 `/video`，不是 `/videos`）
- `config/sync/pathauto.pattern.article_category.yml`：`/articles/category/[term:name]`
- 未给 `photo_category`、`models` 建模式，避免改掉 `/bizhi`、`/cosplay` 或和 `/models/{tid}` 冲突
- 已为原先没有别名的视频/文章栏目生成别名。Redirect 的路由规范化已把旧路径 301 到新别名  
  - `/taxonomy/term/55` → `/video/category/duanshipin`  
  - `/taxonomy/term/10` → `/articles/category/moji`
- 图片栏目 `cospaly`（tid 53）仍无别名，也没有自动模式
- 视频栏目「美女视频」（tid 58）补生成 `/video/category/meinushipin`

### 品牌、描述、视频图（P2）

- 首页 title、description、`og:site_name`、版权、隐藏 H1 为 DcLili；去掉 keywords
- 首页 `og:image` 在 `xedc_page_attachments_alter()` 里换成当前幻灯或最新美图的绝对地址，不再使用主题 `screenshot.png`
- 空摘要不再拼出「标题 -」这种空分类尾巴
- 视频 `og_type` 改为 `video.other`
- 本地视频播放器旁增加与 `poster` 相同 URL 的 `<img class="vd-poster">`，alt 为视频标题；相关推荐 alt 为条目标题，`loading="lazy"`
- 为空的图片栏目、短视频，以及新闻/日报/币圈等文章栏目补了 1 句 description。`/bizhi` 的 meta description 已能读到术语描述
- 标签索引 `/tags`：`metatag.metatag_defaults.xedc_tags.index.yml`；页面只保留一个 H1「全部标签」

### 缓存

- 首页三个区块、美图列表、视频列表、文章列表使用视图缓存插件 `xedc_bundle_tag`（`web/modules/custom/xedc_home/src/Plugin/views/cache/BundleTag.php`）
- 标签分别为 `node_list:article`、`node_list:photo`、`node_list:video`，去掉这些视图上的泛化 `node_list`
- `views.view.article_list.yml` 改为同一插件
- 美图详情匿名页面缓存：`Cache-Control: max-age=86400, public`，第二次请求 `X-Drupal-Cache: HIT`
- 首页匿名缓存 HIT，`max-age=3600`（主题里与边缘缓存对齐的上限）
- CSS/JS 聚合已开启（`system.performance`：`css.preprocess`、`js.preprocess` 均为 true，页面 `max_age` 86400）
- 会员中心收藏/评论等处的 `max-age: 0` 保留。收藏按钮只在已登录时输出，不把美图详情变成匿名不可缓存
- `MemberController` 中评论和节点改为 `loadMultiple()`

### HTML 站点地图

- 路径 `/sitemap`，路由在 `web/modules/custom/xedc_home/xedc_home.routing.yml`（主题里的 `xedc.routing.yml` 不会被 Drupal 加载，已不使用）
- `web/modules/custom/xedc_home/src/Controller/SitemapController.php`
- `web/themes/custom/xedc/templates/page/html-sitemap.html.twig`
- `web/themes/custom/xedc/css/sitemap.css`，库 `xedc/html-sitemap`
- 页脚 `home-footer.html.twig`：「关于我们 · 隐私政策 · 用户协议 · 站点地图」
- 抽查 HTTP 200，`<title>` 为「站点地图 | DcLili」

`web/robots.txt` 增加：

```text
Disallow: /member
Disallow: /user/
Sitemap: https://gitxx.xyz/sitemap.xml
```

没有 `Disallow: /node/`。

## 已运行检查

```bash
php -l web/themes/custom/xedc/xedc.theme
php -l web/modules/custom/xedc_home/xedc_home.module
php -l web/modules/custom/xedc_home/src/Controller/SitemapController.php
drush cr
drush --uri=https://gitxx.xyz pathauto:aliases-generate create canonical_entities:taxonomy_term
drush --uri=https://gitxx.xyz simple-sitemap:generate
```

本机以 `Host: gitxx.xyz` 请求 `https://127.0.0.1` 抽查了首页、`/bizhi/1`、一篇文章、一篇视频、`/models/20`、`/tags`、`/sitemap`、`/taxonomy/term/55`、`/taxonomy/term/10`、`/node/13`、`/sitemap.xml`、`/robots.txt`。

没有浏览器界面操作。视频封面图在播放器下层的叠放，只确认了 HTML 里 `<img>` 与 `poster` 的 URL、alt、宽高一致，没有在桌面/手机视口里点播放。

没有跑 Google 富结果测试。

## 服务器 / CDN（只操作说明，未改）

### Nginx：www 整站 301

在 `www.gitxx.xyz` 的 `server` 中整站跳到无 www，不要只靠 canonical。`.htaccess` 在本环境不生效。

```nginx
server {
    listen 443 ssl;
    server_name www.gitxx.xyz;
    return 301 https://gitxx.xyz$request_uri;
}
```

抽查：

```bash
curl -sI https://www.gitxx.xyz/bizhi/1
```

期望 `301`，且 `Location: https://gitxx.xyz/bizhi/1`。若 Cloudflare 另有 Redirect Rule，方向保持一致：www → 非 www。

### robots.txt

源站 `web/robots.txt` 末尾已有 `Sitemap: https://gitxx.xyz/sitemap.xml`。线上若仍由 Cloudflare 托管 robots，需要在 Cloudflare 的 Managed content 之后保留这行，否则源站追加不会出现在公网响应里。

### Cloudflare：百度

若需要百度收录，在 AI Crawl Control / robots 托管内容里放行 `Baiduspider`。当前托管规则对 `Baiduspider` 是整站 `Disallow: /`。`Googlebot` 未被单独禁止。`GoogleOther` 不负责网页排名。训练爬虫是否继续禁止，需要单独决定；`ai-train=no` 只在确认不想被用于训练时保留。

## 未完成，需要人工确认

1. **英语 `/en`**：sitemap 里仍有 `hreflang="en"`。仓库里的 `language.negotiation.yml` 还出现了 `ru`、`ja` 前缀，那不是这次 SEO 改动，也没有导入。若只做中文，再决定是否删除额外语言并设置 `disable_language_hreflang: true`。
2. **测试视频**：nid 8 与 nid 9 标题同为「墨迹二班测试视频标题」。另外 nid 6、10、54、55、116、129 也像测试标题。这次没有下线，避免清空视频栏目。
3. **文章栏目里的薄分类**：`adc`、`彼岸`、`必然`、`空气`、`表盘`、`记者` 已按模式生成了 `/articles/category/...`。若是测试词，应撤下或 `noindex`，而不是继续当栏目收录。
4. **图片栏目 tid 53 `cospaly`**：无别名、无描述。疑似 `cosplay` 的笔误，没有自动改 URL。
5. **过短 alt**：约 15 条，见上面的 SQL。编辑界面现在可以改。
6. **已撤下美图的 HTTP 状态**：`/node/13` 等为 403。若要让索引更快丢弃，再改成 404。不要 301 到其他美图。
7. **IndexNow**：未生成密钥，也没有写入 `settings.php` 或配置。需要时在 Simple XML Sitemap Engines 里生成，只放 `settings.php`，不要提交到 git。`index_now_on_entity_save` 仍关闭。
8. **Redis**：页面和渲染缓存仍在数据库。内容量上来后再迁，不是当前收录的阻塞项。不建议为了审计分数安装 ImageAPI Optimize。
9. **P3 未做**：非法 `cat` 的 404 仍可能带列表页 canonical；登录页双 H1；Colorbox 库缺失；匿名用户 uid 0；Audit 密钥是否还在 `config/sync`。
10. **响应式样式「宽」「窄」**仍未被字段使用。美图详情已有 650/1300 `srcset`。列表卡片继续用固定样式加宽高。
