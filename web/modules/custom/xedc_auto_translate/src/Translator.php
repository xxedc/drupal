<?php

declare(strict_types=1);

namespace Drupal\xedc_auto_translate;

use Drupal\Component\Datetime\TimeInterface;
use Drupal\content_moderation\ModerationInformationInterface;
use Drupal\content_translation\ContentTranslationManagerInterface;
use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\Core\Entity\ContentEntityInterface;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Extension\ModuleHandlerInterface;
use Drupal\Core\Language\LanguageInterface;
use Drupal\Core\Logger\LoggerChannelInterface;
use Drupal\Core\Session\AccountProxyInterface;
use Drupal\Core\State\StateInterface;
use Drupal\path_alias\AliasManagerInterface;
use Drupal\path_alias\Entity\PathAlias;
use GuzzleHttp\ClientInterface;
use GuzzleHttp\Exception\GuzzleException;
use GuzzleHttp\Exception\RequestException;

/**
 * Translates published Chinese content with Microsoft Translator or DeepL.
 *
 * API keys stay in State (or environment variables) and are never written to
 * exported configuration.
 */
final class Translator {

  private const TEXT_TYPES = [
    'string',
    'string_long',
    'text',
    'text_long',
    'text_with_summary',
  ];

  private const SKIP_FIELDS = [
    'path',
    'langcode',
    'default_langcode',
    'revision_timestamp',
    'revision_uid',
    'revision_log',
    'moderation_state',
    'status',
    'content_translation_source',
    'content_translation_outdated',
    'content_translation_uid',
    'content_translation_status',
    'content_translation_created',
    'content_translation_changed',
  ];

  /**
   * Provider language codes keyed by Drupal langcode.
   *
   * DeepL no longer accepts EN as a target; EN-US is used for English.
   */
  private const LANG_CODES = [
    'microsoft' => [
      'zh-hans' => 'zh-Hans',
      'en' => 'en',
      'ru' => 'ru',
      'ja' => 'ja',
    ],
    'deepl' => [
      'zh-hans' => 'ZH',
      'en' => 'EN-US',
      'ru' => 'RU',
      'ja' => 'JA',
    ],
  ];

  /**
   * Entity ids currently being saved, to ignore the nested update hook.
   *
   * @var array<string, bool>
   */
  private array $inProgress = [];

  public function __construct(
    private readonly ConfigFactoryInterface $configFactory,
    private readonly StateInterface $state,
    private readonly EntityTypeManagerInterface $entityTypeManager,
    private readonly ClientInterface $httpClient,
    private readonly LoggerChannelInterface $logger,
    private readonly AccountProxyInterface $currentUser,
    private readonly TimeInterface $time,
    private readonly ModuleHandlerInterface $moduleHandler,
    private readonly ContentTranslationManagerInterface $contentTranslationManager,
    private readonly AliasManagerInterface $aliasManager,
    private readonly ModerationInformationInterface $moderationInformation,
  ) {}

  /**
   * Translates one saved entity when it is a first-time Chinese publication.
   *
   * @return array<string, string>
   *   Target langcode to created|updated|skipped|failed.
   */
  public function translateEntity(ContentEntityInterface $entity, bool $force = FALSE): array {
    if (!$entity->id() || !$entity->isDefaultTranslation()) {
      return [];
    }
    $lock = $entity->getEntityTypeId() . ':' . $entity->id();
    if (isset($this->inProgress[$lock])) {
      return [];
    }
    $this->inProgress[$lock] = TRUE;
    try {
      return $this->doTranslate($entity, $force);
    }
    finally {
      unset($this->inProgress[$lock]);
    }
  }

