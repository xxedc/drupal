# XEDC 会员中心阶段 0：只读审计报告与实施计划

> 审计日期：2026-10-24  
> 项目根目录：`/var/www/drupal`  
> Drupal：11.4.11  
> 本阶段结论：只完成现状审计与方案设计，未修改任何项目文件、配置或数据库。

## 0. 审计结论摘要

1. 当前站点没有会员中心、收藏、浏览历史、投稿/审核中心；只有基础用户账户、登录/注册/找回密码，以及仅限“美图/photo”的评论。
2. 实际内容类型中没有 `gallery`。美图内容类型机器名是 `photo`，`gallery` 只出现在视图机器名 `image_gallery` 和 `xedc_quick` 的上传目录 `public://gallery/` 中。
3. 未启用 `workflows`、`content_moderation`；普通登录用户没有任何内容创建、编辑、发布权限。内容编辑角色权限较大，拥有 `administer nodes`、`bypass node access`。
4. 评论模块已启用，但只有 `photo` 有评论字段；47 条评论全部已发布；匿名用户和登录用户都有 `skip comment approval`，目前实际上没有评论审核。
5. 所有媒体/文件都在 public 文件系统，图片和视频上传没有大小上限；成员投稿若沿用 media library，未审核文件可能通过直接 URL 访问。服务器层是否完全禁止直接访问，属于待检查项。
6. 最大阻塞项：项目声明的 `config/sync` 与 Drupal 实际使用的同步目录不一致，且数据库中有未导出配置。在解决配置同步问题前，不应执行 `drush cim`/`drush cex` 或任何全站配置导入。
7. 建议新增独立模块 `web/modules/custom/xedc_member/`，复用 Drupal 核心 Comment、Content Moderation、Workflows、Views、Form API、Entity/DB API，不引入 Flag/Profile/Message 等新依赖。

### 审计操作说明

- 仅执行只读检查：`git status`、`git diff`、文件读取、`drush status`、`drush config:status`、`drush updatedb:status`、只读 `php:eval` 查询、`SELECT`/`SHOW TABLES`。
- 未执行 `git reset`、`checkout`、`restore`、`clean`、`commit`，未执行 Composer 安装/更新、`cim`、`cex`、`cr`、`updb`、模块启用、构建或部署。
- 未创建、修改、删除、重命名任何项目文件；审计结束时 `git status` 与开始时一致。
- 安全提醒：检查 `settings.php` 时终端输出曾显示数据库连接信息；本报告未复制这些值。建议评估轮换数据库密码，并确认 `settings.php` 文件权限最小化。

---

## 1. 现有未提交工作的保护说明

当前工作区不是干净状态，后续阶段不得覆盖、回滚或清理以下内容。

### 已修改但未提交

```text
 M web/themes/custom/xedc/xedc.libraries.yml
 M web/themes/custom/xedc/xedc.theme
```

- `xedc.libraries.yml`：新增 `article-detail` 库。
- `xedc.theme`：新增约 219 行文章详情页预处理，包括 `xedc_preprocess_node__article__full`、封面、正文、阅读时长、相关阅读等。

### 未跟踪文件

```text
?? AGENTS.md
?? opencode.json
?? opencode.json.bak
?? web/modules/custom/xa_views/
?? web/themes/custom/xedc/css/article-detail.css
?? web/themes/custom/xedc/js/article-detail.js
?? web/themes/custom/xedc/templates/node/node--article--full.html.twig
```

### 暂存区

无暂存改动。

### 与未提交工作相关的数据库配置

`drush config:status` 显示以下配置只存在于数据库、尚未导出：

- `field.field.node.article.field_show_cover`
- `field.storage.node.field_show_cover`
- `image.style.xa_cover`
- `image.style.xa_hero`

其中 `field_show_cover`、`xa_cover`、`xa_hero` 与当前未提交的文章详情页工作直接相关。在确认这些配置归属前，不要执行配置导出/导入，也不要覆盖主题文件。

---

## 2. 环境与当前架构

| 项目 | 现状 |
|---|---|
| Drupal | 11.4.11 |
| PHP | 8.5.12 |
| 数据库 | MariaDB 13.0.2，mysql 驱动 |
| 站点配置 | `standard` profile |
| 默认主题 | `xedc`，基于 Radix 6 / Bootstrap 5 |
| 管理主题 | `gin`、`claro`、`default_admin` 等已安装 |
| 内容类型 | `article`、`video`、`photo`、`page` |
| 用户数 | 7 个用户，其中 3 个启用；显式角色有 1 个管理员、1 个内容编辑 |
| 内容数量 | article 11、video 6、photo 41（其中 2 篇未发布）、page 4 |

### 2.1 相关模块启用状态

已启用且相关：

- `user`、`node`、`comment`、`media`、`media_library`、`taxonomy`、`file`、`image`
- `views`、`views_ui`、`views_bulk_operations`、`views_infinite_scroll`
- `pathauto`、`path`、`redirect`、`metatag`、`metatag_routes`
- `statistics`、`smtp`、`mailsystem`
- `user_registrationpassword`、`token`、`twig_tweak`
- 自定义：`xedc_models`、`xedc_quick`、`xedc_tags`、`xa_views`

未启用且相关：

- `workflows`
- `content_moderation`
- `history`（核心已标记 deprecated）
- `flag`、`profile`、`message`、通知类模块
- 私有文件系统未启用

没有安装收藏、Flag、个人中心、通知、会员资料类贡献模块。

### 2.2 关键配置同步问题

`AGENTS.md` 声明配置同步目录为 `/var/www/drupal/config/sync`，但 `web/sites/default/settings.php:918` 实际指向：

```text
sites/default/files/config_<hash>/sync
```

`drush config:status` 当前显示 9 项差异：

- `core.entity_form_display.node.article.default`
- `core.entity_view_display.node.article.default`
- `core.extension`
- `field.field.node.article.field_show_cover`（Only in DB）
- `field.storage.node.field_show_cover`（Only in DB）
- `image.style.xa_cover`（Only in DB）
- `image.style.xa_hero`（Only in DB）
- `user.role.content_editor`
- `views.view.article_list`

同时：

- 项目 `config/sync` 有 386 个文件，实际同步目录也有 386 个文件，但内容不完全一致。
- 实际同步目录缺少项目中的 `image.style.xa_cover.yml`。
- `config/sync/core.extension.yml` 不包含 `xa_views`，但 `xa_views` 当前是启用状态。
- 项目 `config/sync` 中 `user.role.content_editor.yml`、`views.view.article_list.yml` 与实际同步目录也不同。

结论：当前没有可信的单一配置源。阶段 1 前必须先备份、比对并确认以哪一个目录为准，否则配置导入可能回退现有功能。具体以哪套目录作为部署源，待项目负责人确认。

---

## 3. 用户系统现状

### 3.1 角色与权限

| 角色 | 机器名 | 关键权限 | 说明 |
|---|---|---|---|
| 匿名用户 | `anonymous` | 8 项：`access content`、`access comments`、`post comments`、`edit own comments`、`skip comment approval`、`search content`、`use text format restricted_html`、`view media` | 当前允许匿名评论 |
| 已登录用户 | `authenticated` | 10 项：`access content`、`access comments`、`post comments`、`edit own comments`、`skip comment approval`、`search content`、`view media`、`delete own files`、`use text format basic_html`、Matomo 选择 | 没有任何内容创建/编辑/发布权限 |
| 内容编辑 | `content_editor` | 62 项，包括 `administer nodes`、`bypass node access`、`administer node published status`、创建/删除任意 article/photo/video、媒体管理、内容翻译、Meta、Pathauto 等 | 权限较大，适合作为审核员或后台编辑；也可另建更小权限的审核角色 |
| 管理员 | `administrator` | `is_admin: true` | 拥有全部权限 |

关键事实：

- `authenticated` 没有 `create article content`、`create photo content`、`create video content`。
- `authenticated` 没有 `view own unpublished content`。
- `authenticated` 没有 `access user profiles`，不能查看其他用户资料页。
- `content_editor` 没有 `administer comments`，目前评论管理实际只有管理员能做。
- 没有单独的“会员”或“投稿者”角色；当前“登录用户”就是事实上的会员。

