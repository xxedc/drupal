<?php

namespace Drupal\xedc_member\Form;

use Drupal\Core\Form\FormBase;
use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Url;
use Drupal\file\Entity\File;
use Drupal\file\FileInterface;
use Drupal\user\Entity\User;

/**
 * Edits the member's nickname, bio and avatar.
 */
class ProfileForm extends FormBase {

  /**
   * {@inheritdoc}
   */
  public function getFormId() {
    return 'xedc_member_profile_form';
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state) {
    $account = $this->loadAccount();
    if (!$account) {
      return [];
    }

    $nickname = '';
    if ($account->hasField('field_xedc_nickname') && !$account->get('field_xedc_nickname')->isEmpty()) {
      $nickname = $account->get('field_xedc_nickname')->value;
    }
    $bio = '';
    if ($account->hasField('field_xedc_bio') && !$account->get('field_xedc_bio')->isEmpty()) {
      $bio = $account->get('field_xedc_bio')->value;
    }
    $picture_fid = NULL;
    if (!$account->get('user_picture')->isEmpty()) {
      $picture_fid = (int) $account->get('user_picture')->target_id;
    }

    $form['#attributes']['class'][] = 'xm-profile-form';
    $form['nickname'] = [
      '#type' => 'textfield',
      '#title' => $this->t('昵称'),
      '#default_value' => $nickname,
      '#maxlength' => 64,
      '#description' => $this->t('显示在会员中心。留空时使用用户名。最多 64 个字符。'),
    ];
    $form['bio'] = [
      '#type' => 'textarea',
      '#title' => $this->t('个人简介'),
      '#default_value' => $bio,
      '#rows' => 5,
      '#maxlength' => 500,
      '#description' => $this->t('最多 500 个字符，保存时会移除 HTML 标签。'),
    ];
    $form['picture'] = [
      '#type' => 'managed_file',
      '#title' => $this->t('头像'),
      '#upload_location' => 'public://pictures/',
      '#default_value' => $picture_fid ? [$picture_fid] : [],
      '#accept' => 'image/*',
      '#upload_validators' => [
        'FileExtension' => ['extensions' => 'png gif jpg jpeg webp'],
        'FileSizeLimit' => ['fileLimit' => 2 * 1024 * 1024],
        'FileIsImage' => [],
      ],
      '#description' => $this->t('支持 JPG、PNG、GIF、WebP，最大 2MB。'),
    ];
    $form['actions']['submit'] = [
      '#type' => 'submit',
      '#value' => $this->t('保存个人资料'),
      '#button_type' => 'primary',
    ];
    $form['actions']['cancel'] = [
      '#type' => 'link',
      '#title' => $this->t('返回会员中心'),
      '#url' => Url::fromRoute('xedc_member.overview'),
      '#attributes' => ['class' => ['xm-btn']],
    ];
    $form['actions']['#prefix'] = '<div class="xm-form-actions">';
    $form['actions']['#suffix'] = '</div>';
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
    $account = $this->loadAccount();
    if (!$account) {
      $form_state->setErrorByName('nickname', $this->t('请先登录后再修改资料。'));
      return;
    }
    if (!$account->hasField('field_xedc_nickname') || !$account->hasField('field_xedc_bio')) {
      $form_state->setErrorByName('nickname', $this->t('个人资料字段尚未配置，请先运行数据库更新。'));
      return;
    }

    $nickname = trim(strip_tags((string) $form_state->getValue('nickname')));
    if (mb_strlen($nickname) > 64) {
      $form_state->setErrorByName('nickname', $this->t('昵称不能超过 64 个字符。'));
    }

    $bio = trim(strip_tags((string) $form_state->getValue('bio')));
    if (mb_strlen($bio) > 500) {
      $form_state->setErrorByName('bio', $this->t('个人简介不能超过 500 个字符。'));
    }

    $fid = $this->getPictureFid($form_state);
    if ($fid > 0 && !(File::load($fid) instanceof FileInterface)) {
      $form_state->setErrorByName('picture', $this->t('头像文件无效，请重新上传。'));
    }
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state) {
    $account = $this->loadAccount();
    if (!$account) {
      $this->messenger()->addError($this->t('请先登录后再修改资料。'));
      return;
    }

    $old_picture_fid = (int) ($account->get('user_picture')->target_id ?? 0);
    $nickname = trim(strip_tags((string) $form_state->getValue('nickname')));
    $bio = trim(strip_tags((string) $form_state->getValue('bio')));
    $account->set('field_xedc_nickname', $nickname);
    $account->set('field_xedc_bio', $bio);

    $fid = $this->getPictureFid($form_state);
    if ($fid > 0) {
      $file = File::load($fid);
      if ($file instanceof FileInterface) {
        if (!$file->isPermanent()) {
          $file->setPermanent();
          $file->save();
        }
        $account->set('user_picture', ['target_id' => $fid]);
      }
    }
    else {
      $account->set('user_picture', []);
    }

    $account->save();

    if ($old_picture_fid > 0 && $old_picture_fid !== $fid) {
      $old_file = File::load($old_picture_fid);
      if ($old_file instanceof FileInterface && empty(\Drupal::service('file.usage')->listUsage($old_file))) {
        $old_file->delete();
      }
    }

    $this->messenger()->addStatus($this->t('个人资料已更新。'));
    $form_state->setRedirectUrl(Url::fromRoute('xedc_member.profile'));
  }

  /**
   * Extracts the uploaded/current picture file ID.
   */
  protected function getPictureFid(FormStateInterface $form_state): int {
    $value = $form_state->getValue('picture');
    if (is_array($value)) {
      $value = reset($value);
    }
    return (int) $value;
  }

  /**
   * Loads the current user entity.
   */
  protected function loadAccount() {
    $uid = (int) $this->currentUser()->id();
    return $uid > 0 ? User::load($uid) : NULL;
  }

}
