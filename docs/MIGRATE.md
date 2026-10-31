# 站点搬家

把正在运行的 Drupal 站点搬到另一台服务器，或在同一台服务器上从备份包恢复。

代码以 GitHub 仓库为准。数据库和上传文件由仓库根目录的 `migrate-site.sh` 打包、导入和回滚。旧服务器上的 `export` 默认只读：不改数据库内容、不改上传文件、不改 `settings.php`。任何会覆盖数据库或上传文件的步骤都会先自动备份。

脚本不改写 Git 历史，也不会把备份包上传到 GitHub。日志在 `/var/log/xedc-migrate.log`（权限 `600`）。导入验收写在 `/root/xedc-migrate-report.txt`（权限 `600`）。这两个文件和终端输出都不会写入数据库口令。

请用 root 运行。

## 快速使用

从旧服务器打包到新服务器恢复，只需三步。

### 1. 旧服务器打包

```bash
cd /var/www/drupal
sudo ./migrate-site.sh export --out /root/xedc-migrate --maintenance --yes
```

跑完后终端会打印出完整的 `.tgz` 路径（例如 `/root/xedc-migrate/xedc-migrate-20261031-150000.tgz`），复制这个路径。

### 2. 传到新服务器

```bash
scp /root/xedc-migrate/xedc-migrate-实际时间.tgz root@新服务器IP:/root/
```

也可以先下载到本地，再从本地上传到新服务器。包内含用户邮箱和密码哈希，用完后两边都删除。

### 3. 新服务器恢复

```bash
curl -fsSL -o /root/migrate-site.sh \
  https://raw.githubusercontent.com/xxedc/drupal/main/migrate-site.sh
chmod +x /root/migrate-site.sh

sudo /root/migrate-site.sh import \
  --pack /root/xedc-migrate-实际时间.tgz \
  --domain 你的新域名 \
  --root /var/www/drupal \
  --force --yes
```

导入结束后查看 `/root/xedc-migrate-report.txt`。用 `curl -sI -H "Host: 你的新域名" http://127.0.0.1` 验证首页。

以下是详细说明。

## 流程

1. 在旧服务器导出。
2. 用 `scp` 把单个压缩包拷到新服务器。不要放进 Git 仓库。
3. 在新服务器导入。目录不存在或站点未安装时，脚本会下载并运行 `install-restore.sh` 来安装 Nginx、PHP-FPM、MariaDB 和代码。
4. 对照节点数、用户数、文件数、bootstrap 和首页 HTTP。
5. 用 hosts 或带 `Host` 头的 curl 确认后，再切 DNS。旧服务器至少再留几天。

## 导出

在旧服务器的仓库根目录：

```bash
cd /var/www/drupal
sudo ./migrate-site.sh export
```

常用形式：

```bash
sudo ./migrate-site.sh export --root /var/www/drupal --out /root/xedc-migrate
sudo ./migrate-site.sh export --maintenance --yes
```

导出过程：

1. 确认 `vendor/bin/drush` 可执行，并且 `drush status` 的 bootstrap 为 `Successful`。
2. 检查 `git status`，以及相对本机远端跟踪分支尚未出现的提交。有这类差异时列出明细，并警告「新服务器只能拉到 GitHub 上的代码」。不加 `--yes` 就停止。这一步不访问网络，也不更新远端跟踪分支。
3. 只有加了 `--maintenance` 才执行 `drush sset system.maintenance_mode 1`。脚本正常结束或异常退出时都会把它写回 `0`，包括开始前已经处于维护模式的情况。
4. `drush sql:dump --gzip`。`cache`、`cache_*`、`sessions`、`watchdog` 只导出结构，通过 `--structure-tables-list` 传入实际表名。表前缀来自 Drupal 连接信息，只接受字符串前缀。
5. 打包 `web/sites/default/files`，排除名为 `php`、`css`、`js`、`styles` 的目录。这些是聚合资源和图片样式，导入后由 Drupal 重新生成。用 `drush php:eval` 读取 `file_private_path`；值非空且目录存在时另行打包，并在 manifest 里记录原路径和绝对路径。
6. 写 `manifest.txt`：时间、Drupal 版本、PHP 版本、MariaDB 版本、git 提交号、旧站域名、`node_field_data` 行数、`users` 行数、files 文件数、各打包文件的 sha256。
7. 打成一个权限 `600` 的 `.tgz`，打印完整路径和大小，并提示用 `scp` 传输。包里有用户邮箱和密码哈希，不要放进 GitHub，用完在两边删除。

