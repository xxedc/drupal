# XEDC 会员中心第二阶段报告：浏览历史

> 项目目录：`/var/www/drupal`  
> 报告日期：2026-10-24  
> 编写依据：当前 `web/modules/custom/xedc_member/` 实际代码、数据库 Schema 定义、路由/服务配置，以及本次重新执行的只读检查。  
> 本次仅生成/更新报告，未修改业务代码，未执行数据库更新、缓存重建、模块启用、配置导入或部署。

## 状态说明

- **已实现**：代码已写入当前模块。
- **已测试**：执行了不修改生产环境的语法、配置、Schema、类加载或只读服务检查，且结果通过。
- **尚未验证**：需要模块启用、数据库表、路由运行时或浏览器才能验证的项目。
- **占位/未实现**：本阶段没有完成的业务。

---

## 1. 实际新增和修改的文件

### 1.1 第二阶段新增文件

| 文件 | 用途 |
|---|---|
| `web/modules/custom/xedc_member/src/Service/HistoryManager.php` | 浏览历史核心服务：记录/更新、开关、计数、分页查询、删除单条、清空、按节点/用户清理。 |
| `web/modules/custom/xedc_member/src/EventSubscriber/HistorySubscriber.php` | 监听 `kernel.request`，仅在登录会员访问正常 canonical 内容详情页时记录历史。 |
| `web/modules/custom/xedc_member/src/Form/HistorySettingsForm.php` | “浏览历史记录”开关表单。 |
| `web/modules/custom/xedc_member/src/Form/HistoryDeleteForm.php` | 单条历史删除表单，支持 AJAX 移除卡片。 |
| `web/modules/custom/xedc_member/src/Form/HistoryClearForm.php` | 清空全部历史的确认表单。 |
| `web/modules/custom/xedc_member/templates/xedc-member-history.html.twig` | 浏览历史页面：关闭提示、类型筛选、卡片列表、空状态、分页、清空入口。 |

### 1.2 第二阶段修改文件

| 文件 | 实际改动 |
|---|---|
| `web/modules/custom/xedc_member/xedc_member.install` | 新增 `xedc_member_history` Schema；拆分 favorite/history schema helper；新增 `xedc_member_update_10001()`；卸载时删除两张表。 |
| `web/modules/custom/xedc_member/xedc_member.services.yml` | 注册 `xedc_member.history_manager` 和 `xedc_member.history_subscriber`。 |
| `web/modules/custom/xedc_member/xedc_member.routing.yml` | `/member/history` 改为真实历史控制器；新增 `/member/history/clear` 确认表单路由。 |
| `web/modules/custom/xedc_member/xedc_member.module` | 注册历史模板变量；节点/用户删除时同时清理收藏和历史。 |
| `web/modules/custom/xedc_member/xedc_member.info.yml` | 描述更新为包含浏览历史。 |
| `web/modules/custom/xedc_member/src/Controller/MemberController.php` | 注入 `HistoryManager`；新增历史页、历史筛选/卡片、概览历史统计、设置页开关表单、清空 URL。 |
| `web/modules/custom/xedc_member/templates/xedc-member-card.html.twig` | 支持可选的 `card_id` 和 `meta`；历史卡片显示浏览次数。收藏卡片保持原有行为。 |
| `web/modules/custom/xedc_member/templates/xedc-member-overview.html.twig` | 浏览历史统计改为真实数量；从“即将接入”移除历史。 |
| `web/modules/custom/xedc_member/templates/xedc-member-settings.html.twig` | “隐私与记录”区域接入历史记录开关表单和说明。 |
| `web/modules/custom/xedc_member/css/member.css` | 新增关闭记录提示、开关表单、单条删除按钮、历史卡片 meta 样式；后续功能网格改为自适应。 |

### 1.3 未改动

- 未修改首页、搜索页、文章详情页或其他无关主题文件。
- 未重写第一阶段收藏功能；仅在共享控制器、卡片模板、概览和设置页上做必要扩展。
- 既有未提交工作保持原样：
  - `web/themes/custom/xedc/xedc.theme`
  - `web/themes/custom/xedc/xedc.libraries.yml`
  - `web/modules/custom/xa_views/`
  - `web/themes/custom/xedc/css/article-detail.css`
  - `web/themes/custom/xedc/js/article-detail.js`
  - 未跟踪的文章详情模板