### 3.2 登录、注册、找回密码、资料编辑

现有实现集中在主题：

- `web/themes/custom/xedc/includes/auth.inc:19`：识别登录、注册、找回密码、重置密码、带 token 的资料编辑路由。
- `web/themes/custom/xedc/includes/auth.inc:91`：登录表单改造，支持用户名或邮箱登录。
- `web/themes/custom/xedc/includes/auth.inc:142`：注册表单精简为用户名、邮箱、密码。
- `web/themes/custom/xedc/includes/auth.inc:219`：找回密码表单。
- `web/themes/custom/xedc/includes/auth.inc:284`：用户编辑表单、密码重置后的新密码表单。
- `web/themes/custom/xedc/includes/auth.inc:267`：密码规则至少 8 位，且包含字母和数字。
- `web/themes/custom/xedc/js/auth.js`：登录弹窗、iframe 预加载、自动继续重置密码、防重复提交。
- `web/themes/custom/xedc/css/auth.css`、`css/usermenu.css`：登录/注册/用户菜单样式。
- `web/themes/custom/xedc/xedc.theme:41`：`xedc_preprocess_page` 构建导航。
- `web/themes/custom/xedc/xedc.theme:269`：主导航数据；登录/未登录链接在自定义头部模板中。

账户设置：

- `user.settings.yml`：`register: visitors`，允许访客注册。
- `verify_mail: false`：注册不要求邮箱验证。
- `user_registrationpassword.settings.yml`：`registration: with-pass`，注册时直接设置密码。
- `cancel_method: user_cancel_block`：注销方式为封禁；`authenticated` 没有 `cancel account` 权限，普通会员不能自行注销。
- 用户可编辑自己的账户（Drupal 核心 `UserAccessControlHandler` 允许用户更新自己）。
- 用户资料字段只有 `user_picture`（头像，public，无大小上限），没有昵称、简介、性别、地区等会员资料字段。

### 3.3 用户页面模板与路由

| 功能 | 路由/路径 | 模板 |
|---|---|---|
| 我的账户 | `user.page` `/user` | `templates/user/user.html.twig`，实际 include `radix:user` |
| 编辑账户 | `user.edit` `/user/edit` | Radix 默认用户表单 |
| 登录 | `user.login` `/user/login` | 主题登录卡片 + iframe 弹窗 |
| 注册 | `user.register` `/user/register` | 主题注册卡片 |
| 找回密码 | `user.pass` `/user/password` | 主题找回密码卡片 |
| 重置密码 | `user.reset*` | 主题重置卡片 |
| 其他用户资料 | `entity.user.canonical` | 需要 `access user profiles`，当前未授予 |

账户菜单：

```text
我的帐户 | /user
登录     | /user/login
```

自定义头部在登录后显示“我的账户”链接到 `user.page`，移动端侧边栏也有同样入口。目前没有 `/member` 或任何会员中心路由。

### 3.4 是否已有会员中心/收藏/历史/通知

没有。

- 自定义模块中没有 member/profile/favorite/history 相关代码。
- 主题、模块、配置中搜索 `收藏`、`浏览历史`、`favorite`、`bookmark`、`会员中心`、`notification`、`flag` 无业务实现。
- `statistics` 只提供全站节点浏览量统计，不是个人浏览历史。
- 核心 `history` 模块已废弃且未启用，只适合“新内容/已读”标记，不适合完整历史。
- 没有站内通知模块；只有 SMTP/mailsystem 邮件基础设施。

---

## 4. 内容类型与字段

### 4.1 `gallery` 命名问题

实际内容类型：

| 类型 | 机器名 | 名称 | 当前数量 |
|---|---|---|---|
| 文章 | `article` | 文章 | 11 |
| 视频 | `video` | 视频 | 6 |
| 美图 | `photo` | 美图 | 41（2 未发布） |
| 基本页面 | `page` | 基本页面 | 4 |

没有 `gallery` 内容类型。需求中的 gallery 应对应 `photo`。`image_gallery` 是视图机器名，路径 `/meitu`。如果一定要新增 `gallery` 机器名，需要新建内容类型、字段、视图、模板并迁移数据，成本明显更大；建议复用 `photo`，仅在 UI 文案使用“图集/美图”。

### 4.2 article 字段

| 字段机器名 | 类型 | 基数 | 必填 | 说明 |
|---|---|---:|---|---|
| `title` | string | 1 | 是 | 核心标题 |
| `field_summary` | string_long | 1 | 否 | 文章摘要 |
| `field_body` | text_long | 1 | 否 | 正文，现有数据为 `basic_html` |
| `field_cover` | entity_reference | 1 | 否 | 指向 `media:image` |
| `field_categories` | entity_reference | 1 | 否 | 指向 `taxonomy:article_category`，`auto_create: true`，但 `auto_create_bundle` 写成 `photo_category`，配置不一致 |
| `field_tags` | entity_reference | -1 | 否 | 可引用 `photo_category`、`article_category`、`tags`、`video_category`，`auto_create: true` |
| `field_author` | string | 1 | 否 | 文本作者，不是用户引用 |
| `field_source` | string | 1 | 否 | 来源 |
| `field_source_url` | link | 1 | 否 | 原文链接 |
| `field_published_at` | datetime | 1 | 否 | 发布时间 |
| `field_views` | integer | 1 | 否 | 阅读量 |
| `field_show_cover` | boolean | 1 | 否 | 仅存在于数据库，未导出到配置；与当前未提交文章详情页相关 |
| `uid` / `status` / `created` / `changed` / `path` | 核心 | 1 | — | 作者、发布状态、时间、别名 |
| 评论字段 | — | — | — | 没有评论字段 |

### 4.3 video 字段

| 字段机器名 | 类型 | 基数 | 必填 | 说明 |
|---|---|---:|---|---|
| `title` | string | 1 | 是 | 核心标题 |
| `field_body` | text_long | 1 | 否 | 视频简介，现有数据为 `basic_html` |
| `field_video_cover` | entity_reference | 1 | 否 | 指向 `media:image` |
| `field_video_file` | entity_reference | 1 | 否 | 指向 `media:video`，媒体文件只允许 `mp4` |
| `field_video_url` | link | 1 | 否 | 外部视频地址，模板支持 YouTube、Bilibili、Twitter/X、Instagram、m3u8、mp4 等 |
| `field_duration` | integer | 1 | 否 | 时长，秒 |
| `field_categories` | entity_reference | 1 | 否 | 指向 `taxonomy:video_category`，`auto_create: true` |
| `field_tags` | entity_reference | -1 | 否 | 指向 `taxonomy:tags`，`auto_create: true` |
| `uid` / `status` / `created` | 核心 | 1 | — | 作者、发布状态、时间 |
| 评论字段 | — | — | — | 没有评论字段 |

### 4.4 photo（图集）字段

| 字段机器名 | 类型 | 基数 | 必填 | 说明 |
|---|---|---:|---|---|
| `title` | string | 1 | 是 | 核心标题 |
| `field_cover_image` | entity_reference | 1 | 否 | 封面，指向 `media:image` |
| `field_images` | entity_reference | -1 | 否 | 图集，指向 `media:image`，可多值 |
| `field_summary` | string_long | 1 | 否 | 内容描述 |
| `field_categories` | entity_reference | 1 | 否 | 指向 `taxonomy:photo_category`，`auto_create: true` |
| `field_model` | entity_reference | -1 | 否 | 人物/模特，指向 `taxonomy:models`，`auto_create: true` |
| `field_tags` | entity_reference | -1 | 否 | 指向 `taxonomy:tags`，`auto_create: true` |
| `field_comment` | comment | 1 | 否 | 评论字段，当前 41 个节点全部为 `status=2`（开放） |
| `uid` / `status` / `created` | 核心 | 1 | — | 作者、发布状态、时间 |

### 4.5 表单显示、展示显示、访问权限

