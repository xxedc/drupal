# XEDC 会员中心第一阶段验收报告

> 项目目录：`/var/www/drupal`  
> 报告日期：2026-10-24  
> 依据：第一阶段实际创建的 `xedc_member` 模块代码、主题模板改动和已执行的只读检查结果。  
> 重要状态：代码已创建，但 **`xedc_member` 模块尚未启用**，收藏表尚未创建，运行时页面和 AJAX 尚未在浏览器中验证。

## 状态说明

本报告严格区分以下状态：

- **已实现**：代码已写入，逻辑存在。
- **已测试**：执行了相应检查，且结果通过；不等同于浏览器验收。
- **尚未验证**：因模块未启用或未执行运行时测试，不能视为已完成验收。

---

## 1. 新增、修改的文件及用途

### 1.1 新增文件

| 文件 | 用途 |
|---|---|
| `web/modules/custom/xedc_member/xedc_member.info.yml` | 模块元数据；依赖 `node`、`user`、`comment`、`file`、`image`、`media`。 |
| `web/modules/custom/xedc_member/xedc_member.routing.yml` | 会员中心 6 个路由：概览、收藏、历史、评论、投稿、设置。 |
| `web/modules/custom/xedc_member/xedc_member.services.yml` | 注册 `xedc_member.favorite_manager` 服务，注入数据库和时间服务。 |
| `web/modules/custom/xedc_member/xedc_member.libraries.yml` | 注册 `xedc_member/member` CSS/资源库，依赖 `core/drupal`、`core/drupal.ajax`。 |
| `web/modules/custom/xedc_member/xedc_member.module` | 注册模板；会员中心入口 URL；`xm-page` body class；私密页面 noindex；内容详情页收藏按钮；内容/用户删除时清理收藏。 |
| `web/modules/custom/xedc_member/xedc_member.install` | 定义 `xedc_member_favorite` 表结构；卸载时删除该表。 |
| `web/modules/custom/xedc_member/src/Controller/MemberController.php` | 会员中心页面控制器：概览、收藏列表、占位页、设置页；导航、账户信息、封面解析、统计。 |
| `web/modules/custom/xedc_member/src/Form/FavoriteToggleForm.php` | 收藏/取消收藏表单；Form API CSRF；AJAX 即时反馈；服务端权限和内容状态校验。 |
| `web/modules/custom/xedc_member/src/Service/FavoriteManager.php` | 收藏数据服务：判断、添加、删除、计数、分页查询、清理。 |
| `web/modules/custom/xedc_member/templates/xedc-member-shell.html.twig` | 会员中心外壳：PC 左侧用户卡片/导航，右侧内容；移动端由 CSS 改为单列。 |
| `web/modules/custom/xedc_member/templates/xedc-member-overview.html.twig` | 会员中心概览：统计、最近收藏、后续功能入口。 |
| `web/modules/custom/xedc_member/templates/xedc-member-favorites.html.twig` | 收藏列表：分类筛选、卡片网格、空状态、分页。 |
| `web/modules/custom/xedc_member/templates/xedc-member-placeholder.html.twig` | 浏览历史、我的评论、我的投稿的占位页面。 |
| `web/modules/custom/xedc_member/templates/xedc-member-settings.html.twig` | 账号信息、个人资料/密码入口、退出登录、隐私说明。 |
| `web/modules/custom/xedc_member/templates/xedc-member-card.html.twig` | 收藏卡片：真实标题、封面、类型、日期、详情链接、取消收藏表单。 |
| `web/modules/custom/xedc_member/css/member.css` | 会员中心白色简约布局、PC 两栏、移动端单列、卡片、筛选、空状态、收藏按钮样式。 |

### 1.2 修改文件

| 文件 | 实际改动 |
|---|---|
| `web/themes/custom/xedc/templates/includes/xedc-header.html.twig` | 新增 `account_url` 变量；登录后的桌面图标和移动端菜单入口改为会员中心；模块未启用时回退到 `user.page`。 |
| `web/themes/custom/xedc/templates/node/node--video--full.html.twig` | 在视频元信息下方输出 `xedc_member_favorite`（模块启用后显示收藏按钮，否则为空）。 |
| `web/themes/custom/xedc/templates/content/node--photo--full.html.twig` | 在美图侧栏标题/元信息下方输出收藏按钮。 |
| `web/themes/custom/xedc/templates/node/node--article--full.html.twig` | 该文件本为用户未跟踪工作；本次仅在操作区增加 1 行收藏按钮输出，原有文章详情逻辑保留。 |

