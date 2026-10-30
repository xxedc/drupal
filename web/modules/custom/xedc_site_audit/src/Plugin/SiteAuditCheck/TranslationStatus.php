<?php

namespace Drupal\xedc_site_audit\Plugin\SiteAuditCheck;

/**
 * Reports translation coverage for published nodes and category terms.
 *
 * @SiteAuditCheck(
 *  id = "xedc_translation",
 *  name = @Translation("Content translation status"),
 *  description = @Translation("Shows how much published content exists in each non-default language."),
 *  checklist = "xedc_seo",
 *  weight = 5
 * )
 */
class TranslationStatus extends XedcCheckBase {

  /**
   * {@inheritdoc}
   */
  protected function checkId(): string {
    return 'translation';
  }

}
