# 模特重定向与 sitemap 修复

## 重定向

`/models/{tid}` 已由路由 `xedc_models.detail` 处理。之后新增的 Pathauto 模式 `pathauto.pattern.model_url`（`/models/[term:tid]`，仅作用于词汇 models）又为同一地址写了术语别名，系统路径仍是 `/taxonomy/term/{tid}`。

请求 `/models/27` 时，别名入站被改写成 `/taxonomy/term/27`。`TagsController` 再 301 回 `xedc_models.detail`，地址仍是 `/models/27`，于是循环。Redirect 模块的 `auto_redirect` 仍为开启，但 `redirect` 表里没有模特相关记录，不是这次循环的来源。

处理：删除该 Pathauto 模式，并删除 12 条 models 术语的 `/models/{tid}` 别名。自定义路由保持不变。`/taxonomy/term/27` 仍只 301 一次到 `/models/27`。

不要在「URL 别名模式」里重建「模特页url」。

## sitemap

- 自定义链接增加 `/models`（优先级 0.6）。
- `xedc_home_simple_sitemap_links_alter()` 把已索引的模特术语从 `/taxonomy/term/{tid}` 改成 `/models/{tid}`。
- 指向主模特的别名术语不写入 sitemap（访问时会 301）：21 → 27、24 → 20、28 → 27。
- 术语 48（美丽）在实体上的 sitemap「索引」原本就是关闭，本次未改，所以仍不出现。
- 本次生成后全部 119 条 URL 都有 `<lastmod>`。`/models` 的 lastmod 取模特术语里最新的 `changed`。`/models/27` 的 lastmod 为 `2026-10-17T10:55:47+08:00`。

已执行 `drush --uri=https://gitxx.xyz simple-sitemap:generate`（11/11）。

## 浏览器中的 sitemap.xml

`web/themes/custom/xedc/xsl/sitemap.xsl` 去掉了「搜索引擎读取的仍是这份 XML」。页头改为「共 N 条地址，更新于 {最新 lastmod}」，表格仍列出每条 URL 和最后更新。样式表只替换 `/sitemap_generator/default/sitemap.xsl` 的响应，不改 XML 生成。

## 自动更新

Simple XML Sitemap 已开启，无需再改：

- `cron_generate`: true
- `cron_generate_interval`: 0（每次 Drupal cron 都按当前内容重建）

此版本没有单独的「保存内容后立即重建」开关。内容变更会在下一次 cron 生成时进入 sitemap。

手动：

```bash
./vendor/bin/drush cron
./vendor/bin/drush --uri=https://gitxx.xyz simple-sitemap:generate
```

确认 cron 是否跑过生成：`./vendor/bin/drush state:get simple_sitemap.last_cron_generate`（有值即为上次由 cron 触发的时间戳）。

## 验证（源站，Host: gitxx.xyz）

- `https://127.0.0.1/models/27`：200，重定向 0 次，页面含「墨迹」和 DcLili。
- `https://127.0.0.1/taxonomy/term/27`：301 到 `/models/27`，再 200。
- `sitemap.xml` 含 `https://gitxx.xyz/models` 与 `https://gitxx.xyz/models/27` 等，不含这些术语的 `/taxonomy/term/{tid}`。
- 已执行 `drush cr`。

未在浏览器里点选页面。Firefox 打开 https://gitxx.xyz/sitemap.xml 可看到表格；若 Chrome 已关闭 XSLT，仍会显示原始 XML。Cloudflare 可能缓存旧的 301 或旧 sitemap，需清缓存后再看公网。

## 后台需人工确认

- `/admin/config/search/path/patterns`：不应再出现「模特页url」。
- `/admin/config/search/simplesitemap/settings`：勾选在 cron 时重新生成，间隔为每次 cron。
- `/admin/config/search/simplesitemap/custom`：含 `/` 与 `/models`。
- 术语「美丽」(tid 48) 的编辑页：Simple XML Sitemap 索引若需出现在 sitemap，再单独打开。
