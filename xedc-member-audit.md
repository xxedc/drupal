# XEDC 会员中心只读审计

审计范围：Drupal 11 会员中心及相关登录、资料、收藏、浏览历史、评论、投稿。只读源码与 `config/sync`，未执行 drush，未改代码，未对照运行中的数据库。导出配置与库内实际权限可能不一致。

**版本：** Drupal **11.4.11**（`composer.json` 的 `drupal/core-recommended`，`composer.lock` 的 `drupal/core`）。默认主题 `xedc`，管理主题 `default_admin`（`config/sync/system.theme.yml`）。自定义模块只在 `web/modules/custom/`：`xedc_member`、`xa_views`、`xedc_models`、`xedc_quick`、`xedc_tags`。`xedc_member` 没有 `.permissions.yml`。

`config/sync/core.extension.yml` 中列出的模块均为已安装模块；其中的数字是权重，不是启用开关。

## 1. 现有会员功能清单

| 功能 | 负责模块 | 路由名 | 主要文件 |
|---|---|---|---|
| 会员中心概览 `/member` | `xedc_member` | `xedc_member.overview` | `MemberController::overview`，`templates/xedc-member-shell.html.twig`，`templates/xedc-member-overview.html.twig` |
| 我的收藏 `/member/favorites` | `xedc_member` | `xedc_member.favorites` | `FavoriteManager`，`FavoriteToggleForm`，`templates/xedc-member-favorites.html.twig`，`templates/xedc-member-card.html.twig` |
| 详情页收藏按钮 | `xedc_member` + 主题 | 无独立路由（表单 POST） | `xedc_member_preprocess_node()`；`node--photo--full.html.twig`、`node--video--full.html.twig`、`node--article--full.html.twig` |
| 浏览历史 `/member/history` | `xedc_member` | `xedc_member.history` | `HistorySubscriber`，`HistoryManager`，`HistoryDeleteForm`，`templates/xedc-member-history.html.twig` |
| 清空历史 `/member/history/clear` | `xedc_member` | `xedc_member.history_clear` | `HistoryClearForm` |
| 历史开关（账号设置内） | `xedc_member` | 挂在 `xedc_member.settings` | `HistorySettingsForm`；偏好存在 `users_data`，键 `xedc_member` / `history_enabled` |
| 我的评论 `/member/comments` | `xedc_member` + 核心 `comment` | `xedc_member.comments` | `MemberController::comments()`；编辑走 `entity.comment.edit_form` |
| 我的投稿 `/member/submissions` | `xedc_member` + `content_moderation` | `xedc_member.submissions` | `MemberController::submissions()`；新建走 `node.add`（`photo` / `video` / `article`） |
| 个人资料 `/member/profile` | `xedc_member` | `xedc_member.profile` | `ProfileForm`；字段 `field_xedc_nickname`、`field_xedc_bio`、核心 `user_picture` |
| 账户安全 `/member/security` | `xedc_member` + 核心 `user` | `xedc_member.security` | 嵌入 `entityFormBuilder()->getForm($account, 'default')`；`xedc_member_form_user_form_alter()` |
| 账号设置 `/member/settings` | `xedc_member` | `xedc_member.settings` | `templates/xedc-member-settings.html.twig` |
| 顶栏入口 | `xedc_member` + 主题 | — | `xedc_member_preprocess_page()` 写入 `member_center_url`；`templates/includes/xedc-header.html.twig` |
| 登录 | 核心 `user` + 主题 | `user.login` | `web/themes/custom/xedc/includes/auth.inc` 的 `xedc_form_user_login_form_alter()`；`js/auth.js` 弹窗 |
| 注册 | 核心 `user` + `user_registrationpassword` + 主题 | `user.register` | `xedc_form_user_register_form_alter()`；`config/sync/user_registrationpassword.settings.yml`（`registration: with-pass`） |
| 找回 / 重置密码 | 核心 `user` + 主题 | `user.pass`、`user.reset`、带 `pass-reset-token` 的 `entity.user.edit_form` | `xedc_form_user_pass_alter()`、`xedc_form_user_pass_reset_alter()`、`xedc_form_user_form_alter()` |
| 退出 | 核心 `user` | `user.logout` | 顶栏 `path('user.logout')`；侧栏 `urls.logout`；`js/usermenu.js` 给退出链接补 `destination` |
| 评论发表与审核策略 | 核心 `comment` + `xedc_member` + 主题 | 核心评论路由 | 评论字段仅 `config/sync/field.field.node.photo.field_comment.yml`；`xedc_member_apply_comment_moderation_policy()`；`xedc_form_comment_form_alter()` |
| 投稿审核流 | `workflows` + `content_moderation`，由 `xedc_member` 安装 | `node.add`、`entity.node.edit_form`、管理端 `moderated_content` | `config/sync/workflows.workflow.xedc_editorial.yml` |
| 站内通知 | 无 | 无 | 未找到通知模块或路由。邮件只有 `smtp` / `mailsystem` |

