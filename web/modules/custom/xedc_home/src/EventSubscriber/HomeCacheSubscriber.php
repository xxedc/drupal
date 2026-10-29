<?php

namespace Drupal\xedc_home\EventSubscriber;

use Drupal\Component\Datetime\TimeInterface;
use Drupal\Core\Path\PathMatcherInterface;
use Drupal\Core\Session\AccountProxyInterface;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * Expires the cached front page after one hour.
 *
 * Drupal's internal page cache ignores render max-age and keeps entries until
 * a cache tag is invalidated. Heat rankings use statistics and would otherwise
 * stay frozen until a node is saved. Node saves still clear the page via
 * node_list.
 */
class HomeCacheSubscriber implements EventSubscriberInterface {

  public function __construct(
    protected TimeInterface $time,
    protected AccountProxyInterface $currentUser,
    protected PathMatcherInterface $pathMatcher,
  ) {}

  /**
   * Limits anonymous front-page caching to one hour.
   */
  public function onResponse(ResponseEvent $event): void {
    if (!$event->isMainRequest() || $this->currentUser->isAuthenticated() || !$this->pathMatcher->isFrontPage()) {
      return;
    }
    $response = $event->getResponse();
    $response->setExpires(new \DateTimeImmutable('@' . ($this->time->getRequestTime() + 3600)));
    $response->setMaxAge(3600);
    $response->headers->set('Cache-Control', 'public, max-age=3600');
  }

  /**
   * {@inheritdoc}
   */
  public static function getSubscribedEvents(): array {
    // Run after FinishResponseSubscriber::onRespond(), which uses priority 0.
    return [KernelEvents::RESPONSE => ['onResponse', -10]];
  }

}