---

## 2. 路由、权限、服务和模板

### 2.1 路由

| 路由名 | 路径 | 处理方式 | 访问要求 |
|---|---|---|---|
| `xedc_member.history` | `/member/history` | `MemberController::history` | `_user_is_logged_in: TRUE` |
| `xedc_member.history_clear` | `/member/history/clear` | `HistoryClearForm` | `_user_is_logged_in: TRUE` |

两个路由均设置：

```yaml
options:
  no_cache: TRUE
```

单条删除没有独立路由；由历史列表卡片内的 `HistoryDeleteForm` 提交到当前页面。

### 2.2 权限与用户隔离

- 没有新增自定义权限，也没有修改任何角色权限配置。
- 历史页和清空页要求登录。
- 记录订阅器只处理已登录且 `uid > 0` 的用户。
- `HistoryManager` 的查询和删除接口都以 `uid` 为必要参数：
  - `record($uid, $node)`
  - `countVisible($uid, $bundle)`
  - `getHistoryRows($uid, $bundle)`
  - `delete($uid, $nid)`
  - `clear($uid)`
- 控制器只传入当前用户 UID，不接受 URL 或表单中的其他 UID。
- 删除/清空表单提交时再次检查登录状态。
- 数据隔离依赖服务端 UID 条件，不依赖前端隐藏按钮。

### 2.3 服务

`xedc_member.services.yml` 实际内容：

```yaml
xedc_member.history_manager:
  class: Drupal\xedc_member\Service\HistoryManager
  arguments:
    - '@database'
    - '@datetime.time'
    - '@user.data'

xedc_member.history_subscriber:
  class: Drupal\xedc_member\EventSubscriber\HistorySubscriber
  arguments:
    - '@xedc_member.history_manager'
    - '@current_route_match'
    - '@current_user'
  tags:
    - { name: event_subscriber }
```

`HistoryManager` 实际方法：

- `isAllowedNode()`
- `isEnabled()`
- `setEnabled()`
- `record()`
- `countVisible()`
- `getHistoryRows()`
- `delete()`
- `clear()`
- `deleteForEntity()`
- `deleteForUser()`

### 2.4 模板

| 模板 | 实际用途 |
|---|---|
| `xedc-member-history.html.twig` | 历史页；读取 `items`、`filters`、`total`、`pager`、`enabled`、`urls`、`empty`。 |
| `xedc-member-card.html.twig` | 共享卡片；支持 `card_id`、`meta`，供历史卡片显示“浏览 N 次”。 |
| `xedc-member-overview.html.twig` | 概览页历史统计使用 `stats.history`。 |
| `xedc-member-settings.html.twig` | 设置页输出 `history_form`。 |
| `xedc-member-shell.html.twig` | 既有会员中心外壳；历史导航项已存在。 |

`xedc_member_theme()` 已注册 `xedc_member_history`，变量包括：

```text
items, filters, total, pager, enabled, urls, empty
```

---

## 3. 数据库 Schema 与表结构

表名：`xedc_member_history`  
定义位置：`xedc_member.install` 的 `xedc_member_history_schema()`。

| 字段 | 类型 | 约束/默认值 | 说明 |
|---|---|---|---|
| `hid` | serial | 主键 | 历史记录 ID |
| `uid` | int unsigned | not null，default 0 | 用户 UID |
| `entity_type` | varchar(32) | not null，default `node` | 当前固定为节点 |
| `entity_id` | int unsigned | not null，default 0 | 节点 ID |
| `bundle` | varchar(32) | not null，default 空字符串 | `photo`、`video`、`article` |
| `first_viewed` | int | not null，default 0 | 首次浏览时间戳 |
| `last_viewed` | int | not null，default 0 | 最近浏览时间戳 |
| `view_count` | int unsigned | not null，default 1 | 浏览次数 |

唯一约束：

```text
uid_entity (uid, entity_type, entity_id)
```

索引：

