# XEDC 会员中心第五阶段报告：整体 UI/UX 优化与功能完善

> 项目目录：`/var/www/drupal`  
> 报告日期：2026-10-24  
> 阶段范围：会员中心 PC/移动端间距、收藏/历史封面、整体视觉层级、按钮系统、个人资料页和响应式回归。  
> 本阶段未执行 `git reset`、`git clean`、`drush cim`、`drush cex`、模块卸载、数据库结构修改、批量图片重生成或部署。

## 1. 执行摘要

- 会员中心已与站点现有列表页 `/meitu`、`/articles` 使用同一容器宽度和左右边距：
  - 1440px：会员中心内容区 x=192、宽 1056，与 `/meitu` 内容区完全一致。
  - 1024px：x=12、宽 1000。
  - 768px：x=12、宽 744。
  - 390px：x=12、宽 366。
- 收藏/历史封面从 `medium`（220×220）改为 `max_650x650` / `max_1300x1300` 的 1x/2x `srcset`；卡片比例从 4:3 改为 3:4；不再加载原图。
- 会员中心减少边框和嵌套卡片：侧栏、导航、统计、面板、评论/投稿列表、空状态改为留白、分隔和单一表面分组。
- 修复按钮根因：
  - 主要链接按钮黑底黑字、不可读。
  - 历史删除按钮被主题 `btn-primary` 渲染成黑色主按钮。
  - 表单按钮被高特异性基础规则覆盖。
  - 头像上传按钮 `.js-hide` 被错误显示。
  - 清空历史确认页按钮和问题标题缺失。
- 个人资料页重新组织头像/资料/表单，新增“返回会员中心”取消入口、文件选择按钮样式和头像移除按钮样式。
- 真实浏览器测试覆盖会员 8 个页面、清空历史确认页、桌面/平板/手机、分页、收藏/历史 AJAX、资料保存、头像上传/移除和权限隔离。

## 2. 问题根因

### 2.1 左右间距不一致

会员中心 `.xm` 位于主题 Bootstrap `.container` 内：

- `.container` 最大宽度 1080px，左右 padding 12px。
- 原 `.xm` 又有 `max-width: 1120px` 和 `padding: 24px 16px 64px`。
- 桌面端外层已经落在 1080px 容器内，`.xm` 再缩进 16px；移动端形成 `12px + 16px = 28px` 的双重左右留白。
- 结果：会员中心内容比 `/meitu`、`/articles` 的列表内容窄约 32px，手机上留白明显偏大。

### 2.2 封面模糊和比例不协调

`MemberController::coverUrl()` 使用 `medium` 图片样式（最大 220×220）：

- 竖图 924×2000 经 `medium` 后只有约 102×220 或 220×220。
- 卡片原先把图片强制放入 4:3 容器，并用 `object-fit: cover` 放大，造成明显模糊和裁切。
- 没有 `srcset`，高 DPR 屏幕仍使用同一张小图。
- 没有利用项目已有的 `max_650x650`、`max_1300x1300` 图片样式。

### 2.3 视觉零散和边框过多

原样式对侧栏用户卡、导航、统计卡、面板、账户信息、快捷链接、空状态、评论、投稿都使用了独立边框或背景盒子。页面被切成多个小盒子，视觉层级主要依赖边框，而不是留白和标题层级。

### 2.4 按钮异常黑色

根因不是单一按钮颜色，而是三处叠加：

1. `.xm a { color: inherit; }` 的优先级高于 `.xm-btn--primary`，导致黑色主按钮上的文字仍为黑色。
2. 主题 `input--submit.html.twig` 给所有提交按钮加 `btn btn-primary`；历史删除按钮没有独立的危险样式，被渲染成黑色主按钮。
3. 基础按钮选择器包含 `input[type=submit]`，其属性选择器特异性高于 `.xm .btn-primary` 和 `.xm .xedc-history-delete-btn`，覆盖了主按钮/危险按钮颜色。
4. 头像上传按钮带 `.js-hide`，但基础按钮的 `display` 规则使其重新显示。
5. 清空历史确认页没有加载会员中心 CSS，且页面标题被 `.xm-page` 隐藏，导致确认问题和危险按钮样式缺失。

## 3. 解决方案

### 3.1 间距和容器

- `.xm` 改为填满父级 `.container`：`width:100%; max-width:none; padding:20px 0 56px;`。
- 桌面/移动端左右边距完全由主题 Bootstrap `.container` 控制，不再创建第二套容器规范。
- 侧栏从 240px 调整为 232px，主内容区在 1440px 下为 796px。
- 断点改为与站点列表页一致：1024px 以上双列，1024px 以下单列。
- 手机端仅保留 `.container` 的 12px 左右边距，不再叠加 `.xm` 的 16px。

### 3.2 封面图

