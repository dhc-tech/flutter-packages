// Unit coverage for generateAndroidFlavor's Gradle-file manipulation. A
// real Gradle build inside a `dart test` run would be slow/flaky (it needs
// the Android SDK, network access for the first Gradle download, and takes
// tens of seconds even when cached) — that's exercised as a real,
// non-unit-testable-here step instead (see the task report: `dart run
// bin/white_label.dart build --tenant <id> --platform android` against
// example/example_app, verified with `flutter build apk` + `aapt dump
// badging` on the resulting artifact). This file covers the part that
// *is* fast and deterministic: the productFlavors block gets generated
// correctly, and generating it twice for the same tenant never duplicates
// it.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

/// A minimal-but-realistic `android/app/build.gradle.kts` skeleton — no
/// `flavorDimensions`/`productFlavors` yet, mirroring a freshly
/// `flutter create`d project before any tenant has ever been onboarded.
const _freshGradleFile = '''
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.example_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.example_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
''';

TenantConfig _tenant(String id, {String? applicationId, String? appName}) {
  return TenantConfig(
    id: id,
    name: appName ?? id,
    android: AndroidTenantConfig(
      applicationId: applicationId ?? 'com.example.$id',
      appName: appName ?? id,
    ),
    ios: IosTenantConfig(bundleId: applicationId ?? 'com.example.$id', appName: appName ?? id),
    assets: const TenantAssets(logo: 'tenants/x/assets/logo.png'),
  );
}

void main() {
  late Directory projectRoot;
  late File gradleFile;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync('android_generation_test_');
    final appDir = Directory(p.join(projectRoot.path, 'android', 'app'))
      ..createSync(recursive: true);
    gradleFile = File(p.join(appDir.path, 'build.gradle.kts'))..writeAsStringSync(_freshGradleFile);
  });

  tearDown(() {
    projectRoot.deleteSync(recursive: true);
  });

  test('throws if android/app/build.gradle.kts does not exist', () {
    final Directory emptyRoot = Directory.systemTemp.createTempSync(
      'android_generation_test_missing_',
    );
    addTearDown(() => emptyRoot.deleteSync(recursive: true));

    expect(
      () => generateAndroidFlavor(_tenant('acme'), projectRoot: emptyRoot.path),
      throwsA(isA<StateError>()),
    );
  });

  test('adds flavorDimensions once, plus a productFlavors block with the tenant entry', () {
    generateAndroidFlavor(
      _tenant('acme', applicationId: 'com.example.acme', appName: 'Acme'),
      projectRoot: projectRoot.path,
    );

    final String content = gradleFile.readAsStringSync();

    expect(content, contains('flavorDimensions += listOf("tenant")'));
    expect(content, contains('productFlavors {'));
    expect(content, contains('create("acme")'));
    expect(content, contains('applicationId = "com.example.acme"'));
    expect(content, contains('resValue("string", "app_name", "Acme")'));

    // The braces the generator inserted must themselves balance — a
    // regression that inserted a stray '{' or dropped a '}' would corrupt
    // the whole file for Gradle, so assert this explicitly rather than
    // just trusting the substring checks above.
    final int opens = '{'.allMatches(content).length;
    final int closes = '}'.allMatches(content).length;
    expect(opens, closes);
  });

  test('calling twice for the same tenant does not duplicate the flavor block', () {
    final TenantConfig tenant = _tenant('acme', applicationId: 'com.example.acme', appName: 'Acme');

    generateAndroidFlavor(tenant, projectRoot: projectRoot.path);
    final String afterFirst = gradleFile.readAsStringSync();

    generateAndroidFlavor(tenant, projectRoot: projectRoot.path);
    final String afterSecond = gradleFile.readAsStringSync();

    // Byte-for-byte identical: the idempotency guard fires before any part
    // of the file is touched a second time.
    expect(afterSecond, equals(afterFirst));

    final int occurrences = 'create("acme")'.allMatches(afterSecond).length;
    expect(occurrences, 1);

    final int flavorDimensionsOccurrences = 'flavorDimensions'.allMatches(afterSecond).length;
    expect(flavorDimensionsOccurrences, 1);
  });

  test('a second, different tenant is added alongside the first, not instead of it', () {
    generateAndroidFlavor(
      _tenant('acme', applicationId: 'com.example.acme', appName: 'Acme'),
      projectRoot: projectRoot.path,
    );
    generateAndroidFlavor(
      _tenant('beta', applicationId: 'com.example.beta', appName: 'Beta Corp'),
      projectRoot: projectRoot.path,
    );

    final String content = gradleFile.readAsStringSync();

    expect(content, contains('create("acme")'));
    expect(content, contains('applicationId = "com.example.acme"'));
    expect(content, contains('create("beta")'));
    expect(content, contains('applicationId = "com.example.beta"'));

    // Only one shared flavorDimensions/productFlavors block — not one per
    // tenant.
    expect('flavorDimensions'.allMatches(content).length, 1);
    expect('productFlavors {'.allMatches(content).length, 1);

    final int opens = '{'.allMatches(content).length;
    final int closes = '}'.allMatches(content).length;
    expect(opens, closes);
  });

  test('the generated file remains parseable-shaped after two different tenants (existing android block content is preserved)', () {
    generateAndroidFlavor(
      _tenant('acme', applicationId: 'com.example.acme', appName: 'Acme'),
      projectRoot: projectRoot.path,
    );
    generateAndroidFlavor(
      _tenant('beta', applicationId: 'com.example.beta', appName: 'Beta Corp'),
      projectRoot: projectRoot.path,
    );

    final String content = gradleFile.readAsStringSync();

    // Nothing pre-existing was clobbered.
    expect(content, contains('namespace = "com.example.example_app"'));
    expect(content, contains('defaultConfig {'));
    expect(content, contains('buildTypes {'));
    expect(content, contains('signingConfig = signingConfigs.getByName("debug")'));
    expect(content, contains('flutter {'));
    expect(content, contains('source = "../.."'));
  });
}
