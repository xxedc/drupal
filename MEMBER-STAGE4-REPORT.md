# XEDC 会员中心第四阶段报告：评论管理、投稿审核与第三阶段收尾

> 项目目录：`/var/www/drupal`  
> 报告日期：2026-10-24  
> 依据：当前 `xedc_member` 代码、实际启用的 Drupal 模块、工作流配置、角色权限、数据库状态，以及本阶段执行的 Drush、PHP、YAML、Twig 和 HTTP 测试。  
> 本阶段未执行 `drush cim`、`drush cex`、模块卸载、生产数据清空或部署。

> 复验更新（2026-10-24）：本报告第 1–11 节保留首次第四阶段实现记录；第 12 节记录本轮收尾复验、修复和最终测试结果。第 12 节优先于前文中“未完成/未验证”的旧表述。  

## 1. 执行摘要

- 第三阶段剩余验收已完成：
  - 收藏添加/取消、历史删除/清空通过真实 HTTP 表单测试。
  - 历史写节流（60 秒）和 180 天保留期清理已实现并测试。
  - 头像有效上传、无效类型、超大文件、移除、移除后重新上传测试通过。
  - 昵称/简介超长输入被拒绝，未保存。
  - 密码修改、错误当前密码拒绝、邮箱修改测试通过。
  - 17 项配置差异已在 `MEMBER-STAGE3-REPORT.md` 补充分析。
- 第四阶段已启用并配置：
  - `workflows`、`content_moderation` 已启用。
  - 创建 `xedc_editorial` 工作流，应用 `article`、`photo`、`video`。
  - 普通会员只能创建/编辑自己的草稿并提交审核，不能直接发布或批准。
  - `content_editor` 拥有审核、发布、退回、拒绝权限，可访问 `/admin/content/moderated`。
  - `/member/comments` 已实现真实评论列表。
  - `/member/submissions` 已实现真实投稿列表、状态和审核意见。
- 发现并修复第三阶段遗留问题：
  - 历史重复写入/长期累积：增加 60 秒节流和 180 天 cron 清理。
  - 头像移除时旧文件清理：已实现并测试。
- 未执行配置导入/导出；当前 active config 与 `config/sync` 差异为 21 项。
- 测试数据已清理；现有真实用户 uid 2 的 2 条收藏、3 条历史、47 条既有评论未被删除或改动。

---

## 2. 备份和当前环境

### 2.1 第四阶段前备份

在启用评论审核/内容审核相关模块前创建新备份：

```text
/var/backups/xedc-member/xedc-member-pre-stage4-20261024-154155.sql.gz
```

验证：

```text
gzip -t 通过
大小约 1.8M
```

第三阶段前备份仍保留：

```text
/var/backups/xedc-member/xedc-member-pre-stage3-20261024-145947.sql.gz
```

### 2.2 当前模块和数据结构

```text
xedc_member=启用
workflows=启用
content_moderation=启用
xedc_member_favorite=存在
xedc_member_history=存在
field_xedc_nickname=存在
field_xedc_bio=存在
xedc_editorial workflow=存在
```

工作流应用内容类型：

```text
article, photo, video
```

`page` 不在工作流中。

### 2.3 当前内容状态

```text
article total=11 published=11 unpublished=0
photo total=41 published=39 unpublished=2
video total=6 published=6 unpublished=0
```

抽查：

```text
nid=1 published state=published
nid=6 published state=published
nid=7 published state=published
nid=44 unpublished state=draft
```

既有已发布内容未因启用工作流被批量取消发布。

### 2.4 测试数据

```text
stage4_test_users=0
stage4_test_nodes=0
stage4_test_comments=0
existing_comments=47
```

现有真实用户 uid 2 的收藏/历史：

```text
favorites_existing=2
history_existing=3
```

这些数据**未被删除或修改**，属于现有用户数据。

---

## 3. 第三阶段剩余验收和修复

### 3.1 浏览历史长期累积与重复刷新优化

修改 `HistoryManager`：

- `WRITE_THROTTLE = 60`：同一用户/内容 60 秒内重复访问不写库、不增加 `view_count`。
- `RETENTION_DAYS = 180`。
- 新增 `purgeExpired()`。
- `hook_cron()` 自动清理超过 180 天的历史。

测试结果：

```text
first=1 throttled_second=0 count=1 view_count=1
after_old_last=1 view_count=2
purged=1 remaining=0
```

