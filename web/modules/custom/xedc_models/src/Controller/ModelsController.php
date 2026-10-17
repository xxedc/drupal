<?php

namespace Drupal\xedc_models\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\Database\Connection;
use Drupal\Core\Url;
use Drupal\file\FileInterface;
use Drupal\image\Entity\ImageStyle;
use Drupal\node\Entity\Node;
use Symfony\Component\DependencyInjection\ContainerInterface;

class ModelsController extends ControllerBase {

  public function __construct(protected Connection $db) {}

  public static function create(ContainerInterface $container) {
    return new static($container->get('database'));
  }

  public function page() {
    $schema = $this->db->schema();

    // 所有 models 术语
    $terms = $this->db->select('taxonomy_term_field_data', 't')
      ->fields('t', ['tid', 'name'])
      ->condition('t.vid', 'models')
      ->condition('t.default_langcode', 1)
      ->execute()->fetchAllKeyed();

    // 别名 -> 主名
    $alias = [];
    if ($schema->tableExists('taxonomy_term__field_alias_of')) {
      $alias = $this->db->select('taxonomy_term__field_alias_of', 'a')
        ->fields('a', ['entity_id', 'field_alias_of_target_id'])
        ->condition('a.deleted', 0)
        ->execute()->fetchAllKeyed();
    }

    // 手动推荐内容
    $featured = [];
    if ($schema->tableExists('taxonomy_term__field_featured_content')) {
      $featured = $this->db->select('taxonomy_term__field_featured_content', 'f')
        ->fields('f', ['entity_id', 'field_featured_content_target_id'])
        ->condition('f.deleted', 0)
        ->execute()->fetchAllKeyed();
    }

    // 初始化主模特
    $groups = [];
    foreach ($terms as $tid => $name) {
      $main = (isset($alias[$tid]) && isset($terms[$alias[$tid]])) ? $alias[$tid] : $tid;
      $groups[$main]['names'][] = $name;
      $groups[$main]['nids'] = $groups[$main]['nids'] ?? [];
    }

    // 内容统计
    $q = $this->db->select('node__field_model', 'm');
    $q->join('node_field_data', 'n', 'n.nid = m.entity_id AND n.default_langcode = 1');
    $q->condition('n.status', 1)->condition('m.deleted', 0);
    $q->addField('m', 'field_model_target_id', 'tid');
    $q->addField('n', 'nid');
    $q->addField('n', 'created');
    if ($schema->tableExists('node_counter')) {
      $q->leftJoin('node_counter', 'c', 'c.nid = n.nid');
      $q->addExpression('COALESCE(c.totalcount, 0)', 'views');
    }
    else {
      $q->addExpression('0', 'views');
    }
    foreach ($q->execute() as $r) {
      if (!isset($terms[$r->tid])) {
        continue;
      }
      $main = (isset($alias[$r->tid]) && isset($terms[$alias[$r->tid]])) ? $alias[$r->tid] : $r->tid;
      $groups[$main]['nids'][$r->nid] = ['v' => (int) $r->views, 'c' => (int) $r->created];
    }

    // 选封面内容：推荐 > 浏览最多 > 最新
    $best = [];
    foreach ($groups as $main => $g) {
      if (!$g['nids']) {
        continue;
      }
      $f = $featured[$main] ?? NULL;
      if ($f && isset($g['nids'][$f])) {
        $best[$main] = $f;
        continue;
      }
      uasort($g['nids'], fn($a, $b) => [$b['v'], $b['c']] <=> [$a['v'], $a['c']]);
      $best[$main] = array_key_first($g['nids']);
    }
    $nodes = $best ? Node::loadMultiple(array_unique($best)) : [];

    $out = [];
    foreach ($groups as $main => $g) {
      $node = isset($best[$main]) ? ($nodes[$best[$main]] ?? NULL) : NULL;
      $out[] = [
        'name' => $terms[$main],
        'count' => count($g['nids']),
        'img' => $this->cover($node),
        'url' => Url::fromRoute('entity.taxonomy_term.canonical', ['taxonomy_term' => $main])->toString(),
        'search' => mb_strtolower(implode(' ', array_unique($g['names']))),
      ];
    }
    usort($out, fn($a, $b) => $b['count'] <=> $a['count']);

    return [
      '#theme' => 'xedc_models_page',
      '#models' => $out,
      '#total' => count($out),
      '#attached' => ['library' => ['xedc_models/models']],
      '#cache' => ['tags' => ['node_list', 'taxonomy_term_list'], 'max-age' => 3600],
    ];
  }

  protected function cover($node) {
    if (!$node || !$node->hasField('field_cover_image') || $node->get('field_cover_image')->isEmpty()) {
      return NULL;
    }
    $e = $node->get('field_cover_image')->entity;
    if ($e && $e->getEntityTypeId() === 'media' && $e->hasField('field_media_image')) {
      $e = $e->get('field_media_image')->entity;
    }
    if (!$e instanceof FileInterface) {
      return NULL;
    }
    $uri = $e->getFileUri();
    $style = ImageStyle::load('large');
    return $style ? $style->buildUrl($uri) : \Drupal::service('file_url_generator')->generateString($uri);
  }

}
