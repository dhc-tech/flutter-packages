import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cache identity stability', () {
    test('stableIdentity prefers cacheKey over id', () {
      const attachment = Attachment(
        id: 'attachment-1',
        name: 'file.pdf',
        source: AttachmentSource.url('https://example.com/f.pdf?sig=abc'),
        cacheKey: 'stable-key-1',
      );
      expect(attachment.stableIdentity, 'stable-key-1');
    });

    test('stableIdentity falls back to id when cacheKey is absent', () {
      const attachment = Attachment(
        id: 'attachment-1',
        name: 'file.pdf',
        source: AttachmentSource.url('https://example.com/f.pdf'),
      );
      expect(attachment.stableIdentity, 'attachment-1');
    });

    test('identity is stable across a rotated signed URL', () {
      const before = Attachment(
        id: 'a1',
        name: 'file.pdf',
        cacheKey: 'logical-key',
        source: AttachmentSource.url(
          'https://cdn.example.com/f.pdf?sig=old&exp=1',
        ),
      );
      final after = before.copyWith(
        source: const AttachmentSource.url(
          'https://cdn.example.com/f.pdf?sig=new&exp=2',
        ),
        remoteUrl: 'https://cdn.example.com/f.pdf?sig=new&exp=2',
      );
      expect(before.stableIdentity, after.stableIdentity);
    });

    test(
      'sanitizedFileName never embeds raw remote filename or path separators',
      () {
        final manager = AttachmentCacheManager(metadataStore: _NoopStore());
        const attachment = Attachment(
          id: 'a1',
          name: 'evil',
          source: AttachmentSource.url('https://example.com/../../etc/passwd'),
          cacheKey: '../../etc/passwd',
          extension: 'pdf',
        );
        final fileName = manager.sanitizedFileName(
          attachment.stableIdentity,
          extension: attachment.extension,
        );
        expect(fileName.contains('/'), isFalse);
        expect(fileName.contains('..'), isFalse);
        expect(fileName.endsWith('.pdf'), isTrue);
      },
    );

    test('sanitizedFileName is deterministic for the same logical key', () {
      final manager = AttachmentCacheManager(metadataStore: _NoopStore());
      final a = manager.sanitizedFileName('same-key', extension: 'pdf');
      final b = manager.sanitizedFileName('same-key', extension: 'pdf');
      expect(a, b);
    });
  });
}

/// Minimal no-op store sufficient for exercising sanitizedFileName, which
/// does not touch the store.
class _NoopStore implements AttachmentMetadataStore {
  @override
  Future<void> init() async {}
  @override
  Future<CacheEntry?> get(String key) async => null;
  @override
  Future<List<CacheEntry>> getAll() async => [];
  @override
  Future<void> put(CacheEntry entry) async {}
  @override
  Future<void> delete(String key) async {}
  @override
  Future<void> clear() async {}
}
