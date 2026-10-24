# XEDC 会员中心第五阶段报告：配置同步基线与上线准备

> 项目目录：`/var/www/drupal`  
> 报告日期：2026-10-24  
> 阶段目标（用户确认）：配置同步与上线准备。  
> 范围：确认 `config/sync` 权威源、审查配置差异、补充上线/回滚步骤；**不直接执行 `drush cim` / `drush cex`**。  
> 本阶段未修改代码、未导入/导出配置、未部署、未修改服务器设置。

> 说明：本文件记录第五阶段“配置同步与上线准备”工作流；同一阶段的 UI/UX 优化记录见 `MEMBER-STAGE5-UI-REPORT.md`。  

## 1. 执行摘要

- 第四阶段收尾已完成，详见 `MEMBER-STAGE4-REPORT.md` 第 12 节。
- 本阶段确认了一个关键事实：**运行中的 Drupal 并没有使用项目根目录的 `config/sync`**。
  - `web/sites/default/settings.php` 第 918 行将 `$settings['config_sync_directory']` 指向：
    `sites/default/files/config_MopvndZmke_1lqYVMERmTx60p0SUJlxT1Rr1ML0zUVVrCFcqnxPMl2cZMUVdjd1_Z5y6NG9vSg/sync`
  - 项目根目录 `config/sync` 有 385 个 YAML；运行中的同步目录有 384 个；active config 有 395 个。
- `config/sync` 比运行中的同步目录**更新**：它包含 `image.style.xa_cover`，且 `views.view.article_list` 与 active 一致；运行中的同步目录缺少/落后这些内容。
- 但 `config/sync` 也不是 active config 的完整快照：相对 active 缺少 10 项，另有 12 项不同；合计 **22 项差异**。
- 相对运行中的同步目录，active 有 **24 项差异**（13 项 Different + 11 项 Only in DB）。
- 结论：**不能直接执行 `drush cim`**。推荐的权威源是项目根目录 `/var/www/drupal/config/sync`，但必须先获得授权，把 active config 受控导出并审查后，才能把它作为部署基线。
- 本阶段已补充上线/回滚清单；未执行任何生产配置切换。

## 2. 配置源事实核对

### 2.1 settings.php 实际配置

```text
$settings['config_sync_directory'] = 'sites/default/files/config_MopvndZ.../sync';
```

`drush status` 也显示 Drupal config 指向该目录，而不是 `/var/www/drupal/config/sync`。

### 2.2 三份配置的数量

| 来源 | 数量 |
|---|---|
| active config（数据库） | 395 |
| 项目根目录 `config/sync` | 385 |
| 运行中的同步目录 `sites/default/files/config_.../sync` | 384 |

文件级比较：

```text
只存在于项目 config/sync：image.style.xa_cover
只存在于运行同步目录：无
```

说明：项目 `config/sync` 至少比运行同步目录新一项；但不能因此认为它完整。

### 2.3 两种比较结果

- active 对比运行同步目录：**24 项差异**
  - 13 项 Different
  - 11 项 Only in DB
- active 对比项目 `config/sync`：**22 项差异**
  - 12 项 Different
  - 10 项 Only in DB（项目 sync 缺失）
  - 0 项 Only in sync

这证明：运行同步目录不是项目源；项目 `config/sync` 也不是当前数据库的完整导出。两套文件都不能直接用于生产 `cim`。


## 3. 24 项差异审查

### 3.1 逐项清单

状态以 `drush config:status` 对比运行同步目录为准；“项目 sync”列表示与 `/var/www/drupal/config/sync` 的关系。

