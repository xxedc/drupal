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

默认目录 `/var/www/drupal`。该目录已存在且未加 `--yes` 时，脚本立即退出，不安装软件包，也不重启服务。管理员和数据库口令写在 `/root/xedc-restore-credentials.txt`（权限 `600`）。成功、部分成功、失败或已跳过都会写这个文件。凭据、日志和最后一行摘要里的「整体」是同一个值，失败不会写成成功。

## 配置自愈

每次重新 clone 之后、替换本站域名之前，脚本只处理这次 clone 出来的 `config/sync`。不改仓库里的文件，也不重命名。

只检查顶层 `.yml`，跳过 `language/` 等子目录。只读顶层 `id`；没有顶层 `id` 的文件不处理。`name`、`vid`、`type` 不参与判断。文件名（去掉 `.yml`）若不以 `.` 加该 `id` 结尾，视为不一致。

不一致文件只有同时满足三点才删除：目录里另有一个顶层 `id` 相同、且文件名本身与 `id` 一致的文件；把两个文件名里的 `_` 都换成 `.` 后完全相同。否则只告警。相同 `uuid` 的重复只告警，不因此删除。

实际删除前会先打印「将要删除的文件」和「只告警的文件」。自愈结果写入日志和凭据文件的「自愈记录」。工作副本里还会放一个拒绝访问的 `config/sync/.htaccess`，该文件不进入仓库。

## 安装流程

空库使用 `drush site:install --existing-config --config-dir=<工作副本>/config/sync`，语言为 `zh-hans`。不再把 `standard` 当作安装参数，也不再分阶段 `--partial` 导入，更不会手工创建内容类型或词汇。

自愈之后做预检，保留这些检查：`core.extension.yml`、`system.site.yml`、节点/分类 bundle 引用、模块和主题的 `.info.yml`。自愈后仍有无法处理的问题才算预检失败：打印明细，不执行 `site:install`，但继续设置权限、cron，并写凭据。配置预检记为「预检失败」，整体记为「失败」。

`site:install` 使用 `drush -vvv`，输出写入 `/var/log/xedc-restore-install.log`。它报错不等于整体失败，也不会阻止后面的 `drush cim`。失败时会把异常之后、堆栈里含 `modules/`、`core/modules` 或 `profiles/` 的前 15 行打到终端和这份日志，用来定位 Missing bundle。中文安装没有留下站点时，才清空数据库并去掉 `--locale` 再试一次，然后仍然导入。不能因为库里已经有表就跳过导入。

每次 `drush cim -y` 之前先 `drush cr`，再每 3 秒查询 `semaphore` 里 `config_importer%` 的锁，最多等 60 秒。超时后，只有 `node_field_data` 行数为 0 且没有 `uid>1` 的用户时，才删除这把锁；库里已有真实内容则直接失败，不删锁。接着用 `drush php:eval` 数 `\Drupal::service('config.storage.sync')->listAll()`。这个数量为 0，或与工作副本 `config/sync` 顶层 `.yml` 相差超过 2，就记为「失败：同步目录不可读」，把 `Settings::get('config_sync_directory')` 和当前目录写入日志，并且不执行 `cim`。

导入计划不用 `cim --no`。用 `drush config:status --state='Only in DB' --format=list` 和 `--state='Only in sync dir' --format=list`。`Only in DB` 里的 `core.entity_view_mode.*.token` 正常，忽略。下面任一情况视为计划异常，不执行 `cim -y`：

- `Only in DB` 含 `core.extension`、`system.site` 或任何 `node.type.*`
- `Only in sync dir` 为 0，而 `config/sync` 里有文件，并且同步存储读不到这些文件，或数据库里的 node 类型还是 0

同步存储数量正常、计划不会删除上述核心配置、而且数据库里已经有 node 类型时，`Only in sync dir` 为 0 只表示没有待创建项，重复运行不会因此判成计划异常。计划异常时释放锁、等 10 秒、`drush cr` 后再验，最多 3 次。仍然异常则记为「失败：导入计划异常」，两个列表的前 20 项写入日志和凭据。随后继续权限、cron 和凭据，但跳过主题安装和翻译导入。

`cim` 不能只看退出码。输出必须包含 `The configuration was imported successfully`，或者已经没有变更时的 `There are no changes to import`，并且不能包含 `Another request may be synchronizing`。出现这句锁警告就视为没执行，等待锁后重试，最多 5 次。只有报错含 `entity with ID '<id>' already exists` 时，才按配置名前缀删除配置实体后重试，最多 8 轮。只删除配置实体，不删除节点、用户、媒体。失败时仍打印 `[Exception]` 之后的原文。

第一次判定成功后，再循环 `drush cim -y`，最多 6 轮。每轮之后用 `drush config:status --format=list` 统计差异并写入日志。差异为 0、连续两轮不再减少，或满 6 轮就停。循环中某轮报错或再次出现锁警告，按上面的 5 次锁重试处理。Drush 没有 `config:list`，所有 `config:status` 都带 `--format=list`。

只有 `cim` 判定成功，才执行 `theme:install`、写入 `system.theme:default` 和翻译导入。否则这几步和差异回写全部跳过，并在日志写明原因。

