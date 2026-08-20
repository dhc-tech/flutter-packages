// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Verifies generateNativeSplash (lib/src/generation/icon_splash_generator.dart)
// WITHOUT actually invoking flutter_native_splash — the point of these
// tests is the auto-derivation from TenantConfig.assets/theme, the
// generated yaml's shape, the opt-out flag, and graceful degradation, not
// the underlying generator's own image processing.

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

  const tenant = TenantConfig(
    id: 'acme',
    name: 'Acme',
    android: AndroidTenantConfig(
      applicationId: 'com.example.acme',
      appName: 'Acme',
    ),
    ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
    assets: TenantAssets(logo: 'tenants/acme/logo.png'),
    theme: TenantTheme(primaryColor: '#123456'),
  );

  test('skips silently when the declared splash/icon/logo file does not '
      'exist on disk yet', () {
    final NativeSplashResult result = generateNativeSplash(
      tenant,
      projectRoot: projectRoot.path,
    );

    expect(result.ran, isFalse);
    expect(result.error, isNull);
    expect(result.skippedReason, isNotNull);
    expect(result.hasError, isFalse);
  });

  test('skips with a clear reason when features.native_splash is explicitly '
      'false — the opt-out for a tenant with its own hand-crafted splash', () {
    File(p.join(projectRoot.path, 'tenants/acme/logo.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    const optedOut = TenantConfig(
      id: 'acme',
      name: 'Acme',
      android: AndroidTenantConfig(
        applicationId: 'com.example.acme',
        appName: 'Acme',
      ),
      ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
      assets: TenantAssets(logo: 'tenants/acme/logo.png'),
      features: {'native_splash': false},
    );

    final NativeSplashResult result = generateNativeSplash(
      optedOut,
      projectRoot: projectRoot.path,
    );

    expect(result.ran, isFalse);
    expect(result.hasError, isFalse);
    expect(result.skippedReason, contains('native_splash'));
    // No config file should even be written when opted out.
    expect(
      File(p.join(projectRoot.path, 'flutter_native_splash-acme.yaml'))
          .existsSync(),
      isFalse,
    );
  });

  test('writes a flutter_native_splash-<tenant>.yaml derived from '
      'assets.logo and theme.primaryColor when no dedicated splash/icon is '
      'declared', () {
    File(p.join(projectRoot.path, 'tenants/acme/logo.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    // No pubspec.yaml / flutter_native_splash dependency in this bare
    // temp dir, so the actual `dart run flutter_native_splash:create`
    // call will fail — but the config file must still be written first,
    // and that's what this test checks.
    generateNativeSplash(tenant, projectRoot: projectRoot.path);

    final String content = File(
      p.join(projectRoot.path, 'flutter_native_splash-acme.yaml'),
    ).readAsStringSync();
    expect(content, contains('image: "tenants/acme/logo.png"'));
    expect(content, contains('color: "#123456"'));
    expect(content, contains('android_12:'));
  });

  test('falls back to white (#ffffff) when the tenant declares no '
      'theme.primaryColor', () {
    File(p.join(projectRoot.path, 'tenants/acme/logo.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    const noTheme = TenantConfig(
      id: 'acme',
      name: 'Acme',
      android: AndroidTenantConfig(
        applicationId: 'com.example.acme',
        appName: 'Acme',
      ),
      ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
      assets: TenantAssets(logo: 'tenants/acme/logo.png'),
    );

    generateNativeSplash(noTheme, projectRoot: projectRoot.path);

    final String content = File(
      p.join(projectRoot.path, 'flutter_native_splash-acme.yaml'),
    ).readAsStringSync();
    expect(content, contains('color: "#ffffff"'));
  });

  test('prefers assets.splash over assets.icon/assets.logo when declared', () {
    const withSplash = TenantConfig(
      id: 'acme',
      name: 'Acme',
      android: AndroidTenantConfig(
        applicationId: 'com.example.acme',
        appName: 'Acme',
      ),
      ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
      assets: TenantAssets(
        logo: 'tenants/acme/logo.png',
        icon: 'tenants/acme/icon.png',
        splash: 'tenants/acme/splash.png',
      ),
    );
    File(p.join(projectRoot.path, 'tenants/acme/splash.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    generateNativeSplash(withSplash, projectRoot: projectRoot.path);

    final String content = File(
      p.join(projectRoot.path, 'flutter_native_splash-acme.yaml'),
    ).readAsStringSync();
    expect(content, contains('image: "tenants/acme/splash.png"'));
  });

  test('merges the tenant\'s raw native_splash: overrides over the '
      'auto-derived defaults, without dropping the un-overridden keys in '
      'the same nested map — every real flutter_native_splash option is '
      'reachable from white_label.yaml this way', () {
    const tenantWithOverrides = TenantConfig(
      id: 'acme',
      name: 'Acme',
      android: AndroidTenantConfig(
        applicationId: 'com.example.acme',
        appName: 'Acme',
      ),
      ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
      assets: TenantAssets(logo: 'tenants/acme/logo.png'),
      theme: TenantTheme(splashColor: '#123456'),
      nativeSplashOverrides: {
        'fullscreen': true,
        'android_12': {'icon_background_color': '#111111'},
      },
    );
    File(p.join(projectRoot.path, 'tenants/acme/logo.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    generateNativeSplash(tenantWithOverrides, projectRoot: projectRoot.path);

    final String content = File(
      p.join(projectRoot.path, 'flutter_native_splash-acme.yaml'),
    ).readAsStringSync();
    // The override itself made it in.
    expect(content, contains('fullscreen: true'));
    expect(content, contains('icon_background_color: "#111111"'));
    // The auto-derived keys in the SAME nested map (android_12) survived
    // the merge — this is the "merge, don't replace" contract.
    expect(content, contains('color: "#123456"'));
    expect(content, contains('image: "tenants/acme/logo.png"'));
  });

  test('reports an error (not a crash) when an image source exists but '
      'flutter_native_splash cannot actually run', () {
    File(p.join(projectRoot.path, 'tenants/acme/logo.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    final NativeSplashResult result = generateNativeSplash(
      tenant,
      projectRoot: projectRoot.path,
    );

    expect(result.ran, isFalse);
    expect(result.error, isNotNull);
    expect(result.hasError, isTrue);
    expect(result.launchScreenRegistered, isFalse);
    expect(result.skippedReason, isNull);
  });
}
