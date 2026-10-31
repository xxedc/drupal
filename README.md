# 完整搬家步骤

下面 5 步可以把旧服务器上的数据库、公共文件和私有文件迁到一台新的 Ubuntu 22.04 或 24.04 服务器。按顺序复制命令。把「新服务器IP」「新域名」和打包文件名换成你自己的。不需要先读脚本。

## 1. 旧服务器打包

在旧服务器的站点目录执行。这一步默认只读：不改数据库内容、不改上传文件、不改 `settings.php`。`--maintenance` 会临时打开维护模式，命令结束或异常退出时都会恢复原来的值。`--yes` 用来确认工作区里未提交的代码改动不会被带走。

```bash
cd /var/www/drupal
sudo ./site-migrate.sh export --out /root/site-migrate --maintenance --yes
```

成功后，终端会打印两个文件的完整路径：一个 `.tgz`，一个同名的 `.tgz.sha256`。复制 `.tgz` 那一行路径，下一步两个文件都要传。

## 2. 传到新服务器

`.tgz` 和 `.tgz.sha256` 必须一起传。不要放进 Git，也不要放到网站目录里。

```bash
scp /root/site-migrate/site-migrate-时间.tgz* root@新服务器IP:/root/
```

把 `site-migrate-时间.tgz` 换成上一步终端里看到的真实文件名。`*` 会同时带上 `.sha256` 文件。

## 3. 新服务器恢复

新服务器还没有 Nginx、PHP、MariaDB 或代码时，导入会自动安装。下面这条命令会下载脚本、校验压缩包，再按包里的 git 提交号拉取代码并导入数据。

```bash
curl -fsSL -o /root/site-migrate.sh https://raw.githubusercontent.com/xxedc/drupal/main/site-migrate.sh
chmod +x /root/site-migrate.sh
sudo /root/site-migrate.sh import --pack /root/site-migrate-时间.tgz --domain 新域名
```

只在目标库已经有节点，或已经有 `uid>1` 的用户时，才在命令末尾加上 `--force --yes`。这两个参数表示确认覆盖现有数据。空库或全新服务器不要加。

也可以先单独装环境，失败后直接再执行同一条命令，已完成的安装步骤会跳过：

```bash
sudo /root/site-migrate.sh setup --domain 新域名
sudo /root/site-migrate.sh import --pack /root/site-migrate-时间.tgz --domain 新域名
```

## 4. 查看报告和凭据

```bash
cat /root/site-migrate-report.txt
cat /root/site-migrate-credentials.txt
```

报告第一行是「结果: 成功」或「结果: 失败」。凭据文件里有数据库名、账号、密码，以及管理员用户名和 uid。Drupal 只保存密码哈希，凭据文件里没有原来的登录密码；用搬家前的原密码登录即可。如果导入时加了 `--reset-admin-pass`，文件里会多一行新的管理员密码，原密码就不再有效。

## 5. 切 DNS 前验证

先不要改权威 DNS。在新服务器上执行：

```bash
curl -sI -H "Host: 新域名" http://127.0.0.1
```

看到 `200` 或 `301`/`302` 这类 3xx 后，再在自己的电脑上用 hosts 把新域名指到新服务器，打开首页、登录和上传文件。确认无误后再切 DNS。旧服务器先留着。

## 前提

仓库需要是公开的，并且 `site-migrate.sh` 已经推送到 `main`，第 3 步的 `curl` 才能下载到脚本。如果仓库是私有的，或脚本还没推上去，改用克隆：

```bash
git clone https://github.com/xxedc/drupal.git /var/www/drupal
sudo /var/www/drupal/site-migrate.sh import --pack /root/site-migrate-时间.tgz --domain 新域名 --root /var/www/drupal
```

旧服务器和新服务器都用 root 运行。只支持 Ubuntu 22.04 和 24.04。`apt` 全程使用 `DEBIAN_FRONTEND=noninteractive`。

## 包里有什么

包含：