说明：60 秒内连续刷新不更新 `last_viewed`；超过节流时间后再次访问会正常更新。

### 3.2 收藏和历史 HTTP 操作

使用临时会员登录，通过真实 HTTP 非 AJAX 表单提交：

```text
PASS | favorite form on node
PASS | favorite add response
PASS | favorite appears in list
PASS | favorite form on list
PASS | favorite removed from list
PASS | history contains node
PASS | history delete form
PASS | history deleted
PASS | history clear form
PASS | history clear response
PASS | history cleared
```

AJAX 卡片移除/消息提示仍建议浏览器点击验收。

### 3.3 头像上传、移除和清理

- 有效 PNG 上传成功，头像渲染。
- `.txt` 文件被拒绝，显示扩展名错误。
- 3MB PNG 被拒绝，显示大小错误。
- 头像移除成功，旧文件被删除。
- 移除后重新上传成功。
- 单次请求“移除旧头像 + 同时上传新文件”不是 managed_file 的实际 UI 流程；实际流程是先移除/保存，再上传/保存。

### 3.4 昵称、简介、密码和邮箱

- 65 字符昵称、501 字符简介未保存，长度校验生效。
- 正确当前密码 + 新密码：保存成功，新密码可重新登录。
- 错误当前密码：被核心用户表单拒绝，旧密码仍可登录。
- 修改邮箱：正确当前密码下保存成功。
- 站点当前 `user.settings:verify_mail = false`；本模块没有改变或绕过该配置。

### 3.5 PC/移动端

- PC 端两栏、移动端单列 CSS 已存在。
- 未进行真机或浏览器响应式实测；仅完成 CSS/模板代码检查。

---

## 4. 第四阶段：我的评论

### 4.1 实现

路由：

```text
/member/comments
```

控制器：`MemberController::comments()`  
模板：`xedc-member-comments.html.twig`

功能：

- 查询当前用户 UID 的评论。
- 分页，每页 20 条。
- 显示：
  - 评论正文
  - 所属内容标题和链接
  - 发表时间
  - 评论审核状态（已发布/待审核）
  - 已发布评论的“查看评论”链接
  - 作者自己可编辑的已发布评论“编辑”链接
- 只查询当前 UID，不能读取其他用户评论。
- 父内容无权访问时显示“内容不可用或已下架”，不输出标题/链接。
- 使用 `accessCheck(FALSE)` 查询后按 UID 限定，以便作者能看到自己的待审核评论。
- 评论正文使用字段渲染数组，经 Drupal 文本格式处理；Twig 自动转义。

### 4.2 当前评论范围限制

- 站点当前只有 `photo` 内容类型有 `field_comment`。
- `article`、`video` 没有评论字段。
- 本阶段没有新增评论字段，避免改动既有内容类型和详情页。
- `/member/comments` 可以显示任何当前用户已有的评论；目前实际可用范围是 photo。
- 如果后续给 article/video 增加评论字段，会员中心评论页无需重写。

### 4.3 评论审核策略

- 现有 `authenticated` 仍拥有 `skip comment approval`，新评论默认已发布。
- 本阶段没有移除该权限，也没有启用评论审核流程。
- 页面仍能显示 `status=0` 的待审核评论（已通过测试评论验证）。
- `content_editor` 已授予 `administer comments`，可在 Drupal 核心评论管理中审核/删除评论。
- 会员中心没有提供“删除自己评论”的入口；评论删除仍走核心评论管理权限，避免越权。

### 4.4 评论测试结果

使用临时会员和一张临时评论（一条已发布、一条待审核、一条属于另一会员）：

```text
PASS | comments page status
PASS | published comment body
PASS | pending comment body
PASS | pending status label
PASS | published status label
PASS | parent photo title
PASS | other member comment hidden
PASS | comment edit link exists
```

说明：

- 待审核评论正文可以正常显示。
- 其他会员评论不会出现在当前会员页面。
- 评论页未做超过 20 条的分页压力测试；分页使用 Drupal pager。

---

## 5. 第四阶段：用户投稿与审核

### 5.1 工作流

创建 `xedc_editorial` 工作流：

```text
类型：content_moderation
适用：article、photo、video
默认状态：draft
```

状态：

