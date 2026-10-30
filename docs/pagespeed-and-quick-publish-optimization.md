# PageSpeed 与快速发布图集优化

品牌保持 DcLili，正式 URL 与页面布局未改。只调整资源加载和快速发布图集的后台流程。

## PageSpeed

- 全站脚本只保留 Bootstrap 下拉（评论/操作的 dropbutton 仍在用）。轮播、模态框、侧栏、折叠、提示、Toast、Tab 等组件在前台模板中没有 `data-bs-toggle`，已从 `src/js/_bootstrap.js` 和 `src/scss/_bootstrap.scss` 去掉。对应的 `_tooltip-init.js`、`_toast-init.js` 没有其它引用，已删除。
- 旧导航（`.xedc-nav` / `data-theme-toggle`）和旧美图灯箱（`.gl`，选择器对不上现在的图集 DOM，且 `photo-detail.js` 已接管）已从全站包移除。主题切换（含系统深色偏好）仍在 `xedc-navbar.js`。
- 评论头像、表情、回复和评论图片灯箱改到 `xedc/comment-form`，由评论模板挂载。美图列表标题计数改到 `xedc/photo-list`。这些行为只在对应页面下载。
- 首页 LCP 图增加 `rel=preload` + `fetchpriority=high`。首页视频、文章封面补了 `decoding="async"`。轮播图仍不输出 width/height，避免拖动时图片被压窄。
- 站点没有 `large` 图片样式，文章/标签/模特封面会回落到原图。已改用现有样式：文章 `xa_cover`（400×300 WebP），美图 `meitu_card_cover`，视频 `video_cover`。显示尺寸仍由 CSS 控制。
- `system.performance` 的 CSS/JS 聚合原本已开启。本次只重建主题包，聚合文件会随内容变化更新。

主题包体积：`build/js/main.script.js` 107KB → 42KB，`build/css/main.style.css` 303KB → 263KB。`npm run build` 后 `build/` 只有这两个文件有差异。

## 快速发布图集

路由仍是 `/admin/quick-gallery`、`/admin/quick-gallery/upload`、`/admin/quick-gallery/create`，权限仍是 `administer nodes`。新增 `GET /admin/quick-gallery/suggest`。

- 页面不再一次性塞入最多 3000 个术语。人物、标签、分类改为输入时查询，最多 20 条；没有匹配时仍可回车新建。
- 选图后直接用本地预览，上传时再压到最长边 2000px 的 WebP（失败则 JPEG）。最多 3 张并行，失败可再点一次重试；CSRF 403 会刷新 token。
- 照片操作用「封面 / 前移 / 最前 / 删除」按钮，不再用 `prompt`。
- 服务端按文件内容去重，并用锁避免并发写出两份媒体。文件用复制写入，不再把整文件读进 PHP 内存。术语按名称一次查齐，只创建缺失项。创建成功后草稿去编辑页，发布去节点别名。

## 验证

- `php -l`：快速发布控制器、安装文件、主题与标签/模特控制器通过。
- `node --check`：快速发布、评论、美图列表、导航脚本通过。
- `npm run build` 成功（Stylelint 仅有原有警告，0 error）。
- `drush cr` 成功。
- `https://gitxx.xyz/` 200。标题为 DcLili；首屏有 `xa_hero` WebP 的 preload；CSS/JS 为 `/sites/default/files/css|js/` 聚合文件。首页 HTML 没有 `data-bs-toggle`、modal、accordion。
- `/xiuren/130` 200，图集有 `srcset` 与首图 `fetchpriority=high`。`/meitu`、`/articles` 200，文章封面为 `xa_cover`。
- 未登录访问 `/admin/quick-gallery` 与 suggest 为 403（不是 404）。以 uid 1 调用 suggest 返回术语 JSON；hash / orig 表存在。

未在浏览器里做像素级对照（本机没有无头浏览器），也没有用管理员会话完整走一遍上传并创建节点。
