<?php

namespace Drupal\xedc_tags\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\Database\Connection;
use Drupal\Core\Datetime\DateFormatterInterface;
use Drupal\Core\Database\Query\PagerSelectExtender;
use Drupal\Core\File\FileUrlGeneratorInterface;
use Drupal\Core\Routing\RouteMatchInterface;
use Drupal\Core\Url;
use Drupal\file\Entity\File;
use Drupal\file\FileInterface;
use Drupal\image\Entity\ImageStyle;
use Drupal\media\MediaInterface;
use Drupal\node\Entity\Node;
use Drupal\node\NodeInterface;
use Drupal\taxonomy\Entity\Term;
use Drupal\taxonomy\TermInterface;
use Drupal\views\Routing\ViewPageController;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\HttpFoundation\RequestStack;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

class TagsController extends ControllerBase {

  const PER_PAGE = 12;
  const VOCAB = 'tags';

  public function __construct(
    protected Connection $db,
    protected FileUrlGeneratorInterface $fug,
    protected DateFormatterInterface $df,
    protected RequestStack $rs,
  ) {}

  public static function create(ContainerInterface $container) {
    return new static(
      $container->get('database'),
      $container->get('file_url_generator'),
      $container->get('date.formatter'),
      $container->get('request_stack'),
    );
  }

  protected function termFromRoute(RouteMatchInterface $route_match): ?TermInterface {
    $term = $route_match->getParameter('taxonomy_term');
    if (!$term instanceof TermInterface) {
      $raw = $route_match->getRawParameter('taxonomy_term');
      $term = $raw ? Term::load($raw) : NULL;
    }
    return $term instanceof TermInterface ? $term : NULL;
  }

  public function termTitle(RouteMatchInterface $route_match) {
    $term = $this->termFromRoute($route_match);
    return $term ? $term->label() : '';
  }

  /**
   * Tag detail page. Other vocabularies fall back to the original handler.
   */
  public function term(RouteMatchInterface $route_match) {
    $term = $this->termFromRoute($route_match);
    if (!$term) {
      throw new NotFoundHttpException();
    }
    if ($term->bundle() !== self::VOCAB) {
      $route = $route_match->getRouteObject();
      $vid = $route->getDefault('_xt_view_id');
      if ($vid) {
        return \Drupal::classResolver(ViewPageController::class)
          ->handle($vid, $route->getDefault('_xt_display_id'), $route_match);
      }
      return $this->entityTypeManager()->getViewBuilder('taxonomy_term')->view($term, 'full');
    }

    $tid = (int) $term->id();
    $sort = $this->rs->getCurrentRequest()->query->get('sort') === 'hot' ? 'hot' : 'new';

    $total = (int) $this->entityTypeManager()->getStorage('node')->getQuery()
      ->accessCheck(TRUE)
      ->condition('status', 1)
      ->condition('field_tags', $tid)
      ->count()
      ->execute();

    $q = $this->db->select('node__field_tags', 't');
    $q->join('node_field_data', 'n', 'n.nid = t.entity_id AND n.langcode = t.langcode AND n.status = 1');
    $q->condition('t.field_tags_target_id', $tid)->condition('t.deleted', 0);
    $q->fields('n', ['nid', 'created']);
    $hasCounter = $this->db->schema()->tableExists('node_counter');
    if ($hasCounter) {
      $q->leftJoin('node_counter', 'c', 'c.nid = n.nid');
      $q->addExpression('COALESCE(c.totalcount, 0)', 'hot');
    }
    $q->distinct();
    if ($sort === 'hot' && $hasCounter) {
      $q->orderBy('hot', 'DESC');
    }
    $q->orderBy('n.created', 'DESC');
    $rows = $q->extend(PagerSelectExtender::class)->limit(self::PER_PAGE)->execute()->fetchAll();

    $nodes = Node::loadMultiple(array_column($rows, 'nid'));
    $items = [];
    foreach ($rows as $r) {
      if (isset($nodes[$r->nid])) {
        $items[] = $this->card($nodes[$r->nid]);
      }
    }

    return [
      'page' => [
        '#theme' => 'xedc_tags_term',
        '#term_name' => $term->label(),
        '#total' => $total,
        '#items' => $items,
        '#sort' => $sort,
        '#sort_urls' => [
          'new' => $term->toUrl('canonical', ['query' => ['sort' => 'new']])->toString(),
          'hot' => $term->toUrl('canonical', ['query' => ['sort' => 'hot']])->toString(),
        ],
        '#index_url' => Url::fromRoute('xedc_tags.index')->toString(),
        '#home_url' => Url::fromRoute('<front>')->toString(),
        '#attached' => ['library' => ['xedc_tags/xedc_tags']],
      ],
      'pager' => ['#type' => 'pager', '#quantity' => 5],
      '#cache' => [
        'contexts' => ['url.query_args'],
        'tags' => ['node_list', 'taxonomy_term:' . $tid],
      ],
    ];
  }

