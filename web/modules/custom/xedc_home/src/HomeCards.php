<?php

namespace Drupal\xedc_home;

use Drupal\Core\Database\Connection;
use Drupal\Core\Datetime\DateFormatterInterface;
use Drupal\Core\Entity\EntityFieldManagerInterface;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\File\FileUrlGeneratorInterface;
use Drupal\file\FileInterface;
use Drupal\image\Entity\ImageStyle;
use Drupal\media\MediaInterface;
use Drupal\node\NodeInterface;
use Drupal\views\Views;
use Psr\Log\LoggerInterface;

/**
 * Builds homepage cards from Views and a short slideshow query.
 */
class HomeCards {

  public function __construct(
    protected EntityTypeManagerInterface $entityTypeManager,
    protected Connection $database,
    protected FileUrlGeneratorInterface $fileUrlGenerator,
    protected DateFormatterInterface $dateFormatter,
    protected EntityFieldManagerInterface $entityFieldManager,
    protected LoggerInterface $logger,
  ) {}

  /**
   * Slideshow photos: flagged first, then hottest published photos.
   *
   * @return array<int, array<string, mixed>>
   *   Card rows, at most $limit.
   */
  public function slideshow(int $limit = 5): array {
    $picked = [];
    if ($this->hasField('field_slideshow')) {
      $flagged = $this->entityTypeManager->getStorage('node')->getQuery()
        ->accessCheck(TRUE)
        ->condition('type', 'photo')
        ->condition('status', 1)
        ->condition('field_slideshow', 1)
        ->sort('created', 'DESC')
        ->range(0, $limit)
        ->execute();
      foreach ($flagged as $nid) {
        $picked[] = (int) $nid;
      }
    }
    $need = $limit - count($picked);
    if ($need > 0) {
      foreach ($this->hotPhotoIds($picked, $need) as $nid) {
        if (!in_array($nid, $picked, TRUE)) {
          $picked[] = $nid;
        }
      }
    }
    return $this->cardsInOrder($picked, 'field_cover_image', 'xa_hero', 'slide');
  }

  /**
   * Loads one homepage View display and maps the rows to cards.
   *
   * @return array<int, array<string, mixed>>
   *   Card rows in view order.
   */
  public function fromView(string $display, string $imageField, string $style, string $kind): array {
    $view = Views::getView('xedc_home');
    if (!$view || !$view->setDisplay($display)) {
      return [];
    }
    $view->execute();
    $nids = [];
    foreach ($view->result as $row) {
      if (!empty($row->_entity) && $row->_entity instanceof NodeInterface) {
        $nids[] = (int) $row->_entity->id();
      }
      elseif (!empty($row->nid)) {
        $nids[] = (int) $row->nid;
      }
    }
    return $this->cardsInOrder($nids, $imageField, $style, $kind);
  }

  /**
   * First three photo categories, each with up to three photos.
   *
   * @return array<int, array<string, mixed>>
   *   Category rows with name, url, and photos.
   */
  public function categories(): array {
    $term_storage = $this->entityTypeManager->getStorage('taxonomy_term');
    $tids = $term_storage->getQuery()
      ->accessCheck(TRUE)
      ->condition('vid', 'photo_category')
      ->sort('weight', 'ASC')
      ->sort('tid', 'ASC')
      ->range(0, 3)
      ->execute();
    if (!$tids) {
      return [];
    }
    $terms = $term_storage->loadMultiple($tids);
    $node_storage = $this->entityTypeManager->getStorage('node');
    $out = [];
    foreach ($tids as $tid) {
      if (!isset($terms[$tid])) {
        continue;
      }
      $term = $terms[$tid];
      $query = $node_storage->getQuery()
        ->accessCheck(TRUE)
        ->condition('status', 1)
        ->condition('type', 'photo')
        ->condition('field_categories', $tid);
      if ($this->hasField('field_featured')) {
        $query->sort('field_featured', 'DESC');
      }
      $query->sort('created', 'DESC')->range(0, 3);
      $nids = array_map('intval', array_values($query->execute()));
      $out[] = [
        'name' => $term->label(),
        'url' => $term->toUrl()->toString(),
        'photos' => $this->cardsInOrder($nids, 'field_cover_image', 'images_450x800', 'photo'),
      ];
    }
    return $out;
  }