### 1.3 保留但未改动的已有未提交工作

- `web/themes/custom/xedc/xedc.theme`
- `web/themes/custom/xedc/xedc.libraries.yml`
- `web/modules/custom/xa_views/`
- `web/themes/custom/xedc/css/article-detail.css`
- `web/themes/custom/xedc/js/article-detail.js`

`git status` 中这些既有改动仍然存在，未被回滚或覆盖。

---

## 2. 新增的会员中心路由、菜单、权限和服务

### 2.1 路由

定义于 `web/modules/custom/xedc_member/xedc_member.routing.yml`。

| 路由名 | 路径 | 控制器方法 | 页面状态 |
|---|---|---|---|
| `xedc_member.overview` | `/member` | `MemberController::overview` | 已实现，尚未运行时验证 |
| `xedc_member.favorites` | `/member/favorites` | `MemberController::favorites` | 已实现，尚未运行时验证 |
| `xedc_member.history` | `/member/history` | `MemberController::placeholder` | 占位页面 |
| `xedc_member.comments` | `/member/comments` | `MemberController::placeholder` | 占位页面 |
| `xedc_member.submissions` | `/member/submissions` | `MemberController::placeholder` | 占位页面 |
| `xedc_member.settings` | `/member/settings` | `MemberController::settings` | 已实现，尚未运行时验证 |

所有路由：

```yaml
requirements:
  _user_is_logged_in: 'TRUE'
options:
  no_cache: TRUE
```

收藏/取消收藏没有单独的 POST 路由；它由嵌入在节点页和收藏列表中的 Form API 表单提交到当前页面路由。

### 2.2 菜单与入口

未新增 Drupal menu link 配置，也未修改 `config/sync`。

实际入口：

- 站点头部登录后图标：由 `xedc_member_preprocess_page()` 提供 `member_center_url`，头部模板使用 `account_url` 指向 `/member`。
- 移动端侧边菜单：同样使用 `account_url`。
- 模块未启用时，`member_center_url` 不存在，头部回退到 `user.page`，不会因路由缺失直接报错。
- 会员中心左侧导航（由 `MemberController::shell()` 构建）：
  - 概览
  - 我的收藏
  - 浏览历史
  - 我的评论
  - 我的投稿
  - 个人资料（核心 `user.edit`）
  - 账号设置
- 左侧底部：个人资料、账号设置、退出登录。
- 退出登录使用核心 `user.logout` URL，包含 CSRF token。

### 2.3 权限

- **没有新增自定义权限配置**，也没有修改任何角色权限。
- 会员中心 6 个路由统一使用 `_user_is_logged_in: 'TRUE'`，匿名用户不能访问。
- 收藏表单额外在 `validateForm()` 和 `submitForm()` 中检查 `currentUser()->isAuthenticated()` 和 `uid > 0`。
- 收藏服务 `add()` 拒绝 `uid <= 0`。
- 所有收藏查询/删除均使用当前登录用户 UID，不接受 URL 或表单传入其他用户 UID。
- 当前实现意味着：所有已登录用户都可以访问会员中心；如果后续需要“仅特定会员角色”，需要新增权限并配置角色，本阶段未做。

### 2.4 服务

`xedc_member.services.yml` 注册：

```yaml
xedc_member.favorite_manager:
  class: Drupal\xedc_member\Service\FavoriteManager
  arguments:
    - '@database'
    - '@datetime.time'
```

服务提供：

- `isAllowedNode()`
- `isFavorited()`
- `add()`
- `remove()`
- `countVisible()`
- `getFavoriteRows()`
- `getRecentRows()`
- `deleteForEntity()`
- `deleteForUser()`

### 2.5 模板库

