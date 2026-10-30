<?php

namespace Drupal\xedc_site_audit\Plugin\SiteAuditCheck;

/**
 * Checks Pathauto patterns and published nodes without an alias.
 *
 * @SiteAuditCheck(
 *  id = "xedc_url_alias",
 *  name = @Translation("URL aliases"),
 *  description = @Translation("Public content types need Pathauto patterns. Model pages keep their custom route."),
 *  checklist = "xedc_seo",
 *  weight = 2
 * )
 */
class UrlAlias extends XedcCheckBase {

  /**
   * {@inheritdoc}
   */
  protected function checkId(): string {
    return 'url_alias';
  }

}