- Controller 新增 `coverImage()`，返回 `src`、`srcset`、`alt`。
- 使用项目已有图片样式：
  - 1x：`max_650x650`
  - 2x：`max_1300x1300`
- 输出 `srcset="... 1x, ... 2x"`，浏览器按 DPR 自动选择；实测 1x 选择 `max_650x650`，2x 选择 `max_1300x1300`。
- 卡片媒体容器改为 `aspect-ratio: 3 / 4`，保持 `object-fit: cover`，不拉伸。站点图片列表使用 9:16，首页文章卡使用 16:9，类型比例并不统一；会员收藏/历史是混合内容，按任务建议采用竖向 3:4，保持卡片整齐和统一。
- 继续使用 `loading="lazy"`、`decoding="async"`。
- 缺失封面使用类型占位，不输出破损图片。
- 未批量重新生成图片样式，未删除旧文件；Drupal 按需生成派生图。
- 说明：原图本身分辨率过低的封面无法通过样式变得清晰；本阶段只保证不把 220px 小图放大到 4:3 卡片。

### 3.3 视觉层级

- 侧栏用户卡改为浅色表面，无边框；导航去除外框，使用激活项浅色背景。
- 统计区改为一个浅色分组表面，内部用分隔线，不再四个独立边框卡片。
- `.xm-panel` 去除边框和背景，改用标题、留白和区块分隔线。
- 账户信息改为一个浅色信息带，不再每个字段一个边框盒子。
- 快捷链接改为分隔线列表，不再每行一个完整边框卡片。
- 评论/投稿改为扁平列表行，使用底部细分隔线，不再每项一张卡片。
- 空状态改为浅色表面，不再使用虚线边框。
- 保留收藏/历史内容卡片的轻边框，与站点图片列表卡片保持一致。
- 资料页去掉左侧资料卡和右侧表单卡的边框，形成单一资料布局。

### 3.4 按钮系统

在 `.xm` 作用域内统一：

- 主要操作：深色背景 + 白字（`xm-btn--primary`、`btn-primary`）。
- 次要操作：白底 + 深色文字 + 边框（`xm-btn`、默认表单按钮）。
- 危险操作：白底红字红边（历史删除）；确认页清空按钮为红底白字。
- 悬停、键盘焦点、禁用状态分别定义。
- 收藏按钮：白底深色文字，已收藏为浅灰底和深色边框。
- 头像上传/移除按钮：次要样式，不再显示为黑色主按钮。
- 修复 `.js-hide` 上传按钮被基础规则重新显示的问题。
- 修复基础 `input[type=submit]` 选择器特异性过高的问题，改用 `:where()` 降低基础输入按钮权重。
- 清空历史确认页加载会员中心 CSS，恢复页面问题标题，并把确认按钮设为危险样式。
- 所有规则限定在 `.xm` / `.xm-page` / `.xm-confirm-form`，没有全局 `button { ... }` 覆盖，不影响后台、登录注册和其他页面。

### 3.5 个人资料页

- 左侧资料栏改为 230px，展示“当前头像”、头像、用户名、邮箱、注册时间和昵称。
- 邮箱字体调整，避免桌面端出现不必要断行。
- 表单保持昵称/简介/头像字段和原有服务端验证、CSRF、访问控制。
- 文件选择按钮使用主题按钮样式；“移除”头像按钮为次要样式。
- 新增“返回会员中心”取消链接，和保存按钮在同一操作行。
- 移动端头像与资料横向排列，表单字段全宽，保存/取消按钮不溢出。
- 未修改用户字段机器名、数据库结构或真实用户资料。

## 4. 修改文件

| 文件 | 改动 |
|---|---|
| `web/modules/custom/xedc_member/src/Controller/MemberController.php` | 新增 `coverImage()`；使用 `max_650x650` / `max_1300x1300` 和 1x/2x `srcset`。 |
| `web/modules/custom/xedc_member/templates/xedc-member-card.html.twig` | 输出响应式封面 `srcset`、`alt`、`decoding`；缺失封面占位。 |
| `web/modules/custom/xedc_member/templates/xedc-member-profile.html.twig` | 增加“当前头像”标签和头像操作说明。 |
| `web/modules/custom/xedc_member/templates/xedc-member-history.html.twig` | “清空历史”改为危险样式。 |
| `web/modules/custom/xedc_member/src/Form/ProfileForm.php` | 新增“返回会员中心”取消链接和操作行包装；保留原有保存/验证逻辑。 |
| `web/modules/custom/xedc_member/src/Form/HistoryClearForm.php` | 加载会员中心样式，增加确认页表单类和危险按钮类。 |
| `web/modules/custom/xedc_member/xedc_member.module` | 为清空历史确认页增加 `xm-page--confirm` 页面类，恢复确认问题标题。 |
| `web/modules/custom/xedc_member/css/member.css` | 统一容器、间距、卡片比例、视觉层级、按钮、表单、分页、消息和响应式规则。 |
| `MEMBER-STAGE5-UI-REPORT.md` | 本报告。 |
| `PROJECT-STATUS.md` | 更新阶段 5 UI/UX 状态和风险。 |