`xedc_member/member` 库提供：`css/member.css`，依赖 `core/drupal`、`core/drupal.ajax`。会员中心页面和内容详情页收藏按钮会附加该库。

---

## 3. 收藏功能的数据库表结构、唯一约束、增删查实现

### 3.1 表结构

表名：`xedc_member_favorite`  
定义位置：`xedc_member.install` 的 `xedc_member_schema()`。

| 字段 | 类型 | 约束/默认值 | 说明 |
|---|---|---|---|
| `fid` | serial | 主键 | 收藏记录 ID |
| `uid` | int unsigned | not null，default 0 | 用户 UID |
| `entity_type` | varchar(32) | not null，default `node` | 当前固定为节点 |
| `entity_id` | int unsigned | not null，default 0 | 节点 ID |
| `bundle` | varchar(32) | not null，default 空字符串 | `photo`、`video`、`article` |
| `created` | int | not null，default 0 | 收藏时间戳 |

### 3.2 唯一约束与索引

- 唯一键：`uid_entity (uid, entity_type, entity_id)`  
  防止同一用户重复收藏同一内容。
- 索引：`uid_created (uid, created)`  
  用于会员收藏列表按时间排序。
- 索引：`entity (entity_type, entity_id)`  
  用于内容删除时清理收藏。

### 3.3 增加收藏

`FavoriteManager::add()`：

1. 校验 `uid > 0` 且节点类型属于 `photo/video/article`、节点已发布。
2. 使用 Drupal Database API `insert()` 写入。
3. 捕获 `IntegrityConstraintViolationException`：如果唯一键已存在，则保持原记录，不重复插入，也不重置原收藏时间。
4. 不使用字符串拼接 SQL。

### 3.4 删除收藏

`FavoriteManager::remove()`：

```text
DELETE FROM xedc_member_favorite
WHERE uid = 当前用户
  AND entity_type = 'node'
  AND entity_id = 当前节点
```

只删除当前用户自己的记录。

### 3.5 查询收藏

`FavoriteManager::baseQuery()` 统一构造查询：

- 条件 `f.uid = 当前用户 UID`
- 条件 `f.entity_type = 'node'`
- 条件 `f.bundle IN ('photo', 'video', 'article')`
- JOIN `node_field_data`，要求 `default_langcode = 1`
- 要求节点 `status = 1`（已发布）
- 可选追加 `f.bundle = 指定分类`
- 排序 `f.created DESC`

`countVisible()` 使用同一基础查询计数。  
`getFavoriteRows()` 追加 `PagerSelectExtender`，每页 12 条。  
`getRecentRows()` 用于概览页最近 4 条收藏。

控制器在加载节点后还会执行 `$node->access('view')`，因此已删除、未发布或当前用户无权查看的内容不会出现在收藏列表。

### 3.6 清理

`xedc_member_entity_delete()`：

- 节点删除：`deleteForEntity('node', nid)`
- 用户删除：`deleteForUser(uid)`

如果内容只是取消发布，收藏记录保留，但列表查询通过 `status = 1` 隐藏；重新发布后会重新出现。

### 3.7 当前数据库实际状态

已通过只读检查确认：

```text
module_exists=0
in_core_extension=0
favorite_table=0
```

即：

- 模块未启用。
- `xedc_member` 未写入 active config。
- `xedc_member_favorite` 表尚未创建。
- 上述表结构目前只是代码定义，尚未在数据库中落地。

---

## 4. 收藏列表的分类筛选、分页、权限校验和缓存处理

### 4.1 分类筛选

- 支持 `?type=photo`、`?type=video`、`?type=article`。
- 控制器只接受 `FavoriteManager::ALLOWED_BUNDLES` 中的值；其他值按“全部”处理。
- 筛选标签由 `MemberController::favoriteFilters()` 生成：
  - 全部
  - 美图
  - 视频
  - 文章
- 当前筛选标签带 `aria-current="page"` 和激活样式。

### 4.2 分页

- 使用 Drupal `PagerSelectExtender`。
- 每页 `FavoriteManager::PER_PAGE = 12` 条。
- 模板中输出 `['#type' => 'pager']`。
- 分页查询和总数来自同一个基础查询条件。

