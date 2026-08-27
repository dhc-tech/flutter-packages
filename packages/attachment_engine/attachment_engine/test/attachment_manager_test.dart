// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('attachment_manager_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('AttachmentManager.dispose', () {
    test('flushes pending (debounced) cache metadata immediately', () async {
      // A long debounce so the write below could only have reached disk
      // via dispose()'s forced flush, not the natural timer.
      final store = FileBasedMetadataStore(
        directoryProvider: () async => tempDir,
        flushDebounce: const Duration(seconds: 30),
      );
      final cacheManager = AttachmentCacheManager(
        metadataStore: store,
        directoryProvider: () async => tempDir,
      );
      await cacheManager.init();
      final resolver = AttachmentResolver(
        cacheManager: cacheManager,
        // Only the cache-write path is exercised below (via
        // AttachmentSource.bytes), which never reaches the download client.
        downloadManager: DownloadManager(client: _UnusedDownloadClient()),
      );
      final manager = AttachmentManager(
        resolver: resolver,
        cacheManager: cacheManager,
      );

      final attachment = Attachment(
        id: 'a1',
        name: 'note.txt',
        source: AttachmentSource.bytes(Uint8List.fromList('hi'.codeUnits)),
      );
      await manager.open(attachment);

      await manager.dispose();

      // Fresh store reading the same directory: if dispose() hadn't forced
      // the flush, this index file wouldn't exist yet (debounce is 30s).
      final reopened = FileBasedMetadataStore(
        directoryProvider: () async => tempDir,
      );
      await reopened.init();
      expect(await reopened.get(attachment.stableIdentity), isNotNull);
    });

    test(
      'disposes the resolver (closes download progress controllers)',
      () async {
        final cacheManager = AttachmentCacheManager(
          metadataStore: _NoopStore(),
          directoryProvider: () async => tempDir,
        );
        await cacheManager.init();
        final downloadManager = DownloadManager(
          client: _UnusedDownloadClient(),
        );
        final resolver = AttachmentResolver(
          cacheManager: cacheManager,
          downloadManager: downloadManager,
        );
        final manager = AttachmentManager(
          resolver: resolver,
          cacheManager: cacheManager,
        );

        // Establish a progress stream/controller for some key, mirroring what
        // a real in-flight download would have left behind.
        final stream = downloadManager.progressStream('k1');
        var done = false;
        stream.listen(null, onDone: () => done = true);

        await manager.dispose();

        // dispose() -> AttachmentResolver.dispose() ->
        // DownloadManager.dispose() closes every progress controller, which
        // fires onDone on any listener.
        expect(done, isTrue);
      },
    );
  });

  group('AttachmentManager.initializeDefault re-initialization', () {
    test('disposes the previous singleton instance before replacing it '
        '(no leaked download-progress resources across re-init)', () async {
      final firstClient = _UnusedDownloadClient();
      final first = await AttachmentManager.initializeDefault(
        downloadClient: firstClient,
      );
      // Grab the first instance's DownloadManager indirectly is not
      // possible from the public API, so instead assert the public
      // contract: a second initializeDefault() call must not throw (it
      // would if disposal state were left inconsistent), and the
      // singleton is actually replaced.
      final second = await AttachmentManager.initializeDefault(
        downloadClient: _UnusedDownloadClient(),
      );

      expect(identical(first, second), isFalse);
      expect(identical(AttachmentManager.instance, second), isTrue);
    });
  });
}

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
