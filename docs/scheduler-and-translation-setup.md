# 定时发布与界面翻译补全

品牌名保持 **DcLili**，不翻译。

## Scheduler 定时发布

Scheduler 已启用。美图（photo）、文章（article）、视频（video）、基本页面（page）打开了「定时发布」，编辑表单使用日期时间字段，不显示定时撤下。

内容编辑角色另有两项权限：`schedule publishing of nodes`、`view scheduled content`。管理员本身拥有全部权限。

### 使用

1. 编辑上述任一内容。
2. 打开「定时发布」。
3. 点「明天」填入明天 08:00（站点时区 Asia/Shanghai），或自己选日期和时间。留空表示不定时。
4. 美图、文章、视频保存为草稿（或其他未发布审核状态）。基本页面取消「已发布」。
5. 到点后由 cron 自动发布。审核内容会转到「已发布」；基本页面直接发布。

过去的时间不能保存。已撤下的内容没有转到「已发布」的审核转换，定时发布会失败并记在日志里，不会强行发布。

### Cron

系统已有每小时任务，会执行完整 Drupal cron，其中包含 Scheduler：

```bash
17 * * * * cd /var/www/drupal && /usr/local/bin/drush cron --quiet
```

只跑定时发布、不跑其他 cron 时：

```bash
vendor/bin/drush scheduler:cron
```

## 新模块的简体中文界面翻译

模块 `xedc_ui_locale` 在新模块安装后自动检测该模块尚未翻译的界面字符串，并走下面的补全流程。已有中文译文不覆盖（自定义和非自定义都不覆盖）。品牌名 DcLili 不翻译。模块 `.info.yml` 里的 `name` 保持原样，不交给 API，也不会被后导入的语言包改掉。

安装新模块时会自动跑一次。之后也可以手动执行。

```bash
# 补全自上次成功执行后新安装的模块
vendor/bin/drush xedc:ui-translate

# 指定模块，多个用逗号分隔
vendor/bin/drush xedc:ui-translate scheduler

# 全部已启用的贡献模块和自定义模块
vendor/bin/drush xedc:ui-translate --all
```

每个模块输出一行：

```text
模块 模块名：官方包导入 N 条，API 自动翻译 M 条，仍剩余 K 条。
```

处理顺序：

1. 登记该模块尚未翻译的界面字符串（数据库里已扫描到的，以及代码里的 `t()` / `@Translation`）。
2. 先导入该模块在 localize.drupal.org / ftp.drupal.org 上的官方 `zh-hans.po`。已下载的语言包也会再导入一次，只补还没有中文的字符串。
3. 再导入 `translations/模块名.zh-hans.po`、模块目录里的 `translations/zh-hans.po`，以及站点目录 `translations/zh-hans.admin-ui.po`。
4. 对仍然没有中文的字符串，调用当前选中的翻译 API，生成简体中文。
5. 把新译文写入 `translations/模块名.zh-hans.po`（已有 msgstr 不改），再用 locale 的 `PoDatabaseWriter` 导入，覆盖选项为不覆盖。

占位符（`@name`、`%name`、`:name`）和品牌名 DcLili、模块名字会先换成令牌再发给 API，返回后还原。还原失败或译文丢掉 DcLili / 模块名时，该条不写入。仍剩余的字符串会在命令里列出最多 30 条样例。

### API 调用

界面翻译不另存 Key，也不读内容翻译的「启用」开关。提供商和 Key 与 `xedc_auto_translate` 相同：

- 提供商：`xedc_auto_translate.settings` 的 `provider`（`deepl` 或 `microsoft`）。
- Key：State `xedc_auto_translate.api_key.deepl` 或 `xedc_auto_translate.api_key.microsoft`。State 为空时再读环境变量 `DEEPL_API_KEY`、`MICROSOFT_TRANSLATOR_API_KEY`。
- 在 `/admin/config/regional/xedc-auto-translate` 保存 Key。不要把 Key 写进代码或 `config/sync`。

调用的是 `xedc_auto_translate` 的 `Translator::translatePlainTexts()`，源语言英语，目标简体中文：

| 提供商 | 接口 | 语言 |
| --- | --- | --- |
| DeepL | `POST /v2/translate`（免费 Key 用 `api-free.deepl.com`，否则 `api.deepl.com`） | `source_lang=EN`，`target_lang=ZH`。含 HTML 时加 `tag_handling=html` |
| Microsoft Translator | `POST {终结点}`，`api-version=3.0`。终结点空则用 `https://api.cognitive.microsofttranslator.com/translate` | `from=en`，`to=zh-Hans`。含 HTML 时 `textType=html` |

Microsoft 区域用配置里的 `microsoft_region`（默认 `global`）。未配置 Key 时官方语言包仍会导入，API 条数为 0，并提示去配置页保存 Key。

## 验证

- photo、article、video、page 的 `publish_enable` 为开启，表单组件是 `datetime_timestamp_no_default`。
- 四个内容的编辑表单都能渲染出「定时发布」「发布日期和时间」「明天」以及时间输入。明天的默认值是站点时区次日 `08:00`。
- 未发布基本页面设置当前时间后，`scheduler.manager->publish()` 会发布并清空发布时间。
- 草稿文章同样会被转到「已发布」。
- 将来的发布时间在这次发布任务里保持未发布。过去时间无法通过校验。
- `drush scheduler:cron` 能跑完。
- `drush xedc:ui-translate scheduler`：官方包 `scheduler-2.3.0.zh-hans.po` 已导入（这次没有新的可补条目）。API 自动翻译 156 条，仍剩余 0 条。译文写入 `translations/scheduler.zh-hans.po`。再执行一次为官方包 0、API 0、剩余 0。
- 已有「Publish on」仍是「发布于」，「Unpublish on」仍是「取消发布于」。模块名「Scheduler」的译文是 Scheduler。`@items`、`%updated`、`%utc` 都还在。例如「Enable scheduled publishing for @items」为「为 @items 启用定时发布功能」。
- 已执行 `drush cr`。

未在浏览器里点击「明天」按钮。表单 HTML 和 `drupalSettings.xedcScheduler` 已核对。