| # | 配置项 | 运行同步目录 | 项目 sync | 分类/结论 |
|---|---|---|---|---|
| 1 | `core.entity_form_display.node.article.default` | Different | Different | 既有文章详情/封面 WIP；active 领先 |
| 2 | `core.entity_form_display.user.user.default` | Different | Different | 第三阶段昵称/简介 + 既有 matomo/path 字段；active 领先 |
| 3 | `core.entity_view_display.node.article.default` | Different | Different | 既有文章展示 WIP；active 领先 |
| 4 | `core.entity_view_display.user.user.compact` | Different | Different | 第三阶段字段 hidden 配置 |
| 5 | `core.entity_view_display.user.user.default` | Different | Different | 第三阶段字段 hidden 配置 |
| 6 | `core.entity_view_display.user.user.token` | Different | Different | 第三阶段字段 hidden 配置 |
| 7 | `core.extension` | Different | Different | active 多 `content_moderation`、`workflows`、`xa_views`、`xedc_member` |
| 8 | `field.field.media.image.field_media_image` | Different | Different | 第四阶段 `max_filesize=10 MB` |
| 9 | `field.field.media.video.field_media_video_file` | Different | Different | 第四阶段 `max_filesize=200 MB` |
| 10 | `field.field.node.article.field_show_cover` | Only in DB | Only in active | 既有文章封面 WIP |
| 11 | `field.field.user.user.field_xedc_bio` | Only in DB | Only in active | 第三阶段简介字段 |
| 12 | `field.field.user.user.field_xedc_nickname` | Only in DB | Only in active | 第三阶段昵称字段 |
| 13 | `field.storage.node.field_show_cover` | Only in DB | Only in active | 既有文章封面 WIP |
| 14 | `field.storage.user.field_xedc_bio` | Only in DB | Only in active | 第三阶段简介字段 |
| 15 | `field.storage.user.field_xedc_nickname` | Only in DB | Only in active | 第三阶段昵称字段 |
| 16 | `image.style.xa_cover` | Only in DB | 与 active 一致 | 项目 sync 更新；运行同步目录缺失 |
| 17 | `image.style.xa_hero` | Only in DB | Only in active | 既有文章图片样式 WIP |
| 18 | `user.role.anonymous` | Different | Different | 第四阶段移除 `skip comment approval` |
| 19 | `user.role.authenticated` | Different | Different | 第三/四阶段投稿、媒体、工作流权限 |
| 20 | `user.role.content_editor` | Different | Different | 既有角色差异 + 第四阶段审核权限；active 多 57 项权限 |
| 21 | `views.view.article_list` | Different | 与 active 一致 | 项目 sync 更新；运行同步目录落后 |
| 22 | `views.view.moderated_content` | Only in DB | Only in active | 第四阶段修正审核状态过滤器 |
| 23 | `workflows.workflow.editorial` | Only in DB | Only in active | Content Moderation 启用时带入的空工作流 |
| 24 | `workflows.workflow.xedc_editorial` | Only in DB | Only in active | 第四阶段投稿审核工作流 |

### 3.2 分类汇总

- **会员中心第三/四阶段产生（预期 active 领先）**：
  `field_xedc_nickname`、`field_xedc_bio`（storage + field）、user form/view displays、`user.role.authenticated`、`user.role.anonymous`、`user.role.content_editor`（部分）、`core.extension`、媒体 image/video 字段、`workflows.workflow.xedc_editorial`、`views.view.moderated_content`。
- **既有未提交文章/图片工作（不属于会员中心）**：
  `field_show_cover`（storage + field）、article form/view displays、`image.style.xa_hero`、部分 `image.style.xa_cover`、`views.view.article_list`、user form 中 matomo/path 字段。
- **项目 sync 比运行同步目录新的项**：
  `image.style.xa_cover`、`views.view.article_list`。
- **空工作流**：
  `workflows.workflow.editorial` 当前无适用 bundle；建议在确认无引用后清理，但本阶段未删除。

### 3.3 权限差异要点

`user.role.content_editor` 是最需要人工确认的一项：

- active 比运行同步目录多 57 项权限。
- 其中既有长期未导出的权限（`administer nodes`、`bypass node access`、`access content overview`、路径/翻译/布局/媒体等），也有第四阶段新增的审核权限。
- 该角色权限较大，不是最小权限审核角色；如果上线要求最小权限，应另立任务评估 `reviewer` 角色，不应在本阶段直接改角色。

`user.role.authenticated` 的 active 权限包含第四阶段全部投稿/媒体/工作流权限；`anonymous` 已不再拥有 `skip comment approval`。

## 4. 权威源结论和建议

### 4.1 事实结论

1. 运行中站点使用的同步目录不是项目根目录 `config/sync`。
2. 项目 `config/sync` 比运行同步目录新，但仍不完整。
3. 两套目录都不能直接作为 `cim` 的生产基线。
4. 直接 `cim` 的风险：会删除 active 独有的 10 项配置，可能回退昵称/简介字段、投稿工作流、审核视图、封面字段和图片样式。

### 4.2 推荐决策（等待负责人授权）

推荐将 `/var/www/drupal/config/sync` 作为项目权威源，但按以下顺序处理：

1. 冻结内容/配置变更，创建数据库和文件备份。
2. 将 active config **受控导出到临时目录**（不是直接覆盖 `config/sync`），审查新增/修改/删除项。
3. 确认要保留的 24 项差异，尤其是 `content_editor` 权限和空 `editorial` 工作流。
4. 经负责人批准后，把审查通过的 active 配置更新到 `config/sync` 并提交。
5. 在 staging 验证 `drush cim` 的 diff 只包含预期项，再考虑修改 `$settings['config_sync_directory']` 指向项目 `config/sync`。
6. 生产环境最后一次配置导入必须单独审批，并与数据库/文件备份绑定。

本阶段**没有执行上述 2–6 步**，因为涉及配置源切换和生产配置写入。

## 5. 上线步骤（建议，未执行）

### 5.1 上线前