路由一律 `_user_is_logged_in: 'TRUE'`，并设 `no_cache: TRUE`。导航不是菜单链接，而是 `MemberController::shell()` 里写死的 8 项。

库：`xedc_member.libraries.yml` 的 `xedc_member/member`（`css/member.css`、`js/member.js`，依赖 `core/drupal`、`core/drupal.ajax`）。

服务（`xedc_member.services.yml`）：

- `xedc_member.favorite_manager` → `FavoriteManager`
- `xedc_member.history_manager` → `HistoryManager`
- `xedc_member.history_subscriber` → `HistorySubscriber`（`KernelEvents::REQUEST`）

存储：

- 表 `xedc_member_favorite`：`uid + entity_type + entity_id` 唯一；字段 `fid, uid, entity_type, entity_id, bundle, created`
- 表 `xedc_member_history`：同样唯一键；字段 `hid, uid, entity_type, entity_id, bundle, first_viewed, last_viewed, view_count`
- 历史开关：`users_data`，模块 `xedc_member`，键 `history_enabled`；默认开启；同内容 60 秒节流；cron 删除 180 天前记录

### 路由证据

`web/modules/custom/xedc_member/xedc_member.routing.yml`：

```yaml
xedc_member.overview:
  path: '/member'
  defaults:
    _controller: '\Drupal\xedc_member\Controller\MemberController::overview'
    _title: '会员中心'
  requirements:
    _user_is_logged_in: 'TRUE'
  options:
    no_cache: TRUE
```

同文件还有：`xedc_member.favorites`（`/member/favorites`）、`xedc_member.history`（`/member/history`）、`xedc_member.history_clear`（`/member/history/clear`）、`xedc_member.comments`（`/member/comments`）、`xedc_member.submissions`（`/member/submissions`）、`xedc_member.settings`（`/member/settings`）、`xedc_member.profile`（`/member/profile`）、`xedc_member.security`（`/member/security`）。要求与缓存选项与概览相同。

### 控制器与壳层

`MemberController::shell()` 写死导航，并关闭缓存：

```php
$nav = [
  ['key' => 'overview', 'label' => $this->t('概览'), 'url' => $urls['overview']],
  ['key' => 'favorites', 'label' => $this->t('我的收藏'), 'url' => $urls['favorites']],
  ['key' => 'history', 'label' => $this->t('浏览历史'), 'url' => $urls['history']],
  ['key' => 'comments', 'label' => $this->t('我的评论'), 'url' => $urls['comments']],
  ['key' => 'submissions', 'label' => $this->t('我的投稿'), 'url' => $urls['submissions']],
  ['key' => 'profile', 'label' => $this->t('个人资料'), 'url' => $urls['profile']],
  ['key' => 'security', 'label' => $this->t('账户安全'), 'url' => $urls['security']],
  ['key' => 'settings', 'label' => $this->t('账号设置'), 'url' => $urls['settings']],
];
// ...
'#cache' => [
  'contexts' => ['user'],
  'max-age' => 0,
],
```

账户安全嵌入核心用户表单：

```php
'#form' => $this->entityFormBuilder()->getForm($account, 'default'),
```

`xedc_member_form_user_form_alter()` 仅在路由 `xedc_member.security` 时隐藏用户名、时区、语言、头像、角色和删除按钮，提交后 `xedc_member_user_form_redirect()` 回到 `xedc_member.security`。

### 收藏与历史

`FavoriteManager::ALLOWED_BUNDLES` 与 `HistoryManager::ALLOWED_BUNDLES` 均为 `photo`、`video`、`article`，且只接受已发布节点。

