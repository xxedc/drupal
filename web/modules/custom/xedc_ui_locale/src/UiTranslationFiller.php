<?php

declare(strict_types=1);

namespace Drupal\xedc_ui_locale;

use Drupal\Component\Gettext\PoHeader;
use Drupal\Component\Gettext\PoItem;
use Drupal\Component\Gettext\PoStreamReader;
use Drupal\Component\Gettext\PoStreamWriter;
use Drupal\Core\Database\Connection;
use Drupal\Core\Extension\ModuleExtensionList;
use Drupal\Core\Extension\ModuleHandlerInterface;
use Drupal\Core\State\StateInterface;
use Drupal\locale\File\LocaleFile;
use Drupal\locale\LocaleFetch;
use Drupal\locale\LocaleProjectRepository;
use Drupal\locale\LocaleSource;
use Drupal\locale\PoDatabaseWriter;
use Drupal\locale\StringDatabaseStorage;
use Drupal\xedc_auto_translate\Translator;
use Psr\Log\LoggerInterface;

/**
 * Imports zh-hans interface translations without replacing existing ones.
 *
 * Official language packs are applied first. Strings that are still missing
 * are sent to the configured DeepL or Microsoft Translator API. Generated
 * strings are written under translations/ and imported with the same
 * non-overwrite rules. The brand DcLili and the module name from .info.yml
 * are kept as written.
 */
final class UiTranslationFiller {

  public const LANGCODE = 'zh-hans';

  public const BRAND = 'DcLili';

  /**
   * File-extracted sources, cached for the current fill.
   *
   * @var array<string, string[]>
   */
  private array $extracted = [];

  public function __construct(
    private readonly ModuleHandlerInterface $moduleHandler,
    private readonly ModuleExtensionList $moduleExtensionList,
    private readonly StringDatabaseStorage $storage,
    private readonly Connection $database,
    private readonly StateInterface $state,
    private readonly LoggerInterface $logger,
    private readonly LocaleProjectRepository $projectRepository,
    private readonly LocaleFetch $localeFetch,
    private readonly LocaleSource $localeSource,
    private readonly Translator $translator,
  ) {}

  /**
   * Modules enabled since the last successful fill.
   *
   * @return string[]
   */
  public function pendingModules(): array {
    $pending = $this->state->get('xedc_ui_locale.pending', []);
    return array_values(is_array($pending) ? $pending : []);
  }

  /**
   * Enabled contributed and custom modules.
   *
   * @return string[]
   */
  public function contributableModules(): array {
    $names = [];
    foreach ($this->moduleHandler->getModuleList() as $name => $extension) {
      $path = $extension->getPath();
      if (!str_starts_with($path, 'core/') && !str_starts_with($path, 'core\\')) {
        $names[] = $name;
      }
    }
    sort($names);
    return $names;
  }

