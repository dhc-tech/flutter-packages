// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ide_generator_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  const tenant = TenantConfig(
    id: 'acme',
    name: 'Acme Student',
    android: AndroidTenantConfig(
      applicationId: 'com.acme.student',
      appName: 'Acme',
    ),
    ios: IosTenantConfig(bundleId: 'com.acme.student', appName: 'Acme'),
    assets: TenantAssets(logo: 'tenants/acme/logo.png'),
  );

  test('generates VS Code launch.json and Android Studio .run configs', () {
    IdeGenerator.generate(tenant, projectRoot: tempDir.path);

    // VS Code check
    final launchFile = File(p.join(tempDir.path, '.vscode', 'launch.json'));
    expect(launchFile.existsSync(), isTrue);

    final launchJson =
        jsonDecode(launchFile.readAsStringSync()) as Map<String, dynamic>;
    final List<Map<String, dynamic>> configs =
        (launchJson['configurations'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
    expect(configs.length, 3);
    expect(configs[0]['name'], 'Acme Student (debug)');
    expect(configs[0]['args'], contains('--flavor'));
    expect(configs[0]['args'], contains('acme'));
    expect(configs[0]['args'], contains('--dart-define=TENANT_ID=acme'));

    // Android Studio / IntelliJ check
    final debugRun = File(p.join(tempDir.path, '.run', 'acme_debug.run.xml'));
    final releaseRun = File(
      p.join(tempDir.path, '.run', 'acme_release.run.xml'),
    );
    expect(debugRun.existsSync(), isTrue);
    expect(releaseRun.existsSync(), isTrue);

    final String debugContent = debugRun.readAsStringSync();
    expect(debugContent, contains('name="Acme Student (debug)"'));
    expect(debugContent, contains('value="acme"'));
    expect(debugContent, contains('--dart-define=TENANT_ID=acme'));
    // Regression check: a prior version's `.substring(1)` on the raw
    // template string stripped the leading `<` instead of a (nonexistent)
    // leading newline — Dart triple-quoted strings don't include one —
    // silently producing invalid XML that Android Studio/IntelliJ can't
    // parse, so the run configuration never appeared in the Run menu at
    // all (no error either — the IDE just ignores an unparseable file).
    expect(debugContent, startsWith('<component'));

    final buildApkRun = File(
      p.join(tempDir.path, '.run', 'acme_build_apk.run.xml'),
    );
    expect(buildApkRun.existsSync(), isTrue);
    expect(buildApkRun.readAsStringSync(), startsWith('<component'));
  });

  test('removes VS Code launch.json and Android Studio .run configs', () {
    IdeGenerator.generate(tenant, projectRoot: tempDir.path);
    expect(
      File(p.join(tempDir.path, '.run', 'acme_debug.run.xml')).existsSync(),
      isTrue,
    );

    IdeGenerator.remove('acme', projectRoot: tempDir.path);

    // Run XMLs deleted
    expect(
      File(p.join(tempDir.path, '.run', 'acme_debug.run.xml')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(tempDir.path, '.run', 'acme_release.run.xml')).existsSync(),
      isFalse,
    );

    // VS Code entries removed
    final launchFile = File(p.join(tempDir.path, '.vscode', 'launch.json'));
    final launchJson =
        jsonDecode(launchFile.readAsStringSync()) as Map<String, dynamic>;
    final List<Map<String, dynamic>> configs =
        (launchJson['configurations'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
    expect(configs.isEmpty, isTrue);
  });

  test(
    'supports monorepo workspace layout where ideRoot differs from projectRoot',
    () {
      final appDir = Directory(p.join(tempDir.path, 'apps', 'student_app'))
        ..createSync(recursive: true);

      IdeGenerator.generate(
        tenant,
        projectRoot: appDir.path,
        ideRoot: tempDir.path,
      );

      // VS Code launch.json written at workspace root (tempDir/.vscode/launch.json)
      final launchFile = File(p.join(tempDir.path, '.vscode', 'launch.json'));
      expect(launchFile.existsSync(), isTrue);

      final launchJson =
          jsonDecode(launchFile.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> configs =
          (launchJson['configurations'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(configs.length, 3);
      expect(configs[0]['name'], 'Acme Student (debug)');
      expect(configs[0]['program'], 'apps/student_app/lib/main.dart');

      // VS Code tasks.json check
      final tasksFile = File(p.join(tempDir.path, '.vscode', 'tasks.json'));
      expect(tasksFile.existsSync(), isTrue);
      final tasksJson =
          jsonDecode(tasksFile.readAsStringSync()) as Map<String, dynamic>;
      final List<Map<String, dynamic>> tasks =
          (tasksJson['tasks'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(tasks.isNotEmpty, isTrue);
      expect(
        tasks[0]['command'],
        contains(
          "cd 'apps/student_app' && dart run white_label_kit:generate --tenant acme && flutter build",
        ),
      );

      // Android Studio / IntelliJ check written at workspace root (.run)
      final debugRun = File(p.join(tempDir.path, '.run', 'acme_debug.run.xml'));
      expect(debugRun.existsSync(), isTrue);
      final String debugContent = debugRun.readAsStringSync();
      expect(
        debugContent,
        contains(r'$PROJECT_DIR$/apps/student_app/lib/main.dart'),
      );

      final buildRun = File(
        p.join(tempDir.path, '.run', 'acme_build_apk.run.xml'),
      );
      expect(buildRun.existsSync(), isTrue);
      final String buildContent = buildRun.readAsStringSync();
      expect(buildContent, contains(r'$PROJECT_DIR$/apps/student_app'));

      // Removal check in monorepo
      IdeGenerator.remove(
        'acme',
        projectRoot: appDir.path,
        ideRoot: tempDir.path,
      );
      expect(
        File(p.join(tempDir.path, '.run', 'acme_debug.run.xml')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(tempDir.path, '.run', 'acme_build_apk.run.xml'))
            .existsSync(),
        isFalse,
      );
    },
  );

  test('forwards custom --config path and safely quotes paths with spaces in IDE configs', () {
    final appWithSpaces = Directory(p.join(tempDir.path, 'apps', 'my app'))
      ..createSync(recursive: true);

    IdeGenerator.generate(
      tenant,
      projectRoot: appWithSpaces.path,
      ideRoot: tempDir.path,
      configPath: 'configs/custom_white_label.yaml',
    );

    final tasksFile = File(p.join(tempDir.path, '.vscode', 'tasks.json'));
    expect(tasksFile.existsSync(), isTrue);
    final tasksJson =
        jsonDecode(tasksFile.readAsStringSync()) as Map<String, dynamic>;
    final List<Map<String, dynamic>> tasks =
        (tasksJson['tasks'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(
      tasks[0]['command'],
      contains(
        "cd 'apps/my app' && dart run white_label_kit:generate --tenant acme --config 'configs/custom_white_label.yaml'",
      ),
    );

    final configureTask = tasks.firstWhere(
      (t) => t['label'] == '🔧 Configure White-Label',
    );
    expect(
      configureTask['command'],
      contains(
        "cd 'apps/my app' && dart run white_label_kit:configure --ide-root '../..' --config 'configs/custom_white_label.yaml'",
      ),
    );

    final runXml = File(p.join(tempDir.path, '.run', 'acme_build_apk.run.xml'))
        .readAsStringSync();
    expect(runXml, contains("--config 'configs/custom_white_label.yaml'"));
  });
}