文件数只计普通文件。公共目录按上面的排除规则计数；私有目录若不在公共 files 里，或落在被排除的目录中，再单独计入。

重复执行 `export` 会生成新的时间戳包，不覆盖旧包，也不修改站点。

## 传输

```bash
scp /root/xedc-migrate/xedc-migrate-时间.tgz root@新服务器:/root/
```

不要把这个文件提交到仓库，也不要放到 Web 可下载的目录。传输完成后，旧服务器上的包可以在确认新站可用后删除。

## 导入

新服务器上可以先拿到脚本：

```bash
curl -fsSL -o /root/migrate-site.sh \
  https://raw.githubusercontent.com/xxedc/drupal/main/migrate-site.sh
chmod +x /root/migrate-site.sh
sudo /root/migrate-site.sh import --pack /root/xedc-migrate-时间.tgz --domain example.com
```

目标库已有节点，或存在 `uid>1` 的用户时，必须同时加上 `--force` 和 `--yes`：

```bash
sudo /root/migrate-site.sh import \
  --pack /root/xedc-migrate-时间.tgz \
  --domain example.com \
  --root /var/www/drupal \
  --force --yes
```

导入过程：

1. 确认包存在。解压前检查 `/root` 和站点所在文件系统的剩余空间都不小于包大小的 3 倍。解压后按 manifest 逐个核对 sha256，不一致就中止。然后打印 manifest。这一步不改站点。
2. `--root` 不存在，或还没有可用的 Drupal（没有 drush、没有 `settings.php`、没有 `users_field_data`）时，下载并运行 `https://raw.githubusercontent.com/xxedc/drupal/main/install-restore.sh`，传入域名、`--yes` 和 `--app-root`。该脚本的最终状态是「失败」或「部分成功」都不会中止，因为接下来会用数据库整体覆盖。但 bootstrap 必须成功且 drush 可用，否则中止并打印原因。目录已存在时，`install-restore.sh` 会先把整个目录改名备份再克隆。若 bootstrap 失败但库里已经有 `users_field_data`，脚本拒绝搬家，避免移走现有代码。
3. 安全闸：`node_field_data` 行数大于 0，或存在 `uid>1` 的用户时，必须同时有 `--force` 和 `--yes`，否则不备份、不覆盖。通过之后、删除数据之前，自动备份到：
   - `/root/xedc-premigrate-<时间>.sql.gz`
   - `/root/xedc-premigrate-<时间>-files.tgz`
   终端和日志都会打印这两个路径，以及对应的 rollback 命令。文件包里是当时的 `files` 目录；若 `settings.php` 里的私有目录存在，也会放进同一个文件包。
4. 打开维护模式。出错时提示维护模式仍开启，并给出 rollback 命令，不会静默改回公开访问。然后 `drush sql:drop -y`，`gunzip -c` 数据库包再交给 `drush sqlc`。公共文件先删除再解压到 `web/sites/default`。私有文件解压到 manifest 记录的路径（没有则创建）。对照 `settings.php` 的 `file_private_path`，不一致只警告，不改 `settings.php`。接着 `chown -R www-data:www-data` 这些文件目录，`drush updb -y`，`drush cr`，再关闭维护模式。`updb` 或 `cr` 失败不会把整体写成成功。
5. 新旧域名不同时，检查 `trusted_host_patterns` 是否包含新域名，以及 `simple_sitemap.settings` 的 `base_url` 等配置是否仍含旧域名。只打印配置名，不打印配置值，也不自动修改。
6. 用同一套计数规则对比 manifest 和新服务器的节点数、用户数、文件数，逐项打印「一致」或「不一致」。检查 bootstrap。首页使用 `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1 -H "Host: <域名>"`（另有连接超时，避免一直卡住）。返回 5xx 时，把 Nginx 和 PHP-FPM 日志里最后 3 条完整错误行打到终端。
7. 写一行验收摘要到 `/root/xedc-migrate-report.txt`。
8. 提示：导入后的管理员是旧站账号，不是 `install-restore.sh` 生成的 admin；切 DNS 前先用 hosts 或 curl 测试；旧服务器至少保留几天。

`install-restore.sh` 生成的管理员会被导入的旧库覆盖。登录口令是旧站的口令。

