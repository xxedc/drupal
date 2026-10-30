# 站点恢复指南

本指南说明如何用仓库根目录的 `install-restore.sh`，在一台全新的 Ubuntu 24.04 服务器上重建可运行的 Drupal 站点。

脚本恢复的是**代码和配置结构**，不是原站的业务数据。

## 用途与适用范围

适用：

- 全新 Ubuntu 24.04 服务器
- 需要安装 PHP 8.5、MariaDB、Nginx、Composer、Node.js 和 Drush
- 需要按仓库里**当时最新**的 `composer.lock` 安装 Drupal **11.4.11** 及已锁定的 contrib 模块
- 需要构建自定义主题 `xedc`，启用自定义模块，并导入 `config/sync`
- 需要导入仓库中的翻译文件（`translations/` 与主题内的 `.po`）

不适用：

- 恢复用户、节点、评论、媒体记录等数据库内容
- 恢复 `web/sites/default/files` 中的上传文件
- 恢复原库的 `hash_salt`、数据库口令或 `settings.php`
- 升级 Drupal 核心或 contrib 模块
- 安装 Matomo 等仓库配置里引用、但本仓库不包含的外部服务

每次执行都会重新 `git clone` 指定分支的最新提交，因此会带上当时最新的代码、`composer.lock`、`config/sync`、自定义模块和主题。不需要为新增模块或锁定文件变更另写步骤。

## 执行前准备

- 系统：Ubuntu 24.04，使用 root 或 `sudo`
- 网络：可以访问 GitHub、packages.drupal.org、ondrej/php PPA；主题构建还需要 npm 注册表
- 磁盘：建议至少空余 2GB。目标目录已存在时，脚本会把**整个旧目录**改名备份，上传文件和 `vendor` 都会留在备份里，短时间内占用双倍空间
- 端口：HTTP 使用 80。启用 HTTPS 时还需要 443，并且域名的 DNS 已指向这台服务器
- 不要在仍承载生产数据的机器上直接执行，除非已经理解下文的 `--yes` 和 `--reinstall`

默认安装位置是 `/var/www/drupal`。若该目录已经存在，脚本会立刻退出，不会安装软件包，也不会重启数据库或 Web 服务。

## 参数与环境变量

命令行参数优先于同名环境变量。

| 参数 | 环境变量 | 默认值 | 说明 |
| --- | --- | --- | --- |
| 位置参数或 `--domain` | `DOMAIN` | 当前主机名 | Nginx `server_name` 与 trusted host |
| `--ssl` / `--certbot` | — | 不申请证书 | 用 Certbot webroot 申请证书并启用 HTTPS |
| `--email` | `CERTBOT_EMAIL` | `admin@域名` | 证书通知邮箱 |
| `--no-www` | — | 同时包含 `www` | 不为 `www` 子域写 `server_name` 或申请证书 |
| `--app-root` | `APP_ROOT` | `/var/www/drupal` | 代码目录 |
| `--repo` | `GIT_REPO` | `https://github.com/xxedc/drupal.git` | 仓库地址 |
| `--branch` | `GIT_BRANCH` | `main` | 每次克隆的分支 |
| `--db-name` | `DB_NAME` | `drupal` | 仅本机 MariaDB |
| `--db-user` | `DB_USER` | `drupal` | 仅允许字母、数字、下划线 |
| `--db-pass` | `DB_PASS` | 自动生成 | 省略时每次写入新口令 |
| `--admin-user` | `DRUPAL_ADMIN_USER` | `admin` | 仅在全新安装时创建 |
| `--admin-pass` | `DRUPAL_ADMIN_PASS` | 自动生成 | 跳过安装时不会重置 |
| `--site-name` | `DRUPAL_SITE_NAME` | `system.site.yml` 中的名称 | 导入配置后以仓库为准 |
| `--site-mail` | `DRUPAL_SITE_MAIL` | `admin@域名` | 导入配置后可能被仓库中的邮箱覆盖 |
| `--yes` | — | — | 目标目录已存在时，确认备份后重新克隆 |
| `--reinstall` | — | — | 删除并重建数据库。库中已有内容时还必须加 `--yes` |

可选文件：

