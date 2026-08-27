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
    tempDir = Directory.systemTemp.createTempSync(
      'attachment_cache_manager_test',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Attachment attachment(String id) => Attachment(
    id: id,
    name: 'file-$id.bin',
    source: AttachmentSource.url('https://example.com/$id'),
  );

  group('AttachmentCacheManager eviction scan avoidance', () {
    test('getAll() is not called at all for writes that stay comfortably '
        'under the size cap (the common case)', () async {
      final store = _CountingStore();
      final manager = AttachmentCacheManager(
        metadataStore: store,
        policy: const CachePolicy(maxTotalSizeBytes: 1000000),
        directoryProvider: () async => tempDir,
      );
      await manager.init();

      for (var i = 0; i < 10; i++) {
        await manager.write(attachment('$i'), Uint8List(100));
      }

      // Exactly one getAll() — the lazy baseline scan on the very first
      // write of the session. None of the following 9 writes should
      // trigger another one, since the running total is now tracked
      // incrementally and stays far under the 1,000,000-byte cap.
      expect(store.getAllCallCount, 1);
    });

    test('getAll() IS called again once a write actually pushes the cache '
        'over its size cap, to determine what to evict', () async {
      final store = _CountingStore();
      final manager = AttachmentCacheManager(
        metadataStore: store,
        policy: const CachePolicy(maxTotalSizeBytes: 250),
        directoryProvider: () async => tempDir,
      );
      await manager.init();

      await manager.write(attachment('a'), Uint8List(100)); // total: 100
      await manager.write(attachment('b'), Uint8List(100)); // total: 200
      expect(store.getAllCallCount, 1); // still under the 250-byte cap

      // This write would push the total to 300, over the 250 cap —
      // eviction must actually run, which needs a real entry list.
      await manager.write(attachment('c'), Uint8List(100));
      expect(store.getAllCallCount, 2);
    });

    test('the running total stays correct across writes and deletions '
        '(clearAttachment), matching a real getAll()-based recount', () async {
      final store = _CountingStore();
      final manager = AttachmentCacheManager(
        metadataStore: store,
        policy: const CachePolicy(maxTotalSizeBytes: 1000000),
        directoryProvider: () async => tempDir,
      );
      await manager.init();

      await manager.write(attachment('a'), Uint8List(100));
      await manager.write(attachment('b'), Uint8List(200));
      await manager.clearAttachment(attachment('a'));
      await manager.write(attachment('c'), Uint8List(50));

      expect(await manager.totalSizeBytes(), 250); // b (200) + c (50)
    });
  });

  group('AttachmentCacheManager offline durability', () {
    test("a newly-cached attachment is found by a fresh manager/store right "
        "away — its metadata isn't left sitting in FileBasedMetadataStore's "
        'debounce window the way a plain LRU-touch update is', () async {
      // A debounce long enough that, if write() relied on it instead of
      // forcing an immediate flush, this test would still be well
      // inside the window by the time it checks — proving the flush is
      // genuinely immediate, not just "fast enough in practice".
      final store = FileBasedMetadataStore(
        directoryProvider: () async => tempDir,
        fileName: 'index.json',
        flushDebounce: const Duration(seconds: 30),
      );
      final manager = AttachmentCacheManager(
        metadataStore: store,
        directoryProvider: () async => tempDir,
      );
      await manager.init();

      final a = attachment('a');
      await manager.write(a, Uint8List.fromList([1, 2, 3]));

      // Simulates an app relaunch: a brand-new store/manager reading
      // the same on-disk index — nothing in memory is shared with the
      // one above.
      final freshStore = FileBasedMetadataStore(
        directoryProvider: () async => tempDir,
        fileName: 'index.json',
      );
      final freshManager = AttachmentCacheManager(
        metadataStore: freshStore,
        directoryProvider: () async => tempDir,
      );
      await freshManager.init();

      expect(await freshManager.lookup(a), isNotNull);
    });
  });
}

/// Wraps a real in-memory-ish store, counting getAll() calls so tests can
/// assert on how often AttachmentCacheManager actually falls back to a
/// full scan.
class _CountingStore implements AttachmentMetadataStore {
  final Map<String, CacheEntry> _entries = {};
  int getAllCallCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<CacheEntry?> get(String key) async => _entries[key];

  @override
  Future<List<CacheEntry>> getAll() async {
    getAllCallCount++;
    return _entries.values.toList();
  }

  @override
  Future<void> put(CacheEntry entry) async => _entries[entry.key] = entry;

  @override
  Future<void> delete(String key) async => _entries.remove(key);

  @override
  Future<void> clear() async => _entries.clear();
}
