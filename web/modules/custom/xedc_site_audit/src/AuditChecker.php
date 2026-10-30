<?php

declare(strict_types=1);

namespace Drupal\xedc_site_audit;

use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\Core\Database\Connection;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Extension\ModuleHandlerInterface;
use Drupal\Core\Language\LanguageManagerInterface;

/**
 * SEO and performance checks for the DcLili content model.
 */
class AuditChecker {

  /**
   * Content types that should have public aliases and metadata.
   */
  private const NODE_BUNDLES = ['photo', 'article', 'video', 'page'];

  /**
   * Vocabularies whose published terms should have translations.
   */
  private const TERM_BUNDLES = ['models', 'photo_category', 'article_category', 'video_category'];

  /**
   * Request-local check results. Each Site Audit check calls all().
   */
  private ?array $results = NULL;

  public function __construct(
    protected ConfigFactoryInterface $configFactory,
    protected Connection $database,
    protected ModuleHandlerInterface $moduleHandler,
    protected LanguageManagerInterface $languageManager,
    protected EntityTypeManagerInterface $entityTypeManager,
  ) {}

  /**
   * @return array<string, array{field: string, detail: string, value: string, message: string}>
   *   Check results keyed by id.
   */
  public function all(): array {
    if ($this->results === NULL) {
      $this->results = [
        'image_alt' => $this->imageAlt(),
        'meta' => $this->meta(),
        'url_alias' => $this->urlAlias(),
        'sitemap' => $this->sitemap(),
        'cache' => $this->cache(),
        'translation' => $this->translation(),
      ];
    }
    return $this->results;
  }

  /**
   * @return array{field: string, detail: string, value: string, message: string}
   *   Image alt result.
   */
  public function imageAlt(): array {
    $settings = $this->configFactory->get('field.field.media.image.field_media_image')->get('settings') ?? [];
    $enabled = !empty($settings['alt_field']);
    $required = !empty($settings['alt_field_required']);
    $empty = 0;
    $short = 0;
    if ($this->database->schema()->tableExists('media__field_media_image')) {
      $empty = (int) $this->database->query("SELECT COUNT(*) FROM {media__field_media_image} WHERE deleted = 0 AND (field_media_image_alt IS NULL OR field_media_image_alt = '')")->fetchField();
      $short = (int) $this->database->query("SELECT COUNT(*) FROM {media__field_media_image} WHERE deleted = 0 AND field_media_image_alt IS NOT NULL AND field_media_image_alt <> '' AND CHAR_LENGTH(field_media_image_alt) < 8")->fetchField();
    }
    $message = sprintf('媒体图片 alt 字段%s，必填%s。空 alt %d 条，短于 8 个字 %d 条。', $enabled ? '已开启' : '未开启', $required ? '已开启' : '未开启', $empty, $short);
    if (!$enabled) {
      return $this->result('field_image_alt', 'field_image_alt_detail', 'fail', $message . ' 编辑界面无法填写画面描述。');
    }
    if ($empty > 0 || $short > 0) {
      return $this->result('field_image_alt', 'field_image_alt_detail', 'warn', $message . ' 配置正确，已有短文本仍需要按画面重写。');
    }
    return $this->result('field_image_alt', 'field_image_alt_detail', 'pass', $message);
  }