| 状态 ID | 标签 | 发布 | 默认修订 |
|---|---|---|---|
| `draft` | 草稿 | 否 | 否 |
| `needs_review` | 待审核 | 否 | 否 |
| `changes_requested` | 退回修改 | 否 | 否 |
| `rejected` | 已拒绝 | 否 | 否 |
| `published` | 已发布 | 是 | 是 |

转换：

| 转换 | 起点 → 终点 | 权限 |
|---|---|---|
| `submit_for_review` | draft → needs_review | 会员 |
| `resubmit_for_review` | changes_requested → needs_review | 会员 |
| `withdraw` | needs_review → draft | 会员 |
| `request_changes` | needs_review → changes_requested | 审核员 |
| `reject` | needs_review → rejected | 审核员 |
| `approve` | needs_review → published | 审核员 |
| `create_new_draft` | published → draft | 审核员 |

### 5.2 权限分配

普通会员 `authenticated` 新增：

```text
create article/photo/video content
edit own article/photo/video content
delete own article/photo/video content
view own unpublished content
view latest version
create image media
create video media
edit own image media
edit own video media
delete own image media
delete own video media
use xedc_editorial transition submit_for_review
use xedc_editorial transition resubmit_for_review
use xedc_editorial transition withdraw
```

普通会员**没有**：

```text
administer nodes
administer node published status
bypass node access
view any unpublished content
use xedc_editorial transition approve
use xedc_editorial transition request_changes
use xedc_editorial transition reject
```

审核员 `content_editor` 新增：

```text
view any unpublished content
view latest version
administer comments
use xedc_editorial transition approve
use xedc_editorial transition request_changes
use xedc_editorial transition reject
use xedc_editorial transition create_new_draft
```

`content_editor` 既有 `administer nodes`、`bypass node access`、`access content overview`，可审核任意内容。

### 5.3 会员投稿表单

- 标准 node add/edit 表单继续使用。
- `hook_form_node_form_alter()` 对没有 `administer nodes` 权限的会员隐藏：
  - `advanced`
  - `options`
  - `status`
  - `uid`
  - `created`
  - `revision_log`
  - `path`
  - `menu`
  - `field_views`
  - `field_published_at`
  - `field_show_cover`
- 保留 `moderation_state` 控件，让会员可以选择提交审核。
- Content Moderation 阻止直接编辑 `status`，并用 transition 权限校验发布/审核动作。
- 新内容默认 `draft`、未发布。
- 普通会员不能选择 `published`，也不能通过 POST 直接发布；已通过实体校验测试。

### 5.4 我的投稿页

路由：

```text
/member/submissions
```

控制器：`MemberController::submissions()`  
模板：`xedc-member-submissions.html.twig`

功能：

- 查询当前用户 UID 的 article/photo/video。
- 加载最新修订，显示最新审核状态。
- 显示：
  - 标题
  - 内容类型
  - 状态徽标
  - 更新时间
  - 退回/拒绝原因（来自最新修订的 revision log）
  - “编辑 / 提交审核”
  - 已发布内容的“查看已发布内容”
- 顶部分页和新建投稿链接：
  - 投稿美图 `/node/add/photo`
  - 投稿视频 `/node/add/video`
  - 投稿文章 `/node/add/article`
- 只查询当前 UID；不能查看/管理他人投稿。
- 编辑链接带 `destination=/member/submissions`，方便返回。

### 5.5 管理员审核入口

复用核心 Content Moderation 视图：

```text
/admin/content/moderated
```

测试：

```text
PASS | member denied moderated content | status=403
PASS | reviewer allowed moderated content | status=200
```

审核员可以在核心内容编辑表单/审核表单中批准、退回或拒绝，并填写 revision log 作为审核原因。

### 5.6 投稿和审核测试结果

程序化实体测试：

```text
PASS | existing published content remains published
PASS | new member node is unpublished
PASS | new member node state is draft
PASS | node owner is member
PASS | member cannot publish draft | violations=1
PASS | member submits for review
PASS | needs_review remains unpublished
PASS | member cannot approve submission | violations=1
PASS | reviewer approves submission
PASS | reviewer can access moderated content
PASS | reviewer requests changes
PASS | review reason stored
PASS | member can view own changes_requested
PASS | member cannot edit another member draft
PASS | member B sees own draft
PASS | member A cannot view B draft
PASS | reviewer can view any unpublished
PASS | member denied moderated content
PASS | reviewer allowed moderated content
```

补充测试：

```text
resubmit_state=needs_review published=0
```