  /**
   * Hottest published photos by statistics totalcount, then created.
   *
   * @param int[] $exclude
   *   Node IDs already chosen.
   *
   * @return int[]
   *   Node IDs.
   */
  protected function hotPhotoIds(array $exclude, int $limit): array {
    if ($limit < 1) {
      return [];
    }
    try {
      if (!$this->database->schema()->tableExists('node_counter')) {
        return $this->latestPhotoIds($exclude, $limit);
      }
      $query = $this->database->select('node_field_data', 'n');
      $query->addTag('node_access');
      $query->leftJoin('node_counter', 'c', 'c.nid = n.nid');
      $query->addField('n', 'nid');
      $query->condition('n.type', 'photo');
      $query->condition('n.status', 1);
      $query->condition('n.default_langcode', 1);
      if ($exclude) {
        $query->condition('n.nid', $exclude, 'NOT IN');
      }
      $query->addExpression('COALESCE(c.totalcount, 0)', 'hot');
      $query->orderBy('hot', 'DESC');
      $query->orderBy('n.created', 'DESC');
      $query->range(0, $limit);
      return array_map('intval', $query->execute()->fetchCol());
    }
    catch (\Exception $e) {
      $this->logger->error('Hot photo query failed, using latest photos: @message', ['@message' => $e->getMessage()]);
      return $this->latestPhotoIds($exclude, $limit);
    }
  }

  /**
   * Latest published photos, excluding the given IDs.
   *
   * @param int[] $exclude
   *   Node IDs already chosen.
   *
   * @return int[]
   *   Node IDs.
   */
  protected function latestPhotoIds(array $exclude, int $limit): array {
    $query = $this->entityTypeManager->getStorage('node')->getQuery()
      ->accessCheck(TRUE)
      ->condition('type', 'photo')
      ->condition('status', 1)
      ->sort('created', 'DESC')
      ->range(0, $limit);
    if ($exclude) {
      $query->condition('nid', $exclude, 'NOT IN');
    }
    return array_map('intval', array_values($query->execute()));
  }

  /**
   * @param int[] $nids
   *   Node IDs in display order.
   *
   * @return array<int, array<string, mixed>>
   *   Card rows.
   */
  protected function cardsInOrder(array $nids, string $image_field, string $style, string $kind): array {
    if (!$nids) {
      return [];
    }
    $nodes = $this->entityTypeManager->getStorage('node')->loadMultiple($nids);
    $items = [];
    foreach ($nids as $nid) {
      if (isset($nodes[$nid]) && $nodes[$nid] instanceof NodeInterface) {
        $items[] = $this->card($nodes[$nid], $image_field, $style, $kind);
      }
    }
    return $items;
  }

  /**
   * @return array<string, mixed>
   *   One card.
   */
  protected function card(NodeInterface $node, string $image_field, string $style, string $kind): array {
    $image = $this->image($node, $image_field, $style);
    $summary = '';
    if ($kind === 'slide') {
      $summary = $this->plainText($node, 'field_summary', 60);
    }
    elseif ($kind === 'article') {
      $summary = $this->plainText($node, 'field_body', 120);
    }
    $count = 0;
    if ($kind === 'photo' && $node->hasField('field_images')) {
      $count = (int) $node->get('field_images')->count();
    }
    return [
      'title' => $node->label(),
      'url' => $node->toUrl()->toString(),
      'img' => $image['url'],
      'width' => $image['width'],
      'height' => $image['height'],
      'count' => $count,
      'duration' => $kind === 'video' ? $this->formatDuration($node) : '',
      'model' => $kind === 'photo' ? $this->modelName($node) : '',
      'summary' => $summary,
      'date' => $kind === 'article' ? $this->dateFormatter->format($node->getCreatedTime(), 'custom', 'm-d') : '',
    ];
  }

