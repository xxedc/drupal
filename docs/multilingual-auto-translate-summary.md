# 多语言与自动翻译

默认语言仍是简体中文（`zh-hans`，URL 无前缀）。英语、俄语、日语使用前缀 `/en`、`/ru`、`/ja`。品牌名 DcLili 未翻译。

## 本次改动

- 自动翻译从 Google Cloud Translation 改为 Microsoft Translator 与 DeepL，在 `/admin/config/regional/xedc-auto-translate` 选择其中一个。中文内容首次发布时仍生成 en / ru / ja，默认不覆盖已有译文。API Key 只进 State。
- 桌面语言切换在登录左侧，并与右边缘留出间距；按钮只显示当前语言，点击展开。移动端在抽屉底部，同样点击展开，不再平铺。

## 已启用的模块与语言

已启用（本次前已在站点中）：`language`、`locale`、`content_translation`、`config_translation`。

本次新增并启用：`xedc_auto_translate`（`web/modules/custom/xedc_auto_translate`）。翻译提供商可在后台切换为 Microsoft Translator 或 DeepL（REST + API Key）。未安装 tmgmt。原先的 Google Cloud Translation 已停用。

| 语言 | langcode | URL 前缀 | 说明 |
| --- | --- | --- | --- |
| 简体中文 | zh-hans | （空） | 默认语言，正式别名保持无前缀 |
| 英语 | en | en | |
| 俄语 | ru | ru | |
| 日语 | ja | ja | |

协商方式：URL 路径前缀。内容语言跟随界面语言。

已开启内容翻译的对象：

- 节点：photo、article、video、page
- 词汇：photo_category、article_category、video_category、models、tags
- 菜单链接：main、footer、account

可翻译文本字段：article 的 `field_body`、`field_summary`、`field_source`；photo 的 `field_summary`；video 的 `field_body`；page 的 `field_body`。图片、分类引用、计数不按语言拆开，各语言共用。分类名称随术语翻译。

## 语言切换器

可见切换器在自定义顶栏，不依赖区块区域（`xedc-header.html.twig`）：

- 桌面：登录文字左侧，与登录间隔 14px。导航栏右侧留白加大（普通宽度 36px，宽屏 48px），切换器不贴右边缘。按钮只显示当前语言，点击展开（`.xn-lang`）。主题图标仍在最右侧。
- 移动端：抽屉底部、登录/注册上方。整行按钮只显示当前语言，点击后向上展开其他语言（`.xn-lang--sheet`），不再平铺。

标签随界面语言变化：

| 界面 | 中文 | 英语 | 俄语 | 日语 |
| --- | --- | --- | --- | --- |
| 简体中文 | 中文 | 英语 | 俄语 | 日语 |
| English | Chinese | English | Russian | Japanese |
| Русский | Китайский | Английский | Русский | Японский |
| 日本語 | 中国語 | 英語 | ロシア語 | 日本語 |

链到当前路径加对应前缀。前缀协商不变。

另有区块 `xedc_language_switcher`（插件 `language_block:language_interface`，区域 `navbar_right`）。当前 `page.html.twig` / `page--front.html.twig` 不输出 `navbar_right`，这个区块在页面上看不到。

## 已修改的主题与相关文件

主题：

- `xedc.theme`、`xedc.libraries.yml`、`xedc.search.inc`、`build.mjs`
- `includes/auth.inc`、`includes/AuthCallbacks.php`
- `css/xedc-navbar.css`
- `src/js/main.script.js` 以及 `js/` 下 `photo-detail.js`、`photo-list.js`、`home-hero.js`、`term-intro.js`、`comment-form.js`、`article-detail.js`、`auth.js`、`video-detail.js`
- 模板：`xedc-header.html.twig`、`home-footer.html.twig`、`home-sections.html.twig`、`html-sitemap.html.twig`、`meitu-card.html.twig`、`photo-all-sheet.html.twig`、`search-card.html.twig`、`search-page.html.twig`、`xedc-meta.html.twig`、`comment.html.twig`、`xa-pager.html.twig`、`views-view--article-list.html.twig`、`views-view--image-gallery.html.twig`、`node--photo--full.html.twig`、`node--article--full.html.twig`、`node--article--teaser.html.twig`、`node--video--full.html.twig`、`node--video--teaser.html.twig`
- 界面译文：`translations/en.po`、`ru.po`、`ja.po`、`xedc.pot`

