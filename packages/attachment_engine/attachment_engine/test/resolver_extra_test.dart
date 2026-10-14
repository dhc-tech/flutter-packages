// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine/src/platform/platform_info.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

const _pdf = [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31];
const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A];

class _IosInfo extends PlatformInfo {
  const _IosInfo();
  @override
  bool get isIOS => true;
  @override
  bool get isAndroid => false;
}

class _NoEventsPlatform extends AttachmentEnginePlatform {
  @override
  Stream<Map<Object?, Object?>> downloadEvents() => const Stream.empty();
}

void main() {
  late Directory tempDir;
  late MemoryMetadataStore store;
  late AttachmentCacheManager cache;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('resolver_extra_test');
    store = MemoryMetadataStore();
    cache = AttachmentCacheManager(
      metadataStore: store,
      directoryProvider: () async => Directory('${tempDir.path}/cache'),
    );
    await cache.init();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  AttachmentResolver resolver({
    ScriptedDownloadClient? client,
    FakeConnectivity? connectivity,
    CapabilityEngine capability = const CapabilityEngine(),
    DownloadConfig config = const DownloadConfig(maxRetries: 1),
  }) => AttachmentResolver(
    cacheManager: cache,
    downloadManager: DownloadManager(
      client: client ?? ScriptedDownloadClient.ok(_pdf),
      config: config,
    ),
    connectivityChecker: connectivity ?? FakeConnectivity(),
    capabilityEngine: capability,
  );

  Attachment urlAtt(
    String id, {
    String url = 'https://example.com/doc.pdf',
    AttachmentType type = AttachmentType.unknown,
    String? extension,
    String? mimeType,
    String? remoteUrl,
    DateTime? expiresAt,
  }) => Attachment(
    id: id,
    name: id,
    source: AttachmentSource.url(url),
    attachmentType: type,
    extension: extension,
    mimeType: mimeType,
    remoteUrl: remoteUrl,
    expiresAt: expiresAt,
  );

  Future<void> expectFailure<T extends AttachmentFailure>(
    Future<Object?> future, {
    Object? cause,
  }) async {
    try {
      await future;
      fail('expected an AttachmentResolutionException');
    } on AttachmentResolutionException catch (e) {
      expect(e.failure, isA<T>());
      if (cause != null) expect(e.failure.cause, cause);
    }
  }

  group('local sources', () {
    test(
      'an existing file resolves in place without touching the cache',
      () async {
        final file = File('${tempDir.path}/a.pdf')..writeAsBytesSync(_pdf);
        final r = await resolver().resolve(
          Attachment(
            id: 'f',
            name: 'f',
            source: AttachmentSource.file(file.path),
            extension: 'pdf',
          ),
        );
        expect(r.localPath, file.path);
        expect(r.fromCache, isFalse);
        expect(r.attachment.status, AttachmentStatus.ready);
        expect(r.attachment.attachmentType, AttachmentType.pdf);
        expect(store.puts, 0);
      },
    );

    test('a missing file is AttachmentNotFound', () async {
      await expectFailure<AttachmentNotFound>(
        resolver().resolve(
          Attachment(
            id: 'f',
            name: 'f',
            source: AttachmentSource.file('${tempDir.path}/missing'),
          ),
        ),
      );
    });

    test(
      'bytes are written to the cache and type is sniffed from them',
      () async {
        final r = await resolver().resolve(
          Attachment(
            id: 'b',
            name: 'b',
            source: AttachmentSource.bytes(Uint8List.fromList(_png)),
          ),
        );
        expect(File(r.localPath).readAsBytesSync(), _png);
        expect(r.attachment.attachmentType, AttachmentType.image);
        expect(r.capabilities.canShare, isTrue);
        expect(store.puts, 1);
      },
    );

    test('empty bytes still resolve, with an unknown type', () async {
      final r = await resolver().resolve(
        Attachment(
          id: 'e',
          name: 'e',
          source: AttachmentSource.bytes(Uint8List(0)),
        ),
      );
      expect(File(r.localPath).lengthSync(), 0);
      expect(r.attachment.attachmentType, AttachmentType.unknown);
    });
  });

  group('network resolution', () {
    test('downloads, caches and reports a miss, then serves the next call '
        'from cache', () async {
      final client = ScriptedDownloadClient.ok(_pdf);
      final r = resolver(client: client);
      final first = await r.resolve(urlAtt('d1'));
      expect(first.fromCache, isFalse);
      expect(first.attachment.attachmentType, AttachmentType.pdf);
      final second = await r.resolve(urlAtt('d1'));
      expect(second.fromCache, isTrue);
      expect(second.localPath, first.localPath);
      expect(client.urls, hasLength(1));
    });

    test('remoteUrl takes precedence over the url source', () async {
      final client = ScriptedDownloadClient.ok(_pdf);
      await resolver(client: client).resolve(
        urlAtt(
          'd2',
          url: 'https://old/doc.pdf',
          remoteUrl: 'https://fresh/doc.pdf',
        ),
      );
      expect(client.urls, ['https://fresh/doc.pdf']);
    });

    test('a non-url source with a remoteUrl downloads it', () async {
      final client = ScriptedDownloadClient.ok(_pdf);
      await resolver(client: client).resolve(
        const Attachment(
          id: 'srv',
          name: 'srv',
          source: AttachmentSource.serverAttachment('42'),
          remoteUrl: 'https://api/attachments/42.pdf',
        ),
      );
      expect(client.urls, ['https://api/attachments/42.pdf']);
    });

    test(
      'no resolvable url is InvalidSource and never checks the network',
      () async {
        final connectivity = FakeConnectivity();
        for (final source in [
          const AttachmentSource.serverAttachment('1'),
          const AttachmentSource.cache('missing'),
          const AttachmentSource.stream('s'),
        ]) {
          await expectFailure<InvalidSource>(
            resolver(connectivity: connectivity).resolve(
              Attachment(
                id: 'x-${source.runtimeType}',
                name: 'x',
                source: source,
              ),
            ),
          );
        }
        expect(connectivity.checks, 0);
      },
    );

    test('offline is NetworkUnavailable and nothing is downloaded', () async {
      final client = ScriptedDownloadClient.ok(_pdf);
      await expectFailure<NetworkUnavailable>(
        resolver(
          client: client,
          connectivity: FakeConnectivity(online: false),
        ).resolve(urlAtt('o')),
      );
      expect(client.urls, isEmpty);
    });

    test('a cache hit is served even while offline', () async {
      final connectivity = FakeConnectivity();
      final r = resolver(connectivity: connectivity);
      await r.resolve(urlAtt('off'));
      connectivity.online = false;
      final again = await r.resolve(urlAtt('off'));
      expect(again.fromCache, isTrue);
    });

    test(
      'a download failure becomes DownloadFailed carrying the cause',
      () async {
        final error = StateError('socket reset');
        await expectFailure<DownloadFailed>(
          resolver(client: ScriptedDownloadClient.failing(error))
              .resolve(urlAtt('fail')),
          cause: error,
        );
      },
    );

    test('magic bytes contradicting the declared type are CorruptedFile and '
        'nothing is cached', () async {
      await expectFailure<CorruptedFile>(
        resolver(client: ScriptedDownloadClient.ok(_png))
            .resolve(urlAtt('mismatch', type: AttachmentType.pdf)),
      );
      expect(store.puts, 0);
    });

    test('an unknown declared type, an undetectable body, or an empty body '
        'never counts as corrupt', () async {
      final r = resolver(client: ScriptedDownloadClient.ok([1, 2, 3, 4]));
      final res = await r.resolve(urlAtt('u1', url: 'https://x/blob'));
      expect(res.attachment.attachmentType, AttachmentType.unknown);

      final declaredButOpaque = await resolver(
        client: ScriptedDownloadClient.ok([1, 2, 3, 4]),
      ).resolve(urlAtt('u2', type: AttachmentType.pdf));
      expect(declaredButOpaque.attachment.attachmentType, AttachmentType.pdf);

      final empty = await resolver(client: ScriptedDownloadClient.ok([]))
          .resolve(urlAtt('u3', type: AttachmentType.pdf));
      expect(File(empty.localPath).lengthSync(), 0);
    });

    test('the attachment expiry is persisted and an expired entry is '
        're-downloaded', () async {
      final client = ScriptedDownloadClient.ok(_pdf);
      final r = resolver(client: client);
      await r.resolve(
        urlAtt(
          'exp',
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      expect(store.entries['exp']!.expiresAt, isNotNull);
      await r.resolve(urlAtt('exp'));
      expect(client.urls, hasLength(2));
    });

    test('cache entries whose file vanished are treated as a miss', () async {
      final client = ScriptedDownloadClient.ok(_pdf);
      final r = resolver(client: client);
      final first = await r.resolve(urlAtt('gone'));
      File(first.localPath).deleteSync();
      final second = await r.resolve(urlAtt('gone'));
      expect(second.fromCache, isFalse);
      expect(client.urls, hasLength(2));
    });
  });

  group('type detection and capabilities', () {
    test('detection prefers mime, then extension, then url', () async {
      final byMime =
          await resolver(client: ScriptedDownloadClient.ok([1, 2, 3])).resolve(
            urlAtt('m', url: 'https://x/a.zip', mimeType: 'application/pdf'),
          );
      expect(byMime.attachment.attachmentType, AttachmentType.pdf);
      final byExt = await resolver(client: ScriptedDownloadClient.ok([1, 2, 3]))
          .resolve(urlAtt('e', url: 'https://x/a.zip', extension: 'csv'));
      expect(byExt.attachment.attachmentType, AttachmentType.csv);
      final byUrl = await resolver(client: ScriptedDownloadClient.ok([1, 2, 3]))
          .resolve(urlAtt('u', url: 'https://x/a.mp4?sig=1'));
      expect(byUrl.attachment.attachmentType, AttachmentType.video);
    });

    test(
      'an explicitly declared type is never overwritten by detection',
      () async {
        final r = await resolver(client: ScriptedDownloadClient.ok([1, 2, 3]))
            .resolve(
              urlAtt('x', type: AttachmentType.text, url: 'https://x/a.mp4'),
            );
        expect(r.attachment.attachmentType, AttachmentType.text);
      },
    );

    test(
      'capabilities honour the injected engine (iOS office preview)',
      () async {
        final office = [0x50, 0x4B, 0x03, 0x04, 0, 0];
        final ios = await resolver(
          client: ScriptedDownloadClient.ok(office),
          capability: const CapabilityEngine(platformInfo: _IosInfo()),
        ).resolve(urlAtt('o1', url: 'https://x/a.docx', extension: 'docx'));
        expect(ios.capabilities.canPreview, isTrue);
        final android = await resolver(
          client: ScriptedDownloadClient.ok(office),
        ).resolve(urlAtt('o2', url: 'https://x/a.docx', extension: 'docx'));
        expect(android.capabilities.canPreview, isFalse);
        expect(android.attachment.capabilities, android.capabilities);
      },
    );

    test(
      'a disabled renderer is reflected in the resolved capabilities',
      () async {
        final r = await resolver(
          capability: const CapabilityEngine(
            rendererConfig: RendererConfig(pdf: false),
          ),
        ).resolve(urlAtt('dis'));
        expect(r.capabilities.rendererDisabledByConfig, isTrue);
        expect(r.capabilities.canPreview, isFalse);
      },
    );
  });

  group('in-flight deduplication', () {
    test(
      'concurrent resolves of the same identity share one download',
      () async {
        final gate = Completer<Uint8List>();
        final client = ScriptedDownloadClient((_, _) => gate.future);
        final r = resolver(client: client);
        final a = r.resolve(urlAtt('same'));
        final b = r.resolve(
          urlAtt('same', url: 'https://rotated/doc.pdf?sig=2'),
        );
        await pumpEventQueue();
        gate.complete(Uint8List.fromList(_pdf));
        final results = await Future.wait([a, b]);
        expect(client.urls, hasLength(1));
        expect(identical(results[0], results[1]), isTrue);
      },
    );

    test('different identities download independently', () async {
      final client = ScriptedDownloadClient.ok(_pdf);
      final r = resolver(client: client);
      await Future.wait([r.resolve(urlAtt('a')), r.resolve(urlAtt('b'))]);
      expect(client.urls, hasLength(2));
    });

    test('cacheKey (not id) is the identity used for dedupe', () async {
      final client = ScriptedDownloadClient.ok(_pdf);
      final r = resolver(client: client);
      final a = urlAtt('id-1').copyWith(cacheKey: 'shared');
      final b = urlAtt('id-2').copyWith(cacheKey: 'shared');
      await Future.wait([r.resolve(a), r.resolve(b)]);
      expect(client.urls, hasLength(1));
    });

    test('a failure reaches every waiter and the next call retries', () async {
      final gate = Completer<Uint8List>();
      var call = 0;
      final client = ScriptedDownloadClient((_, _) {
        call++;
        return call == 1 ? gate.future : Future.value(Uint8List.fromList(_pdf));
      });
      final r = resolver(client: client);
      final a = r.resolve(urlAtt('f'));
      final b = r.resolve(urlAtt('f'));
      final ea = expectFailure<DownloadFailed>(a);
      final eb = expectFailure<DownloadFailed>(b);
      await pumpEventQueue();
      gate.completeError(StateError('x'));
      await Future.wait([ea, eb]);
      final retry = await r.resolve(urlAtt('f'));
      expect(retry.fromCache, isFalse);
      expect(client.urls, hasLength(2));
    });
  });

  group('dispose', () {
    test('disposing a resolver built with a custom client is safe and '
        'repeatable', () {
      final r = resolver();
      r.dispose();
      r.dispose();
    });

    test('a resolver with no download manager builds and disposes a native '
        'client', () {
      AttachmentEnginePlatform.instance = _NoEventsPlatform();
      final r = AttachmentResolver(cacheManager: cache);
      r.dispose();
    });
  });
}