  /**
   * Imports official Chinese, then fills the rest through the translation API.
   *
   * @param string[] $modules
   *   Module machine names.
   *
   * @return array
   *   Import and scan summary. Each module entry has official, api, remaining.
   */
  public function fill(array $modules): array {
    $modules = $this->normalize($modules);
    $this->extracted = [];
    $result = [
      'added' => 0,
      'brand_skipped' => 0,
      'files' => [],
      'errors' => [],
      'modules' => [],
      'provider' => $this->translator->providerLabel(),
      'api_ready' => $this->translator->apiKey() !== '',
    ];
    $before = [];
    $labels = [];
    foreach ($modules as $module) {
      if (!$this->moduleHandler->moduleExists($module)) {
        $result['errors'][] = sprintf('模块 %s 未启用。', $module);
        continue;
      }
      $labels[$module] = $this->moduleLabel($module);
      $before[$module] = $this->collectUntranslated($module);
      $this->lockModuleName($module, $labels[$module]);
      foreach ($before[$module] as $item) {
        if ($this->isModuleName($item['source'], $labels[$module])) {
          continue;
        }
        $this->ensureSource($item['source'], $item['context']);
      }
    }

    $projects = $this->projectRepository->buildProjects();
    $imported_projects = [];
    foreach (array_keys($before) as $module) {
      $project = $this->projectName($module);
      if (!isset($imported_projects[$project]) && isset($projects[$project])) {
        try {
          $this->importOfficial($project, $result);
        }
        catch (\Throwable $e) {
          $result['errors'][] = $project . ': ' . $e->getMessage();
          $this->logger->error('导入 {project} 的官方译文失败：{message}', [
            'project' => $project,
            'message' => $e->getMessage(),
          ]);
        }
        $imported_projects[$project] = TRUE;
      }
    }

    $after_official = [];
    foreach (array_keys($before) as $module) {
      $after_official[$module] = $this->collectUntranslated($module);
    }

    foreach (array_keys($before) as $module) {
      foreach ($this->localPoFiles($module, $this->projectName($module)) as $path) {
        try {
          $this->importPo($path, $result);
        }
        catch (\Throwable $e) {
          $result['errors'][] = $path . ': ' . $e->getMessage();
          $this->logger->error('导入 {path} 失败：{message}', [
            'path' => $path,
            'message' => $e->getMessage(),
          ]);
        }
      }
    }

    $catalog = $this->projectRoot() . '/translations/zh-hans.admin-ui.po';
    if (is_file($catalog)) {
      try {
        $this->importPo($catalog, $result);
      }
      catch (\Throwable $e) {
        $result['errors'][] = $catalog . ': ' . $e->getMessage();
        $this->logger->error('导入站点译文目录失败：{message}', [
          'message' => $e->getMessage(),
        ]);
      }
    }

    foreach (array_keys($before) as $module) {
      $official = 0;
      foreach ($before[$module] as $key => $item) {
        if ($this->isModuleName($item['source'], $labels[$module])) {
          continue;
        }
        if (!isset($after_official[$module][$key])) {
          $official++;
        }
      }
      $missing = $this->collectUntranslated($module);
      $api = 0;
      try {
        $api = $this->fillWithApi($module, $missing, $labels[$module], $result);
      }
      catch (\Throwable $e) {
        $result['errors'][] = sprintf('模块 %s 的 API 翻译失败：%s', $module, $e->getMessage());
        $this->logger->error('模块 {module} 的 API 翻译失败：{message}', [
          'module' => $module,
          'message' => $e->getMessage(),
        ]);
      }
      $remaining = $this->collectUntranslated($module);
      $samples = array_map(static fn (array $item): string => $item['source'], $remaining);
      sort($samples);
      $result['modules'][$module] = [
        'official' => $official,
        'api' => $api,
        'remaining' => count($remaining),
        'samples' => array_slice($samples, 0, 30),
      ];
    }

    if ($result['added'] > 0 || $result['modules'] !== []) {
      _locale_refresh_translations([self::LANGCODE]);
    }
    $this->clearPending(array_keys($before));
    return $result;
  }

  /**
   * @param string[] $modules
   */
  private function clearPending(array $modules): void {
    $pending = $this->pendingModules();
    $this->state->set('xedc_ui_locale.pending', array_values(array_diff($pending, $modules)));
  }

  /**
   * @param string[] $modules
   *   Module machine names.
   *
   * @return string[]
   *   Unique non-empty names.
   */
  private function normalize(array $modules): array {
    $names = [];
    foreach ($modules as $module) {
      $module = trim((string) $module);
      if ($module !== '') {
        $names[$module] = $module;
      }
    }
    return array_values($names);
  }

  private function projectName(string $module): string {
    $info = $this->moduleExtensionList->getExtensionInfo($module);
    $project = $info['project'] ?? $module;
    return $project !== '' ? (string) $project : $module;
  }

  private function moduleLabel(string $module): string {
    if (!$this->moduleExtensionList->exists($module)) {
      return '';
    }
    $info = $this->moduleExtensionList->getExtensionInfo($module);
    return trim((string) ($info['name'] ?? ''));
  }

  /**
   * Keeps the .info.yml name unchanged when it has no Chinese translation yet.
   */
  private function lockModuleName(string $module, string $label): void {
    if ($label === '' || preg_match('/\p{Han}/u', $label)) {
      return;
    }
    if ($this->hasChinese($label, '')) {
      return;
    }
    $this->ensureSource($label, '');
    $this->storeTranslation($label, '', $label);
    $this->logger->notice('模块 {module} 的名字「{label}」保持原样，不翻译。', [
      'module' => $module,
      'label' => $label,
    ]);
  }

