// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Verifies generateIosConfig (lib/src/generation/ios_generator.dart)
// WITHOUT invoking Xcode itself: everything here works on a copy of
// example/example_app's real `flutter create`-generated ios/ directory,
// checked with (a) plain file assertions for the cloned scheme and (b) the
// `xcodeproj` Ruby gem itself (a separate one-off script, not the
// generator's own script) to re-open the resulting .pbxproj and confirm it
// is still a structurally valid Xcode project with the expected, non-
// duplicated build configurations.
//
// Skips (does not fail) if `ruby`/the `xcodeproj` gem aren't available in
// the environment running the test — this generator is Ruby-dependent by
// design (see ios_generator.dart doc comment), so its test suite can't
// assert anything about it without Ruby either.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late bool rubyAvailable;

  setUpAll(() {
    try {
      final ProcessResult result = Process.runSync('ruby', [
        '-rxcodeproj',
        '-e',
        'puts "ok"',
      ]);
      rubyAvailable = result.exitCode == 0;
    } on ProcessException {
      rubyAvailable = false;
    }
  });

  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync('ios_generator_test_');
    final fixtureIosDir = Directory(
      p.join(Directory.current.path, 'test', 'fixtures', 'ios'),
    );
    if (!fixtureIosDir.existsSync()) {
      fail(
        'Fixture not found at ${fixtureIosDir.path} — this test must run '
        'with cwd at the white_label_kit package root (e.g. `dart test`).',
      );
    }
    _copyDirectory(fixtureIosDir, Directory(p.join(projectRoot.path, 'ios')));
  });

  tearDown(() => projectRoot.deleteSync(recursive: true));

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

  test(
    'throws IosGenerationException when ios/Runner.xcodeproj is missing',
    () {
      final Directory bareRoot = Directory.systemTemp.createTempSync(
        'ios_generator_bare_',
      );
      addTearDown(() => bareRoot.deleteSync(recursive: true));

      expect(
        () => generateIosConfig(tenant, projectRoot: bareRoot.path),
        throwsA(isA<IosGenerationException>()),
      );
    },
  );

  test(
    'clones a tenant-specific scheme with tenant-suffixed build configs',
    () {
      if (!rubyAvailable) {
        markTestSkipped('ruby/xcodeproj gem not available in this environment');
        return;
      }

      generateIosConfig(tenant, projectRoot: projectRoot.path);

      final schemeFile = File(
        p.join(
          projectRoot.path,
          'ios',
          'Runner.xcodeproj',
          'xcshareddata',
          'xcschemes',
          'acme.xcscheme',
        ),
      );
      expect(schemeFile.existsSync(), isTrue);
      final String content = schemeFile.readAsStringSync();

      expect(content, contains('buildConfiguration = "Debug-acme"'));
      expect(content, contains('buildConfiguration = "Release-acme"'));
      expect(content, contains('buildConfiguration = "Profile-acme"'));
      // No stray un-suffixed build configuration reference left behind.
      expect(content, isNot(contains('buildConfiguration = "Debug"')));
      expect(content, isNot(contains('buildConfiguration = "Release"')));
      expect(content, isNot(contains('buildConfiguration = "Profile"')));
      // The scheme still targets the one shared Runner blueprint — cloning it
      // must not touch which target it builds/runs/tests.
      expect(content, contains('BlueprintName = "Runner"'));
      expect(content, contains('BlueprintName = "RunnerTests"'));
    },
  );

  test('idempotent: running twice does not duplicate build configurations, '
      'and the pbxproj stays parseable by the xcodeproj gem', () {
    if (!rubyAvailable) {
      markTestSkipped('ruby/xcodeproj gem not available in this environment');
      return;
    }

    final String xcodeprojPath = p.join(
      projectRoot.path,
      'ios',
      'Runner.xcodeproj',
    );

    generateIosConfig(tenant, projectRoot: projectRoot.path);
    final Map<String, dynamic> firstRunInfo = _inspectProject(
      xcodeprojPath,
      'acme',
    );

    // Same tenant id, same bundle id: re-running must be a pure no-op on
    // the *count* of configurations (never append a second one with the
    // same name), and must not corrupt the project.
    generateIosConfig(tenant, projectRoot: projectRoot.path);
    final Map<String, dynamic> secondRunInfo = _inspectProject(
      xcodeprojPath,
      'acme',
    );

    expect(firstRunInfo['targets'], contains('Runner'));
    expect(firstRunInfo['targets'], contains('RunnerTests'));

    expect(firstRunInfo['project_debug_count'], 1);
    expect(firstRunInfo['runner_debug_count'], 1);
    expect(firstRunInfo['tests_debug_count'], 1);

    expect(
      secondRunInfo['project_debug_count'],
      1,
      reason: 'a second run must not add a duplicate project-level config',
    );
    expect(
      secondRunInfo['runner_debug_count'],
      1,
      reason: 'a second run must not add a duplicate Runner-target config',
    );
    expect(
      secondRunInfo['tests_debug_count'],
      1,
      reason: 'a second run must not add a duplicate RunnerTests config',
    );

    expect(firstRunInfo['runner_debug_bundle_id'], 'com.example.acme');
    expect(firstRunInfo['runner_release_bundle_id'], 'com.example.acme');
    expect(firstRunInfo['runner_profile_bundle_id'], 'com.example.acme');
    expect(secondRunInfo['runner_debug_bundle_id'], 'com.example.acme');
  });

  test('re-running after a bundle id change applies the new id, still without duplicating', () {
    if (!rubyAvailable) {
      markTestSkipped('ruby/xcodeproj gem not available in this environment');
      return;
    }

    final String xcodeprojPath = p.join(
      projectRoot.path,
      'ios',
      'Runner.xcodeproj',
    );

    generateIosConfig(tenant, projectRoot: projectRoot.path);

    const updatedTenant = TenantConfig(
      id: 'acme',
      name: 'Acme',
      android: AndroidTenantConfig(
        applicationId: 'com.example.acme',
        appName: 'Acme',
      ),
      ios: IosTenantConfig(bundleId: 'com.example.acme.v2', appName: 'Acme'),
      assets: TenantAssets(logo: 'tenants/acme/assets/logo.png'),
    );
    generateIosConfig(updatedTenant, projectRoot: projectRoot.path);

    final Map<String, dynamic> info = _inspectProject(xcodeprojPath, 'acme');
    expect(info['runner_debug_count'], 1);
    expect(info['runner_debug_bundle_id'], 'com.example.acme.v2');
  });

  test('sets APP_DISPLAY_NAME from TenantConfig.ios.appName on Runner and '
      'project scope, but not on other native targets', () {
    if (!rubyAvailable) {
      markTestSkipped('ruby/xcodeproj gem not available in this environment');
      return;
    }

    const branded = TenantConfig(
      id: 'acme',
      name: 'Acme',
      android: AndroidTenantConfig(
        applicationId: 'com.example.acme',
        appName: 'Acme',
      ),
      ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme App'),
      assets: TenantAssets(logo: 'tenants/acme/assets/logo.png'),
    );

    generateIosConfig(branded, projectRoot: projectRoot.path);

    final String xcodeprojPath = p.join(
      projectRoot.path,
      'ios',
      'Runner.xcodeproj',
    );
    final Map<String, dynamic> info = _inspectProject(xcodeprojPath, 'acme');

    // This is what actually fixes the real-world bug: a stock Info.plist
    // reads CFBundleDisplayName/CFBundleName from $(APP_DISPLAY_NAME), so
    // without this the flavor build shows "Runner" on the home screen
    // instead of the tenant's real name.
    expect(info['runner_debug_app_display_name'], 'Acme App');
    expect(info['runner_release_app_display_name'], 'Acme App');
    // RunnerTests has no branding — matching config *names* only.
    expect(info['tests_debug_app_display_name'], isNull);
  });

  test('removeIosConfig does not leave orphaned XCBuildConfiguration objects '
      'in the project after an add/remove cycle', () {
    if (!rubyAvailable) {
      markTestSkipped('ruby/xcodeproj gem not available in this environment');
      return;
    }

    final String xcodeprojPath = p.join(
      projectRoot.path,
      'ios',
      'Runner.xcodeproj',
    );

    final Map<String, dynamic> before = _inspectProject(xcodeprojPath, 'acme');

    generateIosConfig(tenant, projectRoot: projectRoot.path);
    removeIosConfig('acme', projectRoot: projectRoot.path);

    final Map<String, dynamic> after = _inspectProject(xcodeprojPath, 'acme');

    // Every "acme"-suffixed config actually gone, not just unlinked from
    // a target's build_configuration_list.
    expect(after['runner_debug_count'], 0);
    expect(after['runner_release_count'], 0);
    expect(after['runner_profile_count'], 0);
    expect(after['project_debug_count'], 0);
    expect(after['tests_debug_count'], 0);
    // The real regression check: object count returns to baseline instead
    // of accumulating dead XCBuildConfiguration objects the .pbxproj never
    // sheds on its own.
    expect(after['total_objects'], before['total_objects']);
  });

  test('two tenants get independent, non-colliding schemes and configs', () {
    if (!rubyAvailable) {
      markTestSkipped('ruby/xcodeproj gem not available in this environment');
      return;
    }

    const beta = TenantConfig(
      id: 'beta',
      name: 'Beta Corp',
      android: AndroidTenantConfig(
        applicationId: 'com.example.beta',
        appName: 'Beta Corp',
      ),
      ios: IosTenantConfig(bundleId: 'com.example.beta', appName: 'Beta Corp'),
      assets: TenantAssets(logo: 'tenants/beta/assets/logo.png'),
    );

    generateIosConfig(tenant, projectRoot: projectRoot.path);
    generateIosConfig(beta, projectRoot: projectRoot.path);

    final String xcodeprojPath = p.join(
      projectRoot.path,
      'ios',
      'Runner.xcodeproj',
    );
    final Map<String, dynamic> acmeInfo = _inspectProject(
      xcodeprojPath,
      'acme',
    );
    final Map<String, dynamic> betaInfo = _inspectProject(
      xcodeprojPath,
      'beta',
    );

    expect(acmeInfo['runner_debug_bundle_id'], 'com.example.acme');
    expect(betaInfo['runner_debug_bundle_id'], 'com.example.beta');

    final String acmeScheme = File(
      p.join(xcodeprojPath, 'xcshareddata', 'xcschemes', 'acme.xcscheme'),
    ).readAsStringSync();
    final String betaScheme = File(
      p.join(xcodeprojPath, 'xcshareddata', 'xcschemes', 'beta.xcscheme'),
    ).readAsStringSync();
    expect(acmeScheme, contains('buildConfiguration = "Debug-acme"'));
    expect(betaScheme, contains('buildConfiguration = "Debug-beta"'));
  });
}

