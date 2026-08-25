// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _binPath = p.join(
  Directory.current.path,
  'bin',
  'white_label.dart',
);

Future<ProcessResult> runCli(List<String> args, {required String cwd}) {
  return Process.run('dart', [_binPath, ...args], workingDirectory: cwd);
}

void main() {
  late Directory workspaceRoot;
  late Directory appRoot;

  setUp(() async {
    workspaceRoot = Directory.systemTemp.createTempSync('monorepo_test_');
    // Monorepo root has workspace pubspec
    File(p.join(workspaceRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: my_workspace
environment:
  sdk: '>=3.0.0 <4.0.0'
''');

    // App is nested at apps/flutter_app
    appRoot = Directory(p.join(workspaceRoot.path, 'apps', 'flutter_app'))
      ..createSync(recursive: true);
    File(p.join(appRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: flutter_app
flutter:
  uses-material-design: true
''');

    // Initialize white_label.yaml inside the app directory
    final ProcessResult init = await runCli([
      'init',
      '--example',
      '--project-root',
      'apps/flutter_app',
    ], cwd: workspaceRoot.path);
    expect(init.exitCode, 0, reason: init.stderr.toString());
  });

  tearDown(() {
    if (workspaceRoot.existsSync()) {
      workspaceRoot.deleteSync(recursive: true);
    }
  });

  test(
    'validate and list work from workspace root with --project-root',
    () async {
      final ProcessResult validate = await runCli([
        'validate',
        '--project-root',
        'apps/flutter_app',
      ], cwd: workspaceRoot.path);
      expect(validate.exitCode, 0, reason: validate.stderr.toString());
      expect(validate.stdout, contains('white_label.yaml is valid'));

      final ProcessResult list = await runCli([
        'list',
        '--project-root',
        'apps/flutter_app',
      ], cwd: workspaceRoot.path);
      expect(list.exitCode, 0, reason: list.stderr.toString());
      expect(list.stdout, contains('Default tenant: acme'));
      expect(list.stdout, contains('- acme — Acme  (default)'));
    },
  );

  test(
    'add-tenant and remove-tenant work from workspace root with --project-root',
    () async {
      final ProcessResult add = await runCli([
        'add-tenant',
        'beta',
        'Beta App',
        'com.example.beta',
        '--project-root',
        'apps/flutter_app',
      ], cwd: workspaceRoot.path);
      expect(add.exitCode, 0, reason: add.stderr.toString());
      expect(add.stdout, contains('Added tenant "beta"'));

      expect(
        File(p.join(appRoot.path, 'tenants', 'beta', 'assets', 'logo.png'))
            .existsSync(),
        isTrue,
      );

      final ProcessResult remove = await runCli([
        'remove-tenant',
        'beta',
        '--project-root',
        'apps/flutter_app',
        '--ide-root',
        '.',
      ], cwd: workspaceRoot.path);
      expect(remove.exitCode, 0, reason: remove.stderr.toString());
      expect(remove.stdout, contains('Removed tenant "beta"'));
      expect(
        Directory(p.join(appRoot.path, 'tenants', 'beta')).existsSync(),
        isFalse,
      );
    },
  );

  test('generate and configure work from workspace root with --project-root and --ide-root', () async {
    // Android build.gradle.kts setup in nested app
    final androidAppDir = Directory(p.join(appRoot.path, 'android', 'app'))
      ..createSync(recursive: true);
    File(p.join(androidAppDir.path, 'build.gradle.kts')).writeAsStringSync('''
android {
    namespace = "com.example.app"
    defaultConfig {
        applicationId = "com.example.app"
    }
}
''');

    final ProcessResult configure = await runCli([
      'configure',
      '--project-root',
      'apps/flutter_app',
      '--ide-root',
      '.',
    ], cwd: workspaceRoot.path);

    expect(configure.exitCode, 0, reason: configure.stderr.toString());
    expect(configure.stdout, contains('Configuration complete!'));

    // lib/white_label.g.dart generated in nested app
    final generatedDart = File(
      p.join(appRoot.path, 'lib', 'white_label.g.dart'),
    );
    expect(generatedDart.existsSync(), isTrue);
    expect(generatedDart.readAsStringSync(), contains("tenantId: 'acme'"));

    // Android build.gradle.kts patched in nested app
    final patchedGradle = File(p.join(androidAppDir.path, 'build.gradle.kts'))
        .readAsStringSync();
    expect(patchedGradle, contains('create("acme")'));

    // IDE run configs generated at workspace root (.)
    final launchFile = File(
      p.join(workspaceRoot.path, '.vscode', 'launch.json'),
    );
    expect(launchFile.existsSync(), isTrue);
    final launchJson =
        jsonDecode(launchFile.readAsStringSync()) as Map<String, dynamic>;
    final List<Map<String, dynamic>> configs =
        (launchJson['configurations'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
    expect(configs[0]['program'], 'apps/flutter_app/lib/main.dart');

    final runXml = File(
      p.join(workspaceRoot.path, '.run', 'acme_debug.run.xml'),
    );
    expect(runXml.existsSync(), isTrue);
    expect(
      runXml.readAsStringSync(),
      contains(r'$PROJECT_DIR$/apps/flutter_app/lib/main.dart'),
    );
  });

  test('doctor checks assets relative to project-root in workspace', () async {
    final ProcessResult doctor = await runCli([
      'doctor',
      '--project-root',
      'apps/flutter_app',
    ], cwd: workspaceRoot.path);
    expect(doctor.stdout, contains('tenants/acme/assets/logo.png'));
  });

  test('doctor and build route to generic implementation even if workspace root contains legacy tool scripts', () async {
    // Create dummy legacy scripts at workspace root
    final toolDir = Directory(p.join(workspaceRoot.path, 'tool'))
      ..createSync(recursive: true);
    File(p.join(toolDir.path, 'tenant_doctor.dart'))
        .writeAsStringSync('void main() { print("LEGACY DOCTOR"); }');
    File(p.join(toolDir.path, 'build_runner.dart'))
        .writeAsStringSync('void main() { print("LEGACY BUILD"); }');

    final ProcessResult doctor = await runCli([
      'doctor',
      '--project-root',
      'apps/flutter_app',
    ], cwd: workspaceRoot.path);
    expect(doctor.stdout, isNot(contains('LEGACY DOCTOR')));
    expect(doctor.stdout, contains('tenants/acme/assets/logo.png'));

    final ProcessResult build = await runCli([
      'build',
      '--project-root',
      'apps/flutter_app',
      '--tenant',
      'acme',
      '--dry-run',
    ], cwd: workspaceRoot.path);
    expect(build.stdout, isNot(contains('LEGACY BUILD')));
    expect(build.stdout, contains('dry run — config resolved'));
  });
}