### 4.3 权限与访问校验

- 路由要求登录。
- 查询强制当前用户 UID。
- 节点加载后再次执行 `access('view')`。
- 只允许 `photo/video/article`，且节点必须已发布。
- 表单校验当前用户登录、节点存在、类型允许、节点可见。
- 取消收藏只删除当前用户自己的记录。
- 无法通过 URL 或表单传入其他用户 UID。

### 4.4 缓存与 SEO

实际代码中已包含：

- 会员中心路由 `no_cache: TRUE`。
- 会员中心外壳 `#cache`：
  - `contexts: ['user']`
  - `max-age: 0`
- 收藏表单 `#cache`：
  - `contexts: ['user']`
  - `tags: ['node:{nid}']`
  - `max-age: 0`
- `hook_preprocess_page()` 为页面缓存增加 `user.roles:authenticated` 上下文。
- `hook_preprocess_html()` 为页面缓存增加 `route` 上下文。
- 会员中心和用户资料/编辑路由通过 `hook_page_attachments_alter()` 输出：
  ```html
  <meta name="robots" content="noindex, nofollow, noarchive">
  ```
- 内容详情页收藏按钮通过 `hook_preprocess_node()` 增加 `user` 缓存上下文和 `node:{nid}` 缓存标签。

这些缓存处理目前只做了代码检查，**尚未在启用模块后通过实际页面/AJAX 请求验证**。

---

## 5. 会员中心各页面实现状态

> “已实现”仅表示代码存在；“已测试”表示执行了静态或服务层检查；“尚未验证”表示未进行浏览器/路由运行时验收。

| 页面/功能 | 实现状态 | 已测试 | 尚未验证 |
|---|---|---|---|
| `/member` 概览 | 已实现：账户信息、头像、统计、最近收藏、后续功能入口 | 控制器/Twig 语法检查 | 路由访问、真实页面渲染、不同用户数据 |
| `/member/favorites` 收藏列表 | 已实现：筛选、分页、空状态、卡片、取消收藏 | 服务层查询逻辑阅读、Twig 语法 | 实际收藏/取消、AJAX、分页、两个账号隔离 |
| 内容详情页收藏按钮 | 已实现：article/video/photo 三种模板均接入 | Twig 语法解析；封面解析抽查 | 浏览器实际显示、点击、AJAX 反馈 |
| `/member/history` 浏览历史 | **占位页面** | 路由 YAML、模板语法 | 历史记录写入/查询未实现 |
| `/member/comments` 我的评论 | **占位页面** | 路由 YAML、模板语法 | 评论查询/审核状态未实现 |
| `/member/submissions` 我的投稿 | **占位页面** | 路由 YAML、模板语法 | 投稿/审核状态未实现 |
| `/member/settings` 账号设置 | 已实现：账户信息、资料/密码入口、退出登录、隐私说明 | Twig 语法 | 实际点击核心资料编辑/退出登录 |
| 个人资料入口 | 已实现：链接到核心 `user.edit` | URL 生成逻辑检查 | 实际页面跳转 |
| 退出登录入口 | 已实现：链接到核心 `user.logout`（带 CSRF token） | `drush php:eval` 验证 URL 生成 | 实际退出流程 |
| 头部会员中心入口 | 已实现：登录后入口指向 `/member`；未启用时回退 `/user` | 模板语法 | 启用后实际导航 |
| 移动端单列布局 | 已实现：`@media (max-width: 860px/560px)` | CSS 代码检查 | 真机/响应式浏览器验收 |

---

## 6. 实际执行的检查命令及结果

### 6.1 PHP 语法检查

命令：

```bash
find web/modules/custom/xedc_member -type f \
  \( -name '*.php' -o -name '*.module' -o -name '*.install' \) \
  -print0 | xargs -0 -n1 php -l
```

结果：

```text
No syntax errors detected in .../xedc_member.install
No syntax errors detected in .../src/Controller/MemberController.php
No syntax errors detected in .../src/Form/FavoriteToggleForm.php
No syntax errors detected in .../src/Service/FavoriteManager.php
No syntax errors detected in .../xedc_member.module
```

