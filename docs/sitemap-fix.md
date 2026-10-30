# /sitemap 500 修复

## 原因

`/sitemap` 由 `xedc_home` 的路由 `xedc.html_sitemap` 交给 `SitemapController::page()`。日志中的异常是：

```text
Error: Call to undefined method Drupal\xedc_home\Controller\SitemapController::entityRepository()
```

Drupal 11 的 `ControllerBase` 没有 `entityRepository()`。控制器在列出栏目时调用了这个方法，请求在渲染前就中断，所以 `https://gitxx.xyz/sitemap` 和 `https://www.gitxx.xyz/sitemap` 都是 500。路由、主题钩子和 Twig 本身是通的。

## 修改

`web/modules/custom/xedc_home/src/Controller/SitemapController.php`

改为使用服务 `entity.repository` 的 `getTranslationFromContext()`，再用术语名称和别名输出链接。页面仍包含：浏览（首页、美图、文章、视频、模特、标签）、美图/文章/视频栏目、模特，以及关于 DcLili（关于我们、隐私政策、用户协议、站点地图）。

页脚链接本来就是 `<a href="/sitemap">`，没有改。

## 验证

```bash
drush cr
curl -sk -o /dev/null -w "%{http_code}\n" -H "Host: gitxx.xyz" https://127.0.0.1/sitemap
curl -sk -o /dev/null -w "%{http_code}\n" -H "Host: www.gitxx.xyz" https://127.0.0.1/sitemap
```

源站两次都是 200，标题为「站点地图 | DcLili」。若公网仍短暂看到旧的 500，清一下 Cloudflare 上 `/sitemap` 的缓存后再访问。
