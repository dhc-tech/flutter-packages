// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

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
  });
}
