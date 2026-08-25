// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

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
}