结论：**已测试，通过**。

### 6.2 YAML 语法检查

命令：

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

结论：**已测试，通过**。

### 6.3 新增 Twig 模板语法检查

使用 Twig 解析器对 `web/modules/custom/xedc_member/templates/*.twig` 进行解析。

结果：

```text
OK xedc-member-card.html.twig
OK xedc-member-favorites.html.twig
OK xedc-member-overview.html.twig
OK xedc-member-placeholder.html.twig
OK xedc-member-settings.html.twig
OK xedc-member-shell.html.twig
```

结论：**已测试，通过**。

### 6.4 修改的主题 Twig 模板语法检查

对以下模板使用 Twig 解析器，并补充 Drupal 专用函数/过滤器占位（`attach_library`、`path`、`clean_class`、`render`、`without`、`drupal_entity`）后解析：

- `xedc-header.html.twig`
- `node--article--full.html.twig`
- `node--video--full.html.twig`
- `node--photo--full.html.twig`

结果：全部解析通过。

说明：这是**语法解析**，不是 Drupal 运行时渲染验证。

### 6.5 Schema 定义检查

命令（只读）：

```bash
vendor/bin/drush php:eval \
  'require_once ".../xedc_member.install";
   $s = xedc_member_schema();
   echo "schema=".(isset($s["xedc_member_favorite"])?"OK":"MISSING").
        " fields=".count($s["xedc_member_favorite"]["fields"])."\n";'
```

结果：

```text
schema=OK fields=6
```

结论：**Schema 函数已测试，6 个字段定义有效；表尚未创建。**

### 6.6 模块启用状态和表存在性检查

命令（只读）：

```bash
vendor/bin/drush php:eval \
  'echo "module_exists=".(int) \Drupal::moduleHandler()->moduleExists("xedc_member")."\n";
   echo "in_core_extension=".(int) (bool) \Drupal::config("core.extension")->get("module.xedc_member")."\n";
   echo "favorite_table=".(int) \Drupal::database()->schema()->tableExists("xedc_member_favorite")."\n";'
```

结果：

```text
module_exists=0
in_core_extension=0
favorite_table=0
```

结论：

- 模块未启用。
- 未写入 active config。
- 收藏表不存在。

### 6.7 PHP 类加载检查

命令（只读）：

```bash
php -r 'require "vendor/autoload.php";
  require ".../FavoriteManager.php";
  require ".../FavoriteToggleForm.php";
  require ".../MemberController.php";
  foreach ([...] as $c) { echo $c.": ".(class_exists($c)?"OK":"FAIL")."\n"; }'
```

结果：

```text
Drupal\xedc_member\Service\FavoriteManager: OK
Drupal\xedc_member\Form\FavoriteToggleForm: OK
Drupal\xedc_member\Controller\MemberController: OK
```

结论：**类加载和继承关系检查通过。**

### 6.8 收藏类型判断抽查

命令（只读）：

```bash
vendor/bin/drush php:eval \
  'require_once ".../FavoriteManager.php";
   $m = new FavoriteManager(\Drupal::database(), \Drupal::time());
   $n1 = \Drupal\node\Entity\Node::load(1);
   $n2 = \Drupal\node\Entity\Node::load(2);
   echo ...isAllowedNode($n1)...; ...'
```

结果：

```text
node1 allowed=1
node2 allowed=1
unpublished nid=44 allowed=0
```

结论：已发布 photo 节点允许收藏，未发布 photo 节点拒绝。**这是服务层只读检查，不是完整功能测试。**

### 6.9 封面解析抽查

命令（只读）：实例化 `MemberController`，通过反射调用 `coverUrl()`，抽取 photo/video/article 节点。

结果示例：

```text
photo 1 cover=/sites/default/files/styles/medium/public/2026-10/IMG_3009.jpeg.avif?itok=...
video 6 cover=/sites/default/files/styles/medium/public/2026-10/IMG_1204.png.avif?itok=...
article 7 cover=/sites/default/files/styles/medium/public/2026-10/IMG_1204.png.avif?itok=...
photo 13 cover=/sites/default/files/styles/medium/public/2026-10/IMG_1204.png.avif?itok=...
```