- 数据库。`cache`、`cache_*`、`sessions`、`watchdog`、`flood`、`key_value_expire` 只保留表结构，其余表含数据
- 公共文件 `web/sites/default/files`。名为 `php`、`css`、`js`、`styles` 的目录不打包，这些由 Drupal 重新生成
- 私有文件。只有旧站配置了私有目录并且目录存在时才有

不包含：

- 代码和未提交改动。新服务器按 manifest 里的 git 提交号从仓库检出
- Nginx、SSL、cron、邮件服务器配置

包和旁边的 `.sha256` 文件权限都是 `600`。包内有用户邮箱和密码哈希，用完后在两边都删除。

## 脚本会自动完成的事

- 安装 Nginx、PHP-FPM、MariaDB、Composer，并写入一个只监听 80 端口的基础虚拟主机
- 按提交号拉取代码，执行 `composer install`。PHP 主次版本或 Drupal 版本与包内记录不一致时中止
- 校验 `.tgz.sha256`（如果有）和 manifest 里每个文件的 sha256
- 确认磁盘可用空间至少是包大小的 3 倍
- 覆盖前备份数据库和文件，并在终端打印回滚命令
- 导入数据库、解压文件、修正属主，然后 `drush updb` 和 `drush cr`。不执行 `drush cim`，以数据库里的配置为准
- 创建或沿用数据库账号，并写回 `settings.php` 的数据库连接
- 让 `$settings['trusted_host_patterns']` 包含 `^新域名$`。域名不以 `www.` 开头时同时写入 `www`，以 `www.` 开头时同时写入去掉 `www.` 的域名
- 用 `drush config:set` 更新 `simple_sitemap.settings` 的 `base_url`（保留原来的 http 或 https）
- 私有文件路径为空，或落在 webroot 里面时，改到站点目录下的 `private`（在 `web/` 外面），解压位置和最终路径一致
- `hash_salt` 优先写回迁移包里的旧值。旧站没有该值时，才保留目标 `settings.php` 里已有的值；两边都没有才新生成。用户密码哈希不依赖把明文密码搬过去，原密码仍然可以登录。salt 只放在权限 `600` 的包和 `settings.php` 里，不写入凭据文件
- 把数据库账号、管理员用户名和 uid 写入 `/root/site-migrate-credentials.txt`（权限 `600`）

## 需要手动检查的事

脚本只扫描并写进验收报告，不会改这些内容：

- 节点正文、菜单链接和其他用户内容里的绝对 URL
- Matomo、Metatag 图片地址、SMTP、`system.site` 的邮箱

另外还要自己处理：自定义 Nginx 配置、SSL 证书（certbot）、邮件发送、cron。基础虚拟主机只有 HTTP。证书申请前，DNS 必须已经指向新服务器。

验收报告在 `/root/site-migrate-report.txt`。结果为成功时，节点数、用户数、文件数与 manifest 一致，`drush status` 的 bootstrap 为 `Successful`，首页 HTTP 为 200 或 3xx。验收失败时站点会停在维护模式，并保留覆盖前的备份。

回滚命令形如：

```bash
sudo /root/site-migrate.sh rollback --backup /root/site-migrate-backup-时间 --yes
```

以导入时终端实际打印的命令为准。

## 其他命令

```bash
sudo ./site-migrate.sh export --help
sudo ./site-migrate.sh setup --domain 新域名 --root /var/www/drupal --php 8.5
sudo ./site-migrate.sh import --pack /root/site-migrate-时间.tgz --domain 新域名 --reset-admin-pass
```

同一时间只允许一个 `site-migrate.sh` 运行。日志在 `/var/log/site-migrate.log`，权限 `600`，数据库口令和 `hash_salt` 会打码。

PHP 只要求主次版本与导出时相同（例如都是 8.5）。补丁版本不同会记一条警告后继续。Drupal 核心版本必须与包内完全一致。

尚未在真实环境完成端到端测试，建议先在测试服务器验证后再用于生产。