  /**
   * @return array<string, string>
   */
  private function doTranslate(ContentEntityInterface $entity, bool $force): array {
    $config = $this->configFactory->get('xedc_auto_translate.settings');
    if (!$config->get('enabled')) {
      return [];
    }
    $source = (string) $config->get('source_langcode');
    $bundle_id = $entity->getEntityTypeId() . '.' . $entity->bundle();
    $bundles = $config->get('bundles') ?? [];
    if (!in_array($bundle_id, $bundles, TRUE)) {
      return [];
    }
    if ($entity->language()->getId() !== $source) {
      return [];
    }
    if (!$this->isReady($entity)) {
      return [];
    }

    $storage = $this->entityTypeManager->getStorage($entity->getEntityTypeId());
    $storage->resetCache([$entity->id()]);
    $fresh = $storage->load($entity->id());
    if (!$fresh instanceof ContentEntityInterface) {
      return [];
    }
    $fresh = $fresh->getUntranslated();

    $provider = $this->provider();
    $source_code = $this->providerLanguageCode($provider, $source);
    $targets = array_filter((array) $config->get('targets'));
    $overwrite = $force || (bool) $config->get('overwrite');
    $pending = [];
    foreach ($targets as $langcode => $enabled) {
      $langcode = (string) $langcode;
      $code = $this->providerLanguageCode($provider, $langcode);
      if ($langcode === $source || $enabled === '' || $code === '' || $source_code === '') {
        continue;
      }
      if ($fresh->hasTranslation($langcode) && !$overwrite) {
        $pending[$langcode] = 'skipped';
        continue;
      }
      $pending[$langcode] = $code;
    }
    $todo = array_filter($pending, static fn ($value) => $value !== 'skipped');
    if (!$todo) {
      return $pending;
    }

    $api_key = $this->apiKey($provider);
    if ($api_key === '') {
      $this->logger->warning('Skipped @entity @id: @provider API key is not configured.', [
        '@entity' => $fresh->getEntityTypeId(),
        '@id' => $fresh->id(),
        '@provider' => $this->providerLabel($provider),
      ]);
      return [];
    }

    $results = $pending;
    $changed = FALSE;
    foreach ($todo as $langcode => $code) {
      try {
        $existed = $fresh->hasTranslation($langcode);
        $this->writeLanguage($fresh, $langcode, $code, $api_key, $source, $source_code, $provider, $overwrite);
        $results[$langcode] = $existed ? 'updated' : 'created';
        $changed = TRUE;
      }
      catch (\Throwable $e) {
        $results[$langcode] = 'failed';
        $this->logger->error('Translation to @lang failed for @entity @id: @message', [
          '@lang' => $langcode,
          '@entity' => $fresh->getEntityTypeId(),
          '@id' => $fresh->id(),
          '@message' => $e->getMessage(),
        ]);
      }
    }
    if (!$changed) {
      return $results;
    }

    try {
      $fresh->save();
    }
    catch (\Throwable $e) {
      $this->logger->error('Saving translations failed for @entity @id: @message', [
        '@entity' => $fresh->getEntityTypeId(),
        '@id' => $fresh->id(),
        '@message' => $e->getMessage(),
      ]);
      foreach (array_keys($todo) as $langcode) {
        $results[$langcode] = 'failed';
      }
      return $results;
    }
    $this->copyAliases($fresh, array_keys($todo));
    return $results;
  }

  /**
   * Whether this save should create translations.
   */
  private function isReady(ContentEntityInterface $entity): bool {
    if ($entity->getEntityTypeId() === 'node') {
      if ($this->moduleHandler->moduleExists('content_moderation') && $this->moderationInformation->isModeratedEntity($entity)) {
        // Scheduled nodes can sit in the published moderation state while
        // status is still unpublished. Do not translate those as live content.
        return $entity->hasField('moderation_state')
          && $entity->get('moderation_state')->value === 'published'
          && (!method_exists($entity, 'isPublished') || $entity->isPublished());
      }
      return $entity->isPublished();
    }
    if ($entity->getEntityTypeId() === 'menu_link_content') {
      return $entity->isEnabled();
    }
    return TRUE;
  }