- 三种内容都使用 `default` 表单显示；表单中包含 `uid`、`status`、`created`、`path`、`url_redirects` 等管理字段。
- `article` 表单还包含 `field_views`、`field_published_at`；这些不应暴露给普通会员。
- `photo` 表单包含 `field_comment` 的评论设置。
- 三种内容都有 `default` 展示显示；没有专门的“会员投稿”表单显示或展示模式。
- 节点访问控制使用 Drupal 默认 node access；数据库 `node_access` 只有默认 grant，没有额外 node access 模块。
- 未发布内容默认只有 `bypass node access`、`administer nodes`、作者本人且具备 `view own unpublished content` 时可见。当前 `authenticated` 没有 `view own unpublished content`。
- `content_editor` 拥有 `bypass node access`，可查看/编辑所有内容。
- `page` 不参与会员投稿。

### 4.6 路由与模板位置

| 内容 | 路径 | 模板 |
|---|---|---|
| 文章详情 | `/node/{nid}`，无 pathauto 别名 | `templates/node/node--article--full.html.twig`（当前未跟踪）；通用回退 `templates/content/node.html.twig` |
| 视频详情 | `/node/{nid}` | `templates/node/node--video--full.html.twig` |
| 美图详情 | `/node/{nid}`，photo 有 pathauto 别名 `/[分类]/[nid]` | `templates/content/node--photo--full.html.twig` |
| 美图列表 | `/meitu`、`/meitu2`、`/taxonomy/term/%` | `views.view.image_gallery` + 通用 views 模板 |
| 视频列表 | `/video` | `views.view.video_list` + `views-view-fields--video-list.html.twig` |
| 文章列表 | `/articles` | `views.view.article_list` + `views-view--article-list.html.twig` |
| 评论 | 节点详情内 | `templates/comment/comment.html.twig`、`templates/field/field--comment.html.twig` |
| 用户 | `/user` | `templates/user/user.html.twig` |

### 4.7 上传与验证现状

- `system.file.yml`：`default_scheme: public`，`allow_insecure_uploads: false`，临时文件 6 小时。
- `file_private_path` 未配置。
- `media.type.image`：`png gif jpg jpeg webp`，`max_filesize` 为空，`max_resolution` 为空。
- `media.type.video`：只允许 `mp4`，`max_filesize` 为空。
- 用户头像：`png gif jpg jpeg webp`，`max_filesize` 为空。
- 评论图片：`png gif jpg jpeg webp`，2MB，最大 1600×1600。
- 节点字段本身大多不是必填；标题必填，但正文、封面、分类等都可以为空。
- 现有媒体、文件字段都是 public；未审核内容关联的文件没有 Drupal 文件级访问保护。服务器 Nginx 是否完全禁止直接访问上传目录，待检查。

---

## 5. 评论系统现状

| 项目 | 现状 |
|---|---|
| 评论模块 | 已启用 |
| 评论类型 | `content`，目标实体 `node` |
| 允许评论的内容类型 | 只有 `photo`；`article`、`video`、`page` 没有评论字段 |
| 评论字段 | `photo.field_comment`，`comment` 类型，基数 1 |
| 评论节点状态 | 41 个 photo 全部 `status=2`（开放） |
| 评论正文 | `comment_body`，`text_long`，允许格式只有 `plain_text` |
| 评论图片 | `field_comment_image`，图片，public，2MB，1600×1600 |
| 匿名评论 | `anonymous: 0` 表示匿名者不能填写联系方式；但匿名角色有 `post comments`，所以匿名评论实际可用 |
| 现有评论 | 47 条，全部 `status=1`（已发布） |
| 评论作者分布 | 24 条匿名（uid 0），22 条 uid 2，1 条 uid 1 |
| 审核 | `anonymous`、`authenticated` 都有 `skip comment approval`，所以新评论默认直接发布 |
| 编辑 | 作者可编辑自己的已发布评论（`edit own comments`）；未发布评论作者不能编辑 |
| 删除 | 核心没有“删除自己的评论”权限；只有 `administer comments` 可删除 |
| 管理入口 | `/admin/content/comment`、`/admin/content/comment/approval`；当前只有管理员能管理 |
| 内容编辑角色 | 没有 `administer comments` |

### 会员中心“我的评论”设计限制

- 如果继续保留所有角色 `skip comment approval`，则“审核状态”永远只是“已发布”，没有待审核状态。
- 如果移除 `skip comment approval`，新评论会变成未发布；但 Drupal 核心评论访问控制不允许普通用户查看自己的未发布评论。因此“我的评论”不能直接用 `accessCheck(TRUE)` 查询，否则待审核评论会消失。
- 推荐做法：
  - 用 `entityQuery('comment')->accessCheck(FALSE)->condition('uid', 当前用户)` 限定为当前用户，再逐条检查父节点 `access('view')`。
  - 已发布评论可链接到评论 permalink；待审核评论只显示正文摘要、父内容标题、时间、状态，不生成公开链接。
  - 父节点未发布或用户无权查看时，显示“内容不可用”，不泄露标题。
  - 评论正文继续使用 `plain_text`，通过字段渲染或 `check_markup()` 输出，避免 XSS。
- 如果产品要求“我的评论”覆盖 article/video，则必须给这两个类型增加 `field_comment` 评论字段及展示配置。这是配置变更，并涉及现有节点评论状态初始化。

---

## 6. 投稿和审核工作流现状

### 6.1 现状

- `workflows`、`content_moderation` 未启用。
- 没有工作流状态、转换、审核权限。
- `article`、`video`、`photo` 都是 `new_revision: true`，具备修订版本基础。
- 普通登录用户没有任何创建/编辑/发布权限。
- `content_editor` 可创建、编辑、删除、发布任意 article/photo/video，且拥有 `bypass node access`。
- 管理员是超级管理员。
- 没有“会员投稿”内容类型、投稿表单、审核队列或审核通知。
- 管理审核入口目前只有：
  - `/admin/content`（内容列表）
  - `/admin/content/comment`（评论）
  - `/admin/people`（用户）
- 没有内容审核通知机制；但有 SMTP/mailsystem，可发送邮件。

### 6.2 关键风险：节点默认是已发布

Drupal 节点 `status` 基础字段默认值为 `TRUE`。`NodeAccessControlHandler.php:256` 只限制谁能编辑 `status` 字段，但新建节点时即使隐藏了“发布”复选框，节点仍可能默认发布。

因此，普通会员投稿方案不能只靠“隐藏 status 字段”。必须采用以下之一：

1. 启用 Content Moderation，将新内容默认状态设为 `draft`；这是推荐方案。
2. 不启用 Content Moderation，但在 `hook_entity_presave()` 中对无发布权限的用户强制 `status = 0`，并增加自定义审核状态字段。

### 6.3 推荐：启用 Content Moderation + Workflows

建议对 `article`、`photo`、`video` 启用内容审核，不修改 `page`。

状态设计：

| 状态 | 发布 | 默认修订 | 说明 |
|---|---|---|---|
| `draft` | 否 | 否 | 会员草稿 |
| `needs_review` | 否 | 否 | 已提交，等待审核 |
| `changes_requested` | 否 | 否 | 退回修改 |
| `rejected` | 否 | 否 | 拒绝（建议终态） |
| `published` | 是 | 是 | 审核通过 |

转换设计：

| 转换 | 起点 → 终点 | 权限建议 |
|---|---|---|
| `submit_for_review` | draft → needs_review | 会员 |
| `resubmit_for_review` | changes_requested → needs_review | 会员 |
| `withdraw` | needs_review → draft | 会员（可选） |
| `request_changes` | needs_review → changes_requested | 审核员 |
| `reject` | needs_review → rejected | 审核员 |
| `approve` | needs_review → published | 审核员 |
| `create_new_draft` | published → draft | 审核员/编辑 |

关键机制：

- `ContentModeration.php:298`：已有内容进入审核时，初始状态根据当前发布状态推导；现有已发布内容保持 published，现有未发布内容变为 draft。当前 2 篇未发布 photo 会变成 draft，不会影响已发布内容。
- `ContentModeration.php:301`：新内容默认状态由 `default_moderation_state` 决定；应设为 `draft`。
- `ModerationStateConstraintValidator.php:122`：状态转换会校验用户是否有对应 transition 权限，恶意 POST `moderation_state=published` 会被校验拦截。
- 对受审核实体，`status` 字段由 Content Moderation 管理，普通用户不能直接编辑。
- 节点类型已启用修订，满足“退回修改、重新提交、保留历史版本”。

