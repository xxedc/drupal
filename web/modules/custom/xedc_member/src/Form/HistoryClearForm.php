<?php

namespace Drupal\xedc_member\Form;

use Drupal\Core\Form\ConfirmFormBase;
use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Url;
use Drupal\xedc_member\Service\HistoryManager;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Confirms clearing all browsing history for the current member.
 */
class HistoryClearForm extends ConfirmFormBase {

  /**
   * Constructs a HistoryClearForm.
   */
  public function __construct(
    protected HistoryManager $historyManager,
  ) {}

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container) {
    return new static(
      $container->get('xedc_member.history_manager')
    );
  }

  /**
   * {@inheritdoc}
   */
  public function getFormId() {
    return 'xedc_member_history_clear';
  }

  /**
   * {@inheritdoc}
   */
  public function getQuestion() {
    return $this->t('确定清空全部浏览历史吗？');
  }

  /**
   * {@inheritdoc}
   */
  public function getDescription() {
    return $this->t('此操作只清空当前账号的浏览历史，无法恢复。');
  }

  /**
   * {@inheritdoc}
   */
  public function getCancelUrl() {
    return Url::fromRoute('xedc_member.history');
  }

  /**
   * {@inheritdoc}
   */
  public function getConfirmText() {
    return $this->t('清空历史');
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state) {
    $form = parent::buildForm($form, $form_state);
    $form['#attributes']['class'][] = 'xm-confirm-form';
    $form['#attached']['library'][] = 'xedc_member/member';
    $form['actions']['submit']['#attributes']['class'][] = 'xm-btn--danger';
    return $form;
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state) {
    $account = $this->currentUser();
    if (!$account->isAuthenticated() || (int) $account->id() <= 0) {
      $this->messenger()->addError($this->t('请先登录后再操作。'));
      return;
    }

    $count = $this->historyManager->clear((int) $account->id());
    $this->messenger()->addStatus($this->t('已清空 @count 条浏览历史。', ['@count' => $count]));
    $form_state->setRedirectUrl(Url::fromRoute('xedc_member.history'));
  }

}