  private function isModuleName(string $source, string $label): bool {
    if ($label === '') {
      return FALSE;
    }
    $parts = $this->splitPlural($source);
    return count($parts) === 1 && trim($parts[0]) === $label;
  }

  /**
   * @param array<string, mixed> $result
   */
  private function importOfficial(string $project, array &$result): void {
    $context = [];
    $this->localeFetch->batchVersionCheck($project, self::LANGCODE, $context);
    $this->localeFetch->batchStatusCheck($project, self::LANGCODE, [
      'finish_feedback' => FALSE,
      'use_remote' => TRUE,
    ], $context);
    $source = $this->localeSource->loadSource($project, self::LANGCODE);
    if ($source->type !== LOCALE_TRANSLATION_CURRENT) {
      $this->localeFetch->batchDownload($project, self::LANGCODE, $context);
      $source = $this->localeSource->loadSource($project, self::LANGCODE);
    }
    $file = $source->files[LOCALE_TRANSLATION_LOCAL] ?? NULL;
    if (!$file instanceof LocaleFile || !file_exists($file->uri)) {
      return;
    }
    $this->importPo($file->uri, $result);
    if ($source->type !== LOCALE_TRANSLATION_CURRENT) {
      $this->localeSource->saveSource($project, self::LANGCODE, LOCALE_TRANSLATION_CURRENT, $file);
    }
  }

  /**
   * Sends still-missing strings to the configured translation API.
   *
   * @param array<string, array{source: string, context: string}> $missing
   * @param array<string, mixed> $result
   */
  private function fillWithApi(string $module, array $missing, string $label, array &$result): int {
    $jobs = [];
    foreach ($missing as $item) {
      if ($this->isModuleName($item['source'], $label)) {
        continue;
      }
      $parts = $this->splitPlural($item['source']);
      $shielded = [];
      $maps = [];
      $formats = [];
      $local = [];
      foreach ($parts as $part) {
        if (trim($part) === '') {
          $shielded[] = '';
          $maps[] = [];
          $formats[] = 'text';
          $local[] = TRUE;
          continue;
        }
        [$text, $map] = $this->shield($part, $label);
        $shielded[] = $text;
        $maps[] = $map;
        $formats[] = preg_match('/<\/?[a-z][\w:-]*(\s[^>]*)?>/i', $text) ? 'html' : 'text';
        $local[] = $this->isTokenOnly($text);
      }
      $jobs[] = [
        'item' => $item,
        'parts' => $shielded,
        'maps' => $maps,
        'formats' => $formats,
        'local' => $local,
      ];
    }
    if ($jobs === []) {
      return 0;
    }
    if ($this->translator->apiKey() === '') {
      $result['errors'][] = sprintf('未配置 %s API Key，已跳过模块 %s 的自动翻译。', $this->translator->providerLabel(), $module);
      return 0;
    }

    $flat = [];
    foreach ($jobs as $job) {
      foreach ($job['parts'] as $p => $part) {
        if ($part === '' || $job['local'][$p]) {
          continue;
        }
        $flat[] = [
          'text' => $part,
          'format' => $job['formats'][$p],
        ];
      }
    }
    $translated_flat = array_fill(0, count($flat), NULL);
    if ($flat !== []) {
      foreach (['text', 'html'] as $format) {
        $indexes = [];
        $texts = [];
        foreach ($flat as $i => $row) {
          if ($row['format'] === $format) {
            $indexes[] = $i;
            $texts[] = $row['text'];
          }
        }
        if ($texts === []) {
          continue;
        }
        try {
          $out = $this->translator->translatePlainTexts($texts, $format);
        }
        catch (\Throwable $e) {
          $result['errors'][] = sprintf('模块 %s 的 %s 请求失败：%s', $module, $this->translator->providerLabel(), $e->getMessage());
          $this->logger->error('模块 {module} 的 API 翻译失败：{message}', [
            'module' => $module,
            'message' => $e->getMessage(),
          ]);
          continue;
        }
        if (count($out) !== count($texts)) {
          $result['errors'][] = sprintf('模块 %s 的翻译 API 返回条数与请求不一致。', $module);
          continue;
        }
        foreach ($indexes as $position => $i) {
          $translated_flat[$i] = $out[$position] ?? NULL;
        }
      }
    }

    $rows = [];
    $cursor = 0;
    foreach ($jobs as $j => $job) {
      $parts = [];
      $failed = FALSE;
      $used_api = FALSE;
      foreach ($job['parts'] as $p => $part) {
        if ($part === '') {
          $parts[] = '';
          continue;
        }
        if ($job['local'][$p]) {
          $restored = $this->unshield($part, $job['maps'][$p]);
          if ($restored === NULL) {
            $failed = TRUE;
            break;
          }
          $parts[] = $restored;
          continue;
        }
        $raw = $translated_flat[$cursor] ?? NULL;
        $cursor++;
        if (!is_string($raw) || trim($raw) === '') {
          $failed = TRUE;
          break;
        }
        $restored = $this->unshield($raw, $job['maps'][$p]);
        if ($restored === NULL || trim($restored) === '') {
          $failed = TRUE;
          break;
        }
        $parts[] = $restored;
        $used_api = TRUE;
      }
      if ($failed) {
        continue;
      }
      $translation = count($parts) > 1 ? implode(PoItem::DELIMITER, $parts) : $parts[0];
      $source = $job['item']['source'];
      if (!$this->keepsBrand($source, $translation) || !$this->keepsText($source, $translation, $label)) {
        $result['brand_skipped']++;
        continue;
      }
      $rows[] = [
        'source' => $source,
        'context' => $job['item']['context'],
        'translation' => $translation,
        'api' => $used_api,
      ];
    }
    if ($rows === []) {
      return 0;
    }
    if ($label !== '') {
      $rows[] = [
        'source' => $label,
        'context' => '',
        'translation' => $label,
        'api' => FALSE,
      ];
    }

    $path = $this->writeModulePo($module, $rows);
    foreach ($rows as $row) {
      $this->ensureSource($row['source'], $row['context']);
    }
    $this->importPo($path, $result);

    $stored = 0;
    foreach ($rows as $row) {
      if (!$row['api']) {
        continue;
      }
      if ($this->hasChinese($row['source'], $row['context'])) {
        $stored++;
      }
    }
    return $stored;
  }