其后若仍有差异，用 `drush cex -y --destination=/tmp/xedc-cex` 导出，再用 python3 的 yaml 比较工作副本和导出文件（忽略键顺序）。只有内容相等，或差异仅仅是 `core.entity_form_display.*` / `core.entity_view_display.*` 里 `hidden` 和 `content` 下的 `publish_on`、`unpublish_on`，才把导出文件复制回工作副本。`views.view.*`、`node.type.*`、`field.*`、`media.type.*` 一律不回写。只改这次 clone 的本地文件，脚本不执行 `git commit` 或 `git push`。回写后再统计一次 `config:status`。

导入后若 Drush 改写了 `config_sync_directory`，脚本只把这一项改回 `../config/sync`。若它指向 `sites/default/files` 下的随机目录，脚本改回该相对路径并删除多余目录，再执行 `drush cr`。

域名替换只发生在本次 `git clone` 的 `config/sync` 上，并且只处理本站旧域名。替换后用 python3 的 yaml（没有该模块时用 PHP Symfony Yaml）确认全部 YAML 仍可解析；解析失败则恢复原文件并报错。

已有真实站点是指 `node_field_data` 行数大于 0，或存在 `uid>1` 的用户。没有 `--reinstall` 时跳过安装和配置导入，不改数据库。不能用「库里有表」代替这个判断。`--reinstall` 会删库后重装；库里已有真实内容时还要同时传入 `--yes`。只有管理员、没有节点的已安装站点会跳过 `site:install`，但仍继续 `drush cim`。

## 状态

凭据文件、`/var/log/xedc-restore-install.log` 和终端最后一行使用同一个「整体」：

| 整体 | 含义 |
| --- | --- |
| 成功 | `cim` 判定成功，`config:status` 差异为 0，数据库 node 类型数等于 `config/sync/node.type.*.yml` 的数量，首页 HTTP 为 200 或 30x |
| 部分成功 | `cim` 判定成功，node 类型数一致，首页为 200 或 30x，但 `config:status` 仍有差异。不设差异上限。日志按前缀统计（例如 `views.view 22、media.type 3`），列出 `Only in sync dir` 的全部项和 `Different` 的前 30 项 |
| 失败 | `cim` 未成功、同步目录不可读、导入计划异常、node 类型数不符、首页 5xx，以及其余没有达到成功或部分成功的情况。日志和凭据写明原因 |
| 已跳过 | 已有真实站点，且没有 `--reinstall`。这是保留的旧行为，不改数据库 |

「失败：同步目录不可读」和「失败：导入计划异常」写在配置导入和失败原因里，整体仍是「失败」。预检未通过时整体也是「失败」，配置预检栏仍写「预检失败」。

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
验收：bootstrap=<Successful|Failed>  配置差异=<N>  node类型=<列表>  首页HTTP=<状态码>  整体=<成功|部分成功|失败>
```

已有真实站点且未重装时，整体为「已跳过」。首页状态码来自 `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1 -H "Host: <域名>"`。返回 5xx 时，脚本把 `/var/log/nginx/error.log` 和 PHP-FPM 日志里最后 3 条完整错误行写入日志、凭据，并打到终端，不截断。

- 首页和 `/user/login` 可打开，CSS/JS 不是 404
- 前台主题为 `xedc`：`drush config:get system.theme default`
- 日志中的本站地址已换成新域名；Matomo、SMTP 服务器、外部邮箱仍是原值
- `systemctl status nginx php8.5-fpm mariadb` 为 active
- 定时发布依赖 cron，默认每 15 分钟：`/etc/cron.d/xedc-drupal`

确认可用后再删除 `*.bak.*` 备份。

## 故障排查

- **Missing bundle / `entity type node_type`**：看安装日志里的 `-vvv` 输出，以及终端上含 `modules/` 或 `profiles/` 的堆栈。这只用于定位模块，不代替配置导入。
- **`Another request may be synchronizing` 且退出码为 0**：这次 `cim` 没有导入。崩溃的 `site:install` 可能留下 `config_importer` 锁。应等锁释放或在空库上删锁后再导入，不能把退出码 0 当成成功。
- **导入计划全是 Delete**：同步目录未被读到，或锁还在。先看日志里的 `listAll` 数量和 `config_sync_directory`。这种计划会被拒绝，避免删掉 `core.extension` 和 node 类型。
- **单轮 `cim` 后仍有差异**：正常。再跑几轮，直到 `config:status --format=list` 不再下降。`views.view`、`media.type` 一类差异会留在「部分成功」里，不会回写。
- **首页 500，`TypeError` … `Language::sort()`**：配置没有真正导入，node 类型往往是 0。先看整体是不是「失败」，再看 nginx 和 PHP-FPM 的最后几条错误。
- **`apt-get update` 报 `File has unexpected size` 或 `Mirror sync in progress`**：脚本会清空 `/var/lib/apt/lists` 后重试，最多 3 次，间隔 20 秒。源里仍是 `ec2.archive.ubuntu.com` 时会改成 `archive.ubuntu.com` 再试一次。只有最后的 `apt-get install` 失败才中止。

## HTTPS

`--ssl` 使用 Certbot HTTP-01，80 端口必须能从公网访问。成功后 80 端口除证书校验外跳转到 HTTPS。Nginx 1.25.1 及以上使用 `http2 on`，更早版本使用 `listen 443 ssl http2`。证书申请失败时站点保持 HTTP，脚本以非零状态结束。已有对应证书时，不加 `--ssl` 也会按 HTTPS 写 Nginx 配置。
