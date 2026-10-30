<?php

namespace Drupal\xedc_site_audit\Plugin\SiteAuditChecklist;

use Drupal\site_audit\Plugin\SiteAuditChecklistBase;

/**
 * SEO checks for DcLili content.
 *
 * @SiteAuditChecklist(
 *  id = "xedc_seo",
 *  name = @Translation("DcLili SEO"),
 *  description = @Translation("Image alt, metadata, aliases, sitemap, cache and translation.")
 * )
 */
class Seo extends SiteAuditChecklistBase {}
