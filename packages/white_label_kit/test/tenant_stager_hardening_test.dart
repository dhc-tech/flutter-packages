// Regression tests for the 3 real bugs an adversarial audit found and this
// package was then fixed against — see TenantStager's class doc for the
// three guarantees these tests each map to.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync('stager_hardening_test_');
  });

  tearDown(() {
    projectRoot.deleteSync(recursive: true);
  });

  test(
    'stage() rejects a hand-built TenantConfig with a path-traversal asset',
    () {
      // Simulates a consumer bypassing WhiteLabelConfig/ConfigValidator
      // entirely by constructing TenantConfig directly (its constructor is
      // public) — stage() must still refuse to copy the file.
      Directory(p.join(projectRoot.path, 'secret_outside')).createSync();
      File(p.join(projectRoot.path, 'secret_outside', 'leak.png'))
          .writeAsStringSync('TOP_SECRET');

      const evil = TenantConfig(
        id: 'acme',
        name: 'Acme',
        android: AndroidTenantConfig(
          applicationId: 'com.example.acme',
          appName: 'Acme',
        ),
        ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
        assets: TenantAssets(logo: '../secret_outside/leak.png'),
      );

      expect(
        () => TenantStager(projectRoot.path).stage(evil),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('stage() is atomic: a failed re-stage leaves the prior good output untouched', () {
    final assetsDir = Directory(
      p.join(projectRoot.path, 'tenants', 'acme', 'assets'),
    )..createSync(recursive: true);
    File(p.join(assetsDir.path, 'logo.png')).writeAsStringSync('LOGO_V1');
    File(p.join(assetsDir.path, 'icon.png')).writeAsStringSync('ICON_V1');

    const tenant = TenantConfig(
      id: 'acme',
      name: 'Acme',
      android: AndroidTenantConfig(
        applicationId: 'com.example.acme',
        appName: 'Acme',
      ),
      ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
      assets: TenantAssets(
        logo: 'tenants/acme/assets/logo.png',
        icon: 'tenants/acme/assets/icon.png',
      ),
    );

    final stager = TenantStager(projectRoot.path);
    stager.stage(tenant); // good state: logo.png + icon.png

    // Remove icon.png so the next stage() fails partway through.
    File(p.join(assetsDir.path, 'icon.png')).deleteSync();

    expect(() => stager.stage(tenant), throwsA(isA<StateError>()));

    // The last-known-good staged output must be exactly as it was — not
    // half-deleted, not partially overwritten.
    expect(stager.stagedAssetNames('acme'), ['icon.png', 'logo.png']);
    expect(
      File(p.join(stager.stagingDirFor('acme'), 'assets', 'logo.png'))
          .readAsStringSync(),
      'LOGO_V1',
    );
  });

  test(
    'stage() rejects two different declared assets that collide on basename',
    () {
      final acmeAssets = Directory(
        p.join(projectRoot.path, 'tenants', 'acme', 'assets'),
      )..createSync(recursive: true);
      final iconSubdir = Directory(
        p.join(projectRoot.path, 'tenants', 'acme', 'icon'),
      )..createSync(recursive: true);
      File(p.join(acmeAssets.path, 'logo.png'))
          .writeAsStringSync('LOGO_CONTENT');
      // Different source file, but same basename as the logo once staged.
      File(p.join(iconSubdir.path, 'logo.png'))
          .writeAsStringSync('ICON_CONTENT_DIFFERENT_FILE');

      const tenant = TenantConfig(
        id: 'acme',
        name: 'Acme',
        android: AndroidTenantConfig(
          applicationId: 'com.example.acme',
          appName: 'Acme',
        ),
        ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
        assets: TenantAssets(
          logo: 'tenants/acme/assets/logo.png',
          icon: 'tenants/acme/icon/logo.png', // collides on basename with logo
        ),
      );

      expect(
        () => TenantStager(projectRoot.path).stage(tenant),
        throwsA(isA<StateError>()),
      );

      // Nothing should have been staged at all — reject before writing.
      expect(TenantStager(projectRoot.path).stagedAssetNames('acme'), isEmpty);
    },
  );
}