HTTP 投稿页测试：

```text
PASS | submissions page status
PASS | submission title draft
PASS | submission title changes
PASS | submission title published
PASS | draft state label
PASS | changes state label
PASS | published state label
PASS | review reason visible
PASS | create links visible
PASS | needs_review label
PASS | rejected label
PASS | rejected reason visible
```

节点表单测试：

```text
article status=200 moderation_state=1 status_hidden=1
photo status=200 moderation_state=1 status_hidden=1
video status=200 moderation_state=1 status_hidden=1
PASS | uid field hidden
PASS | created field hidden
PASS | path field hidden
PASS | direct published option absent
```

---

## 6. 实际修改文件

### 6.1 第四阶段新增

| 文件 | 用途 |
|---|---|
| `web/modules/custom/xedc_member/templates/xedc-member-comments.html.twig` | 我的评论页面。 |
| `web/modules/custom/xedc_member/templates/xedc-member-submissions.html.twig` | 我的投稿页面。 |

### 6.2 第四阶段修改

| 文件 | 实际改动 |
|---|---|
| `web/modules/custom/xedc_member/src/Controller/MemberController.php` | 新增 `comments()`、`submissions()`；评论/投稿卡片、最新修订、审核状态、新建投稿链接。 |
| `web/modules/custom/xedc_member/xedc_member.module` | 注册评论/投稿模板；新增 `hook_form_node_form_alter()` 隐藏会员不允许的节点表单字段。 |
| `web/modules/custom/xedc_member/xedc_member.install` | 新增 `xedc_member_update_10003()`；创建 `xedc_editorial` 工作流；分配会员/审核员权限；`hook_install()` 同步调用。 |
| `web/modules/custom/xedc_member/xedc_member.info.yml` | 增加 `content_moderation`、`workflows` 依赖；更新描述。 |
| `web/modules/custom/xedc_member/xedc_member.routing.yml` | `/member/comments`、`/member/submissions` 改为真实控制器。 |
| `web/modules/custom/xedc_member/templates/xedc-member-overview.html.twig` | 移除已实现功能的“即将接入”区块。 |
| `web/modules/custom/xedc_member/css/member.css` | 新增评论/投稿卡片、状态徽标、审核意见、创建入口样式。 |

### 6.3 第三阶段收尾修改

| 文件 | 实际改动 |
|---|---|
| `web/modules/custom/xedc_member/src/Service/HistoryManager.php` | 增加 60 秒写节流、180 天保留期 `purgeExpired()`。 |
| `web/modules/custom/xedc_member/xedc_member.module` | 新增 `hook_cron()` 清理过期历史。 |

### 6.4 未改动

- 未修改首页、搜索页、文章详情页和无关主题文件。
- 未覆盖现有未提交主题/文章详情工作。
- 未卸载模块。
- 未执行 `drush cim`、`drush cex`。
- 未部署。

---

## 7. 数据库和配置变更

### 7.1 数据库

- 启用 `workflows`、`content_moderation`（核心模块安装产生其自身表/字段/配置）。
- 工作流配置为 config entity，不是自定义数据库表。
- `xedc_member_favorite`、`xedc_member_history` 保持不变。
- 未新增自定义表。
- `xedc_editorial` 工作流应用后，node 的 `moderation_state` 字段/修订机制生效。
- 既有内容保持原发布状态。

### 7.2 配置状态

当前 active config 与 `config/sync` 差异为 **21 项**：

```text
core.entity_form_display.node.article.default
core.entity_form_display.user.user.default
core.entity_view_display.node.article.default
core.entity_view_display.user.user.compact
core.entity_view_display.user.user.default
core.entity_view_display.user.user.token
core.extension
field.field.node.article.field_show_cover
field.field.user.user.field_xedc_bio
field.field.user.user.field_xedc_nickname
field.storage.node.field_show_cover
field.storage.user.field_xedc_bio
field.storage.user.field_xedc_nickname
image.style.xa_cover
image.style.xa_hero
user.role.authenticated
user.role.content_editor
views.view.article_list
views.view.moderated_content
workflows.workflow.editorial
workflows.workflow.xedc_editorial
```

### 7.3 17 项差异分析（第三阶段结束时）

已在 `MEMBER-STAGE3-REPORT.md` 第 12.5 节记录。摘要：

