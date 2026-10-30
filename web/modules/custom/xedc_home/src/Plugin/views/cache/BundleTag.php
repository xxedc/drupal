<?php

namespace Drupal\xedc_home\Plugin\views\cache;

use Drupal\Core\Cache\Cache;
use Drupal\Core\StringTranslation\TranslatableMarkup;
use Drupal\views\Attribute\ViewsCache;
use Drupal\views\Plugin\views\cache\Tag;

/**
 * Tag cache that invalidates on the content type shown by the view.
 */
#[ViewsCache(
  id: 'xedc_bundle_tag',
  title: new TranslatableMarkup('Bundle list tag'),
  help: new TranslatableMarkup('Invalidates when the displayed content type changes, not when any node is saved.'),
)]
class BundleTag extends Tag {

  /**
   * {@inheritdoc}
   */
  public function getCacheTags() {
    $tags = parent::getCacheTags();
    $bundle_tag = $this->bundleTag();
    if ($bundle_tag === NULL) {
      return $tags;
    }
    $tags = array_values(array_filter($tags, static fn($tag) => $tag !== 'node_list'));
    return Cache::mergeTags($tags, [$bundle_tag]);
  }

  /**
   * List cache tag for this view display.
   */
  protected function bundleTag(): ?string {
    $view_id = $this->view->id();
    $display = $this->view->current_display;
    if ($view_id === 'xedc_home') {
      return match ($display) {
        'block_articles' => 'node_list:article',
        'block_photos' => 'node_list:photo',
        'block_videos' => 'node_list:video',
        default => NULL,
      };
    }
    return match ($view_id) {
      'image_gallery' => 'node_list:photo',
      'article_list' => 'node_list:article',
      'video_list', 'taxonomy_term' => 'node_list:video',
      default => NULL,
    };
  }

}