### 6.4 推荐权限矩阵

| 能力 | 匿名 | 普通会员（authenticated） | 审核员（content_editor 或新角色） | 管理员 |
|---|---|---|---|---|
| 访问会员中心 | 否 | 是 | 是 | 是 |
| 收藏/历史 | 否 | 仅自己 | 仅自己 | 仅自己 |
| 我的评论 | 否 | 仅自己 | 仅自己 | 全部 |
| 创建 article/photo/video | 否 | 是 | 是 | 是 |
| 编辑自己的投稿 | 否 | 是 | 是 | 是 |
| 查看自己的未发布内容 | 否 | 是 | 是 | 是 |
| 提交/重新提交审核 | 否 | 是 | 是 | 是 |
| 直接发布 | 否 | 否 | 是 | 是 |
| 审核通过/退回/拒绝 | 否 | 否 | 是 | 是 |
| 查看他人未发布内容 | 否 | 否 | 是 | 是 |
| 管理评论 | 否 | 否 | 建议授予 `administer comments` | 是 |
| 管理用户/角色 | 否 | 否 | 否 | 是 |

普通会员建议授予：

```text
access xedc member center
create article content
edit own article content
delete own article content
create photo content
edit own photo content
delete own photo content
create video content
edit own video content
delete own video content
view own unpublished content
view latest version
use xedc_editorial transition submit_for_review
use xedc_editorial transition resubmit_for_review
use xedc_editorial transition withdraw（可选）
```

审核员建议授予：

```text
access content overview
view any unpublished content
view latest version
use xedc_editorial transition approve
use xedc_editorial transition request_changes
use xedc_editorial transition reject
use xedc_editorial transition create_new_draft
administer comments
```

注意：

- 不要给普通会员 `administer nodes`、`administer node published status`、`bypass node access`、`view any unpublished content`。
- `view latest version` 单独授予不会泄露他人未发布修订；它需要配合 `view any unpublished content` 或“作者本人 + view own unpublished content”才能查看待审修订。
- 如果使用 `content_editor` 作为审核员，它已经拥有 `bypass node access` 和 `administer nodes`，可以直接发布。若要求最小权限，建议新建 `reviewer` 角色，而不是继续扩大 `content_editor`。

### 6.5 退回修改与重新提交

推荐流程：

1. 会员创建内容，状态 `draft`，节点未发布。
2. 会员编辑并提交，转换到 `needs_review`。
3. 审核员在 `/admin/content/moderated` 查看待审内容。
4. 审核员选择：
   - 通过 → `published`，节点发布。
   - 退回修改 → `changes_requested`，填写 `field_review_note`。
   - 拒绝 → `rejected`，填写原因。
5. 会员在会员中心看到状态和审核意见；`changes_requested` 状态下可编辑并重新提交。
6. 每次保存产生新修订；审核员可查看修订历史。

`field_review_note` 建议新增为 `text_long` 或 `string_long`：

- 审核员可编辑；
- 作者可查看；
- 匿名和公开页面不显示；
- 会员中心显示最新审核意见。

### 6.6 文件与媒体权限风险

当前媒体和文件全部为 public：

- 如果给会员 `create image media`、`create video media`，他们可以通过 media library 上传；未审核媒体本身是已发布媒体，直接 URL 可能可访问。
- 直接文件 URL 不受节点发布状态保护。
- `file_private_path` 未配置，无法直接使用 `private://`。
- 如果安全要求“未审核文件不可访问”，需要：
  - 配置私有文件目录（通常在 web root 外），并调整服务器配置；
  - 或使用自定义上传/下载控制器，按节点访问权限控制文件读取；
  - 或至少限制文件类型、大小、文件名，并明确接受“知道 URL 即可访问”的残余风险。

这是阶段 3 前必须由项目负责人决定的安全取舍。

---

## 7. 收藏与浏览历史设计

### 7.1 是否已有可复用实现

没有。

- 没有 Flag、Favorites、Bookmarks、History、Profile、Message 模块。
- `statistics` 只有聚合计数，不能按用户查询。
- `history` 核心模块 deprecated，只记录“新/已更新”标记，不是完整历史。
- `xa_views` 只做文章阅读量，不记录用户。
- `views` 可用于列表展示，但没有收藏/历史数据表。

### 7.2 收藏数据模型

推荐使用自定义数据库表，而不是引入 Flag 或自定义内容实体。

表：`xedc_member_favorite`

| 字段 | 类型 | 说明 |
|---|---|---|
| `fid` | serial | 主键 |
| `uid` | int unsigned | 用户 ID |
| `entity_type` | varchar(32) | 当前固定 `node`，为未来扩展保留 |
| `entity_id` | int unsigned | 节点 ID |
| `bundle` | varchar(32) | `article`、`photo`、`video`，便于筛选 |
| `created` | int | 收藏时间 |

索引：

- 唯一键 `(uid, entity_type, entity_id)`：防止重复收藏。
- 普通索引 `(uid, created)`：会员收藏列表。
- 普通索引 `(entity_type, entity_id)`：内容删除时清理。

行为：

- 添加使用 `merge()` 或捕获唯一键冲突，保证幂等；重复提交不产生重复记录。
- 取消收藏按 `uid + entity_type + entity_id` 删除。
- 列表只查询当前登录用户 UID，绝不接受请求参数传入 UID。
- 支持 `type=article|photo|video` 筛选、分页、按收藏时间倒序。
- 内容取消发布：默认从列表隐藏，但保留记录；重新发布后恢复显示。
- 内容删除：`hook_entity_delete()` 删除关联收藏。
- 用户注销/删除：`hook_user_cancel()` / `hook_entity_delete()` 删除该用户全部收藏。
- 访问控制：添加/取消只允许当前用户操作；列表只显示当前用户记录；跨用户 ID 操作返回 403 或忽略。
- 缓存：列表使用 `user` 缓存上下文；写操作使自定义 cache tag 失效，或初期直接 `max-age=0`。

评估：

- DB 表 + 服务层：最少代码、无新依赖、性能好，适合当前规模。
- 自定义内容实体：可获得实体访问控制和 Views 集成，但代码和配置更多；当前不需要。
- Flag 模块：功能完整但引入新依赖和配置，且需要额外权限/视图配置；不建议仅为收藏引入。
- 推荐：DB 表 + `FavoriteManager` 服务 + Form API/控制器。

### 7.3 浏览历史数据模型

表：`xedc_member_history`

| 字段 | 类型 | 说明 |
|---|---|---|
| `hid` | serial | 主键 |
| `uid` | int unsigned | 用户 ID |
| `entity_type` | varchar(32) | 当前固定 `node` |
| `entity_id` | int unsigned | 节点 ID |
| `bundle` | varchar(32) | `article`、`photo`、`video` |
| `first_viewed` | int | 首次浏览时间 |
| `last_viewed` | int | 最近浏览时间 |
| `view_count` | int unsigned | 浏览次数，默认 1 |

索引：

- 唯一键 `(uid, entity_type, entity_id)`：同一用户同一内容只有一条记录。
- `(uid, last_viewed)`：历史列表和分页。
- `(entity_type, entity_id)`：内容删除清理。
- `(last_viewed)`：保留期限清理。

记录规则：

- 仅登录用户记录；匿名不记录。
- 仅记录允许的内容类型：`article`、`photo`、`video`。
- 仅记录已发布节点。
- 仅在节点 canonical full 页面记录：
  - 路由必须是 `entity.node.canonical`；
  - `view_mode === 'full'`；
  - 请求为 GET；
  - 不是 AJAX、不是 preview、不是后台页面、不是列表/teaser 渲染。
