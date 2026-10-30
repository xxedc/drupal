# XEDC Drupal 11 项目

面向生产环境的 Drupal 11.4.11 站点，包含自定义主题 `xedc`、自定义模块、配置同步与一键恢复脚本。

## 快速恢复（新服务器）

在全新 Ubuntu 24.04 服务器上执行以下命令即可完成环境安装、代码部署、空站点安装与配置导入：

```bash
curl -fsSL -o /root/install-restore.sh \
  https://raw.githubusercontent.com/xxedc/drupal/main/install-restore.sh
chmod +x /root/install-restore.sh
sudo /root/install-restore.sh example.com
```

需要 HTTPS 时可加 `--ssl --email admin@example.com`。

详细参数说明、已知风险与执行后检查项见 [docs/RESTORE.md](docs/RESTORE.md)。

## 已知风险

仓库中的 `PROJECT-STATUS.md` 提到：实际运行配置与提交的 `config/sync` 存在约 22-24 项差异，直接执行 `drush cim` 可能与原站点不完全一致。脚本会在导入前给出提示。

脚本不会恢复任何用户内容、上传文件或原有数据库数据。

## 项目结构

- `web/`：Drupal 文档根目录
- `web/themes/custom/xedc`：自定义主题
- `config/sync`：配置同步
- `_server/`：Nginx 与 PHP 参考配置
- `install-restore.sh`：一键恢复脚本

## 开发说明

严格使用仓库中的 `composer.lock`，禁止 `composer update`。
