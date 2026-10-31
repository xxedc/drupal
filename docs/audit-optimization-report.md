# 审计优化报告

对照 `audit-report-20261030-181802.json` 的同一次审计结果（本地缓存 `/tmp/audit-full.json`，2026-10-31 02:41 +08）。仓库里没有这份 JSON，也没有已写好的 `optimization-report.md`。上一轮已把点名的直接数据库查询改完，并包含在备份提交 `121412b` 里。本轮在那之上继续做，没有重写那些查询。

页面样式、布局、登录弹窗、表单文案和前台交互保持原样。首页、美图列表、登录页、找回密码页已用 HTTPS 请求核对：首页仍输出轮播样式，美图列表不再带首页样式和登录表单样式，登录页仍有 `form.xedc-auth`。

## 实际修改的文件

本轮工作区改动：

- `web/themes/custom/xedc/xedc.libraries.yml`
- `web/themes/custom/xedc/xedc.theme`
- `web/themes/custom/xedc/includes/auth.inc`
- `web/themes/custom/xedc/css/auth.css`
- `web/themes/custom/xedc/css/login-dialog.css`（新建，规则从 `auth.css` 原样拆出）
- `web/modules/custom/xedc_home/src/HomeCards.php`
- `web/modules/custom/xedc_home/xedc_home.services.yml`
- `web/modules/custom/xedc_member/src/PathProcessor/MemberAliasPathProcessor.php`
- `config/sync/smtp.settings.yml`（只改 `smtp_timeout`：30 → 15）
- `config/sync/user.role.content_editor.yml`（去掉已删除的空媒体包权限）
- 删除未使用且 0 条内容的媒体包配置：`audio`、`document`、`remote_video` 及其字段、显示配置和 ja/ru 翻译覆盖。`image`、`video` 保留。

此前备份里已经落地、本轮没有再改逻辑的文件：

- `web/modules/custom/xedc_quick/src/QuickStore.php`
- `web/modules/custom/xedc_quick/xedc_quick.services.yml`
- `web/modules/custom/xedc_quick/xedc_quick.module`
- `web/modules/custom/xedc_quick/src/Controller/QuickController.php`
- `web/modules/custom/xa_views/src/Controller/Hit.php`
- `web/modules/custom/xa_views/xa_views.routing.yml`
- `web/modules/custom/xedc_member/xedc_member.routing.yml`
- `web/modules/custom/xedc_site_audit/xedc_site_audit.module`
- `web/modules/custom/xedc_home/xedc_home.module`
- `web/modules/custom/xedc_home/src/EventSubscriber/SecurityHeaderSubscriber.php`
- `web/modules/custom/xedc_member/src/Service/MemberAliasManager.php`
- `web/themes/custom/xedc/xedc.search.inc`
- `web/modules/custom/xedc_tags/src/Controller/TagsController.php`
- `web/modules/custom/xedc_models/src/Controller/ModelsController.php`

另外对活跃配置执行了 `drush config:set smtp.settings smtp_timeout 15`，并删除了 5 组完全相同的重复 path alias（保留 id 较小的那条，公开 URL 不变）。

## 主要优化

### 直接数据库查询

审计点名的 `\Drupal::database()` 已全部去掉，复跑后 `DIRECT_DB_CONNECTION` 为 0。

- 模特别名、sitemap 的最新修改时间改为实体查询，并带 `accessCheck()`。未发布术语仍用 `accessCheck(FALSE)`，和原来读字段表的范围一致，避免 sitemap 漏掉别名术语。
- 快速上传的哈希表、原图大小表不是实体，改为注入 `database` 服务（`QuickStore`）。上传路由本来就要求管理节点权限。表已存在时不再在请求里执行 `CREATE TABLE`。
- 文章阅读数仍是字段表上的原子自增，改为注入的数据库连接，并且先确认节点是已发布文章。
- 浏览量接口 `/xa/hit/{nid}` 和会员无权页改为 `access content`，不再使用 `_access: TRUE`。匿名用户原本就能访问，前台计数和无权提示不变。

### CSS / JS