| 分类 | 配置项 | 原因 | 处理 |
|---|---|---|---|
| 既有文章/站点改动 | article form/view display、field_show_cover storage/field、xa_cover、xa_hero、article_list | 既有未提交文章详情/封面/视图工作，active 领先 sync | 保留；不导入不覆盖 |
| 既有角色 | content_editor | 既有角色差异 | 保留，本阶段后又增加审核权限 |
| 模块启用 | core.extension | xedc_member（后续增加 content_moderation/workflows） | 预期；暂不导出 |
| 资料字段 | nickname/bio 的 storage+field | 第三阶段 update hook 创建 | 预期；暂不导出 |
| 用户显示配置 | user form display + 3 个 user view display | 字段创建后 field 模块把新字段加入配置为 hidden | 预期；暂不导出 |

### 7.4 第四阶段新增/变化的配置

新增/变化：

- `core.extension`：增加 `workflows`、`content_moderation`。
- `user.role.authenticated`：会员投稿、媒体、transition 权限。
- `user.role.content_editor`：审核 transition、`view any unpublished content`、`administer comments`。
- `workflows.workflow.xedc_editorial`：新工作流。
- `workflows.workflow.editorial`：Content Moderation 启用时带入的默认空工作流（无适用 bundle，当前未使用）。
- `views.view.moderated_content`：Content Moderation 管理视图，路径 `/admin/content/moderated`。

### 7.5 配置处理方案

- 本阶段**未执行** `drush cim` 或 `drush cex`。
- 不导入，避免覆盖既有未提交配置。
- 后续应由项目负责人确认 `config/sync` 与 active config 的权威来源后，再统一导出/比对。
- `workflows.workflow.editorial` 是空工作流；如确认不需要，可后续清理，但本阶段未删除。
- 不应在未备份/未确认前执行配置导入。

---

## 8. 测试汇总

### 8.1 静态检查

- PHP 语法：全部通过。
- YAML：4 个模块 YAML 全部通过。
- Twig：11 个模块模板全部通过语法解析。
- `git diff --check`：通过。
- `drush updatedb:status`：无待执行更新。
- 模块、表、字段、工作流、路由、服务均检查通过。

### 8.2 功能测试

已通过：

- 收藏添加/取消、列表、隔离、分页服务层测试。
- 收藏 HTTP 表单添加/取消。
- 历史记录、重复访问、筛选、分页、单条删除、清空。
- 历史写节流和 180 天清理。
- 订阅器跳过 AJAX/列表/预览/未发布/匿名。
- 我的评论页：已发布/待审核/父内容/其他用户隔离。
- 我的投稿页：草稿/待审核/退回/拒绝/已发布、审核原因、创建链接。
- 会员不能直接发布、不能批准自己的投稿。
- 审核员可批准、退回、拒绝、访问 `/admin/content/moderated`。
- 被退稿后可重新提交。
- 既有已发布内容保持发布，既有未发布 photo 保持未发布。
- 账户资料、头像、密码、邮箱测试。

### 8.3 未完成/未验证

- 移动端真机或浏览器响应式验收。
- 评论分页超过 20 条的压力测试。
- 投稿分页超过 20 条的压力测试。
- 收藏/历史 AJAX 点击的浏览器级验收。
- 评论删除、评论审核的浏览器级操作验收。
- 评论审核策略未改变；新评论仍自动发布（`skip comment approval` 保留）。
- article/video 尚未增加评论字段；目前评论实际只在 photo 上可用。
- 媒体库实际投稿上传（图片/视频）未做浏览器级测试。
- 投稿媒体文件大小/MIME 限制沿用现有媒体字段配置；媒体文件为 public，存在未审核媒体可通过 URL 访问的既有风险。
- 内容审核的 revision log 审核原因通过程序化测试和页面显示测试，未做完整浏览器审核面板点击测试。
- 生产环境多用户并发测试。

---

## 9. 风险和遗留问题

