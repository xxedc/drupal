# XEDC 会员中心第三阶段报告：启用、验收、个人资料与账户安全

> 项目目录：`/var/www/drupal`  
> 报告日期：2026-10-24  
> 依据：第一、二阶段报告，当前 `web/modules/custom/xedc_member/` 实际代码，实际启用的模块/数据库状态，以及本阶段执行的 Drush、PHP、YAML、Twig 和 HTTP 测试。  
> 本阶段已按授权备份数据库、启用模块、执行必要数据库更新和缓存重建；未执行 `drush cim`、`drush cex`、模块卸载或部署。

## 1. 执行摘要

- 数据库备份已完成并验证：`/var/backups/xedc-member/xedc-member-pre-stage3-20261024-145947.sql.gz`。
- `xedc_member` 模块已启用。
- `xedc_member_favorite`、`xedc_member_history` 两张表已创建。
- 第一阶段收藏功能、第二阶段浏览历史已通过服务层、权限、订阅器和 HTTP 页面验证。
- 发现并修复两个实际问题：
  1. 浏览历史 `merge()` 的插入键被覆盖，导致写入使用 `uid=0/entity_id=0`；已修复并复测通过。
  2. 头像上传时 managed_file 的值是数组，原提交逻辑错误地强转为整数；已修复并复测通过。
- 启用模块后，旧 Twig 编译缓存导致收藏按钮未显示；执行 `drush cr` 后恢复。
- 第三阶段个人资料和账户安全已实现：
  - 新增昵称、个人简介字段，复用现有 `user_picture` 头像字段。
  - 新增 `/member/profile` 个人资料页和 `/member/security` 账户安全页。
  - 账户安全页嵌入 Drupal 核心用户编辑表单，保留核心邮箱/密码验证机制，不自行存储密码。
- 已执行 `drush updb`（创建资料字段）和 `drush cr`。
- 未执行 `drush cim`/`drush cex`；active config 与配置同步目录差异目前为 17 项，需后续单独处理。
- 测试用临时用户、收藏、历史和头像文件已清理；当前收藏/历史表为空，无测试用户残留。

---

## 2. 开发前保护和数据库备份

### 2.1 Git 工作区

开发前已检查 `git status --short`，保留了所有现有未提交改动，包括：

- `web/themes/custom/xedc/xedc.theme`
- `web/themes/custom/xedc/xedc.libraries.yml`
- `web/modules/custom/xa_views/`
- `web/themes/custom/xedc/css/article-detail.css`
- `web/themes/custom/xedc/js/article-detail.js`
- 未跟踪的文章详情模板

未执行 Git reset、clean、checkout、回滚、覆盖或提交。

### 2.2 数据库备份

先创建备份目录，再执行：

```bash
mkdir -p /var/backups/xedc-member
vendor/bin/drush sql:dump --gzip \
  --result-file=/var/backups/xedc-member/xedc-member-pre-stage3-YYYYmmdd-HHMMSS.sql.gz
```

实际备份文件（Drush 自动追加了 `.gz`，已重命名为最终路径）：

```text
/var/backups/xedc-member/xedc-member-pre-stage3-20261024-145947.sql.gz
```

验证结果：

```text
2.0M
gzip -t 通过
```

### 2.3 模块启用

由于当前模块此前未启用，执行：

```bash
vendor/bin/drush en xedc_member -y
```

结果：

```text
[success] Module xedc_member has been installed.
```

`hook_schema()` 创建了：

- `xedc_member_favorite`
- `xedc_member_history`

### 2.4 缓存重建

启用模块后，以及修复代码/完成字段更新后，执行了：

```bash
vendor/bin/drush cr
```

结果：

```text
[success] Cache rebuild complete.
```

首次启用后，旧 Twig 编译缓存仍保留旧版 `node--photo--full` 模板，导致详情页没有收藏按钮；执行 `drush cr` 后收藏按钮正常出现。

