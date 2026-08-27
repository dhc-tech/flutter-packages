// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [DownloadClient] so download tests never touch the network.
class FakeDownloadClient implements DownloadClient {
  FakeDownloadClient({this.failuresBeforeSuccess = 0, this.bytes});

  int failuresBeforeSuccess;
  int callCount = 0;
  Uint8List? bytes;
  final List<bool> resumeFlagsByCall = [];

  @override
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  }) async {
    callCount++;
    resumeFlagsByCall.add(resume);
    onProgress?.call(const DownloadProgress(received: 5, total: 10));
    if (callCount <= failuresBeforeSuccess) {
      throw Exception('simulated network failure');
    }
    return bytes ?? Uint8List.fromList([1, 2, 3]);
  }

  @override
  Object createCancelToken() => Object();

  @override
  void cancel(Object cancelToken) {}
}

/// Fake client whose `download()` for a given URL only resolves once a
/// per-URL gate (if one is registered) is completed — for tests that need
/// to hold a download "in flight" deliberately.
class _GatedDownloadClient implements DownloadClient {
  final Map<String, Completer<void>> gates = {};
  final List<String> startedUrls = [];

  @override
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  }) async {
    startedUrls.add(url);
    final gate = gates[url];
    if (gate != null) await gate.future;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Object createCancelToken() => Object();

  @override
  void cancel(Object cancelToken) {}
}

void main() {
  group('DownloadManager', () {
    test('returns bytes from the injected fake client on first try', () async {
      final client = FakeDownloadClient();
      final manager = DownloadManager(client: client);

      final result = await manager.download('key', 'https://example.com/f.bin');

      expect(result.bytes, [1, 2, 3]);
      expect(client.callCount, 1);
    });

    test('retries up to maxRetries on failure before succeeding', () async {
      final client = FakeDownloadClient(failuresBeforeSuccess: 2);
      final manager = DownloadManager(client: client, maxRetries: 5);

      final result = await manager.download('key', 'https://example.com/f.bin');

      expect(result.bytes, [1, 2, 3]);
      expect(client.callCount, 3);
    });

    test('throws after exceeding maxRetries', () async {
      final client = FakeDownloadClient(failuresBeforeSuccess: 10);
      final manager = DownloadManager(client: client, maxRetries: 2);

      await expectLater(
        () => manager.download('key', 'https://example.com/f.bin'),
        throwsA(isA<Exception>()),
      );
    });

    test('emits progress updates on the progress stream', () async {
      final client = FakeDownloadClient();
      final manager = DownloadManager(client: client);

      final progressFuture = manager.progressStream('key').first;
      await manager.download('key', 'https://example.com/f.bin');

      final progress = await progressFuture;
      expect(progress.received, 5);
      expect(progress.total, 10);
    });

    test('retries pass resume: true from the second attempt onward', () async {
      final client = FakeDownloadClient(failuresBeforeSuccess: 2);
      final manager = DownloadManager(client: client, maxRetries: 5);

      await manager.download('key', 'https://example.com/f.bin');

      expect(client.resumeFlagsByCall, [false, true, true]);
    });

    test('cancelling a still-queued (not yet running) download prevents it '
        'from ever actually starting', () async {
      final client = _GatedDownloadClient();
      final manager = DownloadManager(
        client: client,
        config: const DownloadConfig(maxConcurrentDownloads: 1),
      );
      final gateA = Completer<void>();
      client.gates['https://example.com/a'] = gateA;

      // Occupies the only concurrency slot, blocked on gateA.
      final futureA = manager.download('a', 'https://example.com/a');
      await Future<void>.delayed(Duration.zero); // let A actually start

      // b is queued behind the single slot — never gets to run yet.
      final futureB = manager.download('b', 'https://example.com/b');
      // Marks the future's eventual rejection as "handled" for zone
      // purposes right away — Futures support multiple independent
      // listeners, so the expectLater below still sees the same error;
      // this just avoids it being reported as an unhandled zone error in
      // the gap before expectLater gets to it.
      futureB.ignore();
      await Future<void>.delayed(Duration.zero);

      manager.cancel('b');

      gateA.complete();
      await futureA;

      await expectLater(
        () => futureB,
        throwsA(isA<DownloadCancelledException>()),
      );
      // 'b' never actually reached the DownloadClient at all.
      expect(client.startedUrls, ['https://example.com/a']);
    });

    test('a key\'s progress controller is closed/replaced once its download '
        'completes, instead of being kept forever', () async {
      final client = FakeDownloadClient();
      final manager = DownloadManager(client: client);

      final streamBefore = manager.progressStream('key');
      await manager.download('key', 'https://example.com/f.bin');
      final streamAfter = manager.progressStream('key');

      // Different Stream instances mean a fresh StreamController was
      // created for the second call — the first one was removed/closed
      // by download()'s cleanup rather than being reused indefinitely.
      expect(identical(streamBefore, streamAfter), isFalse);
    });
  });
}