1. **媒体上传权限和公开文件风险**：普通会员获得创建 image/video media 权限后，可使用 media library 上传；现有媒体文件为 public，未审核媒体可能通过 URL 访问。
2. **媒体大小限制**：现有 media image/video 字段 `max_filesize` 为空；本阶段未修改，建议后续增加上传大小和 MIME/尺寸限制。
3. **评论审核策略未改变**：`authenticated` 仍有 `skip comment approval`，新评论默认已发布；`content_editor` 已获得 `administer comments`，但未改变自动批准策略。
4. **评论范围**：article/video 没有评论字段；当前评论实际只在 photo 上使用。
5. **评论删除**：会员中心不提供删除按钮；删除由核心评论管理权限控制，避免越权。
6. **配置同步差异 21 项**：未执行 `cex`/`cim`；需要后续确认权威配置源。
7. **空 `editorial` 工作流**：Content Moderation 启用时带入，当前无适用 bundle；未删除。
8. **审核界面**：管理员审核复用 `/admin/content/moderated` 和核心编辑表单；未做完整浏览器审核点击验收。
9. **移动端**：CSS 已适配，但未浏览器实测。
10. **分页压力**：评论/投稿每页 20 条，未做超过 20 条的实际压力验证。
11. **历史节流**：60 秒内刷新不更新 `last_viewed`，是性能优化取舍。
12. **真实数据**：uid 2 的 2 条收藏、3 条历史和 47 条既有评论未删除/改动。
13. **卸载风险**：模块卸载会删除收藏表、历史表和资料字段；工作流/角色权限清理未做完整卸载测试。本阶段未卸载。

---

## 10. 仍需执行的操作

当前环境：

- 模块已启用，数据库更新已完成，缓存已重建；`drush updatedb:status` 无待执行更新。
- 建议人工验收：
  1. 使用普通会员账号测试 photo/video/article 投稿表单、媒体上传、提交审核。
  2. 使用 `content_editor` 访问 `/admin/content/moderated`，批准、退回、拒绝并填写原因。
  3. 会员查看 `/member/submissions` 状态和审核意见，退回后重新提交。
  4. 普通会员测试 `/member/comments`，确认只能看到自己的评论。
  5. 审核员测试评论管理/删除。
  6. PC/手机浏览器检查评论、投稿、资料、安全页布局。
- 其他环境部署代码时：

```bash
vendor/bin/drush updb -y
vendor/bin/drush cr
```

不要执行 `drush cim`，除非先解决配置同步基线。

---

## 11. 结论

- 第三阶段剩余验收已完成：历史优化、收藏/历史 HTTP 操作、头像移除/清理、昵称简介校验、密码和邮箱修改均完成可用测试。
- 第四阶段已实现：
  - 我的评论页。
  - 我的投稿页。
  - 内容审核工作流。
  - 会员投稿权限和审核员权限。
  - 管理员审核入口。
  - 状态、退回/拒绝原因显示。
- 普通会员不能直接发布，不能批准投稿，不能管理他人投稿。
- 既有内容保持发布状态。
- 未执行 `cim`/`cex`、模块卸载或部署；配置同步差异为 21 项，需后续专项处理。
- 本阶段停止，不进入第五阶段。

报告保存路径：`/var/www/drupal/MEMBER-STAGE4-REPORT.md`


---

## 12. 第四阶段收尾复验与修复（2026-10-24）

### 12.1 复验环境和安全边界

- Drupal 11.4.11，PHP 8.5.12，MySQL；本地站点通过 `gitxx.xyz` 解析到 `127.0.0.1` 进行真实 HTTPS 浏览器测试。
- 浏览器测试使用 Playwright 1.64.1 + Chromium headless，非静态检查替代。
- 复验前备份：`/var/backups/xedc-member/xedc-member-pre-stage4-verify-20261024.sql.gz`（gzip 校验通过）。
- 未执行 `drush cim`、`drush cex`、模块卸载、部署、`git reset`、`git clean` 或回滚。
- 复验使用临时账号 `s4check_member`、`s4check_member2`、`s4check_reviewer`、`s4check_admin` 和临时内容；测试结束后已全部清理，真实用户 uid 2 的数据未改动。

### 12.2 本轮确认的问题和修复

