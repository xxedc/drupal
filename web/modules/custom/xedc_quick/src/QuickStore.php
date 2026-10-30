<?php

namespace Drupal\xedc_quick;

use Drupal\Core\Database\Connection;
use Drupal\Core\State\StateInterface;

/**
 * Bookkeeping for quick gallery uploads.
 *
 * The hash and original-size tables are not entities. Upload routes already
 * require the administer nodes permission, so these queries do not list
 * content to anonymous users.
 */
class QuickStore {

  public function __construct(
    protected Connection $database,
    protected StateInterface $state,
  ) {}

  /**
   * Total original bytes for the given media ids, or 0 when unknown.
   */
  public function originalSize(array $mids): int {
    if (!$mids || !$this->database->schema()->tableExists('xedc_quick_orig')) {
      return 0;
    }
    return (int) $this->database->query('SELECT SUM(bytes) FROM {xedc_quick_orig} WHERE mid IN (:mids[])', [':mids[]' => $mids])->fetchField();
  }

  /**
   * Original byte size keyed by media id.
   *
   * @return array<int|string, int|string>
   *   Media id to byte count.
   */
  public function originalSizes(array $mids): array {
    if (!$mids || !$this->database->schema()->tableExists('xedc_quick_orig')) {
      return [];
    }
    return $this->database->query('SELECT mid, bytes FROM {xedc_quick_orig} WHERE mid IN (:mids[])', [':mids[]' => $mids])->fetchAllKeyed();
  }

  /**
   * Creates the hash and original-size tables once.
   *
   * Upload used to run CREATE TABLE on the request path. After the tables
   * exist, later requests only read a state flag.
   */
  public function ensureTables(): void {
    if ($this->state->get('xedc_quick.schema') === 1) {
      return;
    }
    $schema = $this->database->schema();
    if (!$schema->tableExists('xedc_quick_hash') || !$schema->tableExists('xedc_quick_orig')) {
      \Drupal::moduleHandler()->loadInclude('xedc_quick', 'install');
      foreach (xedc_quick_schema() as $name => $table) {
        if (!$schema->tableExists($name)) {
          $schema->createTable($name, $table);
        }
      }
    }
    $this->state->set('xedc_quick.schema', 1);
  }

  /**
   * Media id already stored for this file hash, or 0.
   */
  public function mediaIdForHash(string $hash): int {
    return (int) $this->database->select('xedc_quick_hash', 'h')
      ->fields('h', ['mid'])
      ->condition('hash', $hash)
      ->range(0, 1)
      ->execute()
      ->fetchField();
  }

  /**
   * Stores the hash and the pre-compression size for one media item.
   */
  public function rememberUpload(string $hash, int $mid, int $bytes): void {
    $this->database->merge('xedc_quick_hash')->key('hash', $hash)->fields(['mid' => $mid])->execute();
    $this->database->merge('xedc_quick_orig')->key('mid', $mid)->fields([
      'bytes' => max(0, $bytes),
    ])->execute();
  }

}