## 验收标准

报告文件只有这一行：

```text
搬家验收：节点=<新/旧>  用户=<新/旧>  文件=<新/旧>  bootstrap=<…>  首页HTTP=<…>  整体=<成功|失败>
```

整体为「成功」必须同时满足：

- 节点数、用户数、文件数都与 manifest 一致
- bootstrap 为 `Successful`
- 首页 HTTP 为 200 或 3xx
- `drush updb -y`、`drush cr` 和关闭维护模式没有失败

域名不一致、私有路径与 `settings.php` 不一致，只产生警告，不单独把整体改成失败。需要在切 DNS 前按警告处理。

## 切 DNS

先不要改权威 DNS。在操作者自己的机器上，把新域名指到新服务器 IP，或在新服务器上执行：

```bash
curl -sI -H "Host: example.com" http://127.0.0.1
```

确认首页、登录页和已有内容后再改 DNS。CDN 或浏览器可能还缓存旧地址，观察一段时间再停旧服务器。

## 回滚

`rollback` 恢复的是 **import 覆盖之前** 自动生成的备份，不是再做一次 export。必须带 `--yes`，否则只打印用法。

```bash
sudo ./migrate-site.sh rollback \
  --backup /root/xedc-premigrate-时间.sql.gz \
  --root /var/www/drupal \
  --yes
```

同目录若有同时间戳的 `/root/xedc-premigrate-<时间>-files.tgz`，会一并恢复公共文件和当时记录的私有文件。没有这个文件时只恢复数据库，并明确警告。

回滚会先再备份当前库和文件到 `/root/xedc-prerollback-<时间>.sql.gz` 与对应的 `-files.tgz`，然后开维护模式、`drush sql:drop -y`、导入指定备份、恢复文件、`drush cr`、关闭维护模式，并打印验收。文件包会在删除现有数据之前完成解压检查。

## 旧站回退

`export` 不修改旧站数据。若新站导入后发现问题：

- 还没切 DNS：继续使用旧服务器，不需要在旧站做回滚。
- 已经切了 DNS：把 DNS 指回旧服务器 IP。旧站数据库和文件仍是导出时的内容（导出期间若加了 `--maintenance`，结束后维护模式会是 `0`）。
- 新服务器上想回到导入前：用上面的 `rollback`，备份文件在新服务器的 `/root/xedc-premigrate-*.sql.gz`。

旧服务器至少保留几天，确认邮件、上传和定时任务都正常后再关机。

## 参数

| 参数 | 命令 | 作用 |
| --- | --- | --- |
| `--root` | 全部 | Drupal 项目根目录，默认 `/var/www/drupal` |
| `--out` | export | 压缩包目录，默认 `/root/xedc-migrate`。不能放在站点目录里面 |
| `--maintenance` | export | 导出期间打开维护模式，结束时写回 `0` |
| `--yes` | export | 工作区不干净或有未同步提交时仍继续 |
| `--pack` | import | 导出的 `.tgz`，必填 |
| `--domain` | import | 新站域名，必填。传给 `install-restore.sh`，并用作首页 `Host` 头 |
| `--force` | import | 与 `--yes` 一起，才允许覆盖已有内容 |
| `--yes` | import | 与 `--force` 一起，才允许覆盖已有内容 |
| `--backup` | rollback | import 生成的 `.sql.gz`，必填 |
| `--yes` | rollback | 必填。不带它就只打印用法 |

参数缺失或无法识别时，脚本只打印用法，不写日志，也不访问站点。

## 安全

- 压缩包、覆盖前备份和验收报告权限都是 `600`。日志权限也是 `600`。
- 包内有用户邮箱和密码哈希。不要放进 GitHub，不要放到可被 Web 访问的目录，用完在两边删除。
- 脚本不打印、不记录数据库口令。Drush 或安装脚本若把口令打到输出里，写入日志前会打码；仍不要把日志公开。
- `export` 不执行 `sql:drop`，不改 `settings.php`，不改上传文件。唯一的写操作是显式传入 `--maintenance` 时切换维护模式，并在退出时写回 `0`。
- 导入和回滚都不自动修改 `settings.php`、`trusted_host_patterns` 或 sitemap 的 `base_url`。
- 覆盖前必有备份。目标库已有真实内容时，少了 `--force` 或 `--yes` 都会停止。
- 同时只允许一个 `migrate-site.sh` 运行。
