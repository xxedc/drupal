# 后台界面简体中文翻译

站点默认语言是简体中文。本次只补界面翻译（locale），没有改内容翻译，也没有改 `xedc_auto_translate` 的翻译逻辑。已有中文译文未覆盖：导入全部使用 `--override=none`，原先 11 条自定义译文保持不变。品牌名 DcLili 未翻译。

## 翻译方法

1. `drush locale:check`：已登记项目的官方语言包均为最新，没有可更新文件。
2. 对 info.yml 里没有 `project`/`version`、因此不会自动下载语言包的贡献模块，从 `ftp.drupal.org` 导入官方 `.po`（`gin`、`gin_toolbar`、`matomo`、`smtp`、`redirect`、`mailsystem`、`audit`、`site_audit`，以及核心 `drupal-11.x` 快照）。
3. `drush locale:export zh-hans --types=not-translated` 导出仍无译文的字符串，译成简体中文后写入 `translations/zh-hans.admin-ui.po`，再 `drush locale:import`。
4. 占位符（`@`、`%`、`:`、`[token]`）、HTML 标签、`DcLili`、`XEDC` 在翻译时保留。PHP 日期格式按中文习惯改为 `Y年n月j日` 这类格式串，而不是把格式字符翻成词语。
5. `drush cr`。导入时 Locale 顺带更新了 24 个仍使用英文源文的配置对象。

导入结果：界面译文从 10249 条增加到 15179 条（新增约 4930 条，其中官方包约 167 条，其余来自本次补译）。0 条被更新，11 条自定义译文未变。

## 已处理模块与译文示例

自定义模块的用户可见文案大多已经直接写在 `t()` / `@Translation` 里，本次只补仍是英文的说明和权限名：

| 模块 | 示例 |
| --- | --- |
| xedc_member | `XEDC Member` 的说明 →「XEDC 会员中心，包括收藏、浏览历史、个人资料、评论和投稿。」 |
| xedc_moderation | 「为待审内容列表提供批量审核操作。」 |
| xedc_home | 视图缓存插件 `Bundle list tag` →「按内容类型的列表缓存」 |
| xedc_auto_translate、xedc_tags、xedc_quick、xedc_models、xa_views | 名称与说明里的英文产品名保留，其余说明原本就是中文，未改写 |

核心与已安装贡献模块（导航、Gin、Metatag、Schema.org Metatag、Pathauto、Redirect、SMTP、Mail System、Matomo、Simple XML Sitemap、Token、Audit、Site Audit、Views Bulk Operations 等）补的是官方语言包没收录的字符串。后台常用文案示例：

- Navigation settings → 导航设置
- Administrative top bar → 管理顶栏
- More actions → 更多操作
- Add and install modules to extend site functionality. → 添加并安装模块以扩展站点功能。
- Manage navigation blocks. → 管理导航区块。
- Africa/Cairo → 非洲/开罗
- Path pattern → 路径模式
- Configure audit settings and manage analyzer options. → 配置审计设置并管理分析器选项。

Drupal 术语按社区习惯统一：Block → 区块，pattern → 模式，field → 字段，workflow → 工作流。

## 验证

`drush cr` 之后用一次登录链接打开后台（界面语言为简体中文），页面标题如下：

| 路径 | 标题 |
| --- | --- |
| `/admin` | 管理 |
| `/admin/content` | 内容 |
| `/admin/structure` | 结构 |
| `/admin/modules` | 扩展 |
| `/admin/people` | 人员 |
| `/admin/people/permissions` | 权限 |
| `/admin/config` | 配置 |
| `/admin/config/system/site-information` | 网站基本设置 |
| `/admin/config/regional/xedc-auto-translate` | 自动翻译 |
| `/admin/appearance` | 外观 |
| `/admin/reports/status` | 状态报告 |

`t()` 抽查：`Navigation settings`、`Save`、`Content`、审核批量操作说明、会员中心模块说明均为中文。权限页上 Audit 的三条权限说明已显示中文。网站基本设置页正文里没有成段英文。

## 仍无法翻译或故意保留的部分

仍有约 363 条源字符串没有 zh-hans 译文，原因如下：

- **令牌必须原样保留**：`[site:name]`、`[node:title]` 等整句就是替换令牌，译掉会破坏 Pathauto / Metatag。
- **源文已经是中文**：例如「上传的视频不是有效的 MP4 文件。」「关于 DcLili」。界面直接显示源文，不再写一条机器译文盖掉作者原文。
- **扩展页上的模块名称**：Drupal 11 的模块列表把 `.info.yml` 的 `name` 当作 `#markup` 输出，不经过 `t()`。因此「Content Moderation」「Block Content」「XEDC Member」等名称仍是英文。同一页的模块**说明**会走 `t()`，已经是中文。依赖关系列表里的模块名同样来自未翻译的 `name`。
- **代码、命令、URL、协议名**：`phpcs`、`composer require`、Schema.org 属性名等保留英文；属性名另加了中文说明（如「标题（headline）」）。
- **8 条帮助文字**第一次导入时因 HTML 不被 Locale 允许（`<script>`、`<embed>`、`<meta>` 等）被跳过，已改成允许的标签后重新导入。
- **未包在 `t()` 里的硬编码**：自定义模块里面向用户的句子基本已用中文 `t()`。未走 `t()` 的字符串 Locale 无法接管，本次没有为了翻译去改业务代码。
