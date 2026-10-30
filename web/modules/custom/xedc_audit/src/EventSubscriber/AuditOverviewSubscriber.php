<?php

namespace Drupal\xedc_audit\EventSubscriber;

use Drupal\Core\StringTranslation\StringTranslationTrait;
use Drupal\Core\Url;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\ViewEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * Adds download buttons to the audit overview.
 */
class AuditOverviewSubscriber implements EventSubscriberInterface {

  use StringTranslationTrait;

  /**
   * {@inheritdoc}
   */
  public static function getSubscribedEvents(): array {
    // Run before the main-content subscriber turns the render array into a
    // response. Equal priority would lose that race.
    return [KernelEvents::VIEW => ['onView', 30]];
  }

  /**
   * Inserts JSON and CSV download links into the overview actions.
   */
  public function onView(ViewEvent $event): void {
    if (!$event->isMainRequest()) {
      return;
    }
    if ($event->getRequest()->attributes->get('_route') !== 'audit.reports') {
      return;
    }

    $result = $event->getControllerResult();
    if (!is_array($result)) {
      return;
    }
    if (!isset($result['actions']) || !is_array($result['actions'])) {
      $result['actions'] = [
        '#type' => 'container',
        '#attributes' => ['class' => ['audit-list-actions']],
        '#weight' => -10,
      ];
    }

    $result['actions']['download_json'] = $this->downloadLink('json', $this->t('下载全部报告（JSON）'));
    $result['actions']['download_csv'] = $this->downloadLink('csv', $this->t('下载全部报告（CSV）'));
    $event->setControllerResult($result);
  }

  /**
   * Builds one CSRF-protected download link.
   *
   * @param \Drupal\Core\StringTranslation\TranslatableMarkup|string $title
   *   The link text.
   *
   * @return array<string, mixed>
   *   The link render array.
   */
  protected function downloadLink(string $format, $title): array {
    return [
      '#type' => 'link',
      '#title' => $title,
      '#url' => Url::fromRoute('xedc_audit.download', ['format' => $format]),
      '#attributes' => [
        'class' => ['button'],
      ],
    ];
  }

}