```text
uid_last_viewed (uid, last_viewed)
entity (entity_type, entity_id)
last_viewed (last_viewed)
```

### 3.1 已有安装的升级

新增：

```text
xedc_member_update_10001()
```

该 update hook：

- 检查 `xedc_member_history` 是否存在。
- 不存在时使用 Schema API `createTable()` 创建。
- 当前尚未执行。

### 3.2 当前数据库实际状态

本次只读检查结果：

```text
favorite=6 fields, history=8 fields
history_table=0
favorite_table=0
module=0
update_hook=yes
```

解释：

- Schema 定义存在，历史表有 8 个字段。
- `xedc_member_history` 表尚未创建。
- `xedc_member_favorite` 表也尚未创建。
- `xedc_member` 模块未启用。
- update hook 已定义，但未执行。

### 3.3 历史开关存储

- 使用 Drupal 核心 `user.data` 服务。
- key：`xedc_member.history_enabled`。
- 不需要新增配置、字段或表。
- 默认无值视为开启。
- 关闭后只阻止新记录；已有记录保留。

---

## 4. 浏览历史功能实现情况

### 4.1 登录会员浏览美图、视频、文章时记录历史

实际实现：`HistorySubscriber` 监听 `kernel.request`，优先级 0。

只有以下条件全部满足才记录：

1. 主请求，不是子请求。
2. HTTP 方法为 GET。
3. 不是 AJAX 请求。
4. 不包含 `_wrapper_format` 或 `_format`。
5. 路由名严格等于 `entity.node.canonical`。
6. 当前用户已登录且 `uid > 0`。
7. bundle 属于 `photo`、`video`、`article`。
8. 节点已发布。
9. 当前用户对节点有 `view` 权限。
10. 用户历史开关为开启状态（由 `HistoryManager::record()` 再次检查）。

因此不会记录列表页、后台页、预览页、修订页、AJAX、POST、JSON `_format` 请求或匿名访问。

状态：**已实现；尚未运行时验证。**

### 4.2 重复访问时更新时间，避免重复记录

实际实现：`HistoryManager::record()` 使用 Drupal `merge()`：

- 唯一匹配键：`uid + entity_type + entity_id`。
- 不存在时插入：
  - `bundle`
  - `first_viewed = 当前时间`
  - `last_viewed = 当前时间`
  - `view_count = 1`
- 已存在时更新：
  - `bundle`
  - `last_viewed = 当前时间`
  - `view_count = view_count + 1`
- `first_viewed` 保留首次浏览时间。
- 唯一键和 merge 共同避免重复行。
- 数据库异常会被捕获并记录日志，避免影响内容详情页。

状态：**已实现；尚未运行时验证。** 由于表未创建，没有实际执行写入测试。

### 4.3 我的浏览历史列表、分类筛选和分页

实际实现：

- 路由 `/member/history` 由 `MemberController::history()` 处理。
- 支持 `?type=photo`、`?type=video`、`?type=article`。
- 只接受 `HistoryManager::ALLOWED_BUNDLES` 中的值；其他值按“全部”处理。
- 筛选标签：全部、美图、视频、文章。
- 使用 `PagerSelectExtender`，每页 12 条。
- 模板输出 `['#type' => 'pager']`。
- 每张卡片使用共享卡片模板，显示真实标题、封面、类型、最近浏览时间、浏览次数和详情链接。
- 空状态区分“全部无记录”和“当前分类无记录”。
- 分页越界时由 Drupal pager 返回空结果，页面显示空状态。

状态：**已实现；Twig/路由静态检查通过；尚未浏览器验证。**

### 4.4 删除单条记录

实际实现：`HistoryDeleteForm`

- 每个历史卡片内嵌“删除”按钮。
- 表单只提交隐藏的 `nid`，不提交 UID。
- 服务端按当前用户 UID + nid 删除。
- Form API 自动提供 CSRF 保护。
- AJAX 成功后：
  - `RemoveCommand` 移除 `#xedc-member-history-{nid}` 卡片。
  - `MessageCommand` 显示删除成功消息。
- 非 AJAX 提交后重定向回当前历史页并显示消息。
- 重复提交不会影响其他用户，也不会删除其他用户数据。