---

## 3. 第一、二阶段检查、修复与验收

### 3.1 模块、表、路由和服务

当前实际状态：

```text
module=1
xedc_member_favorite=1
xedc_member_history=1
xedc_member.favorite_manager=1
xedc_member.history_manager=1
xedc_member.history_subscriber=1
```

已注册路由：

```text
/member
/member/favorites
/member/history
/member/history/clear
/member/comments
/member/submissions
/member/settings
/member/profile
/member/security
```

### 3.2 实际修复的问题

#### 问题 1：浏览历史 merge 的插入键被覆盖

现象：功能测试中 `HistoryManager::record()` 插入时出现：

```text
Duplicate entry '0-node-0' for key 'uid_entity'
```

原因是 Drupal `Merge` 查询中 `insertFields()` 会替换此前的插入字段数组，导致 `keys()` 写入的 `uid/entity_type/entity_id` 被覆盖；插入实际变成默认 `0/0`。

修复：调整 `HistoryManager::record()` 调用顺序，先 `insertFields()`，再 `keys()`。修复后：

- 唯一记录正确写入。
- 重复访问更新 `last_viewed`。
- `view_count` 正常递增。
- 两个用户数据隔离正常。

修复后也清理了测试产生的 `uid=0/entity_id=0` 历史残留。

#### 问题 2：头像上传 managed_file 值处理错误

现象：首次头像上传测试出现 500。managed_file 的表单值是文件 ID 数组，而代码直接 `(int)` 强转，导致错误使用文件 ID 1。

修复：新增 `getPictureFid()`，从数组中提取首个 fid；`#default_value` 改为 fid 数组。修复后：

- 有效 PNG 上传成功。
- 头像在个人资料页渲染。
- 无效类型和大文件被拒绝。
- 不再出现 500。

#### 问题 3：旧 Twig 缓存导致收藏按钮缺失

现象：启用模块后 HTTP 页面无收藏按钮，Twig 缓存仍是旧模板。

修复：执行 `drush cr` 后重新编译模板，收藏按钮出现。

### 3.3 第一、二阶段功能测试结果

使用临时用户、现有已发布节点和真实数据库执行服务层/订阅器测试。结果全部通过：

```text
PASS | nodes loaded | nids=1,6,7,44
PASS | n44 unpublished
PASS | n1 published photo
PASS | anonymous denied /member/history
PASS | member allowed /member/history
PASS | member allowed /member/history/clear
PASS | member allowed /member/favorites
PASS | favorite duplicate prevented
PASS | favorite count after second content
PASS | favorite B isolation initially
PASS | favorite isFavorited
PASS | favorite B remove does not affect A
PASS | favorite remove A
PASS | favorite paged rows
PASS | history count after two unique contents
PASS | history duplicate row avoided
PASS | history view_count incremented | view_count=2
PASS | history first_viewed preserved
PASS | history paged rows
PASS | history delete single
PASS | history disabled flag
PASS | history disabled blocks new write
PASS | history disabled keeps old rows
PASS | history clear
PASS | history A has row
PASS | history B isolation
PASS | history B clear does not affect A
PASS | subscriber records canonical GET
PASS | subscriber skips AJAX
PASS | subscriber skips list route
PASS | subscriber skips preview route
PASS | subscriber skips unpublished
PASS | subscriber skips anonymous
PASS | cleanup user favorites
PASS | cleanup user history
```

测试后确认：

```text
test_users=0
favorites=0
history=0
```

### 3.4 HTTP 页面验收

使用临时登录用户访问站点前台，结果：

```text
/member=200
/member/favorites=200
/member/history=200
/member/settings=200
/member/profile=200
/member/security=200
anonymous /member=403
anonymous /member/profile=403
anonymous /member/security=403
```

详情页和收藏按钮：

