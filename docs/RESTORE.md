# 站点恢复

用仓库根目录的 `install-restore.sh`，在全新 Ubuntu 24.04 或 26.04 上安装环境、拉取最新代码、构建主题 `xedc`，并用 `config/sync` 执行 `drush site:install --existing-config`。

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

默认目录 `/var/www/drupal`。该目录已存在且未加 `--yes` 时，脚本立即退出，不安装软件包，也不重启服务。管理员和数据库口令写在 `/root/xedc-restore-credentials.txt`（权限 `600`）。导入成功、部分成功、失败或预检失败都会写这个文件，失败时不会写成成功。

## 配置自愈

每次重新 clone 之后、替换本站域名之前，脚本只处理这次 clone 出来的 `config/sync`。不改仓库里的文件，也不重命名。

只检查顶层 `.yml`，跳过 `language/` 等子目录。只读顶层 `id`；没有顶层 `id` 的文件不处理。`name`、`vid`、`type` 不参与判断。文件名（去掉 `.yml`）若不以 `.` 加该 `id` 结尾，视为不一致。

不一致文件只有同时满足三点才删除：目录里另有一个顶层 `id` 相同、且文件名本身与 `id` 一致的文件；把两个文件名里的 `_` 都换成 `.` 后完全相同。否则只告警。相同 `uuid` 的重复只告警，不因此删除。

实际删除前会先打印「将要删除的文件」和「只告警的文件」。自愈结果写入日志和凭据文件的「自愈记录」。工作副本里还会放一个拒绝访问的 `config/sync/.htaccess`，该文件不进入仓库。

## 安装流程

空库使用 `drush site:install --existing-config --config-dir=<工作副本>/config/sync`，语言为 `zh-hans`。不再把 `standard` 当作安装参数，也不再分阶段 `--partial` 导入，更不会手工创建内容类型或词汇。

自愈之后做预检，保留这些检查：`core.extension.yml`、`system.site.yml`、节点/分类 bundle 引用、模块和主题的 `.info.yml`。自愈后仍有无法处理的问题才算预检失败：打印明细，不执行 `site:install`，但继续设置权限、cron，并写凭据，状态为「预检失败」。

`site:install` 的报错不等于整体失败。无论它是否报错，都会执行 `drush cim -y`，输出在 `/var/log/xedc-restore-install.log`。不能因为库里已经有表就跳过这次导入。中文安装没有留下站点时，才清空数据库并去掉 `--locale` 再试一次安装，然后仍然导入。

`cim` 失败时先打印 `[Exception]` 之后的原文（并把 `&#039;` 还原为 `'`，最多 15 行）。只有报错含 `entity with ID '<id>' already exists` 时，才按配置名前缀推断实体类型（例如 `metatag.metatag_defaults.*` 对应 `metatag_defaults`），执行 `drush entity:delete <实体类型> <id> -y` 后重试，最多 8 轮。只删除配置实体，不删除节点、用户、媒体。其他错误不自动处理。`cim` 成功后再执行一次 `drush cim -y`。

若 `drush config:status --format=list` 仍有差异，把活动配置导出到 `/tmp/xedc-cex`。只有名称以 `core.entity_form_display.` 或 `core.entity_view_display.` 开头，且用 python3 的 yaml 去掉 `hidden` / `content` 下的 `publish_on`、`unpublish_on` 后与工作副本相等（忽略键顺序）的文件，才复制回工作副本。这用于消掉 Scheduler 补上的发布时间字段和 view display 的键顺序差异。其余差异保留。复制后再统计一次。

导入后若 Drush 改写了 `config_sync_directory`，脚本只把这一项改回 `../config/sync`。若它指向 `sites/default/files` 下的随机目录，脚本改回该相对路径并删除多余目录，再执行 `drush cr`。

域名替换只发生在本次 `git clone` 的 `config/sync` 上，并且只处理本站旧域名。替换后用 python3 的 yaml（没有该模块时用 PHP Symfony Yaml）确认全部 YAML 仍可解析；解析失败则恢复原文件并报错。

已有真实站点是指 `node_field_data` 行数大于 0，或存在 `uid>1` 的用户。没有 `--reinstall` 时跳过安装和配置导入，不改数据库。不能用「库里有表」代替这个判断。`--reinstall` 会删库后重装；库里已有真实内容时还要同时传入 `--yes`。只有管理员、没有节点的已安装站点会跳过 `site:install`，但仍继续 `drush cim`。

## 状态

凭据文件里的「配置导入」与日志一致：

| 状态 | 含义 |
| --- | --- |
| 成功 | `cim` 完成，且最终 `config:status` 差异为 0 |
| 部分成功（差异 N 项，详见日志） | `cim` 完成，仍有未回写的差异。日志里有前 20 个配置名，每项最多 5 行 diff |
| 失败 | `cim` 最终失败，并附第一条错误原文 |
| 预检失败 | 自愈后仍有无法处理的问题，未执行 `site:install` |
| 已跳过（站点已有内容，未改动数据） | 已有真实站点，且没有 `--reinstall` |

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

- `config/sync` 可能和原站点当时的实际配置不一致。空库安装以仓库里的 `config/sync` 为准。
- 不恢复用户数据和上传文件。旧目录会备份为 `*.bak.时间戳`，其中的文件不会自动进新站点。
- 默认数据库名是 `drupal`。同名库若 `node_field_data` 有行，或有 `uid>1` 的用户，且没有 `--reinstall`，脚本跳过安装，不删除数据。要删库重装必须同时传入 `--reinstall --yes`。
- 每次克隆使用新的 `hash_salt`。锁定版本不是 11.4.11 时脚本停止。
- 重复运行会再次克隆。已有真实内容时不重装；只有空表的站点会跳过 `site:install` 并重新导入配置。

## 执行后检查

```bash
sudo cat /root/xedc-restore-credentials.txt
```

脚本结束时会在终端和凭据文件各写一行：

```text
验收：bootstrap=<Successful|Failed>  配置差异=<N>  node类型=<列表>  首页HTTP=<状态码>
```

首页状态码来自 `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1 -H "Host: <域名>"`。

- 首页和 `/user/login` 可打开，CSS/JS 不是 404
- 前台主题为 `xedc`：`drush config:get system.theme default`
- 日志中的本站地址已换成新域名；Matomo、SMTP 服务器、外部邮箱仍是原值
- `systemctl status nginx php8.5-fpm mariadb` 为 active
- 定时发布依赖 cron，默认每 15 分钟：`/etc/cron.d/xedc-drupal`

确认可用后再删除 `*.bak.*` 备份。

## HTTPS

`--ssl` 使用 Certbot HTTP-01，80 端口必须能从公网访问。成功后 80 端口除证书校验外跳转到 HTTPS。Nginx 1.25.1 及以上使用 `http2 on`，更早版本使用 `listen 443 ssl http2`。证书申请失败时站点保持 HTTP，脚本以非零状态结束。已有对应证书时，不加 `--ssl` 也会按 HTTPS 写 Nginx 配置。