  /**
   * Adds or updates one language on the entity, without saving yet.
   */
  private function writeLanguage(ContentEntityInterface $entity, string $langcode, string $target_code, string $api_key, string $source, string $source_code, string $provider, bool $overwrite): void {
    $jobs = $this->collectJobs($entity);
    $translated = $this->translateJobs($jobs, $source_code, $target_code, $api_key, $provider);
    $values = $this->copyTranslatableValues($entity);
    $this->applyJobs($values, $translated);
    $this->clampToFieldLengths($entity, $values);

    if ($entity->hasTranslation($langcode)) {
      if (!$overwrite) {
        return;
      }
      $translation = $entity->getTranslation($langcode);
      foreach ($values as $name => $value) {
        if ($translation->hasField($name) && $translation->getFieldDefinition($name)->isTranslatable()) {
          $translation->set($name, $value);
        }
      }
    }
    else {
      $translation = $entity->addTranslation($langcode, $values);
    }

    $metadata = $this->contentTranslationManager->getTranslationMetadata($translation);
    $metadata->setSource($source);
    $metadata->setOutdated(FALSE);
    $this->applyPublication($translation);
    if ($translation->getEntityType()->isRevisionable()) {
      $translation->setNewRevision(TRUE);
      $translation->setRevisionTranslationAffected(TRUE);
      $translation->setRevisionUserId((int) $this->currentUser->id());
      $translation->setRevisionCreationTime($this->time->getRequestTime());
      $translation->setRevisionLogMessage($this->providerLabel($provider) . ' from zh-hans.');
    }
    if ($translation->hasField('path')) {
      $translation->path->pathauto = 0;
    }
  }

  /**
   * @return list<array{field: string, delta: int, column: string, format: string, text: string}>
   */
  private function collectJobs(ContentEntityInterface $entity): array {
    $jobs = [];
    foreach ($entity->getFieldDefinitions() as $name => $definition) {
      if (!$definition->isTranslatable() || in_array($name, self::SKIP_FIELDS, TRUE)) {
        continue;
      }
      if (!in_array($definition->getType(), self::TEXT_TYPES, TRUE) || $entity->get($name)->isEmpty()) {
        continue;
      }
      $format = in_array($definition->getType(), ['text', 'text_long', 'text_with_summary'], TRUE) ? 'html' : 'text';
      foreach ($entity->get($name) as $delta => $item) {
        foreach (['value', 'summary'] as $column) {
          $text = trim((string) ($item->{$column} ?? ''));
          if ($text === '') {
            continue;
          }
          $jobs[] = [
            'field' => $name,
            'delta' => (int) $delta,
            'column' => $column,
            'format' => $column === 'summary' ? 'text' : $format,
            'text' => $text,
          ];
        }
      }
    }
    return $jobs;
  }

  /**
   * @param list<array{field: string, delta: int, column: string, format: string, text: string}> $jobs
   * @return list<array{field: string, delta: int, column: string, format: string, text: string}>
   */
  private function translateJobs(array $jobs, string $source_code, string $target_code, string $api_key, string $provider): array {
    if (!$jobs) {
      return [];
    }
    $max_chars = $provider === 'deepl' ? 10000 : 4500;
    $max_items = $provider === 'deepl' ? 50 : 80;
    foreach (['html', 'text'] as $format) {
      $indexes = [];
      foreach ($jobs as $index => $job) {
        if ($job['format'] === $format) {
          $indexes[] = $index;
        }
      }
      if (!$indexes) {
        continue;
      }
      $chunks = [];
      $current = [];
      $chars = 0;
      foreach ($indexes as $index) {
        $length = mb_strlen($jobs[$index]['text']);
        if ($current && ($chars + $length > $max_chars || count($current) >= $max_items)) {
          $chunks[] = $current;
          $current = [];
          $chars = 0;
        }
        $current[] = $index;
        $chars += $length;
      }
      if ($current) {
        $chunks[] = $current;
      }
      foreach ($chunks as $chunk) {
        $texts = array_map(static fn (int $index) => $jobs[$index]['text'], $chunk);
        $translated = $this->request($texts, $source_code, $target_code, $format, $api_key, $provider);
        foreach ($chunk as $position => $index) {
          $jobs[$index]['text'] = $translated[$position];
        }
      }
    }
    return $jobs;
  }

  /**
   * @param list<string> $texts
   * @return list<string>
   */
  private function request(array $texts, string $source, string $target, string $format, string $api_key, string $provider): array {
    if ($provider === 'deepl') {
      return $this->requestDeepL($texts, $source, $target, $format, $api_key);
    }
    return $this->requestMicrosoft($texts, $source, $target, $format, $api_key);
  }