  /**
   * Model names from field_model, joined for a single line.
   */
  protected function modelName(NodeInterface $node): string {
    if (!$node->hasField('field_model') || $node->get('field_model')->isEmpty()) {
      return '';
    }
    $names = [];
    foreach ($node->get('field_model')->referencedEntities() as $term) {
      $label = trim((string) $term->label());
      if ($label !== '') {
        $names[] = $label;
      }
    }
    return implode(' · ', $names);
  }

  /**
   * @return array{url: string, width: int, height: int}
   *   Styled image URL and dimensions.
   */
  protected function image(NodeInterface $node, string $field, string $style_name): array {
    $empty = ['url' => '', 'width' => 0, 'height' => 0];
    if (!$node->hasField($field) || $node->get($field)->isEmpty()) {
      return $empty;
    }
    $entity = $node->get($field)->entity;
    $file = NULL;
    $width = 0;
    $height = 0;
    if ($entity instanceof MediaInterface) {
      if ($entity->hasField('field_media_image') && !$entity->get('field_media_image')->isEmpty()) {
        $item = $entity->get('field_media_image')->first();
        if ($item) {
          $width = (int) ($item->width ?? 0);
          $height = (int) ($item->height ?? 0);
          $file = $item->entity;
        }
      }
      if (!$file instanceof FileInterface && $entity->hasField('thumbnail') && !$entity->get('thumbnail')->isEmpty()) {
        $file = $entity->get('thumbnail')->entity;
      }
    }
    elseif ($entity instanceof FileInterface) {
      $file = $entity;
    }
    if (!$file instanceof FileInterface) {
      return $empty;
    }
    $style = ImageStyle::load($style_name);
    $url = $style ? $style->buildUrl($file->getFileUri()) : $this->fileUrlGenerator->generateString($file->getFileUri());
    if ($style) {
      foreach ($style->getEffects() as $effect) {
        $data = $effect->getConfiguration()['data'] ?? [];
        if (!empty($data['width']) && !empty($data['height'])) {
          $width = (int) $data['width'];
          $height = (int) $data['height'];
          break;
        }
      }
    }
    return ['url' => $url, 'width' => $width, 'height' => $height];
  }

  /**
   * Formats a duration stored as whole seconds.
   */
  protected function formatDuration(NodeInterface $node): string {
    if (!$node->hasField('field_duration') || $node->get('field_duration')->isEmpty()) {
      return '';
    }
    $seconds = (int) $node->get('field_duration')->value;
    if ($seconds < 1) {
      return '';
    }
    $hours = intdiv($seconds, 3600);
    $minutes = intdiv($seconds % 3600, 60);
    $remain = $seconds % 60;
    if ($hours > 0) {
      return sprintf('%d:%02d:%02d', $hours, $minutes, $remain);
    }
    return sprintf('%02d:%02d', $minutes, $remain);
  }

  /**
   * Plain excerpt trimmed to a character count.
   */
  protected function plainText(NodeInterface $node, string $field, int $length): string {
    if (!$node->hasField($field) || $node->get($field)->isEmpty()) {
      return '';
    }
    $item = $node->get($field)->first();
    if (!$item) {
      return '';
    }
    $text = '';
    if (isset($item->summary) && trim((string) $item->summary) !== '') {
      $text = (string) $item->summary;
    }
    else {
      $text = (string) ($item->value ?? '');
    }
    $text = trim(preg_replace('/\s+/u', ' ', strip_tags($text)) ?? '');
    if ($text === '') {
      return '';
    }
    if (mb_strlen($text) <= $length) {
      return $text;
    }
    return mb_substr($text, 0, $length) . '…';
  }

  /**
   * Whether a node field storage exists.
   */
  protected function hasField(string $name): bool {
    $definitions = $this->entityFieldManager->getFieldStorageDefinitions('node');
    return isset($definitions[$name]);
  }

}
