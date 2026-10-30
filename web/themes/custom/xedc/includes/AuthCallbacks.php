<?php

namespace Drupal\xedc;

use Drupal\Core\Security\TrustedCallbackInterface;

/**
 * 把状态消息 / 错误消息渲染到登录、注册、找回密码卡片内部。
 */
class AuthCallbacks implements TrustedCallbackInterface {

  public static function trustedCallbacks(): array {
    return ['messages'];
  }

  public static function messages(array $form): array {
    $all = array_filter(\Drupal::messenger()->deleteAll());
    if ($all) {
      $form['xedc_messages'] = [
        '#theme' => 'status_messages',
        '#message_list' => $all,
        '#status_headings' => [
          'status' => t('状态消息'),
          'error' => t('错误消息'),
          'warning' => t('警告消息'),
        ],
        '#weight' => -900,
        '#cache' => ['max-age' => 0],
      ];
    }
    return $form;
  }

}