  /**
   * @param list<array{source: string, context: string, translation: string, api: bool}> $rows
   */
  private function writeModulePo(string $module, array $rows): string {
    $dir = $this->projectRoot() . '/translations';
    if (!is_dir($dir) && !mkdir($dir, 0775, TRUE) && !is_dir($dir)) {
      throw new \RuntimeException('无法创建译文目录：' . $dir);
    }
    $path = $dir . '/' . $module . '.zh-hans.po';
    $existing = [];
    if (is_file($path)) {
      $existing = $this->readPoItems($path);
    }
    foreach ($rows as $row) {
      $key = $row['context'] . "\n" . $this->sourceKey($row['source']);
      if (isset($existing[$key])) {
        $current = trim((string) $existing[$key]['translation']);
        if ($current !== '') {
          continue;
        }
      }
      $existing[$key] = [
        'source' => $this->sourceKey($row['source']),
        'context' => $row['context'],
        'translation' => $row['translation'],
      ];
    }

    $header = new PoHeader(self::LANGCODE);
    $header->setProjectName('DcLili');
    $header->setLanguageName(self::LANGCODE);
    $tmp = $path . '.tmp';
    $writer = new PoStreamWriter();
    $writer->setURI($tmp);
    $writer->setLangcode(self::LANGCODE);
    $writer->setHeader($header);
    $writer->open();
    try {
      foreach ($existing as $row) {
        $item = new PoItem();
        $source = $this->splitPlural($row['source']);
        $translation = $this->splitPlural($row['translation']);
        $item->setSource(count($source) > 1 ? $source : $source[0]);
        $item->setTranslation(count($translation) > 1 ? $translation : $translation[0]);
        if ($row['context'] !== '') {
          $item->setContext($row['context']);
        }
        $writer->writeItem($item);
      }
    }
    catch (\Throwable $e) {
      $writer->close();
      if (is_file($tmp)) {
        unlink($tmp);
      }
      throw $e;
    }
    $writer->close();
    if (!rename($tmp, $path)) {
      throw new \RuntimeException('无法写入译文文件：' . $path);
    }
    return $path;
  }

