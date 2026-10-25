# 图片分类列表页优化报告

日期：2026-10-25  
站点：https://gitxx.xyz  
主题：`web/themes/custom/xedc`

## 一、改动文件

- `config/sync/views.view.image_gallery.yml`
  - 每页数量：12 → 16
  - 分页 ID：8 → 0，分页链接改为 `?page=1` 形式
  - 页码数量：9 → 5
  - 封面图片样式：`images_450x800` → `photo_card_640`
- `config/sync/image.style.photo_card_640.yml`（新增）
  - 640×1138，居中裁剪
  - 输出 WebP
- `web/themes/custom/xedc/xedc.theme`
  - 术语简介输出与缓存标签
  - 语义化卡片 HTML
  - 分类角标逻辑
  - 分页 SEO、canonical、rel prev/next
  - JSON-LD（BreadcrumbList、CollectionPage、ItemList）
- `web/themes/custom/xedc/includes/auth.inc`
  - 第 2 页起给 `<title>` 增加「第 N 页」
- `web/themes/custom/xedc/xedc.libraries.yml`
  - 新增 `term-intro`、`photo-list` 库
- `web/themes/custom/xedc/css/term-intro.css`
- `web/themes/custom/xedc/js/term-intro.js`
- `web/themes/custom/xedc/css/photo-list.css`（新增）
- `web/themes/custom/xedc/templates/views/views-view--image-gallery.html.twig`（新增）

## 二、实现要点

### 1. 术语简介

- 仅在第 1 页显示 `photo_category` 术语描述。
- 描述为空时不输出任何内容。
- PC 3 行、手机 2 行，使用 `line-clamp` 折叠。
- 全文始终保留在 HTML 中，不使用 `display:none` 删除全文。
- 展开/收起按钮由 JS 判断是否溢出后显示。
- 使用术语 cache tags，后台修改描述后页面可自动失效更新。

### 2. 列表与分页

- PC 4 列、手机 2 列。
- 每页 16 条。
- 使用 Full pager，每页最多 5 个页码。
- 手机端隐藏首尾页和省略号，避免换行溢出。
- 分页链接为真实 `<a href="?page=1">`。
- 第 1 页 canonical 无参数；第 2 页起 canonical 指向当前页自身。
- 排序参数不进入 canonical。
- 第 2 页起不显示简介，并移除重复 meta description。
- `<title>` 第 2 页起增加「第 N 页」。

### 3. 卡片与图片

- 卡片标题改为 `<h2>`。
- 整张卡片包裹在 `<a>` 中。
- 日期使用 `<time datetime="YYYY-MM-DD">`。
- 图片 `alt` 使用标题。
- 输出 `width="640" height="1138"`。
- 前 2 张 `loading="eager"` + `fetchpriority="high"`，其余 `loading="lazy"`。
- 分类页隐藏与当前分类重复的角标；存在非当前分类时显示分类名。
- 封面图使用图片样式生成的 WebP 缩略图。

### 4. SEO

- 输出 BreadcrumbList。
- 输出 CollectionPage + ItemList。
- 分页页输出 `<link rel="prev">` / `<link rel="next">`。
- Meta description 不重复输出，沿用已安装的 Metatag 模块。
- 排序页 canonical 指向无排序参数的分类页。

### 5. 体验

- 列表页使用 `min-height:100vh` flex 布局，内容少时页脚贴底。
- 手机端缩小头部与面包屑之间的空白。
- 分页样式沿用站点 shadcn 风格。

## 三、验证结果

已执行：

```bash
php -l web/themes/custom/xedc/xedc.theme
php -l web/themes/custom/xedc/includes/auth.inc
node --check web/themes/custom/xedc/js/term-intro.js
vendor/bin/drush cr
```

验证结果：

- `/cosplay`、`/cosplay?page=1`、`/meitu`、`/meitu?page=1`、排序页均返回 200。
- `/cosplay`：简介、meta description、8 个 `<h2>`、JSON-LD、canonical、8 张 WebP 缩略图均存在。
- `/cosplay?page=1`：简介和 meta description 已不输出，`<title>` 带「第 2 页」。
- cosplay 仅 8 条内容，少于每页 16 条，因此没有实际第 2 页数据。
- `/meitu?page=1`：16 张卡片、完整分页、`?page=1` 真实链接、prev/next、canonical、JSON-LD、16 张 WebP 均正常。
- 排序 URL 的 canonical 已去掉 `sort_by`。
- 原列表已使用 `images_450x800` WebP，不是原图；本次替换为 640 宽样式，约为 PC 卡片宽度 315px 的 2 倍。
- 实际 PHP-FPM `memory_limit=128M`，不是 2GB；当前最大原图 1440×2560（约 14MB GD），已实际生成 16 张缩略图且无 OOM，2GB 下更无问题。
- `drush cex` 被当前环境策略阻止，未执行；已直接写入 `config/sync`，并校验 active 配置与导出文件一致。
- 未做浏览器视觉验收；展开按钮交互、暗黑模式和手机分页外观需人工确认。

## 四、回滚方式

备份提交：`ea6c7ae`

```bash
git reset --hard ea6c7ae
vendor/bin/drush php:eval '$v=\Drupal\Core\Serialization\Yaml::decode(file_get_contents(DRUPAL_ROOT."/../config/sync/views.view.image_gallery.yml")); \Drupal::configFactory()->getEditable("views.view.image_gallery")->setData($v)->save(); $s=\Drupal\image\Entity\ImageStyle::load("photo_card_640"); if ($s) { $s->delete(); }'
vendor/bin/drush cr
```

## 五、因现有结构未改的项

- `/cosplay` 是 `xedc_tags` 接管 taxonomy term 路由后回退到 `image_gallery.page_3`；`/meitu` 是同一 View 的 `page_1`，分页与卡片逻辑已统一生效。
- 子分类/筛选标签目前实际取的是 `field_model` 人物术语（莉莉、小乖等），不是 `photo_category` 子分类；但已经是真实 `<a href>`，不是纯 JS 筛选，因此未改。
- 未手动重复输出 meta description；站点已安装 Metatag，第 2 页起仅移除重复 description。
- 未改 H1 文案；`/meitu` 的 H1 来自 View 标题数组，未强行改成「第 N 页」，但浏览器 `<title>` 已加。

## 六、后台还需处理

- 给 `photo_category` 各术语填写简介；空简介不会显示简介块。
- 将 H1 术语名改成「Cosplay 美图」等展示名，需要修改术语名称或单独覆盖标题逻辑。
- 将测试图片标题替换为真实标题。
- Metatag：在 `/admin/config/search/metatag/taxonomy_term__photo_category` 的 Description 填 `[term:description]`；如需严格 160 字，在 Metatag 设置中启用最大长度 160，不要在同一页再手动添加第二个 description。
- 建议在浏览器中检查 PC/手机、暗黑模式、简介展开/收起和分页按钮布局。
