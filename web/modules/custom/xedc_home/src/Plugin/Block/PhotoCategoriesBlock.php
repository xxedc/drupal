<?php

namespace Drupal\xedc_home\Plugin\Block;

use Drupal\Core\Block\Attribute\Block;
use Drupal\Core\Block\BlockBase;
use Drupal\Core\Cache\Cache;
use Drupal\Core\Plugin\ContainerFactoryPluginInterface;
use Drupal\Core\StringTranslation\TranslatableMarkup;
use Drupal\xedc_home\HomeCards;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Three photo categories with up to three photos each.
 */
#[Block(
  id: 'xedc_home_photo_categories',
  admin_label: new TranslatableMarkup('图片分类栏目'),
  category: new TranslatableMarkup('XEDC'),
)]
class PhotoCategoriesBlock extends BlockBase implements ContainerFactoryPluginInterface {

  public function __construct(
    array $configuration,
    $plugin_id,
    $plugin_definition,
    protected HomeCards $cards,
  ) {
    parent::__construct($configuration, $plugin_id, $plugin_definition);
  }

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container, array $configuration, $plugin_id, $plugin_definition): static {
    return new static(
      $configuration,
      $plugin_id,
      $plugin_definition,
      $container->get('xedc_home.cards'),
    );
  }

  /**
   * {@inheritdoc}
   */
  public function build(): array {
    $categories = $this->cards->categories();
    if (!$categories) {
      return [];
    }
    return [
      '#theme' => 'xedc_home_categories',
      '#categories' => $categories,
      '#cache' => [
        'tags' => $this->getCacheTags(),
        'contexts' => $this->getCacheContexts(),
        'max-age' => $this->getCacheMaxAge(),
      ],
    ];
  }

  /**
   * {@inheritdoc}
   */
  public function getCacheTags(): array {
    return Cache::mergeTags(parent::getCacheTags(), ['node_list', 'taxonomy_term_list']);
  }

  /**
   * {@inheritdoc}
   */
  public function getCacheContexts(): array {
    return Cache::mergeContexts(parent::getCacheContexts(), [
      'user.permissions',
      'languages:language_interface',
    ]);
  }

  /**
   * {@inheritdoc}
   */
  public function getCacheMaxAge(): int {
    return 3600;
  }

}
