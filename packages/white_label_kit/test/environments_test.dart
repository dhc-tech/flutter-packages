// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Verifies TenantConfig.resolveEnvironment/`environments:`/`custom:`
// (config/tenant_config.dart, config/white_label_config.dart) and the
// `--env` flag's effect on generated output
// (generation/dart_config_generator.dart) — same on-disk-fixture style as
// default_tenant_test.dart.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'white_label_environments_test_',
    );
  });

  tearDown(() => projectRoot.deleteSync(recursive: true));

  test(
    'a tenant with no environments: block resolves to environment for '
    'null AND throws for a named env (nothing declared to pick from)',
    () {
      _writeTenant(projectRoot, id: 'acme');
      _writeConfig(projectRoot, '''
white_label:
  tenants:
${_tenantYaml('acme', apiBaseUrl: 'https://api.example.com')}
''');
      final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);
      final TenantConfig acme = config['acme'];

      expect(acme.resolveEnvironment().apiBaseUrl, 'https://api.example.com');
      expect(acme.resolveEnvironment(null).apiBaseUrl, 'https://api.example.com');
      expect(
        () => acme.resolveEnvironment('staging'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('acme'), contains('staging'), contains('none declared')),
          ),
        ),
      );
    },
  );

  test(
    'environments: staging/production override api_base_url and custom '
    'independently of the default environment: block',
    () {
      _writeTenant(projectRoot, id: 'acme');
      _writeConfig(projectRoot, '''
white_label:
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
      environment:
        api_base_url: "https://api.example.com"
        custom:
          sentry_dsn: "https://default-sentry.example.com"
      environments:
        staging:
          api_base_url: "https://staging-api.example.com"
          custom:
            sentry_dsn: "https://staging-sentry.example.com"
        production:
          api_base_url: "https://prod-api.example.com"
''');
      final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);
      final TenantConfig acme = config['acme'];

      expect(acme.resolveEnvironment().apiBaseUrl, 'https://api.example.com');
      expect(
        acme.resolveEnvironment().custom['sentry_dsn'],
        'https://default-sentry.example.com',
      );

      final TenantEnvironment staging = acme.resolveEnvironment('staging');
      expect(staging.apiBaseUrl, 'https://staging-api.example.com');
      expect(staging.custom['sentry_dsn'], 'https://staging-sentry.example.com');

      final TenantEnvironment production = acme.resolveEnvironment(
        'production',
      );
      expect(production.apiBaseUrl, 'https://prod-api.example.com');
      // production didn't declare its own custom: -- empty, NOT inherited
      // from the default environment: block. Each named environment is a
      // fully independent override, not a partial patch.
      expect(production.custom, isEmpty);
    },
  );

  test(
    'an invalid api_base_url inside environments.<name> is a validation '
    'error, same as the top-level environment: block',
    () {
      _writeTenant(projectRoot, id: 'acme');
      _writeConfig(projectRoot, '''
white_label:
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
      environments:
        staging:
          api_base_url: "not-a-url"
''');
      expect(
        () => WhiteLabelConfig.load(projectRoot.path),
        throwsA(isA<WhiteLabelConfigException>()),
      );
    },
  );

  test(
    'generateWhiteLabelSource bakes the resolved --env environment, not '
    'the default, and records the environment name',
    () {
      _writeTenant(projectRoot, id: 'acme');
      _writeConfig(projectRoot, '''
white_label:
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
      environment:
        api_base_url: "https://api.example.com"
      environments:
        staging:
          api_base_url: "https://staging-api.example.com"
          custom:
            sentry_dsn: "https://staging-sentry.example.com"
''');
      final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);

      final String defaultSource = generateWhiteLabelSource(config, 'acme');
      expect(defaultSource, contains("apiBaseUrl: 'https://api.example.com'"));
      expect(defaultSource, contains("whiteLabelEnvironmentName = '';"));

      final String stagingSource = generateWhiteLabelSource(
        config,
        'acme',
        envName: 'staging',
      );
      expect(
        stagingSource,
        contains("apiBaseUrl: 'https://staging-api.example.com'"),
      );
      expect(
        stagingSource,
        contains("sentry_dsn': 'https://staging-sentry.example.com'"),
      );
      expect(stagingSource, contains("whiteLabelEnvironmentName = 'staging';"));
    },
  );

  test(
    'generateWhiteLabelSource throws ArgumentError for an undeclared --env',
    () {
      _writeTenant(projectRoot, id: 'acme');
      _writeConfig(projectRoot, '''
white_label:
  tenants:
${_tenantYaml('acme')}
''');
      final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);

      expect(
        () => generateWhiteLabelSource(config, 'acme', envName: 'staging'),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}

void _writeConfig(Directory projectRoot, String yaml) {
  File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync(yaml);
}

String _tenantYaml(String id, {String? apiBaseUrl}) {
  final String name = '${id[0].toUpperCase()}${id.substring(1)}';
  final String envBlock = apiBaseUrl == null
      ? ''
      : '\n      environment:\n        api_base_url: "$apiBaseUrl"';
  return '''
    $id:
      name: "$name"
      android:
        application_id: "com.example.$id"
        app_name: "$name"
      ios:
        bundle_id: "com.example.$id"
        app_name: "$name"
      assets:
        logo: "tenants/$id/assets/logo.png"$envBlock''';
}

void _writeTenant(Directory projectRoot, {required String id}) {
  final dir = Directory(p.join(projectRoot.path, 'tenants', id, 'assets'))
    ..createSync(recursive: true);
  File(p.join(dir.path, 'logo.png')).writeAsStringSync('${id}_LOGO_BYTES');
}