  /**
   * @return array{field: string, detail: string, value: string, message: string}
   *   Metatag result.
   */
  public function meta(): array {
    $required = [
      'metatag.metatag_defaults.front' => '首页',
      'metatag.metatag_defaults.node__photo' => '美图',
      'metatag.metatag_defaults.node__article' => '文章',
      'metatag.metatag_defaults.node__video' => '视频',
      'metatag.metatag_defaults.node__page' => '基础页',
      'metatag.metatag_defaults.xedc_models.detail' => '模特详情',
    ];
    $missing = [];
    $empty_description = [];
    foreach ($required as $name => $label) {
      $config = $this->configFactory->get($name);
      if ($config->isNew() || $config->get('status') === FALSE && $config->get('tags') === NULL) {
        $missing[] = $label;
        continue;
      }
      $tags = $config->get('tags') ?? [];
      if (!is_array($tags) || trim((string) ($tags['description'] ?? '')) === '' || trim((string) ($tags['title'] ?? '')) === '') {
        $empty_description[] = $label;
      }
    }
    $front = $this->configFactory->get('metatag.metatag_defaults.front')->get('tags') ?? [];
    $brand = '';
    foreach (['title', 'description', 'og_site_name', 'rights'] as $key) {
      $brand .= ' ' . (string) ($front[$key] ?? '');
    }
    $old_brand = stripos($brand, 'XEDC') !== FALSE;
    $parts = [];
    if ($missing) {
      $parts[] = '缺少 Metatag 默认值：' . implode('、', $missing);
    }
    if ($empty_description) {
      $parts[] = '标题或描述为空：' . implode('、', $empty_description);
    }
    if ($old_brand) {
      $parts[] = '首页元数据仍包含旧品牌 XEDC';
    }
    if (!$parts) {
      return $this->result('field_meta_tags', 'field_meta_detail', 'pass', '首页、美图、文章、视频、基础页和模特详情都有标题与描述，品牌为 DcLili。');
    }
    $value = $missing ? 'fail' : 'warn';
    return $this->result('field_meta_tags', 'field_meta_detail', $value, implode('。', $parts) . '。');
  }

  /**
   * @return array{field: string, detail: string, value: string, message: string}
   *   Pathauto result.
   */
  public function urlAlias(): array {
    $patterns = [
      'gggg' => '美图',
      'article_url' => '文章',
      'video_url' => '视频',
      'page_url' => '基础页',
      'article_category' => '文章栏目',
      'video_category' => '视频栏目',
      'tags_url' => '标签',
    ];
    $storage = $this->entityTypeManager->hasDefinition('pathauto_pattern')
      ? $this->entityTypeManager->getStorage('pathauto_pattern')
      : NULL;
    $loaded = $storage ? $storage->loadMultiple(array_keys($patterns)) : [];
    $missing = [];
    foreach ($patterns as $id => $label) {
      $pattern = $loaded[$id] ?? NULL;
      if (!$pattern || !$pattern->status()) {
        $missing[] = $label;
      }
    }
    $without = $this->nodesWithoutAlias();
    $parts = ['模特使用自定义路径 /models/{id}，不另建 Pathauto，避免和正式 URL 冲突。'];
    if ($missing) {
      $parts[] = '缺少 URL 模式：' . implode('、', $missing);
    }
    if ($without) {
      $bits = [];
      foreach ($without as $bundle => $count) {
        $bits[] = $bundle . ' ' . $count . ' 篇';
      }
      $parts[] = '已发布内容没有别名：' . implode('，', $bits);
    }
    $critical = array_intersect($missing, ['美图', '文章', '视频', '基础页']);
    if ($critical) {
      $value = 'fail';
    }
    elseif ($missing || $without) {
      $value = 'warn';
    }
    else {
      $value = 'pass';
      $parts[] = '美图、文章、视频、基础页、栏目和标签都有别名模式，已发布内容均有别名。';
    }
    return $this->result('field_url_alias', 'field_url_alias_detail', $value, implode(' ', $parts));
  }

