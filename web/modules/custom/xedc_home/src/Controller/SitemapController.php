<?php

namespace Drupal\xedc_home\Controller;

use Drupal\Core\Controller\ControllerBase;

/**
 * HTML sitemap at /sitemap.
 */
class SitemapController extends ControllerBase {

  /**
   * Builds the HTML sitemap.
   */
  public function page(): array {
    $href = static function (string $path): string {
      return $path === '/'
        ? \Drupal\Core\Url::fromRoute('<front>')->toString()
        : \Drupal\Core\Url::fromUserInput($path)->toString();
    };
    $sections = [
      [
        'title' => $this->t('浏览'),
        'links' => [
          ['title' => $this->t('首页'), 'url' => $href('/')],
          ['title' => $this->t('美图'), 'url' => $href('/meitu')],
          ['title' => $this->t('文章'), 'url' => $href('/articles')],
          ['title' => $this->t('视频'), 'url' => $href('/video')],
          ['title' => $this->t('模特'), 'url' => $href('/models')],
          ['title' => $this->t('标签'), 'url' => $href('/tags')],
        ],
      ],
    ];
    $vocabularies = [
      'photo_category' => $this->t('美图栏目'),
      'article_category' => $this->t('文章栏目'),
      'video_category' => $this->t('视频栏目'),
    ];
    $storage = $this->entityTypeManager()->getStorage('taxonomy_term');
    $repository = \Drupal::service('entity.repository');
    $tags = [];
    $vocabularies_loaded = $this->entityTypeManager()->getStorage('taxonomy_vocabulary')->loadMultiple(array_keys($vocabularies));
    foreach ($vocabularies as $vid => $title) {
      $tags[] = 'taxonomy_term_list:' . $vid;
      if (!isset($vocabularies_loaded[$vid])) {
        continue;
      }
      $terms = $storage->loadTree($vid, 0, NULL, TRUE);
      $links = [];
      foreach ($terms as $term) {
        if (!$term->access('view')) {
          continue;
        }
        $translated = $repository->getTranslationFromContext($term);
        $links[] = [
          'title' => $translated->label(),
          'url' => $translated->toUrl()->toString(),
        ];
        $tags = \Drupal\Core\Cache\Cache::mergeTags($tags, $term->getCacheTags());
      }
      if ($links) {
        $sections[] = ['title' => $title, 'links' => $links];
      }
    }
    $sections[] = [
      'title' => $this->t('模特'),
      'links' => [
        ['title' => $this->t('全部模特'), 'url' => $href('/models')],
      ],
    ];
    $tags[] = 'taxonomy_term_list:models';
    $sections[] = [
      'title' => $this->t('关于 DcLili'),
      'links' => [
        ['title' => $this->t('关于我们'), 'url' => $href('/about')],
        ['title' => $this->t('隐私政策'), 'url' => $href('/privacy-policy')],
        ['title' => $this->t('用户协议'), 'url' => $href('/terms')],
        ['title' => $this->t('站点地图'), 'url' => $href('/sitemap')],
      ],
    ];
    return [
      '#theme' => 'xedc_html_sitemap',
      '#sections' => $sections,
      '#cache' => [
        'tags' => $tags,
        'contexts' => ['user.permissions', 'languages:language_interface', 'languages:language_content'],
      ],
      '#attached' => ['library' => ['xedc/html-sitemap']],
    ];
  }

}