- `/root/xedc-settings.local.php`：若存在，会复制为 `web/sites/default/settings.local.php`。重新克隆后，只放在站点目录里的 `settings.local.php` 不会保留。
- 凭据写入 `/root/xedc-restore-credentials.txt`，权限 `600`。可用 `CREDENTIALS_FILE` 改路径。

数据库主机固定为本机。脚本不为远程数据库建账号。

## 执行步骤与示例

在新服务器上先取脚本，再执行。脚本自己会再次克隆整个仓库，因此一开始只需要这一个文件：

```bash
curl -fsSL -o /root/install-restore.sh \
  https://raw.githubusercontent.com/xxedc/drupal/main/install-restore.sh
chmod +x /root/install-restore.sh
sudo /root/install-restore.sh example.com
```

申请 HTTPS：

```bash
sudo /root/install-restore.sh example.com --ssl --email admin@example.com
```

指定数据库口令，并且域名不含 `www`：

```bash
sudo DB_NAME=drupal DB_USER=drupal DB_PASS='请换成新口令' \
  /root/install-restore.sh example.com --no-www
```

目标目录已经存在、确认要备份后重装代码，但保留尚无内容的空库：

```bash
sudo /root/install-restore.sh example.com --yes
```

确认删除已有数据库并安装空站点：

```bash
sudo /root/install-restore.sh example.com --reinstall --yes
```

查看全部参数：

```bash
sudo /root/install-restore.sh --help
```

脚本按下面的顺序工作：

1. 安装 PHP 8.5（ondrej/php，含 gd、mbstring、xml、curl、zip、intl、mysql、apcu、bcmath；OPcache 随 PHP 提供）、MariaDB、Nginx、Composer、Node.js 22（若系统已有 Node.js 18 或更高则保留）和 npm。
2. 若目标目录已存在且传入了 `--yes`，把整个目录改名为 `/var/www/drupal.bak.时间戳`。
3. `git clone` 指定分支的最新提交。
4. 删除仓库里带来的 `settings.php`。
5. `composer install --no-dev --no-interaction --prefer-dist`。不执行 `composer update`。安装后核对 `drupal/core` 是否为 11.4.11。
6. 若 `web/themes/custom/xedc/package.json` 存在，执行 `npm install && npm run build`。
7. 创建空数据库（或在 `--reinstall` 时删除后重建），生成新的 `hash_salt`，写入新的 `settings.php`。`config_sync_directory` 指向仓库的 `config/sync`。
8. 配置 Nginx。文档根是 `web/`。规则参考 `_server/nginx/conf.d/drupal.conf`，并加上安全响应头、gzip、HTTP/2（启用 HTTPS 时）、上传与 FastCGI 超时。
9. 传入 `--ssl` 时用 Certbot 申请证书。失败则保留 HTTP，脚本最后以非零状态退出。
10. 若数据库还不是 Drupal 站点，执行 `drush site:install standard`。优先使用 `zh-hans`，失败则改用安装程序默认语言。
11. 把站点 UUID 改成 `config/sync/system.site.yml` 里的值，然后执行 `drush cim -y`。有差异也会继续。第一次失败时会再导入一次。
12. `drush updatedb -y`，启用 `xedc` 并确认为默认主题（仓库配置里默认主题已经是 `xedc`）。
13. 导入仓库中的 `.po`。语言未启用的文件会跳过并给出警告。
14. 把 `simple_sitemap.settings:base_url` 改成这次的站点地址，然后 `drush cr`。
15. 将 `web/sites/default/files` 和站点根目录外的 `private` 交给 `www-data` 写。其余代码为 `root:www-data` 只读。
16. 安装每 15 分钟一次的 `drush cron`。

重复执行时仍会重新克隆最新代码并再次导入配置。只有库中没有节点、且除匿名用户外只有一个账号时，才会跳过 `site:install`。一旦有节点或额外用户，必须显式 `--reinstall --yes`，否则脚本拒绝继续。

## 已知风险与注意事项

