# XEDC Drupal 11 项目

面向生产环境的 Drupal 11.4.11 站点，包含自定义主题 `xedc`、自定义模块、配置同步和一键恢复脚本。

## 快速恢复（新服务器）

在全新的 Ubuntu 24.04 或 26.04 服务器上执行以下命令即可完成环境安装、代码部署、空站点安装和配置导入：

```bash
curl -fsSL -o /root/install-restore.sh \
  https://raw.githubusercontent.com/xxedc/drupal/main/install-restore.sh
chmod +x /root/install-restore.sh
sudo /root/install-restore.sh example.com
```

更详细的使用说明、参数说明、已知风险和执行后检查项请参见：

**[docs/RESTORE.md](docs/RESTORE.md)**

脚本链接：[install-restore.sh](install-restore.sh)

## 安装完成后如何查看数据库账户和密码

脚本会自动生成数据库账户、数据库密码，以及 Drupal 管理员账户（默认用户名 `admin`）和密码，并写入以下文件：

```bash
sudo cat /root/xedc-restore-credentials.txt
```

文件权限为 `600`，仅 root 可读。里面会清晰列出：

- 数据库名、用户名、密码
- Drupal 管理员用户名和密码
- 站点域名等其他关键信息

你也可以在运行脚本时自己指定管理员账户和密码：

```bash
sudo /root/install-restore.sh example.com --admin-user myadmin --admin-pass 'YourSecurePassword'
```

## 重要说明

- 仅恢复代码、主题、模块、`config/sync` 和翻译文件。不恢复用户内容、上传文件或数据库数据。
- 严格使用仓库中的 `composer.lock`，安装 Drupal 11.4.11 及所有已锁定的 contrib 模块，不会执行 `composer update`。
- 每次运行脚本都会从本仓库拉取最新内容。
- 导入前会把配置里属于本站的绝对地址改成传入的域名。外部统计、SMTP 服务器和外部邮箱保持不变，详见 `docs/RESTORE.md`。
- 仓库中的 `PROJECT-STATUS.md` 提到实际运行配置与提交的 `config/sync` 存在差异，直接导入可能与原站点不完全一致。

## 仓库结构概览

- `web/`：Drupal 文档根目录
- `config/sync/`：配置同步
- `_server/`：服务器配置参考（Nginx / PHP 8.5）
- `docs/`：详细文档
- `translations/`：翻译文件

如有问题请查看 `docs/RESTORE.md` 或直接查看脚本注释。