收藏写入 `xedc_member_favorite`，唯一键冲突时保持原收藏时间。历史用 `merge` 更新 `last_viewed` 并 `view_count + 1`。`HistorySubscriber::onRequest()` 仅在主请求、GET、非 Ajax、无 `_wrapper_format` / `_format`、路由 `entity.node.canonical`、已登录、节点可查看时调用 `HistoryManager::record()`。

详情页收藏：`xedc_member_preprocess_node()` 在 `full` 视图、允许的 bundle、已发布时，已登录用户输出 `FavoriteToggleForm`，匿名用户输出指向 `user.login` 且带 `destination` 的链接。

### 登录、注册、密码、退出

`xedc.theme` 第 353 行 `require_once __DIR__ . '/includes/auth.inc'`。`xedc_preprocess_html()` 在非搜索页挂载库 `xedc/xedc_auth`。

- 无 `destination` 的普通登录：`_xedc_auth_login_submit()` 回首页。
- 带 `xedc_embed=1` 的弹窗登录：去掉 `destination`，跳 `robots.txt?xedc_done=1`，父窗口 `auth.js` 的 `goBack()` 回到原页面，并拒绝跨源。
- `auth.js` 的 `embedUrl()`：链接上没有 `destination` 时写入当前 path + search + hash。
- 注册：`user.settings.yml` 为 `register: visitors`、`verify_mail: false`；`user_registrationpassword.settings.yml` 为 `registration: with-pass`。有 `destination` 则交给核心；否则未登录回 `user.login`，已登录且目标是用户主页则回首页。
- 密码规则：`_xedc_auth_validate_password()` 要求至少 8 位且同时包含字母和数字。
- 顶栏退出：`xedc-header.html.twig` 的 `path('user.logout')`。`usermenu.js` 在非 `/user` 路径点击退出时追加 `destination`。
- 会员中心退出：`MemberController::memberUrls()` 的 `Url::fromRoute('user.logout')`。

### 缓存、权限、CSRF

- 会员路由：`_user_is_logged_in` + `no_cache: TRUE`。
- 壳层与各表单：`#cache` 上下文 `user`，`max-age` 0。
- `xedc_member_preprocess_page()` 增加上下文 `user.roles:authenticated`。
- `xedc_member_preprocess_html()` 在会员路由增加上下文 `route`。
- 收藏、删历史、清空历史、资料、历史开关都是 Form API，自带 `form_token`。清空历史是 `ConfirmFormBase`。
- 写库使用当前用户 ID。收藏与历史删除都带 `uid` 条件。
- 会员页 `xedc_member_page_attachments_alter()` 输出 `noindex, nofollow, noarchive`，同样覆盖 `user.page`、`user.edit`、`entity.user.canonical`、`entity.user.edit_form`。

## 2. 重复功能与可整合点

会员业务已经集中在 `xedc_member`，不要再拆新模块。可收的是死代码和三套「浏览计数」，它们数据含义不同，不能并表。

| 点 | 证据 | 建议 |
|---|---|---|
| 占位页已无路由 | `MemberController::placeholder()` 与 `xedc-member-placeholder.html.twig` 仍在；`xedc_member.routing.yml` 的评论/投稿已指向真实方法 | 下一阶段删占位实现 |
| 两套用户表单 alter | 主题 `xedc_form_user_form_alter()`（`includes/auth.inc`）管重置密码；模块 `xedc_member_form_user_form_alter()` 只在路由 `xedc_member.security` 裁剪核心账户表单 | 保留两边，不要合成一个函数 |
| 两个 `hook_preprocess_html` | 主题 `xedc_preprocess_html()` 挂 `xedc/xedc_auth`；模块 `xedc_member_preprocess_html()` 给 `xedc_member.*` 加 `xm-page` | 保留 |
| 核心 `editorial` 与 `xedc_editorial` 并存 | `config/sync/workflows.workflow.editorial.yml` 与 `workflows.workflow.xedc_editorial.yml`；`xedc_member_update_moderated_content_view()` 两套状态都写进 `moderated_content` 视图 | 前台只用 `xedc_editorial`。核心 `editorial` 未绑到美图/视频/文章前不要删 |
| 三套计数 | `statistics`：全站 `node_counter`，图库按 `totalcount` 排序。`xa_views`：`POST /xa/hit/{nid}` 只加文章字段 `field_views`。`xedc_member_history`：登录用户自己的浏览记录 | 不要合并。会员历史只保留第三套 |
| 评论只挂在美图 | `config/sync` 里只有 `field.field.node.photo.field_comment.yml`，文章/视频没有评论字段 | 会员「我的评论」仍按 `comment.uid` 列全部评论；没有第二套评论系统 |
| 顶栏退出与侧栏退出 | 顶栏 Twig `path('user.logout')`；侧栏控制器 `Url::fromRoute('user.logout')` | 都走核心路由，保留一处生成方式即可 |