/// Shells out to the `xcodeproj` gem — separately from
/// [generateIosConfig]'s own internal script — to re-open [xcodeprojPath]
/// and report on its structure. A non-zero exit here means the pbxproj is
/// no longer parseable by the same tool that wrote it.
Map<String, dynamic> _inspectProject(String xcodeprojPath, String tenantId) {
  final ProcessResult result = Process.runSync('ruby', [
    '-rxcodeproj',
    '-rjson',
    '-e',
    _inspectorRubyScript,
    '--',
    xcodeprojPath,
    tenantId,
  ]);
  if (result.exitCode != 0) {
    fail(
      'xcodeproj gem could not re-open $xcodeprojPath after generation:\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const String _inspectorRubyScript = r'''
path, tenant = ARGV
project = Xcodeproj::Project.open(path)
runner = project.targets.find { |t| t.name == 'Runner' }
tests_target = project.targets.find { |t| t.name == 'RunnerTests' }

def configs_named(list, name)
  return [] unless list
  list.build_configurations.select { |c| c.name == name }
end

def bundle_id_of(list, name)
  configs_named(list, name).first&.build_settings&.[]('PRODUCT_BUNDLE_IDENTIFIER')
end

def display_name_of(list, name)
  configs_named(list, name).first&.build_settings&.[]('APP_DISPLAY_NAME')
end

result = {
  targets: project.targets.map(&:name),
  project_debug_count: configs_named(project.root_object.build_configuration_list, "Debug-#{tenant}").length,
  runner_debug_count: configs_named(runner&.build_configuration_list, "Debug-#{tenant}").length,
  runner_release_count: configs_named(runner&.build_configuration_list, "Release-#{tenant}").length,
  runner_profile_count: configs_named(runner&.build_configuration_list, "Profile-#{tenant}").length,
  tests_debug_count: configs_named(tests_target&.build_configuration_list, "Debug-#{tenant}").length,
  runner_debug_bundle_id: bundle_id_of(runner&.build_configuration_list, "Debug-#{tenant}"),
  runner_release_bundle_id: bundle_id_of(runner&.build_configuration_list, "Release-#{tenant}"),
  runner_profile_bundle_id: bundle_id_of(runner&.build_configuration_list, "Profile-#{tenant}"),
  runner_debug_app_display_name: display_name_of(runner&.build_configuration_list, "Debug-#{tenant}"),
  runner_release_app_display_name: display_name_of(runner&.build_configuration_list, "Release-#{tenant}"),
  tests_debug_app_display_name: display_name_of(tests_target&.build_configuration_list, "Debug-#{tenant}"),
  total_objects: project.objects.length,
}
puts JSON.generate(result)
''';

void _copyDirectory(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final FileSystemEntity entity in source.listSync()) {
    final String name = p.basename(entity.path);
    final String destPath = p.join(destination.path, name);
    if (entity is Directory) {
      _copyDirectory(entity, Directory(destPath));
    } else if (entity is File) {
      entity.copySync(destPath);
    }
  }
}