模块与配置：

- `web/modules/custom/xedc_auto_translate/`（全部为新增）
- `web/modules/custom/xedc_home/src/Controller/SitemapController.php`、`templates/xedc-home-categories.html.twig`
- `config/sync` 中的语言实体、协商前缀、内容翻译设置、上述文本字段 `translatable: true`、语言切换区块、`xedc_auto_translate.settings.yml`、`core.extension.yml` 中的模块条目

`build.mjs` 为主包增加 `charset: 'utf8'`，避免压缩后把 `Drupal.t('表情')` 写成 `\u` 转义，否则界面翻译扫描不到这些字符串。`npm run build` 后 `build/` 仅 `main.style.css` 与 `main.script.js` 各一行差异。

## 自动翻译

配置页：`/admin/config/regional/xedc-auto-translate`（权限「管理自动翻译」）。

当前配置（`xedc_auto_translate.settings`）：

- `enabled: true`
- `provider: microsoft`（可改为 `deepl`）
- 源语言 `zh-hans`
- Microsoft 区域默认 `global`，终结点默认空（使用全球地址）
- DeepL 接口默认 `auto`（Key 以 `:fx` 结尾时走免费接口）
- 目标 `en`、`ru`、`ja`
- `overwrite: false`（已有译文不覆盖）
- `save_as: published`（可改为 `draft`）

语言代码由提供商内部映射，不写入密钥：

| Drupal | Microsoft | DeepL |
| --- | --- | --- |
| zh-hans | zh-Hans | ZH |
| en | en | EN-US |
| ru | ru | RU |
| ja | ja | JA |

触发：`hook_entity_insert` / `hook_entity_update`。仅处理源语言为中文的默认译文，且实体类型在上面的列表中。带审核流的节点（article、photo、video）只在 `moderation_state = published` 时翻译；其他节点在已发布时翻译；菜单链接在启用时翻译；分类术语在保存时翻译。

行为：

- 只补缺失语言。`overwrite` 关闭时跳过已有译文。
- 一次保存写入全部目标语言。译文审核状态为已发布；选草稿时，有审核流的节点写入 `draft`，普通节点为未发布，菜单链接为禁用。分类术语没有草稿，保存后即可用。
- 写入前把 pathauto 关掉，再按源别名复制一条目标语言的 `path_alias`。中文别名不改。因此 `/bizhi/1` 保持原样，译文就绪后才有 `/en/bizhi/1`。
- API 失败或未配置 Key 只写日志，不让原文发布失败。
- 两个提供商的 Key 分开存在 State，不进配置导出：
  - `xedc_auto_translate.api_key.microsoft`，环境变量 `MICROSOFT_TRANSLATOR_API_KEY`（State 优先）
  - `xedc_auto_translate.api_key.deepl`，环境变量 `DEEPL_API_KEY`（State 优先）
- 同一套提供商和 Key 也用于界面翻译。`drush xedc:ui-translate` 把未翻译的英文界面字符串译成简体中文，调用方式见 `docs/scheduler-and-translation-setup.md`。内容翻译仍是中文译到 en / ru / ja，两者互不影响。
- 区域也可由环境变量 `MICROSOFT_TRANSLATOR_REGION` 提供（配置里已有区域时优先用配置）。
- 原先的 Google Key（State `xedc_auto_translate.api_key` 与 `GOOGLE_TRANSLATION_API_KEY`）不再使用。更新时会删掉旧的 State Key。

## 申请 Microsoft Translator 免费额度

免费层 F0 每月约 200 万字符（以 Azure 当前定价页为准）。