  /**
   * @return array<string, array{source: string, context: string, translation: string}>
   */
  private function readPoItems(string $uri): array {
    $reader = new PoStreamReader();
    $reader->setURI($uri);
    $reader->setLangcode(self::LANGCODE);
    $reader->open();
    $items = [];
    try {
      if (!$reader->getHeader()) {
        throw new \RuntimeException('PO 文件缺少 header：' . $uri);
      }
      while ($item = $reader->readItem()) {
        $source = $item->getSource();
        $translation = $item->getTranslation();
        $context = (string) $item->getContext();
        $source_key = is_array($source) ? implode(PoItem::DELIMITER, $source) : (string) $source;
        $translation_text = is_array($translation) ? implode(PoItem::DELIMITER, $translation) : (string) $translation;
        $items[$context . "\n" . $source_key] = [
          'source' => $source_key,
          'context' => $context,
          'translation' => $translation_text,
        ];
      }
    }
    finally {
      $reader->close();
    }
    return $items;
  }

  private function sourceKey(string $source): string {
    return str_replace("\0", PoItem::DELIMITER, $source);
  }

  /**
   * @return string[]
   */
  private function splitPlural(string $source): array {
    $source = str_replace("\0", PoItem::DELIMITER, $source);
    if (str_contains($source, PoItem::DELIMITER)) {
      return explode(PoItem::DELIMITER, $source);
    }
    return [$source];
  }

  /**
   * @return array{0: string, 1: array<string, string>}
   */
  private function shield(string $text, string $label): array {
    $map = [];
    $n = 0;
    $replace = static function (string $value) use (&$text, &$map, &$n): void {
      if ($value === '' || !str_contains($text, $value)) {
        return;
      }
      $token = 'XEDCPH' . $n;
      $map[$token] = $value;
      $text = str_replace($value, $token, $text);
      $n++;
    };
    $replace(self::BRAND);
    if ($label !== '' && $label !== self::BRAND) {
      $pattern = '/(?<![\p{L}\p{N}])' . preg_quote($label, '/') . '(?![\p{L}\p{N}])/u';
      $text = preg_replace_callback($pattern, static function (array $matches) use (&$map, &$n): string {
        $token = 'XEDCPH' . $n;
        $map[$token] = $matches[0];
        $n++;
        return $token;
      }, $text) ?? $text;
    }
    if (preg_match_all('/(?<![\p{L}\p{N}_])[@%!:][\p{L}\p{N}_-]+/u', $text, $matches)) {
      $placeholders = array_unique($matches[0]);
      usort($placeholders, static fn (string $a, string $b): int => strlen($b) <=> strlen($a));
      foreach ($placeholders as $placeholder) {
        $replace($placeholder);
      }
    }
    return [$text, $map];
  }

  /**
   * @param array<string, string> $map
   */
  private function unshield(string $text, array $map): ?string {
    $text = preg_replace('/XEDCPH\s*(\d+)/iu', 'XEDCPH$1', $text) ?? $text;
    $tokens = array_keys($map);
    usort($tokens, static fn (string $a, string $b): int => strlen($b) <=> strlen($a));
    foreach ($tokens as $token) {
      if (!str_contains($text, $token)) {
        return NULL;
      }
      $text = str_replace($token, $map[$token], $text);
    }
    if (preg_match('/XEDCPH\d+/u', $text)) {
      return NULL;
    }
    if (str_contains($text, self::BRAND) === FALSE && $map !== []) {
      foreach ($map as $value) {
        if (str_contains($value, self::BRAND) && !str_contains($text, self::BRAND)) {
          return NULL;
        }
      }
    }
    return $text;
  }

  private function isTokenOnly(string $text): bool {
    $stripped = preg_replace('/XEDCPH\d+/u', '', $text);
    return trim((string) $stripped) === '';
  }

  private function ensureSource(string $source, string $context): void {
    $existing = $this->storage->findString([
      'source' => $source,
      'context' => $context,
    ]);
    if ($existing) {
      return;
    }
    $string = $this->storage->createString([
      'source' => $source,
      'context' => $context,
    ]);
    $this->storage->save($string);
  }