`user_registrationpassword` 与主题注册表单是同一条注册链路，不是两套账号系统。`config/sync/user.settings.yml` 为 `register: visitors`、`verify_mail: false`，注册即活跃；模块配置 `registration: with-pass`，注册页自填密码。

`xa_views` 路由 `xa_views.hit`，路径 `/xa/hit/{nid}`，要求 `_access: 'TRUE'`，只处理已发布 `article`，用 flood 按 IP 30 分钟去重后更新 `node__field_views`。这与会员历史无关。

## 3. 必须保留的依赖

`xedc_member.info.yml` 声明：`node`、`user`、`comment`、`content_moderation`、`field`、`workflows`、`file`、`image`、`media`。

另外这些不能卸：

- **角色与权限配置：** `user.role.authenticated`、`user.role.content_editor`、`user.role.anonymous`
- **工作流配置：** `workflows.workflow.xedc_editorial`（状态：草稿、待审核、退回修改、已拒绝、已发布；会员过渡：`save_draft`、`submit_for_review`、`resubmit_for_review`、`withdraw`；编辑过渡：`approve`、`request_changes`、`reject`、`create_new_draft`）
- **用户字段：** `field_xedc_nickname`（string，64）、`field_xedc_bio`（string_long）、核心 `user_picture`。表单显示里这两个自定义字段是隐藏的（`core.entity_form_display.user.user.default.yml` 的 `hidden`），只在 `ProfileForm` 里编辑
- **主题登录链：** `includes/auth.inc`（由 `xedc.theme` 第 353 行 `require_once`）、`css/auth.css`、`js/auth.js`、`js/usermenu.js`、库 `xedc/xedc_auth`
- **注册模块：** `user_registrationpassword`
- **邮件：** `smtp`、`mailsystem`（重置密码、注册通知）
- **数据表：** `xedc_member_favorite`、`xedc_member_history`，以及 `users_data` 里的 `history_enabled`
- **媒体限制（已在配置中）：** 图片 `10 MB`、视频 `200 MB`（`field.field.media.image.field_media_image.yml`、`field.field.media.video.field_media_video_file.yml`）

`statistics` 和 `xa_views` 要留给前台阅读量，不属于会员中心依赖。

已登录用户投稿相关权限（`config/sync/user.role.authenticated.yml`）包括：创建/编辑/删除自己的 `article`、`photo`、`video`；创建/编辑/删除自己的 `image`、`video` 媒体；`view own unpublished content`；`view latest version`；`post comments`；`edit own comments`；`skip comment approval`；以及 `use xedc_editorial transition` 的 `save_draft`、`submit_for_review`、`resubmit_for_review`、`withdraw`。

`content_editor` 拥有审核过渡 `approve`、`request_changes`、`reject`、`create_new_draft`，以及 `administer comments`、`administer nodes`、`bypass node access`、`view any unpublished content`。

## 4. 数据与权限风险点

**1. 评论免审权限：代码与导出配置相反**

`xedc_member_apply_comment_moderation_policy()` 会从 `anonymous` 和 `authenticated` 撤销 `skip comment approval`。但 `config/sync/user.role.authenticated.yml` 第 52 行仍有该权限。匿名角色配置里没有这条。未查数据库，不知道线上是否已撤销。执行配置导入会把免审权限加回已登录用户，评论会立即公开。

**2. `view latest version` 发给了全部已登录用户**

`user.role.authenticated.yml` 含 `view latest version`。在内容审核里，该权限允许查看非默认的最新修订。已登录用户只要知道 `/node/{nid}/latest`，就可能看到别人尚未发布的草稿。会员看自己的投稿不需要把这个权限给所有人。

**3. 每个已登录用户都是投稿人**

`authenticated` 拥有美图/视频/文章的 `create`、`edit own`、`delete own`，以及图片/视频媒体的对应权限，外加四条会员过渡。没有单独的「投稿者」角色。已发布内容也可以被作者直接删除。

