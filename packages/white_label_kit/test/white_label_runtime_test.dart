// WhiteLabelRuntime is the public, app-facing runtime API (see its
// dartdoc / lib/white_label_kit.dart's library dartdoc for why it exists
// separately from WhiteLabelConfig/TenantConfig). This covers:
//
//   1. Field mapping from a fully-populated TenantConfig ->
//      WhiteLabelRuntime.fromConfig, including platform version overrides.
//   2. Field mapping when optional TenantConfig values are left at their
//      defaults (no theme/environment/feature overrides declared).
//   3. isFeatureEnabled: true for a declared flag, false for a declared
//      flag set to false, and false (not a throw) for a flag that was
//      never declared at all — see WhiteLabelRuntime.isFeatureEnabled's
//      dartdoc for why "missing == false" was chosen over throwing.

import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  group('WhiteLabelRuntime.fromConfig', () {
    test('maps every field from a fully-populated TenantConfig', () {
      const config = TenantConfig(
        id: 'acme',
        name: 'Acme Corp',
        android: AndroidTenantConfig(
          applicationId: 'com.example.acme',
          appName: 'Acme',
          version: TenantVersion(name: '2.1.0', buildNumber: 9),
        ),
        ios: IosTenantConfig(
          bundleId: 'com.example.acme',
          appName: 'Acme',
          version: TenantVersion(name: '2.0.5', buildNumber: 7),
        ),
        assets: TenantAssets(logo: 'tenants/acme/assets/logo.png'),
        version: TenantVersion(name: '1.5.0', buildNumber: 3),
        theme: TenantTheme(primaryColor: '#D41414', secondaryColor: '#00FF00'),
        environment: TenantEnvironment(
          apiBaseUrl: 'https://api.acme.example.com',
        ),
        features: {'dark_mode': true, 'beta_banner': false},
      );

      final runtime = WhiteLabelRuntime.fromConfig(config);

      expect(runtime.tenantId, 'acme');
      expect(runtime.tenantName, 'Acme Corp');

      expect(runtime.theme.primaryColorHex, '#D41414');
      expect(runtime.theme.secondaryColorHex, '#00FF00');

      expect(runtime.environment.apiBaseUrl, 'https://api.acme.example.com');

      expect(runtime.features, {'dark_mode': true, 'beta_banner': false});

      // Platform-specific overrides win over the shared `version`.
      expect(runtime.android.applicationId, 'com.example.acme');
      expect(runtime.android.appName, 'Acme');
      expect(runtime.android.version.name, '2.1.0');
      expect(runtime.android.version.buildNumber, 9);
      expect(runtime.android.version.combined, '2.1.0+9');

      expect(runtime.ios.bundleId, 'com.example.acme');
      expect(runtime.ios.appName, 'Acme');
      expect(runtime.ios.version.name, '2.0.5');
      expect(runtime.ios.version.buildNumber, 7);
      expect(runtime.ios.version.combined, '2.0.5+7');
    });

    test(
      'falls back to the shared version when no platform override is set',
      () {
        const config = TenantConfig(
          id: 'beta',
          name: 'Beta Corp',
          android: AndroidTenantConfig(
            applicationId: 'com.example.beta',
            appName: 'Beta',
          ),
          ios: IosTenantConfig(bundleId: 'com.example.beta', appName: 'Beta'),
          assets: TenantAssets(logo: 'tenants/beta/assets/logo.png'),
          version: TenantVersion(name: '3.0.0', buildNumber: 42),
        );

        final runtime = WhiteLabelRuntime.fromConfig(config);

        expect(runtime.android.version.combined, '3.0.0+42');
        expect(runtime.ios.version.combined, '3.0.0+42');
      },
    );

    test('leaves theme/environment fields null and features empty when the '
        'TenantConfig declares none', () {
      const config = TenantConfig(
        id: 'plain',
        name: 'Plain',
        android: AndroidTenantConfig(
          applicationId: 'com.example.plain',
          appName: 'Plain',
        ),
        ios: IosTenantConfig(bundleId: 'com.example.plain', appName: 'Plain'),
        assets: TenantAssets(logo: 'tenants/plain/assets/logo.png'),
      );

      final runtime = WhiteLabelRuntime.fromConfig(config);

      expect(runtime.theme.primaryColorHex, isNull);
      expect(runtime.theme.secondaryColorHex, isNull);
      expect(runtime.environment.apiBaseUrl, isNull);
      expect(runtime.features, isEmpty);
    });
  });

  group('WhiteLabelRuntime construction path (a) vs (b)', () {
    test('the const constructor produces a value equal in content to '
        'fromConfig, for use by generated compile-time constants', () {
      const fromLiteral = WhiteLabelRuntime(
        tenantId: 'acme',
        tenantName: 'Acme Corp',
        theme: WhiteLabelTheme(primaryColorHex: '#D41414'),
        environment: WhiteLabelEnvironment(
          apiBaseUrl: 'https://api.acme.example.com',
        ),
        features: {'dark_mode': true},
        android: WhiteLabelAndroidInfo(
          applicationId: 'com.example.acme',
          appName: 'Acme',
          version: WhiteLabelVersion(name: '1.0.0', buildNumber: 1),
        ),
        ios: WhiteLabelIosInfo(
          bundleId: 'com.example.acme',
          appName: 'Acme',
          version: WhiteLabelVersion(name: '1.0.0', buildNumber: 1),
        ),
      );

      const config = TenantConfig(
        id: 'acme',
        name: 'Acme Corp',
        android: AndroidTenantConfig(
          applicationId: 'com.example.acme',
          appName: 'Acme',
        ),
        ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
        assets: TenantAssets(logo: 'tenants/acme/assets/logo.png'),
        theme: TenantTheme(primaryColor: '#D41414'),
        environment: TenantEnvironment(
          apiBaseUrl: 'https://api.acme.example.com',
        ),
        features: {'dark_mode': true},
      );
      final fromConfig = WhiteLabelRuntime.fromConfig(config);

      expect(fromLiteral.tenantId, fromConfig.tenantId);
      expect(fromLiteral.tenantName, fromConfig.tenantName);
      expect(
        fromLiteral.theme.primaryColorHex,
        fromConfig.theme.primaryColorHex,
      );
      expect(
        fromLiteral.environment.apiBaseUrl,
        fromConfig.environment.apiBaseUrl,
      );
      expect(fromLiteral.features, fromConfig.features);
      expect(
        fromLiteral.android.version.combined,
        fromConfig.android.version.combined,
      );
      expect(fromLiteral.ios.version.combined, fromConfig.ios.version.combined);
    });
  });

  group('WhiteLabelRuntime.isFeatureEnabled', () {
    const runtime = WhiteLabelRuntime(
      tenantId: 'acme',
      tenantName: 'Acme Corp',
      theme: WhiteLabelTheme(),
      environment: WhiteLabelEnvironment(),
      features: {'dark_mode': true, 'beta_banner': false},
      android: WhiteLabelAndroidInfo(
        applicationId: 'com.example.acme',
        appName: 'Acme',
        version: WhiteLabelVersion(name: '1.0.0', buildNumber: 1),
      ),
      ios: WhiteLabelIosInfo(
        bundleId: 'com.example.acme',
        appName: 'Acme',
        version: WhiteLabelVersion(name: '1.0.0', buildNumber: 1),
      ),
    );

    test('returns true for a flag declared true', () {
      expect(runtime.isFeatureEnabled('dark_mode'), isTrue);
    });

    test('returns false for a flag declared false', () {
      expect(runtime.isFeatureEnabled('beta_banner'), isFalse);
    });

    test('returns false (does not throw) for a flag that was never declared '
        '-- the documented default, so a new flag is never a breaking '
        'change for existing tenant configs', () {
      expect(
        () => runtime.isFeatureEnabled('some_future_flag'),
        returnsNormally,
      );
      expect(runtime.isFeatureEnabled('some_future_flag'), isFalse);
    });
  });
}
