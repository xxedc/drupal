<?php

namespace Drupal\xedc_member;

use Drupal\Core\Form\FormBuilderInterface;
use Drupal\Core\Security\TrustedCallbackInterface;
use Drupal\Core\Session\AccountProxyInterface;
use Drupal\Core\StringTranslation\StringTranslationTrait;
use Drupal\Core\Url;
use Drupal\xedc_member\Form\FavoriteToggleForm;

/**
 * User-specific header and favorite markup, isolated from the page cache.
 */
class MemberLazyBuilders implements TrustedCallbackInterface {

  use StringTranslationTrait;

  public function __construct(
    protected AccountProxyInterface $currentUser,
    protected FormBuilderInterface $formBuilder,
  ) {}

  /**
   * {@inheritdoc}
   */
  public static function trustedCallbacks() {
    return ['accountIcon', 'accountSheet', 'favorite'];
  }

  /**
   * Header account icon for the current user.
   */
  public function accountIcon(): array {
    return $this->accountLink('icon');
  }

  /**
   * Member-center button in the mobile sheet.
   */
  public function accountSheet(): array {
    return $this->accountLink('sheet');
  }

  /**
   * Favorite control for a published photo, video or article.
   */
  public function favorite(string $nid): array {
    $nid = (int) $nid;
    if ($this->currentUser->isAuthenticated()) {
      $form = $this->formBuilder->getForm(FavoriteToggleForm::class, $nid, 'detail');
      $form['#attached']['library'][] = 'xedc_member/member';
      return $form;
    }
    return [
      '#type' => 'link',
      '#title' => $this->t('登录后收藏'),
      '#url' => Url::fromRoute('user.login', [], [
        'query' => ['destination' => \Drupal::request()->getRequestUri()],
      ]),
      '#attributes' => ['class' => ['xedc-favorite-login']],
      '#attached' => ['library' => ['xedc_member/member']],
      '#cache' => [
        'contexts' => ['user.roles:authenticated', 'url'],
        'tags' => ['node:' . $nid],
      ],
    ];
  }

  /**
   * Renders one account link without putting the user context on the page.
   */
  protected function accountLink(string $variant): array {
    $uid = (int) $this->currentUser->id();
    if ($uid < 1) {
      return [
        '#cache' => ['contexts' => ['user.roles:authenticated']],
      ];
    }
    $generated = Url::fromRoute('xedc_member.overview')->toString(TRUE);
    $avatar = $variant === 'icon' ? xedc_member_avatar_url($uid) : '';
    $template = $variant === 'icon'
      ? '<a class="xn-icon xn-account" href="{{ url }}" aria-label="{{ label }}">{% if avatar %}<img class="xn-avatar" src="{{ avatar }}" alt="" width="32" height="32">{% else %}<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>{% endif %}</a>'
      : '<a class="xn-btn xn-btn-ghost" href="{{ url }}">{{ label }}</a>';
    return [
      '#type' => 'inline_template',
      '#template' => $template,
      '#context' => [
        'url' => $generated->getGeneratedUrl(),
        'label' => $this->t('会员中心'),
        'avatar' => $avatar,
      ],
      '#cache' => [
        'contexts' => array_merge(['user'], $generated->getCacheContexts()),
        'tags' => array_merge(['user:' . $uid, 'xedc_member:aliases'], $generated->getCacheTags()),
      ],
    ];
  }

}