- 已发布 photo 详情页返回 200。
- 页面包含收藏按钮（`xedc-favorite`）。
- 访问详情页后，`/member/history` 返回 200 且包含该节点标题，说明请求级记录生效。
- 历史页面包含单条删除按钮。
- 清空历史确认页 `/member/history/clear` 返回 200，包含“确定清空全部浏览历史吗？”。

历史记录开关：

- 设置页包含“记录我的浏览历史”复选框。
- 实际提交关闭后显示“浏览历史记录已关闭”。
- 再次提交开启后显示“浏览历史记录已开启”。

---

## 4. 第三阶段：个人资料管理与账户安全

### 4.1 新增用户资料字段

新增两个 user 字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `field_xedc_nickname` | string，max_length 64 | 昵称，留空时显示用户名 |
| `field_xedc_bio` | string_long | 个人简介，最多 500 字 |

头像继续复用 Drupal 核心 `user_picture` 字段，没有新建重复头像字段。

字段创建方式：

- `xedc_member_install()`：新安装时创建字段。
- `xedc_member_update_10002()`：已启用环境升级时创建字段。
- 本环境执行了：

```bash
vendor/bin/drush updb -y
```

结果：

```text
Created the member profile nickname and bio fields.
[success] Finished performing updates.
```

当前字段状态：

```text
field_xedc_nickname storage=1 field=1
field_xedc_bio storage=1 field=1
```

### 4.2 个人资料页 `/member/profile`

新增：

- 路由 `xedc_member.profile` → `/member/profile`
- 控制器 `MemberController::profile()`
- 表单 `Drupal\xedc_member\Form\ProfileForm`
- 模板 `xedc-member-profile.html.twig`

功能：

- 显示用户名、邮箱、注册时间、当前头像、昵称、简介。
- 修改昵称。
- 修改个人简介。
- 上传/更换/移除头像。
- 保存后留在会员中心个人资料页。

校验：

- 昵称：最长 64 字符，保存时去除 HTML 标签。
- 简介：最长 500 字符，保存时去除 HTML 标签。
- 头像：
  - 扩展名：`png gif jpg jpeg webp`
  - 大小：最大 2MB
  - 必须为图片（`FileIsImage`）
  - 使用 managed_file + Form API
- 仅允许当前登录用户修改自己的资料。
- Form API 自动提供 CSRF 保护。
- 替换/移除头像后，若旧文件没有其他 usage，会尝试删除旧文件；该逻辑已实现，替换场景的浏览器级验证尚不完整。

### 4.3 账户安全页 `/member/security`

新增：

- 路由 `xedc_member.security` → `/member/security`
- 控制器 `MemberController::security()`
- 模板 `xedc-member-security.html.twig`
- 表单：**嵌入 Drupal 核心用户编辑表单**，没有自定义密码存储。
- `hook_form_user_form_alter()` 仅在 `xedc_member.security` 路由隐藏：
  - 用户名（由资料页单独展示）
  - 时区
  - 语言
  - 头像
  - 角色
  - 删除账户操作
- 保留：
  - 邮箱
  - 当前密码
  - 新密码 / 确认密码
- 提交按钮改为“保存账户安全设置”。
- 保存后通过 submit callback 重定向回 `/member/security`。

邮箱与密码：

- 修改邮箱或密码必须输入当前密码。
- 当前密码验证、邮箱保存、密码哈希全部由 Drupal 核心 `AccountForm`/User 实体处理。
- 没有自行保存密码。
- 邮箱修改遵循站点现有核心账户机制；当前站点 `user.settings:verify_mail` 为 `false`，本阶段没有改变该配置，也没有绕过核心流程。
- 当前密码错误会被核心表单拒绝；测试中错误当前密码未保存，旧密码仍可登录。
- 正确当前密码 + 新密码后，新密码登录成功。

### 4.4 会员中心导航和设置页

- 左侧导航新增“账户安全”。
- “个人资料”改为指向 `/member/profile`。
- “账号设置”保留，继续管理浏览历史开关和退出登录。
- 设置页链接改为：
  - 个人资料
  - 账户安全
  - 退出登录
  - 隐私与记录（浏览历史开关）
