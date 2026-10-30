<?php

namespace Drupal\xedc_site_audit\Plugin\SiteAuditCheck;

/**
 * Checks anonymous page cache, aggregation and the homepage views.
 *
 * @SiteAuditCheck(
 *  id = "xedc_cache_performance",
 *  name = @Translation("Cache and performance"),
 *  description = @Translation("Anonymous pages, CSS/JS aggregation and homepage views should be cacheable."),
 *  checklist = "xedc_seo",
 *  weight = 4
 * )
 */
class CachePerformance extends XedcCheckBase {

  /**
   * {@inheritdoc}
   */
  protected function checkId(): string {
    return 'cache';
  }

}
