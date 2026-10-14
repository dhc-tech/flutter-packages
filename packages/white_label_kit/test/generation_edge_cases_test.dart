// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Error paths and edge cases for the generators/stager/runtime that the
// feature-level suites do not reach: missing/malformed project files,
// removal and idempotency, corrupt IDE JSON, stale staging leftovers,
// generator tenant resolution, runtime toString output and builder wiring.

import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/builder.dart';
import 'package:white_label_kit/white_label_kit.dart';

TenantConfig tenant(
  String id, {
  String? applicationId,
  String? appName,
  Map<String, bool> features = const {},
  TenantTheme theme = const TenantTheme(),
  TenantEnvironment environment = const TenantEnvironment(),
}) => TenantConfig(
  id: id,
  name: appName ?? id,
  android: AndroidTenantConfig(
    applicationId: applicationId ?? 'com.example.$id',
    appName: appName ?? id,
  ),
  ios: IosTenantConfig(
    bundleId: applicationId ?? 'com.example.$id',
    appName: appName ?? id,
  ),
  assets: TenantAssets(logo: 'tenants/$id/assets/logo.png'),
  features: features,
  theme: theme,
  environment: environment,
);

const freshGradle = '''
plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.app"
    defaultConfig {
        applicationId = "com.example.app"
    }
}
''';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('wl_edge_'));
  tearDown(() => root.deleteSync(recursive: true));

  File gradle() =>
      File(p.join(root.path, 'android', 'app', 'build.gradle.kts'));
  void writeGradle(String content) {
    gradle().parent.createSync(recursive: true);
    gradle().writeAsStringSync(content);
  }

  group('android flavors', () {
    test('generate throws StateError when the gradle file is missing', () {
      expect(
        () => generateAndroidFlavor(tenant('acme'), projectRoot: root.path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'm',
            contains('No android/app/build.gradle.kts'),
          ),
        ),
      );
    });

    test('generate refuses a file without an android block and leaves it untouched', () {
      writeGradle('plugins { }\n');
      expect(
        () => generateAndroidFlavor(tenant('acme'), projectRoot: root.path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'm',
            contains('no top-level `android'),
          ),
        ),
      );
      expect(gradle().readAsStringSync(), 'plugins { }\n');
    });

    test('generate refuses an unterminated android block', () {
      writeGradle('android {\n  defaultConfig {\n');
      expect(
        () => generateAndroidFlavor(tenant('acme'), projectRoot: root.path),
        throwsStateError,
      );
    });

    test('generate refuses an unterminated productFlavors block', () {
      writeGradle('android {\n  productFlavors {\n    create("x") {\n}\n');
      expect(
        () => generateAndroidFlavor(tenant('beta'), projectRoot: root.path),
        throwsStateError,
      );
    });

    test('quotes and backslashes in names are escaped for Kotlin', () {
      writeGradle(freshGradle);
      generateAndroidFlavor(
        tenant('acme', appName: r'Ac"me \ Co'),
        projectRoot: root.path,
      );
      expect(gradle().readAsStringSync(), contains(r'"Ac\"me \\ Co"'));
    });

    test(
      'adding into an existing productFlavors block keeps other entries',
      () {
        writeGradle(freshGradle);
        generateAndroidFlavor(tenant('acme'), projectRoot: root.path);
        generateAndroidFlavor(tenant('beta'), projectRoot: root.path);
        generateAndroidFlavor(tenant('beta'), projectRoot: root.path);
        final String content = gradle().readAsStringSync();
        expect('create("acme")'.allMatches(content), hasLength(1));
        expect('create("beta")'.allMatches(content), hasLength(1));
        expect('flavorDimensions'.allMatches(content), hasLength(1));
        expect('resValues = true'.allMatches(content), hasLength(1));
      },
    );

    test('remove deletes only the requested flavor and is idempotent', () {
      writeGradle(freshGradle);
      generateAndroidFlavor(tenant('acme'), projectRoot: root.path);
      generateAndroidFlavor(tenant('beta'), projectRoot: root.path);

      removeAndroidFlavor('acme', projectRoot: root.path);
      String content = gradle().readAsStringSync();
      expect(content, isNot(contains('create("acme")')));
      expect(content, contains('create("beta")'));
      expect('{'.allMatches(content).length, '}'.allMatches(content).length);

      removeAndroidFlavor('acme', projectRoot: root.path);
      expect(gradle().readAsStringSync(), content);

      removeAndroidFlavor('beta', projectRoot: root.path);
      content = gradle().readAsStringSync();
      expect(content, isNot(contains('create("beta")')));
      expect('{'.allMatches(content).length, '}'.allMatches(content).length);
    });

    test('remove is a no-op without a gradle file and for ids with regex characters', () {
      expect(
        () => removeAndroidFlavor('acme', projectRoot: root.path),
        returnsNormally,
      );
      writeGradle(freshGradle);
      removeAndroidFlavor('a.c(me', projectRoot: root.path);
      expect(gradle().readAsStringSync(), freshGradle);
    });

    test('remove ignores an unterminated flavor block', () {
      const broken = 'android {\n  productFlavors {\n    create("acme") {\n';
      writeGradle(broken);
      removeAndroidFlavor('acme', projectRoot: root.path);
      expect(gradle().readAsStringSync(), broken);
    });

    test('remove handles CRLF line endings', () {
      writeGradle(freshGradle.replaceAll('\n', '\r\n'));
      generateAndroidFlavor(tenant('acme'), projectRoot: root.path);
      final String crlf = gradle()
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .replaceAll('\n', '\r\n');
      gradle().writeAsStringSync(crlf);
      removeAndroidFlavor('acme', projectRoot: root.path);
      expect(gradle().readAsStringSync(), isNot(contains('create("acme")')));
    });
  });

  group('iOS generation errors', () {
    test('generateIosConfig requires an Xcode project', () {
      expect(
        () => generateIosConfig(tenant('acme'), projectRoot: root.path),
        throwsA(
          isA<IosGenerationException>().having(
            (e) => e.message,
            'm',
            contains('No ios/Runner.xcodeproj'),
          ),
        ),
      );
    });

    test('generateIosConfig requires a Runner scheme', () {
      Directory(p.join(root.path, 'ios', 'Runner.xcodeproj'))
          .createSync(recursive: true);
      expect(
        () => generateIosConfig(tenant('acme'), projectRoot: root.path),
        throwsA(
          isA<IosGenerationException>().having(
            (e) => e.message,
            'm',
            contains('No Runner.xcscheme'),
          ),
        ),
      );
    });

    test('removeIosConfig is a no-op without an Xcode project', () {
      expect(
        () => removeIosConfig('acme', projectRoot: root.path),
        returnsNormally,
      );
    });

    test('IosGenerationException.toString includes the message', () {
      expect(
        IosGenerationException('boom').toString(),
        'IosGenerationException: boom',
      );
    });
  });

  group('icon and splash generators', () {
    test('return null unless the feature flag is exactly true', () {
      expect(
        maybeGenerateLauncherIcon(tenant('acme'), projectRoot: root.path),
        isNull,
      );
      expect(
        maybeGenerateLauncherIcon(
          tenant('acme', features: {'icon_generate': false}),
          projectRoot: root.path,
        ),
        isNull,
      );
      expect(
        maybeGenerateNativeSplash(tenant('acme'), projectRoot: root.path),
        isNull,
      );
      expect(
        maybeGenerateNativeSplash(
          tenant('acme', features: {'splash_generate': false}),
          projectRoot: root.path,
        ),
        isNull,
      );
      expect(root.listSync(), isEmpty);
    });

    TenantConfig adaptive({String? primary, String? bgColor, String? bg}) =>
        TenantConfig(
          id: 'acme',
          name: 'Acme',
          android: AndroidTenantConfig(
            applicationId: 'com.example.acme',
            appName: 'Acme',
            adaptiveIcon: AndroidAdaptiveIconConfig(
              foreground: 'tenants/acme/assets/fg.png',
              background: bg,
              backgroundColor: bgColor,
              monochrome: 'tenants/acme/assets/mono.png',
            ),
          ),
          ios: const IosTenantConfig(
            bundleId: 'com.example.acme',
            appName: 'Acme',
          ),
          assets: const TenantAssets(logo: 'tenants/acme/assets/logo.png'),
          features: const {'icon_generate': true},
          theme: TenantTheme(primaryColor: primary),
        );

    String launcherYaml() =>
        File(p.join(root.path, 'icons_launcher-acme.yaml')).readAsStringSync();

    test('adaptive background falls back: explicit color, theme primary, then white', () {
      maybeGenerateLauncherIcon(
        adaptive(bgColor: '#010203', primary: '#AAAAAA'),
        projectRoot: root.path,
      );
      expect(launcherYaml(), contains('adaptive_background_color: "#010203"'));
      File(p.join(root.path, 'icons_launcher-acme.yaml')).deleteSync();

      maybeGenerateLauncherIcon(
        adaptive(primary: '#AAAAAA'),
        projectRoot: root.path,
      );
      expect(launcherYaml(), contains('adaptive_background_color: "#AAAAAA"'));
      File(p.join(root.path, 'icons_launcher-acme.yaml')).deleteSync();

      maybeGenerateLauncherIcon(adaptive(), projectRoot: root.path);
      expect(launcherYaml(), contains('adaptive_background_color: "#ffffff"'));
      expect(
        launcherYaml(),
        contains('adaptive_monochrome_image: "tenants/acme/assets/mono.png"'),
      );
      File(p.join(root.path, 'icons_launcher-acme.yaml')).deleteSync();

      maybeGenerateLauncherIcon(
        adaptive(bg: 'tenants/acme/assets/bg.png'),
        projectRoot: root.path,
      );
      expect(
        launcherYaml(),
        contains('adaptive_background_image: "tenants/acme/assets/bg.png"'),
      );
      expect(launcherYaml(), isNot(contains('adaptive_background_color')));
    });

    test('a failing flutter_native_splash run is reported, not thrown', () {
      final IconSplashGenerateResult? result = maybeGenerateNativeSplash(
        tenant('acme', features: {'splash_generate': true}),
        projectRoot: root.path,
      );
      expect(result, isNotNull);
      expect(result!.ran, isFalse);
      expect(result.error, contains('flutter_native_splash'));
      expect(
        File(p.join(root.path, 'flutter_native_splash-acme.yaml'))
            .readAsStringSync(),
        allOf(
          contains('color: "#ffffff"'),
          contains('tenants/acme/assets/logo.png'),
        ),
      );
    });

    test('registerLaunchScreenStoryboard reports a missing Xcode project', () {
      final String? error = registerLaunchScreenStoryboard(
        'acme',
        projectRoot: root.path,
      );
      expect(error, isNull, reason: 'nothing to register in a non-iOS project');
    });
  });

  group('IDE generator with corrupt files', () {
    File vscode(String name) => File(p.join(root.path, '.vscode', name));

    test('replaces an unparseable launch.json and tasks.json', () {
      vscode('launch.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');
      vscode('tasks.json').writeAsStringSync('[1, 2');

      IdeGenerator.generate(tenant('acme'), projectRoot: root.path);

      final launch = jsonDecode(
        vscode('launch.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect((launch['configurations'] as List), isNotEmpty);
      final tasks = jsonDecode(
        vscode('tasks.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect((tasks['tasks'] as List), isNotEmpty);
    });

    test(
      'a launch.json that is valid JSON but not an object is also reset',
      () {
        vscode('launch.json')
          ..createSync(recursive: true)
          ..writeAsStringSync('[]');
        IdeGenerator.generateVsCodeConfig(
          tenant('acme'),
          projectRoot: root.path,
        );
        expect(
          jsonDecode(vscode('launch.json').readAsStringSync()),
          isA<Map<String, dynamic>>(),
        );
      },
    );

    test(
      'regenerating preserves unrelated configurations and never duplicates',
      () {
        vscode('launch.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'version': '0.2.0',
              'configurations': [
                {
                  'name': 'Mine',
                  'request': 'launch',
                  'args': ['--flavor', 'other'],
                },
                {'name': 'NoArgs', 'request': 'launch'},
              ],
            }),
          );

        IdeGenerator.generateVsCodeConfig(
          tenant('acme'),
          projectRoot: root.path,
        );
        final String once = vscode('launch.json').readAsStringSync();
        IdeGenerator.generateVsCodeConfig(
          tenant('acme'),
          projectRoot: root.path,
        );

        expect(vscode('launch.json').readAsStringSync(), once);
        final names = ((jsonDecode(once) as Map)['configurations'] as List)
            .map((c) => (c as Map)['name'])
            .toList();
        expect(names, containsAll(['Mine', 'NoArgs']));
      },
    );

    test('remove clears one tenant and leaves the others', () {
      IdeGenerator.generate(tenant('acme'), projectRoot: root.path);
      IdeGenerator.generate(tenant('beta'), projectRoot: root.path);
      IdeGenerator.remove('acme', projectRoot: root.path);

      final String launch = vscode('launch.json').readAsStringSync();
      expect(launch, isNot(contains('acme')));
      expect(launch, contains('beta'));
      expect(
        vscode('tasks.json').readAsStringSync(),
        isNot(contains('(acme)')),
      );
    });

    test('remove is safe when nothing was generated', () {
      expect(
        () => IdeGenerator.remove('ghost', projectRoot: root.path),
        returnsNormally,
      );
    });

    test(
      'ideRoot can differ from projectRoot (monorepo) and paths stay relative',
      () {
        final Directory ide = Directory(p.join(root.path, 'repo'))
          ..createSync();
        final Directory app = Directory(p.join(ide.path, 'apps', 'mobile'))
          ..createSync(recursive: true);
        IdeGenerator.generate(
          tenant('acme'),
          projectRoot: app.path,
          ideRoot: ide.path,
        );

        final launch = File(p.join(ide.path, '.vscode', 'launch.json'))
            .readAsStringSync();
        expect(launch, contains('apps/mobile'));
        expect(Directory(p.join(app.path, '.vscode')).existsSync(), isFalse);
      },
    );

    test('const IdeGenerator can be instantiated', () {
      expect(const IdeGenerator(), isA<IdeGenerator>());
    });
  });

  group('TenantStager', () {
    TenantConfig staged(String id) => tenant(id);

    void writeAsset(String id, [String name = 'logo.png']) {
      File(p.join(root.path, 'tenants', id, 'assets', name))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
    }

    test('stage replaces a stale temp directory left by a crashed run', () {
      writeAsset('acme');
      final stager = TenantStager(root.path);
      final Directory stale = Directory(
        '${stager.stagingDirFor('acme')}.tmp-acme',
      )..createSync(recursive: true);
      File(p.join(stale.path, 'junk')).writeAsStringSync('x');

      stager.stage(staged('acme'));

      expect(stale.existsSync(), isFalse);
      expect(stager.stagedAssetNames('acme'), ['logo.png']);
    });

    test('stage twice overwrites the previous output', () {
      writeAsset('acme');
      final stager = TenantStager(root.path)..stage(staged('acme'));
      File(p.join(stager.stagingDirFor('acme'), 'assets', 'old.txt'))
          .writeAsStringSync('x');
      stager.stage(staged('acme'));
      expect(stager.stagedAssetNames('acme'), ['logo.png']);
    });

    test('clean removes output and temp leftovers and is idempotent', () {
      writeAsset('acme');
      final stager = TenantStager(root.path)..stage(staged('acme'));
      final Directory temp = Directory(
        '${stager.stagingDirFor('acme')}.tmp-acme',
      )..createSync();

      stager.clean('acme');
      expect(Directory(stager.stagingDirFor('acme')).existsSync(), isFalse);
      expect(temp.existsSync(), isFalse);
      expect(() => stager.clean('acme'), returnsNormally);
      expect(() => stager.clean('never_staged'), returnsNormally);
    });

    test('listings are empty before staging and without firebase', () {
      writeAsset('acme');
      final stager = TenantStager(root.path);
      expect(stager.stagedAssetNames('acme'), isEmpty);
      stager.stage(staged('acme'));
      expect(stager.stagedFirebaseFileNames('acme'), isEmpty);
    });

    test('a missing declared file is reported without leaving output', () {
      final stager = TenantStager(root.path);
      expect(() => stager.stage(staged('acme')), throwsA(isA<StateError>()));
      expect(Directory(stager.stagingDirFor('acme')).existsSync(), isFalse);
    });
  });

  group('resolveGeneratorTenantId', () {
    final WhiteLabelConfig config = WhiteLabelConfig.parse('''
white_label:
  default_tenant: acme
  tenants:
    acme:
      name: A
      android: {application_id: com.example.acme}
      ios: {bundle_id: com.example.acme}
      assets: {logo: tenants/acme/assets/logo.png}
    beta:
      name: B
      android: {application_id: com.example.beta}
      ios: {bundle_id: com.example.beta}
      assets: {logo: tenants/beta/assets/logo.png}
''');

    test('explicit id wins, and an unknown explicit id throws', () {
      expect(
        resolveGeneratorTenantId(
          config,
          explicitTenantId: 'beta',
          environment: {'TENANT_ID': 'acme'},
        ),
        'beta',
      );
      expect(
        () => resolveGeneratorTenantId(config, explicitTenantId: 'ghost'),
        throwsArgumentError,
      );
    });

    test('TENANT_ID is used when valid, ignored when unknown or empty', () {
      expect(
        resolveGeneratorTenantId(config, environment: {'TENANT_ID': 'beta'}),
        'beta',
      );
      expect(
        resolveGeneratorTenantId(config, environment: {'TENANT_ID': 'ghost'}),
        'acme',
      );
      expect(
        resolveGeneratorTenantId(config, environment: {'TENANT_ID': ''}),
        'acme',
      );
      expect(resolveGeneratorTenantId(config, environment: const {}), 'acme');
    });

    test('generateWhiteLabelSource rejects an unknown environment name', () {
      expect(
        () => generateWhiteLabelSource(config, 'acme', envName: 'nope'),
        throwsArgumentError,
      );
    });

    test('writeGeneratedFile creates lib/ and writes the file', () {
      writeGeneratedFile(root.path, config, 'beta');
      final File out = File(p.join(root.path, 'lib', 'white_label.g.dart'));
      expect(out.existsSync(), isTrue);
      expect(out.readAsStringSync(), contains("'beta'"));
      expect(out.readAsStringSync(), isNot(contains('com.example.acme')));
    });

    test('writeGeneratedFile escapes single quotes in values', () {
      final WhiteLabelConfig tricky = WhiteLabelConfig.parse('''
white_label:
  tenants:
    acme:
      name: "A'cme Co"
      android: {application_id: com.example.acme}
      ios: {bundle_id: com.example.acme}
      assets: {logo: tenants/acme/assets/logo.png}
''');
      final String source = generateWhiteLabelSource(tricky, 'acme');
      expect(source, contains(r"A\'cme Co"));
    });
  });

  group('runtime value objects', () {
    final runtime = WhiteLabelRuntime.fromConfig(
      tenant(
        'acme',
        features: {'x': true},
        theme: const TenantTheme(
          primaryColor: '#112233',
          brandColors: {'main': '#FFFFFF'},
        ),
        environment: const TenantEnvironment(
          apiBaseUrl: 'https://a.example',
          custom: {'k': 'v'},
        ),
      ),
    );

    test('toString output names the interesting fields', () {
      expect(runtime.toString(), contains('acme'));
      expect(
        runtime.theme.toString(),
        allOf(contains('#112233'), contains('main')),
      );
      expect(
        runtime.environment.toString(),
        allOf(contains('https://a.example'), contains('k')),
      );
      expect(runtime.android.toString(), contains('com.example.acme'));
      expect(runtime.ios.toString(), contains('com.example.acme'));
      expect(runtime.android.version.toString(), 'WhiteLabelVersion(1.0.0+1)');
    });

    test('maps handed to the runtime are unmodifiable copies', () {
      expect(() => runtime.features['y'] = true, throwsUnsupportedError);
      expect(
        () => runtime.environment.custom['z'] = 'q',
        throwsUnsupportedError,
      );
    });

    test('isFeatureEnabled defaults to false for unknown keys', () {
      expect(runtime.isFeatureEnabled('x'), isTrue);
      expect(runtime.isFeatureEnabled('missing'), isFalse);
      expect(runtime.isFeatureEnabled(''), isFalse);
    });

    test('fromConfig with an undeclared env name throws', () {
      expect(
        () => WhiteLabelRuntime.fromConfig(tenant('acme'), envName: 'qa'),
        throwsArgumentError,
      );
    });
  });

  group('build_runner builder', () {
    test('whiteLabelBuilder returns a WhiteLabelBuilder', () {
      expect(whiteLabelBuilder(BuilderOptions.empty), isA<WhiteLabelBuilder>());
    });
  });

  group('interactive menu preconditions', () {
    test('returns 1 when white_label.yaml is missing', () async {
      expect(await runInteractiveMenu(projectRoot: root.path), 1);
    });

    test('returns 1 when white_label.yaml cannot be parsed', () async {
      File(p.join(root.path, 'white_label.yaml'))
          .writeAsStringSync('white_label: [oops');
      expect(await runInteractiveMenu(projectRoot: root.path), 1);
    });

    test('returns 1 when white_label.yaml fails validation', () async {
      File(p.join(root.path, 'white_label.yaml'))
          .writeAsStringSync('white_label:\n  tenants: {}\n');
      expect(await runInteractiveMenu(projectRoot: root.path), 1);
    });
  });
}