**4. 编辑链接不检查 `update` 访问**

`MemberController::submissionCard()` 始终生成 `entity.node.edit_form`：

```php
$edit_url = Url::fromRoute('entity.node.edit_form', ['node' => $node->id()], [
  'query' => ['destination' => Url::fromRoute('xedc_member.submissions')->toString()],
])->toString();
```

待审核节点是否真能改，取决于内容审核对当前状态的访问结果，控制器没有调用 `$node->access('update')`。

**5. 评论查询关闭了实体访问检查**

`commentCount()` 和 `comments()` 使用 `accessCheck(FALSE)`，只按当前用户 `uid` 过滤。作者能看到自己待审评论的正文，这是预期。父节点不可查看时标题会改成「内容不可用或已下架」，但评论正文仍渲染。没有跨用户泄露。

**6. 概览投稿数与列表计数不一致**

`submissionCount()` 使用 `accessCheck(FALSE)`，列表 `submissions()` 使用 `accessCheck(TRUE)`。当前没有额外的 node access 模块，且已登录用户有 `view own unpublished content`，两边大体一致。以后若加访问模块，概览数字会偏大。

**7. 退出链接的 CSRF**

`user.logout` 需要 `_csrf_token`。会员中心页面 `max-age: 0` 且 `no_cache: TRUE`，侧栏 `Url::fromRoute('user.logout')` 每次现算，风险低。顶栏在可缓存页面里用 Twig `path('user.logout')`，令牌是按会话生成的。若页面只按 `user.roles:authenticated` 缓存（`xedc_member_preprocess_page()` 加的就是这个上下文），其他用户会拿到别人的退出令牌，退出失败或误伤会话。`usermenu.js` 只追加 `destination`，不重新签发令牌。

**8. 返回原页面**

- 未登录收藏：`Url::fromRoute('user.login', [], ['query' => ['destination' => 当前 URI]])`
- `auth.js` 的 `embedUrl()`：没有 `destination` 时写入当前 path + search + hash，并加 `xedc_embed=1`
- 弹窗登录成功：`_xedc_auth_login_submit()` 去掉 `destination`，改跳 `robots.txt?xedc_done=1`，父窗口 `goBack()` 回 `pendingDest`，并拒绝跨源
- 无 `destination` 的普通登录：回首页
- 注册：有 `destination` 则交给核心；否则未登录回 `user.login`，已登录且目标是用户主页则回首页
- 评论编辑取消：`xedc_form_comment_form_alter()` 只接受以 `/` 开头且不是 `//` 的 `destination`

**9. 表单 CSRF**

收藏、删历史、清空历史、资料、历史开关都是 Form API，自带 `form_token`。清空历史是 `ConfirmFormBase`。提交时用当前用户 ID 写库，不能改别人的收藏或历史。

**10. 历史写入在动态页面缓存之后仍会执行**

`HistorySubscriber` 优先级为 0，主请求、GET、非 Ajax、路由 `entity.node.canonical`、已发布且 `access('view')` 才写入。动态页面缓存命中时请求订阅者仍会跑，所以登录用户每次打开详情都会打 `xedc_member_history`。有 60 秒节流。

**11. 审核角色过宽**

`content_editor` 同时有 `administer nodes`、`bypass node access`、`administer comments`、`administer content types`。节点表单 alter 遇到 `administer nodes` 会直接返回，不隐藏作者、路径、发布选项。这是后台编辑角色，不是普通会员。

**12. 头像**

`ProfileForm` 上传到 `public://pictures/`，限制扩展名、2MB、`FileIsImage`，保存前 `strip_tags`。文件归属依赖核心 `managed_file`，模块没有再查文件属主。

**13. 无站内通知**

审核结果只出现在投稿卡片的 `revision_log`（仅 `changes_requested`、`rejected`）。没有通知实体、没有未读数。

## 5. 建议的最终架构（xedc_member）

继续用现有模块，不新建模块。目录保持：

```text
web/modules/custom/xedc_member/
  xedc_member.info.yml
  xedc_member.routing.yml
  xedc_member.services.yml
  xedc_member.libraries.yml
  xedc_member.module
  xedc_member.install
  src/Controller/MemberController.php
  src/Form/
  src/Service/FavoriteManager.php
  src/Service/HistoryManager.php
  src/EventSubscriber/HistorySubscriber.php
  templates/
  css/member.css
  js/member.js
```

