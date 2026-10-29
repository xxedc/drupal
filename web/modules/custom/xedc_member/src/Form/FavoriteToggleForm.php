<?php

namespace Drupal\xedc_member\Form;

use Drupal\Core\Ajax\AjaxResponse;
use Drupal\Core\Ajax\RemoveCommand;
use Drupal\Core\Ajax\ReplaceCommand;
use Drupal\Core\Form\FormBase;
use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Url;
use Drupal\node\Entity\Node;
use Drupal\node\NodeInterface;
use Drupal\xedc_member\Service\FavoriteManager;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Provides a favorite/unfavorite button.
 */
class FavoriteToggleForm extends FormBase {

  /**
   * Constructs a FavoriteToggleForm.
   */
  public function __construct(
    protected FavoriteManager $favoriteManager,
  ) {}

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container) {
    return new static(
      $container->get('xedc_member.favorite_manager')
    );
  }

  /**
   * {@inheritdoc}
   */
  public function getFormId() {
    return 'xedc_member_favorite_toggle';
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state, ?int $nid = NULL, string $context = 'detail') {
    if ($nid === NULL) {
      return [];
    }

    $node = Node::load($nid);
    if (!$node instanceof NodeInterface || !$this->favoriteManager->isAllowedNode($node) || !$node->access('view')) {
      return [];
    }

    $account = $this->currentUser();
    if (!$account->isAuthenticated()) {
      return [];
    }

    $context = $context === 'list' ? 'list' : 'detail';
    $uid = (int) $account->id();
    $is_favorite = $this->favoriteManager->isFavorited($uid, $nid);
    $wrapper = 'xedc-favorite-' . $context . '-' . $nid;

    $form['#attributes']['class'][] = 'xedc-favorite-form';
    $form['#prefix'] = '<div id="' . $wrapper . '" class="xedc-favorite-wrap">';
    $form['#suffix'] = '</div>';
    $form['nid'] = [
      '#type' => 'hidden',
      '#default_value' => $nid,
    ];
    $form['context'] = [
      '#type' => 'hidden',
      '#default_value' => $context,
    ];
    $form['actions']['submit'] = [
      '#type' => 'submit',
      '#value' => $is_favorite ? $this->t('取消收藏') : $this->t('收藏'),
      '#button_type' => $is_favorite ? 'secondary' : 'primary',
      '#attributes' => [
        'class' => [
          'xedc-favorite-btn',
          $is_favorite ? 'is-favorite' : 'is-not-favorite',
        ],
      ],
      '#ajax' => [
        'callback' => [static::class, 'ajaxToggle'],
        'wrapper' => $wrapper,
        'progress' => [
          'type' => 'throbber',
          'message' => NULL,
        ],
      ],
    ];
    $form['#cache'] = [
      'contexts' => ['user'],
      'tags' => ['node:' . $nid],
      'max-age' => 0,
    ];

    return $form;
  }

  /**
   * {@inheritdoc}
   */
  public function validateForm(array &$form, FormStateInterface $form_state) {
    if (!$this->currentUser()->isAuthenticated()) {
      $form_state->setErrorByName('nid', $this->t('请先登录后再收藏。'));
      return;
    }
    $nid = (int) $form_state->getValue('nid');
    $node = Node::load($nid);
    if (!$node instanceof NodeInterface || !$this->favoriteManager->isAllowedNode($node) || !$node->access('view')) {
      $form_state->setErrorByName('nid', $this->t('内容不可用，无法收藏。'));
    }
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state) {
    $nid = (int) $form_state->getValue('nid');
    $context = (string) $form_state->getValue('context') === 'list' ? 'list' : 'detail';
    $node = Node::load($nid);
    $uid = (int) $this->currentUser()->id();

    if (!$this->currentUser()->isAuthenticated() || $uid <= 0) {
      $this->messenger()->addError($this->t('请先登录后再收藏。'));
      $form_state->setRebuild(TRUE);
      return;
    }

    if (!$node instanceof NodeInterface || !$this->favoriteManager->isAllowedNode($node) || !$node->access('view')) {
      $this->messenger()->addError($this->t('内容不可用，无法收藏。'));
      $form_state->setRebuild(TRUE);
      return;
    }

    $was_favorite = $this->favoriteManager->isFavorited($uid, $nid);
    if ($was_favorite) {
      $this->favoriteManager->remove($uid, $nid);
    }
    else {
      $this->favoriteManager->add($uid, $node);
    }

    $form_state->set('xedc_favorite_context', $context);
    $form_state->set('xedc_favorite_list_removed', $context === 'list' && $was_favorite);

    if ($this->getRequest()->isXmlHttpRequest()) {
      $form_state->setRebuild(TRUE);
    }
    else {
      $form_state->setRedirectUrl(Url::fromRoute('<current>', [], [
        'query' => $this->getRequest()->query->all(),
      ]));
    }
  }

  /**
   * Ajax callback for the favorite button.
   */
  public static function ajaxToggle(array &$form, FormStateInterface $form_state) {
    $response = new AjaxResponse();
    $context = $form_state->get('xedc_favorite_context') ?: 'detail';
    $nid = (int) $form_state->getValue('nid');

    if ($context === 'list' && $form_state->get('xedc_favorite_list_removed')) {
      $response->addCommand(new RemoveCommand('#xedc-member-fav-' . $nid));
    }
    else {
      $response->addCommand(new ReplaceCommand('#xedc-favorite-' . $context . '-' . $nid, $form));
    }

    return $response;
  }

}