- 同一用户重复访问同一内容时更新 `last_viewed`、`view_count`，不新增记录。
- 建议 5 分钟节流：同一用户同一节点 5 分钟内只更新一次，避免写放大。
- 用户关闭记录后不再写入；已有记录保留，直到用户清空或保留期限到期。
- 用户只能查询、删除自己的记录；所有查询强制 `uid = 当前用户`。
- 支持按内容类型筛选、删除单条、清空全部。
- 内容删除：清理该内容全部历史。
- 用户注销/删除：清理该用户全部历史。
- 保留期限：建议默认 180 天，通过 `hook_cron()` 清理；可配置。
- 不记录 IP、User-Agent、Referer 等额外个人信息。

评估：

- 核心 `history` 模块不适合，且已废弃。
- `statistics` 是聚合统计，不是个人历史。
- 推荐 DB 表 + `HistoryManager` 服务；不引入新模块。
- 记录位置建议用 `hook_entity_view()` 而不是前端 JS，确保跨设备、无 JS 也能记录；但要严格做路由和 view mode 判断，避免列表/AJAX 误记录。

### 7.4 收藏/历史的缓存与 SEO

- 会员页面必须按用户隔离缓存：`#cache['contexts'][] = 'user'`，初期可 `max-age = 0`。
- 页面加 `noindex, nofollow, noarchive`。
- 收藏/历史 AJAX 端点设置 `no_cache: TRUE`，仅 POST。
- 不使用 localStorage 保存历史；跨设备必须服务端存储。
- 如果使用 Matomo，建议排除 `/member*` 或确保尊重用户 opt-out，避免把私人页面行为发送到分析平台。

---

## 8. 推荐的最小改动架构

### 8.1 新模块

建议新增：

```text
web/modules/custom/xedc_member/
```

不修改现有业务模块，不引入新的 Composer 依赖。

### 8.2 计划文件结构

```text
web/modules/custom/xedc_member/
  xedc_member.info.yml
  xedc_member.routing.yml
  xedc_member.permissions.yml
  xedc_member.services.yml
  xedc_member.libraries.yml
  xedc_member.module
  xedc_member.install
  config/install/xedc_member.settings.yml
  config/schema/xedc_member.schema.yml
  src/Controller/MemberController.php
  src/Controller/FavoriteController.php
  src/Controller/HistoryController.php
  src/Controller/CommentController.php
  src/Controller/SubmissionController.php
  src/Service/FavoriteManager.php
  src/Service/HistoryManager.php
  src/Form/FavoriteForm.php
  src/Form/HistorySettingsForm.php
  src/Form/HistoryDeleteForm.php
  src/Form/HistoryClearForm.php
  templates/xedc-member-shell.html.twig
  templates/xedc-member-overview.html.twig
  templates/xedc-member-favorites.html.twig
  templates/xedc-member-history.html.twig
  templates/xedc-member-comments.html.twig
  templates/xedc-member-submissions.html.twig
  css/member.css
  js/member.js
```

阶段 3 可能新增：

```text
  src/EventSubscriber/SubmissionNotification.php
  config/install/workflows.workflow.xedc_editorial.yml
  config/install/field.storage.node.field_review_note.yml
  config/install/field.field.node.article.field_review_note.yml
  config/install/field.field.node.photo.field_review_note.yml
  config/install/field.field.node.video.field_review_note.yml
```

### 8.3 路由建议

| 路由 | 路径 | 访问 |
|---|---|---|
| `xedc_member.overview` | `/member` | 登录 + `access xedc member center` |
| `xedc_member.favorites` | `/member/favorites` | 登录 |
| `xedc_member.favorite_add` | `/member/favorites/add/{node}` | POST + CSRF |
| `xedc_member.favorite_remove` | `/member/favorites/remove/{node}` | POST + CSRF |
| `xedc_member.history` | `/member/history` | 登录 |
| `xedc_member.history_delete` | `/member/history/delete/{node}` | POST + CSRF |
| `xedc_member.history_clear` | `/member/history/clear` | POST + CSRF |
| `xedc_member.settings` | `/member/settings` | 登录 |
| `xedc_member.comments` | `/member/comments` | 登录 |
| `xedc_member.submissions` | `/member/submissions` | 登录 |
| `xedc_member.submission_add` | 可重定向到 `/node/add/{type}` | 登录 + 内容创建权限 |
| 管理审核 | 复用 `/admin/content/moderated`、`/admin/content/comment/approval` | 审核员权限 |

建议使用 Form API 处理所有写操作，自动获得 CSRF 保护；收藏按钮也优先用表单，JS 只做增强。

### 8.4 服务与实体

- `FavoriteManager`：添加、删除、查询、清理；依赖 `Connection`。
- `HistoryManager`：记录、更新、查询、删除、清空、清理过期；依赖 `Connection`。
- 不新增自定义内容实体；收藏/历史是关系表，不需要字段 API 和实体 UI。
- 会员中心页面使用控制器返回渲染数组，`#theme` 指向模块模板。
- 通过 `hook_theme()` 注册模板。
- 通过 `hook_preprocess_html()` 添加 `member-page` body class（在模块中实现，避免修改当前未提交的 `xedc.theme`）。
- 通过 `hook_page_attachments()` 给 `/member*` 加 `noindex` meta。

### 8.5 主题改动

最小主题改动：

- `web/themes/custom/xedc/templates/includes/xedc-header.html.twig`
  - 登录后“我的账户”链接从 `user.page` 改为 `xedc_member.overview`。
  - 移动端侧边栏“我的账户”同样改为 `/member`。

不修改：

- `web/themes/custom/xedc/xedc.theme`（当前有未提交改动）
- `web/themes/custom/xedc/xedc.libraries.yml`（当前有未提交改动）
- 现有文章详情模板

会员中心 CSS 放在模块 `css/member.css`，复用主题全局已加载的 `--xa-*` 变量（`xedc_preprocess_html` 全局附加 `xedc/xedc_auth` 库），不需要运行主题构建。

### 8.6 配置与数据库

- 收藏、历史表通过 `xedc_member.install` 的 `hook_schema()` 创建。
- 权限通过 `xedc_member.permissions.yml` 声明，角色分配通过配置导出。
- 阶段 3 启用 `workflows`、`content_moderation`，需要数据库更新和配置导入。
- 在配置同步问题解决前，不执行 `drush cim`。
- 每个阶段结束用 `drush cex` 前，先确认目标目录并审查 diff。

---

## 9. PC / 移动端 UI 方案

### 9.1 PC

- 内容最大宽度约 `72rem`，与现有 `xa-container` 一致。
- 两栏：左侧 220–240px 导航，右侧自适应内容区。
- 左侧：
  - 用户卡片：头像、用户名、邮箱、注册时间。
  - 导航：概览、我的收藏、浏览历史、我的评论、我的投稿、账户设置。
  - 当前项使用浅灰背景、深色文字和左侧/底部强调线。
- 右侧：
  - 白色卡片，1px `#e4e4e7` 边框，8px 圆角，不使用重阴影。
  - 标题、说明、筛选条、列表、分页。
- 收藏/图集可使用 3 列卡片；视频/文章可使用 2 列或列表。
- 状态徽标：
  - 草稿：灰色
  - 待审核：琥珀色
  - 退回修改：橙色
  - 已拒绝：红色
  - 已发布：绿色
- 操作按钮使用现有 Bootstrap 5 风格或主题按钮，不引入新 UI 框架。

### 9.2 移动端

- 单列布局，左右 16px 内边距。
- 左侧导航改为：
  - 顶部横向可滚动标签，或
  - `<details>` 折叠菜单，或
  - 下拉选择。
- 用户卡片移到内容顶部，紧凑显示。
- 列表卡片全宽，封面比例 4:3 或 16:9。
- 操作按钮触控高度至少 44px。
- 筛选条横向滚动，不换行挤压。
- 分页可用 Drupal pager 或“加载更多”；优先保证可用性。
- 不使用仅 hover 才显示的操作。

### 9.3 页面结构

