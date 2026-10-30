<?php

namespace Drupal\xedc_home\EventSubscriber;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * Adds the security headers that are not already set by the web server.
 *
 * X-Content-Type-Options and X-Frame-Options are already present. Framing
 * stays SAMEORIGIN so the same-site login dialog iframe keeps working.
 */
class SecurityHeaderSubscriber implements EventSubscriberInterface {

  /**
   * Sets Referrer-Policy and HSTS when the response does not already have them.
   */
  public function onResponse(ResponseEvent $event): void {
    if (!$event->isMainRequest()) {
      return;
    }
    $headers = $event->getResponse()->headers;
    if (!$headers->has('Referrer-Policy')) {
      $headers->set('Referrer-Policy', 'strict-origin-when-cross-origin');
    }
    if ($event->getRequest()->isSecure() && !$headers->has('Strict-Transport-Security')) {
      $headers->set('Strict-Transport-Security', 'max-age=15552000');
    }
  }

  /**
   * {@inheritdoc}
   */
  public static function getSubscribedEvents(): array {
    return [KernelEvents::RESPONSE => ['onResponse', -20]];
  }

}