  /**
   * @return array{field: string, detail: string, value: string, message: string}
   *   Sitemap result.
   */
  public function sitemap(): array {
    $problems = [];
    $notes = [];
    if (!$this->moduleHandler->moduleExists('simple_sitemap')) {
      $problems[] = '未启用 Simple XML Sitemap';
    }
    $settings = $this->configFactory->get('simple_sitemap.settings');
    $base = (string) $settings->get('base_url');
    if ($base === '' || !str_starts_with($base, 'https://')) {
      $problems[] = 'sitemap base_url 不是 https 地址';
    }
    else {
      $notes[] = 'base_url 为 ' . $base;
    }
    foreach (['photo', 'article', 'video', 'page'] as $bundle) {
      $indexed = $this->configFactory->get('simple_sitemap.bundle_settings.default.node.' . $bundle)->get('index');
      if (!$indexed) {
        $problems[] = $bundle . ' 未加入 sitemap';
      }
    }
    $models = $this->configFactory->get('simple_sitemap.bundle_settings.default.taxonomy_term.models')->get('index');
    if ($models) {
      $notes[] = '模特术语会改写为 /models/{id}，指向其他模特的别名术语不进入 sitemap';
    }
    else {
      $problems[] = '模特术语未加入 sitemap';
    }
    $robots = \Drupal::root() . '/robots.txt';
    $robots_text = is_readable($robots) ? (string) file_get_contents($robots) : '';
    if (!preg_match('/^Sitemap:\s+\S+/m', $robots_text)) {
      $problems[] = 'robots.txt 没有 Sitemap 声明';
    }
    else {
      $notes[] = 'robots.txt 已声明 Sitemap';
    }
    if ($problems) {
      return $this->result('field_sitemap', 'field_sitemap_detail', 'fail', implode('。', array_merge($problems, $notes)) . '。');
    }
    return $this->result('field_sitemap', 'field_sitemap_detail', 'pass', implode('。', $notes) . '。美图、文章、视频和基础页已索引。');
  }

  /**
   * @return array{field: string, detail: string, value: string, message: string}
   *   Cache and aggregation result.
   */
  public function cache(): array {
    $performance = $this->configFactory->get('system.performance');
    $max_age = (int) $performance->get('cache.page.max_age');
    $css = (bool) $performance->get('css.preprocess');
    $js = (bool) $performance->get('js.preprocess');
    $problems = [];
    if ($max_age < 900) {
      $problems[] = '匿名页面缓存最大期限只有 ' . $max_age . ' 秒';
    }
    if (!$css || !$js) {
      $problems[] = 'CSS 或 JS 聚合未开启';
    }
    foreach (['page_cache' => '内部页面缓存', 'dynamic_page_cache' => '动态页面缓存'] as $module => $label) {
      if (!$this->moduleHandler->moduleExists($module)) {
        $problems[] = $label . '未启用';
      }
    }
    $view = $this->configFactory->get('views.view.xedc_home');
    foreach (['block_articles', 'block_photos', 'block_videos'] as $display) {
      $type = (string) ($view->get('display.' . $display . '.display_options.cache.type') ?? 'none');
      if ($type === '' || $type === 'none') {
        $problems[] = '首页视图 ' . $display . ' 没有缓存';
      }
    }
    $message = sprintf('页面缓存 %d 秒，CSS 聚合%s，JS 聚合%s。', $max_age, $css ? '已开启' : '未开启', $js ? '已开启' : '未开启');
    if ($problems) {
      return $this->result('field_cache_status', 'field_cache_detail', 'fail', $message . implode('。', $problems) . '。');
    }
    return $this->result('field_cache_status', 'field_cache_detail', 'pass', $message . '首页三个区块使用按内容类型失效的缓存。');
  }

