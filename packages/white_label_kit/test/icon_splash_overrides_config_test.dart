// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Verifies the full white_label.yaml -> TenantConfig path for
// theme.splash_color and the raw icons_launcher:/native_splash: override
// blocks (parsed in WhiteLabelConfig, consumed by generateLauncherIcon/
// generateNativeSplash) — not just the generator functions in isolation.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'icon_splash_overrides_config_test_',
    );
    final dir = Directory(p.join(projectRoot.path, 'tenants', 'acme'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'logo.png')).writeAsStringSync('LOGO');
  });

  tearDown(() => projectRoot.deleteSync(recursive: true));

  test('theme.splash_color, icons_launcher:, and native_splash: all parse '
      'into TenantConfig', () {
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
        logo: "tenants/acme/logo.png"
      theme:
        primary_color: "#2EA3F2"
        splash_color: "#E8F2FF"
      icons_launcher:
        platforms:
          android:
            adaptive_background_color: "#ffffff"
      native_splash:
        fullscreen: true
        android_12:
          icon_background_color: "#111111"
''');

    final TenantConfig tenant = WhiteLabelConfig.load(projectRoot.path)['acme'];

    expect(tenant.theme.primaryColor, '#2EA3F2');
    expect(tenant.theme.splashColor, '#E8F2FF');

    expect(tenant.iconsLauncherOverrides['platforms'], {
      'android': {'adaptive_background_color': '#ffffff'},
    });

    expect(tenant.nativeSplashOverrides['fullscreen'], true);
    expect(tenant.nativeSplashOverrides['android_12'], {
      'icon_background_color': '#111111',
    });
  });

  test('a tenant with neither block declared gets empty override maps, not '
      'null or a parse error', () {
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
        logo: "tenants/acme/logo.png"
''');

    final TenantConfig tenant = WhiteLabelConfig.load(projectRoot.path)['acme'];

    expect(tenant.iconsLauncherOverrides, isEmpty);
    expect(tenant.nativeSplashOverrides, isEmpty);
    expect(tenant.theme.splashColor, isNull);
  });
}