  /**
   * @param list<string> $texts
   * @return list<string>
   */
  private function requestMicrosoft(array $texts, string $source, string $target, string $format, string $api_key): array {
    $body = [];
    foreach ($texts as $text) {
      $body[] = ['Text' => $text];
    }
    try {
      $response = $this->httpClient->request('POST', $this->microsoftUrl(), [
        'headers' => [
          'Ocp-Apim-Subscription-Key' => $api_key,
          'Ocp-Apim-Subscription-Region' => $this->microsoftRegion(),
          'Content-Type' => 'application/json',
        ],
        'query' => [
          'api-version' => '3.0',
          'from' => $source,
          'to' => $target,
          'textType' => $format === 'html' ? 'html' : 'plain',
        ],
        'json' => $body,
        'timeout' => 30,
      ]);
    }
    catch (GuzzleException $e) {
      throw $this->httpError('Microsoft Translator', $e);
    }
    $data = json_decode((string) $response->getBody(), TRUE);
    if (!is_array($data) || count($data) !== count($texts)) {
      throw new \RuntimeException('Microsoft Translator returned an unexpected response.');
    }
    $out = [];
    foreach ($data as $row) {
      $text = $row['translations'][0]['text'] ?? NULL;
      if (!is_string($text) || $text === '') {
        throw new \RuntimeException('Microsoft Translator returned an empty translation.');
      }
      $out[] = html_entity_decode($text, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    }
    return $out;
  }

  /**
   * @param list<string> $texts
   * @return list<string>
   */
  private function requestDeepL(array $texts, string $source, string $target, string $format, string $api_key): array {
    $payload = [
      'text' => array_values($texts),
      'source_lang' => $source,
      'target_lang' => $target,
    ];
    if ($format === 'html') {
      $payload['tag_handling'] = 'html';
    }
    $response = NULL;
    for ($attempt = 1; $attempt <= 5; $attempt++) {
      try {
        $response = $this->httpClient->request('POST', $this->deeplUrl($api_key), [
          'headers' => [
            'Authorization' => 'DeepL-Auth-Key ' . $api_key,
            'Content-Type' => 'application/json',
          ],
          'json' => $payload,
          'timeout' => 30,
        ]);
        break;
      }
      catch (GuzzleException $e) {
        $status = $e instanceof RequestException && $e->hasResponse() ? $e->getResponse()->getStatusCode() : 0;
        if ($status !== 429 || $attempt === 5) {
          throw $this->httpError('DeepL', $e);
        }
        $retry_after = 2 * $attempt;
        if ($e instanceof RequestException && $e->hasResponse()) {
          $header = $e->getResponse()->getHeaderLine('Retry-After');
          if (is_numeric($header)) {
            $retry_after = min(30, max(1, (int) $header));
          }
        }
        sleep($retry_after);
      }
    }
    if ($response === NULL) {
      throw new \RuntimeException('DeepL request failed.');
    }
    $data = json_decode((string) $response->getBody(), TRUE);
    $rows = $data['translations'] ?? NULL;
    if (!is_array($rows) || count($rows) !== count($texts)) {
      throw new \RuntimeException('DeepL returned an unexpected response.');
    }
    $out = [];
    foreach ($rows as $row) {
      $text = $row['text'] ?? NULL;
      if (!is_string($text) || $text === '') {
        throw new \RuntimeException('DeepL returned an empty translation.');
      }
      $out[] = html_entity_decode($text, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    }
    return $out;
  }

  /**
   * Builds a safe exception that does not include the API key.
   */
  private function httpError(string $provider, GuzzleException $e): \RuntimeException {
    $message = $e->getMessage();
    if ($e instanceof RequestException && $e->hasResponse()) {
      $body = trim((string) $e->getResponse()->getBody());
      if ($body !== '') {
        $message .= ' ' . mb_substr($body, 0, 400);
      }
    }
    return new \RuntimeException($provider . ' request failed: ' . $message, 0, $e);
  }

  /**
   * Global Translator endpoint, or a validated custom Azure host.
   */
  private function microsoftUrl(): string {
    $custom = trim((string) $this->configFactory->get('xedc_auto_translate.settings')->get('microsoft_endpoint'));
    if ($custom === '' || !$this->isAllowedMicrosoftEndpoint($custom)) {
      return 'https://api.cognitive.microsofttranslator.com/translate';
    }
    $parts = parse_url($custom);
    $host = strtolower((string) ($parts['host'] ?? ''));
    $path = (string) ($parts['path'] ?? '');
    if ($path === '' || $path === '/') {
      $path = str_contains($host, '.cognitiveservices.azure.')
        ? '/translator/text/v3.0/translate'
        : '/translate';
    }
    else {
      $path = rtrim($path, '/');
      if (!str_ends_with(strtolower($path), '/translate')) {
        $path .= str_contains($host, '.cognitiveservices.azure.')
          ? '/translator/text/v3.0/translate'
          : '/translate';
      }
    }
    return 'https://' . $host . $path;
  }

  /**
   * Whether a Microsoft endpoint host is an official Translator host.
   */
  public function isAllowedMicrosoftEndpoint(string $endpoint): bool {
    $parts = parse_url(trim($endpoint));
    if (!$parts || strtolower((string) ($parts['scheme'] ?? '')) !== 'https' || empty($parts['host'])) {
      return FALSE;
    }
    $host = strtolower((string) $parts['host']);
    if (in_array($host, [
      'api.cognitive.microsofttranslator.com',
      'api.cognitive.microsofttranslator.us',
      'api.translator.azure.cn',
    ], TRUE)) {
      return TRUE;
    }
    return (bool) preg_match('/^[a-z0-9-]+\.cognitiveservices\.azure\.(com|cn|us)$/', $host);
  }

  /**
   * Free keys end with :fx and must use the free host.
   */
  private function deeplUrl(string $api_key): string {
    $mode = (string) $this->configFactory->get('xedc_auto_translate.settings')->get('deepl_endpoint');
    if ($mode !== 'free' && $mode !== 'pro') {
      $mode = str_ends_with($api_key, ':fx') ? 'free' : 'pro';
    }
    $host = $mode === 'free' ? 'https://api-free.deepl.com' : 'https://api.deepl.com';
    return $host . '/v2/translate';
  }

  /**
   * @return array<string, mixed>
   */
  private function copyTranslatableValues(ContentEntityInterface $entity): array {
    $values = [];
    $entity_type = $entity->getEntityType();
    $skip_keys = array_filter([
      $entity_type->getKey('id'),
      $entity_type->getKey('uuid'),
      $entity_type->getKey('revision'),
      $entity_type->getKey('bundle'),
      $entity_type->getKey('langcode'),
    ]);
    foreach ($entity->getFieldDefinitions() as $name => $definition) {
      if (!$definition->isTranslatable() || $definition->isComputed() || in_array($name, self::SKIP_FIELDS, TRUE) || in_array($name, $skip_keys, TRUE)) {
        continue;
      }
      if ($entity->hasField($name)) {
        $values[$name] = $entity->get($name)->getValue();
      }
    }
    return $values;
  }

  /**
   * Keeps translated strings inside the field storage limit.
   *
   * Machine translation can make a title longer than the 255-character column.
   *
   * @param array<string, mixed> $values
   */
  private function clampToFieldLengths(ContentEntityInterface $entity, array &$values): void {
    foreach ($values as $name => &$items) {
      if (!is_array($items) || !$entity->hasField($name)) {
        continue;
      }
      $max = (int) $entity->getFieldDefinition($name)->getFieldStorageDefinition()->getSetting('max_length');
      if ($max < 1) {
        continue;
      }
      foreach ($items as &$item) {
        if (!is_array($item)) {
          continue;
        }
        foreach (['value', 'summary'] as $column) {
          if (!isset($item[$column]) || !is_string($item[$column])) {
            continue;
          }
          if (mb_strlen($item[$column]) > $max) {
            $item[$column] = mb_substr($item[$column], 0, $max);
          }
        }
      }
    }
  }

  /**
   * @param array<string, mixed> $values
   * @param list<array{field: string, delta: int, column: string, format: string, text: string}> $jobs
   */
  private function applyJobs(array &$values, array $jobs): void {
    foreach ($jobs as $job) {
      if (!isset($values[$job['field']][$job['delta']]) || !is_array($values[$job['field']][$job['delta']])) {
        continue;
      }
      $values[$job['field']][$job['delta']][$job['column']] = $job['text'];
    }
  }

  /**
   * Publishes the translation, or stores it as a draft when configured.
   */
  private function applyPublication(ContentEntityInterface $translation): void {
    $draft = $this->configFactory->get('xedc_auto_translate.settings')->get('save_as') === 'draft';
    if ($translation->getEntityTypeId() === 'menu_link_content') {
      $translation->set('enabled', !$draft);
      return;
    }
    if ($translation->getEntityTypeId() === 'node' && $this->moderationInformation->isModeratedEntity($translation)) {
      $translation->set('moderation_state', $draft ? 'draft' : 'published');
      return;
    }
    if (method_exists($translation, 'setPublished')) {
      $draft ? $translation->setUnpublished() : $translation->setPublished();
    }
  }

  /**
   * Keeps the existing alias and exposes it under each target language prefix.
   *
   * @param list<string> $langcodes
   */
  private function copyAliases(ContentEntityInterface $entity, array $langcodes): void {
    if (!in_array($entity->getEntityTypeId(), ['node', 'taxonomy_term'], TRUE)) {
      return;
    }
    $system = '/' . $entity->toUrl()->getInternalPath();
    $source = $entity->getUntranslated()->language()->getId();
    $alias = $this->aliasManager->getAliasByPath($system, $source);
    if ($alias === $system) {
      $alias = $this->aliasManager->getAliasByPath($system, LanguageInterface::LANGCODE_NOT_SPECIFIED);
    }
    if ($alias === $system) {
      return;
    }
    $storage = $this->entityTypeManager->getStorage('path_alias');
    foreach ($langcodes as $langcode) {
      $existing = $storage->loadByProperties([
        'path' => $system,
        'alias' => $alias,
        'langcode' => $langcode,
      ]);
      if ($existing) {
        continue;
      }
      try {
        PathAlias::create([
          'path' => $system,
          'alias' => $alias,
          'langcode' => $langcode,
        ])->save();
      }
      catch (\Throwable $e) {
        $this->logger->warning('Could not copy alias @alias to @lang: @message', [
          '@alias' => $alias,
          '@lang' => $langcode,
          '@message' => $e->getMessage(),
        ]);
      }
    }
  }

  /**
   * Translates English interface strings into Simplified Chinese.
   *
   * Uses the provider selected in xedc_auto_translate.settings. The API key is
   * read from State (xedc_auto_translate.api_key.microsoft or
   * xedc_auto_translate.api_key.deepl), then from the environment. Callers
   * should hide placeholders and the DcLili brand before calling.
   *
   * DeepL is called as source_lang=EN, target_lang=ZH. Microsoft Translator is
   * called as from=en, to=zh-Hans. HTML strings keep textType=html or
   * tag_handling=html so markup stays intact.
   *
   * @param list<string> $texts
   *   Plain English strings, in order.
   * @param string $format
   *   Either "text" or "html".
   *
   * @return list<string|null>
   *   Translations aligned with $texts. Null means that one string failed.
   */
  public function translatePlainTexts(array $texts, string $format = 'text'): array {
    $texts = array_values($texts);
    if ($texts === []) {
      return [];
    }
    $format = $format === 'html' ? 'html' : 'text';
    $provider = $this->provider();
    $api_key = $this->apiKey($provider);
    if ($api_key === '') {
      throw new \RuntimeException($this->providerLabel($provider) . ' API key is not configured.');
    }
    $source = $provider === 'deepl' ? 'EN' : 'en';
    $target = self::LANG_CODES[$provider]['zh-hans'] ?? '';
    if ($target === '') {
      throw new \RuntimeException('No Simplified Chinese language code for ' . $provider . '.');
    }
    $max_chars = $provider === 'deepl' ? 10000 : 4500;
    $max_items = $provider === 'deepl' ? 50 : 80;
    $out = [];
    $chunk = [];
    $chars = 0;
    foreach ($texts as $text) {
      $text = (string) $text;
      $length = mb_strlen($text);
      if ($chunk !== [] && ($chars + $length > $max_chars || count($chunk) >= $max_items)) {
        $out = array_merge($out, $this->translateChunk($chunk, $source, $target, $format, $api_key, $provider));
        $chunk = [];
        $chars = 0;
      }
      $chunk[] = $text;
      $chars += $length;
    }
    if ($chunk !== []) {
      $out = array_merge($out, $this->translateChunk($chunk, $source, $target, $format, $api_key, $provider));
    }
    return $out;
  }

  /**
   * @param list<string> $texts
   * @return list<string|null>
   */
  private function translateChunk(array $texts, string $source, string $target, string $format, string $api_key, string $provider): array {
    try {
      return $this->request($texts, $source, $target, $format, $api_key, $provider);
    }
    catch (\Throwable $e) {
      if (count($texts) > 1 && !$this->isFatalTranslationError($e)) {
        $out = [];
        foreach ($texts as $text) {
          $out = array_merge($out, $this->translateChunk([$text], $source, $target, $format, $api_key, $provider));
        }
        return $out;
      }
      if (count($texts) === 1 && !$this->isFatalTranslationError($e)) {
        $this->logger->warning('Skipped one interface string: @message', [
          '@message' => $e->getMessage(),
        ]);
        return [NULL];
      }
      throw $e;
    }
  }

  private function isFatalTranslationError(\Throwable $e): bool {
    $message = $e->getMessage();
    return str_contains($message, 'API key is not configured')
      || (bool) preg_match('/\b(401|403|429|456)\b/', $message);
  }

  /**
   * Active provider: microsoft or deepl.
   */
  public function provider(): string {
    $provider = (string) $this->configFactory->get('xedc_auto_translate.settings')->get('provider');
    return $provider === 'deepl' ? 'deepl' : 'microsoft';
  }

  /**
   * Human-readable provider name for logs and revision messages.
   */
  public function providerLabel(?string $provider = NULL): string {
    return ($provider ?? $this->provider()) === 'deepl' ? 'DeepL' : 'Microsoft Translator';
  }

  /**
   * API key from State, otherwise from the environment.
   */
  public function apiKey(?string $provider = NULL): string {
    $provider = $this->normalizeProvider($provider);
    $key = trim((string) $this->state->get($this->stateKey($provider), ''));
    if ($key !== '') {
      return $key;
    }
    $env_name = $provider === 'deepl' ? 'DEEPL_API_KEY' : 'MICROSOFT_TRANSLATOR_API_KEY';
    $env = getenv($env_name);
    return is_string($env) ? trim($env) : '';
  }

  /**
   * Stores or clears one provider key outside exported configuration.
   */
  public function setApiKey(string $key, ?string $provider = NULL): void {
    $provider = $this->normalizeProvider($provider);
    $key = trim($key);
    if ($key === '') {
      $this->state->delete($this->stateKey($provider));
      return;
    }
    $this->state->set($this->stateKey($provider), $key);
  }

  public function hasStoredApiKey(?string $provider = NULL): bool {
    $provider = $this->normalizeProvider($provider);
    return trim((string) $this->state->get($this->stateKey($provider), '')) !== '';
  }

  /**
   * Azure region, from config or MICROSOFT_TRANSLATOR_REGION.
   */
  public function microsoftRegion(): string {
    $region = strtolower(trim((string) $this->configFactory->get('xedc_auto_translate.settings')->get('microsoft_region')));
    if ($region === '') {
      $env = getenv('MICROSOFT_TRANSLATOR_REGION');
      $region = is_string($env) ? strtolower(trim($env)) : '';
    }
    return $region !== '' ? $region : 'global';
  }

  private function providerLanguageCode(string $provider, string $langcode): string {
    return self::LANG_CODES[$provider][$langcode] ?? '';
  }

  private function normalizeProvider(?string $provider): string {
    $provider = $provider ?? $this->provider();
    return $provider === 'deepl' ? 'deepl' : 'microsoft';
  }

  private function stateKey(string $provider): string {
    return 'xedc_auto_translate.api_key.' . $provider;
  }

}
