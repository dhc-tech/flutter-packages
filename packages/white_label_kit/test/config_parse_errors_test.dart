// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Error paths and boundary values for WhiteLabelConfig.parse/load and
// ConfigValidator: malformed YAML, wrong types, every required field, every
// invalid value shape, and the "report all errors at once" contract.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

/// A minimal valid tenant block; [extra] is appended inside the tenant.
String tenant(String id, {String extra = '', String? name = 'Acme'}) =>
    '''
    $id:
${name == null ? '' : '      name: "$name"'}
      android:
        application_id: "com.example.$id"
      ios:
        bundle_id: "com.example.$id"
      assets:
        logo: "tenants/$id/assets/logo.png"
$extra''';

String config({String? defaultTenant = 'acme', required String tenants}) =>
    '''
white_label:
${defaultTenant == null ? '' : '  default_tenant: $defaultTenant'}
  tenants:
$tenants
''';

List<String> errorsOf(String yaml, {String? projectRoot}) {
  try {
    WhiteLabelConfig.parse(yaml, projectRoot: projectRoot);
  } on WhiteLabelConfigException catch (e) {
    return e.errors;
  }
  fail('expected WhiteLabelConfigException');
}

Matcher hasError(Pattern p) => contains(
  predicate<String>((s) => s.contains(p), 'an error containing "$p"'),
);

