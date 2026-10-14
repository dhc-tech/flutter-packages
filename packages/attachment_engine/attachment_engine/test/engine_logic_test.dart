// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine/src/platform/platform_info.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';
import 'helpers/widget_harness.dart';
import 'helpers/zip_builder.dart';

class _Info extends PlatformInfo {
  const _Info({this.ios = false});
  final bool ios;
  @override
  bool get isIOS => ios;
  @override
  bool get isAndroid => !ios;
}

void main() {
  group('InFlightRegistry', () {
    test('shares one operation between callers of the same key', () async {
      final registry = InFlightRegistry<int>();
      var runs = 0;
      final gate = Completer<int>();
      final a = registry.run('k', () {
        runs++;
        return gate.future;
      });
      final b = registry.run('k', () {
        runs++;
        return gate.future;
      });
      expect(identical(a, b), isTrue);
      expect(registry.activeCount, 1);
      expect(registry.isInFlight('k'), isTrue);
      gate.complete(7);
      expect(await Future.wait([a, b]), [7, 7]);
      expect(runs, 1);
    });

    test('different keys run independently and the key is released '
        'afterwards', () async {
      final registry = InFlightRegistry<String>();
      final a = registry.run('a', () async => 'A');
      final b = registry.run('b', () async => 'B');
      expect(registry.activeCount, 2);
      expect(await a, 'A');
      expect(await b, 'B');
      expect(registry.activeCount, 0);
      expect(registry.isInFlight('a'), isFalse);
      var runs = 0;
      await registry.run('a', () async => '${++runs}');
      expect(runs, 1);
    });

    test(
      'a failure reaches all waiters, then the key is free to retry',
      () async {
        final registry = InFlightRegistry<int>();
        final gate = Completer<int>();
        final a = registry.run('k', () => gate.future);
        final b = registry.run('k', () => gate.future);
        final ea = expectLater(a, throwsA(isA<StateError>()));
        final eb = expectLater(b, throwsA(isA<StateError>()));
        gate.completeError(StateError('x'));
        await Future.wait([ea, eb]);
        expect(registry.isInFlight('k'), isFalse);
        expect(await registry.run('k', () async => 1), 1);
      },
    );

    test('a synchronously throwing operation does not leave a stale key', () {
      final registry = InFlightRegistry<int>();
      expect(
        () => registry.run('k', () => throw StateError('sync')),
        throwsStateError,
      );
      expect(registry.activeCount, 0);
      expect(registry.isInFlight('k'), isFalse);
    });

    test(
      'clear() forgets in-flight operations without cancelling them',
      () async {
        final registry = InFlightRegistry<int>();
        final gate = Completer<int>();
        final f = registry.run('k', () => gate.future);
        registry.clear();
        expect(registry.activeCount, 0);
        gate.complete(3);
        expect(await f, 3);
      },
    );

    test('empty and very long keys are valid', () async {
      final registry = InFlightRegistry<int>();
      expect(await registry.run('', () async => 1), 1);
      expect(await registry.run('k' * 10000, () async => 2), 2);
    });
  });

  group('CapabilityEngine status matrix (android, pdf, url source)', () {
    const engine = CapabilityEngine(platformInfo: _Info());

    AttachmentCapabilities derive(
      AttachmentStatus status, {
      AttachmentType type = AttachmentType.pdf,
      AttachmentSource source = const AttachmentSource.url('https://x/f.pdf'),
      String? remoteUrl,
      CapabilityEngine? with_,
    }) => (with_ ?? engine).derive(
      Attachment(
        id: 'a',
        name: 'a',
        source: source,
        attachmentType: type,
        status: status,
        remoteUrl: remoteUrl,
      ),
    );

    test('discovered: preview and download, nothing local yet', () {
      expect(
        derive(AttachmentStatus.discovered),
        const AttachmentCapabilities(
          canPreview: true,
          canDownload: true,
          canCache: true,
        ),
      );
    });

    test('in-progress and expired states can only download and cache', () {
      for (final s in [
        AttachmentStatus.validating,
        AttachmentStatus.resolving,
        AttachmentStatus.downloading,
        AttachmentStatus.expired,
      ]) {
        expect(
          derive(s),
          const AttachmentCapabilities(canDownload: true, canCache: true),
          reason: s.name,
        );
      }
    });

    test('cached and ready have the full local capability set', () {
      for (final s in [AttachmentStatus.cached, AttachmentStatus.ready]) {
        expect(
          derive(s),
          const AttachmentCapabilities(
            canPreview: true,
            canOpen: true,
            canDownload: true,
            canShare: true,
            canCache: true,
            canOpenExternally: true,
            canDeleteCache: true,
          ),
          reason: s.name,
        );
      }
    });

    test('rendering is like ready but has no cache to delete yet', () {
      final c = derive(AttachmentStatus.rendering);
      expect(c.canOpen, isTrue);
      expect(c.canShare, isTrue);
      expect(c.canDeleteCache, isFalse);
    });

    test('failed offers nothing', () {
      expect(derive(AttachmentStatus.failed), AttachmentCapabilities.none);
    });

    test('cleaned only offers re-download, and not for in-memory bytes', () {
      expect(
        derive(AttachmentStatus.cleaned),
        const AttachmentCapabilities(canDownload: true),
      );
      expect(
        derive(
          AttachmentStatus.cleaned,
          source: AttachmentSource.bytes(Uint8List(1)),
        ),
        AttachmentCapabilities.none,
      );
    });

    test('video and audio can play only with local content', () {
      for (final t in [AttachmentType.video, AttachmentType.audio]) {
        expect(derive(AttachmentStatus.ready, type: t).canPlay, isTrue);
        expect(derive(AttachmentStatus.discovered, type: t).canPlay, isFalse);
        expect(derive(AttachmentStatus.failed, type: t).canPlay, isFalse);
      }
      expect(derive(AttachmentStatus.ready).canPlay, isFalse);
    });

    test('unknown type: no preview/open but still shareable and external', () {
      final c = derive(AttachmentStatus.ready, type: AttachmentType.unknown);
      expect(c.canPreview, isFalse);
      expect(c.canOpen, isFalse);
      expect(c.canShare, isTrue);
      expect(c.canOpenExternally, isTrue);
      expect(c.rendererDisabledByConfig, isFalse);
    });

    test('office previews in-app only on iOS', () {
      final android = derive(
        AttachmentStatus.ready,
        type: AttachmentType.office,
      );
      expect(android.canPreview, isFalse);
      expect(android.canOpen, isTrue);
      expect(android.canOpenExternally, isTrue);
      final ios = derive(
        AttachmentStatus.ready,
        type: AttachmentType.office,
        with_: const CapabilityEngine(platformInfo: _Info(ios: true)),
      );
      expect(ios.canPreview, isTrue);
    });

    test(
      'a disabled renderer blocks preview/open/play and flags the config',
      () {
        final c = derive(
          AttachmentStatus.ready,
          type: AttachmentType.video,
          with_: const CapabilityEngine(
            platformInfo: _Info(),
            rendererConfig: RendererConfig(video: false),
          ),
        );
        expect(c.rendererDisabledByConfig, isTrue);
        expect(c.canPreview, isFalse);
        expect(c.canOpen, isFalse);
        expect(c.canPlay, isFalse);
        expect(c.canShare, isTrue);
      },
    );

    test('external fallback disabled removes canOpenExternally only', () {
      final c = derive(
        AttachmentStatus.ready,
        with_: const CapabilityEngine(
          platformInfo: _Info(),
          externalOpenConfig: ExternalOpenConfig(allowExternalFallback: false),
        ),
      );
      expect(c.canOpenExternally, isFalse);
      expect(c.canShare, isTrue);
    });

    test('download availability depends on the source and remoteUrl', () {
      expect(
        derive(
          AttachmentStatus.ready,
          source: AttachmentSource.bytes(Uint8List(1)),
        ).canDownload,
        isFalse,
      );
      expect(
        derive(
          AttachmentStatus.ready,
          source: const AttachmentSource.file('/f'),
        ).canDownload,
        isFalse,
      );
      expect(
        derive(
          AttachmentStatus.ready,
          source: const AttachmentSource.file('/f'),
          remoteUrl: 'https://x',
        ).canDownload,
        isTrue,
      );
      expect(
        derive(
          AttachmentStatus.ready,
          source: const AttachmentSource.serverAttachment('1'),
        ).canDownload,
        isTrue,
      );
      expect(
        derive(
          AttachmentStatus.ready,
          source: const AttachmentSource.stream('s'),
        ).canDownload,
        isFalse,
      );
    });

    test('a cache-source attachment cannot be re-cached', () {
      expect(
        derive(
          AttachmentStatus.ready,
          source: const AttachmentSource.cache('k'),
        ).canCache,
        isFalse,
      );
    });
  });

  group('AttachmentCacheManager', () {
    late Directory tempDir;
    late MemoryMetadataStore store;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cache_manager_extra');
      store = MemoryMetadataStore();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    AttachmentCacheManager make({
      CacheConfig config = const CacheConfig(),
      CachePolicy policy = const CachePolicy(),
      MemoryMetadataStore? s,
    }) => AttachmentCacheManager(
      metadataStore: s ?? store,
      config: config,
      policy: policy,
      directoryProvider: () async => Directory('${tempDir.path}/c'),
    );

    Attachment att(String id, {String? extension, DateTime? expiresAt}) =>
        Attachment(
          id: id,
          name: id,
          source: AttachmentSource.url('https://x/$id'),
          extension: extension,
          expiresAt: expiresAt,
        );

    Uint8List data(int n, [int fill = 1]) =>
        Uint8List.fromList(List.filled(n, fill));

    test('init creates the directory and initialises the store', () async {
      final m = make();
      await m.init();
      expect(store.initialized, isTrue);
      expect(Directory('${tempDir.path}/c').existsSync(), isTrue);
      await m.init();
    });

    test('sanitizedFileName hashes the key and sanitises the extension', () {
      final m = make();
      final plain = m.sanitizedFileName('../../etc/passwd');
      expect(plain, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        m.sanitizedFileName('k', extension: 'pdf'),
        '${m.sanitizedFileName('k')}.pdf',
      );
      expect(
        m.sanitizedFileName('k', extension: '.p/d\\f!'),
        '${m.sanitizedFileName('k')}.pdf',
      );
      expect(
        m.sanitizedFileName('k', extension: '..//'),
        m.sanitizedFileName('k'),
      );
      expect(m.sanitizedFileName('k', extension: ''), m.sanitizedFileName('k'));
      expect(m.sanitizedFileName('a'), isNot(m.sanitizedFileName('b')));
      expect(m.sanitizedFileName(''), hasLength(64));
      expect(m.sanitizedFileName('é' * 10000), hasLength(64));
    });

    test('write persists bytes, a checksum and metadata; lookup returns the '
        'path and bumps lastAccessedAt', () async {
      final m = make()..toString();
      await m.init();
      final bytes = Uint8List.fromList(utf8.encode('hello'));
      final path = await m.write(att('k', extension: 'txt'), bytes);
      expect(path, endsWith('.txt'));
      expect(File(path).readAsBytesSync(), bytes);
      final entry = store.entries['k']!;
      expect(entry.sizeBytes, 5);
      expect(
        entry.checksum,
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
      final stale = DateTime.utc(2020);
      store.entries['k'] = entry.copyWith(lastAccessedAt: stale);
      expect(await m.lookup(att('k', extension: 'txt')), path);
      expect(store.entries['k']!.lastAccessedAt.isAfter(stale), isTrue);
    });

    test('lookup misses for unknown keys and for missing files', () async {
      final m = make();
      await m.init();
      expect(await m.lookup(att('nope')), isNull);
      final path = await m.write(att('k'), data(3));
      File(path).deleteSync();
      expect(await m.lookup(att('k')), isNull);
    });

    test('expired entries are misses, unless pinned', () async {
      final m = make();
      await m.init();
      await m.write(
        att('e'),
        data(3),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(await m.lookup(att('e')), isNull);
      await m.pin(att('e'));
      expect(await m.lookup(att('e')), isNotNull);
    });

    test('retention makes old entries misses', () async {
      final m = make(config: const CacheConfig(retention: Duration(days: 7)));
      await m.init();
      await m.write(att('r'), data(3));
      expect(await m.lookup(att('r')), isNotNull);
      final e = store.entries['r']!;
      store.entries['r'] = CacheEntry(
        key: e.key,
        localPath: e.localPath,
        sizeBytes: e.sizeBytes,
        createdAt: DateTime.now().subtract(const Duration(days: 8)),
        lastAccessedAt: e.lastAccessedAt,
      );
      expect(await m.lookup(att('r')), isNull);
    });

    test('totalSizeBytes sums entries; clearExpired removes only expired, '
        'unpinned entries', () async {
      final m = make();
      await m.init();
      await m.write(att('a'), data(10));
      await m.write(
        att('b'),
        data(20),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      await m.write(
        att('c'),
        data(40),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      await m.pin(att('c'));
      expect(await m.totalSizeBytes(), 70);
      await m.clearExpired();
      expect(store.entries.keys, unorderedEquals(['a', 'c']));
      expect(await m.totalSizeBytes(), 50);
    });

    test(
      'clearUnused honours the cutoff boundary and skips pinned entries',
      () async {
        final m = make();
        await m.init();
        final old = DateTime.now().subtract(const Duration(days: 40));
        for (final id in ['old', 'oldPinned', 'fresh']) {
          await m.write(att(id), data(1));
        }
        store.entries['old'] = store.entries['old']!.copyWith(
          lastAccessedAt: old,
        );
        store.entries['oldPinned'] = store.entries['oldPinned']!.copyWith(
          lastAccessedAt: old,
          pinned: true,
        );
        await m.clearUnused();
        expect(store.entries.keys, unorderedEquals(['oldPinned', 'fresh']));
        await m.clearUnused(unusedFor: Duration.zero);
        expect(store.entries.keys, ['oldPinned']);
      },
    );

    test(
      'clearAll wipes everything including pinned and deletes the files',
      () async {
        final m = make();
        await m.init();
        final p1 = await m.write(att('a'), data(1));
        final p2 = await m.write(att('b'), data(1));
        await m.pin(att('b'));
        await m.clearAll();
        expect(store.entries, isEmpty);
        expect(File(p1).existsSync(), isFalse);
        expect(File(p2).existsSync(), isFalse);
        expect(await m.totalSizeBytes(), 0);
      },
    );

    test('LRU eviction removes the least recently used until the new write '
        'fits', () async {
      final m = make(policy: const CachePolicy(maxTotalSizeBytes: 100));
      await m.init();
      await m.write(att('a'), data(40));
      store.entries['a'] = store.entries['a']!.copyWith(
        lastAccessedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      await m.write(att('b'), data(40));
      store.entries['b'] = store.entries['b']!.copyWith(
        lastAccessedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await m.write(att('c'), data(40));
      expect(store.entries.keys, unorderedEquals(['b', 'c']));
      await m.write(att('d'), data(100));
      expect(store.entries.keys, ['d']);
    });

    test('a write exactly filling the cap evicts nothing', () async {
      final m = make(policy: const CachePolicy(maxTotalSizeBytes: 100));
      await m.init();
      await m.write(att('a'), data(60));
      await m.write(att('b'), data(40));
      expect(store.entries.keys, unorderedEquals(['a', 'b']));
    });

    test(
      'a single write larger than the cap still succeeds and evicts the rest',
      () async {
        final m = make(policy: const CachePolicy(maxTotalSizeBytes: 10));
        await m.init();
        await m.write(att('a'), data(5));
        final path = await m.write(att('big'), data(50));
        expect(File(path).lengthSync(), 50);
        expect(store.entries.keys, ['big']);
      },
    );

    test('a disabled cache makes every operation a harmless no-op and '
        'writes throwaway files', () async {
      final m = make(config: const CacheConfig(enabled: false));
      await m.init();
      expect(store.initialized, isFalse);
      final path = await m.write(att('x'), data(3));
      addTearDown(() {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      });
      expect(File(path).existsSync(), isTrue);
      expect(await m.lookup(att('x')), isNull);
      expect(await m.totalSizeBytes(), 0);
      expect(await m.isPinned(att('x')), isFalse);
      await m.pin(att('x'));
      await m.unpin(att('x'));
      await m.clearAll();
      await m.clearExpired();
      await m.clearUnused();
      await m.clearAttachment(att('x'));
      expect(store.puts, 0);
      expect(store.getAllCalls, 0);
    });

    test(
      'thumbnail/preview categories can be disabled independently',
      () async {
        final m = make(
          config: const CacheConfig(
            thumbnailCachingEnabled: false,
            previewCachingEnabled: false,
          ),
        );
        await m.init();
        final t = await m.write(
          att('t'),
          data(1),
          category: CacheEntryCategory.thumbnail,
        );
        final p = await m.write(
          att('p'),
          data(1),
          category: CacheEntryCategory.preview,
        );
        addTearDown(() {
          for (final f in [t, p]) {
            if (File(f).existsSync()) File(f).deleteSync();
          }
        });
        expect(store.entries, isEmpty);
        await m.write(att('o'), data(1));
        expect(store.entries.keys, ['o']);
      },
    );

    test(
      'maxFileSizeBytes: exactly at the limit is cached, one over is not',
      () async {
        final m = make(config: const CacheConfig(maxFileSizeBytes: 10));
        await m.init();
        await m.write(att('fits'), data(10));
        final over = await m.write(att('over'), data(11));
        addTearDown(() {
          if (File(over).existsSync()) File(over).deleteSync();
        });
        expect(store.entries.keys, ['fits']);
      },
    );

    test(
      'pin is idempotent and unpin of unknown or unpinned is a no-op',
      () async {
        final m = make();
        await m.init();
        await m.write(att('a'), data(1));
        await m.pin(att('a'));
        final putsAfterFirstPin = store.puts;
        await m.pin(att('a'));
        expect(store.puts, putsAfterFirstPin);
        await m.unpin(att('a'));
        final putsAfterUnpin = store.puts;
        await m.unpin(att('a'));
        await m.unpin(att('never'));
        expect(store.puts, putsAfterUnpin);
      },
    );

    test('mutations are serialised so concurrent writes keep the total under '
        'the cap', () async {
      final m = make(policy: const CachePolicy(maxTotalSizeBytes: 100));
      await m.init();
      await Future.wait([
        for (var i = 0; i < 20; i++) m.write(att('k$i'), data(30, i)),
      ]);
      expect(await m.totalSizeBytes(), lessThanOrEqualTo(100));
    });

    test('a failing mutation does not wedge the queue', () async {
      final m = make();
      await m.init();
      await expectLater(m.pin(att('not cached')), throwsStateError);
      await m.write(att('after'), data(1));
      expect(store.entries.keys, ['after']);
    });

    test('dispose is safe for a non-file store', () async {
      await make().dispose();
    });
  });

  group('CachePolicy', () {
    CacheEntry entry(
      String key,
      int size, {
      int minutesAgo = 0,
      bool pinned = false,
      DateTime? expiresAt,
    }) {
      final t = DateTime(2026, 1, 1).subtract(Duration(minutes: minutesAgo));
      return CacheEntry(
        key: key,
        localPath: '/$key',
        sizeBytes: size,
        createdAt: t,
        lastAccessedAt: t,
        pinned: pinned,
        expiresAt: expiresAt,
      );
    }

    test('ties on lastAccessedAt and an exactly-full cache evict nothing', () {
      const policy = CachePolicy(maxTotalSizeBytes: 100);
      expect(
        policy.selectEntriesToEvict([entry('a', 50), entry('b', 50)]),
        isEmpty,
      );
    });

    test('an empty list and zero cap are handled', () {
      expect(
        const CachePolicy(maxTotalSizeBytes: 0).selectEntriesToEvict([]),
        isEmpty,
      );
      final all = const CachePolicy(maxTotalSizeBytes: 0)
          .selectEntriesToEvict([entry('a', 1), entry('b', 1)]);
      expect(all.map((e) => e.key), ['a', 'b']);
    });

    test('evicts oldest first and stops as soon as the budget fits', () {
      const policy = CachePolicy(maxTotalSizeBytes: 100);
      final evicted = policy.selectEntriesToEvict([
        entry('new', 50, minutesAgo: 1),
        entry('old', 50, minutesAgo: 30),
        entry('mid', 50, minutesAgo: 10),
      ]);
      expect(evicted.map((e) => e.key), ['old']);
    });

    test('selectExpired treats a null expiry as never expiring', () {
      final past = DateTime.now().subtract(const Duration(seconds: 1));
      final future = DateTime.now().add(const Duration(hours: 1));
      expect(
        const CachePolicy()
            .selectExpired([
              entry('none', 1),
              entry('past', 1, expiresAt: past),
              entry('future', 1, expiresAt: future),
            ])
            .map((e) => e.key),
        ['past'],
      );
    });
  });

  group('CacheEntry', () {
    test('toMap/fromMap round trip including optional fields', () {
      final entry = CacheEntry(
        key: 'k',
        localPath: '/p',
        sizeBytes: 9,
        createdAt: DateTime.utc(2026, 1, 1),
        lastAccessedAt: DateTime.utc(2026, 1, 2),
        expiresAt: DateTime.utc(2026, 2, 1),
        attachmentType: 'pdf',
        category: CacheEntryCategory.preview,
        checksum: 'abc',
        pinned: true,
      );
      final back = CacheEntry.fromMap(
        jsonDecode(jsonEncode(entry.toMap())) as Map,
      );
      expect(back.key, 'k');
      expect(back.localPath, '/p');
      expect(back.sizeBytes, 9);
      expect(back.createdAt, entry.createdAt);
      expect(back.lastAccessedAt, entry.lastAccessedAt);
      expect(back.expiresAt, entry.expiresAt);
      expect(back.attachmentType, 'pdf');
      expect(back.category, CacheEntryCategory.preview);
      expect(back.checksum, 'abc');
      expect(back.pinned, isTrue);
    });

    test('legacy maps lacking pinned/category/expiry get safe defaults', () {
      final back = CacheEntry.fromMap({
        'key': 'k',
        'localPath': '/p',
        'sizeBytes': 1,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'lastAccessedAt': '2026-01-01T00:00:00.000Z',
        'category': 'something-removed',
      });
      expect(back.pinned, isFalse);
      expect(back.category, CacheEntryCategory.original);
      expect(back.expiresAt, isNull);
      expect(back.isExpired, isFalse);
    });

    test('a malformed map throws rather than yielding a bogus entry', () {
      expect(() => CacheEntry.fromMap({'key': 'k'}), throwsA(anything));
      expect(
        () => CacheEntry.fromMap({
          'key': 'k',
          'localPath': '/p',
          'sizeBytes': 1,
          'createdAt': 'not a date',
          'lastAccessedAt': '2026-01-01T00:00:00.000Z',
        }),
        throwsFormatException,
      );
    });

    test('isExpired is true strictly after expiresAt and copyWith touches only '
        'its fields', () {
      final e = CacheEntry(
        key: 'k',
        localPath: '/p',
        sizeBytes: 1,
        createdAt: DateTime(2020),
        lastAccessedAt: DateTime(2020),
        expiresAt: DateTime.now().subtract(const Duration(milliseconds: 1)),
      );
      expect(e.isExpired, isTrue);
      final touched = e.copyWith(lastAccessedAt: DateTime(2030), pinned: true);
      expect(touched.lastAccessedAt, DateTime(2030));
      expect(touched.pinned, isTrue);
      expect(touched.key, 'k');
      expect(touched.createdAt, DateTime(2020));
      expect(e.copyWith().pinned, isFalse);
    });
  });

  group('FileBasedMetadataStore', () {
    late Directory tempDir;
    late File indexFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('metadata_store_extra');
      indexFile = File('${tempDir.path}/idx/index.json');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    FileBasedMetadataStore make({
      Duration debounce = const Duration(seconds: 2),
    }) => FileBasedMetadataStore(
      fileName: 'index.json',
      directoryProvider: () async => Directory('${tempDir.path}/idx'),
      flushDebounce: debounce,
    );

    CacheEntry entry(String key) => CacheEntry(
      key: key,
      localPath: '/$key',
      sizeBytes: 1,
      createdAt: DateTime.utc(2026),
      lastAccessedAt: DateTime.utc(2026),
    );

    test('using the store before init() is a clear StateError', () async {
      final s = make();
      await s.put(entry('k'));
      await expectLater(s.flushPending(), throwsStateError);
    });

    test('init creates the directory, treats a missing, empty or corrupt '
        'index as empty', () async {
      final s = make();
      await s.init();
      expect(await s.getAll(), isEmpty);
      indexFile.writeAsStringSync('   \n');
      final empty = make();
      await empty.init();
      expect(await empty.getAll(), isEmpty);
      indexFile.writeAsStringSync('{ not json');
      final corrupt = make();
      await corrupt.init();
      expect(await corrupt.getAll(), isEmpty);
      indexFile.writeAsStringSync('[1,2,3]');
      final wrongShape = make();
      await wrongShape.init();
      expect(await wrongShape.getAll(), isEmpty);
    });

    test('an index written by one store is read back by another', () async {
      final a = make();
      await a.init();
      await a.put(entry('one'));
      await a.put(entry('two'));
      await a.delete('one');
      await a.flushPending();
      final b = make();
      await b.init();
      expect((await b.getAll()).map((e) => e.key), ['two']);
      expect(await b.get('two'), isNotNull);
      expect(await b.get('one'), isNull);
    });

    test('flushPending with nothing pending does nothing; clear writes an '
        'empty index immediately', () async {
      final s = make();
      await s.init();
      await s.flushPending();
      expect(indexFile.existsSync(), isFalse);
      await s.put(entry('k'));
      await s.clear();
      expect(jsonDecode(indexFile.readAsStringSync()), isEmpty);
      expect(await s.getAll(), isEmpty);
    });

    test('HiveCacheMetadataStore is an alias of the file store', () {
      final HiveCacheMetadataStore s = FileBasedMetadataStore();
      expect(s, isA<FileBasedMetadataStore>());
    });

    testWidgets('the debounce coalesces a burst into one write that lands only '
        'after the full delay', (tester) async {
      final s = make();
      await tester.runAsync(s.init);
      // Called in the fake-async zone so the debounce Timer is fake too.
      await s.put(entry('a'));
      await tester.pump(const Duration(milliseconds: 500));
      await s.put(entry('b'));
      await s.delete('a');
      await tester.pump(const Duration(milliseconds: 1499));
      expect(indexFile.existsSync(), isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await pumpUntil(
        tester,
        () => indexFile.existsSync() && indexFile.lengthSync() > 0,
        reason: 'debounced index write',
      );
      expect((jsonDecode(indexFile.readAsStringSync()) as Map).keys, ['b']);
    });
  });

  group('ZipReader', () {
    test('decodeBytes lists entries with their method, sizes and flags', () {
      final zip = ZipReader.decodeBytes(
        buildZip([
          const TestZipEntry('dir/', []),
          TestZipEntry(
            'dir/a.txt',
            utf8.encode('aaaaaaaaaaaaaaaaaaaa'),
            deflate: true,
          ),
          const TestZipEntry('link', [1], symlink: true),
        ]),
      );
      expect(zip.entries.map((e) => e.name), ['dir/', 'dir/a.txt', 'link']);
      expect(zip.entries[0].isDirectory, isTrue);
      expect(zip.entries[1].isDirectory, isFalse);
      expect(zip.entries[1].compressionMethod, 8);
      expect(zip.entries[1].uncompressedSize, 20);
      expect(zip.entries[2].isSymlink, isTrue);
      expect(zip.entries[1].isSymlink, isFalse);
    });

    test('readBytes handles stored and deflated entries and empty content', () {
      final zip = ZipReader.decodeBytes(
        buildZip([
          const TestZipEntry('stored', [1, 2, 3]),
          TestZipEntry('deflated', List<int>.filled(1000, 9), deflate: true),
          const TestZipEntry('empty', []),
        ]),
      );
      expect(zip.readBytes(zip.entries[0]), [1, 2, 3]);
      expect(zip.readBytes(zip.entries[1]), List<int>.filled(1000, 9));
      expect(zip.readBytes(zip.entries[2]), isEmpty);
    });

    test('an unsupported compression method is a FormatException', () {
      final zip = ZipReader.decodeBytes(
        buildZip([
          const TestZipEntry('x', [1], method: 99),
        ]),
      );
      expect(() => zip.readBytes(zip.entries.single), throwsFormatException);
    });

    test('a corrupted local header offset is a FormatException', () {
      final bytes = buildZip([
        const TestZipEntry('x', [1, 2]),
      ]);
      bytes[0] = 0;
      final zip = ZipReader.decodeBytes(bytes);
      expect(() => zip.readBytes(zip.entries.single), throwsFormatException);
    });

    test('non-zip, empty and tiny buffers are rejected', () {
      for (final b in [
        Uint8List(0),
        Uint8List(21),
        Uint8List.fromList(List.filled(100, 7)),
      ]) {
        expect(() => ZipReader.decodeBytes(b), throwsFormatException);
      }
    });

    test('an archive with a trailing comment is still found', () {
      final zip = ZipReader.decodeBytes(
        buildZip([
          const TestZipEntry('x', [1]),
        ], commentLength: 500),
      );
      expect(zip.entries.single.name, 'x');
    });

    test('an empty archive has no entries', () {
      expect(ZipReader.decodeBytes(buildZip([])).entries, isEmpty);
    });

    group('listEntries', () {
      late Directory tempDir;
      setUp(() => tempDir = Directory.systemTemp.createTempSync('zip_list'));
      tearDown(() => tempDir.deleteSync(recursive: true));

      test('reads entries from the file tail', () async {
        final f = File('${tempDir.path}/a.zip')
          ..writeAsBytesSync(
            buildZip([
              const TestZipEntry('a', [1]),
              const TestZipEntry('b', [2]),
            ]),
          );
        expect((await ZipReader.listEntries(f)).map((e) => e.name), ['a', 'b']);
      });

      test('handles a central directory larger than the tail window', () async {
        final entries = [
          for (var i = 0; i < 1500; i++)
            TestZipEntry('${'n' * 60}_$i.txt', const [1]),
        ];
        final bytes = buildZip(entries, commentLength: 65535);
        final f = File('${tempDir.path}/big.zip')..writeAsBytesSync(bytes);
        final listed = await ZipReader.listEntries(f);
        expect(listed, hasLength(1500));
        expect(listed.last.name, '${'n' * 60}_1499.txt');
      });

      test('rejects a non-zip file and a missing file', () async {
        final f = File('${tempDir.path}/bad')
          ..writeAsBytesSync(List.filled(200, 3));
        await expectLater(ZipReader.listEntries(f), throwsFormatException);
        await expectLater(
          ZipReader.listEntries(File('${tempDir.path}/missing')),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('an empty file is rejected', () async {
        final f = File('${tempDir.path}/empty')..writeAsBytesSync([]);
        await expectLater(ZipReader.listEntries(f), throwsFormatException);
      });
    });
  });
}