状态：**已实现；PHP/类加载检查通过；尚未运行时验证。**

### 4.5 清空历史

实际实现：`HistoryClearForm`

- 路由 `/member/history/clear`。
- 使用 `ConfirmFormBase`，需要确认。
- Form API 提供 CSRF 保护。
- 只清空当前用户 UID 的全部历史。
- 成功后重定向回 `/member/history`，提示清空数量。
- 不删除收藏、评论或其他用户数据。

状态：**已实现；PHP/YAML/类加载检查通过；尚未运行时验证。**

### 4.6 开启或关闭浏览历史记录

实际实现：`HistorySettingsForm`，嵌入 `/member/settings`。

- 复选框：`history_enabled`。
- 默认值来自 `HistoryManager::isEnabled()`。
- 默认无值时开启。
- 关闭后写入 `user.data` 的 `history_enabled = 0`。
- 设置页明确提示：
  - 关闭后不再记录新的浏览行为。
  - 已有历史会保留。
  - 可以在浏览历史页面删除单条或清空全部。
- 历史页在关闭状态下显示提示，并仍保留列表、删除和清空能力。

状态：**已实现；PHP/服务注入检查通过；尚未运行时验证。**

### 4.7 用户权限隔离

实际实现：

- 历史路由要求登录。
- 订阅器只处理当前登录用户。
- 所有查询/删除强制当前 UID。
- 不接受外部 UID 参数。
- 表单只提交 nid，服务端使用当前 UID。
- 删除/清空表单均使用 Form API。
- 没有新增自定义权限或放宽现有权限。

状态：**已实现；尚未用两个真实账号做运行时隔离测试。**

### 4.8 未发布、已删除和无权访问内容处理

实际实现：

- `HistoryManager::baseQuery()` 条件：
  - `h.uid = 当前用户`
  - `h.entity_type = 'node'`
  - `h.bundle IN ('photo','video','article')`
  - JOIN `node_field_data`
  - `n.default_langcode = 1`
  - `n.status = 1`
- 控制器加载节点后再次执行 `$node->access('view')`。
- 已删除、未发布或当前用户无权访问的内容不会输出标题、封面或链接。
- 如果历史行仍存在但内容不可见，该行不会显示；用户仍可通过“清空历史”删除全部旧记录。
- `countVisible()` 使用与列表相同的发布状态和内容类型条件。
- 当前站点没有额外 node access 模块；未来若增加访问控制模块，需要复核计数与列表过滤的一致性。

状态：**已实现；尚未运行时验证。**

### 4.9 缓存和 CSRF

缓存：

- 历史路由：`no_cache: TRUE`。
- 会员中心外壳：`#cache` 使用 `user` 上下文，`max-age: 0`。
- 删除表单：`#cache` 使用 `user` 上下文，`max-age: 0`。
- 设置页开关表单：`#cache` 使用 `user` 上下文，`max-age: 0`。
- 会员中心和用户资料/编辑路由继续输出 `noindex, nofollow, noarchive`。
- 记录逻辑在请求级执行，不依赖内容渲染缓存。

CSRF：

- `HistorySettingsForm`：Form API。
- `HistoryDeleteForm`：Form API。
- `HistoryClearForm`：`ConfirmFormBase` + Form API token。
- 没有自行拼接无 token 的写接口。

状态：**代码已实现；尚未做实际 HTTP/浏览器验证。**

---

## 5. 已实现、已测试、尚未验证

