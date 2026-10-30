<?php

namespace Drupal\xedc_site_audit\Plugin\SiteAuditCheck;

use Drupal\site_audit\Plugin\SiteAuditCheckBase;

/**
 * Shared result storage for DcLili checks.
 */
abstract class XedcCheckBase extends SiteAuditCheckBase {

  /**
   * Message for the calculated score.
   */
  protected string $message = '';

  /**
   * Machine name passed to AuditChecker::all().
   */
  abstract protected function checkId(): string;

  /**
   * {@inheritdoc}
   */
  public function getResultFail() {
    return $this->message;
  }

  /**
   * {@inheritdoc}
   */
  public function getResultInfo() {
    return $this->message;
  }

  /**
   * {@inheritdoc}
   */
  public function getResultPass() {
    return $this->message;
  }

  /**
   * {@inheritdoc}
   */
  public function getResultWarn() {
    return $this->message;
  }

  /**
   * {@inheritdoc}
   */
  public function getAction() {
    return '';
  }

  /**
   * {@inheritdoc}
   */
  public function calculateScore() {
    $result = \Drupal::service('xedc_site_audit.checker')->all()[$this->checkId()];
    $this->message = $result['message'];
    return match ($result['value']) {
      'pass' => SiteAuditCheckBase::AUDIT_CHECK_SCORE_PASS,
      'warn' => SiteAuditCheckBase::AUDIT_CHECK_SCORE_WARN,
      'info' => SiteAuditCheckBase::AUDIT_CHECK_SCORE_INFO,
      default => SiteAuditCheckBase::AUDIT_CHECK_SCORE_FAIL,
    };
  }

}
