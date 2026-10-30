# DcLili Site Audit 与性能优化

品牌为 DcLili。正式 URL、Pathauto 模式和模特路径 `/models/{id}` 没有改。

## 已创建和配置的字段与检查项

`/admin/structure/site-audit-report/fields` 现有 13 个字段。Field UI 列表能读出这 13 行，管理字段页面不是空的。来源是模块 `xedc_site_audit` 的 `config/install`，`hook_update_9001` 在字段缺失时补建。

| 字段 | 作用 |
| --- | --- |
| `field_content_bundles` | 检查范围：photo、article、video、page、models、photo_category、article_category、video_category |
| `field_image_alt` / `field_image_alt_detail` | 媒体图片 alt 是否开启、必填，以及空 alt、过短 alt |
| `field_meta_tags` / `field_meta_detail` | 首页、美图、文章、视频、基础页、模特详情的标题和描述 |
| `field_url_alias` / `field_url_alias_detail` | Pathauto：美图、文章、视频、基础页、栏目、标签 |
| `field_sitemap` / `field_sitemap_detail` | Simple XML Sitemap、https base URL、robots.txt |
| `field_cache_status` / `field_cache_detail` | 匿名页面缓存、CSS/JS 聚合、首页视图缓存 |
| `field_translation` / `field_translation_detail` | 已发布节点和模特、图片分类、文章分类、视频分类的 en / ru / ja 覆盖率 |

对应 Site Audit 清单 `xedc_seo`：Image alt text、Meta tags、URL alias、Sitemap、Cache and performance、Translation status。保存报告时 `hook_site_audit_report_presave()` 把结果写入这些字段。同一次请求里各检查只算一遍。

配合关系：

- Metatag：首页、`node__photo`、`node__article`、`node__video`、`node__page`、`xedc_models.detail` 都有标题和描述，品牌为 DcLili。
- Pathauto：美图 `gggg`、文章、视频、基础页、文章栏目、视频栏目、标签。模特不建 Pathauto，避免和 `/models/{id}` 冲突。图片栏目使用已有手工别名，没有另建会改写正式 URL 的模式。
- Simple XML Sitemap：photo、article、video、page 和模特术语进入 sitemap。指向其他模特的别名术语被排除，模特 URL 改写成 `/models/{id}`。`web/robots.txt` 增加了 `Sitemap: https://gitxx.xyz/sitemap.xml`。`https://gitxx.xyz/sitemap.xml` 返回 200。

## 已关闭或降低的不必要检查

评分权重（`audit.settings` 的 multipliers）为 0，不计入总分：

- PHPUnit、代码复杂度、重复代码、PHPCS、PHPStan

Site Audit 的 codebase 报告已关闭。用户和媒体的 Pathauto 检查忽略。图片审计不再要求 Responsive Image 格式化器：前台用固定图片样式，美图详情用 `photo_gallery_650` 和 `photo_gallery_1300` 做 srcset。

仍会报警、但没有改配置消掉的项：

- 视图 `watchdog`、`redirect_404` 不缓存。它们是后台实时日志和 404 列表。
- 图片 alt：1 条空 alt，14 条短于 8 个字。字段已必填。
- 登录、注册卡片里的状态消息，会员中心和快速上传页使用 `max-age: 0`。这些页面带当前用户或一次性消息，不能进匿名页面缓存。
- 缓存箱目前走数据库。换成 Redis 要改服务器，本次没有动。
- 界面翻译（英文约 2.7%、日语约 56%）不是内容译文。内容译文覆盖率是 100%。

## 已完成的性能优化

匿名页面缓存、动态页面缓存、CSS/JS 聚合已开启。页面缓存最大期限 86400 秒，首页单独 3600 秒。首页三个区块和美图、文章、视频、术语视图使用 `xedc_bundle_tag`，按内容类型失效。

- 整页不带 `user` 缓存上下文。会员头像、会员中心链接和详情页收藏按钮是占位符，按当前用户单独渲染。匿名响应可以进入页面缓存。
- 美图、文章、视频、视频分类列表在渲染行之前一次性加载封面媒体、文件和术语。
- 导航、美图列表分类和文章列表分类不再逐条 `Term::load()`。文章列表补上文章分类和标签的缓存标签。
- 美图详情图库在同一次请求里只组装一次，并带上媒体、文件缓存标签。主题里没有 `drupal_entity()` 循环。
- 搜索页的缓存上下文和缓存标签改用 `Cache::mergeContexts()` / `Cache::mergeTags()`。
- 首页图片分类查询限制 200 条。当前实际返回 10 个有美图的分类。
- 删除了 `/node/131`、`/node/132` 各一条重复的中文别名。对外路径仍是 `/cosplay/cos/131` 和 `/cosplay/cos/132`。