```text
[现有站点头部]
[会员中心容器]
  [用户卡片 / 左侧导航] [右侧内容]
    - 概览：统计数字 + 最近收藏 + 最近历史 + 最近投稿状态
    - 收藏：类型筛选 + 卡片列表 + 取消收藏
    - 历史：类型筛选 + 时间分组 + 删除单条 + 清空 + 关闭记录
    - 评论：状态筛选 + 评论摘要 + 父内容 + 时间 + 状态
    - 投稿：新建投稿 + 状态列表 + 编辑/重新提交 + 审核意见
    - 设置：资料、密码、历史记录开关
[现有站点底部]
```

---

## 10. 分阶段实施方案

### 阶段 0：现状审计与方案确认（当前阶段）

1. 目标和验收标准
   - 完成只读审计。
   - 确认 `gallery`/`photo`、评论范围、审核方案、文件隐私、角色方案、配置同步源。
   - 本阶段不写业务代码。
2. 预计新增文件
   - 无。
3. 预计修改文件
   - 无。
4. Drupal 变更
   - 无。
5. 数据库/配置
   - 无。
6. 测试
   - 仅只读检查；已确认无待执行数据库更新。
7. 风险与回滚
   - 无代码风险。
   - 配置同步不一致是后续最大风险，必须先解决。

进入阶段 1 的前置条件：

- 项目负责人确认本报告和关键决策。
- 备份数据库、文件、两套配置目录。
- 明确 `config/sync` 与实际同步目录的权威来源。
- 确认不覆盖当前未提交的文章详情和 `xa_views` 工作。

---

### 阶段 1：会员中心基础、账户概览、收藏

1. 目标和验收标准
   - `/member` 仅登录用户可访问；访客跳转登录并带 destination。
   - PC 左侧导航 + 右侧内容；移动端单列。
   - 账户概览显示用户名、邮箱、头像、注册时间、收藏/历史/投稿数量。
   - 收藏支持 article/photo/video；添加、取消、防重复、筛选、分页。
   - 两个会员账号之间收藏数据完全隔离。
   - 会员页面 noindex，缓存按用户隔离。
2. 预计新增文件
   - `xedc_member.info.yml`
   - `xedc_member.routing.yml`
   - `xedc_member.permissions.yml`
   - `xedc_member.services.yml`
   - `xedc_member.libraries.yml`
   - `xedc_member.module`
   - `xedc_member.install`
   - `config/install/xedc_member.settings.yml`
   - `config/schema/xedc_member.schema.yml`
   - `src/Controller/MemberController.php`
   - `src/Controller/FavoriteController.php`
   - `src/Service/FavoriteManager.php`
   - `src/Form/FavoriteForm.php`
   - `templates/xedc-member-shell.html.twig`
   - `templates/xedc-member-overview.html.twig`
   - `templates/xedc-member-favorites.html.twig`
   - `css/member.css`
   - `js/member.js`
3. 预计修改文件
   - `web/themes/custom/xedc/templates/includes/xedc-header.html.twig`：登录后入口改为 `/member`。
   - `config/sync/user.role.authenticated.yml`：增加 `access xedc member center`。
   - 可选：`config/sync/system.menu.account.yml` 增加会员中心菜单项。
4. Drupal 变更
   - 新路由：`/member`、`/member/favorites`、收藏添加/取消。
   - 新权限：`access xedc member center`。
   - 新服务：`xedc_member.favorite_manager`。
   - 新表单：收藏添加/取消。
   - 新表：`xedc_member_favorite`。
   - 不新增内容实体。
5. 数据库/配置
   - `drush en xedc_member` 创建表；如模块已启用则 `drush updb`。
   - 角色权限配置需导出；先解决配置同步问题。
   - 无内容配置导入。
6. 测试角色和边界
   - 匿名访问 `/member`、收藏 POST。
   - 会员 A 添加/取消/重复添加/分页/筛选。
   - 会员 A 不能查看或操作会员 B 的收藏。
   - 未发布、已删除、无访问权限内容。
   - CSRF 缺失/错误 token。
   - 标题 XSS。
   - 移动端布局和键盘操作。
7. 风险、依赖、回滚
   - 风险：配置同步错误、头部入口影响所有登录用户、缓存串用户。
   - 回滚：禁用模块、恢复角色配置和头部模板、备份/删除收藏表。
   - 依赖：无新贡献模块。

---

### 阶段 2：浏览历史、我的评论

1. 目标和验收标准
   - 登录会员访问 article/photo/video 详情页时记录历史；同一内容只保留一条，重复访问更新时间/次数。
   - 列表、teaser、AJAX、后台、预览不产生历史。
   - 支持类型筛选、删除单条、清空全部、关闭记录。
   - 跨设备可查看同一账号历史。
   - 我的评论显示正文摘要、父内容、时间、审核状态；只能看到自己的评论。
   - 评论审核策略确定并生效；待审核评论作者可见但不可公开访问。
2. 预计新增文件
   - `src/Controller/HistoryController.php`
   - `src/Controller/CommentController.php`
   - `src/Service/HistoryManager.php`
   - `src/Form/HistorySettingsForm.php`
   - `src/Form/HistoryDeleteForm.php`
   - `src/Form/HistoryClearForm.php`
   - `templates/xedc-member-history.html.twig`
   - `templates/xedc-member-comments.html.twig`
3. 预计修改文件
   - `xedc_member.module`：`hook_entity_view`、`hook_cron`、`hook_entity_delete`、`hook_user_cancel`、`hook_theme`、`hook_page_attachments`。
   - `xedc_member.routing.yml`
   - `xedc_member.services.yml`
   - `xedc_member.libraries.yml`
   - `xedc_member.install`：新增历史表 update hook。
   - `xedc_member.permissions.yml`
   - `config/install/xedc_member.settings.yml`：保留天数、节流时间。
   - `config/schema/xedc_member.schema.yml`
   - `templates/xedc-member-shell.html.twig`：增加导航项。
   - `css/member.css`、`js/member.js`
   - 评论策略相关：
     - `config/sync/user.role.authenticated.yml`
     - `config/sync/user.role.anonymous.yml`
     - `config/sync/user.role.content_editor.yml`
     - `config/sync/core.entity_form_display.node.article.default.yml`
     - `config/sync/core.entity_form_display.node.video.default.yml`
     - `config/sync/core.entity_view_display.node.article.default.yml`
     - `config/sync/core.entity_view_display.node.video.default.yml`
4. Drupal 变更
   - 新表：`xedc_member_history`。
   - 新服务：`xedc_member.history_manager`。
   - 新路由：`/member/history`、删除、清空、`/member/settings`、`/member/comments`。
   - 新表单：历史设置、删除、清空。
   - 评论：如决定覆盖 article/video，新增 `field_comment` 字段实例；如要求审核，移除 `skip comment approval`，给审核员 `administer comments`。
   - 新权限：可复用 `access xedc member center`；如需评论审核，使用核心 `administer comments`。
5. 数据库/配置
   - `drush updb` 创建历史表。
   - 评论字段/权限配置变更；配置导出。
   - 如果给 article/video 新增评论字段，现有节点评论状态需要初始化为合适值（建议开放或关闭由产品决定）。
   - 无全站内容导入。
6. 测试角色和边界
   - 会员 A/B 历史隔离；A 不能删除 B 的记录。
   - 同一节点重复访问只更新一条；5 分钟内节流。
   - 列表页、搜索页、AJAX、后台、预览不记录。
   - 删除节点、注销用户、保留期限清理。
   - 关闭记录后不再写入。
   - 评论：会员只能看到自己的评论；待审核评论作者可见；其他会员/匿名不可见；审核员可批准；父内容未发布时不泄露。
   - 评论正文 XSS、图片上传限制。
7. 风险、依赖、回滚
   - 风险：GET 请求写库、隐私/保留期限、评论审核改变现有行为、匿名评论策略。
   - 回滚：关闭历史写入、禁用模块、删除历史表；恢复评论权限和字段配置；备份评论数据。
   - 依赖：无新模块。

---

### 阶段 3：投稿表单、审核工作流、管理员审核、状态展示

