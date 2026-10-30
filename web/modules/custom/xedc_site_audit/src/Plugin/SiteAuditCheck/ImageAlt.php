<?php

namespace Drupal\xedc_site_audit\Plugin\SiteAuditCheck;

/**
 * Checks media image alt configuration and existing values.
 *
 * @SiteAuditCheck(
 *  id = "xedc_image_alt",
 *  name = @Translation("Image alt text"),
 *  description = @Translation("Media images used by photos should have an editable alt field."),
 *  checklist = "xedc_seo",
 *  weight = 0
 * )
 */
class ImageAlt extends XedcCheckBase {

  /**
   * {@inheritdoc}
   */
  protected function checkId(): string {
    return 'image_alt';
  }

}
