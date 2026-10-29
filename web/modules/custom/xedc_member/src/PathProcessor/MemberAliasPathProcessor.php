<?php

namespace Drupal\xedc_member\PathProcessor;

use Drupal\Core\PathProcessor\InboundPathProcessorInterface;
use Drupal\Core\PathProcessor\OutboundPathProcessorInterface;
use Drupal\Core\Render\BubbleableMetadata;
use Drupal\Core\Session\AccountProxyInterface;
use Drupal\xedc_member\Service\MemberAliasManager;
use Symfony\Component\HttpFoundation\Request;

/**
 * Maps a member vanity URL onto the member center, and back out again.
 */
class MemberAliasPathProcessor implements InboundPathProcessorInterface, OutboundPathProcessorInterface {

  /**
   * Constructs a MemberAliasPathProcessor.
   */
  public function __construct(
    protected MemberAliasManager $aliasManager,
    protected AccountProxyInterface $currentUser,
  ) {}

  /**
   * {@inheritdoc}
   */
  public function processInbound($path, Request $request) {
    if ($path === '/' || !str_starts_with($path, '/')) {
      return $path;
    }
    $trimmed = trim($path, '/');
    if ($trimmed === '') {
      return $path;
    }
    $parts = explode('/', $trimmed);
    $slug = rawurldecode($parts[0]);
    $lower = mb_strtolower($slug);
    if ($slug === '' || str_contains($slug, '.') || $this->aliasManager->isReservedSlug($lower)) {
      return $path;
    }
    $uid = $this->aliasManager->findUidBySlug($slug);
    if ($uid <= 0) {
      return $path;
    }
    $suffix = implode('/', array_slice($parts, 1));
    $internal = $this->aliasManager->internalPath($suffix);
    if ($internal === NULL) {
      return $path;
    }
    if ((int) $this->currentUser->id() !== $uid) {
      return '/xedc-member/alias-denied';
    }
    return $internal;
  }

  /**
   * {@inheritdoc}
   */
  public function processOutbound($path, &$options = [], ?Request $request = NULL, ?BubbleableMetadata $bubbleable_metadata = NULL) {
    if ($path !== '/member' && !str_starts_with($path, '/member/')) {
      return $path;
    }
    $uid = (int) $this->currentUser->id();
    if ($uid <= 0) {
      return $path;
    }
    if ($bubbleable_metadata) {
      $bubbleable_metadata->addCacheContexts(['user']);
      $bubbleable_metadata->addCacheTags(['user:' . $uid, 'xedc_member:aliases']);
    }
    return $this->aliasManager->toPublicPath($uid, $path);
  }

}