1. 目标和验收标准
   - 普通会员可创建 article/photo/video 草稿，不能直接发布。
   - 会员可编辑自己的投稿，提交审核；退回后可修改并重新提交。
   - 审核员可批准、退回修改、拒绝；会员中心显示状态和审核意见。
   - 现有已发布内容不受影响；未发布内容按预期变为 draft。
   - 会员不能编辑他人内容、不能查看他人未发布内容、不能通过 POST 绕过审核。
   - 文件类型、大小、MIME 校验生效。
2. 预计新增文件
   - `src/Controller/SubmissionController.php`
   - `src/Service/SubmissionManager.php`
   - `src/EventSubscriber/SubmissionNotification.php`（或模块内 `hook_entity_update`）
   - `templates/xedc-member-submissions.html.twig`
   - `config/install/workflows.workflow.xedc_editorial.yml`
   - `config/install/field.storage.node.field_review_note.yml`
   - `config/install/field.field.node.article.field_review_note.yml`
   - `config/install/field.field.node.photo.field_review_note.yml`
   - `config/install/field.field.node.video.field_review_note.yml`
   - 可选：`config/install/views.view.xedc_member_submissions.yml`
3. 预计修改文件
   - `xedc_member.module`：`hook_form_node_form_alter`、`hook_entity_presave`、`hook_entity_field_access`、`hook_entity_update`、`hook_mail`、`hook_theme`。
   - `xedc_member.routing.yml`
   - `xedc_member.permissions.yml`
   - `xedc_member.services.yml`
   - `xedc_member.libraries.yml`
   - `templates/xedc-member-shell.html.twig`
   - `templates/xedc-member-submissions.html.twig`
   - `css/member.css`、`js/member.js`
   - `config/sync/user.role.authenticated.yml`
   - `config/sync/user.role.content_editor.yml`（或新审核角色）
   - `config/sync/user.role.anonymous.yml`（如评论策略变更）
   - `config/sync/core.entity_form_display.node.*.default.yml`
   - `config/sync/core.entity_view_display.node.*.default.yml`
   - `config/sync/metatag.metatag_defaults.user.yml`（noindex）
4. Drupal 变更
   - 启用 `workflows`、`content_moderation`。
   - 新建工作流 `xedc_editorial`，状态：draft、needs_review、changes_requested、rejected、published。
   - 应用工作流到 article、photo、video，不应用到 page。
   - `default_moderation_state: draft`。
   - 新增 `field_review_note`。
   - 新权限：各 transition 权限；会员仅 submit/resubmit/withdraw；审核员 approve/request_changes/reject/create_new_draft。
   - 会员内容权限：create/edit own/delete own + `view own unpublished content` + `view latest version`。
   - 审核员：`view any unpublished content`、`view latest version`、transition 权限、`administer comments`。
   - 表单改造：隐藏会员的 `uid`、`created`、`status`、`path`、`menu`、`promote`、`sticky`、`field_views`、`field_published_at`、`field_review_note` 编辑权。
   - 防御：`hook_entity_presave` 强制无发布权限会员的新内容为 draft/未发布；Content Moderation 负责转换校验。
   - 通知：状态变化时邮件通知作者/审核员；不做站内通知中心。
5. 数据库/配置
   - 备份数据库和两套配置目录。
   - `drush en workflows content_moderation`。
   - `drush updb`（Content Moderation 实体表）。
   - 配置导入 workflow、字段、角色、显示配置。
   - `drush cr`。
   - 现有 39 篇已发布 photo、11 篇 article、6 篇 video 保持 published；2 篇未发布 photo 变为 draft，需验证。
   - 如果阶段 2 没有处理评论字段，这里不要顺带修改，保持阶段边界。
6. 测试角色和边界
   - 会员创建草稿；无法直接发布；无法通过 POST `status=1` 或 `moderation_state=published` 绕过。
   - 会员 A 不能编辑/查看会员 B 的草稿、待审、退回内容。
   - 会员不能查看他人未发布内容。
   - 审核员批准/退回/拒绝；作者看到审核意见；`changes_requested` 可重新提交；`rejected` 按决策处理。
   - 修订版本生成；回滚到旧版本不破坏审核状态。
   - 现有内容前后对比。
   - 文件类型、MIME、大小、双扩展名、恶意文件。
   - 通知邮件只发给正确对象。
7. 风险、依赖、回滚
   - 风险最高阶段：Content Moderation 会改变节点表单、权限和修订行为；错误配置可能影响现有内容。
   - 回滚：数据库快照恢复；不要仅依赖卸载模块（可能丢审核数据）。
   - 依赖：核心 `workflows`、`content_moderation`；无新贡献模块。
   - 上线前必须在 staging 完整演练导入和回滚。

---

### 阶段 4：PC/移动端优化、权限与安全测试、上线准备

1. 目标和验收标准
   - 所有会员页面 PC/移动端可用，键盘可操作，空状态/错误状态完整。
   - 访客、会员 A、会员 B、审核员、管理员测试全部通过。
   - CSRF、XSS、越权、文件上传、缓存、noindex 检查通过。
   - 有上线/回滚步骤和验收记录。
2. 预计新增文件
   - `tests/src/Functional/MemberCenterTest.php`
   - `tests/src/Functional/FavoriteIsolationTest.php`
   - `tests/src/Functional/HistoryTest.php`
   - `tests/src/Functional/SubmissionWorkflowTest.php`
   - `tests/src/Functional/CommentModerationTest.php`
3. 预计修改文件
   - 会员相关 Twig/CSS/JS 的最后修正。
   - `config/sync/metatag.metatag_defaults.user.yml`：用户页 noindex。
   - 如需，补充 `xedc_member` 的 noindex/缓存配置。
4. Drupal 变更
   - 不新增业务功能。
   - 主要补充 noindex、缓存策略、可访问性和测试。
5. 数据库/配置
   - 原则上无数据库变更。
   - 配置修改需导出并审查。
6. 测试角色和边界
   - 完整执行第 11 节测试清单。
   - 至少两个普通会员账号的数据隔离。
   - 真实移动端或响应式模拟。
   - 回归现有登录/注册/找回密码、文章详情、视频详情、美图详情、评论。
7. 风险、依赖、回滚
   - 风险：安全回归、缓存串用户、SEO 误索引。
   - 回滚：恢复配置快照、关闭新功能入口、保留数据表。
   - 依赖：Drupal 核心测试框架；测试数据库不得指向生产。

---

## 11. 安全和测试标准

### 11.1 角色与访问

必须覆盖：

- 匿名用户
- 普通会员 A
- 普通会员 B
- 内容编辑/审核员
- 管理员

测试点：

- 匿名访问 `/member` 全部页面 → 跳转登录或 403。
- 匿名调用收藏/历史/投稿 POST → 403，不产生数据。
- 会员 A 不能通过修改 URL 中的 UID/NID 操作用户 B 的数据。
- 会员 A 不能查看用户 B 的收藏、历史、评论、投稿。
- 会员不能访问 `/admin/*`、`/admin/content/moderated`。
- 会员不能查看他人未发布内容。
- 会员不能编辑/删除他人内容。
- 管理员/审核员权限符合预期。

### 11.2 收藏与历史

- 重复添加收藏不产生重复记录。
- 重复访问同一内容只更新一条历史。
- 分页、类型筛选、空状态正常。
- 删除单条、清空全部只影响当前用户。
- 删除节点后收藏/历史清理。
- 取消发布内容从列表隐藏；重新发布后恢复。
- 缓存不串用户；会员页面 noindex。
- 未登录不记录历史。
- 关闭记录后不再写入。
- 保留期限清理只删除过期记录。

### 11.3 评论

- 评论审核权限正确：审核员可批准，普通会员不可。
- 待审核评论只有作者和审核员可见。
- 作者只能看到自己的评论。
- 未发布父内容的评论不泄露标题/正文。
- 评论正文 XSS 被过滤。
- 评论图片类型/大小校验。
- 编辑已发布评论后是否重新审核，按最终产品决策测试。
- 删除评论只允许管理员/审核员。

### 11.4 投稿与审核

