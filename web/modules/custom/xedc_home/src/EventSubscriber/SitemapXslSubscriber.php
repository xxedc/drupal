<?php

namespace Drupal\xedc_home\EventSubscriber;

use Drupal\Core\Extension\ThemeExtensionList;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * Serves a plain XSLT 1.0 stylesheet for sitemap.xml.
 *
 * Simple XML Sitemap already points the XML at its XSL route. That stylesheet
 * is XSLT 2.0 and pulls in scripts, which browsers do not apply reliably.
 * Replacing only this response leaves the sitemap XML unchanged.
 */
class SitemapXslSubscriber implements EventSubscriberInterface {

  public function __construct(
    protected ThemeExtensionList $themeList,
  ) {}

  /**
   * {@inheritdoc}
   */
  public static function getSubscribedEvents(): array {
    return [
      KernelEvents::RESPONSE => ['onResponse'],
    ];
  }

  /**
   * Replaces the module stylesheet with the theme file.
   */
  public function onResponse(ResponseEvent $event): void {
    if (!$event->isMainRequest()) {
      return;
    }
    if ($event->getRequest()->attributes->get('_route') !== 'simple_sitemap.sitemap_xsl') {
      return;
    }
    $path = $this->themeList->getPath('xedc') . '/xsl/sitemap.xsl';
    if (!is_readable($path)) {
      return;
    }
    $xsl = file_get_contents($path);
    if ($xsl === FALSE || $xsl === '') {
      return;
    }
    $response = $event->getResponse();
    $response->setContent($xsl);
    $response->headers->set('Content-Type', 'text/xsl; charset=UTF-8');
  }

}
