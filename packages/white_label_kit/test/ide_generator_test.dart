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
}