- 会员只能创建允许的类型。
- 会员不能直接发布；隐藏 status 不够，必须有 presave/工作流防御。
- 会员不能通过 POST 修改 `status`、`moderation_state`、`uid`、`created`。
- 会员不能编辑/查看他人未发布内容。
- 审核员批准/退回/拒绝正确。
- 退回后作者可编辑并重新提交。
- 拒绝终态或可重开，按最终决策测试。
- 修订版本保留；审核意见正确显示。
- 现有已发布内容在启用工作流后仍发布。
- 通知只发送给正确用户。

### 11.5 文件上传

- 扩展名白名单：图片 `png gif jpg jpeg webp`，视频 `mp4`。
- MIME 与实际内容校验，不只信任扩展名。
- 拒绝 SVG、HTML、PHP、双扩展名、伪装图片。
- 图片尺寸/解压炸弹限制。
- 视频大小限制、MIME 校验。
- 文件名清理，避免路径穿越。
- 上传目录不可执行脚本。
- 未审核文件访问策略明确：
  - 推荐私有文件系统；
  - 如使用 public，必须记录残余风险，不能声称未审核文件安全。
- 会员不能创建 document/audio 等不需要的媒体类型。
- 服务器 Nginx/上传目录实际访问规则待检查。

### 11.6 CSRF、XSS、输入验证

- 所有写操作使用 POST + Form API token 或 `_csrf_token` / `_csrf_request_header_token`。
- 收藏/历史 AJAX 端点不接受 GET 写操作。
- 所有用户输入经 Twig 自动转义或 `check_markup()`。
- 标题、分类名、标签名、审核意见、评论正文、URL 都测试 XSS payload。
- 外链视频只允许白名单 provider；不允许任意 iframe/JS URL。
- 分页、筛选参数做类型和范围校验。
- 数据库查询使用 DB API 占位符，不拼接 SQL。

### 11.7 缓存与 SEO

- 会员页面按用户隔离缓存，不能出现 A 看到 B 数据。
- 会员页面 `noindex, nofollow, noarchive`。
- 用户资料页也建议 noindex（当前 `metatag.metatag_defaults.user.yml` 没有 robots 配置）。
- 会员页面不被 page cache / dynamic page cache 错误缓存。
- 收藏/历史写操作后相关缓存失效。
- Matomo 对 `/member*` 的处理明确：排除或尊重 opt-out。

### 11.8 不引入不必要依赖

- 收藏/历史不引入 Flag/Profile/Message。
- 评论复用核心 Comment。
- 审核复用核心 Content Moderation/Workflows。
- 列表复用核心 Views 或自定义查询。
- 不新增前端框架；复用 Bootstrap 5 / 现有设计变量。
- 如确需 2FA、验证码、私有文件模块，单独评估，不在阶段 1–2 顺手引入。

---

## 12. 需要项目负责人决定的问题

| # | 问题 | 建议默认 |
|---|---|---|
| 1 | `gallery` 是否就是现有 `photo`？ | 复用 `photo`，UI 文案称“图集/美图”；不新建 `gallery` 类型 |
| 2 | 评论是否要覆盖 article/video？ | 如果要完整“我的评论”，建议给 article/video 增加评论字段；否则阶段 2 只覆盖 photo |
| 3 | 是否保留匿名评论？ | 建议要求登录后评论，降低审核和归属复杂度；如保留匿名，则匿名评论也需审核 |
| 4 | 是否启用评论审核？ | 建议移除 `skip comment approval`，给审核员 `administer comments` |
| 5 | 投稿审核用 Content Moderation 还是自定义字段？ | 建议 Content Moderation；它解决默认发布和转换权限校验问题 |
| 6 | 审核员用 `content_editor` 还是新角色？ | 如需最小权限，新建 `reviewer`；否则复用 `content_editor` |
| 7 | 会员角色用 `authenticated` 还是新“member”角色？ | 用 `authenticated` 作为会员，减少额外角色分配 |
| 8 | 拒绝是终态还是允许重开？ | 建议终态，会员可新建投稿；如要允许修改后重提，增加 `rejected → draft` |
| 9 | 会员上传文件是否必须私有？ | 建议私有文件系统；如无法调整服务器，则明确接受 public 残余风险并加大小/类型限制 |
| 10 | 上传大小限制 | 建议图片 ≤ 10MB、视频 ≤ 200MB，或视频优先只允许外部 URL；最终按服务器能力定 |
| 11 | 历史保留期限和关闭记录行为 | 建议 180 天；关闭后停止记录，已有记录保留到用户清空/到期 |
| 12 | 是否需要站内通知？ | 建议阶段 3 只做邮件通知，不做站内通知中心 |
| 13 | 是否需要 2FA、邮箱验证、验证码？ | 当前无；建议至少评估“邮箱变更验证”和投稿频率限制，2FA 单独立项 |
| 14 | 配置同步以哪个目录为准？ | 建议以 `/var/www/drupal/config/sync` 为项目源，但先备份并导出/比对实际 DB 配置 |
| 15 | 是否允许会员编辑已发布内容？ | 建议允许编辑但生成待审修订，不直接影响线上版本；或禁止，按产品定 |

---

## 13. 主要风险清单

1. 配置同步不一致：实际同步目录不是 `config/sync`，且数据库有未导出配置；直接 `cim` 可能回退未提交功能。
2. `gallery` 命名不一致：需求写 gallery，实际是 photo；新增类型会产生迁移成本。
3. 评论范围不足：article/video 没有评论字段；“我的评论”目前只能覆盖 photo。
4. 评论审核缺失：所有角色可跳过审核，现有评论全部已发布。
5. 节点默认发布：隐藏 status 字段不能让新节点自动未发布；必须用 Content Moderation 或 presave 强制。
6. 文件公开：媒体/文件全部 public，未审核文件可能通过 URL 访问；无私有文件路径。服务器实际访问规则待检查。
7. 上传无限制：图片、视频、头像无大小上限；需要限制类型、MIME、大小。
8. 媒体库权限：给会员创建媒体权限会扩大可上传范围和媒体浏览范围；建议自定义表单或严格限制。
9. Content Moderation 上线风险：启用会改变表单、权限、修订和数据库；需要 staging 演练和备份。
10. `content_editor` 权限过大：拥有 `bypass node access`、`administer nodes`，不适合作为最小权限审核员。
11. 匿名评论与开放注册：可能带来垃圾评论/垃圾投稿；当前无验证码、无邮箱验证。
12. 缓存串用户：会员页面必须按用户隔离；否则 A 可能看到 B 的收藏/历史。
13. SEO：用户页当前没有 noindex；会员页必须 noindex。
14. Matomo 隐私：会员页面行为可能被分析平台记录，需要排除或尊重 opt-out。
15. 现有 `xa_views` 安全：`xa_views.hit` 路由为 POST 且 `_access: TRUE`，没有 CSRF；当前模块启用但未导出配置。虽不属于会员中心，但属于现有风险，不应复制该模式。
16. 现有 `xedc_quick` 运行时建表：上传/创建时动态创建 `xedc_quick_hash`、`xedc_quick_orig` 表；不建议在会员中心复用这种模式。实际表是否存在待检查。
17. 文章分类配置不一致：`article.field_categories` 的 `auto_create_bundle` 指向 `photo_category`，但目标 bundle 只有 `article_category`，可能造成自动创建 validation 问题。
18. 未提交工作覆盖风险：`xedc.theme`、`xedc.libraries.yml`、`xa_views`、文章详情模板/JS/CSS 必须保留；阶段实施时避免改动这些文件。

---

## 14. 结论与停止点

- 本阶段只完成审计和方案设计，没有修改任何生产文件、配置或数据库。
- 推荐的最小架构是：新增 `xedc_member` 模块，使用自定义表保存收藏/历史，复用核心 Comment、Content Moderation、Workflows、Views、Form API；主题只做最小入口修改。
- 阶段 1 开始前必须先完成：
  1. 确认 `gallery = photo`；
  2. 确认评论范围和审核策略；
  3. 确认是否启用 Content Moderation；
  4. 确认文件私有/公开取舍；
  5. 解决配置同步源问题并备份。
- 本阶段到此停止，等待项目负责人审阅并明确批准后，才进入阶段 1。
