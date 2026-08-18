// Regression test for a real defect found by an independent audit: a
// symlink placed INSIDE a tenant's own asset directory (e.g.
// tenants/acme/assets/logo.png) that points OUTSIDE the tenant tree was
// followed and staged/validated without rejection — a real violation of
// the "never anything outside tenants/<id>/" guarantee, reachable by
// anyone who can write into a tenant's own asset directory (not via
// white_label.yaml alone, but still a real bypass of the stated contract).
//
// Fixed in ConfigValidator.assetPath: when projectRoot is given, the
// existence check now also resolves symlinks and rejects a target that
// escapes the tenant directory, instead of only checking File.existsSync().

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync('symlink_escape_test_');
  });

  tearDown(() => projectRoot.deleteSync(recursive: true));

  test('assetPath rejects a symlink inside the tenant dir that escapes it', () {
    final secretDir = Directory(p.join(projectRoot.path, 'secret_outside'))
      ..createSync(recursive: true);
    final secret = File(p.join(secretDir.path, 'leak.png'))
      ..writeAsStringSync('TOP_SECRET_BYTES_OUTSIDE_TENANT_TREE');

    final assetsDir = Directory(
      p.join(projectRoot.path, 'tenants', 'acme', 'assets'),
    )..createSync(recursive: true);
    final linkPath = p.join(assetsDir.path, 'logo.png');
    Link(linkPath).createSync(secret.path);

    final result = ConfigValidator.assetPath(
      'tenants/acme/assets/logo.png',
      tenantId: 'acme',
      projectRoot: projectRoot.path,
    );

    expect(result, isA<Invalid>());
    expect((result as Invalid).message, contains('symlink'));
  });

  test('assetPath still accepts a real, non-symlinked file', () {
    final assetsDir = Directory(
      p.join(projectRoot.path, 'tenants', 'acme', 'assets'),
    )..createSync(recursive: true);
    File(p.join(assetsDir.path, 'logo.png')).writeAsStringSync('REAL_LOGO');

    final result = ConfigValidator.assetPath(
      'tenants/acme/assets/logo.png',
      tenantId: 'acme',
      projectRoot: projectRoot.path,
    );

    expect(result, isA<Valid>());
  });

  test('TenantStager.stage() also refuses a symlink-escape asset (defense in depth)', () {
    final secretDir = Directory(p.join(projectRoot.path, 'secret_outside'))
      ..createSync(recursive: true);
    final secret = File(p.join(secretDir.path, 'leak.png'))
      ..writeAsStringSync('TOP_SECRET_BYTES_OUTSIDE_TENANT_TREE');

    final assetsDir = Directory(
      p.join(projectRoot.path, 'tenants', 'acme', 'assets'),
    )..createSync(recursive: true);
    Link(p.join(assetsDir.path, 'logo.png')).createSync(secret.path);

    const tenant = TenantConfig(
      id: 'acme',
      name: 'Acme',
      android: AndroidTenantConfig(
        applicationId: 'com.example.acme',
        appName: 'Acme',
      ),
      ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
      assets: TenantAssets(logo: 'tenants/acme/assets/logo.png'),
    );

    expect(
      () => TenantStager(projectRoot.path).stage(tenant),
      throwsA(isA<StateError>()),
    );
    expect(TenantStager(projectRoot.path).stagedAssetNames('acme'), isEmpty);
  });
}
