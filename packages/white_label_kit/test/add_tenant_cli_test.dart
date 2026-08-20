// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Exercises the real `add-tenant` CLI subcommand as a subprocess against a
// throwaway temp project — this is the "no manual YAML editing, no manual
// mkdir" guarantee, so it's tested end-to-end as a real process, not just
// the string-manipulation logic in isolation.

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
  late Directory projectRoot;

  setUp(() async {
    projectRoot = Directory.systemTemp.createTempSync('add_tenant_cli_test_');
    File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: fake_app
flutter:
  uses-material-design: true
''');
    final ProcessResult init = await runCli([
      'init',
      '--example',
    ], cwd: projectRoot.path);
    expect(init.exitCode, 0, reason: init.stderr.toString());
  });

  tearDown(() {
    projectRoot.deleteSync(recursive: true);
  });

  test('add-tenant generates the yaml entry and the assets folder — no manual editing', () async {
    final ProcessResult result = await runCli([
      'add-tenant',
      'beta',
      'Beta Corp',
      'com.example.beta',
    ], cwd: projectRoot.path);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('Added tenant "beta"'));

    // The folder was created for us — no mkdir required.
    final logo = File(
      p.join(projectRoot.path, 'tenants', 'beta', 'assets', 'logo.png'),
    );
    expect(logo.existsSync(), isTrue);

    // The yaml entry was appended for us — no hand-editing required. Prove
    // it via `validate` and `list`, not by re-parsing the raw string.
    final ProcessResult validate = await runCli([
      'validate',
    ], cwd: projectRoot.path);
    expect(
      validate.exitCode,
      0,
      reason: validate.stdout.toString() + validate.stderr.toString(),
    );
    expect(validate.stdout, contains('beta'));

    final ProcessResult list = await runCli(['list'], cwd: projectRoot.path);
    expect(list.stdout, contains('beta'));
    expect(
      list.stdout,
      contains('Default tenant: acme'),
    ); // unchanged, no --default passed
  });

  test('add-tenant --default updates default_tenant', () async {
    final ProcessResult result = await runCli([
      'add-tenant',
      'beta',
      'Beta Corp',
      'com.example.beta',
      '--default',
    ], cwd: projectRoot.path);
    expect(result.exitCode, 0, reason: result.stderr.toString());

    final ProcessResult list = await runCli(['list'], cwd: projectRoot.path);
    expect(list.stdout, contains('Default tenant: beta'));
  });

  test('add-tenant rejects a duplicate tenant id', () async {
    final ProcessResult result = await runCli([
      'add-tenant',
      'acme', // already exists from init --example
      'Acme Again',
      'com.example.acmeagain',
    ], cwd: projectRoot.path);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('already exists'));
  });

  test('add-tenant rejects an invalid bundle id and creates nothing', () async {
    final ProcessResult result = await runCli([
      'add-tenant',
      'beta',
      'Beta Corp',
      'Not A Valid Bundle Id',
    ], cwd: projectRoot.path);

    expect(result.exitCode, 1);
    expect(
      Directory(p.join(projectRoot.path, 'tenants', 'beta')).existsSync(),
      isFalse,
    );
  });

  test(
    'add-tenant with --logo copies the real file instead of a placeholder',
    () async {
      final realLogo = File(p.join(projectRoot.path, 'real_logo.png'))
        ..writeAsStringSync('REAL_LOGO_BYTES');

      final ProcessResult result = await runCli([
        'add-tenant',
        'beta',
        'Beta Corp',
        'com.example.beta',
        '--logo',
        realLogo.path,
      ], cwd: projectRoot.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final staged = File(
        p.join(projectRoot.path, 'tenants', 'beta', 'assets', 'logo.png'),
      );
      expect(staged.readAsStringSync(), 'REAL_LOGO_BYTES');
    },
  );
}
