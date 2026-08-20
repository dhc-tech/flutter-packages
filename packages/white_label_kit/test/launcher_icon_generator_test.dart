// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Verifies generateLauncherIcon (lib/src/generation/launcher_icon_generator.dart)
// WITHOUT actually invoking icons_launcher (not a dev dependency invoked
// from a bare temp dir in these tests) — the point here is the
// auto-derivation from TenantConfig.assets, the generated yaml's shape,
// and graceful degradation, not the underlying generator's own image
// processing.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'launcher_icon_generator_test_',
    );
  });

  tearDown(() => projectRoot.deleteSync(recursive: true));

  const tenantNoAssets = TenantConfig(
    id: 'acme',
    name: 'Acme',
    android: AndroidTenantConfig(
      applicationId: 'com.example.acme',
      appName: 'Acme',
    ),
    ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
    assets: TenantAssets(logo: 'tenants/acme/logo.png'),
  );

  test('skips silently when the declared logo/icon file does not exist on '
      'disk yet — most tenants will not have real brand assets checked in '
      'from day one', () {
    final LauncherIconResult result = generateLauncherIcon(
      tenantNoAssets,
      projectRoot: projectRoot.path,
    );

    expect(result.ran, isFalse);
    expect(result.error, isNull);
    expect(result.skippedReason, isNotNull);
    expect(result.hasError, isFalse);
  });

  test('falls back to assets.logo when assets.icon is not declared, and '
      'writes an icons_launcher-<tenant>.yaml derived from it — including '
      'the Android notification icon, not just the launcher icon', () {
    final logoFile = File(p.join(projectRoot.path, 'tenants/acme/logo.png'))
      ..createSync(recursive: true);
    logoFile.writeAsBytesSync([1, 2, 3]);

    // No pubspec.yaml / icons_launcher dependency in this bare temp dir,
    // so the actual `dart run icons_launcher:create` call will fail — but
    // the config file must still be written first, and that's what this
    // test checks.
    generateLauncherIcon(tenantNoAssets, projectRoot: projectRoot.path);

    final configFile = File(
      p.join(projectRoot.path, 'icons_launcher-acme.yaml'),
    );
    expect(configFile.existsSync(), isTrue);
    final String content = configFile.readAsStringSync();
    expect(content, contains('image_path: "tenants/acme/logo.png"'));
    expect(content, contains('notification_image: "tenants/acme/logo.png"'));
    expect(content, contains('android:'));
    expect(content, contains('ios:'));
  });

  test('prefers assets.icon over assets.logo when both are declared', () {
    const tenantWithIcon = TenantConfig(
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
      ),
    );
    File(p.join(projectRoot.path, 'tenants/acme/icon.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    generateLauncherIcon(tenantWithIcon, projectRoot: projectRoot.path);

    final String content = File(
      p.join(projectRoot.path, 'icons_launcher-acme.yaml'),
    ).readAsStringSync();
    expect(content, contains('image_path: "tenants/acme/icon.png"'));
    expect(content, contains('notification_image: "tenants/acme/icon.png"'));
  });

  test('reports an error (not a crash) when an icon source exists but '
      'icons_launcher cannot actually run', () {
    File(p.join(projectRoot.path, 'tenants/acme/logo.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    final LauncherIconResult result = generateLauncherIcon(
      tenantNoAssets,
      projectRoot: projectRoot.path,
    );

    expect(result.ran, isFalse);
    expect(result.error, isNotNull);
    expect(result.hasError, isTrue);
    expect(result.skippedReason, isNull);
  });
}
