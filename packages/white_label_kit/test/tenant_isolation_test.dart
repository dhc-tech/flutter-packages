// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Mandatory build-time isolation proof (see README "Build-time tenant
// isolation" / the acceptance criteria this package was built against):
//
//   Build tenant A => A's assets are present, B's are absent.
//   Build tenant B => B's assets are present, A's are absent.
//   Build A again after B => no stale B asset survives (A→B→A staleness).
//
// Uses a real temp directory on disk (not mocks) so the proof is about
// actual files in an actual staging directory, not an in-memory illusion.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'white_label_isolation_test_',
    );

    _writeTenant(
      projectRoot,
      id: 'acme',
      logoContent: 'ACME_LOGO_BYTES',
      iconContent: 'ACME_ICON_BYTES',
    );
    _writeTenant(
      projectRoot,
      id: 'beta',
      logoContent: 'BETA_LOGO_BYTES',
      iconContent: 'BETA_ICON_BYTES',
    );

    File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync('''
white_label:
  default_tenant: acme
  tenants:
    acme:
      name: "Acme"
      android:
        application_id: "com.example.acme"
        app_name: "Acme"
      ios:
        bundle_id: "com.example.acme"
        app_name: "Acme"
      assets:
        logo: "tenants/acme/assets/logo.png"
        icon: "tenants/acme/assets/icon.png"
    beta:
      name: "Beta"
      android:
        application_id: "com.example.beta"
        app_name: "Beta"
      ios:
        bundle_id: "com.example.beta"
        app_name: "Beta"
      assets:
        logo: "tenants/beta/assets/logo.png"
        icon: "tenants/beta/assets/icon.png"
''');
  });

  tearDown(() {
    projectRoot.deleteSync(recursive: true);
  });

  test('config parses both tenants with distinct identities', () {
    final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);
    expect(config.tenants.keys, unorderedEquals(['acme', 'beta']));
    expect(config['acme'].android.applicationId, 'com.example.acme');
    expect(config['beta'].android.applicationId, 'com.example.beta');
  });

  test('default tenant is always resolvable and clearly marked', () {
    final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);

    expect(config.defaultTenant, 'acme');
    expect(config.isDefault('acme'), isTrue);
    expect(config.isDefault('beta'), isFalse);

    // No --tenant given: must resolve to the declared default, never a
    // silent guess (e.g. "first key in the map").
    expect(config.resolve().id, 'acme');
    expect(config.defaultTenantConfig.id, 'acme');

    // Explicit tenant always wins over the default.
    expect(config.resolve('beta').id, 'beta');
  });

  test('building tenant A stages only A assets, never B', () {
    final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);
    final stager = TenantStager(projectRoot.path);

    stager.stage(config['acme']);

    final List<String> acmeAssets = stager.stagedAssetNames('acme');
    expect(acmeAssets, containsAll(['logo.png', 'icon.png']));

    final String acmeLogo = File(
      p.join(stager.stagingDirFor('acme'), 'assets', 'logo.png'),
    ).readAsStringSync();
    expect(acmeLogo, 'ACME_LOGO_BYTES');

    // The hard requirement: nothing beta-flavored anywhere in A's staging
    // output, and B's staging directory doesn't even exist yet.
    expect(
      acmeAssets.any((name) => name.toLowerCase().contains('beta')),
      isFalse,
    );
    expect(Directory(stager.stagingDirFor('beta')).existsSync(), isFalse);
  });

  test('building tenant B stages only B assets, never A', () {
    final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);
    final stager = TenantStager(projectRoot.path);

    stager.stage(config['beta']);

    final String betaLogo = File(
      p.join(stager.stagingDirFor('beta'), 'assets', 'logo.png'),
    ).readAsStringSync();
    expect(betaLogo, 'BETA_LOGO_BYTES');
    expect(Directory(stager.stagingDirFor('acme')).existsSync(), isFalse);
  });

  test('A -> B -> A: no stale asset survives across repeated builds', () {
    final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);
    final stager = TenantStager(projectRoot.path);

    stager.stage(config['acme']);
    stager.stage(config['beta']);
    stager.stage(config['acme']);

    // Prove A's re-stage is genuinely A again, byte-for-byte — not a stale
    // leftover from the B build that happened in between.
    final String acmeLogo = File(
      p.join(stager.stagingDirFor('acme'), 'assets', 'logo.png'),
    ).readAsStringSync();
    expect(acmeLogo, 'ACME_LOGO_BYTES');
    expect(stager.stagedAssetNames('acme'), ['icon.png', 'logo.png']);

    // B's staging directory from the middle step is untouched by the final
    // A stage — each tenant's staging output is independent.
    final String betaLogo = File(
      p.join(stager.stagingDirFor('beta'), 'assets', 'logo.png'),
    ).readAsStringSync();
    expect(betaLogo, 'BETA_LOGO_BYTES');
  });

  test(
    'validation rejects a tenant asset path that escapes its own directory',
    () {
      File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync('''
white_label:
  default_tenant: acme
  tenants:
    acme:
      name: "Acme"
      android:
        application_id: "com.example.acme"
        app_name: "Acme"
      ios:
        bundle_id: "com.example.acme"
        app_name: "Acme"
      assets:
        logo: "tenants/beta/assets/logo.png"
''');

      expect(
        () => WhiteLabelConfig.load(projectRoot.path),
        throwsA(
          isA<WhiteLabelConfigException>().having(
            (e) => e.errors.join('\n'),
            'errors',
            contains('must live under tenants/acme/'),
          ),
        ),
      );
    },
  );
}

void _writeTenant(
  Directory projectRoot, {
  required String id,
  required String logoContent,
  required String iconContent,
}) {
  final dir = Directory(p.join(projectRoot.path, 'tenants', id, 'assets'))
    ..createSync(recursive: true);
  File(p.join(dir.path, 'logo.png')).writeAsStringSync(logoContent);
  File(p.join(dir.path, 'icon.png')).writeAsStringSync(iconContent);
}
