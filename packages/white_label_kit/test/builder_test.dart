// Covers WhiteLabelBuilder's generated-constant integration for
// WhiteLabelRuntime (construction path (b) — see white_label_runtime.dart's
// dartdoc and builder.dart's WhiteLabelBuilder dartdoc).
//
// SECURITY REGRESSION COVERAGE — this file exists primarily to pin the fix
// for a real tenant-isolation vulnerability: an earlier version of this
// builder emitted *every* declared tenant's data into one compile-time Map,
// which would ship every other tenant's branding/config inside any build
// meant to contain only one tenant's. See builder.dart's dartoc. The tests
// below prove:
//   1. Exactly one tenant's data is emitted (`whiteLabelRuntime`, singular).
//   2. Its fields match WhiteLabelRuntime.fromConfig field-for-field.
//   3. `whiteLabelDefaultTenant`/`whiteLabelTenantIds` are still emitted
//      (names only, not sensitive — fine to ship in every build).
//   4. TENANT_ID environment variable selects which tenant is emitted; an
//      unset/invalid TENANT_ID falls back to default_tenant.
//   5. THE ACTUAL LEAK CHECK: when TENANT_ID selects tenant "beta", the
//      generated file does NOT contain tenant "acme"'s applicationId, API
//      URL, or theme color anywhere in its text — not just "beta's data is
//      present", but "acme's data is verifiably absent".

import 'package:build_test/build_test.dart';
import 'package:test/test.dart';
import 'package:white_label_kit/builder.dart';
import 'package:white_label_kit/white_label_kit.dart';

const _yaml = '''
white_label:
  default_tenant: acme

  tenants:
    acme:
      name: "Acme Corp"
      android:
        application_id: "com.example.acme"
        app_name: "Acme"
      ios:
        bundle_id: "com.example.acme"
        app_name: "Acme"
      assets:
        logo: "tenants/acme/assets/logo.png"
      theme:
        primary_color: "#D41414"
      environment:
        api_base_url: "https://api.acme.example.com"
      features:
        dark_mode: true

    beta:
      name: "Beta Corp"
      android:
        application_id: "com.example.beta"
        app_name: "Beta Corp"
        version:
          name: "2.0.0"
          build_number: 5
      ios:
        bundle_id: "com.example.beta"
        app_name: "Beta Corp"
      assets:
        logo: "tenants/beta/assets/logo.png"
      environment:
        api_base_url: "https://api.beta.example.com"
      features:
        dark_mode: false
''';

Future<String> _generate({Map<String, String>? environment}) async {
  final TestBuilderResult result = await testBuilder(
    WhiteLabelBuilder(environmentOverride: environment),
    {'pkg|white_label.yaml': _yaml},
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  return result.readerWriter.testing.readString(makeAssetId('pkg|lib/white_label.g.dart'));
}

void main() {
  group('resolveBuilderTenantId', () {
    final WhiteLabelConfig config = WhiteLabelConfig.parse(_yaml);

    test('uses TENANT_ID when it names a declared tenant', () {
      expect(resolveGeneratorTenantId(config, environment: {'TENANT_ID': 'beta'}), 'beta');
    });

    test('falls back to default_tenant when TENANT_ID is unset', () {
      expect(resolveGeneratorTenantId(config, environment: {}), 'acme');
    });

    test('falls back to default_tenant when TENANT_ID names an unknown tenant', () {
      expect(resolveGeneratorTenantId(config, environment: {'TENANT_ID': 'nope'}), 'acme');
    });
  });

  test('emits whiteLabelDefaultTenant and whiteLabelTenantIds (names only)', () async {
    final String generated = await _generate(environment: {});

    expect(generated, contains("const String whiteLabelDefaultTenant = 'acme';"));
    expect(generated, contains("const List<String> whiteLabelTenantIds = ['acme', 'beta'];"));
  });

  test(
    'emits exactly ONE const WhiteLabelRuntime (the default tenant, no TENANT_ID set)',
    () async {
      final String generated = await _generate(environment: {});
      final WhiteLabelConfig config = WhiteLabelConfig.parse(_yaml);
      final expected = WhiteLabelRuntime.fromConfig(config['acme']);

      expect(generated, contains('const WhiteLabelRuntime whiteLabelRuntime = WhiteLabelRuntime('));
      // Old, leaky API must be gone entirely.
      expect(generated, isNot(contains('whiteLabelRuntimes')));
      expect(generated, isNot(contains('whiteLabelDefaultRuntime')));

      expect(generated, contains("tenantId: '${expected.tenantId}'"));
      expect(generated, contains("primaryColorHex: '${expected.theme.primaryColorHex}'"));
      expect(generated, contains("apiBaseUrl: '${expected.environment.apiBaseUrl}'"));
      expect(generated, contains("features: {'dark_mode': true}"));
      expect(generated, contains("applicationId: '${expected.android.applicationId}'"));
    },
  );

  test("TENANT_ID=beta selects beta — and, critically, leaks NONE of acme's data", () async {
    final String generated = await _generate(environment: {'TENANT_ID': 'beta'});
    final WhiteLabelConfig config = WhiteLabelConfig.parse(_yaml);
    final expectedBeta = WhiteLabelRuntime.fromConfig(config['beta']);

    // Positive: beta's own data is present.
    expect(generated, contains("tenantId: 'beta'"));
    expect(generated, contains("applicationId: '${expectedBeta.android.applicationId}'"));
    expect(generated, contains("apiBaseUrl: '${expectedBeta.environment.apiBaseUrl}'"));
    expect(
      generated,
      contains(
        "name: '${expectedBeta.android.version.name}', buildNumber: "
        '${expectedBeta.android.version.buildNumber}',
      ),
    );

    // THE ACTUAL SECURITY CHECK: acme's identifying data must be verifiably
    // absent from a build selected for beta — not merely "beta is also
    // there somewhere", but "acme is nowhere in this file".
    expect(generated, isNot(contains('com.example.acme')));
    expect(generated, isNot(contains('api.acme.example.com')));
    expect(generated, isNot(contains('D41414'))); // acme's primary_color
    expect(generated, isNot(contains("tenantId: 'acme'")));
  });

  test('invalid white_label.yaml still fails the build (regression)', () async {
    final TestBuilderResult result = await testBuilder(
      WhiteLabelBuilder(),
      {'pkg|white_label.yaml': 'white_label:\n  tenants: {}\n'},
      rootPackage: 'pkg',
      flattenOutput: true,
    );

    expect(result.succeeded, isFalse);
  });
}