| 功能 | 已实现 | 已测试 | 尚未验证 |
|---|---|---|---|
| 历史表 Schema | 是 | 字段/唯一键/索引检查通过 | 表未创建 |
| `HistoryManager` 服务 | 是 | 语法、类加载、只读方法检查 | 实际 DB 写入/查询 |
| 请求记录订阅器 | 是 | 类加载、事件注册检查 | 真实详情页触发 |
| 重复访问更新 | 是 | 代码检查 | merge 实际执行 |
| 历史列表 | 是 | Twig/路由静态检查 | 页面渲染 |
| 分类筛选 | 是 | 代码检查 | 页面行为 |
| 分页 | 是 | 代码检查 | 页面行为 |
| 单条删除 | 是 | 语法/类加载 | AJAX/表单实际提交 |
| 清空历史 | 是 | 语法/路由/类加载 | 确认表单实际提交 |
| 历史开关 | 是 | 语法/服务注入 | 保存、关闭后不记录 |
| 用户隔离 | 是 | 代码检查 | 两个真实账号测试 |
| 未发布内容隐藏 | 是 | 查询条件代码检查 | 真实数据验证 |
| 缓存/CSRF | 是 | 代码检查 | HTTP/浏览器验证 |
| 后台/预览/AJAX 不记录 | 是 | 订阅器条件代码检查 | 真实请求验证 |
| PC/移动端样式 | 是 | CSS 代码检查 | 浏览器响应式验收 |

---

## 6. 实际执行的检查命令及结果

### 6.1 PHP 语法检查

```bash
find web/modules/custom/xedc_member -type f \
  \( -name '*.php' -o -name '*.module' -o -name '*.install' \) \
  -print0 | xargs -0 -n1 php -l
```

实际结果：

```text
No syntax errors detected in .../xedc_member.install
No syntax errors detected in .../src/Controller/MemberController.php
No syntax errors detected in .../src/Form/HistoryClearForm.php
No syntax errors detected in .../src/Form/HistorySettingsForm.php
No syntax errors detected in .../src/Form/FavoriteToggleForm.php
No syntax errors detected in .../src/Form/HistoryDeleteForm.php
No syntax errors detected in .../src/Service/FavoriteManager.php
No syntax errors detected in .../src/Service/HistoryManager.php
No syntax errors detected in .../src/EventSubscriber/HistorySubscriber.php
No syntax errors detected in .../xedc_member.module
```

结论：**通过。**

### 6.2 YAML 语法检查

```bash
vendor/bin/yaml-lint \
  web/modules/custom/xedc_member/xedc_member.info.yml \
  web/modules/custom/xedc_member/xedc_member.routing.yml \
  web/modules/custom/xedc_member/xedc_member.services.yml \
  web/modules/custom/xedc_member/xedc_member.libraries.yml
```

实际结果：

```text
[OK] All 4 YAML files contain valid syntax.
```

结论：**通过。**

### 6.3 Twig 语法检查

```bash
php -r 'require "vendor/autoload.php";
  $loader = new \Twig\Loader\FilesystemLoader(["web/modules/custom/xedc_member/templates"]);
  $twig = new \Twig\Environment($loader);
  foreach (glob("web/modules/custom/xedc_member/templates/*.twig") as $f) {
    $name = basename($f);
    $twig->parse($twig->tokenize($loader->getSourceContext($name)));
    echo "OK $name\n";
  }'
```

实际结果：

```text
OK xedc-member-card.html.twig
OK xedc-member-favorites.html.twig
OK xedc-member-history.html.twig
OK xedc-member-overview.html.twig
OK xedc-member-placeholder.html.twig
OK xedc-member-settings.html.twig
OK xedc-member-shell.html.twig
```

结论：**通过；仅 Twig 语法解析，不是 Drupal 运行时渲染。**

### 6.4 Schema、模块和表状态检查

只读执行：

```text
favorite=6 fields, history=8 fields
history_table=0
favorite_table=0
module=0
update_hook=yes
```

同时检查历史 Schema：

```text
history fields=hid,uid,entity_type,entity_id,bundle,first_viewed,last_viewed,view_count
unique={"uid_entity":["uid","entity_type","entity_id"]}
indexes={"uid_last_viewed":["uid","last_viewed"],"entity":["entity_type","entity_id"],"last_viewed":["last_viewed"]}
```

结论：**Schema 定义通过检查；表未创建，模块未启用。**

### 6.5 类加载检查

```text
Drupal\xedc_member\Service\FavoriteManager: OK
Drupal\xedc_member\Service\HistoryManager: OK
Drupal\xedc_member\EventSubscriber\HistorySubscriber: OK
Drupal\xedc_member\Form\FavoriteToggleForm: OK
Drupal\xedc_member\Form\HistorySettingsForm: OK
Drupal\xedc_member\Form\HistoryDeleteForm: OK
Drupal\xedc_member\Form\HistoryClearForm: OK
Drupal\xedc_member\Controller\MemberController: OK
```