| 问题 | 复验证据 | 修复 |
|---|---|---|
| 会员评论自动发布，审核策略未生效 | 修复前会员评论 cid=72 直接 `status=1` 并公开展示 | `xedc_member_update_10004()` 移除 `anonymous`、`authenticated` 的 `skip comment approval`；新评论默认待审核，保留审核员 `administer comments` |
| 评论表单没有审核提示 | 普通会员提交前无提示 | `hook_form_alter()` 为无审核权限用户增加“评论提交后需要审核”提示 |
| 媒体图片无字段级大小限制 | 修复前 26MB PNG 可通过 `/media/add/image` 上传并保存 | `xedc_member_update_10005()` 设置 image 源字段 `max_filesize=10 MB`、video 源字段 `max_filesize=200 MB` |
| 媒体表单向会员暴露状态、作者、时间、修订信息 | 媒体 add/edit 表单显示 `status`、`uid`、`created`、`revision_log_message` | `hook_form_alter()` 对无 `administer media` 权限用户隐藏这些字段；复验确认字段不存在 |
| 伪造 MP4 可上传 | 文本文件改名为 `.mp4` 时修复前可进入媒体表单 | `xedc_member_validate_video_mime()` 在视频媒体表单和媒体库上传表单校验真实 MIME；媒体添加表单实测伪造 MP4 被拒、真实 MP4 通过 |
| 会员无法在 UI 保存草稿 | 修复前新投稿“保存为”只有“待审核” | `xedc_member_update_10008()` 新增 `draft → draft` 的 `save_draft` 转换并授予会员；复验确认可保存草稿后再提交审核 |
| 管理员审核队列不显示 `xedc_editorial` 内容 | 修复前 `/admin/content/moderated` 返回 200 但列表为空，原因是视图过滤器仍绑定空的 `editorial` 工作流 | `xedc_member_update_10006()` / `10007()` 修正 `views.view.moderated_content` 的审批状态过滤器；复验确认待审投稿出现在队列并可批准 |
| 无封面相关内容导致美图详情 500 | 发布测试美图后页面 500，watchdog：`drupalEntity()` 第 2 参数为 null | `node--photo--full.html.twig` 关联推荐增加 `target_id` 守卫；复验 107、47、74、48 均返回 200 |

说明：`10006` 首次使用了错误的嵌套配置访问方式，未生效；立即用 `10007` 以正确的 `display` 数组方式重新应用，并已在复验中确认视图过滤器为 `xedc_editorial-*` 状态。

### 12.3 浏览器级测试结果

基础会员中心与分页/隔离：

```text
PASS | 8 个会员页面均 200 且 noindex
PASS | 收藏第 1 页 12 条、第 2 页 1 条
PASS | 历史第 1 页 12 条、第 2 页 1 条
PASS | 评论第 1 页 20 条、第 2 页 1 条
PASS | 投稿第 1 页 20 条、第 2 页 5 条
PASS | 其他会员草稿不在当前会员投稿列表
PASS | 评论正文 `<script>` 被过滤
PASS | 收藏 AJAX 添加/列表显示/列表移除
PASS | 浏览历史 AJAX 单条删除
PASS | 会员访问 /admin、/admin/content/moderated 均为 403
PASS | 会员可查看自己的未发布内容，不能查看其他会员草稿
```

资料与头像：

```text
PASS | 昵称、简介保存
PASS | 简介 HTML 标签被移除
PASS | 有效 PNG 上传并显示
PASS | 头像移除
PASS | 无效扩展名被拒绝（实际错误信息：只允许 png/gif/jpg/jpeg/webp）
PASS | 超过 2MB 文件被拒绝
```

媒体与投稿：

```text
PASS | 会员可进入 image/video 媒体添加页
PASS | 会员不能进入 document/audio/remote_video 媒体添加页
PASS | 会员不能进入 /admin/content/media
PASS | 会员可编辑自己的媒体，不能编辑/删除他人媒体
PASS | 26MB 图片在修复后被拒绝
PASS | 伪造 PNG 被拒绝
PASS | 伪造 MP4 被拒绝，真实 MP4 通过（媒体添加表单）
PASS | 会员通过媒体库选择图片并保存美图投稿
PASS | 美图投稿进入待审核状态，审核员批准后发布
PASS | 发布后的美图详情返回 200 并渲染媒体
PASS | 无封面关联内容不再导致详情页 500
```

评论审核：

```text
PASS | 普通会员评论提交后为待审核（status=0），不公开展示
PASS | 会员在 /member/comments 能看到自己的待审核评论和“待审核”标签
PASS | 匿名评论提交后为待审核，不公开展示
PASS | 审核员在评论审批页批量批准后，评论公开展示
```

投稿审核工作流：

```text
PASS | 会员新投稿不再出现“已发布”选项
PASS | 会员可保存草稿，草稿状态显示为“草稿”
PASS | 草稿可再次编辑并提交审核
PASS | 会员不能批准自己的投稿
PASS | 待审投稿出现在 /admin/content/moderated
PASS | 审核员可批准并发布投稿
PASS | 会员投稿页显示“已发布”
```