图片：详情页首图 `loading="eager"` 且带 srcset，其余 `loading="lazy"`。列表和首页除前两张外为 lazy。卡片使用单一裁切样式 `meitu_card_cover`（480×800 WebP），没有再叠一个裁切不同的 srcset。

## 修改的文件

- `web/modules/custom/xedc_site_audit/src/AuditChecker.php`
- `web/modules/custom/xedc_site_audit/src/Plugin/SiteAuditCheck/TranslationStatus.php`
- `web/modules/custom/xedc_site_audit/xedc_site_audit.module`
- `web/modules/custom/xedc_site_audit/config/install/field.field.site_audit_report.site_audit_report.field_content_bundles.yml`
- `web/modules/custom/xedc_site_audit/config/install/field.field.site_audit_report.site_audit_report.field_translation.yml`
- `config/sync/field.field.site_audit_report.site_audit_report.field_content_bundles.yml`
- `config/sync/field.field.site_audit_report.site_audit_report.field_translation.yml`
- `web/modules/custom/xedc_home/src/HomeCards.php`
- `web/themes/custom/xedc/xedc.theme`
- `web/robots.txt`

会员占位符、视图预热和首页缓存插件是已有实现，这次没有再改那些文件。

## 验证方法和结果

- `php -l`：`AuditChecker.php`、`xedc.theme`、`xedc_site_audit.module`、`HomeCards.php` 无语法错误。
- `drush cr`：成功。
- 管理字段列表：13 行。
- `xedc_site_audit` 检查：meta、url alias、sitemap、cache、translation 为通过。image alt 为警告。
- `drush site_audit:audit xedc_seo --detail`：DcLili SEO 92%。唯一警告是图片 alt。
- `drush site_audit:audit cache --detail`：缓存 100%。
- `drush site_audit:audit views --detail`：75%。未缓存的只有 `watchdog` 和 `redirect_404`。
- `drush audit:run seo,images,cache,performance,url,i18n`：SEO 91（A），图片 93（A），URL 93（A），性能 84（B），界面翻译 84（B）。缓存分析 47 分，主要是数据库缓存箱和上面保留的 `max-age: 0`。
- 清空缓存后匿名请求首页、`/meitu`、一篇美图、搜索页：第一次 `X-Drupal-Cache: MISS`，第二次 `HIT`。首页 `Cache-Control: max-age=3600, public`，其余 `max-age=86400, public`。动态缓存头在页面缓存命中时仍是第一次写入的 `MISS`，不是 `UNCACHEABLE`。
- 首页有聚合后的 CSS/JS（`/sites/default/files/css/`、`/js/`）。首页 1 张 eager、26 张 lazy。美图详情有 srcset，1 张 eager、17 张 lazy。
- `https://gitxx.xyz/robots.txt` 含 Sitemap 声明。`https://gitxx.xyz/sitemap.xml` 为 200，模特地址是 `/models/{id}`。
- 这次请求之后，watchdog 没有新的 Error。已有错误是更早的语言包导入和一次 Drush 试探。

未用浏览器点选登录后的头像和收藏按钮。

## 仍需人工确认的设置

- 补写 1 条空 alt 和 14 条过短 alt。
- 图片栏目「cospaly」（术语 53）没有别名，相关美图的正式路径是 `/taxonomy/term/53/{nid}`。不要批量重写这些别名。
- 不要给模特词汇建 Pathauto，也不要给 `watchdog`、`redirect_404` 打开视图缓存。
- 首页缓存 3600 秒是为了让按阅读量排序的区块定期更新。内容保存仍会按缓存标签立刻失效。
- 数据库缓存箱要不要换成 Redis，以及要不要安装 BigPipe 无会话模块，需要单独决定。本次没有安装模块，也没有改 Nginx、PHP 或数据库配置。
- `config/sync/audit.settings.yml` 里有 Druscan 的项目和环境密钥。不要把这个文件提交到公开仓库。
- 登录后确认头像、会员中心链接和详情页收藏按钮仍正常。
