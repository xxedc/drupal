<?php

namespace Drupal\xedc_site_audit\Plugin\SiteAuditCheck;

/**
 * Checks title and description defaults for public content.
 *
 * @SiteAuditCheck(
 *  id = "xedc_meta",
 *  name = @Translation("Title and meta description"),
 *  description = @Translation("Front page, photo, article, video, page and model routes need a title and description."),
 *  checklist = "xedc_seo",
 *  weight = 1
 * )
 */
class MetaTags extends XedcCheckBase {

  /**
   * {@inheritdoc}
   */
  protected function checkId(): string {
    return 'meta';
  }

}
