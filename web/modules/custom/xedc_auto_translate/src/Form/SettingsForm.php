<?php

declare(strict_types=1);

namespace Drupal\xedc_auto_translate\Form;

use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\Core\Config\TypedConfigManagerInterface;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Form\ConfigFormBase;
use Drupal\Core\Form\FormStateInterface;
use Drupal\xedc_auto_translate\Translator;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Settings for Microsoft Translator or DeepL, plus a manual translate action.
 */
final class SettingsForm extends ConfigFormBase {

  public function __construct(
    ConfigFactoryInterface $config_factory,
    TypedConfigManagerInterface $typed_config_manager,
    private readonly Translator $translator,
    private readonly EntityTypeManagerInterface $entityTypeManager,
  ) {
    parent::__construct($config_factory, $typed_config_manager);
  }

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container): static {
    return new static(
      $container->get('config.factory'),
      $container->get('config.typed'),
      $container->get('xedc_auto_translate.translator'),
      $container->get('entity_type.manager'),
    );
  }

  /**
   * {@inheritdoc}
   */
  public function getFormId(): string {
    return 'xedc_auto_translate_settings';
  }

  /**
   * {@inheritdoc}
   */
  protected function getEditableConfigNames(): array {
    return ['xedc_auto_translate.settings'];
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state): array {
    $config = $this->config('xedc_auto_translate.settings');
    $provider = $config->get('provider') === 'deepl' ? 'deepl' : 'microsoft';
    $form['enabled'] = [
      '#type' => 'checkbox',
      '#title' => $this->t('启用自动翻译'),
      '#default_value' => $config->get('enabled'),
      '#description' => $this->t('简体中文内容第一次变为已发布时，自动翻译成英语、俄语和日语。已有译文默认不覆盖。'),
    ];
    $form['provider'] = [
      '#type' => 'radios',
      '#title' => $this->t('翻译提供商'),
      '#options' => [
        'microsoft' => $this->t('Microsoft Translator'),
        'deepl' => $this->t('DeepL'),
      ],
      '#default_value' => $provider,
      '#required' => TRUE,
    ];

    $form['microsoft'] = [
      '#type' => 'container',
      '#states' => [
        'visible' => [
          ':input[name="provider"]' => ['value' => 'microsoft'],
        ],
      ],
    ];
    $form['microsoft']['microsoft_api_key'] = [
      '#type' => 'password',
      '#title' => $this->t('Microsoft Translator API Key'),
      '#description' => $this->t('在 Azure 创建 Translator 资源（免费层 F0）后，从「密钥和终结点」复制 Key 1。密钥只保存在 State，不会写入 config/sync。留空表示不修改已保存的密钥。当前：@status。也可以设置环境变量 MICROSOFT_TRANSLATOR_API_KEY。', [
        '@status' => $this->translator->hasStoredApiKey('microsoft') ? $this->t('已设置') : $this->t('未设置'),
      ]),
    ];
    $form['microsoft']['microsoft_region'] = [
      '#type' => 'textfield',
      '#title' => $this->t('Microsoft 区域'),
      '#default_value' => $config->get('microsoft_region') ?: 'global',
      '#required' => FALSE,
      '#description' => $this->t('与资源所在位置一致。全球资源填 global，东亚填 eastasia。也可以设置环境变量 MICROSOFT_TRANSLATOR_REGION。'),
    ];
    $form['microsoft']['microsoft_endpoint'] = [
      '#type' => 'textfield',
      '#title' => $this->t('Microsoft 终结点'),
      '#default_value' => (string) $config->get('microsoft_endpoint'),
      '#description' => $this->t('留空使用 https://api.cognitive.microsofttranslator.com 。中国区可填 https://api.translator.azure.cn ，或填写资源自己的 cognitiveservices.azure.com 地址。'),
    ];
    $form['microsoft']['clear_microsoft_key'] = [
      '#type' => 'checkbox',
      '#title' => $this->t('清除已保存的 Microsoft API Key'),
    ];

    $deepl_endpoint = (string) $config->get('deepl_endpoint');
    $form['deepl'] = [
      '#type' => 'container',
      '#states' => [
        'visible' => [
          ':input[name="provider"]' => ['value' => 'deepl'],
        ],
      ],
    ];
    $form['deepl']['deepl_api_key'] = [
      '#type' => 'password',
      '#title' => $this->t('DeepL API Key'),
      '#description' => $this->t('在 DeepL 账户中创建 API Key。免费额度的 Key 以 :fx 结尾。密钥只保存在 State，不会写入 config/sync。留空表示不修改已保存的密钥。当前：@status。也可以设置环境变量 DEEPL_API_KEY。', [
        '@status' => $this->translator->hasStoredApiKey('deepl') ? $this->t('已设置') : $this->t('未设置'),
      ]),
    ];
    $form['deepl']['deepl_endpoint'] = [
      '#type' => 'radios',
      '#title' => $this->t('DeepL 接口'),
      '#options' => [
        'auto' => $this->t('自动（Key 以 :fx 结尾时走免费接口）'),
        'free' => $this->t('免费接口 api-free.deepl.com'),
        'pro' => $this->t('专业接口 api.deepl.com'),
      ],
      '#default_value' => in_array($deepl_endpoint, ['auto', 'free', 'pro'], TRUE) ? $deepl_endpoint : 'auto',
    ];
    $form['deepl']['clear_deepl_key'] = [
      '#type' => 'checkbox',
      '#title' => $this->t('清除已保存的 DeepL API Key'),
    ];

    $form['overwrite'] = [
      '#type' => 'checkbox',
      '#title' => $this->t('覆盖已有译文'),
      '#default_value' => $config->get('overwrite'),
      '#description' => $this->t('默认关闭。关闭时，已经存在的译文不会在再次发布时被机器翻译覆盖。'),
    ];
    $form['save_as'] = [
      '#type' => 'radios',
      '#title' => $this->t('译文保存状态'),
      '#options' => [
        'published' => $this->t('直接发布'),
        'draft' => $this->t('保存为草稿'),
      ],
      '#default_value' => $config->get('save_as') === 'draft' ? 'draft' : 'published',
      '#description' => $this->t('对使用审核流程的 photo、article、video 生效。分类术语没有草稿状态，会直接保存译文。'),
    ];
    $form['manual'] = [
      '#type' => 'details',
      '#title' => $this->t('手动翻译一条已有内容'),
      '#open' => FALSE,
      '#tree' => TRUE,
    ];
    $form['manual']['entity_type'] = [
      '#type' => 'textfield',
      '#title' => $this->t('实体类型'),
      '#default_value' => 'node',
      '#description' => $this->t('例如 node、taxonomy_term、menu_link_content。'),
    ];
    $form['manual']['entity_id'] = [
      '#type' => 'number',
      '#title' => $this->t('实体 ID'),
      '#min' => 1,
    ];
    $form['manual']['force'] = [
      '#type' => 'checkbox',
      '#title' => $this->t('这次覆盖已有译文'),
    ];
    $form['manual']['translate'] = [
      '#type' => 'submit',
      '#value' => $this->t('立即翻译'),
      '#submit' => ['::translateOne'],
      '#limit_validation_errors' => [
        ['manual'],
      ],
    ];
    return parent::buildForm($form, $form_state);
  }

  /**
   * {@inheritdoc}
   */
  public function validateForm(array &$form, FormStateInterface $form_state): void {
    $provider = $form_state->getValue('provider') === 'deepl' ? 'deepl' : 'microsoft';
    if ($provider === 'microsoft') {
      $region = strtolower(trim((string) $form_state->getValue('microsoft_region')));
      if ($region === '' || !preg_match('/^[a-z0-9]+$/', $region)) {
        $form_state->setErrorByName('microsoft_region', $this->t('请填写 Microsoft 区域，例如 global 或 eastasia。'));
      }
      $endpoint = trim((string) $form_state->getValue('microsoft_endpoint'));
      if ($endpoint !== '' && !$this->translator->isAllowedMicrosoftEndpoint($endpoint)) {
        $form_state->setErrorByName('microsoft_endpoint', $this->t('Microsoft 终结点必须是 Azure Translator 的 HTTPS 地址。'));
      }
    }
    parent::validateForm($form, $form_state);
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state): void {
    $provider = $form_state->getValue('provider') === 'deepl' ? 'deepl' : 'microsoft';
    $deepl_endpoint = (string) $form_state->getValue('deepl_endpoint');
    $region = strtolower(trim((string) $form_state->getValue('microsoft_region')));
    $this->config('xedc_auto_translate.settings')
      ->set('enabled', (bool) $form_state->getValue('enabled'))
      ->set('provider', $provider)
      ->set('microsoft_region', $region !== '' ? $region : 'global')
      ->set('microsoft_endpoint', trim((string) $form_state->getValue('microsoft_endpoint')))
      ->set('deepl_endpoint', in_array($deepl_endpoint, ['auto', 'free', 'pro'], TRUE) ? $deepl_endpoint : 'auto')
      ->set('overwrite', (bool) $form_state->getValue('overwrite'))
      ->set('save_as', $form_state->getValue('save_as') === 'draft' ? 'draft' : 'published')
      ->save();
    if ($form_state->getValue('clear_microsoft_key')) {
      $this->translator->setApiKey('', 'microsoft');
    }
    elseif (trim((string) $form_state->getValue('microsoft_api_key')) !== '') {
      $this->translator->setApiKey((string) $form_state->getValue('microsoft_api_key'), 'microsoft');
    }
    if ($form_state->getValue('clear_deepl_key')) {
      $this->translator->setApiKey('', 'deepl');
    }
    elseif (trim((string) $form_state->getValue('deepl_api_key')) !== '') {
      $this->translator->setApiKey((string) $form_state->getValue('deepl_api_key'), 'deepl');
    }
    parent::submitForm($form, $form_state);
  }

  /**
   * Translates a single existing entity.
   */
  public function translateOne(array &$form, FormStateInterface $form_state): void {
    $manual = $form_state->getValue('manual') ?? [];
    $entity_type = trim((string) ($manual['entity_type'] ?? ''));
    $entity_id = (int) ($manual['entity_id'] ?? 0);
    if ($entity_type === '' || $entity_id < 1 || !$this->entityTypeManager->hasDefinition($entity_type)) {
      $this->messenger()->addError($this->t('请填写有效的实体类型和 ID。'));
      return;
    }
    $entity = $this->entityTypeManager->getStorage($entity_type)->load($entity_id);
    if (!$entity) {
      $this->messenger()->addError($this->t('找不到该内容。'));
      return;
    }
    $results = $this->translator->translateEntity($entity, (bool) ($manual['force'] ?? FALSE));
    if (!$results) {
      $this->messenger()->addWarning($this->t('没有生成译文。请确认内容是已发布的简体中文，并且当前提供商的 API Key 已填写。'));
      return;
    }
    $this->messenger()->addStatus($this->t('翻译结果：@result', [
      '@result' => json_encode($results, JSON_UNESCAPED_UNICODE),
    ]));
  }

}
