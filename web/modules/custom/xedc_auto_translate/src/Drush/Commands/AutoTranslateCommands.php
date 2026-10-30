<?php

declare(strict_types=1);

namespace Drupal\xedc_auto_translate\Drush\Commands;

use Drupal\Core\Entity\ContentEntityInterface;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\xedc_auto_translate\Translator;
use Drush\Attributes as CLI;
use Drush\Commands\DrushCommands;

/**
 * Manual translation commands for content that is already published.
 */
final class AutoTranslateCommands extends DrushCommands {

  public function __construct(
    private readonly Translator $translator,
    private readonly EntityTypeManagerInterface $entityTypeManager,
  ) {
    parent::__construct();
  }

  /**
   * Translates one Chinese entity into en, ru and ja.
   */
  #[CLI\Command(name: 'xedc:translate', aliases: ['xedc-translate'])]
  #[CLI\Argument(name: 'entity_type', description: 'Entity type, for example node')]
  #[CLI\Argument(name: 'id', description: 'Entity ID')]
  #[CLI\Option(name: 'force', description: 'Overwrite existing translations')]
  #[CLI\Usage(name: 'drush xedc:translate node 123', description: 'Translate a node if translations are missing')]
  #[CLI\Usage(name: 'drush xedc:translate node 123 --force', description: 'Overwrite existing translations')]
  public function translate(string $entity_type, string $id, array $options = ['force' => FALSE]): void {
    $entity = $this->entityTypeManager->getStorage($entity_type)->load($id);
    if (!$entity instanceof ContentEntityInterface) {
      throw new \InvalidArgumentException(sprintf('Cannot load %s %s.', $entity_type, $id));
    }
    $results = $this->translator->translateEntity($entity, (bool) $options['force']);
    if (!$results) {
      $this->logger()->warning('Nothing was translated. Check the API key, source language, and published state.');
      return;
    }
    foreach ($results as $langcode => $status) {
      $this->logger()->notice('{lang}: {status}', ['lang' => $langcode, 'status' => $status]);
    }
  }

  /**
   * Translates published Chinese content that is still missing a language.
   */
  #[CLI\Command(name: 'xedc:translate-missing', aliases: ['xedc-translate-missing'])]
  #[CLI\Option(name: 'limit', description: 'Maximum entities to process')]
  #[CLI\Option(name: 'force', description: 'Overwrite existing translations')]
  #[CLI\Usage(name: 'drush xedc:translate-missing --limit=20', description: 'Backfill up to 20 published entities')]
  public function translateMissing(array $options = ['limit' => 20, 'force' => FALSE]): void {
    $config = \Drupal::config('xedc_auto_translate.settings');
    $limit = max(1, (int) $options['limit']);
    $done = 0;
    foreach ($config->get('bundles') ?? [] as $bundle_id) {
      if ($done >= $limit) {
        break;
      }
      [$entity_type, $bundle] = array_pad(explode('.', (string) $bundle_id, 2), 2, '');
      if ($entity_type === '' || $bundle === '' || !$this->entityTypeManager->hasDefinition($entity_type)) {
        continue;
      }
      $definition = $this->entityTypeManager->getDefinition($entity_type);
      $query = $this->entityTypeManager->getStorage($entity_type)->getQuery()
        ->accessCheck(FALSE)
        ->condition($definition->getKey('bundle'), $bundle)
        ->condition($definition->getKey('langcode') ?: 'langcode', (string) $config->get('source_langcode'))
        ->range(0, $limit - $done);
      if ($definition->hasKey('default_langcode')) {
        $query->condition($definition->getKey('default_langcode'), 1);
      }
      if ($entity_type === 'node') {
        $query->condition('status', 1);
      }
      $ids = $query->execute();
      foreach ($this->entityTypeManager->getStorage($entity_type)->loadMultiple($ids) as $entity) {
        if (!$entity instanceof ContentEntityInterface) {
          continue;
        }
        $results = $this->translator->translateEntity($entity, (bool) $options['force']);
        $done++;
        $this->logger()->notice('{type} {id}: {result}', [
          'type' => $entity_type,
          'id' => $entity->id(),
          'result' => $results ? json_encode($results, JSON_UNESCAPED_UNICODE) : 'skipped',
        ]);
        if ($done >= $limit) {
          break;
        }
      }
    }
    $this->logger()->notice('Processed {count} entities.', ['count' => $done]);
  }

}
