// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File indexFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cache_metadata_store_test');
    indexFile = File('${tempDir.path}/index.json');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  CacheEntry entry(String key) {
    final now = DateTime(2026, 1, 1);
    return CacheEntry(
      key: key,
      localPath: '/tmp/$key',
      sizeBytes: 100,
      createdAt: now,
      lastAccessedAt: now,
    );
  }

  /// Reads and parses [indexFile] as the store's JSON index, returning its
  /// keys. Fails the test (via a normal exception) if the file is missing
  /// or empty — callers that expect that state check existsSync() first.
  List<String> keysOnDisk() {
    final content = indexFile.readAsStringSync();
    if (content.trim().isEmpty) return const [];
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    return decoded.keys.toList();
  }

  group('FileBasedMetadataStore debounced flush', () {
    test(
      'put() is visible via get() immediately, before the disk write happens',
      () async {
        final store = FileBasedMetadataStore(
          directoryProvider: () async => tempDir,
          fileName: 'index.json',
          flushDebounce: const Duration(seconds: 30), // never fires in-test
        );
        await store.init();

        await store.put(entry('a'));

        // In-memory correctness holds immediately...
        expect((await store.get('a'))?.key, 'a');
        // ...even though nothing has been written to disk yet (the flush
        // is still pending, debounced).
        expect(indexFile.existsSync(), isFalse);
      },
    );

    test('a burst of put() calls within the debounce window results in a '
        'single disk write covering all of them', () async {
      final store = FileBasedMetadataStore(
        directoryProvider: () async => tempDir,
        fileName: 'index.json',
        flushDebounce: const Duration(milliseconds: 50),
      );
      await store.init();

      // Simulates many tiles in a grid each bumping lastAccessedAt on
      // roughly the same frame.
      for (var i = 0; i < 20; i++) {
        await store.put(entry('key-$i'));
      }
      expect(indexFile.existsSync(), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(indexFile.existsSync(), isTrue);
      expect(keysOnDisk().length, 20);
    });

    test('flushPending() persists immediately without waiting', () async {
      final store = FileBasedMetadataStore(
        directoryProvider: () async => tempDir,
        fileName: 'index.json',
        flushDebounce: const Duration(seconds: 30),
      );
      await store.init();

      await store.put(entry('a'));
      expect(indexFile.existsSync(), isFalse);

      await store.flushPending();

      expect(indexFile.existsSync(), isTrue);
      expect(keysOnDisk(), contains('a'));
    });

    test('clear() flushes immediately, not debounced', () async {
      final store = FileBasedMetadataStore(
        directoryProvider: () async => tempDir,
        fileName: 'index.json',
        flushDebounce: const Duration(seconds: 30),
      );
      await store.init();
      await store.put(entry('a'));
      await store.flushPending();
      expect(keysOnDisk(), contains('a'));

      await store.clear();

      expect(keysOnDisk(), isEmpty);
    });

    test('a later put() within the same debounce window still results in '
        'both entries being persisted (one write covers both)', () async {
      final store = FileBasedMetadataStore(
        directoryProvider: () async => tempDir,
        fileName: 'index.json',
        flushDebounce: const Duration(milliseconds: 80),
      );
      await store.init();

      await store.put(entry('a'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await store.put(entry('b')); // Same debounce window as 'a'.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(keysOnDisk(), containsAll(['a', 'b']));
    });
  });
}