未修改：

- `config/sync`、`settings.php`、服务器 Nginx/PHP-FPM。
- 主题 SCSS/JS 源文件、主题构建产物（构建尝试后已恢复执行前状态）。
- 用户字段机器名、数据库结构、真实用户数据。

## 5. 测试结果

### 5.1 静态检查

```text
PASS | xedc_member 全部 PHP 文件 php -l
PASS | xedc_member 相关 Twig 编译
PASS | stylelint member.css（0 errors）
PASS | git diff --check
PASS | drush updatedb:status = 无待执行更新
PASS | drush config:status = 24 项（与 UI 阶段前一致，无新增配置差异）
```

主题构建：

```text
npm run build 执行完成，但生成与本次无关的 tracked build 产物全量差异；
已从执行前备份恢复 build/，当前 git status 中 build/ 无差异。
会员中心样式是模块独立 CSS，不依赖该构建。
```

### 5.2 真实浏览器测试

使用 Playwright + Chromium，对本地 `gitxx.xyz`（127.0.0.1）测试：

```text
PASS | 1440px、1024px、768px、390px 下 9 个会员页面 200 且无横向溢出
PASS | 会员中心内容区与 /meitu 内容区 x/宽完全一致（4 个断点）
PASS | 收藏/历史桌面 4 列、手机 2 列；360px 2 列；320px 1 列
PASS | 封面 3:4；1x 使用 max_650x650，2x 使用 max_1300x1300
PASS | 不加载原图；缺失封面显示占位、无破图
PASS | 主要链接按钮黑底白字
PASS | 次要按钮白底深色文字
PASS | 历史删除红色危险样式；清空确认页红底白字
PASS | 清空历史确认问题标题恢复显示
PASS | 按钮 hover/focus/disabled 状态
PASS | 收藏 AJAX 添加/列表显示/移除
PASS | 历史 AJAX 单条删除
PASS | 清空历史功能和确认页
PASS | 资料保存、头像上传、头像移除、取消链接
PASS | 设置页历史记录开关保存
PASS | 评论编辑页主按钮可读
PASS | 分页：收藏 12/9，历史 12/8，激活页深色
PASS | 会员访问 /admin/content/moderated = 403
PASS | 匿名访问 /member = 403
```

### 5.3 未执行/未覆盖

- 真实手机和 Safari/Firefox 测试未执行；本轮使用 Chromium 响应式模拟。
- 暗色主题未专项验收。
- 管理员后台、登录/注册页未做视觉回归（本阶段规则均限定在会员中心作用域）。
- 未进行生产部署、多用户并发或生产环境压测。
- 低分辨率原图无法通过样式变清晰；未批量替换原图或重新生成全部图片。
- 安全页部分 Drupal 核心英文提示（如密码说明、Matomo 设置）仍存在，属于既有本地化/贡献模块范围，未在本阶段改动。

## 6. 数据清理

测试用户 `s5check_member`、临时草稿/无封面文章、测试评论、收藏、历史和上传头像已清理。

最终核对：

```text
[S5CHECK] 节点残留 = 0
[S5CHECK] 评论残留 = 0
s5check_ 用户残留 = 0
文章已发布 = 11，page = 4，photo = 39/2，video = 6
全站评论 = 47
uid 2 收藏 = 2
uid 2 历史 = 5（会话期间存在真实浏览活动，清理未触碰 uid 2）
```

## 7. 遗留风险

1. 媒体文件仍为 public，未审核节点媒体可通过公开 URL 访问；属于基础设施/私有文件方案，未在本阶段处理。
2. PHP-FPM 上传上限 64MB，低于视频字段配置的 200MB。
3. `config/sync` 与运行同步目录仍有 24 项差异，不能直接 `cim`。
4. `article`、`video` 仍无评论字段。
5. `content_editor` 权限较大，含 `administer nodes`、`bypass node access`。
6. 空 `workflows.workflow.editorial` 仍存在。
7. 真实手机、跨浏览器、暗色主题未验收。
8. 原图分辨率不足时封面仍会偏软；不应通过加载原图解决。

## 8. 结论和停止点

- 第五阶段 UI/UX 目标已完成：间距统一、封面清晰度和比例改善、视觉简化、按钮修复、资料页优化、响应式回归通过。
- 会员功能、权限和真实数据未被破坏；测试数据已清理。
- 本阶段未修改配置、数据库结构或部署环境。
- 完成后停止，不进入第六阶段。