移动端：

```text
PASS | 390px 手机宽度下 8 个会员页面均无横向溢出，主区域单列
PASS | 768px 平板宽度下 8 个会员页面均无横向溢出，主区域单列
```

分页、收藏/历史 AJAX、评论审核、投稿审核和移动端均已做浏览器级复验；不是仅做 CSS/静态检查。

### 12.4 配置差异

复验完成后 `drush config:status` 为 **24 项**，比首次阶段报告的 21 项增加 3 项：

```text
field.field.media.image.field_media_image
field.field.media.video.field_media_video_file
user.role.anonymous
```

新增原因：媒体上传大小限制和匿名评论审核策略。原有 `user.role.authenticated`、`views.view.moderated_content`、`workflows.workflow.xedc_editorial` 差异也在本轮发生变化，但配置项名称已在原 21 项列表中。

本轮仍未执行 `drush cim` / `drush cex`。配置同步源的权威性仍需项目负责人确认；不得直接用 `cim` 覆盖现有配置。

### 12.5 数据清理和真实数据核对

复验创建并清理：

```text
临时用户 4 个
临时节点 34 个
临时评论 25 条
临时媒体 3 个
临时文件 8 个
```

清理后核对：

```text
[S4CHECK] 节点残留 = 0
[S4CHECK] 评论残留 = 0
s4check_ 用户残留 = 0
photo published = 39，photo unpublished = 2
article published = 11
video published = 6
全部评论 = 47（status=1）
uid 2：收藏 2、历史 3、评论 22
```

真实用户、内容、评论、收藏和历史未被删除或改动。

### 12.6 本轮修改文件

| 文件 | 改动 |
|---|---|
| `web/modules/custom/xedc_member/xedc_member.module` | 媒体表单字段隐藏、媒体库/视频 MIME 校验、评论审核提示、视频 MIME 校验函数 |
| `web/modules/custom/xedc_member/xedc_member.install` | 新增 `10004`–`10008` 更新：评论审核、媒体大小、审核队列视图、草稿转换；安装时同步调用 |
| `web/themes/custom/xedc/templates/content/node--photo--full.html.twig` | 关联推荐图片增加 `target_id` 守卫，修复无封面内容导致的 500 |

未修改 `config/sync`、未修改无关主题/模块、未提交 Git。

### 12.7 本轮实际执行的检查

```text
PASS | PHP 语法检查（xedc_member 全部 PHP 文件）
PASS | YAML 语法检查（xedc_member 4 个 YAML）
PASS | Twig 编译（xedc_member 全部模板 + node--photo--full）
PASS | git diff --check
PASS | drush updatedb:status = 无待执行更新
PASS | 浏览器级测试（Playwright/Chromium）
```

### 12.8 仍未解决/需决策的遗留风险

1. **媒体文件为 public**：待审核节点对应的媒体文件仍可通过公开 URL 访问；复验确认匿名请求已发布媒体文件返回 200。彻底修复需要私有文件系统、服务器配置或下载控制器，属于部署/基础设施决策，本轮未改。
2. **PHP 实际上传上限**：PHP-FPM `upload_max_filesize=64M`，因此视频字段虽然配置 200MB，实际仍受 64MB 服务器限制；需要服务器负责人确认。
3. **评论范围**：`article`、`video` 仍没有评论字段，当前评论实际只有 `photo` 可用；本轮未扩大范围。
4. **配置同步差异 24 项**：未 `cim/cex`；需要确认 `config/sync` 与 active config 的权威来源。
5. **空 `editorial` 工作流**：仍保留，未删除。
6. **移动端真机/多用户并发**：已完成 390px/768px 浏览器响应式测试，但未做真实手机和多用户并发压测。
7. **媒体实体访问**：会员拥有 `view media`，可查看已发布媒体实体；媒体文件本身仍公开，未做按作者隔离。

### 12.9 第四阶段结论

- 第四阶段未完成的浏览器级测试已补齐，发现并修复 8 类明确问题。
- 评论审核、媒体上传大小/真实 MIME、媒体表单权限、草稿保存、审核队列、无封面详情页 500 均已复验通过。
- 真实数据已核对，无测试残留。
- 第四阶段可以视为完成，但 public 文件访问和配置同步仍是上线前风险。
- 本节完成后停止，不进入未定义需求的第五阶段。
