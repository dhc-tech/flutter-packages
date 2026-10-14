// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

const _pdf = [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31];

class _Platform extends AttachmentEnginePlatform {
  _Platform(this.supportDir);
  final String supportDir;
  final List<String> shared = [];
  final List<String> opened = [];
  NativeOpenResult openResult = const NativeOpenResult(success: true);

  @override
  Future<void> shareFile(String path, {String? text}) async =>
      shared.add('$path|$text');

  @override
  Future<NativeOpenResult> openExternally(
    String path, {
    String? mimeType,
  }) async {
    opened.add(path);
    return openResult;
  }

  @override
  Future<String> getApplicationSupportDirectory() async => supportDir;

  @override
  Future<String> getApplicationCacheDirectory() async => '$supportDir/cache';

  @override
  Stream<Map<Object?, Object?>> downloadEvents() => const Stream.empty();
}

/// Throws something that is not an [AttachmentResolutionException].
class _ExplodingClient extends ScriptedDownloadClient {
  _ExplodingClient() : super((_, _) async => Uint8List(0));

  @override
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  }) => throw StateError('sync explosion');
}

void main() {
  late Directory tempDir;
  late _Platform platform;
  late MemoryMetadataStore store;
  late RecordingDiagnostics diagnostics;
  late ScriptedDownloadClient client;
  late AttachmentCacheManager cache;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('manager_extra_test');
    platform = _Platform('${tempDir.path}/support');
    AttachmentEnginePlatform.instance = platform;
    NativePathsChannel.resetForTesting();
    store = MemoryMetadataStore();
    diagnostics = RecordingDiagnostics();
    client = ScriptedDownloadClient.ok(_pdf);
    cache = AttachmentCacheManager(
      metadataStore: store,
      directoryProvider: () async => Directory('${tempDir.path}/cache'),
    );
    await cache.init();
  });

  tearDown(() {
    NativePathsChannel.resetForTesting();
    tempDir.deleteSync(recursive: true);
  });

  AttachmentManager manager({
    AttachmentEngineConfig config = const AttachmentEngineConfig.defaults(),
    DownloadClient? downloadClient,
    FakeConnectivity? connectivity,
  }) {
    final resolver = AttachmentResolver(
      cacheManager: cache,
      downloadManager: DownloadManager(
        client: downloadClient ?? client,
        config: const DownloadConfig(maxRetries: 1),
      ),
      connectivityChecker: connectivity ?? FakeConnectivity(),
      capabilityEngine: CapabilityEngine(
        rendererConfig: config.renderers,
        externalOpenConfig: config.externalOpen,
      ),
    );
    return AttachmentManager(
      resolver: resolver,
      cacheManager: cache,
      diagnostics: diagnostics,
      config: config,
    );
  }

  Attachment att(String id, {String? localPath}) => Attachment(
    id: id,
    name: 'name-$id',
    source: AttachmentSource.url('https://example.com/$id.pdf'),
    localPath: localPath,
  );

  group('AttachmentManager.instance', () {
    test('throws a descriptive StateError before initializeDefault', () {
      expect(
        () => AttachmentManager.instance,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('initializeDefault'),
          ),
        ),
      );
    });

    test('initializeDefault validates config before doing any work', () async {
      await expectLater(
        AttachmentManager.initializeDefault(
          config: const AttachmentEngineConfig(
            cache: CacheConfig(maxTotalSizeBytes: -1),
          ),
        ),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
      expect(() => AttachmentManager.instance, throwsStateError);
    });

    test(
      'initializeDefault wires one config through cache, download, '
      'renderers and capabilities, and re-initialisation replaces it',
      () async {
        final first = await AttachmentManager.initializeDefault(
          diagnostics: diagnostics,
          downloadClient: client,
          connectivityChecker: FakeConnectivity(),
          config: const AttachmentEngineConfig(
            renderers: RendererConfig(pdf: false),
            externalOpen: ExternalOpenConfig(allowExternalFallback: false),
          ),
        );
        expect(AttachmentManager.instance, same(first));
        final resolved = await first.open(att('wired'));
        expect(resolved.attachment.attachmentType, AttachmentType.pdf);
        expect(resolved.capabilities.rendererDisabledByConfig, isTrue);
        expect(resolved.capabilities.canOpenExternally, isFalse);
        expect(File(resolved.localPath).existsSync(), isTrue);
        expect(client.urls, ['https://example.com/wired.pdf']);
        expect(diagnostics.events, ['start:wired', 'complete:wired:false']);

        final second = await AttachmentManager.initializeDefault(
          downloadClient: client,
          connectivityChecker: FakeConnectivity(),
        );
        expect(second, isNot(same(first)));
        expect(AttachmentManager.instance, same(second));
        await second.dispose();
      },
    );
  });

  group('construction and config', () {
    test('an invalid config is rejected by the constructor', () {
      expect(
        () => AttachmentManager(
          resolver: AttachmentResolver(
            cacheManager: cache,
            downloadManager: DownloadManager(client: client),
          ),
          cacheManager: cache,
          config: const AttachmentEngineConfig(
            download: DownloadConfig(maxRetries: -1),
          ),
        ),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });

    test('exposes its config, a config-aware registry, and recomputes '
        'capabilities with the configured policy', () {
      const config = AttachmentEngineConfig(
        renderers: RendererConfig(video: false),
        externalOpen: ExternalOpenConfig(allowExternalFallback: false),
      );
      final m = manager(config: config);
      expect(m.config, config);
      expect(m.rendererRegistry, same(m.rendererRegistry));
      expect(
        m.rendererRegistry.rendererFor(AttachmentType.video),
        isA<UnknownAttachmentRenderer>().having(
          (r) => r.disabledByConfig,
          'disabled',
          isTrue,
        ),
      );
      final caps = m.capabilitiesFor(
        Attachment(
          id: 'v',
          name: 'v',
          source: const AttachmentSource.url('https://x/v.mp4'),
          attachmentType: AttachmentType.video,
          status: AttachmentStatus.ready,
          localPath: '/v.mp4',
        ),
      );
      expect(caps.rendererDisabledByConfig, isTrue);
      expect(caps.canPlay, isFalse);
      expect(caps.canOpenExternally, isFalse);
      expect(caps.canShare, isTrue);
    });
  });

  group('resolution entry points and diagnostics', () {
    test(
      'open/preview/play/retry all resolve through the same pipeline',
      () async {
        final m = manager();
        final a = att('p');
        expect((await m.open(a)).fromCache, isFalse);
        expect((await m.preview(a)).fromCache, isTrue);
        expect((await m.play(a)).fromCache, isTrue);
        expect((await m.retry(a)).fromCache, isTrue);
        expect(
          diagnostics.events.where((e) => e.startsWith('start:')),
          hasLength(4),
        );
        expect(
          diagnostics.events.where((e) => e.startsWith('complete:p:true')),
          hasLength(3),
        );
        expect(diagnostics.lastDuration, isNotNull);
        expect(client.urls, hasLength(1));
      },
    );

    test(
      'download() clears the cache entry first so it always refetches',
      () async {
        final m = manager();
        final a = att('dl');
        await m.open(a);
        final again = await m.download(a);
        expect(again.fromCache, isFalse);
        expect(client.urls, hasLength(2));
      },
    );

    test(
      'a typed failure is reported with its type name and rethrown',
      () async {
        final m = manager(connectivity: FakeConnectivity(online: false));
        await expectLater(
          m.open(att('off')),
          throwsA(
            isA<AttachmentResolutionException>().having(
              (e) => e.failure,
              'failure',
              isA<NetworkUnavailable>(),
            ),
          ),
        );
        expect(diagnostics.events, [
          'start:off',
          'failed:off:NetworkUnavailable',
        ]);
      },
    );

    test(
      'an unexpected error is wrapped as UnknownFailure with the cause',
      () async {
        // The resolver wraps client errors as DownloadFailed, so make the
        // failure unexpected at the cache layer instead.
        final broken = AttachmentManager(
          resolver: AttachmentResolver(
            cacheManager: _ThrowingCache(),
            downloadManager: DownloadManager(client: client),
            connectivityChecker: FakeConnectivity(),
          ),
          cacheManager: cache,
          diagnostics: diagnostics,
        );
        await expectLater(
          broken.open(att('boom')),
          throwsA(
            isA<AttachmentResolutionException>()
                .having((e) => e.failure, 'failure', isA<UnknownFailure>())
                .having((e) => e.failure.cause, 'cause', isA<StateError>()),
          ),
        );
        expect(diagnostics.events, [
          'start:boom',
          'failed:boom:UnknownFailure',
        ]);
      },
    );

    test('download errors from the client surface as DownloadFailed', () async {
      final m = manager(downloadClient: _ExplodingClient());
      await expectLater(
        m.open(att('dlf')),
        throwsA(
          isA<AttachmentResolutionException>().having(
            (e) => e.failure,
            'failure',
            isA<DownloadFailed>(),
          ),
        ),
      );
      expect(diagnostics.events.last, 'failed:dlf:DownloadFailed');
    });

    test('concurrent open() calls for one attachment download once', () async {
      final gate = Completer<Uint8List>();
      final gated = ScriptedDownloadClient((_, _) => gate.future);
      final m = manager(downloadClient: gated);
      final a = m.open(att('c'));
      final b = m.open(att('c'));
      await pumpEventQueue();
      gate.complete(Uint8List.fromList(_pdf));
      await Future.wait([a, b]);
      expect(gated.urls, hasLength(1));
    });
  });

  group('prefetch', () {
    test('defaults the id and name to the url', () async {
      final m = manager();
      final r = await m.prefetch('https://example.com/report.pdf');
      expect(r!.attachment.id, 'https://example.com/report.pdf');
      expect(r.attachment.name, 'https://example.com/report.pdf');
      expect(r.attachment.remoteUrl, 'https://example.com/report.pdf');
    });

    test('uses the supplied id and name and reports failures to diagnostics '
        'while returning null', () async {
      final m = manager(connectivity: FakeConnectivity(online: false));
      final r = await m.prefetch(
        'https://example.com/x.pdf',
        id: 'stable',
        name: 'Report',
      );
      expect(r, isNull);
      expect(diagnostics.events, [
        'start:stable',
        'failed:stable:NetworkUnavailable',
      ]);
    });
  });

  group('share and openExternally', () {
    test('share requires a local path', () async {
      await expectLater(
        manager().share(att('s')),
        throwsA(
          isA<AttachmentResolutionException>().having(
            (e) => e.failure,
            'f',
            isA<InvalidSource>(),
          ),
        ),
      );
      expect(platform.shared, isEmpty);
    });

    test('share passes the path and the attachment name', () async {
      await manager().share(att('s', localPath: '/data/s.pdf'));
      expect(platform.shared, ['/data/s.pdf|name-s']);
    });

    test('openExternally is refused when the config disallows it', () async {
      final m = manager(
        config: const AttachmentEngineConfig(
          externalOpen: ExternalOpenConfig(allowExternalFallback: false),
        ),
      );
      await expectLater(
        m.openExternally(att('o', localPath: '/x')),
        throwsA(
          isA<AttachmentResolutionException>().having(
            (e) => e.failure,
            'f',
            isA<ExternalOpenDisabled>(),
          ),
        ),
      );
      expect(platform.opened, isEmpty);
    });

    test('openExternally requires a local path', () async {
      await expectLater(
        manager().openExternally(att('o')),
        throwsA(
          isA<AttachmentResolutionException>().having(
            (e) => e.failure,
            'f',
            isA<InvalidSource>(),
          ),
        ),
      );
    });

    test('openExternally maps a native failure to RendererFailed', () async {
      platform.openResult = const NativeOpenResult(
        success: false,
        message: 'no app',
      );
      await expectLater(
        manager().openExternally(att('o', localPath: '/x')),
        throwsA(
          isA<AttachmentResolutionException>().having(
            (e) => e.failure,
            'f',
            isA<RendererFailed>(),
          ),
        ),
      );
    });

    test('openExternally succeeds with the local path', () async {
      await manager().openExternally(att('o', localPath: '/data/o.pdf'));
      expect(platform.opened, ['/data/o.pdf']);
    });
  });

  group('cache management', () {
    test(
      'deleteCache removes the cached copy so the next open redownloads',
      () async {
        final m = manager();
        final a = att('del');
        final first = await m.open(a);
        await m.deleteCache(a);
        expect(File(first.localPath).existsSync(), isFalse);
        expect((await m.open(a)).fromCache, isFalse);
      },
    );

    test('deleteCache for something never cached is a no-op', () async {
      await manager().deleteCache(att('never'));
    });

    test('pin / isPinned / unpin round trip', () async {
      final m = manager();
      final a = att('pin');
      expect(await m.isPinnedForOffline(a), isFalse);
      await m.pinForOffline(a);
      expect(await m.isPinnedForOffline(a), isTrue);
      await m.unpinFromOffline(a);
      expect(await m.isPinnedForOffline(a), isFalse);
    });

    test(
      'pinForOffline propagates resolution failures without pinning',
      () async {
        final m = manager(connectivity: FakeConnectivity(online: false));
        await expectLater(
          m.pinForOffline(att('pf')),
          throwsA(isA<AttachmentResolutionException>()),
        );
        expect(await m.isPinnedForOffline(att('pf')), isFalse);
      },
    );

    test('dispose can be called repeatedly', () async {
      final m = manager();
      await m.dispose();
      await m.dispose();
    });
  });
}

/// A cache whose lookup throws a non-resolution error.
class _ThrowingCache extends AttachmentCacheManager {
  _ThrowingCache() : super(metadataStore: MemoryMetadataStore());

  @override
  Future<String?> lookup(Attachment attachment) =>
      Future.error(StateError('cache exploded'));
}