- `home.css` 只在首页加载。美图列表的聚合 CSS 里已经没有 `.xedc-hero`、`.xedc-section`。
- 登录表单样式 `auth.css` 只在登录、注册、找回密码、重置密码页加载。全站仍加载体积更小的 `login-dialog.css` 和 `auth.js`，弹窗登录行为不变。规则是从原文件拆出去的，没有改选择器。
- `inputs.css`、`xedc-pill.css`、`main.style.css` 仍全站加载，这些类在多个页面上使用。
- Matomo 跟踪脚本本身已是 `async`。没有改跟踪代码，避免统计漏计。
- CSS/JS 聚合与压缩原本已开启（`system.performance`：`preprocess` 与 `compress` 均为 true）。

### 缓存

- 页面缓存、Dynamic Page Cache、BigPipe 均已启用。匿名页面缓存 `max-age` 为 86400 秒。首页第二次请求为 `X-Drupal-Cache: HIT`。
- 首页附件按路由、路径和界面语言区分缓存，避免动态页缓存串页。
- 首页图片栏目计数写入 `cache_data`，标签为 `node_list:photo`。发布或删除美图后计数会失效，数字和原来的 SQL 一致。
- 会员别名解析本来就有永久缓存。超过 32 字或含非法字符的第一段路径不再查别名，内容 URL 结果不变。
- 登录消息和会员中心仍是 `max-age: 0`。这两处是表单令牌和个人数据，缓存会串用户或缓存过期的表单，所以保留。

### 表单、登录、邮件

- 登录页、找回密码页的 GET 约 12–15ms。提交变慢的部分不是页面渲染。
- 登录校验仍走 Drupal 密码哈希和会话，没有减弱哈希，也没有改跳转（弹窗登录、会员中心跳转都保持原提交回调）。
- 发信走 SMTP 模块连 `smtp.gmail.com:587`。本机 TCP 握手约 1 秒，完整 TLS 和发信会更长。超时从 30 秒改为 15 秒：成功发信不受影响，Gmail 无响应时表单不再挂满 30 秒。
- 没有把邮件放进队列。Cron 每 15 分钟一次，排队会让重置邮件明显变晚；若先返回成功再在后台失败，页面上的失败提示也会消失。

### 图片、别名、空媒体包

- 美图详情已经用 `photo_gallery_1300` 做主图、`photo_gallery_650` 做 srcset，并设置了 `loading` / `decoding`。首页首张轮播是 `eager` + `fetchpriority=high`，其余是 `lazy`。没有改这些样式，避免裁切和清晰度变化。审计把这两个样式标成“未使用”，是因为它只扫配置，不扫主题 PHP。
- 删除 5 组重复别名（路径、别名、语言完全相同）。`/cosplay/cos/136` 等公开地址保留一条。
- 删除 0 条内容、前台和自定义模块都未引用的媒体包：录音、文档、远程视频。工作区是 Workspaces 模块，没有卸载。

### 安全响应头

`SecurityHeaderSubscriber` 在响应里补 `Referrer-Policy: strict-origin-when-cross-origin`。HTTPS 响应补 `Strict-Transport-Security: max-age=15552000`。`X-Frame-Options` 仍是 SAMEORIGIN，登录弹窗 iframe 可以继续用。首页响应里已经能看到这两项。

## 如何验证

已执行：

- `php -l`：`HomeCards.php`、`MemberAliasPathProcessor.php`、`xedc.theme`、`auth.inc`、`QuickStore.php`、`Hit.php`
- `drush cr`
- `drush updatedb -y`（只跑了 `xedc_quick_update_10001`，补建快速上传记账表）
- `drush audit:run security,performance,cache,seo,images,url,entity,status`
- `curl` 核对 `/`、`/meitu`、`/user/login`、`/user/password` 的状态码、缓存头、安全头，以及聚合 CSS 里是否含首页样式、弹窗样式、登录表单样式

建议再人工点一遍：