  private function storeTranslation(string $source, string $context, string $translation): void {
    if ($this->hasChinese($source, $context)) {
      return;
    }
    $string = $this->storage->findString([
      'source' => $source,
      'context' => $context,
    ]);
    if (!$string) {
      return;
    }
    $target = $this->storage->createTranslation([
      'lid' => $string->lid,
      'language' => self::LANGCODE,
      'translation' => $translation,
      'customized' => LOCALE_NOT_CUSTOMIZED,
    ]);
    $this->storage->save($target);
  }

  /**
   * Composer project root, where translations/*.po is kept.
   */
  private function projectRoot(): string {
    $parent = dirname(DRUPAL_ROOT);
    if (is_file($parent . '/composer.json') && is_dir($parent . '/translations')) {
      return $parent;
    }
    return DRUPAL_ROOT;
  }

  /**
   * @return string[]
   */
  private function localPoFiles(string $module, string $project): array {
    $root = $this->projectRoot();
    $module_path = DRUPAL_ROOT . '/' . $this->moduleExtensionList->getPath($module);
    $candidates = [
      $root . '/translations/' . $module . '.zh-hans.po',
      $root . '/translations/' . $project . '.zh-hans.po',
      $module_path . '/translations/zh-hans.po',
    ];
    $files = [];
    foreach ($candidates as $path) {
      if (is_file($path)) {
        $files[$path] = $path;
      }
    }
    return array_values($files);
  }

  /**
   * Imports one po file with locale's database writer.
   *
   * Existing customized and non-customized translations are left unchanged.
   * A translation that would drop the brand name DcLili is skipped.
   *
   * @param array<string, mixed> $result
   */
  private function importPo(string $uri, array &$result): void {
    $reader = new PoStreamReader();
    $reader->setURI($uri);
    $reader->setLangcode(self::LANGCODE);
    $reader->open();
    $brand_skipped = 0;
    try {
      $header = $reader->getHeader();
      if (!$header) {
        throw new \RuntimeException('PO 文件缺少 header：' . $uri);
      }
      $writer = new PoDatabaseWriter();
      $writer->setLangcode(self::LANGCODE);
      $writer->setOptions([
        'overwrite_options' => [
          'not_customized' => FALSE,
          'customized' => FALSE,
        ],
        'customized' => LOCALE_NOT_CUSTOMIZED,
      ]);
      $writer->setHeader($header);
      $transaction = $this->database->startTransaction();
      try {
        while ($item = $reader->readItem()) {
          if (!$this->acceptItem($item, $brand_skipped)) {
            continue;
          }
          $writer->writeItem($item);
        }
      }
      catch (\Throwable $e) {
        $transaction->rollBack();
        throw $e;
      }
      $report = $writer->getReport();
      $added = (int) ($report['additions'] ?? 0);
    }
    finally {
      $reader->close();
    }
    $result['added'] += $added;
    $result['brand_skipped'] += $brand_skipped;
    $result['files'][] = basename($uri) . ' +' . $added;
  }

  private function acceptItem(PoItem $item, int &$brand_skipped): bool {
    $source = $item->getSource();
    $translation = $item->getTranslation();
    if (is_array($source)) {
      $source = implode(PoItem::DELIMITER, $source);
    }
    if (is_array($translation)) {
      $translation = implode(PoItem::DELIMITER, $translation);
    }
    $translation = trim((string) $translation);
    if ($translation === '') {
      return FALSE;
    }
    if (!$this->keepsBrand((string) $source, $translation)) {
      $brand_skipped++;
      return FALSE;
    }
    return TRUE;
  }

  private function keepsBrand(string $source, string $translation): bool {
    return $this->keepsText($source, $translation, self::BRAND);
  }

  private function keepsText(string $source, string $translation, string $needle): bool {
    if ($needle === '') {
      return TRUE;
    }
    $needed = substr_count($source, $needle);
    if ($needed === 0) {
      return TRUE;
    }
    return substr_count($translation, $needle) >= $needed;
  }