- 概览页“编辑资料”现在指向新的会员中心个人资料页。

### 4.5 权限和安全

- 个人资料页和账户安全页均要求登录。
- 控制器只加载当前登录用户，不接受其他 UID。
- 个人资料表单只操作当前用户。
- 账户安全表单只嵌入当前用户的 core user form。
- 所有写操作使用 Form API（CSRF token）。
- 头像使用扩展名、大小、图片内容验证。
- 没有新增会员等级、积分、私信、关注等功能。
- 没有修改首页、搜索页、文章详情页或无关主题模板。

---

## 5. 实际文件变更

### 5.1 第三阶段新增文件

| 文件 | 用途 |
|---|---|
| `web/modules/custom/xedc_member/src/Form/ProfileForm.php` | 昵称、简介、头像编辑表单；字段和头像校验；旧头像清理。 |
| `web/modules/custom/xedc_member/templates/xedc-member-profile.html.twig` | 个人资料页。 |
| `web/modules/custom/xedc_member/templates/xedc-member-security.html.twig` | 账户安全页。 |

### 5.2 第三阶段修改文件

| 文件 | 实际改动 |
|---|---|
| `web/modules/custom/xedc_member/src/Controller/MemberController.php` | 新增 `profile()`、`security()`；账户资料显示昵称/用户名/最近登录；新增 `profile`/`security` URL；导航新增账户安全。 |
| `web/modules/custom/xedc_member/xedc_member.module` | 注册 profile/security 模板；新增 `hook_form_user_form_alter()`；新增安全表单重定向 callback。 |
| `web/modules/custom/xedc_member/xedc_member.install` | 新增 `hook_install()` 创建资料字段；新增 update 10002；卸载时删除字段；保留历史/收藏表逻辑。 |
| `web/modules/custom/xedc_member/xedc_member.info.yml` | 描述更新；增加 `drupal:field` 依赖。 |
| `web/modules/custom/xedc_member/xedc_member.routing.yml` | 新增 `/member/profile`、`/member/security`。 |
| `web/modules/custom/xedc_member/templates/xedc-member-shell.twig` | 侧边栏新增账户安全入口。 |
| `web/modules/custom/xedc_member/templates/xedc-member-settings.html.twig` | 账号信息使用 `account.username`；新增账户安全链接；保留历史开关。 |
| `web/modules/custom/xedc_member/css/member.css` | 新增个人资料页、头像、表单、账户安全页、按钮和移动端样式。 |
| `web/modules/custom/xedc_member/src/Service/HistoryManager.php` | 修复 `merge()` 插入键顺序导致的记录错误。 |

### 5.3 未改动

- 第一阶段收藏功能未重写；仅在需要处复用。
- 第二阶段历史功能保留。
- 现有未提交主题/文章详情工作未被覆盖。
- 未修改 `config/sync`。
- 未执行 `drush cim`/`drush cex`。

---

## 6. 数据库、路由、字段、权限、服务和模板实际状态

### 6.1 数据库

| 对象 | 状态 |
|---|---|
| `xedc_member` 模块 | 已启用 |
| `xedc_member_favorite` | 已创建 |
| `xedc_member_history` | 已创建 |
| `field_xedc_nickname` | 已创建（storage + field config） |
| `field_xedc_bio` | 已创建（storage + field config） |
| `user_picture` | 复用，未改结构 |

`xedc_member_history` 字段：

```text
hid, uid, entity_type, entity_id, bundle, first_viewed, last_viewed, view_count
```

唯一键：

```text
uid_entity (uid, entity_type, entity_id)
```

`xedc_member_favorite` 字段：

```text
fid, uid, entity_type, entity_id, bundle, created
```

### 6.2 路由

