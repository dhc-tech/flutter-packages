// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Verifies generateIconsAndSplash (lib/src/generation/icon_splash_generator.dart)
// WITHOUT actually invoking icons_launcher/flutter_native_splash (neither is
// a dependency of this package's test suite) — the point of these tests is
// the skip-if-not-configured contract and the register_launch_screen.rb
// wiring, not the underlying generators' own behavior.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'icon_splash_generator_test_',
    );
  });

  tearDown(() => projectRoot.deleteSync(recursive: true));

  test('skips both steps silently (no error) when neither config file exists — '
      'a consumer who has not set up icons_launcher/flutter_native_splash for '
      'this tenant is never forced into either dependency', () {
    final IconSplashResult result = generateIconsAndSplash(
      'acme',
      projectRoot: projectRoot.path,
    );

    expect(result.iconsRan, isFalse);
    expect(result.splashRan, isFalse);
    expect(result.launchScreenRegistered, isFalse);
    expect(result.iconsError, isNull);
    expect(result.splashError, isNull);
    expect(result.hasError, isFalse);
  });

  test('reports an error (not a crash) when icons_launcher-<tenant>.yaml '
      'exists but the icons_launcher package cannot actually run', () {
    File(p.join(projectRoot.path, 'icons_launcher-acme.yaml'))
        .writeAsStringSync(
          'icons_launcher:\n  image_path: "does_not_matter.png"\n',
        );

    // No pubspec.yaml / icons_launcher dependency in this bare temp dir,
    // so `dart run icons_launcher:create` is guaranteed to fail to
    // resolve — exactly the "consumer hasn't added the dependency"
    // scenario this function must degrade gracefully for.
    final IconSplashResult result = generateIconsAndSplash(
      'acme',
      projectRoot: projectRoot.path,
    );

    expect(result.iconsRan, isFalse);
    expect(result.iconsError, isNotNull);
    expect(result.hasError, isTrue);
    // Splash wasn't configured at all — independent of the icons failure.
    expect(result.splashRan, isFalse);
    expect(result.splashError, isNull);
  });

  test(
    'launchScreenRegistered stays false when the host app has no '
    'tool/register_launch_screen.rb — its absence is expected, not an error',
    () {
      // flutter_native_splash isn't a dependency here either, so splashRan
      // will be false — this test only asserts launchScreenRegistered
      // never flips true without a real successful splash step, and that
      // there's no error/crash just because the script file is missing.
      File(p.join(projectRoot.path, 'flutter_native_splash-acme.yaml'))
          .writeAsStringSync('flutter_native_splash:\n  color: "#ffffff"\n');

      final IconSplashResult result = generateIconsAndSplash(
        'acme',
        projectRoot: projectRoot.path,
      );

      expect(result.launchScreenRegistered, isFalse);
    },
  );
}
