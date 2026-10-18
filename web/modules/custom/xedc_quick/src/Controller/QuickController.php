<?php

namespace Drupal\xedc_quick\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\File\FileExists;
use Drupal\Core\File\FileSystemInterface;
use Drupal\media\Entity\Media;
use Drupal\node\Entity\Node;
use Drupal\taxonomy\Entity\Term;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;

class QuickController extends ControllerBase {

  protected function info(): array {
    $fm = \Drupal::service('entity_field.manager');
    $bundle = array_key_first($fm->getFieldMap()['node']['field_images']['bundles'] ?? []);
    $def = $fm->getFieldDefinitions('node', $bundle)['field_images'];
    $mt = array_key_first($def->getSetting('handler_settings')['target_bundles']);
    $type = $this->entityTypeManager()->getStorage('media_type')->load($mt);
    $src = $type->getSource()->getConfiguration()['source_field'];
    return [$bundle, $mt, $src];
  }

  protected function vocab(string $bundle, string $field) {
    $d = \Drupal::service('entity_field.manager')->getFieldDefinitions('node', $bundle)[$field] ?? NULL;
    return $d ? array_key_first($d->getSetting('handler_settings')['target_bundles'] ?? []) : NULL;
  }

  protected function terms(string $bundle, string $field, array $names): array {
    $v = $this->vocab($bundle, $field);
    if (!$v) {
      return [];
    }
    $st = $this->entityTypeManager()->getStorage('taxonomy_term');
    $out = [];
    foreach ($names as $name) {
      $name = trim($name);
      if ($name === '') {
        continue;
      }
      $found = $st->loadByProperties(['name' => $name, 'vid' => $v]);
      if ($found) {
        $t = reset($found);
      }
      else {
        $t = Term::create(['name' => $name, 'vid' => $v]);
        $t->save();
      }
      $out[] = ['target_id' => $t->id()];
    }
    return $out;
  }

  public function page() {
    [$bundle] = $this->info();
    $names = [];
    foreach (['field_model' => 'models', 'field_tags' => 'tags', 'field_categories' => 'cats'] as $fld => $key) {
      $names[$key] = [];
      if ($v = $this->vocab($bundle, $fld)) {
        foreach (array_slice($this->entityTypeManager()->getStorage('taxonomy_term')->loadTree($v), 0, 3000) as $t) {
          $names[$key][] = $t->name;
        }
      }
    }
    return [
      '#type' => 'html_tag',
      '#tag' => 'div',
      '#attributes' => ['id' => 'xq-app'],
      '#attached' => [
        'library' => ['xedc_quick/app'],
        'drupalSettings' => ['xq' => $names],
      ],
      '#cache' => ['max-age' => 0],
    ];
  }

  public function upload(Request $r) {
    [, $mt, $src] = $this->info();
    $f = $r->files->get('file');
    if (!$f || !$f->isValid() || !@getimagesize($f->getPathname())) {
      return new JsonResponse(['error' => 'bad file'], 400);
    }
    $db = \Drupal::database();
    $schema = $db->schema();
    if (!$schema->tableExists('xedc_quick_hash')) {
      $schema->createTable('xedc_quick_hash', [
        'fields' => [
          'hash' => ['type' => 'varchar', 'length' => 64, 'not null' => TRUE],
          'mid' => ['type' => 'int', 'unsigned' => TRUE, 'not null' => TRUE],
        ],
        'primary key' => ['hash'],
      ]);
    }
    $hash = hash_file('sha256', $f->getPathname());
    $old = (int) $db->select('xedc_quick_hash', 'h')->fields('h', ['mid'])->condition('hash', $hash)->execute()->fetchField();
    if ($old && Media::load($old)) {
      return new JsonResponse(['mid' => $old, 'dup' => TRUE]);
    }
    $title = trim((string) $r->request->get('title', 'gallery'));
    $n = (int) $r->request->get('n', 1);
    $slug = strtolower(trim(preg_replace('/[^a-z0-9]+/i', '-', \Drupal::service('transliteration')->transliterate($title, 'en')), '-')) ?: 'gallery';
    $slug = substr($slug, 0, 60);
    $ext = strtolower($f->getClientOriginalExtension()) === 'jpg' ? 'jpg' : 'webp';
    $dir = 'public://gallery/' . date('Y-m');
    \Drupal::service('file_system')->prepareDirectory($dir, FileSystemInterface::CREATE_DIRECTORY);
    $file = \Drupal::service('file.repository')->writeData(
      file_get_contents($f->getPathname()),
      sprintf('%s/%s-%03d.%s', $dir, $slug, $n, $ext),
      FileExists::Rename
    );
    $media = Media::create([
      'bundle' => $mt,
      'name' => $title . ' ' . $n,
      'uid' => $this->currentUser()->id(),
      'status' => 1,
      $src => ['target_id' => $file->id(), 'alt' => $title . ' - 图' . $n],
    ]);
    $media->save();
    $db->merge('xedc_quick_hash')->key('hash', $hash)->fields(['mid' => $media->id()])->execute();
    if (!$schema->tableExists('xedc_quick_orig')) {
      $schema->createTable('xedc_quick_orig', [
        'fields' => [
          'mid' => ['type' => 'int', 'unsigned' => TRUE, 'not null' => TRUE],
          'bytes' => ['type' => 'int', 'size' => 'big', 'unsigned' => TRUE, 'not null' => TRUE],
        ],
        'primary key' => ['mid'],
      ]);
    }
    $db->merge('xedc_quick_orig')->key('mid', $media->id())->fields(['bytes' => (int) $r->request->get('orig', 0)])->execute();
    return new JsonResponse(['mid' => $media->id()]);
  }

  public function createNode(Request $r) {
    [$bundle] = $this->info();
    $d = json_decode($r->getContent(), TRUE) ?: [];
    $title = trim($d['title'] ?? '');
    $mids = array_values(array_unique(array_filter($d['mids'] ?? [])));
    if ($title === '' || !$mids) {
      return new JsonResponse(['error' => '缺少标题或图片'], 400);
    }
    $cover = $d['cover'] ?? $mids[0];
    $node = Node::create([
      'type' => $bundle,
      'title' => $title,
      'uid' => $this->currentUser()->id(),
      'status' => empty($d['publish']) ? 0 : 1,
      'field_images' => array_map(fn($m) => ['target_id' => $m], $mids),
    ]);
    if ($node->hasField('moderation_state')) {
      $node->set('moderation_state', empty($d['publish']) ? 'draft' : 'published');
    }
    if ($node->hasField('field_cover_image')) {
      if ($node->getFieldDefinition('field_cover_image')->getType() === 'image') {
        $m = Media::load($cover);
        $node->set('field_cover_image', ['target_id' => $m->getSource()->getSourceFieldValue($m), 'alt' => $title]);
      }
      else {
        $node->set('field_cover_image', ['target_id' => $cover]);
      }
    }
    if ($node->hasField('field_model') && !empty($d['model'])) {
      $node->set('field_model', $this->terms($bundle, 'field_model', [$d['model']]));
    }
    if ($node->hasField('field_tags')) {
      $node->set('field_tags', $this->terms($bundle, 'field_tags', $d['tags'] ?? []));
    }
    if ($node->hasField('field_categories')) {
      $node->set('field_categories', $this->terms($bundle, 'field_categories', $d['cats'] ?? []));
    }
    $node->save();
    return new JsonResponse(['edit' => '/node/' . $node->id() . (empty($d['publish']) ? '/edit' : '')]);
  }

}