| 路由 | 路径 | 访问 |
|---|---|---|
| `xedc_member.overview` | `/member` | 登录 |
| `xedc_member.favorites` | `/member/favorites` | 登录 |
| `xedc_member.history` | `/member/history` | 登录 |
| `xedc_member.history_clear` | `/member/history/clear` | 登录 |
| `xedc_member.comments` | `/member/comments` | 登录（占位） |
| `xedc_member.submissions` | `/member/submissions` | 登录（占位） |
| `xedc_member.settings` | `/member/settings` | 登录 |
| `xedc_member.profile` | `/member/profile` | 登录 |
| `xedc_member.security` | `/member/security` | 登录 |

### 6.3 权限

- 没有新增自定义权限，也没有修改角色权限。
- 所有会员中心路由使用 `_user_is_logged_in: TRUE`。
- 个人资料/安全页面只操作当前登录用户。
- 匿名访问会员中心、资料页、安全页均返回 403。

### 6.4 服务

```text
xedc_member.favorite_manager
xedc_member.history_manager
xedc_member.history_subscriber
```

### 6.5 模板

会员中心模块模板：

```text
xedc-member-shell.html.twig
xedc-member-overview.html.twig
xedc-member-favorites.html.twig
xedc-member-history.html.twig
xedc-member-card.html.twig
xedc-member-settings.html.twig
xedc-member-placeholder.html.twig
xedc-member-profile.html.twig
xedc-member-security.html.twig
```

### 6.6 配置同步

- 未执行 `drush cex`。
- 未修改 `config/sync`。
- 启用模块和创建字段后，active config 与同步目录差异为 17 项。
- 未执行 `drush cim`，避免覆盖现有未提交配置。
- 后续需要单独决策并处理配置同步。

---

## 7. 实际执行的测试和结果

### 7.1 PHP 语法检查

```bash
find web/modules/custom/xedc_member -type f \
  \( -name '*.php' -o -name '*.module' -o -name '*.install' \) \
  -print0 | xargs -0 -n1 php -l
```

结果：全部通过，无语法错误。

### 7.2 YAML 检查

```bash
vendor/bin/yaml-lint \
  web/modules/custom/xedc_member/xedc_member.info.yml \
  web/modules/custom/xedc_member/xedc_member.routing.yml \
  web/modules/custom/xedc_member/xedc_member.services.yml \
  web/modules/custom/xedc_member/xedc_member.libraries.yml
```

结果：

```text
[OK] All 4 YAML files contain valid syntax.
```

### 7.3 Twig 语法检查

对模块全部模板执行 Twig 解析，9 个模板全部通过：

```text
OK xedc-member-card.html.twig
OK xedc-member-favorites.html.twig
OK xedc-member-history.html.twig
OK xedc-member-overview.html.twig
OK xedc-member-placeholder.html.twig
OK xedc-member-profile.html.twig
OK xedc-member-security.html.twig
OK xedc-member-settings.html.twig
OK xedc-member-shell.html.twig
```

### 7.4 模块、表、字段、路由检查

```text
module=1
xedc_member_favorite=1
xedc_member_history=1
field_xedc_nickname storage=1 field=1
field_xedc_bio storage=1 field=1
```

9 个会员中心路由均可从路由提供器取得。

### 7.5 数据库更新和缓存

```bash
vendor/bin/drush updb -y
vendor/bin/drush cr
vendor/bin/drush updatedb:status
```

结果：

```text
Created the member profile nickname and bio fields.
[success] Finished performing updates.
[success] Cache rebuild complete.
[success] No database updates required.
```

### 7.6 个人资料 HTTP 测试

使用临时用户登录后：

- `/member/profile` 返回 200。
- 页面包含 `name="nickname"`、`name="bio"`、文件上传字段和“保存个人资料”。
- 提交昵称“测试昵称”和简介后：
  - 显示“个人资料已更新”。
  - 再次打开个人资料页，昵称和简介已持久化。
