<?php

namespace Drupal\xedc_member\Form;

use Drupal\Core\Ajax\AjaxResponse;
use Drupal\Core\Ajax\RemoveCommand;
use Drupal\Core\Form\FormBase;
use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Url;
use Drupal\xedc_member\Service\HistoryManager;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Deletes one browsing history row.
 */
class HistoryDeleteForm extends FormBase {

  /**
   * Constructs a HistoryDeleteForm.
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
    return 'xedc_member_history_delete';
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state, ?int $nid = NULL) {
    if ($nid === NULL || !$this->currentUser()->isAuthenticated()) {
      return [];
    }

    $wrapper = 'xedc-history-delete-' . $nid;
    $form['#attributes']['class'][] = 'xedc-history-delete-form';
    $form['#prefix'] = '<div id="' . $wrapper . '" class="xedc-history-delete-wrap">';
    $form['#suffix'] = '</div>';
    $form['nid'] = [
      '#type' => 'hidden',
      '#default_value' => $nid,
    ];
    $form['actions']['submit'] = [
      '#type' => 'submit',
      '#value' => $this->t('删除'),
      '#attributes' => [
        'class' => ['xedc-history-delete-btn'],
      ],
      '#ajax' => [
        'callback' => [static::class, 'ajaxDelete'],
        'wrapper' => $wrapper,
        'progress' => [
          'type' => 'throbber',
          'message' => NULL,
        ],
      ],
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
  public function validateForm(array &$form, FormStateInterface $form_state) {
    if (!$this->currentUser()->isAuthenticated() || (int) $form_state->getValue('nid') <= 0) {
      $form_state->setErrorByName('nid', $this->t('无法删除这条浏览历史。'));
    }
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state) {
    $account = $this->currentUser();
    $nid = (int) $form_state->getValue('nid');
    if (!$account->isAuthenticated() || (int) $account->id() <= 0 || $nid <= 0) {
      $this->messenger()->addError($this->t('无法删除这条浏览历史。'));
      return;
    }

    $this->historyManager->delete((int) $account->id(), $nid);

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
   * Ajax callback for deleting one history row.
   */
  public static function ajaxDelete(array &$form, FormStateInterface $form_state) {
    $response = new AjaxResponse();
    $nid = (int) $form_state->getValue('nid');
    $response->addCommand(new RemoveCommand('#xedc-member-history-' . $nid));

    return $response;
  }

}
