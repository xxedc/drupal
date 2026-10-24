<?php

namespace Drupal\xedc_member\EventSubscriber;

use Drupal\Core\Routing\RouteMatchInterface;
use Drupal\Core\Session\AccountProxyInterface;
use Drupal\node\Entity\Node;
use Drupal\node\NodeInterface;
use Drupal\xedc_member\Service\HistoryManager;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\RequestEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * Records authenticated content detail views for the member center.
 */
class HistorySubscriber implements EventSubscriberInterface {

  /**
   * Constructs a HistorySubscriber.
   */
  public function __construct(
    protected HistoryManager $historyManager,
    protected RouteMatchInterface $routeMatch,
    protected AccountProxyInterface $currentUser,
  ) {}

  /**
   * {@inheritdoc}
   */
  public static function getSubscribedEvents(): array {
    return [
      KernelEvents::REQUEST => ['onRequest', 0],
    ];
  }

  /**
   * Records a canonical published content view.
   */
  public function onRequest(RequestEvent $event): void {
    if (!$event->isMainRequest()) {
      return;
    }

    $request = $event->getRequest();
    if (!$request->isMethod('GET') || $request->isXmlHttpRequest()) {
      return;
    }
    if ($request->query->has('_wrapper_format') || $request->query->has('_format')) {
      return;
    }

    if ($this->routeMatch->getRouteName() !== 'entity.node.canonical') {
      return;
    }

    $account = $this->currentUser;
    if (!$account->isAuthenticated() || (int) $account->id() <= 0) {
      return;
    }

    $node = $this->routeMatch->getParameter('node');
    if (is_numeric($node)) {
      $node = Node::load($node);
    }
    if (!$node instanceof NodeInterface) {
      return;
    }
    if (!in_array($node->bundle(), HistoryManager::ALLOWED_BUNDLES, TRUE) || !$node->isPublished()) {
      return;
    }
    if (!$node->access('view')) {
      return;
    }

    $this->historyManager->record((int) $account->id(), $node);
  }

}