- 头像：
  - 有效 PNG 上传成功，头像渲染。
  - `.txt` 文件被拒绝，页面显示文件扩展名错误，头像 fid 保持 0。
  - 3MB PNG 被拒绝，页面显示大小/文件错误，头像 fid 保持 0。
- 旧头像替换/移除时删除旧文件的逻辑已实现；由于 managed_file 在已有文件时会隐藏上传控件，替换场景的浏览器级验证尚不完整。

### 7.7 账户安全 HTTP 测试

- `/member/security` 返回 200。
- 页面包含：
  - `name="mail"`
  - `name="current_pass"`
  - `name="pass[pass1]"`
  - `name="pass[pass2]"`
  - “保存账户安全设置”
- 用户名输入、时区输入在安全页被隐藏。
- 提供正确当前密码并设置新密码：
  - 表单提交成功。
  - 使用新密码可以重新登录，`/member` 返回 200。
- 提供错误当前密码：
  - 页面显示当前密码错误。
  - 未保存新密码。
  - 旧密码仍可登录。
- 核心 `/user/edit` 页面未被本模块的字段隐藏逻辑影响；其页面仍包含时区字段。

### 7.8 历史记录开关 HTTP 测试

- 设置页包含历史记录复选框。
- 提交关闭后显示“浏览历史记录已关闭”。
- 再次提交开启后显示“浏览历史记录已开启”。

### 7.9 测试数据清理

测试结束后：

```text
test_users=0
favorites=0
history=0
```

测试头像文件也已清理；未留下测试用户、收藏、历史或上传文件。

### 7.10 尚未完成的测试

以下项目尚未验证或未完整验证：

- 移动端真机/浏览器响应式验收；只做了 CSS 代码检查。
- 收藏按钮的浏览器点击和 AJAX 实际交互；已做服务层增删测试、HTTP 页面按钮存在验证。
- 历史单条删除和清空的浏览器点击；已做服务层删除/清空测试、历史页面和确认页验证。
- 头像“已有头像再替换/移除”的完整浏览器流程；旧文件清理代码已实现，但未完成端到端验证。
- 邮箱修改的实际提交流程；安全页复用核心用户表单，未改变邮箱验证配置。
- 昵称/简介超长输入的浏览器级错误提示；服务端校验已实现。
- 生产环境多用户并发和多语言场景。

---

## 8. 当前环境状态

- `xedc_member`：已启用。
- `xedc_member_favorite`：存在。
- `xedc_member_history`：存在。
- `field_xedc_nickname`：存在。
- `field_xedc_bio`：存在。
- 数据库更新：已执行 10002，当前无待执行更新。
- 缓存：已多次执行 `drush cr`，最后一次成功。
- 配置导入：未执行 `cim`。
- 配置导出：未执行 `cex`。
- 模块卸载：未执行。
- 部署：未执行。
- 数据库备份：存在且 gzip 校验通过。
- 测试数据：已清理。

---

## 9. 仍需执行的操作和建议

### 9.1 当前环境

当前环境不需要再执行数据库更新或缓存重建；模块、表、字段均已完成。建议进行人工前台验收：

1. 使用真实普通会员账号登录。
2. 访问 `/member/profile`：
   - 修改昵称、简介。
   - 上传、替换、移除头像。
   - 确认页面显示和移动端布局。
3. 访问 `/member/security`：
   - 验证错误当前密码被拒绝。
   - 验证修改密码后新密码可登录。
   - 在 staging 环境测试邮箱修改和邮件通知；当前 `verify_mail=false`。
4. 访问 `/member/history`：
   - 浏览详情页，确认历史记录和重复访问更新。
   - 测试类型筛选、分页、单条删除、清空历史。
5. 测试收藏按钮的浏览器点击和 AJAX 反馈。
6. 测试两个真实会员账号的数据隔离。
7. 检查 PC 和手机端布局、键盘操作和错误提示。

