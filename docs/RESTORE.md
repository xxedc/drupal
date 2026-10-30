# 站点恢复

用仓库根目录的 `install-restore.sh`，在全新 Ubuntu 24.04 或 26.04 上安装环境、拉取最新代码、构建主题 `xedc`，并导入 `config/sync`。

恢复的是代码和配置结构。不恢复用户、内容、上传文件或原数据库。每次运行都会重新 `git clone` 指定分支，并严格执行 `composer install`（不执行 `composer update`）。Drupal 版本以 `composer.lock` 为准，当前为 **11.4.11**。

## 常用命令

```bash
curl -fsSL -o /root/install-restore.sh \
  https://raw.githubusercontent.com/xxedc/drupal/main/install-restore.sh
chmod +x /root/install-restore.sh
sudo /root/install-restore.sh example.com
```

```bash
# HTTPS。www 的 DNS 不存在时加 --no-www
sudo /root/install-restore.sh example.com --ssl --email admin@example.com

# 目录已存在：先整目录备份，再克隆。不会删除已有数据库
sudo /root/install-restore.sh example.com --yes

# 删除已有数据库并安装空站点。库里已有内容时，两个参数都要
sudo /root/install-restore.sh example.com --reinstall --yes
```

默认目录 `/var/www/drupal`。该目录已存在且未加 `--yes` 时，脚本立即退出，不安装软件包，也不重启服务。管理员和数据库口令写在 `/root/xedc-restore-credentials.txt`（权限 `600`）。

## 域名会改哪些地址

导入前，脚本从 `simple_sitemap.settings.yml` 的 `base_url`（否则从站点邮箱域名）识别旧域名，并改成这次传入的域名。协议与 `--ssl` 结果一致。

| 会替换 | 不替换 |
| --- | --- |
| sitemap `base_url` | 子域上的外部统计，如 Matomo |
| Metatag 中指向本站的 `http(s)` 地址，含序列化字段 | SMTP 服务器，如 `smtp.gmail.com` |
| `@旧域名` 的站点邮箱 | 外部邮箱，如 Gmail |
| 与旧域名完全相同的主机名，如 `smtp_client_hostname` | Drupal.org、oEmbed、IndexNow 等第三方 URL |

`www.旧域名` 视作本站。其他子域保持原样。脚本会列出改过的配置文件，以及保留下来的外部主机。配置里的邮件口令不会打印，新环境应自行更换。

## 参数

命令行参数优先于同名环境变量。

| 参数 | 环境变量 | 默认 |
| --- | --- | --- |
| 域名 / `--domain` | `DOMAIN` | 当前主机名 |
| `--ssl` | — | 不申请证书 |
| `--email` | `CERTBOT_EMAIL` | `admin@域名` |
| `--no-www` | — | 同时包含 `www` |
| `--app-root` | `APP_ROOT` | `/var/www/drupal` |
| `--repo` / `--branch` | `GIT_REPO` / `GIT_BRANCH` | 本仓库 `main` |
| `--db-name` / `--db-user` / `--db-pass` | 同名 | `drupal` / `drupal` / 自动生成 |
| `--admin-user` / `--admin-pass` | `DRUPAL_ADMIN_USER` / `DRUPAL_ADMIN_PASS` | `admin` / 仅新安装时生成 |
| `--yes` | — | 目录已存在时必须给出 |
| `--reinstall` | — | 删库重装；有内容时还要 `--yes` |

数据库只创建在本机 MariaDB。可选覆盖文件：`/root/xedc-settings.local.php`。

## 风险

- `config/sync` 可能和原站点当时的实际配置不一致。`drush cim -y` 仍会导入，结果以仓库为准。
- 不恢复用户数据和上传文件。旧目录会备份为 `*.bak.时间戳`，其中的文件不会自动进新站点。
- 默认数据库名是 `drupal`。同名库若已有节点或额外用户，脚本会在改动服务前退出。
- 每次克隆使用新的 `hash_salt`。锁定版本不是 11.4.11 时脚本停止。
- 重复运行会再次克隆并导入。只有空站点（无节点、除匿名用户外只有一个账号）才会跳过 `site:install`。

## 执行后检查

```bash
sudo cat /root/xedc-restore-credentials.txt
```

- 首页和 `/user/login` 可打开，CSS/JS 不是 404
- 前台主题为 `xedc`：`drush config:get system.theme default`
- 日志中的本站地址已换成新域名；Matomo、SMTP 服务器、外部邮箱仍是原值
- `systemctl status nginx php8.5-fpm mariadb` 为 active
- 定时发布依赖 cron，默认每 15 分钟：`/etc/cron.d/xedc-drupal`

确认可用后再删除 `*.bak.*` 备份。

## HTTPS

`--ssl` 使用 Certbot HTTP-01，80 端口必须能从公网访问。成功后 80 端口除证书校验外跳转到 HTTPS。Nginx 1.25.1 及以上使用 `http2 on`，更早版本使用 `listen 443 ssl http2`。证书申请失败时站点保持 HTTP，脚本以非零状态结束。已有对应证书时，不加 `--ssl` 也会按 HTTPS 写 Nginx 配置。
