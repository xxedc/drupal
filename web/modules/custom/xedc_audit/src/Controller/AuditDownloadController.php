<?php

namespace Drupal\xedc_audit\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\xedc_audit\AuditReportExporter;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\HttpFoundation\Response;

/**
 * Streams a combined audit report without storing it on disk.
 */
class AuditDownloadController extends ControllerBase {

  public function __construct(
    protected AuditReportExporter $exporter,
  ) {}

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container): static {
    return new static(
      $container->get('xedc_audit.exporter'),
    );
  }

  /**
   * Runs every enabled audit and returns the report as a download.
   */
  public function download(string $format): Response {
    $report = $this->exporter->runAll();
    $stamp = (new \DateTimeImmutable())->format('Ymd-His');

    if ($format === 'csv') {
      $body = $this->exporter->toCsv($report);
      $content_type = 'text/csv; charset=UTF-8';
      $filename = 'audit-report-' . $stamp . '.csv';
    }
    else {
      $body = $this->exporter->toJson($report);
      $content_type = 'application/json; charset=UTF-8';
      $filename = 'audit-report-' . $stamp . '.json';
    }

    $response = new Response($body);
    $response->headers->set('Content-Type', $content_type);
    $response->headers->set('Content-Disposition', 'attachment; filename="' . $filename . '"');
    $response->headers->set('Cache-Control', 'private, no-store');
    $response->headers->set('X-Content-Type-Options', 'nosniff');
    return $response;
  }

}
