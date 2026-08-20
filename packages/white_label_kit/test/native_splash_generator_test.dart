// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Verifies generateNativeSplash (lib/src/generation/icon_splash_generator.dart)
// WITHOUT actually invoking flutter_native_splash (not a dependency of this
// package's test suite) — the point of these tests is the
// skip-if-not-configured contract and the register_launch_screen.rb
// wiring, not the underlying generator's own behavior.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'native_splash_generator_test_',
    );
  });

  tearDown(() => projectRoot.deleteSync(recursive: true));

  test('skips silently (no error) when flutter_native_splash-<tenant>.yaml '
      'does not exist — a consumer who has not set up flutter_native_splash '
      'for this tenant is never forced into the dependency', () {
    final NativeSplashResult result = generateNativeSplash(
      'acme',
      projectRoot: projectRoot.path,
    );

    expect(result.ran, isFalse);
    expect(result.launchScreenRegistered, isFalse);
    expect(result.error, isNull);
    expect(result.hasError, isFalse);
  });

  test(
    'reports an error (not a crash) when flutter_native_splash-<tenant>.yaml '
    'exists but the flutter_native_splash package cannot actually run',
    () {
      File(p.join(projectRoot.path, 'flutter_native_splash-acme.yaml'))
          .writeAsStringSync('flutter_native_splash:\n  color: "#ffffff"\n');

      // No pubspec.yaml / flutter_native_splash dependency in this bare
      // temp dir, so `dart run flutter_native_splash:create` is guaranteed
      // to fail to resolve — exactly the "consumer hasn't added the
      // dependency" scenario this function must degrade gracefully for.
      final NativeSplashResult result = generateNativeSplash(
        'acme',
        projectRoot: projectRoot.path,
      );

      expect(result.ran, isFalse);
      expect(result.error, isNotNull);
      expect(result.hasError, isTrue);
      expect(result.launchScreenRegistered, isFalse);
    },
  );
}
