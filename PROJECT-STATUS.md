# XEDC 项目状态（按需读取）
更新：2026-10-24

## 路径
- 会员中心：web/modules/custom/xedc_member/（路由 /member/*，CSS 为模块独立 css/member.css）
- 主题：web/themes/custom/xedc
- 运行站点实际配置同步目录是 sites/default/files/config_*/sync，不是 config/sync（settings.php 918 行）。active 与两处 sync 各有 22-24 项差异，禁止 cim。

## 会员中心设计约定
- 复用主题 .container，不另建容器，不用负 margin 掩盖间距
- 封面：max_650x650(1x)/max_1300x1300(2x) srcset，3:4，缺图用 .xm-card__ph
- 按钮样式限定在 .xm / .xm-page / .xm-confirm-form，不全局覆盖
- 改 UI 需检查 1440/1024/768/390 四断点
- 收藏/历史每页 12 条，评论/投稿每页 20 条

## 必须保留的无关 WIP（不得回滚）
xedc.theme、xedc.libraries.yml、article-detail 相关模板/CSS/JS、xa_views 模块

## 已知风险（未处理，待授权）
1. 媒体文件为 public，待审内容文件可匿名访问
2. PHP 上传上限 64MB，低于视频配置 200MB
3. content_editor 角色权限过大
4. 配置源不一致，上线前需先决定权威源
5. article/video 无评论字段，评论仅 photo 可用

## 详细历史
MEMBER-STAGE1~5-REPORT.md、MEMBER-STAGE5-UI-REPORT.md。仅在排查具体问题时读对应报告。