登录注册留在主题 `includes/auth.inc`，不要迁进模块。

**迁移顺序（只整理，不换存储）：**

1. 先对齐权限配置：从 `authenticated` 去掉 `skip comment approval` 和面向全站的 `view latest version`，并确认与数据库一致。这一步会改变线上行为，需要单独确认。
2. 投稿卡片按 `$node->access('update')` 决定是否输出编辑链接。
3. 概览计数与列表使用同一套 `accessCheck`。
4. 顶栏退出改成带会话上下文或懒生成的 CSRF 链接。
5. 删除 `placeholder()` 和占位模板。
6. 样式收到主题色变量上（见第 6 节）。不要改表结构。

**必须保留的存储：**

- `xedc_member_favorite`
- `xedc_member_history`
- `users_data` 的 `xedc_member.history_enabled`
- 用户字段 `field_xedc_nickname`、`field_xedc_bio`、`user_picture`
- 工作流 `xedc_editorial` 及现有状态机
- 评论实体（核心 `comment`，目前只挂美图）
- 节点修订日志 `revision_log`（审核意见）
- `statistics` 的 `node_counter` 与文章字段 `field_views`（前台阅读量，不是会员历史）

## 6. 主题风格适配建议

主题色在 `web/themes/custom/xedc/src/scss/base/_variables.scss`：主色 `#18181b`，正文同色，边框 `#e4e4e7`，背景 `#fff`，按钮圆角 `.5rem`，卡片圆角 `.75rem`、内边距 `1.5rem`。导航令牌在 `css/xedc-navbar.css` 的 `--xn-*`，暗色由 `[data-theme=dark]` 切换。登录令牌在 `css/auth.css` 的 `--xa-*`，`:root` 为浅色，暗色选择器同时覆盖 `.dark`、`[data-theme=dark]`、`[data-bs-theme=dark]`。

会员中心样式在模块 `css/member.css`，不走主题 SCSS。它读取 `--xa-*`，并带浅色回退值。非搜索页会通过 `xedc_preprocess_html()` 加载 `xedc/xedc_auth`，所以会员页一般能接到这套变量，暗色主背景能跟着变。

差异：

- 按钮是自定义 `.xm-btn`（高 38px、圆角 8px），不是 Bootstrap `.btn`，也不是导航 `.xn-btn`。主按钮行为接近导航：实底、悬停 `opacity: .9`。
- 卡片 `.xm-card` 圆角 12px、边框 1px，悬停阴影写死 `rgba(0, 0, 0, .06)`，暗色下阴影偏浅。
- 危险按钮、历史删除按钮、状态消息用了固定浅色（`#fecaca`、`#fef2f2`、`#f0fdf4`），暗色下不会跟着 `--xa-danger` / `--xa-ok` 变。
- 侧栏 232px + 间距 28px，独立于 Bootstrap 栅格和主题 `$card-spacer-*`。
- 收藏按钮是胶囊形（`border-radius: 999px`），和卡片按钮的 8px 圆角不是同一套。
- 布局和信息架构已经对齐（左导航、统计、卡片网格），差在令牌没有收口。

适配时只改 `member.css`：危险色和消息色改用 `auth.css` 已有的 `--xa-danger`、`--xa-ok`、`--xa-warn`；阴影和边框改用 `--xa-border`。不必把会员页重做成 Bootstrap card。登录弹窗、顶栏继续用现有 `auth.css` / `xedc-navbar.css`。

## 已启用模块（来自 config/sync/core.extension.yml）

自定义：`xa_views`、`xedc_member`、`xedc_models`、`xedc_quick`、`xedc_tags`。

与会员直接相关的贡献/核心模块：`user`、`comment`、`content_moderation`、`workflows`、`user_registrationpassword`、`file`、`image`、`media`、`smtp`、`mailsystem`、`statistics`。

其余已安装模块（核心与贡献，含 audit、colorbox、easy_breadcrumb、metatag、pathauto、redirect、simple_sitemap、site_audit、token、twig_tweak、views 及 views 扩展等）见 `config/sync/core.extension.yml`。已安装主题：`olivero`、`claro`、`default_admin`、`radix`、`xedc`、`gin`。默认前台主题是 `xedc`。