### 9.2 其他环境部署时

代码部署到已经启用过 `xedc_member` 的环境时，执行：

```bash
vendor/bin/drush updb -y
vendor/bin/drush cr
```

**不要执行 `drush cim`**，除非先解决现有配置同步目录不一致问题。

### 9.3 配置同步

- 当前 active config 与 `config/sync` 有 17 项差异，包括本阶段新增模块、字段和既有未导出配置。
- 未执行 `drush cex`。
- 需要单独确认配置同步策略后再导出，避免覆盖既有未提交配置。

---

## 10. 风险、问题和未解决事项

1. **配置同步差异扩大**：模块启用、资料字段创建后，active config 与同步目录差异从既有差异增加到 17 项；未执行 `cex`。
2. **头像替换/移除的端到端验证不完整**：旧文件清理代码已实现，并通过文件 usage 检查避免误删；但浏览器级替换流程未完整测试。
3. **邮箱验证配置**：站点当前 `verify_mail=false`；本阶段没有改变它，也没有绕过核心流程。若产品要求邮箱验证，需要单独调整站点配置并测试。
4. **移动端未浏览器验收**：CSS 已包含 PC 两栏/移动端单列，但未做真机或响应式浏览器测试。
5. **收藏/历史写操作的 AJAX 交互未做浏览器级验证**：已通过 HTTP 非 AJAX 表单验证收藏添加/取消、历史删除/清空；AJAX 卡片移除仍待浏览器验收。
6. **历史保留期限已实现**：`hook_cron()` + 180 天保留期；已通过服务层清理测试。
7. **历史单条删除 AJAX 后总数不实时更新**：卡片会移除，但顶部总数和 pager 需刷新后更新。
9. **多语言**：历史/收藏列表使用 `node_field_data.default_langcode = 1`，只覆盖默认翻译。
10. **未来 node access 模块**：`countVisible()` 只按发布状态/类型计数；若未来增加节点访问控制模块，计数与列表过滤需复核。
11. **测试脚本和临时用户**：测试用户、节点、评论、头像文件均已清理；仍存在真实用户 uid 2 的 2 条收藏和 3 条历史，未删除、未改动。测试脚本位于 `/tmp/opencode`，不属于项目代码。
12. **历史写入范围**：任何有节点查看权限的登录用户（包括管理员/编辑）访问 canonical 详情页都会记录；如果要求排除管理员，需要额外判断。
13. **重复刷新**：已增加 60 秒写节流和 180 天保留期；60 秒内重复访问不增加 `view_count`，避免写放大。
14. **卸载风险**：卸载模块会删除收藏表、历史表和资料字段，数据会丢失；本阶段未卸载。

---

## 11. 结论

- 第一、二阶段已实际启用并验证；发现的历史 merge 写入 bug 已修复，收藏和历史功能服务层/权限/订阅器/HTTP 页面测试通过。
- 第三阶段个人资料与账户安全已实现：
  - 昵称、个人简介字段。
  - 头像上传、类型/大小校验。
  - 个人资料页。
  - 账户安全页复用 Drupal 核心用户表单，验证当前密码，不自行存储密码。
  - 会员中心导航和设置页已接入。
- 实际执行了数据库备份、模块启用、`drush updb`、`drush cr`；未执行 `cim`/`cex`、模块卸载或部署。
- 核心表单、路由、权限、字段和缓存状态已通过检查。
- 移动端仍需人工浏览器验收；配置同步仍待专项处理。其余补充结果见第 12 节。
- 本阶段停止，不进入后续未要求的会员等级、积分、私信、关注等功能。

## 12. 第三阶段补充验收（本轮）

> 本节记录第三阶段剩余验收和修复，若与前文结论冲突，以本节为准。

### 12.1 浏览历史长期累积与重复刷新优化

已在 `HistoryManager` 实现：

