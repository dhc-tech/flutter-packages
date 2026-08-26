// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late AttachmentResolver resolver;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('attachment_resolver_test');
    resolver = AttachmentResolver(
      cacheManager: AttachmentCacheManager(metadataStore: _NoopStore()),
      // Every test here only exercises the already-local-file path, which
      // never touches the download manager — but the resolver's default
      // constructor would otherwise eagerly build a NativeDownloadClient,
      // which needs a real platform channel unavailable in a unit test.
      downloadManager: DownloadManager(client: _UnusedDownloadClient()),
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('AttachmentResolver attachmentType detection', () {
    test('populates attachmentType from extension when left unset (the '
        'documented minimal id/name/source usage)', () async {
      final file = File('${tempDir.path}/report.csv');
      file.writeAsStringSync('a,b\n1,2\n');
      final attachment = Attachment(
        id: 'a1',
        name: 'report.csv',
        source: AttachmentSource.file(file.path),
        extension: 'csv',
        // attachmentType intentionally omitted — defaults to `unknown`.
      );

      final resolved = await resolver.resolve(attachment);

      expect(resolved.attachment.attachmentType, AttachmentType.csv);
    });

    test(
      'detects type from a URL extension when no local extension is set',
      () async {
        final file = File('${tempDir.path}/report.pdf');
        file.writeAsStringSync('%PDF-1.4 fake');
        final attachment = Attachment(
          id: 'a2',
          name: 'report.pdf',
          source: AttachmentSource.file(file.path),
          remoteUrl: 'https://example.com/files/report.pdf',
        );

        final resolved = await resolver.resolve(attachment);

        expect(resolved.attachment.attachmentType, AttachmentType.pdf);
      },
    );

    test('leaves an already-declared attachmentType untouched', () async {
      final file = File('${tempDir.path}/weird.bin');
      file.writeAsStringSync('irrelevant');
      final attachment = Attachment(
        id: 'a3',
        name: 'weird.bin',
        source: AttachmentSource.file(file.path),
        attachmentType: AttachmentType.image,
      );

      final resolved = await resolver.resolve(attachment);

      expect(resolved.attachment.attachmentType, AttachmentType.image);
    });

    test(
      'stays unknown when no signal (extension/mime/url) allows detection',
      () async {
        final file = File('${tempDir.path}/mystery');
        file.writeAsStringSync('no clues here');
        final attachment = Attachment(
          id: 'a4',
          name: 'mystery',
          source: AttachmentSource.file(file.path),
        );

        final resolved = await resolver.resolve(attachment);

        expect(resolved.attachment.attachmentType, AttachmentType.unknown);
      },
    );

    test('detects type from magic bytes for a BytesAttachmentSource with no '
        'extension/mime/url signal', () async {
      final bytesResolver = AttachmentResolver(
        cacheManager: AttachmentCacheManager(
          metadataStore: _NoopStore(),
          directoryProvider: () async => tempDir,
        ),
        downloadManager: DownloadManager(client: _UnusedDownloadClient()),
      );
      // Real %PDF-1.4 magic bytes — no extension, mime, or url given, so
      // this can only be detected via the bytes themselves.
      final bytes = Uint8List.fromList('%PDF-1.4 fake'.codeUnits);
      final attachment = Attachment(
        id: 'a5',
        name: 'mystery-blob',
        source: AttachmentSource.bytes(bytes),
      );

      final resolved = await bytesResolver.resolve(attachment);

      expect(resolved.attachment.attachmentType, AttachmentType.pdf);
    });
  });
}

/// Minimal no-op store — this resolver's local-file path doesn't touch the
/// cache metadata store at all.
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

/// Never actually called — every test here uses a [FileAttachmentSource],
/// which the resolver serves without downloading. Only exists so
/// [AttachmentResolver]'s constructor doesn't build a real
/// `NativeDownloadClient`.
class _UnusedDownloadClient implements DownloadClient {
  @override
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  }) => throw StateError('should never be called in these tests');
  @override
  Object createCancelToken() => Object();
  @override
  void cancel(Object cancelToken) {}
}