结论：**通过。**

### 6.6 服务层只读功能抽查

`HistoryManager::isAllowedNode()` 和 `isEnabled()`：

```text
nid=1 bundle=photo published=1 allowed=1
nid=2 bundle=photo published=1 allowed=1
nid=44 bundle=photo published=0 allowed=0
uid1_enabled=1
```

结论：

- 已发布 photo 允许记录。
- 未发布 photo 拒绝记录。
- 用户 1 默认历史开关为开启。
- 这是只读检查，不是实际写入。

### 6.7 订阅器事件注册检查

```text
Array
(
    [kernel.request] => Array
        (
            [0] => onRequest
            [1] => 0
        )
)
```

结论：订阅器注册到 `kernel.request`，优先级 0。

### 6.8 历史卡片只读检查

通过反射调用 `MemberController::historyCard()`，传入真实节点 1 和模拟历史行：

```text
card_id=xedc-member-history-1
type=photo
date=2025-06-15 23:06
meta=浏览 3 次
cover=yes
```

结论：历史卡片字段、日期格式、浏览次数文案和封面解析逻辑可用；**不是浏览器渲染测试**。

### 6.9 Git 空白检查

```bash
git diff --check
```

实际结果：退出码 0，无空白错误。

### 6.10 未执行的功能测试

以下测试**尚未执行**：

- 启用模块后的路由访问。
- 真实详情页触发记录。
- `merge()` 插入/更新、`view_count` 递增、`first_viewed` 保留。
- 两个会员账号之间的历史隔离。
- 历史列表筛选、分页、空状态的实际页面行为。
- 单条删除 AJAX 卡片移除和消息提示。
- 清空历史确认表单。
- 设置页开关保存、关闭后不再记录、旧记录保留。
- 未发布/已删除内容隐藏。
- CSRF、缓存隔离、noindex 的实际 HTTP 验证。
- PC/移动端浏览器布局。

---

## 7. 模块、数据库和缓存状态

### 7.1 模块

- `xedc_member` **未启用**。
- `module=0`。
- active config 中未出现 `xedc_member`。
- 未执行 `drush en xedc_member`。

### 7.2 数据库

- `xedc_member_history` 表**未创建**。
- `xedc_member_favorite` 表**未创建**。
- 未执行 `drush updb`。
- 未执行 update hook 10001。
- 未执行任何数据库写入或结构修改。

### 7.3 缓存

- 未执行 `drush cr`。
- 未执行模块启用引发的缓存重建。
- 未执行主题构建或部署。

### 7.4 配置

- 未执行 `drush cim`。
- 未执行 `drush cex`。
- 未修改 `config/sync`。
- 启用模块后 active config 会增加 `xedc_member`，但本阶段按约束未导出。

---

## 8. 仍需执行的操作和准确命令

### 8.1 当前环境：模块尚未启用

当前环境应先启用模块；`hook_schema()` 会创建 `xedc_member_favorite` 和 `xedc_member_history` 两张表。

```bash
vendor/bin/drush en xedc_member -y
```

模块启用通常会触发容器、路由和缓存重建。如需显式重建：

```bash
vendor/bin/drush cr
```

### 8.2 已启用过第一阶段模块的环境

如果某个环境已经启用过 `xedc_member`，但还没有历史表，则需要运行 update hook：

```bash
vendor/bin/drush updb -y
vendor/bin/drush cr
```

### 8.3 启用后的只读状态验证

```bash
vendor/bin/drush php:eval '
  echo "module=" . (int) \Drupal::moduleHandler()->moduleExists("xedc_member") . "\n";
  echo "history_table=" . (int) \Drupal::database()->schema()->tableExists("xedc_member_history") . "\n";
  echo "favorite_table=" . (int) \Drupal::database()->schema()->tableExists("xedc_member_favorite") . "\n";
'
```

预期：

```text
module=1
history_table=1
favorite_table=1
```

