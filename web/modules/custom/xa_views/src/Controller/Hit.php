<?php

namespace Drupal\xa_views\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\node\Entity\Node;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;

class Hit extends ControllerBase {

  public function hit(Request $request, $nid) {
    $node = Node::load((int) $nid);
    if (!$node || $node->bundle() !== 'article' || !$node->isPublished()) {
      return new JsonResponse(['ok' => FALSE], 404);
    }
    $id = (int) $node->id();

    // 同一访客 30 分钟内同一篇只计一次（兼容 Cloudflare 代理）
    $who = $request->headers->get('CF-Connecting-IP') ?: $request->getClientIp();
    $flood = \Drupal::flood();
    $event = 'xa_views.hit.' . $id;
    if (!$flood->isAllowed($event, 1, 1800, $who)) {
      return new JsonResponse(['ok' => TRUE, 'counted' => FALSE]);
    }
    $flood->register($event, 1800, $who);

    $db = \Drupal::database();
    $vid = (int) $node->getRevisionId();
    $rows = $db->update('node__field_views')
      ->expression('field_views_value', 'field_views_value + 1')
      ->condition('entity_id', $id)->condition('delta', 0)->execute();
    if ($rows) {
      $db->update('node_revision__field_views')
        ->expression('field_views_value', 'field_views_value + 1')
        ->condition('revision_id', $vid)->condition('delta', 0)->execute();
    }
    else {
      foreach (['node__field_views', 'node_revision__field_views'] as $t) {
        $db->insert($t)->fields([
          'bundle' => 'article', 'deleted' => 0, 'entity_id' => $id, 'revision_id' => $vid,
          'langcode' => $node->language()->getId(), 'delta' => 0, 'field_views_value' => 1,
        ])->execute();
      }
    }
    $count = (int) $db->select('node__field_views', 'f')->fields('f', ['field_views_value'])
      ->condition('entity_id', $id)->execute()->fetchField();

    return new JsonResponse(['ok' => TRUE, 'counted' => TRUE, 'views' => $count]);
  }

}
