<?php

namespace Drupal\xedc_member\Form;

use Drupal\Core\Form\FormBase;
use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Url;
use Drupal\xedc_member\Service\HistoryManager;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Provides the browsing history recording preference form.
 */
class HistorySettingsForm extends FormBase {

  /**
   * Constructs a HistorySettingsForm.
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
    return 'xedc_member_history_settings';
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state) {
    $account = $this->currentUser();
    if (!$account->isAuthenticated()) {
      return [];
    }

    $form['#attributes']['class'][] = 'xm-history-form';
    $form['history_enabled'] = [
      '#type' => 'checkbox',
      '#title' => $this->t('记录我的浏览历史'),
      '#default_value' => $this->historyManager->isEnabled((int) $account->id()),
      '#description' => $this->t('关闭后不再记录新的浏览行为。已有历史会保留，你可以在浏览历史页面删除单条记录或清空全部历史。'),
    ];
    $form['actions']['submit'] = [
      '#type' => 'submit',
      '#value' => $this->t('保存设置'),
      '#button_type' => 'primary',
    ];
    $form['#cache'] = [
      'contexts' => ['user'],
      'max-age' => 0,
    ];

    return $form;
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state) {
    $account = $this->currentUser();
    if (!$account->isAuthenticated() || (int) $account->id() <= 0) {
      $this->messenger()->addError($this->t('请先登录后再修改设置。'));
      return;
    }

    $enabled = (bool) $form_state->getValue('history_enabled');
    $this->historyManager->setEnabled((int) $account->id(), $enabled);
    $this->messenger()->addStatus($enabled
      ? $this->t('浏览历史记录已开启。')
      : $this->t('浏览历史记录已关闭。已有记录会保留，你可以在浏览历史页面管理。'));
    $form_state->setRedirectUrl(Url::fromRoute('xedc_member.settings'));
  }

}
