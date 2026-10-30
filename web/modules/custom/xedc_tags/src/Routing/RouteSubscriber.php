<?php

namespace Drupal\xedc_tags\Routing;

use Drupal\Core\Routing\RouteSubscriberBase;
use Drupal\Core\Routing\RoutingEvents;
use Symfony\Component\Routing\RouteCollection;

class RouteSubscriber extends RouteSubscriberBase {

  protected function alterRoutes(RouteCollection $collection) {
    if ($route = $collection->get('entity.taxonomy_term.canonical')) {
      $orig = $route->getDefaults();
      $route->setDefaults([
        '_controller' => '\Drupal\xedc_tags\Controller\TagsController::term',
        '_title_callback' => '\Drupal\xedc_tags\Controller\TagsController::termTitle',
        '_xt_view_id' => $orig['view_id'] ?? '',
        '_xt_display_id' => $orig['display_id'] ?? '',
      ]);
    }
    // taxonomy_term 与 image_gallery 都声明了 taxonomy/term/%。
    // 公开地址只走 canonical，避免第二条路由抢走图片栏目。
    if ($collection->get('view.taxonomy_term.page_1')) {
      $collection->remove('view.taxonomy_term.page_1');
    }
  }

  public static function getSubscribedEvents(): array {
    $events = parent::getSubscribedEvents();
    // Run after Views has taken over the term route.
    $events[RoutingEvents::ALTER] = ['onAlterRoutes', -300];
    return $events;
  }

}
