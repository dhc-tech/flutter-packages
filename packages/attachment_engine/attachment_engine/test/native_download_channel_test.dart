// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine/src/download/download_manager.dart';
import 'package:attachment_engine/src/native/native_download_channel.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stand-in for a platform implementation: these tests only
/// exercise pure destination-path sanitization logic, not actual downloads,
/// so only [downloadEvents] (invoked eagerly by the constructor) needs a
/// real implementation.
class _FakeDownloadPlatform extends AttachmentEnginePlatform {
  @override
  Stream<Map<Object?, Object?>> downloadEvents() =>
      const Stream<Map<Object?, Object?>>.empty();
}

/// A fuller fake: starts a download (returning a fixed id) and records
/// cancelDownload() calls, but — deliberately, matching a real platform
/// implementation with no guaranteed event-after-cancel contract — never
/// emits any event on [downloadEvents] for it.
class _NeverEmitsEventPlatform extends AttachmentEnginePlatform {
  final List<String> cancelledIds = [];

  @override
  Stream<Map<Object?, Object?>> downloadEvents() =>
      const Stream<Map<Object?, Object?>>.empty();

  @override
  Future<String> startDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) async => 'download-1';

  @override
  Future<void> cancelDownload(String downloadId) async {
    cancelledIds.add(downloadId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AttachmentEnginePlatform.instance = _FakeDownloadPlatform();

  group('NativeDownloadClient destination sanitization', () {
    late NativeDownloadClient client;

    setUp(() {
      client = NativeDownloadClient(tempDirPath: '/tmp/test');
    });

    tearDown(() {
      client.dispose();
    });

    test('strips path-traversal sequences from destination hints', () {
      final path = client.destPathForTesting('../../etc/passwot');
      expect(path.contains('..'), isFalse);
      expect(path.startsWith('/tmp/test/'), isTrue);
    });

    test('strips null-byte-like and unsafe characters', () {
      final path = client.destPathForTesting('evil name/../x');
      final suffix = path.substring(path.lastIndexOf('attachment_engine_dl_'));
      expect(suffix.contains(' '), isFalse);
      expect(suffix.contains('/'), isFalse);
      expect(suffix.contains('..'), isFalse);
    });

    test('bounds extremely long destination hints', () {
      final longHint = 'a' * 5000;
      final path = client.destPathForTesting(longHint);
      expect(path.length, lessThan(200));
    });

    test('falls back to a timestamped path when no hint is given', () {
      final a = client.destPathForTesting(null);
      expect(a, contains('attachment_engine_dl_'));
    });
  });

  group('NativeDownloadClient cancel', () {
    test('cancel() resolves the pending download immediately with '
        'DownloadCancelledException, even when no corresponding event ever '
        'arrives on downloadEvents()', () async {
      final platform = _NeverEmitsEventPlatform();
      AttachmentEnginePlatform.instance = platform;
      final cancelClient = NativeDownloadClient(tempDirPath: '/tmp/test');
      addTearDown(cancelClient.dispose);

      final cancelToken = cancelClient.createCancelToken();
      final future = cancelClient.download(
        'https://example.com/f.bin',
        cancelToken: cancelToken,
      );

      // Give download() a moment to actually call startDownload() and
      // register the cancel token's downloadId, before cancelling.
      await Future<void>.delayed(Duration.zero);
      cancelClient.cancel(cancelToken);

      await expectLater(
        () => future,
        throwsA(isA<DownloadCancelledException>()),
      );
      expect(platform.cancelledIds, ['download-1']);

      // Restore the platform used by the rest of this file's tests.
      AttachmentEnginePlatform.instance = _FakeDownloadPlatform();
    });
  });
}
