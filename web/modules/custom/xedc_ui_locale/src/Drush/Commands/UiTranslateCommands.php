<?php

declare(strict_types=1);

namespace Drupal\xedc_ui_locale\Drush\Commands;

use Drupal\xedc_ui_locale\UiTranslationFiller;
use Drush\Attributes as CLI;
use Drush\Commands\DrushCommands;

/**
 * Fills missing Simplified Chinese interface translations.
 */
final class UiTranslateCommands extends DrushCommands {

  public function __construct(
    private readonly UiTranslationFiller $filler,
  ) {
    parent::__construct();
  }

  /**
   * Imports official zh-hans UI packs, then translates the rest with the API.
   */
  #[CLI\Command(name: 'xedc:ui-translate', aliases: ['xedc-ui-translate'])]
  #[CLI\Argument(name: 'modules', description: 'Comma-separated module machine names. Omit to use modules installed since the last run.')]
  #[CLI\Option(name: 'all', description: 'Scan every enabled contributed and custom module')]
  #[CLI\Usage(name: 'drush xedc:ui-translate scheduler', description: 'Import official Chinese and API-translate Scheduler')]
  #[CLI\Usage(name: 'drush xedc:ui-translate --all', description: 'Do the same for every enabled contributed and custom module')]
  #[CLI\Usage(name: 'drush xedc:ui-translate', description: 'Fill translations for modules installed since the last run')]
  public function translate(?string $modules = NULL, array $options = ['all' => FALSE]): void {
    if (!empty($options['all'])) {
      $names = $this->filler->contributableModules();
    }
    elseif ($modules !== NULL && trim($modules) !== '') {
      $names = array_values(array_filter(array_map('trim', explode(',', $modules))));
    }
    else {
      $names = $this->filler->pendingModules();
    }
    if (!$names) {
      $this->logger()->warning('没有待补全的模块。用法：drush xedc:ui-translate MODULE，或 drush xedc:ui-translate --all');
      return;
    }

    $result = $this->filler->fill($names);
    if ($result['api_ready']) {
      $this->logger()->notice('未翻译的界面字符串使用 {provider} 自动翻译为简体中文。API Key 从 State 读取。', [
        'provider' => $result['provider'],
      ]);
    }
    else {
      $this->logger()->warning('未配置 {provider} API Key，已跳过自动翻译。请在 /admin/config/regional/xedc-auto-translate 保存 Key。', [
        'provider' => $result['provider'] !== '' ? $result['provider'] : 'DeepL 或 Microsoft Translator',
      ]);
    }
    foreach ($result['errors'] as $error) {
      $this->logger()->error('{error}', ['error' => $error]);
    }
    foreach ($result['files'] as $file) {
      $this->logger()->notice('已处理 {file}', ['file' => $file]);
    }
    if ($result['brand_skipped'] > 0) {
      $this->logger()->warning('有 {brand} 条因为品牌名 DcLili、模块名或占位符未能还原而跳过。', [
        'brand' => $result['brand_skipped'],
      ]);
    }
    foreach ($result['modules'] as $module => $scan) {
      $this->logger()->notice('模块 {module}：官方包导入 {official} 条，API 自动翻译 {api} 条，仍剩余 {remaining} 条。', [
        'module' => $module,
        'official' => $scan['official'],
        'api' => $scan['api'],
        'remaining' => $scan['remaining'],
      ]);
      foreach ($scan['samples'] as $sample) {
        $this->logger()->warning('  - {sample}', ['sample' => $sample]);
      }
    }
  }

}