  /**
   * @return array{field: string, detail: string, value: string, message: string}
   *   Translation coverage for published nodes and category terms.
   */
  public function translation(): array {
    if (!$this->moduleHandler->moduleExists('content_translation')) {
      return $this->result('field_translation', 'field_translation_detail', 'warn', '未启用内容翻译。');
    }
    $default = $this->languageManager->getDefaultLanguage()->getId();
    $languages = [];
    foreach ($this->languageManager->getLanguages() as $language) {
      $id = $language->getId();
      if ($id !== $default) {
        $languages[] = $id;
      }
    }
    if (!$languages) {
      return $this->result('field_translation', 'field_translation_detail', 'info', '站点只有默认语言 ' . $default . '。');
    }
    $node_rows = $this->database->query(
      "SELECT type, langcode, default_langcode, COUNT(*) AS cnt FROM {node_field_data} WHERE status = 1 AND type IN (:types[]) GROUP BY type, langcode, default_langcode",
      [':types[]' => self::NODE_BUNDLES]
    )->fetchAll();
    $term_rows = $this->database->schema()->tableExists('taxonomy_term_field_data')
      ? $this->database->query(
        "SELECT vid AS type, langcode, default_langcode, COUNT(*) AS cnt FROM {taxonomy_term_field_data} WHERE status = 1 AND vid IN (:bundles[]) GROUP BY vid, langcode, default_langcode",
        [':bundles[]' => self::TERM_BUNDLES]
      )->fetchAll()
      : [];
    $bits = [];
    $below = FALSE;
    $this->coverageBits($node_rows, self::NODE_BUNDLES, $languages, $bits, $below);
    $this->coverageBits($term_rows, self::TERM_BUNDLES, $languages, $bits, $below);
    $message = '默认语言 ' . $default . '。节点与模特、图片分类、文章分类、视频分类均计入。' . ($bits ? implode('，', $bits) . '。' : '没有已发布的目标内容。');
    if ($below) {
      return $this->result('field_translation', 'field_translation_detail', 'warn', $message . ' 未达到 80%。中文站可以保留译文缺口，但不要把没有译文的语言前缀提交进 sitemap。');
    }
    return $this->result('field_translation', 'field_translation_detail', 'pass', $message);
  }

  /**
   * Adds per-bundle translation percentages.
   *
   * @param object[] $rows
   *   Rows with type, langcode, default_langcode and cnt.
   * @param string[] $bundles
   *   Bundles to report, in display order.
   * @param string[] $languages
   *   Non-default language codes.
   * @param string[] $bits
   *   Human-readable percentages, appended in place.
   * @param bool $below
   *   Set when any percentage is under 80.
   */
  protected function coverageBits(array $rows, array $bundles, array $languages, array &$bits, bool &$below): void {
    $source = [];
    $translated = [];
    foreach ($rows as $row) {
      if ((int) $row->default_langcode === 1) {
        $source[$row->type] = ($source[$row->type] ?? 0) + (int) $row->cnt;
      }
      else {
        $translated[$row->type][$row->langcode] = (int) $row->cnt;
      }
    }
    foreach ($bundles as $bundle) {
      $total = $source[$bundle] ?? 0;
      if ($total === 0) {
        continue;
      }
      foreach ($languages as $langcode) {
        $count = $translated[$bundle][$langcode] ?? 0;
        $percent = (int) floor(($count / $total) * 100);
        $bits[] = $bundle . '/' . $langcode . ' ' . $percent . '%';
        if ($percent < 80) {
          $below = TRUE;
        }
      }
    }
  }

  /**
   * @return array<string, int>
   *   Published nodes with no path alias, keyed by bundle.
   */
  protected function nodesWithoutAlias(): array {
    if (!$this->database->schema()->tableExists('path_alias')) {
      return [];
    }
    $query = $this->database->query(
      "SELECT n.type, COUNT(DISTINCT n.nid) AS cnt
       FROM {node_field_data} n
       LEFT JOIN {path_alias} p ON p.path = CONCAT('/node/', n.nid) AND p.status = 1
       WHERE n.status = 1 AND n.default_langcode = 1 AND n.type IN (:types[]) AND p.id IS NULL
       GROUP BY n.type",
      [':types[]' => self::NODE_BUNDLES]
    );
    $out = [];
    foreach ($query as $row) {
      if ((int) $row->cnt > 0) {
        $out[$row->type] = (int) $row->cnt;
      }
    }
    return $out;
  }

  /**
   * @return array{field: string, detail: string, value: string, message: string}
   *   Normalized result.
   */
  protected function result(string $field, string $detail, string $value, string $message): array {
    return [
      'field' => $field,
      'detail' => $detail,
      'value' => $value,
      'message' => $message,
    ];
  }

}
