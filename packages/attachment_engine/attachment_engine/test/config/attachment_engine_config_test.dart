// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory fake metadata store that records every `put` call, so tests
/// can assert zero writes occur when caching is disabled — mirrors the
/// fake-collaborator pattern used by `native_download_channel_test.dart`.
class FakeMetadataStore implements AttachmentMetadataStore {
  final Map<String, CacheEntry> _entries = {};
  int putCalls = 0;
  int initCalls = 0;

  @override
  Future<void> init() async => initCalls++;

  @override
  Future<CacheEntry?> get(String key) async => _entries[key];

  @override
  Future<List<CacheEntry>> getAll() async => _entries.values.toList();

  @override
  Future<void> put(CacheEntry entry) async {
    putCalls++;
    _entries[entry.key] = entry;
  }

  @override
  Future<void> delete(String key) async => _entries.remove(key);

  @override
  Future<void> clear() async => _entries.clear();
}

Attachment _attachment({
  String id = 'a1',
  AttachmentType type = AttachmentType.image,
  AttachmentStatus status = AttachmentStatus.ready,
  String? localPath,
}) {
  return Attachment(
    id: id,
    name: 'file',
    source: const AttachmentSource.url('https://example.com/f.bin'),
    remoteUrl: 'https://example.com/f.bin',
    attachmentType: type,
    status: status,
    localPath: localPath,
  );
}

