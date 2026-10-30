<?php

namespace Drupal\xedc_audit\Drush\Commands;

use Consolidation\AnnotatedCommand\Hooks\HookManager;
use Drupal\audit\AuditAnalyzerPluginManager;
use Drupal\audit\Drush\Commands\AuditCommands;
use Drupal\audit\Service\AuditRunner;
use Drupal\audit\Service\AuditScoreStorage;
use Drupal\xedc_audit\AuditReportExporter;
use Drush\Attributes as CLI;
use Drush\Commands\AutowireTrait;
use Drush\Commands\DrushCommands;
use Symfony\Component\DependencyInjection\Attribute\Autowire;

/**
 * Adds CSV output to the existing audit:run command.
 */
final class AuditFormatCommands extends DrushCommands {

  use AutowireTrait;

  public function __construct(
    #[Autowire(service: 'audit.runner')]
    protected AuditRunner $runner,
    #[Autowire(service: 'plugin.manager.audit_analyzer')]
    protected AuditAnalyzerPluginManager $pluginManager,
    #[Autowire(service: 'audit.score_storage')]
    protected AuditScoreStorage $scoreStorage,
    #[Autowire(service: 'xedc_audit.exporter')]
    protected AuditReportExporter $exporter,
  ) {
    parent::__construct();
  }

  /**
   * Prints CSV for --format=csv and leaves every other format to Audit.
   *
   * The replacement receives the same arguments as audit:run.
   */
  #[CLI\Hook(type: HookManager::REPLACE_COMMAND_HOOK, target: 'audit:run')]
  public function replaceAuditRun(string $analyzerId, array $options = []): int {
    $format = strtolower((string) ($options['format'] ?? 'json'));

    if ($format === 'csv') {
      $report = $this->exporter->run($analyzerId);
      $this->output()->write($this->exporter->toCsv($report));
      if ($report['count'] === 0) {
        $this->logger()?->error(dt('No audit results were produced for @id.', ['@id' => $analyzerId]));
        return self::EXIT_FAILURE;
      }
      if ($report['failed'] !== []) {
        return self::EXIT_FAILURE;
      }
      return self::EXIT_SUCCESS;
    }

    $original = new AuditCommands($this->runner, $this->pluginManager, $this->scoreStorage);
    $original->setInput($this->input());
    $original->setOutput($this->output());
    $logger = $this->logger();
    if ($logger) {
      $original->setLogger($logger);
    }

    return $original->runAnalyzer($analyzerId, $options);
  }

}
