# 性能与 SEO 优化记录

- 日期：2026-10-30
- 项目：`/var/www/drupal`（Drupal 11.4.11，主题 `web/themes/custom/xedc`）
- 品牌：DcLili
- 线上域名：`https://gitxx.xyz`
- 未改语言切换器的位置和样式。未执行 `drush cim` / `cex`，未提交。

## 1. 已优化项与修改文件

### 缓存与查询

- 匿名页面缓存保持开启：`system.performance` 的 `cache.page.max_age` 为 86400，CSS/JS 聚合与压缩已开启。首页由 `HomeCacheSubscriber` 把匿名响应收成 `public, max-age=3600`，避免热门视频排序被页面缓存一直冻住。
- 首页三个区块、美图/文章/视频列表、视频分类视图继续使用 `xedc_bundle_tag`，按 `node_list:photo` / `article` / `video` 失效，而不是任意节点保存就清空全部列表。
- 公开页上的泛化 `node_list`、`taxonomy_term_list` 改成 bundle / 词表标签：
  - 美图筛选条、首页分类区块
  - 标签索引与标签页
  - 模特列表
  - 搜索页
  - 文章详情正文不再挂 `node_list`
- 美图栏目筛选不再 `loadMultiple()` 该栏目全部节点。改为一条按人物分组的 SQL，只加载出现过的术语。
- 首页图片分类计数从「每个术语一次 count 查询」改成一次 `GROUP BY`。
- 美图画廊按文件 ID 批量 `loadMultiple()`，不再在循环里 `File::load()`。
- 视频卡片、美图列表、术语介绍的缓存标签改用 `Cache::mergeTags()`。
- 视频正文去掉 `|render` 后再输出，避免同一段正文渲染两次。

### 视图显示模式

模板已经在预处理里取字段，默认显示模式仍在跑图片、封面和正文字段格式化器。这次把前台不打印的字段从显示模式里拿掉，检索仍走单独的 `search_index` 显示模式，避免正文从搜索索引里消失。

| 显示模式 | 处理 |
|---|---|
| `node.photo.default` | 只保留评论和审核控件。画廊由预处理输出 `photo_gallery_1300` / `650` |
| `node.article.default` | 字段全部隐藏。正文由预处理 `check_markup()` 输出，并给正文图片加 `loading="lazy"` |
| `node.article.teaser` | 新建，字段全部隐藏。列表卡片只用预处理数据 |
| `node.article.search_index` | 新建，保留正文、摘要、栏目、标签、作者、来源 |
| `node.video.default` | 只保留正文 |
| `node.video.teaser` | 字段全部隐藏 |
| `node.video.search_index` | 新建，保留正文、栏目、标签 |
| `node.photo.search_index` | 新建，保留摘要、栏目、人物、标签，不渲染原图 |

### SEO

- HTML 站点地图 `/sitemap` 的「模特」一节只保留「全部模特」→ `/models`，不再列出具体人名。栏目术语仍按美图、文章、视频分列。
- 启用已写在配置里、但运行配置中缺失的 Pathauto 模式，不批量改已有别名：
  - 文章 `/articles/[node:title]`
  - 视频 `/videos/[node:title]`
  - 文章栏目 `/articles/category/[term:name]`
  - 视频栏目 `/video/category/[term:name]`
- 美图节点继续用现有 `/栏目路径/[nid]`。人物继续走 `/models/{tid}`，不为人物词表再建 Pathauto，避免和自定义路由冲突。图片栏目继续手工别名（`/bizhi`、`/cosplay` 等）。
- `sitemap.xml` 抽查：119 个 URL 都有 `lastmod`，没有 `/node/NID`。美图 `image:loc` 已由 `xedc_home_simple_sitemap_links_alter()` 改成与详情页相同的 `photo_gallery_1300`。
- 首页、美图、文章、视频详情已有 JSON-LD。首页 H1 与 title 为 DcLili。`robots.txt` 已声明 `Sitemap: https://gitxx.xyz/sitemap.xml`，并禁止 `/member`、`/user/`。
- 卸载 `automated_cron`。它会在页面请求结束时跑 cron，把 TTFB 拉长。Config checks 因此从 95 变为 100。系统 cron 改为每小时第 17 分执行 `drush cron`，站点地图和搜索索引仍会更新。

### 修改的文件

- `web/modules/custom/xedc_home/src/Controller/SitemapController.php`
- `web/modules/custom/xedc_home/src/HomeCards.php`
- `web/modules/custom/xedc_home/src/Plugin/Block/PhotoCategoriesBlock.php`
- `web/modules/custom/xedc_home/xedc_home.services.yml`
- `web/modules/custom/xedc_models/src/Controller/ModelsController.php`
- `web/modules/custom/xedc_tags/src/Controller/TagsController.php`
- `web/themes/custom/xedc/xedc.theme`
- `web/themes/custom/xedc/templates/node/node--video--full.html.twig`
- `config/sync/core.entity_view_display.node.photo.default.yml`
- `config/sync/core.entity_view_display.node.article.default.yml`
- `config/sync/core.entity_view_display.node.article.teaser.yml`（新建）
- `config/sync/core.entity_view_display.node.article.search_index.yml`（新建）
- `config/sync/core.entity_view_display.node.video.default.yml`
- `config/sync/core.entity_view_display.node.video.teaser.yml`
- `config/sync/core.entity_view_display.node.video.search_index.yml`（新建）
- `config/sync/core.entity_view_display.node.photo.search_index.yml`（新建）
- `config/sync/core.extension.yml`（去掉 `automated_cron`）
- 根用户 crontab：每小时 `drush cron`

