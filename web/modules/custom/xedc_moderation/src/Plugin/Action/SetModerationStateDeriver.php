<?php

declare(strict_types=1);

namespace Drupal\xedc_moderation\Plugin\Action;

use Drupal\Component\Plugin\Derivative\DeriverBase;
use Drupal\Core\StringTranslation\TranslatableMarkup;

/**
 * Provides one bulk action per moderation target state.
 */
final class SetModerationStateDeriver extends DeriverBase {

  /**
   * {@inheritdoc}
   */
  public function getDerivativeDefinitions($base_plugin_definition) {
    $states = [
      'published' => new TranslatableMarkup('改为已发布'),
      'rejected' => new TranslatableMarkup('改为已拒绝'),
      'draft' => new TranslatableMarkup('改为草稿'),
    ];
    foreach ($states as $state => $label) {
      $this->derivatives[$state] = $base_plugin_definition;
      $this->derivatives[$state]['label'] = $label;
      $this->derivatives[$state]['state'] = $state;
    }
    return $this->derivatives;
  }

}