  /**
   * All tags page.
   */
  public function index() {
    $terms = $this->entityTypeManager()->getStorage('taxonomy_term')
      ->loadByProperties(['vid' => self::VOCAB]);

    $stats = $this->db->query(
      "SELECT t.field_tags_target_id AS tid, COUNT(DISTINCT t.entity_id) AS cnt, MAX(n.created) AS latest
       FROM {node__field_tags} t
       INNER JOIN {node_field_data} n ON n.nid = t.entity_id AND n.langcode = t.langcode AND n.status = 1
       WHERE t.deleted = 0
       GROUP BY t.field_tags_target_id"
    )->fetchAllAssoc('tid');

    $totalItems = (int) $this->db->query(
      "SELECT COUNT(DISTINCT t.entity_id)
       FROM {node__field_tags} t
       INNER JOIN {node_field_data} n ON n.nid = t.entity_id AND n.langcode = t.langcode AND n.status = 1
       WHERE t.deleted = 0"
    )->fetchField();

    $max = 1;
    foreach ($stats as $s) {
      $max = max($max, (int) $s->cnt);
    }

    $tags = [];
    foreach ($terms as $tid => $term) {
      if (empty($stats[$tid])) {
        continue;
      }
      $cnt = (int) $stats[$tid]->cnt;
      $tags[] = [
        'name' => $term->label(),
        'url' => $term->toUrl()->toString(),
        'count' => $cnt,
        'latest' => (int) $stats[$tid]->latest,
        'pct' => max(6, (int) round($cnt / $max * 100)),
      ];
    }
    usort($tags, fn($a, $b) => [$b['count'], $a['name']] <=> [$a['count'], $b['name']]);

    return [
      '#theme' => 'xedc_tags_index',
      '#tags' => $tags,
      '#total_tags' => count($tags),
      '#total_items' => $totalItems,
      '#home_url' => Url::fromRoute('<front>')->toString(),
      '#attached' => ['library' => ['xedc_tags/xedc_tags']],
      '#cache' => ['tags' => ['node_list', 'taxonomy_term_list']],
    ];
  }

  protected function card(NodeInterface $n): array {
    $cat = '';
    if ($n->hasField('field_categories') && !$n->get('field_categories')->isEmpty()) {
      $e = $n->get('field_categories')->entity;
      $cat = $e ? $e->label() : '';
    }
    return [
      'title' => $n->label(),
      'url' => $n->toUrl()->toString(),
      'date' => $this->df->format($n->getCreatedTime(), 'custom', 'Y-m-d'),
      'cat' => $cat,
      'cover' => $this->cover($n),
    ];
  }

  protected function cover(NodeInterface $n): string {
    foreach (['field_cover_image', 'field_images'] as $f) {
      if (!$n->hasField($f) || $n->get($f)->isEmpty()) {
        continue;
      }
      $ent = $n->get($f)->entity;
      $file = NULL;
      if ($ent instanceof MediaInterface) {
        $fid = $ent->getSource()->getSourceFieldValue($ent);
        $file = $fid ? File::load($fid) : NULL;
      }
      elseif ($ent instanceof FileInterface) {
        $file = $ent;
      }
      if (!$file) {
        continue;
      }
      $uri = $file->getFileUri();
      $style = ImageStyle::load('large');
      return $style ? $style->buildUrl($uri) : $this->fug->generateString($uri);
    }
    return '';
  }

}
