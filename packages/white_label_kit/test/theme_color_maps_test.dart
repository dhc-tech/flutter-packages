import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync('theme_color_maps_test_');
    final dir = Directory(p.join(projectRoot.path, 'tenants', 'acme', 'assets'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'logo.png')).writeAsStringSync('LOGO');
  });

  tearDown(() => projectRoot.deleteSync(recursive: true));

  test('theme color maps parse and round-trip into WhiteLabelRuntime', () {
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
      theme:
        primary_color: "#2EA3F2"
        secondary_color: "#604ABD"
        brand_colors:
          logo_accent: "#FF0000"
        feature_colors:
          courses: "#00FF00"
        section_colors:
          header: "#0000FF"
        gradient_colors:
          start: "#111111"
          end: "#EEEEEE"
''');

    final tenant = WhiteLabelConfig.load(projectRoot.path)['acme'];
    expect(tenant.theme.brandColors, {'logo_accent': '#FF0000'});
    expect(tenant.theme.featureColors, {'courses': '#00FF00'});
    expect(tenant.theme.sectionColors, {'header': '#0000FF'});
    expect(tenant.theme.gradientColors, {'start': '#111111', 'end': '#EEEEEE'});

    final runtime = WhiteLabelRuntime.fromConfig(tenant);
    expect(runtime.theme.brandColors, tenant.theme.brandColors);
    expect(runtime.theme.gradientColors, tenant.theme.gradientColors);
  });

  test('an invalid color inside a theme map is rejected non-silently', () {
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
      theme:
        brand_colors:
          logo_accent: "not-a-color"
''');

    expect(
      () => WhiteLabelConfig.load(projectRoot.path),
      throwsA(
        isA<WhiteLabelConfigException>().having(
          (e) => e.errors.join('\n'),
          'errors',
          contains('brand_colors.logo_accent'),
        ),
      ),
    );
  });

  test('theme maps default to empty when omitted', () {
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
''');

    final tenant = WhiteLabelConfig.load(projectRoot.path)['acme'];
    expect(tenant.theme.brandColors, isEmpty);
    expect(tenant.theme.featureColors, isEmpty);
    expect(tenant.theme.sectionColors, isEmpty);
    expect(tenant.theme.gradientColors, isEmpty);
  });
}