结论：三种内容类型的封面字段和媒体引用解析逻辑可用。**尚未在浏览器收藏列表中验证视觉输出。**

### 6.10 Git 空白/冲突检查

命令：

```bash
git diff --check
```

结果：退出码 0，无空白错误。

### 6.11 尚未执行的功能测试

以下测试**尚未执行**，因此不能标记为已完成验收：

- 启用模块后访问 `/member`、`/member/favorites`、`/member/settings` 的路由测试。
- 匿名用户访问会员中心的实际 HTTP 响应测试。
- 两个普通会员账号之间的收藏隔离测试。
- 内容详情页收藏按钮的浏览器显示和点击测试。
- AJAX 收藏/取消收藏、列表卡片移除、消息提示测试。
- 收藏分类筛选、分页、空状态的实际页面测试。
- `user.edit` 和 `user.logout` 的实际跳转/退出测试。
- 移动端浏览器布局测试。
- 主题模板在 Drupal 完整运行时下的渲染测试（仅做了 Twig 语法解析）。

---

## 7. 数据库更新、缓存重建和配置修改情况

### 7.1 未执行的操作

本阶段**没有执行**：

- `drush en xedc_member`
- `drush updb`
- `drush cr`
- `drush cim`
- `drush cex`
- 数据库表创建或修改
- 配置导入/导出
- 构建、部署
- Git 回滚、清理、覆盖或提交

### 7.2 当前实际状态

- `xedc_member` 模块未启用。
- `xedc_member_favorite` 表不存在。
- `config/sync` 未被修改。
- active config 中未出现 `xedc_member`。
- 站点头部对已登录用户仍回退到 `user.page`，因为模块未启用。
- 三种内容详情页的收藏按钮变量未产生输出，因为模块未启用。

### 7.3 启用模块会带来的必要变更

如果后续确认启用：

```bash
vendor/bin/drush en xedc_member -y
```

该操作会：

- 创建 `xedc_member_favorite` 表。
- 启用 6 个会员中心路由。
- 触发容器、路由和缓存重建。
- 在 active config 的 `core.extension` 中记录 `xedc_member`。

按本阶段约束，**未执行该操作，也未执行 `drush cex` 导出新配置**。因此启用后 active config 与配置同步目录的差异会扩大，需要后续单独处理。

---

## 8. 尚存问题、风险和第二阶段可复用组件

### 8.1 尚存问题

1. **模块未启用**：所有会员中心页面和收藏流程尚未做浏览器级验收。
2. **收藏表未创建**：Schema 已定义，但数据库中没有实际表。
3. **路由未做运行时验证**：只验证了 YAML 语法和控制器方法存在，没有验证实际访问、权限跳转和表单处理。
4. **AJAX 未做运行时验证**：收藏/取消收藏的 AJAX 回调、`MessageCommand`、`RemoveCommand`、`ReplaceCommand` 尚未在浏览器中实测。
5. **两个会员账号隔离未实测**：代码强制当前 UID，但没有实际创建两个测试账号进行收藏隔离验收。
6. **匿名访问行为**：路由使用 `_user_is_logged_in`，匿名用户直接访问 `/member` 预期为 403，而不是登录页跳转；未做实际 HTTP 验证。
7. **配置同步差异仍在**：第一阶段未处理此前审计发现的 `config/sync` 与实际同步目录不一致问题。
8. **文章详情模板是未跟踪文件**：本次在其操作区增加了 1 行收藏输出；如果后续该文件被重新生成或覆盖，需要重新接入。
9. **未新增自定义权限**：当前所有登录用户都可以访问会员中心；如果未来需要只允许特定会员角色，需要新增权限并配置角色。
10. **`hook_uninstall` 会删除收藏表**：卸载模块会丢失收藏数据；仅“禁用”模块不会删除表。
11. **多语言默认翻译限制**：收藏列表 JOIN 使用 `node_field_data.default_langcode = 1`，当前站点以默认语言为主；多语言场景需要进一步验证。
12. **计数与节点访问模块的兼容性**：`countVisible()` 使用状态和内容类型过滤，列表加载后再执行 `node->access('view')`；当前没有额外 node access 模块，未来若增加访问控制模块，计数与列表可能出现差异，需要复核。

