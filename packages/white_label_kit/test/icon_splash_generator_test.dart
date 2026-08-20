// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Verifies maybeGenerateLauncherIcon/maybeGenerateNativeSplash
// (lib/src/generation/icon_splash_generator.dart) WITHOUT actually invoking
// icons_launcher/flutter_native_splash — the point here is the opt-in
// contract (off unless features.icon_generate/splash_generate is true) and
// the never-overwrite-an-existing-config-file contract.

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
    File(p.join(projectRoot.path, 'tenants/acme/logo.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() => projectRoot.deleteSync(recursive: true));

  const tenantNotOptedIn = TenantConfig(
    id: 'acme',
    name: 'Acme',
    android: AndroidTenantConfig(
      applicationId: 'com.example.acme',
      appName: 'Acme',
    ),
    ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
    assets: TenantAssets(logo: 'tenants/acme/logo.png'),
  );

  const tenantOptedIn = TenantConfig(
    id: 'acme',
    name: 'Acme',
    android: AndroidTenantConfig(
      applicationId: 'com.example.acme',
      appName: 'Acme',
    ),
    ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
    assets: TenantAssets(logo: 'tenants/acme/logo.png'),
    features: {'icon_generate': true, 'splash_generate': true},
  );

  group('maybeGenerateLauncherIcon', () {
    test('returns null (does not run at all) when not opted in', () {
      final result = maybeGenerateLauncherIcon(
        tenantNotOptedIn,
        projectRoot: projectRoot.path,
      );
      expect(result, isNull);
      expect(
        File(p.join(projectRoot.path, 'icons_launcher-acme.yaml')).existsSync(),
        isFalse,
      );
    });

    test(
      'when opted in, auto-creates the config from assets.logo if missing',
      () {
        maybeGenerateLauncherIcon(tenantOptedIn, projectRoot: projectRoot.path);

        final configFile = File(
          p.join(projectRoot.path, 'icons_launcher-acme.yaml'),
        );
        expect(configFile.existsSync(), isTrue);
        expect(
          configFile.readAsStringSync(),
          contains('image_path: "tenants/acme/logo.png"'),
        );
      },
    );

    test('when opted in, never overwrites an already-existing hand-authored '
        'config file', () {
      final configFile = File(
        p.join(projectRoot.path, 'icons_launcher-acme.yaml'),
      )..writeAsStringSync('icons_launcher:\n  image_path: "custom.png"\n');

      maybeGenerateLauncherIcon(tenantOptedIn, projectRoot: projectRoot.path);

      expect(
        configFile.readAsStringSync(),
        contains('image_path: "custom.png"'),
      );
    });

    test('reports an error (not a crash) when opted in but icons_launcher '
        'cannot actually run', () {
      final result = maybeGenerateLauncherIcon(
        tenantOptedIn,
        projectRoot: projectRoot.path,
      );
      expect(result, isNotNull);
      expect(result!.ran, isFalse);
      expect(result.error, isNotNull);
      expect(result.hasError, isTrue);
    });
  });

  group('maybeGenerateNativeSplash', () {
    test('returns null (does not run at all) when not opted in', () {
      final result = maybeGenerateNativeSplash(
        tenantNotOptedIn,
        projectRoot: projectRoot.path,
      );
      expect(result, isNull);
      expect(
        File(p.join(projectRoot.path, 'flutter_native_splash-acme.yaml'))
            .existsSync(),
        isFalse,
      );
    });

    test('when opted in, auto-creates the config from assets.logo and '
        'falls back to white when no theme.primary_color is declared', () {
      maybeGenerateNativeSplash(tenantOptedIn, projectRoot: projectRoot.path);

      final content = File(
        p.join(projectRoot.path, 'flutter_native_splash-acme.yaml'),
      ).readAsStringSync();
      expect(content, contains('image: "tenants/acme/logo.png"'));
      expect(content, contains('color: "#ffffff"'));
    });

    test('when opted in, never overwrites an already-existing hand-authored '
        'config file', () {
      final configFile = File(
        p.join(projectRoot.path, 'flutter_native_splash-acme.yaml'),
      )..writeAsStringSync('flutter_native_splash:\n  color: "#123456"\n');

      maybeGenerateNativeSplash(tenantOptedIn, projectRoot: projectRoot.path);

      expect(configFile.readAsStringSync(), contains('#123456'));
    });
  });
}
