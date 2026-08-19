// Default-tenant resolution rules (see WhiteLabelConfig.parse):
//
//   1. Explicit `default_tenant` must name a declared tenant.
//   2. Omitted + exactly one tenant declared -> that tenant is implicitly
//      the default, no error.
//   3. Omitted + multiple tenants declared -> hard validation error with an
//      actionable message.
//   4. `WhiteLabelConfig.resolve('id')` always overrides the default, even
//      when a default exists.
//
// Uses real temp directories on disk (not mocks), matching
// tenant_isolation_test.dart's style.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync('white_label_default_tenant_test_');
  });

  tearDown(() {
    projectRoot.deleteSync(recursive: true);
  });

  test('explicit default_tenant is honored', () {
    _writeTenant(projectRoot, id: 'acme');
    _writeTenant(projectRoot, id: 'beta');
    _writeConfig(projectRoot, '''
white_label:
  default_tenant: beta
  tenants:
${_tenantYaml('acme')}
${_tenantYaml('beta')}
''');

    final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);

    expect(config.defaultTenant, 'beta');
    expect(config.isDefault('beta'), isTrue);
    expect(config.isDefault('acme'), isFalse);
    expect(config.defaultTenantConfig.id, 'beta');
  });

  test('omitted default_tenant + exactly one tenant -> that tenant becomes '
      'the default with no error', () {
    _writeTenant(projectRoot, id: 'acme');
    _writeConfig(projectRoot, '''
white_label:
  tenants:
${_tenantYaml('acme')}
''');

    final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);

    expect(config.defaultTenant, 'acme');
    expect(config.isDefault('acme'), isTrue);
    expect(config.resolve().id, 'acme');
    expect(config.defaultTenantConfig.id, 'acme');
  });

  test('omitted default_tenant + multiple tenants -> throws with an '
      'actionable message', () {
    _writeTenant(projectRoot, id: 'acme');
    _writeTenant(projectRoot, id: 'beta');
    _writeConfig(projectRoot, '''
white_label:
  tenants:
${_tenantYaml('acme')}
${_tenantYaml('beta')}
''');

    expect(
      () => WhiteLabelConfig.load(projectRoot.path),
      throwsA(
        isA<WhiteLabelConfigException>().having(
          (e) => e.errors.join('\n'),
          'errors',
          allOf(contains('Multiple tenants declared'), contains('default_tenant')),
        ),
      ),
    );
  });

  test('default_tenant referencing a nonexistent tenant throws', () {
    _writeTenant(projectRoot, id: 'acme');
    _writeConfig(projectRoot, '''
white_label:
  default_tenant: nope
  tenants:
${_tenantYaml('acme')}
''');

    expect(
      () => WhiteLabelConfig.load(projectRoot.path),
      throwsA(
        isA<WhiteLabelConfigException>().having(
          (e) => e.errors.join('\n'),
          'errors',
          contains('`default_tenant: nope` is not one of the declared tenants.'),
        ),
      ),
    );
  });

  test('WhiteLabelConfig.resolve overrides the default even when a default '
      'exists', () {
    _writeTenant(projectRoot, id: 'acme');
    _writeTenant(projectRoot, id: 'beta');
    _writeConfig(projectRoot, '''
white_label:
  default_tenant: acme
  tenants:
${_tenantYaml('acme')}
${_tenantYaml('beta')}
''');

    final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);

    expect(config.defaultTenant, 'acme');
    expect(config.resolve().id, 'acme');
    expect(config.resolve('beta').id, 'beta');
  });
}

void _writeConfig(Directory projectRoot, String yaml) {
  File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync(yaml);
}

String _tenantYaml(String id) =>
    '''
    $id:
      name: "${id[0].toUpperCase()}${id.substring(1)}"
      android:
        application_id: "com.example.$id"
        app_name: "${id[0].toUpperCase()}${id.substring(1)}"
      ios:
        bundle_id: "com.example.$id"
        app_name: "${id[0].toUpperCase()}${id.substring(1)}"
      assets:
        logo: "tenants/$id/assets/logo.png"''';

void _writeTenant(Directory projectRoot, {required String id}) {
  final dir = Directory(p.join(projectRoot.path, 'tenants', id, 'assets'))
    ..createSync(recursive: true);
  File(p.join(dir.path, 'logo.png')).writeAsStringSync('${id}_LOGO_BYTES');
}