上述显示模式和 Pathauto 已写入当前生效配置。站点实际使用的 sync 目录也放了同名 YAML，避免以后从该目录导入时把显示模式退回旧版。

## 2. 删除或清理的无用内容

- 删除未被调用的 `xedc_xa_detail_v1_unused()`。
- 删除未被调用的 `XedcPhotoGalleryLazy`。画廊的 eager/lazy 已在 `node--photo--full.html.twig` 里按第一张图处理。
- 未删除主题模板。现有 Twig 覆盖仍被页面、视图和表单使用。
- 未下线测试节点。已发布内容里没有缺别名的节点；标题大量是测试文案，整批撤下会把栏目掏空，需要编辑确认后再做。
- 未卸载 Field UI、Views UI、Colorbox、Olivero、Gin。这些是后台或核心主题，不是前台死代码。
- 未安装 Redis、Memcache、PHPStan、`schema_metatag`。PHPStan 分析器当前报「未安装」，按约束不新增依赖。

## 3. 缓存与 SEO 改进点

- 匿名用户：首页第二次请求 `X-Drupal-Cache: HIT`，`Cache-Control: max-age=3600, public`。美图详情与文章列表为 `max-age=86400, public`，预热后为 HIT。
- 动态页面缓存仍是 `UNCACHEABLE (poor cacheability)`。匿名整页缓存已经生效。会员中心和登录消息上的 `max-age: 0` 保留，这两处是按用户变化的，不能进公共缓存。
- 美图详情主图为未裁剪的 `photo_gallery_1300`，并带 650/1300 的 `srcset`。第一张 `loading="eager"` 且 `fetchpriority="high"`，其余与相关推荐为 `lazy`。抽查 `/bizhi/1` 只有 1 个 `fetchpriority="high"`。
- `/sitemap` 模特节只有一条「全部模特」。
- 文章详情正文、视频播放器和 JSON-LD 在隐藏多余字段后仍然输出。
- Config checks：22/22，100 分。

## 4. 验证

在本机用 `--resolve gitxx.xyz:443:127.0.0.1` 绕过 Cloudflare，对匿名请求检查：

| 页面 | 结果 |
|---|---|
| `/` | 200。第二次 `X-Drupal-Cache: HIT`，`max-age=3600`。H1 为 DcLili。1 段 JSON-LD。1 张 eager，其余 lazy |
| `/bizhi/1` | 200。第二次 HIT，`max-age=86400`。主图 srcset、1 个 high、评论区仍在 |
| `/articles` | 200。预热后 HIT。标题「文章列表 \| DcLili」 |
| `/articles/xiaomojiwenzhangtupianjianjietu` | 200。正文和标签仍在，2 段 JSON-LD |
| `/videos/shipinlanmuziduandeceshineirong` | 200。播放器、正文、2 段 JSON-LD |
| `/sitemap` | 200。模特节只有「全部模特」→ `/models` |
| `/bizhi` | 200 |

已运行：相关 PHP 文件 `php -l`，`drush cr`，`drush audit:run config_checks`（100），`drush audit:run performance`。未跑主题 `npm run build`（未改 SCSS/JS 源文件）。

## 5. 仍需人工确认

1. 已发布标题大多是测试文案（美图、文章、视频都有）。没有缺别名的已发布节点。撤下哪些、重复视频 nid 8/9/10 留哪一条，需要编辑决定。不要为了清 sitemap 直接批量取消发布。
2. 图片栏目术语 53「cospaly」没有别名，HTML 站点地图仍是 `/taxonomy/term/53`。确认路径后再补别名，避免和 `/cosplay` 冲突。
3. `www.gitxx.xyz` 是否 301 到 `https://gitxx.xyz` 在 Nginx / Cloudflare，这次没有改服务器配置。
4. 缓存 bin 仍在数据库。访问量上来后再装 Redis。不要为了审计分数先装。
5. PHPStan 未安装，Modules 审计里的「建议装 Redis」和「后台 UI 模块」未处理。
6. 首页分类术语查询没有 `range()`，词表很小，这是有意一次取全。性能审计仍会警告 `HomeCards.php`。
7. 会员中心、登录错误消息的 `max-age: 0` 保留。快速上传和自动翻译在循环里保存，是写入流程，不是前台页面。
8. 英文 / 日文 / 俄文 hreflang 仍在 sitemap 里。语言切换器由另一任务处理，这里没有改。
9. 搜索索引要等下一次 `drush cron`（或手动执行）后，才会按新的 `search_index` 显示模式重写正文。现有索引在那之前仍然可用。
