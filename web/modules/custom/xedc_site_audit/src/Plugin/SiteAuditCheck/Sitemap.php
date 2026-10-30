<?php

namespace Drupal\xedc_site_audit\Plugin\SiteAuditCheck;

/**
 * Checks sitemap coverage and the robots Sitemap line.
 *
 * @SiteAuditCheck(
 *  id = "xedc_sitemap",
 *  name = @Translation("Sitemap completeness"),
 *  description = @Translation("Published content types and model terms should be in the XML sitemap."),
 *  checklist = "xedc_seo",
 *  weight = 3
 * )
 */
class Sitemap extends XedcCheckBase {

  /**
   * {@inheritdoc}
   */
  protected function checkId(): string {
    return 'sitemap';
  }

}