void main() {
  group('AttachmentEngineConfig defaults', () {
    test('reproduce current hardcoded behavior', () {
      const config = AttachmentEngineConfig.defaults();

      expect(config.cache.enabled, isTrue);
      expect(
        config.cache.maxTotalSizeBytes,
        500 * 1024 * 1024,
      ); // CachePolicy default
      expect(config.download.maxRetries, 3); // DownloadManager default
      expect(config.download.resumeEnabled, isTrue);
      expect(config.externalOpen.allowExternalFallback, isTrue);
      for (final type in AttachmentType.values) {
        expect(config.renderers.isEnabled(type), isTrue, reason: '$type');
      }
    });

    test('is a const, equatable value type', () {
      expect(
        const AttachmentEngineConfig.defaults(),
        const AttachmentEngineConfig(),
      );
    });
  });

  group('validation', () {
    test('rejects negative maxTotalSizeBytes', () {
      expect(
        () => const CacheConfig(maxTotalSizeBytes: -1).let(_validateCache),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });

    test('rejects negative maxFileSizeBytes', () {
      expect(
        () => const CacheConfig(maxFileSizeBytes: -1).let(_validateCache),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });

    test('rejects maxFileSizeBytes exceeding maxTotalSizeBytes', () {
      expect(
        () => const CacheConfig(
          maxTotalSizeBytes: 100,
          maxFileSizeBytes: 200,
        ).let(_validateCache),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });

    test('rejects negative retention', () {
      expect(
        () =>
            const CacheConfig(retention: Duration(seconds: -1))
                .let(_validateCache),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });

    test('rejects zero/negative maxConcurrentDownloads', () {
      expect(
        () =>
            const DownloadConfig(maxConcurrentDownloads: 0)
                .let(_validateDownload),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
      expect(
        () =>
            const DownloadConfig(maxConcurrentDownloads: -1)
                .let(_validateDownload),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });

    test('rejects negative maxRetries', () {
      expect(
        () => const DownloadConfig(maxRetries: -1).let(_validateDownload),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });

    test('rejects non-positive timeouts', () {
      expect(
        () =>
            const DownloadConfig(connectTimeout: Duration.zero)
                .let(_validateDownload),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
      expect(
        () =>
            const DownloadConfig(receiveTimeout: Duration.zero)
                .let(_validateDownload),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });

    test('boundary: maxConcurrentDownloads of exactly 1 is valid', () {
      expect(
        () =>
            const DownloadConfig(maxConcurrentDownloads: 1)
                .let(_validateDownload),
        returnsNormally,
      );
    });

    test('boundary: maxRetries of 0 is valid (no retries)', () {
      expect(
        () => const DownloadConfig(maxRetries: 0).let(_validateDownload),
        returnsNormally,
      );
    });

    test(
      'boundary: maxFileSizeBytes exactly equal to maxTotalSizeBytes is valid',
      () {
        expect(
          () => const CacheConfig(
            maxTotalSizeBytes: 100,
            maxFileSizeBytes: 100,
          ).let(_validateCache),
          returnsNormally,
        );
      },
    );

    test('top-level validate() surfaces sub-config errors', () {
      const config = AttachmentEngineConfig(
        download: DownloadConfig(maxConcurrentDownloads: 0),
      );
      expect(config.validate, throwsA(isA<AttachmentConfigValidationError>()));
    });
  });

  group('CacheConfig enabled vs disabled', () {
    late FakeMetadataStore store;

    setUp(() {
      store = FakeMetadataStore();
    });

    test('enabled: init initializes the metadata store and write persists metadata', () async {
      final manager = AttachmentCacheManager(
        metadataStore: store,
        config: const CacheConfig(enabled: true),
        directoryProvider: () async => Directory.systemTemp,
      );
      await manager.init();
      expect(store.initCalls, 1);

      await manager.write(_attachment(), Uint8List.fromList([1, 2, 3]));
      expect(store.putCalls, 1);
    });

    test('disabled: init never touches the metadata store', () async {
      final manager = AttachmentCacheManager(
        metadataStore: store,
        config: const CacheConfig(enabled: false),
        directoryProvider: () async => Directory.systemTemp,
      );
      await manager.init();
      expect(store.initCalls, 0);
    });

    test('disabled: write never persists metadata (zero put calls)', () async {
      final manager = AttachmentCacheManager(
        metadataStore: store,
        config: const CacheConfig(enabled: false),
        directoryProvider: () async => Directory.systemTemp,
      );
      await manager.init();

      final path = await manager.write(
        _attachment(),
        Uint8List.fromList([1, 2, 3]),
      );

      expect(store.putCalls, 0);
      expect(File(path).existsSync(), isTrue);
      await File(path).delete();
    });

    test('disabled: lookup always returns null', () async {
      final manager = AttachmentCacheManager(
        metadataStore: store,
        config: const CacheConfig(enabled: false),
        directoryProvider: () async => Directory.systemTemp,
      );
      await manager.init();
      await manager.write(_attachment(), Uint8List.fromList([1, 2, 3]));

      expect(await manager.lookup(_attachment()), isNull);
    });

    test(
      'disabled: clearAll/clearExpired/clearUnused are no-ops (no store calls)',
      () async {
        final manager = AttachmentCacheManager(
          metadataStore: store,
          config: const CacheConfig(enabled: false),
          directoryProvider: () async => Directory.systemTemp,
        );
        await manager.init();

        await manager.clearAll();
        await manager.clearExpired();
        await manager.clearUnused();

        expect(store.putCalls, 0);
      },
    );

    test('maxFileSizeBytes: oversized writes bypass the managed cache (no metadata)', () async {
      final manager = AttachmentCacheManager(
        metadataStore: store,
        config: const CacheConfig(maxFileSizeBytes: 2),
        directoryProvider: () async => Directory.systemTemp,
      );
      await manager.init();

      final path = await manager.write(
        _attachment(),
        Uint8List.fromList([1, 2, 3, 4]),
      );

      expect(store.putCalls, 0);
      expect(File(path).existsSync(), isTrue);
      await File(path).delete();
    });

    test(
      'retention: entries older than retention are treated as a miss',
      () async {
        final manager = AttachmentCacheManager(
          metadataStore: store,
          config: const CacheConfig(retention: Duration(milliseconds: 1)),
          directoryProvider: () async => Directory.systemTemp,
        );
        await manager.init();
        final attachment = _attachment();
        await manager.write(attachment, Uint8List.fromList([1, 2, 3]));

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(await manager.lookup(attachment), isNull);
      },
    );

    test('cache size limit (maxTotalSizeBytes) still evicts via existing CachePolicy', () async {
      final manager = AttachmentCacheManager(
        metadataStore: store,
        policy: const CachePolicy(maxTotalSizeBytes: 5),
        config: const CacheConfig(maxTotalSizeBytes: 5),
        directoryProvider: () async => Directory.systemTemp,
      );
      await manager.init();

      await manager.write(
        _attachment(id: 'first'),
        Uint8List.fromList(List.filled(4, 1)),
      );
      await manager.write(
        _attachment(id: 'second'),
        Uint8List.fromList(List.filled(4, 2)),
      );

      // First entry should have been evicted to make room for the second.
      expect(await manager.lookup(_attachment(id: 'first')), isNull);
      expect(await manager.lookup(_attachment(id: 'second')), isNotNull);
    });
  });

  group('RendererConfig / CapabilityEngine', () {
    test('a single disabled renderer type reports rendererDisabledByConfig and no preview/open/play', () {
      const engine = CapabilityEngine(
        rendererConfig: RendererConfig(video: false),
      );
      final caps = engine.derive(
        _attachment(type: AttachmentType.video, localPath: '/f.mp4'),
      );

      expect(caps.rendererDisabledByConfig, isTrue);
      expect(caps.canPreview, isFalse);
      expect(caps.canPlay, isFalse);
      expect(caps.canOpen, isFalse);
    });

    test(
      'multiple renderers disabled simultaneously are each reported disabled',
      () {
        const engine = CapabilityEngine(
          rendererConfig: RendererConfig(
            video: false,
            audio: false,
            pdf: false,
          ),
        );

        for (final type in [
          AttachmentType.video,
          AttachmentType.audio,
          AttachmentType.pdf,
        ]) {
          final caps = engine.derive(_attachment(type: type, localPath: '/f'));
          expect(caps.rendererDisabledByConfig, isTrue, reason: '$type');
        }

        final imageCaps = engine.derive(
          _attachment(type: AttachmentType.image, localPath: '/f.png'),
        );
        expect(imageCaps.rendererDisabledByConfig, isFalse);
        expect(imageCaps.canPreview, isTrue);
      },
    );

    test('an enabled renderer type is unaffected', () {
      const engine = CapabilityEngine(
        rendererConfig: RendererConfig(video: false),
      );
      final caps = engine.derive(
        _attachment(type: AttachmentType.image, localPath: '/f.png'),
      );
      expect(caps.rendererDisabledByConfig, isFalse);
      expect(caps.canPreview, isTrue);
    });
  });

  group('RendererRegistry', () {
    test('rendererFor a disabled type never returns the real renderer', () {
      final registry = RendererRegistry(
        rendererConfig: const RendererConfig(video: false),
      );
      final renderer = registry.rendererFor(AttachmentType.video);
      expect(renderer, isA<UnknownAttachmentRenderer>());
      expect(renderer, isNot(isA<VideoAttachmentRenderer>()));
    });

    test(
      'rendererFor an enabled type returns the real registered renderer',
      () {
        final registry = RendererRegistry();
        expect(
          registry.rendererFor(AttachmentType.video),
          isA<VideoAttachmentRenderer>(),
        );
      },
    );
  });

  group('ExternalOpenConfig', () {
    test(
      'AttachmentCapabilities.canOpenExternally is false when disallowed',
      () {
        const engine = CapabilityEngine(
          externalOpenConfig: ExternalOpenConfig(allowExternalFallback: false),
        );
        final caps = engine.derive(_attachment(localPath: '/f.png'));
        expect(caps.canOpenExternally, isFalse);
      },
    );

    test('canOpenExternally is true by default when content is local', () {
      const engine = CapabilityEngine();
      final caps = engine.derive(_attachment(localPath: '/f.png'));
      expect(caps.canOpenExternally, isTrue);
    });
  });

  group('DownloadConfig retry/backoff/concurrency', () {
    test('maxRetries is honored (bounded attempts before throwing)', () async {
      final client = _CountingFailingClient();
      final manager = DownloadManager(
        client: client,
        config: const DownloadConfig(
          maxRetries: 2,
          retryBackoff: DownloadRetryBackoff.none,
        ),
      );

      await expectLater(
        () => manager.download('k', 'https://example.com/f'),
        throwsA(isA<Exception>()),
      );
      expect(client.callCount, 2);
    });

    test('resumeEnabled:false forces resume:false on every attempt including retries', () async {
      final client = _CountingFailingClient(failuresBeforeSuccess: 2);
      final manager = DownloadManager(
        client: client,
        config: const DownloadConfig(
          maxRetries: 5,
          retryBackoff: DownloadRetryBackoff.none,
          resumeEnabled: false,
        ),
      );

      await manager.download('k', 'https://example.com/f');

      expect(client.resumeFlags, [false, false, false]);
    });

    test(
      'resumeEnabled:true (default) passes resume:true from the second attempt',
      () async {
        final client = _CountingFailingClient(failuresBeforeSuccess: 1);
        final manager = DownloadManager(
          client: client,
          config: const DownloadConfig(retryBackoff: DownloadRetryBackoff.none),
        );

        await manager.download('k', 'https://example.com/f');

        expect(client.resumeFlags, [false, true]);
      },
    );

    test(
      'maxConcurrentDownloads caps genuinely concurrent in-flight downloads',
      () async {
        final client = _ConcurrencyTrackingClient();
        final manager = DownloadManager(
          client: client,
          config: const DownloadConfig(maxConcurrentDownloads: 2),
        );

        await Future.wait([
          manager.download('a', 'u'),
          manager.download('b', 'u'),
          manager.download('c', 'u'),
          manager.download('d', 'u'),
          manager.download('e', 'u'),
        ]);

        expect(client.maxObservedConcurrency, lessThanOrEqualTo(2));
        expect(client.totalCalls, 5);
      },
    );

    test('zero/negative maxConcurrentDownloads throws at construction', () {
      expect(
        () => DownloadManager(
          client: _CountingFailingClient(),
          config: const DownloadConfig(maxConcurrentDownloads: 0),
        ),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });
  });
}

void _validateCache(CacheConfig c) =>
    AttachmentEngineConfig(cache: c).validate();
void _validateDownload(DownloadConfig d) =>
    AttachmentEngineConfig(download: d).validate();

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class _CountingFailingClient implements DownloadClient {
  _CountingFailingClient({this.failuresBeforeSuccess = 999});
  final int failuresBeforeSuccess;
  int callCount = 0;
  final List<bool> resumeFlags = [];

  @override
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  }) async {
    callCount++;
    resumeFlags.add(resume);
    if (callCount <= failuresBeforeSuccess) {
      throw Exception('simulated failure');
    }
    return Uint8List.fromList([1]);
  }

  @override
  Object createCancelToken() => Object();

  @override
  void cancel(Object cancelToken) {}
}

class _ConcurrencyTrackingClient implements DownloadClient {
  int _running = 0;
  int maxObservedConcurrency = 0;
  int totalCalls = 0;

  @override
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  }) async {
    totalCalls++;
    _running++;
    maxObservedConcurrency = maxObservedConcurrency > _running
        ? maxObservedConcurrency
        : _running;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    _running--;
    return Uint8List.fromList([1]);
  }

  @override
  Object createCancelToken() => Object();

  @override
  void cancel(Object cancelToken) {}
}
