# Drupal 项目规则
回复使用中文，简洁。

## 环境
Drupal 11，根目录 /var/www/drupal；主题 web/themes/custom/xedc；自定义模块以 web/modules/custom/ 实际目录为准；配置目录 config/sync。主题构建：主题目录 npm run build。
项目背景见 PROJECT-STATUS.md，仅在任务相关时读取，不要默认读取。

## 修改原则
- 先查现有代码，复用已有实现；字段名/路由/依赖不确定时先查，不猜。
- 只改任务必需的文件；不重构、不顺手修复无关问题。
- 需求模糊或要改 3 个以上文件时，先给方案，等确认再改。
- 不覆盖未提交改动；操作前 git status。
- 遵循 Drupal 11 API、缓存、安全规范；沿用 Bootstrap 5 和现有样式，不引入新框架。

## 禁止（未经明确授权）
- 修改 vendor/、web/core/、web/modules/contrib/、settings.php、Nginx/PHP-FPM/数据库配置
- drush cim / cex / 数据库清空 / 模块卸载 / 安装新依赖
- git reset / clean / commit / push
- 新建报告、总结类 md 文件
- 读取 build/、node_modules/、vendor/、web/core/、sites/default/files/
- 除非任务涉及会员中心或配置同步，否则不读取 PROJECT-STATUS.md 和 MEMBER-*.md

## 验证与汇报
- 改了主题 SCSS/JS 源文件后，在主题目录执行 npm run build；仅改模块独立 CSS 或 Twig/PHP 时不要构建。构建后用 git diff --stat 检查 build/，若出现与本次任务无关的大量差异，如实汇报，不要自行回滚。
- 按改动选 php -l、twig 编译、drush cr 等最小检查；不声称未运行的验证。
- 完成后只汇报：修改文件 / 改动要点 / 已运行检查 / 未验证项。