void main() {
  group('top-level document shape', () {
    test('reports invalid YAML syntax', () {
      expect(
        errorsOf('white_label: [unclosed'),
        hasError('Invalid YAML syntax'),
      );
    });

    test(
      'an empty document is not a map; a map without the key is missing it',
      () {
        expect(errorsOf(''), hasError('to be a map'));
        expect(errorsOf('other: 1'), ['Missing top-level `white_label:` key.']);
      },
    );

    test('a scalar or list root is rejected with a type message', () {
      expect(errorsOf('just a string'), hasError('to be a map'));
      expect(errorsOf('- a\n- b'), hasError('to be a map'));
    });

    test('white_label must be a map', () {
      expect(errorsOf('white_label: 5'), hasError('"white_label" to be a map'));
    });

    test('no tenants declared and no default is an error', () {
      expect(
        errorsOf('white_label:\n  tenants: {}\n'),
        hasError('Missing `white_label.default_tenant`'),
      );
    });

    test('tenants must be a map', () {
      expect(
        errorsOf('white_label:\n  default_tenant: a\n  tenants: [x]\n'),
        hasError('white_label.tenants'),
      );
    });

    test('default_tenant naming an undeclared tenant is rejected', () {
      expect(
        errorsOf(config(defaultTenant: 'ghost', tenants: tenant('acme'))),
        hasError('`default_tenant: ghost` is not one of the declared tenants'),
      );
    });

    test('multiple tenants without a default are ambiguous', () {
      expect(
        errorsOf(
          config(
            defaultTenant: null,
            tenants: '${tenant('acme')}\n${tenant('beta')}',
          ),
        ),
        hasError('Multiple tenants declared but no default_tenant'),
      );
    });

    test('a numeric default_tenant is stringified before matching', () {
      expect(
        errorsOf(config(defaultTenant: '123', tenants: tenant('acme'))),
        hasError('`default_tenant: 123`'),
      );
    });
  });

  group('tenant ids', () {
    for (final bad in [
      'Acme',
      '1acme',
      'my-tenant',
      'my tenant',
      'testing',
      'test',
    ]) {
      test('rejects "$bad"', () {
        final List<String> errors = errorsOf(
          config(defaultTenant: 'x', tenants: tenant('"$bad"')),
        );
        expect(errors, isNotEmpty);
      });
    }

    test('accepts boundary ids', () {
      for (final ok in ['a', 'a1', 'z999', 'tes']) {
        expect(
          () => WhiteLabelConfig.parse(
            config(defaultTenant: ok, tenants: tenant(ok)),
          ),
          returnsNormally,
          reason: ok,
        );
      }
    });

    test('a very long id is accepted (no length limit) and round-trips', () {
      final id = 'a${'b' * 500}';
      final WhiteLabelConfig c = WhiteLabelConfig.parse(
        config(defaultTenant: id, tenants: tenant(id)),
      );
      expect(c.has(id), isTrue);
    });
  });

  group('required tenant fields', () {
    test('a tenant that is not a map', () {
      expect(
        errorsOf(config(tenants: '    acme: 5')),
        hasError('Expected "tenants.acme" to be a map'),
      );
    });

    test('missing name, blank name', () {
      expect(
        errorsOf(config(tenants: tenant('acme', name: null))),
        hasError('missing required field `name`'),
      );
      expect(
        errorsOf(config(tenants: tenant('acme', name: '   '))),
        hasError('missing required field `name`'),
      );
    });

    test('missing android/ios/assets blocks report every missing field', () {
      final List<String> errors = errorsOf(
        config(tenants: '    acme:\n      name: "A"\n'),
      );
      expect(errors, hasError('android.application_id'));
      expect(errors, hasError('ios.bundle_id'));
      expect(errors, hasError('assets.logo'));
    });

    test('invalid application id and bundle id values', () {
      final List<String> errors = errorsOf(
        config(
          tenants: '''
    acme:
      name: "A"
      android:
        application_id: "Not Valid"
      ios:
        bundle_id: "com.under_score.app"
      assets:
        logo: "tenants/acme/assets/logo.png"
''',
        ),
      );
      expect(errors, hasError('Invalid Android applicationId'));
      expect(errors, hasError('Invalid iOS bundle id'));
    });

    test('collects errors from several tenants in one pass', () {
      final List<String> errors = errorsOf(
        config(
          tenants:
              '${tenant('acme', name: null)}\n${tenant('beta', name: null)}',
        ),
      );
      expect(
        errors.where((e) => e.contains('missing required field `name`')),
        hasLength(2),
      );
    });

    test('WhiteLabelConfigException.toString lists every error', () {
      final e = WhiteLabelConfigException(['a', 'b']);
      expect(e.toString(), 'ERROR: a\nERROR: b');
    });
  });

  group('asset paths', () {
    String withLogo(String logo) => config(
      tenants:
          '''
    acme:
      name: "A"
      android:
        application_id: "com.example.acme"
      ios:
        bundle_id: "com.example.acme"
      assets:
        logo: "$logo"
''',
    );

    test('rejects absolute, traversal and cross-tenant paths', () {
      expect(errorsOf(withLogo('/etc/passwd')), hasError('must be relative'));
      expect(
        errorsOf(withLogo('tenants/acme/../beta/x.png')),
        hasError('".."'),
      );
      expect(
        errorsOf(withLogo('tenants/beta/assets/logo.png')),
        hasError('must live under tenants/acme/'),
      );
      expect(
        errorsOf(withLogo('logo.png')),
        hasError('must live under tenants/acme/'),
      );
    });

    test('with a projectRoot, a missing file is reported', () {
      final Directory root = Directory.systemTemp.createTempSync('wl_cfg_');
      addTearDown(() => root.deleteSync(recursive: true));
      expect(
        errorsOf(
          withLogo('tenants/acme/assets/logo.png'),
          projectRoot: root.path,
        ),
        hasError('Asset file not found'),
      );
    });

    test('icon and splash paths are validated like the logo', () {
      final List<String> errors = errorsOf(
        config(
          tenants: '''
    acme:
      name: "A"
      android:
        application_id: "com.example.acme"
      ios:
        bundle_id: "com.example.acme"
      assets:
        logo: "tenants/acme/assets/logo.png"
        icon: "/abs/icon.png"
        splash: "../splash.png"
''',
        ),
      );
      expect(errors, hasError('must be relative'));
      expect(errors, hasError('".."'));
    });
  });

  group('adaptive icon', () {
    test('background and background_color are mutually exclusive', () {
      expect(
        errorsOf(
          config(
            tenants:
                tenant(
                  'acme',
                  extra: '''
      android_placeholder: x
''',
                ).replaceFirst(
                  '        application_id: "com.example.acme"',
                  '''        application_id: "com.example.acme"
        adaptive_icon:
          background: "tenants/acme/assets/bg.png"
          background_color: "#FFFFFF"''',
                ),
          ),
        ),
        hasError('not both'),
      );
    });

    test(
      'rejects an invalid background color and out-of-tenant foreground',
      () {
        final List<String> errors = errorsOf(
          config(
            tenants: tenant('acme').replaceFirst(
              '        application_id: "com.example.acme"',
              '''        application_id: "com.example.acme"
        adaptive_icon:
          foreground: "tenants/other/fg.png"
          background_color: "red"''',
            ),
          ),
        );
        expect(errors, hasError('Invalid color "red"'));
        expect(errors, hasError('must live under tenants/acme/'));
      },
    );

    test('a valid adaptive icon is parsed', () {
      final WhiteLabelConfig c = WhiteLabelConfig.parse(
        config(
          tenants: tenant('acme').replaceFirst(
            '        application_id: "com.example.acme"',
            '''        application_id: "com.example.acme"
        adaptive_icon:
          foreground: "tenants/acme/assets/fg.png"
          background_color: "#112233"
          monochrome: "tenants/acme/assets/mono.png"''',
          ),
        ),
      );
      final AndroidAdaptiveIconConfig a = c['acme'].android.adaptiveIcon!;
      expect(a.foreground, 'tenants/acme/assets/fg.png');
      expect(a.backgroundColor, '#112233');
      expect(a.monochrome, 'tenants/acme/assets/mono.png');
      expect(a.background, isNull);
    });

    test('adaptive_icon that is not a map is rejected', () {
      expect(
        errorsOf(
          config(
            tenants: tenant('acme').replaceFirst(
              '        application_id: "com.example.acme"',
              '        application_id: "com.example.acme"\n        adaptive_icon: 7',
            ),
          ),
        ),
        hasError('adaptive_icon'),
      );
    });
  });

  group('versions', () {
    List<String> versionErrors(String block) =>
        errorsOf(config(tenants: tenant('acme', extra: block)));

    test('missing name', () {
      expect(
        versionErrors('      version:\n        build_number: 1\n'),
        hasError('tenants.acme.version.name'),
      );
    });

    test('invalid semver values', () {
      for (final bad in [
        '1.0',
        '1.0.0-beta',
        'v1.0.0',
        '1.0.0.0',
        'a.b.c',
        '',
      ]) {
        expect(
          versionErrors(
            '      version:\n        name: "$bad"\n        build_number: 1\n',
          ),
          isNotEmpty,
          reason: bad,
        );
      }
    });

    test('build_number must be a positive integer', () {
      for (final bad in ['0', '-1', 'abc', '1.5']) {
        expect(
          versionErrors(
            '      version:\n        name: "1.0.0"\n        build_number: $bad\n',
          ),
          isNotEmpty,
          reason: bad,
        );
      }
      expect(
        versionErrors('      version:\n        name: "1.0.0"\n'),
        hasError('build_number'),
      );
    });

    test('build_number given as a numeric string is accepted', () {
      final WhiteLabelConfig c = WhiteLabelConfig.parse(
        config(
          tenants: tenant(
            'acme',
            extra: '      version:\n        name: "1.2.3"\n        build_number: "42"\n',
          ),
        ),
      );
      expect(c['acme'].version.buildNumber, 42);
    });

    test('large build numbers are accepted', () {
      final WhiteLabelConfig c = WhiteLabelConfig.parse(
        config(
          tenants: tenant(
            'acme',
            extra: '      version:\n        name: "1.2.3"\n        build_number: 2100000000\n',
          ),
        ),
      );
      expect(c['acme'].version.buildNumber, 2100000000);
    });

    test('platform overrides are validated separately', () {
      final yaml = config(
        tenants: tenant('acme').replaceFirst(
          '        application_id: "com.example.acme"',
          '        application_id: "com.example.acme"\n        version:\n          name: "x"\n          build_number: 1',
        ),
      );
      expect(errorsOf(yaml), hasError('tenants.acme.android.version'));
    });

    test(
      'ios override is applied and android falls back to the shared version',
      () {
        final WhiteLabelConfig c = WhiteLabelConfig.parse(
          config(
            tenants:
                tenant(
                  'acme',
                  extra: '      version:\n        name: "1.0.0"\n        build_number: 1\n',
                ).replaceFirst(
                  '        bundle_id: "com.example.acme"',
                  '        bundle_id: "com.example.acme"\n        version:\n          name: "2.0.0"\n          build_number: 5',
                ),
          ),
        );
        expect(c['acme'].iosVersion.name, '2.0.0');
        expect(c['acme'].androidVersion.name, '1.0.0');
      },
    );
  });

  group('theme, environment and features', () {
    List<String> errs(String block) =>
        errorsOf(config(tenants: tenant('acme', extra: block)));

    test('theme must be a map; colors must be hex', () {
      expect(errs('      theme: 3\n'), hasError('tenants.acme.theme'));
      expect(
        errs(
          '      theme:\n        primary_color: "blue"\n        secondary_color: "#12"\n',
        ),
        hasError('Invalid color "blue"'),
      );
    });

    test('every named color map validates entries and rejects non-maps', () {
      for (final field in [
        'brand_colors',
        'feature_colors',
        'section_colors',
        'gradient_colors',
      ]) {
        expect(
          errs('      theme:\n        $field:\n          a: "nope"\n'),
          hasError('tenants.acme.theme.$field.a'),
          reason: field,
        );
        expect(
          errs('      theme:\n        $field: 1\n'),
          hasError('tenants.acme.theme.$field'),
        );
      }
    });

    test('valid color maps keep #RRGGBB and #AARRGGBB values', () {
      final WhiteLabelConfig c = WhiteLabelConfig.parse(
        config(
          tenants: tenant(
            'acme',
            extra: '''
      theme:
        primary_color: "#112233"
        brand_colors:
          main: "#AABBCCDD"
''',
          ),
        ),
      );
      expect(c['acme'].theme.brandColors, {'main': '#AABBCCDD'});
      expect(c['acme'].theme.primaryColor, '#112233');
    });

    test('api_base_url must be an absolute http(s) URL', () {
      for (final bad in [
        'ftp://x.com',
        'api.example.com',
        '/relative',
        'javascript:alert(1)',
      ]) {
        expect(
          errs('      environment:\n        api_base_url: "$bad"\n'),
          hasError('Invalid URL'),
          reason: bad,
        );
      }
    });

    test('environment must be a map and custom values must be strings', () {
      expect(
        errs('      environment: x\n'),
        hasError('tenants.acme.environment'),
      );
      expect(
        errs('      environment:\n        custom:\n          n: 5\n'),
        hasError('expected value in "custom" to be String'),
      );
      expect(
        errs('      environment:\n        custom:\n          1: "x"\n'),
        hasError('expected all keys in "custom" to be String'),
      );
      expect(
        errs('      environment:\n        custom: [a]\n'),
        hasError('environment.custom'),
      );
    });

    test('named environments are validated and resolvable', () {
      expect(
        errs(
          '      environments:\n        staging:\n          api_base_url: "nope"\n',
        ),
        hasError('Invalid URL'),
      );
      expect(
        errs('      environments: 1\n'),
        hasError('tenants.acme.environments'),
      );
      expect(
        errs('      environments:\n        staging: 1\n'),
        hasError('environments.staging'),
      );

      final WhiteLabelConfig c = WhiteLabelConfig.parse(
        config(
          tenants: tenant(
            'acme',
            extra: '''
      environments:
        staging:
          api_base_url: "https://stg.example.com"
          custom:
            k: "v"
''',
          ),
        ),
      );
      expect(
        c['acme'].resolveEnvironment('staging').apiBaseUrl,
        'https://stg.example.com',
      );
      expect(c['acme'].resolveEnvironment('staging').custom, {'k': 'v'});
    });

    test('resolveEnvironment explains unknown names (declared and none)', () {
      final WhiteLabelConfig none = WhiteLabelConfig.parse(
        config(tenants: tenant('acme')),
      );
      expect(
        () => none['acme'].resolveEnvironment('prod'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('(none declared)'),
          ),
        ),
      );
      final WhiteLabelConfig some = WhiteLabelConfig.parse(
        config(
          tenants: tenant(
            'acme',
            extra: '      environments:\n        staging: {}\n',
          ),
        ),
      );
      expect(
        () => some['acme'].resolveEnvironment('prod'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('staging'),
          ),
        ),
      );
      expect(some['acme'].resolveEnvironment(), same(some['acme'].environment));
    });

    test('feature flags must be booleans', () {
      expect(
        errs(
          '      features:\n        a: "yes"\n        b: 1\n        c: true\n',
        ),
        allOf(
          hasError('feature "a" must be true/false'),
          hasError('feature "b"'),
        ),
      );
      expect(errs('      features: [x]\n'), hasError('tenants.acme.features'));
    });

    test('firebase paths follow the asset path rules', () {
      expect(
        errs(
          '      firebase:\n        google_services_json: "/abs.json"\n        google_service_info_plist: "tenants/other/x.plist"\n',
        ),
        allOf(hasError('must be relative'), hasError('must live under')),
      );
      expect(errs('      firebase: 4\n'), hasError('tenants.acme.firebase'));
    });
  });

  group('WhiteLabelConfig API', () {
    final WhiteLabelConfig c = WhiteLabelConfig.parse(
      config(tenants: '${tenant('acme')}\n${tenant('beta')}'),
    );

    test('operator [] throws for unknown tenants', () {
      expect(() => c['ghost'], throwsArgumentError);
      expect(c['acme'].id, 'acme');
    });

    test('has / isDefault / resolve', () {
      expect(c.has('acme'), isTrue);
      expect(c.has('ghost'), isFalse);
      expect(c.isDefault('acme'), isTrue);
      expect(c.resolve().id, 'acme');
      expect(c.resolve('beta').id, 'beta');
      expect(() => c.resolve('ghost'), throwsArgumentError);
    });

    test('a duplicate YAML key is rejected by the YAML parser', () {
      expect(
        errorsOf(
          'white_label:\n  default_tenant: a\n  tenants:\n    a: {}\n    a: {}\n',
        ),
        hasError('Invalid YAML syntax'),
      );
    });
  });

  group('load / configFile', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('wl_load_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('load throws a helpful exception when the file is missing', () {
      expect(
        () => WhiteLabelConfig.load(root.path),
        throwsA(
          isA<WhiteLabelConfigException>().having(
            (e) => e.errors.single,
            'error',
            allOf(
              contains('white_label.yaml not found'),
              contains('white_label_kit:init'),
            ),
          ),
        ),
      );
    });

    test('configFile resolves default, relative and absolute paths', () {
      expect(
        WhiteLabelConfig.configFile(root.path).path,
        '${root.path}/white_label.yaml',
      );
      expect(
        WhiteLabelConfig.configFile(root.path, configPath: 'cfg/dev.yaml').path,
        p.join(root.path, 'cfg', 'dev.yaml'),
      );
      expect(
        WhiteLabelConfig.configFile(root.path, configPath: '/abs/x.yaml').path,
        '/abs/x.yaml',
      );
    });

    test(
      'load honours a custom config path and reports its basename when missing',
      () {
        expect(
          () => WhiteLabelConfig.load(root.path, configPath: 'nope.yaml'),
          throwsA(
            isA<WhiteLabelConfigException>().having(
              (e) => e.errors.single,
              'e',
              contains('nope.yaml not found'),
            ),
          ),
        );

        Directory(p.join(root.path, 'tenants/acme/assets'))
            .createSync(recursive: true);
        File(p.join(root.path, 'tenants/acme/assets/logo.png'))
            .writeAsBytesSync([1]);
        File(p.join(root.path, 'custom.yaml'))
            .writeAsStringSync(config(tenants: tenant('acme')));
        expect(
          WhiteLabelConfig.load(
            root.path,
            configPath: 'custom.yaml',
          ).defaultTenant,
          'acme',
        );
      },
    );

    test('load checks that asset files exist on disk', () {
      File(p.join(root.path, 'white_label.yaml'))
          .writeAsStringSync(config(tenants: tenant('acme')));
      expect(
        () => WhiteLabelConfig.load(root.path),
        throwsA(
          isA<WhiteLabelConfigException>().having(
            (e) => e.errors.join(),
            'e',
            contains('Asset file not found'),
          ),
        ),
      );
    });
  });

  group('ConfigValidator boundaries', () {
    test('semanticVersion', () {
      expect(ConfigValidator.semanticVersion('0.0.0'), isA<Valid>());
      expect(ConfigValidator.semanticVersion('10.20.30'), isA<Valid>());
      for (final bad in [
        '1.0',
        '1.0.0 ',
        ' 1.0.0',
        '1.0.0\n',
        '1..0',
        '-1.0.0',
      ]) {
        expect(
          ConfigValidator.semanticVersion(bad),
          isA<Invalid>(),
          reason: bad,
        );
      }
    });

    test('buildNumber', () {
      expect(ConfigValidator.buildNumber(1), isA<Valid>());
      expect(ConfigValidator.buildNumber(0), isA<Invalid>());
      expect(ConfigValidator.buildNumber(-5), isA<Invalid>());
    });

    test('colorHex', () {
      expect(ConfigValidator.colorHex('#abcdef'), isA<Valid>());
      expect(ConfigValidator.colorHex('#ABCDEF12'), isA<Valid>());
      for (final bad in [
        '#abc',
        '#abcdeg',
        '#1234567',
        '#123456789',
        '',
        '#',
        'abcdef',
        '#abcdef\n',
      ]) {
        expect(ConfigValidator.colorHex(bad), isA<Invalid>(), reason: bad);
      }
    });

    test('url', () {
      expect(ConfigValidator.url('http://localhost:8080/x?y=1'), isA<Valid>());
      expect(ConfigValidator.url('https://example.com'), isA<Valid>());
      for (final bad in [
        '',
        'example.com',
        'ftp://example.com',
        'mailto:a@b.c',
        '//example.com',
        'http//x',
      ]) {
        expect(ConfigValidator.url(bad), isA<Invalid>(), reason: bad);
      }
    });

    test('androidApplicationId and iosBundleId boundaries', () {
      expect(ConfigValidator.androidApplicationId('a.b'), isA<Valid>());
      expect(ConfigValidator.androidApplicationId('com.a_b.c1'), isA<Valid>());
      for (final bad in [
        '',
        'a',
        'a.',
        '.a',
        'a..b',
        '1a.b',
        'a.1b',
        'a.b-c',
        'a b.c',
      ]) {
        expect(
          ConfigValidator.androidApplicationId(bad),
          isA<Invalid>(),
          reason: bad,
        );
      }
      expect(ConfigValidator.iosBundleId('a.b-c'), isA<Valid>());
      for (final bad in ['', 'a', 'a..b', 'a.b_c', '1a.b', 'a.-b']) {
        expect(ConfigValidator.iosBundleId(bad), isA<Invalid>(), reason: bad);
      }
    });

    test('assetPath handles Windows-style separators and odd segments', () {
      expect(
        ConfigValidator.assetPath(
          r'tenants\acme\assets\logo.png',
          tenantId: 'acme',
        ),
        isA<Invalid>(),
        reason: 'backslash paths do not satisfy the forward-slash prefix rule',
      );
      expect(
        ConfigValidator.assetPath(
          'tenants/acme/./assets/logo.png',
          tenantId: 'acme',
        ),
        isA<Valid>(),
      );
      expect(ConfigValidator.assetPath('', tenantId: 'acme'), isA<Invalid>());
      expect(
        ConfigValidator.assetPath('tenants/acme', tenantId: 'acme'),
        isA<Invalid>(),
      );
      expect(
        ConfigValidator.assetPath(
          'tenants/acme/${'d/' * 200}f.png',
          tenantId: 'acme',
        ),
        isA<Valid>(),
      );
    });

    test('expectMap', () {
      final errors = <String>[];
      expect(ConfigValidator.expectMap(null, 'x', errors), isNull);
      expect(errors, isEmpty);
      expect(ConfigValidator.expectMap({'a': 1}, 'x', errors), {'a': 1});
      expect(ConfigValidator.expectMap([1], 'x', errors), isNull);
      expect(errors.single, contains('Expected "x" to be a map'));
    });
  });
}