### 8.4 前台验收步骤

1. 使用普通会员账号登录。
2. 访问一个已发布的 `photo`、`video`、`article` 详情页。
3. 重复访问同一详情页。
4. 打开 `/member/history`：
   - 应只出现一条该内容记录。
   - `last_viewed` 应更新。
   - `view_count` 应递增。
5. 测试全部/美图/视频/文章筛选。
6. 测试分页和空状态。
7. 删除单条记录，确认卡片移除或页面刷新后消失。
8. 打开 `/member/history/clear`，确认清空全部。
9. 在 `/member/settings` 关闭“记录我的浏览历史”：
   - 再访问新的详情页，不应新增记录。
   - 旧历史仍应保留并可删除/清空。
10. 重新开启历史，确认恢复记录。
11. 使用两个会员账号验证互相看不到对方历史。
12. 访问未发布/已删除内容，确认历史页不泄露标题或封面。

### 8.5 不要执行

在本阶段未确认前，不要执行：

```text
drush cim
drush cex
数据库重置
部署
```

尤其不要用配置导入覆盖现有未提交配置/功能。

---

## 9. 错误、风险和未解决问题

### 9.1 当前错误

- 本次静态检查未发现 PHP/YAML/Twig/Schema/类加载错误。
- 没有执行运行时功能测试，因此不能声称“功能运行通过”。

### 9.2 风险与未解决问题

1. **模块未启用**：所有历史页面和写入行为尚未运行时验收。
2. **表未创建**：历史页查询表缺失会导致运行时错误；必须先启用模块或执行 `updb`。
3. **记录写入未实测**：`merge()` 的实际插入/更新行为尚未在真实请求中验证。
4. **两账号隔离未实测**：代码强制 UID，但还没有两个真实账号的隔离测试。
5. **无自动过期清理**：没有 `hook_cron()` 保留期限清理，历史会持续累积。
6. **AJAX 删除后的总数不实时更新**：单条删除会移除卡片，但页面顶部的总数和 pager 数字要刷新后才更新。
7. **多语言限制**：历史列表 JOIN 使用 `default_langcode = 1`，只覆盖默认翻译。
8. **访问控制扩展风险**：`countVisible()` 只按发布状态和内容类型计数；未来增加 node access 模块时，需要复核计数和列表访问过滤的一致性。
9. **事件记录范围**：任何具有节点查看权限的登录用户（包括管理员/编辑）访问 canonical 详情页都会记录；如果产品要求排除管理员，需要额外判断。
10. **重复刷新**：同一用户反复刷新详情页会增加 `view_count` 和写库次数，但不会新增重复行；当前没有节流。
11. **匿名直接访问历史页**：预计返回 403，而不是登录页跳转；本阶段未改变该行为。
12. **配置同步差异**：既有 `config/sync` 与实际同步目录不一致；启用模块后 active config 差异会扩大，未执行 `cex`。
13. **卸载风险**：`hook_uninstall()` 会删除两张表，收藏和历史数据会丢失；仅禁用模块不会删除表。
14. **浏览器/移动端未验收**：PC 两栏和移动端单列只做了 CSS 代码检查。
15. **主题构建未执行**：本阶段只改模块 CSS，不涉及主题 SCSS 构建。

---

## 10. 结论

- 第二阶段浏览历史代码已完成：Schema、服务、请求级记录、历史列表、筛选、分页、单条删除、清空、记录开关、概览统计、设置页和样式。
- 静态检查通过：PHP 语法、YAML、Twig 语法、Schema 字段/唯一键/索引、类加载、订阅器事件注册、服务层只读抽查、历史卡片只读构造。
- **尚未完成运行时验收**：模块未启用、历史表未创建、真实记录/页面/AJAX/CSRF/两账号隔离/缓存行为尚未验证。
- **未执行**数据库更新、缓存重建、模块启用、配置导入、配置导出、部署或主题构建。
- 既有未提交改动全部保留；本阶段只修改会员中心模块，未改动无关页面。
- 本阶段停止，不进入第三阶段评论功能。

报告保存路径：`/var/www/drupal/MEMBER-STAGE2-REPORT.md`