```bash
cd /var/www/drupal
vendor/bin/drush status
vendor/bin/drush updatedb:status
vendor/bin/drush config:status
```

检查：

- 数据库和文件备份完成且可解压验证。
- 当前无待执行数据库更新。
- 确认配置同步策略；**未解决前禁止 `drush cim`**。
- 确认 PHP-FPM 上传上限（当前 64MB）与媒体字段上限（image 10MB、video 200MB）的关系。
- 确认维护窗口、回滚负责人和备份存放位置。
- 确认 `trusted_host_patterns` 覆盖实际域名（当前为 `gitxx.xyz`、`www.gitxx.xyz`）。

### 5.2 部署代码和数据库更新

```bash
vendor/bin/drush updb -y
vendor/bin/drush cr
```

- 会员中心相关更新：`xedc_member_update_10004`–`10008`。
- 不要在生产执行 `drush cim`，直到配置基线问题经负责人批准解决。

### 5.3 上线后冒烟检查

- 匿名：首页、文章/美图/视频详情 200；`/member` 403/跳转登录。
- 会员：`/member`、收藏、历史、评论、投稿、资料、安全、设置均 200；noindex 存在。
- 收藏/历史 AJAX 添加、取消、删除正常。
- 评论：新评论为待审核，作者可见，匿名不可见，审核员可批准。
- 投稿：会员可保存草稿、提交审核，不能直接发布；审核员可在 `/admin/content/moderated` 批准。
- 媒体：会员可上传 image/video，不可上传 document/audio/remote_video；10MB 图片限制生效；伪造 MIME 被拒绝。
- 资料：昵称/简介/头像上传与移除正常，头像 2MB 限制生效。
- 移动端：390px、768px 无横向溢出。
- 日志：`drush watchdog:show --severity=3` 无新增未处理错误。

### 5.4 回滚步骤

只在确认上线失败且负责人批准后执行：

1. 开启维护模式。
2. 停止内容写入。
3. 恢复上线前数据库备份。
4. 恢复 `web/sites/default/files` 备份（含 public 文件）。
5. 恢复上一版本代码（使用发布包/备份，不使用 `git reset` 破坏当前未提交工作）。
6. `drush cr`。
7. 验证首页、登录、内容详情、会员中心。
8. 关闭维护模式。

注意：本轮未导入配置，因此回滚不需要配置回滚；如果未来执行了 `cim`，必须同时准备配置和数据库双重回滚。

## 6. 上线前仍存在的风险

1. **配置基线未解决**：运行站点指向运行目录，项目 `config/sync` 不是完整 active 快照；禁止直接 `cim`。
2. **媒体 public 访问**：未审核节点对应的媒体文件仍可通过公开 URL 访问；需要私有文件系统或受控下载方案。
3. **PHP 上传上限 64MB**：视频字段配置 200MB，但服务器实际限制更低；需服务器负责人确认。
4. **评论范围**：article/video 仍无评论字段，目前实际只有 photo 评论。
5. **空工作流**：`workflows.workflow.editorial` 仍存在，建议确认无引用后清理。
6. **content_editor 权限过大**：包含 `administer nodes`、`bypass node access` 等；如要求最小权限，应另立任务。
7. **系统状态报告存在既有告警**：Colorbox library 未安装（Error）、DOMPurify 未安装（Warning）、实验管理主题、Toolbar/Navigation 重复、翻译缺失；不属于会员中心本阶段改动，但属于上线检查项。
8. **未做真机/多用户并发/生产压测**：仅完成 Chromium 390/768 响应式测试。

## 7. 本阶段实际执行的检查

```text
PASS | drush core:status
PASS | drush updatedb:status = 无待执行更新
PASS | drush config:status = 24 项差异（只读）
PASS | active vs 项目 config/sync 只读比较 = 22 项差异
PASS | settings.php / config_sync_directory / trusted_host_patterns / private path 核对
PASS | 备份文件存在且先前 gzip 校验通过
PASS | 真实数据核对：47 条评论；uid 2 收藏 2、历史 3
```

未执行：

```text
drush cim
drush cex
修改 settings.php
修改服务器/Nginx/PHP-FPM
部署
```

## 8. 修改文件

本阶段为只读审查和文档阶段，未修改代码、配置或服务器设置。

新增文档：

- `MEMBER-STAGE5-REPORT.md`

## 9. 结论和停止点

- 第五阶段目标（配置同步与上线准备）的审查部分已完成。
- 已确认 `config/sync` 与运行同步目录不是同一来源，且两者都不完整。
- 已给出 24 项差异分类、权威源建议、上线和回滚步骤。
- 配置源切换和任何 `cim/cex` 仍需负责人明确授权；本阶段不执行。
- 完成后停止，等待负责人决定是否授权配置导出/切换和正式上线。