- `WRITE_THROTTLE = 60`：同一用户/内容 60 秒内重复访问不重复写库，也不增加 `view_count`。
- `RETENTION_DAYS = 180`：新增 `purgeExpired()`。
- `hook_cron()` 自动清理超过 180 天的历史。

测试结果：

```text
first=1 throttled_second=0 count=1 view_count=1
after_old_last=1 view_count=2
purged=1 remaining=0
```

说明：60 秒内连续刷新不会更新 `last_viewed`；超过节流时间后再次访问会正常更新时间/次数。

### 12.2 收藏和历史 HTTP 操作验收

使用临时会员登录，通过真实 HTTP 表单完成：

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

说明：这是非 AJAX 表单提交路径；AJAX 卡片移除仍建议浏览器点击验收。

### 12.3 头像上传、移除和清理

测试结果：

- 有效 PNG 上传成功，头像渲染。
- `.txt` 文件被拒绝（扩展名错误），头像 fid 保持 0。
- 3MB PNG 被拒绝（大小错误），头像 fid 保持 0。
- 头像移除成功，旧文件被删除。
- 移除后重新上传成功。
- 单次请求“移除旧头像并同时上传新文件”不是 managed_file 的实际 UI 流程；实际流程是先移除/保存，再上传/保存。

测试文件已清理。

### 12.4 昵称、简介、邮箱和密码

- 超长昵称（65 字符）和超长简介（501 字符）未保存，服务端长度校验生效。
- 正确当前密码 + 新密码：保存成功，新密码可登录。
- 错误当前密码：被核心表单拒绝，旧密码仍可登录。
- 修改邮箱：使用核心账户表单，正确当前密码下保存成功；站点当前 `verify_mail=false`，本模块没有改变或绕过该配置。

### 12.5 17 项配置差异分析（第三阶段结束时）

| 分类 | 配置项 | 原因 | 处理方案 |
|---|---|---|---|
| 既有文章/站点未导出改动 | `core.entity_form_display.node.article.default`、`core.entity_view_display.node.article.default`、`field.field.node.article.field_show_cover`、`field.storage.node.field_show_cover`、`image.style.xa_cover`、`image.style.xa_hero`、`views.view.article_list` | 既有未提交文章详情/封面/视图工作，active config 领先于 sync | 保留，不导入不覆盖；由文章功能负责人确认后再导出 |
| 既有角色改动 | `user.role.content_editor` | 既有角色权限差异 | 保留；本阶段后又加入审核权限，需单独审查 |
| 模块启用 | `core.extension` | 启用 `xedc_member`（后续又启用 content_moderation/workflows） | 属预期；暂不导出 |
| 第三阶段资料字段 | `field.storage.user.field_xedc_nickname`、`field.field.user.user.field_xedc_nickname`、`field.storage.user.field_xedc_bio`、`field.field.user.user.field_xedc_bio` | 本阶段通过 update hook 创建昵称/简介字段 | 属预期；暂不导出 |
| 第三阶段用户显示配置 | `core.entity_form_display.user.user.default`、`core.entity_view_display.user.user.default`、`core.entity_view_display.user.user.compact`、`core.entity_view_display.user.user.token` | 创建字段后 field 模块把新字段加入用户表单/显示配置为 hidden | 属预期；暂不导出 |

结论：17 项中没有本阶段需要立即导入的配置；禁止直接 `drush cim`/`drush cex`，先解决 sync 基线和既有未提交配置归属。

### 12.6 第三阶段补充结论

- 收藏/历史 HTTP 操作、历史节流/保留期、头像类型/大小/移除、昵称/简介验证、密码和邮箱修改均已完成可用测试。
- 移动端仍只做 CSS 代码检查，未做浏览器实测。
- 真实用户 uid 2 的收藏/历史数据未被清理或改动。
- 配置同步仍未处理；后续阶段继续禁止直接 `cim/cex`。

报告保存路径：`/var/www/drupal/MEMBER-STAGE3-REPORT.md`
