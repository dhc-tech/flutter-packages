import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync('tenant_version_test_');
    final dir = Directory(p.join(projectRoot.path, 'tenants', 'acme', 'assets'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'logo.png')).writeAsStringSync('LOGO');
  });

  tearDown(() {
    projectRoot.deleteSync(recursive: true);
  });

  WhiteLabelConfig loadWith(String versionYaml) {
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
$versionYaml
''');
    return WhiteLabelConfig.load(projectRoot.path);
  }

  test('omitted version defaults to 1.0.0+1 for both platforms', () {
    final TenantConfig tenant = loadWith('')['acme'];
    expect(tenant.version.name, '1.0.0');
    expect(tenant.version.buildNumber, 1);
    expect(tenant.androidVersion.combined, '1.0.0+1');
    expect(tenant.iosVersion.combined, '1.0.0+1');
  });

  test('shared version applies to both platforms when no override is set', () {
    final TenantConfig tenant = loadWith('''
      version:
        name: "2.5.0"
        build_number: 7
''')['acme'];
    expect(tenant.androidVersion.combined, '2.5.0+7');
    expect(tenant.iosVersion.combined, '2.5.0+7');
  });

  test('android/ios version overrides are independent of each other and the shared version', () {
    File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync('''
white_label:
  default_tenant: acme
  tenants:
    acme:
      name: "Acme"
      version:
        name: "2.5.0"
        build_number: 7
      android:
        application_id: "com.example.acme"
        app_name: "Acme"
        version:
          name: "2.5.0"
          build_number: 9
      ios:
        bundle_id: "com.example.acme"
        app_name: "Acme"
        version:
          name: "2.4.0"
          build_number: 3
      assets:
        logo: "tenants/acme/assets/logo.png"
''');
    final TenantConfig tenant = WhiteLabelConfig.load(projectRoot.path)['acme'];

    expect(tenant.version.combined, '2.5.0+7', reason: 'shared value unchanged');
    expect(tenant.androidVersion.combined, '2.5.0+9');
    expect(tenant.iosVersion.combined, '2.4.0+3');
  });

  test('invalid semantic version is rejected with an actionable message', () {
    expect(
      () => loadWith('''
      version:
        name: "not-a-version"
        build_number: 1
'''),
      throwsA(
        isA<WhiteLabelConfigException>().having(
          (e) => e.errors.join('\n'),
          'errors',
          contains('MAJOR.MINOR.PATCH'),
        ),
      ),
    );
  });

  test('non-positive build number is rejected', () {
    expect(
      () => loadWith('''
      version:
        name: "1.0.0"
        build_number: 0
'''),
      throwsA(isA<WhiteLabelConfigException>()),
    );
  });
}