1. 打开 [Azure 门户](https://portal.azure.com) 并登录。没有订阅时，按提示创建一个免费订阅。
2. 选择「创建资源」，搜索 **Translator**。
3. 定价层选 **Free F0**。区域选 **Global**，或离站点更近的区域（例如 East Asia）。
4. 创建完成后打开该资源，进入「密钥和终结点」。
5. 复制 **Key 1**。区域看「位置」：Global 在后台填 `global`，East Asia 填 `eastasia`。
6. 打开 `/admin/config/regional/xedc-auto-translate`，提供商选 **Microsoft Translator**，粘贴 Key，填写区域。终结点留空。
7. 保存。Key 输入框留空表示保留已保存的 Key；勾选清除可删掉。
8. 不要把 Key 写入代码、`settings.php` 或 `config/sync`。

中国区或政府云才需要填写终结点，例如 `https://api.translator.azure.cn`。普通全球或区域资源不要改。

## 申请 DeepL 免费额度

DeepL API Free 每月约 50 万字符（以 DeepL 当前定价页为准）。这是 API 额度，不是网页版 DeepL Translator 的免费次数。

1. 打开 [DeepL API](https://www.deepl.com/pro-api)，注册或登录。
2. 选择 **DeepL API Free**，不要选只供网页翻译的 Pro 订阅。
3. 进入账户的 [API Keys](https://www.deepl.com/your-account/keys)，创建一个密钥。
4. 免费密钥以 `:fx` 结尾。
5. 打开 `/admin/config/regional/xedc-auto-translate`，提供商选 **DeepL**，粘贴 Key。接口保持「自动」。
6. 保存。Key 输入框留空表示保留已保存的 Key；勾选清除可删掉。
7. 不要把 Key 写入代码、`settings.php` 或 `config/sync`。

「自动」会在 Key 以 `:fx` 结尾时请求 `https://api-free.deepl.com`，否则请求 `https://api.deepl.com`。专业版 Key 不要选免费接口。

同一页可将「保存为」从「已发布」改为「草稿」。两个 Key 会同时保留，切换提供商不会清掉另一个。

## DeepL 补译结果

提供商为 DeepL（免费 Key，接口自动）。`overwrite` 仍为关闭。用 `drush xedc:translate-missing --limit=55` 处理已发布中文 photo / article / video / page，未覆盖已有译文。

已发布中文内容现均有 en / ru / ja 译文：photo 33、article 11、video 8、page 4。其中 node 131 原本已有译文，被跳过。

第一次批量在 article 60 中断：中文标题有 152 字，英/俄译文超过标题字段 255 字，保存报 `Data too long for column 'title'`。已在写入前按字段 `max_length` 截断，保存失败不再中断整批。重跑后 node 60 的英、俄标题为 255 字，日语 238 字，中文标题未改。随后补上因名额被新 photo 挤掉的 page 53（`/terms`）。

抽查均为 200，且页面里能看到对应语言标题：

| 内容 | 中文 | 英语 | 俄语 | 日语 |
| --- | --- | --- | --- | --- |
| photo 1 | `/bizhi/1` 海边风景手机壁纸 测试 | Seaside Scenery Phone Wallpapers - Test | Обои для мобильного телефона… | 海辺の風景のスマホ壁紙 テスト |
| article 7 | `/articles/xiaomojiwenzhangtupianjianjietu` | Xiao Moji: Article, Image, and Thumbnail | Небольшое изображение к статье «Може» | 「小墨跡」の記事・画像・概要画像 |
| video 6 | `/videos/shipinlanmuziduandeceshineirong` | Test Content for Video Section Fields | Тестовое содержимое поля «Видеорубрика» | 動画コーナーのフィールドに関するテスト内容 |
| page 53 | `/terms` 用户协议 | User Agreement | Пользовательское соглашение | 利用規約 |

分类术语和菜单链接这次没有批量翻译。

## 如何验证

1. 桌面打开首页。导航栏右侧、登录左侧应只有当前语言「中文」。点击后出现「英语」「俄语」「日语」。
2. 点「英语」，地址变为 `/en`，响应头 `Content-Language: en`。按钮变为 English，展开项为 Chinese、Russian、Japanese。俄语、日语同理（按钮为 Русский / 日本語，展开项用该语言的名称）。中文首页仍无前缀。
3. 把窗口缩到手机宽度，打开侧边菜单。语言行应在底部、登录/注册按钮上方，不应出现在菜单顶部。
4. 中文首页应看到「登录」，`/en` 为 “Log in”，`/ru` 为 “Войти”，`/ja` 为 “ログイン”。
5. 按上面的步骤申请并填写其中一个 Key 后，发布一篇新的中文 photo / article / video。
6. 打开 `/en`、`/ru`、`/ja` 加上该内容的原别名，应看到译文且中文 URL 仍可访问。
7. 再改中文并发布：已有译文应保持不变。需要覆盖时用下面的 `--force`。
8. 在配置页切换另一个提供商并填写对应 Key 后，用手动翻译或 `--force` 重译一条内容，确认走的是新提供商。

未配置 Key 时翻译不会改原文，只在日志里记一条 warning。不要把真实 Key 写进配置导出。

## 手动翻译或重译

配置页底部可指定实体类型和 ID，勾选强制覆盖后提交。

```bash
vendor/bin/drush xedc:translate node 123
vendor/bin/drush xedc:translate node 123 --force
vendor/bin/drush xedc:translate-missing --limit=20
vendor/bin/drush xedc:translate taxonomy_term 45
```

`--force` 会覆盖已有译文，包括人工修改。缺省只补缺失语言。`translate-missing` 按已发布中文内容回填，默认最多 20 条。

界面字符串在 `web/themes/custom/xedc/translations/`。修改后重新导入：

```bash
vendor/bin/drush locale:import en web/themes/custom/xedc/translations/en.po --type=customized --override=all -y
vendor/bin/drush locale:import ru web/themes/custom/xedc/translations/ru.po --type=customized --override=all -y
vendor/bin/drush locale:import ja web/themes/custom/xedc/translations/ja.po --type=customized --override=all -y
vendor/bin/drush cr
```

Drush 的 Drupal 根目录是 `web/`。在项目根目录执行时请使用绝对路径，或把路径写成 `themes/custom/xedc/translations/en.po`。

## 高频界面文字建议

完整建议已导入（每种语言 181 条）。节选：

| 中文 | English | Русский | 日本語 |
| --- | --- | --- | --- |
| 登录 | Log in | Войти | ログイン |
| 注册 | Sign up | Регистрация | 登録 |
| 搜索 | Search | Поиск | 検索 |
| 首页 | Home | Главная | ホーム |
| 美图 | Photos | Фото | 写真 |
| 文章 | Articles | Статьи | 記事 |
| 视频 | Videos | Видео | 動画 |
| 模特 | Models | Модели | モデル |
| 更多 | More | Ещё | もっと見る |
| 站点地图 | Sitemap | Карта сайта | サイトマップ |

`@count万` 的英文建议是 `@count0k`（1.2万会变成 “1.20k”），只作占位。`@count张` 的译文去掉了量词。搜索结果那句带 HTML 的文案在模板里用 `|t`，PO 里可能还没有对应条目，需要翻译时保留标签。

## 未完成与需人工确认

- 未配置真实 API Key，没有对 Microsoft Translator 或 DeepL 发起过翻译请求，别名复制和「发布 / 草稿」未在真实译文上验证。
- 会员中心、模特详情、标签页模板仍有硬编码中文，未改。
- 英文等内容列表在译文生成前为空，这是语言过滤的预期结果。
- 启用模块时，活动配置里约 186 个对象的默认语言被标成 `zh-hans`（只在数据库）。没有把整站 `drush cex` 写回 `config/sync`，避免盖掉其他未提交配置。
- 菜单、视图的配置翻译功能已可用，但还没有录入各语言的配置译文。菜单链接标题会在保存时由自动翻译补齐（若该链接已启用且尚无译文）。