### 8.2 风险

- 启用模块会创建表并重建缓存，属于生产环境变更；应在确认后执行。
- 启用后 active config 会出现 `xedc_member`，但未执行 `cex`；配置同步差异需要专门处理。
- 收藏列表使用真实数据库查询；若未启用模块就访问相关代码路径，会因表不存在失败，因此不能绕过正常启用流程。
- 主题模板改动范围很小，但文章详情模板本身是用户未跟踪工作，需要避免后续覆盖。
- 现有媒体文件仍为 public；收藏功能本身不改变文件访问策略，但后续投稿/媒体阶段仍需单独处理该风险。
- 头部入口依赖 `member_center_url` 页面变量；模块启用后需要确认页面缓存和登录状态切换正常。

### 8.3 第二阶段浏览历史可复用的现有组件

| 可复用组件 | 位置 | 复用方式 |
|---|---|---|
| 会员中心外壳和导航 | `MemberController::shell()`、`xedc-member-shell.html.twig` | 直接沿用；历史页只需在 `shell()` 的导航中保持 `history` active。 |
| 会员中心布局和响应式 CSS | `css/member.css` 的 `.xm`、`.xm-side`、`.xm-main`、`@media` | 历史列表复用同一布局、卡片/面板、移动端单列规则。 |
| 收藏列表筛选模式 | `MemberController::favoriteFilters()`、`.xm-tabs` | 改为历史类型筛选（全部/美图/视频/文章）。 |
| 收藏分页模式 | `FavoriteManager::getFavoriteRows()`、`PagerSelectExtender`、`#type => pager` | 历史查询使用同样的每页 12 条和 pager 输出。 |
| 卡片模板 | `templates/xedc-member-card.html.twig` | 可复用标题、封面、类型、日期、详情链接；历史页移除取消收藏表单。 |
| 账户信息/头像 | `MemberController::accountData()`、`avatar()` | 历史页外壳直接复用。 |
| URL 集合 | `MemberController::memberUrls()` | 已包含 `history`，添加历史相关操作 URL 即可。 |
| 收藏服务模式 | `src/Service/FavoriteManager.php` | 历史服务可采用同样的数据库表 + 服务层 + 当前 UID 限定 + 分页模式。 |
| 安装 Schema 模式 | `xedc_member.install` | 第二阶段新增 `xedc_member_history` 表时，沿用 `hook_schema()` + update hook。 |
| 删除清理模式 | `xedc_member_entity_delete()` | 历史记录同样在节点/用户删除时清理；另需保留期限 `hook_cron()`。 |
| 缓存隔离模式 | `no_cache`、`#cache` 的 `user` 上下文、`max-age=0`、`noindex` | 历史页直接沿用。 |
| 表单/AJAX 模式 | `FavoriteToggleForm` | 历史删除单条、清空历史可复用 Form API + AJAX/消息模式。 |
| 占位页面 | `xedc-member-placeholder.html.twig` | 历史页在正式实现前可继续使用。 |
| 详情页变量注入模式 | `hook_preprocess_node()` | 历史记录不应复用它做写入；第二阶段建议用 `hook_entity_view()` 严格限定 canonical full 页面，再调用历史服务。 |

---

## 9. 验收结论

- 第一阶段代码已创建：会员中心外壳、账户概览、收藏、设置页、占位页、详情页收藏按钮均已写入。
- 静态检查通过：PHP 语法、YAML、新增模板 Twig 语法、Schema 定义、类加载、服务层类型判断和封面解析抽查。
- **未完成运行时验收**：模块未启用，收藏表未创建，路由、权限、AJAX、分页和跨账号隔离尚未在浏览器中验证。
- **未执行数据库更新、缓存重建、配置导入/导出或部署。**
- 所有已有未提交改动已保留；仅新增报告文件和第一阶段代码，未回滚或覆盖用户原有工作。

报告保存路径：`/var/www/drupal/MEMBER-STAGE1-REPORT.md`