- **配置不等于当时的生产现场。** 提交到 `config/sync` 的内容，可能少于或多于原服务器上正在使用的配置。`settings.php` 里曾经有过的 `$config` 覆盖不会进入配置导入。`drush cim -y` 以仓库文件为准，即使和标准安装结果不同也会继续。
- **不恢复用户数据。** 新站点是空的。旧目录备份里可能仍有上传文件，但新的 `sites/default/files` 是空目录，站点不会引用那些文件。
- **绝对地址和第三方服务会原样导入。** 除 sitemap 的 `base_url` 会被脚本改成新域名外，Metatag、Matomo 地址、邮件发件域名等仍是仓库里的值。导入后要按新环境修改。Matomo 不在本脚本的安装范围内。
- **邮件口令等敏感值可能在配置里。** 新环境应更换邮件和应用口令，不要假设导入的凭据仍然适用。
- **每次克隆都使用新的 `hash_salt`。** 已登录会话和一次性登录链接会失效。账户口令本身由安装程序另行生成，并写在 root 的凭据文件里。
- **默认数据库名是 `drupal`。** 若本机已有同名且含内容的库，脚本会在安装软件包之前退出。删除该库必须同时传入 `--reinstall` 和 `--yes`。
- **重新克隆会丢掉目标目录中未提交的文件。** 包括上传文件、`settings.local.php`（除非放在 `/root/xedc-settings.local.php`）和未提交的配置导出。
- **Composer 只做 install。** 锁定版本不是 11.4.11 时脚本会停止，不会改锁文件或升级依赖。
- **主题必须能在当前 Node.js 上构建。** `package.json` 要求 Node.js ≥ 18。构建失败时脚本停止，站点不会带着过期的前端资源继续。

## 执行后检查

凭据文件：

```bash
sudo cat /root/xedc-restore-credentials.txt
```

建议逐项确认：

- 浏览器打开站点地址，首页返回 200，静态 CSS/JS 不是 404
- `/user/login` 可用凭据文件中的管理员登录
- 管理页主题为 Gin，前台主题为 `xedc`：`drush config:get system.theme default`
- 默认语言与仓库一致（当前配置为简体中文）
- `drush config:status` 没有意外的未导入差异
- 抽查一种启用的语言，确认界面翻译来自仓库中的 `.po`，而不是空白
- 修改 Nginx 中的域名后，用该域名访问，确认没有 trusted host 报错
- 检查 sitemap、Metatag 和统计配置里的绝对 URL
- 确认 SMTP 是否应该关闭或改成新环境的账号
- 上传一张测试图片，确认 `web/sites/default/files` 可写；这不能代替用户文件恢复
- `systemctl status nginx php8.5-fpm mariadb` 均为 active
- 等待一次计划任务，或手动执行：

```bash
sudo -u www-data /usr/bin/php /var/www/drupal/vendor/bin/drush --root=/var/www/drupal/web cron
```

定时发布依赖该 cron。默认每 15 分钟一次，可修改 `/etc/cron.d/xedc-drupal`。

确认新站点可用后，再删除 `*.bak.*` 备份目录以释放磁盘。备份中的上传文件不会自动迁入新站点。

## 域名与 HTTPS

域名决定三件事：

- Nginx `server_name`（默认还有 `www`）
- `settings.php` 的 `trusted_host_patterns`（含该域名、`www`、`localhost` 和服务器主机名）
- 导入后的 `simple_sitemap.settings:base_url`

只使用裸域名时加 `--no-www`。`www` 的 DNS 没有指向本机时，不要申请包含 `www` 的证书。

启用 HTTPS：

```bash
sudo /root/install-restore.sh example.com --ssl --email admin@example.com
```

证书申请使用 HTTP-01，80 端口必须能从公网访问到 `/.well-known/acme-challenge/`。成功后，80 端口只保留证书续期路径，其余请求跳转到 HTTPS。Nginx 1.25.1 及以上使用 `http2 on`，更早版本使用 `listen 443 ssl http2`。

Certbot 安装后会尝试启用 `certbot.timer` 自动续期。证书申请失败时，站点保持 HTTP，需要修正 DNS 或防火墙后重新执行同一命令。

已有 `/etc/letsencrypt/live/<域名>/` 证书时，即使不加 `--ssl`，脚本也会按 HTTPS 写出 Nginx 配置。

安全响应头包括 `X-Content-Type-Options`、`X-Frame-Options`、`Referrer-Policy` 和 `Permissions-Policy`。上传限制与现有站点一致：PHP `upload_max_filesize` 200M，`post_max_size` 与 Nginx `client_max_body_size` 为 220M。

若要在导入之后覆盖个别设置，把 PHP 放在 `/root/xedc-settings.local.php`。它会在每次恢复时复制到站点目录，并在 `settings.php` 末尾加载。