  /**
   * @return array<string, array{source: string, context: string}>
   */
  private function collectUntranslated(string $module): array {
    $missing = [];
    $path = $this->moduleExtensionList->getPath($module);
    $query = $this->database->select('locales_source', 's');
    $query->fields('s', ['source', 'context']);
    $query->innerJoin('locales_location', 'l', 'l.sid = s.lid');
    $query->leftJoin('locales_target', 't', 't.lid = s.lid AND t.language = :langcode', [
      ':langcode' => self::LANGCODE,
    ]);
    $query->condition('l.name', $this->database->escapeLike($path) . '/%', 'LIKE');
    $empty = $query->orConditionGroup()
      ->isNull('t.translation')
      ->condition('t.translation', '');
    $query->condition($empty);
    $query->distinct();
    foreach ($query->execute() as $row) {
      $this->rememberMissing($missing, (string) $row->source, (string) $row->context);
    }
    foreach ($this->extractSources($module) as $source) {
      if (!$this->hasChinese($source, '')) {
        $this->rememberMissing($missing, $source, '');
      }
    }
    return $missing;
  }

  /**
   * @param array<string, array{source: string, context: string}> $missing
   */
  private function rememberMissing(array &$missing, string $source, string $context): void {
    $source = trim($source);
    if ($source === '' || $source === self::BRAND || mb_strlen($source) > 500) {
      return;
    }
    if (preg_match('/\p{Han}/u', $source)) {
      return;
    }
    $missing[$context . "\n" . $source] = [
      'source' => $source,
      'context' => $context,
    ];
  }

  private function hasChinese(string $source, string $context = ''): bool {
    $string = $this->storage->findTranslation([
      'language' => self::LANGCODE,
      'source' => $source,
      'context' => $context,
    ]);
    return $string && isset($string->translation) && $string->translation !== '';
  }

  /**
   * @return string[]
   */
  private function extractSources(string $module): array {
    if (isset($this->extracted[$module])) {
      return $this->extracted[$module];
    }
    $root = DRUPAL_ROOT . '/' . $this->moduleExtensionList->getPath($module);
    if (!is_dir($root)) {
      return $this->extracted[$module] = [];
    }
    $found = [];
    $iterator = new \RecursiveIteratorIterator(
      new \RecursiveDirectoryIterator($root, \FilesystemIterator::SKIP_DOTS)
    );
    foreach ($iterator as $file) {
      if (!$file->isFile() || $file->getSize() > 1048576) {
        continue;
      }
      $pathname = $file->getPathname();
      if (preg_match('#/(tests|node_modules|vendor)/#', $pathname)) {
        continue;
      }
      if ($this->isNestedExtensionFile($root, $pathname)) {
        continue;
      }
      $extension = $file->getExtension();
      if (!in_array($extension, ['php', 'module', 'install', 'inc', 'theme', 'yml', 'js', 'twig'], TRUE)) {
        continue;
      }
      $contents = file_get_contents($pathname);
      if ($contents === FALSE) {
        continue;
      }
      if (preg_match_all('/(?<![\w$])t\(\s*([\'"])((?:\\\\.|(?!\1).)*)\1/s', $contents, $matches)) {
        foreach ($matches[2] as $raw) {
          $found[] = stripcslashes($raw);
        }
      }
      if (preg_match_all('/@Translation\(\s*([\'"])((?:\\\\.|(?!\1).)*)\1/s', $contents, $matches)) {
        foreach ($matches[2] as $raw) {
          $found[] = stripcslashes($raw);
        }
      }
      if ($extension === 'yml' && str_ends_with($file->getFilename(), '.info.yml')) {
        if (preg_match('/^description:\s*[\'"]?(.*?)[\'"]?\s*$/m', $contents, $description)) {
          $found[] = $description[1];
        }
      }
    }
    return $this->extracted[$module] = $found;
  }

  /**
   * Skips files that belong to an extension nested inside this module.
   */
  private function isNestedExtensionFile(string $root, string $pathname): bool {
    $dir = dirname($pathname);
    while ($dir !== $root && str_starts_with($dir, $root)) {
      $infos = glob($dir . '/*.info.yml') ?: [];
      if ($infos !== []) {
        return TRUE;
      }
      $parent = dirname($dir);
      if ($parent === $dir) {
        break;
      }
      $dir = $parent;
    }
    return FALSE;
  }

}
