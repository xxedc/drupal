<?php

namespace Drupal\xedc_member\Service;

use Drupal\Component\Datetime\TimeInterface;
use Drupal\Core\Database\Connection;
use Drupal\Core\Database\DatabaseException;
use Drupal\Core\Database\Query\PagerSelectExtender;
use Drupal\Core\Database\Query\SelectInterface;
use Drupal\node\NodeInterface;
use Drupal\user\UserDataInterface;

/**
 * Stores and retrieves member browsing history.
 */
class HistoryManager {

  /**
   * Content types that can be recorded.
   */
  public const ALLOWED_BUNDLES = ['photo', 'video', 'article'];

  /**
   * Number of history records per page.
   */
  public const PER_PAGE = 12;

  /**
   * Pager element id, kept off the default so other blocks cannot steal it.
   */
  public const PAGER_ELEMENT = 10;

  /**
   * User data key for the history recording preference.
   */
  public const ENABLED_KEY = 'history_enabled';

  /**
   * Minimum seconds between writes for the same user/content.
   */
  public const WRITE_THROTTLE = 60;

  /**
   * Default history retention in days.
   */
  public const RETENTION_DAYS = 180;

  /**
   * Constructs a HistoryManager.
   */
  public function __construct(
    protected Connection $database,
    protected TimeInterface $time,
    protected UserDataInterface $userData,
  ) {}

  /**
   * Checks whether a node is eligible for history recording.
   */
  public function isAllowedNode(NodeInterface $node): bool {
    return in_array($node->bundle(), self::ALLOWED_BUNDLES, TRUE) && $node->isPublished();
  }

  /**
   * Checks whether history recording is enabled for a user.
   */
  public function isEnabled(int $uid): bool {
    $value = $this->userData->get('xedc_member', $uid, self::ENABLED_KEY);
    return $value === NULL ? TRUE : (bool) $value;
  }

  /**
   * Enables or disables history recording for a user.
   */
  public function setEnabled(int $uid, bool $enabled): void {
    $this->userData->set('xedc_member', $uid, self::ENABLED_KEY, $enabled ? 1 : 0);
  }

  /**
   * Records a content view, updating the existing row when present.
   */
  public function record(int $uid, NodeInterface $node): bool {
    if ($uid <= 0 || !$this->isEnabled($uid) || !$this->isAllowedNode($node)) {
      return FALSE;
    }

    $now = $this->time->getRequestTime();
    $nid = (int) $node->id();

    $last_viewed = $this->database->select('xedc_member_history', 'h')
      ->fields('h', ['last_viewed'])
      ->condition('uid', $uid)
      ->condition('entity_type', 'node')
      ->condition('entity_id', $nid)
      ->execute()
      ->fetchField();
    if ($last_viewed !== FALSE && (int) $last_viewed > $now - self::WRITE_THROTTLE) {
      return FALSE;
    }

    try {
      $this->database->merge('xedc_member_history')
        ->insertFields([
          'bundle' => $node->bundle(),
          'first_viewed' => $now,
          'last_viewed' => $now,
          'view_count' => 1,
        ])
        ->keys([
          'uid' => $uid,
          'entity_type' => 'node',
          'entity_id' => $nid,
        ])
        ->updateFields([
          'bundle' => $node->bundle(),
          'last_viewed' => $now,
        ])
        ->expression('view_count', 'view_count + 1')
        ->execute();
    }
    catch (DatabaseException $e) {
      // A history write must never break the content page.
      \Drupal::logger('xedc_member')->warning('Unable to record browsing history: @message', [
        '@message' => $e->getMessage(),
      ]);
      return FALSE;
    }

    return TRUE;
  }

  /**
   * Counts visible history rows for a user.
   */
  public function countVisible(int $uid, ?string $bundle = NULL): int {
    $query = $this->baseQuery($uid, $bundle);
    return (int) $query->countQuery()->execute()->fetchField();
  }

  /**
   * Loads a paged list of visible history rows.
   *
   * @return object[]
   *   Rows with entity_id, bundle, first_viewed, last_viewed, view_count
   *   and title.
   */
  public function getHistoryRows(int $uid, ?string $bundle = NULL): array {
    $query = $this->baseQuery($uid, $bundle);
    $query->orderBy('h.last_viewed', 'DESC');
    $query = $query->extend(PagerSelectExtender::class);
    $query->element(self::PAGER_ELEMENT);
    $query->limit(self::PER_PAGE);
    return $query->execute()->fetchAll();
  }

  /**
   * Deletes one history row for a user.
   */
  public function delete(int $uid, int $nid): bool {
    $deleted = $this->database->delete('xedc_member_history')
      ->condition('uid', $uid)
      ->condition('entity_type', 'node')
      ->condition('entity_id', $nid)
      ->execute();
    return (bool) $deleted;
  }

  /**
   * Deletes all history rows for a user.
   */
  public function clear(int $uid): int {
    return (int) $this->database->delete('xedc_member_history')
      ->condition('uid', $uid)
      ->execute();
  }

  /**
   * Deletes history rows older than the retention period.
   */
  public function purgeExpired(int $days = self::RETENTION_DAYS): int {
    $threshold = $this->time->getRequestTime() - ($days * 86400);
    return (int) $this->database->delete('xedc_member_history')
      ->condition('last_viewed', $threshold, '<')
      ->execute();
  }

  /**
   * Deletes all history rows for a deleted entity.
   */
  public function deleteForEntity(string $entity_type, int $entity_id): void {
    $this->database->delete('xedc_member_history')
      ->condition('entity_type', $entity_type)
      ->condition('entity_id', $entity_id)
      ->execute();
  }

  /**
   * Deletes all history rows for a deleted user.
   */
  public function deleteForUser(int $uid): void {
    $this->database->delete('xedc_member_history')
      ->condition('uid', $uid)
      ->execute();
  }

  /**
   * Builds the base query for visible history rows.
   */
  protected function baseQuery(int $uid, ?string $bundle = NULL): SelectInterface {
    $query = $this->database->select('xedc_member_history', 'h');
    $query->join('node_field_data', 'n', 'n.nid = h.entity_id AND n.default_langcode = 1');
    $query->fields('h', ['entity_id', 'bundle', 'first_viewed', 'last_viewed', 'view_count']);
    $query->addField('n', 'title');
    $query->condition('h.uid', $uid);
    $query->condition('h.entity_type', 'node');
    $query->condition('h.bundle', self::ALLOWED_BUNDLES, 'IN');
    $query->condition('n.status', 1);
    if ($bundle !== NULL) {
      $query->condition('h.bundle', $bundle);
    }
    return $query;
  }

}