1. 匿名打开首页，刷新一次，响应应带 `X-Drupal-Cache: HIT`，轮播和栏目数量与改前一致。
2. 打开美图列表和一篇美图详情，卡片和画廊构图应与改前一致，详情图仍有 srcset。
3. 未登录时从导航打开登录弹窗，登录、找回密码、注册各提交一次。成功和失败提示应和原来一样。找回密码在 SMTP 慢时最多等待约 15 秒，而不是 30 秒。
4. 用内容编辑账号确认后台仍能添加图片和视频媒体，音频、文档、远程视频入口没有了。

没有在浏览器里做点击操作。上面是 HTTP 响应和 CSS 内容核对。

## 优化前后摘要

| 项 | 改前 | 改后 |
| --- | --- | --- |
| 安全分 | 53 / F | 77 / C |
| 性能分 | 88 / B | 89 / B |
| 缓存分 | 68 / D | 73 / C |
| URL 分 | 88 / B | 98 / A |
| 实体分 | 94 / A | 97 / A |
| `DIRECT_DB_CONNECTION` | 14 处 | 0 |
| `_access: TRUE` | 2 条路由 | 0 |
| 重复别名 | 5 组 | 0 |
| 空媒体包 | 录音、文档、远程视频、工作区 | 只剩工作区 |
| 数据库更新 | `xedc_quick` 待更新 | 已执行 |
| 首页 CSS | 全站包含 `home.css` | 仅首页 |
| 登录表单 CSS | 全站包含 `auth.css` | 仅认证页面 |

SEO 分 91 → 90。缺 Pathauto 的两个词表和用户头像 alt 没改；删掉三个空媒体包后，媒体 alt 统计的分母变了，分数略降。前台标题和别名没有改。

## 剩余需要人工确认

这些项要么会改变现有账号、权限或后台能力，要么要改服务器或 `settings.php`，本轮没有动。

- 文件系统：`sites/default/settings.php` 和 `sites/default/files/.htaccess` 对 Web 进程可写。收紧权限要和备份脚本一起看，避免把配置写坏。
- 内容编辑角色仍有：添加 Matomo JS 片段、管理内容类型、管理元标签、管理节点发布状态、管理内容、绕过节点访问、配置任意布局。收这些权限会改变编辑后台。
- UID 1 仍启用，用户名是 `admin`。改用户名或停用 UID 1 会影响现有管理员登录。
- 访客注册不需要管理员批准。改成需审核会改变注册流程。
- `/search` 别名指向 `/search/node`，盖住了核心 `search.view`。这是当前搜索页，删除别名会改搜索 URL。
- 词表「人物」「图片栏目」没有 Pathauto 模式。补模式并批量生成会改已有网址。
- 用户头像字段关闭了 alt。打开后编辑资料页会多一个输入项。
- 媒体默认/Gallery 显示没用响应式图片样式。前台画廊已经自己输出 srcset，改显示配置不一定作用到前台，反而可能改后台预览尺寸。
- 登录消息和会员中心 `max-age: 0` 是故意的。
- 快速上传和自动翻译在循环里 `save()`，是为了逐条触发钩子。改成批量保存会改变翻译和上传的副作用。
- BigPipe 无会话模块、Redis/Memcache 未安装。缓存 bin 因此在数据库上。安装它们要新依赖和 `settings.php`。
- Colorbox 与 DOMPurify 库未下载。前台灯箱是主题自己的，不是 Colorbox。装上库可能让 Colorbox 开始接管图片。
- IndexNow 密钥、InnoDB `buffer_pool` 128MB、`max_allowed_packet` 16MB、实验主题、工具栏与导航同时启用：分别要改 `settings.php`、MySQL 或卸载模块。
- 美图 en/ru/ja 翻译覆盖率约 76%，以及界面翻译覆盖率。这是内容，不是代码。
- `drush updatedb` 提示 `xedc_audit` 在数据库里没有 schema 记录。该模块没有 `hook_update_N`。需要的话再核对 `key_value` 里的 schema 版本，不要凭空补更新。
- 用户字段「个人简介」「昵称」被标成未出现在显示和表单里。它们可能被会员代码读取，没有删除。
