// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/tenant_config.dart';

/// Generates IDE run/debug and build task configurations for VS Code and Android Studio / IntelliJ.
///
/// Enables developers to 1-click Run, Debug, and Build any tenant flavor directly
/// from IDE UI menus without typing commands in terminal.
class IdeGenerator {
  /// Creates an [IdeGenerator]. Stateless — all functionality is exposed via
  /// static methods.
  const IdeGenerator();

  /// Generates or updates IDE configurations for [tenant].
  ///
  /// [projectRoot] is the root directory of the Flutter application.
  /// [ideRoot] is the directory where `.vscode` and `.run` configurations
  /// will be written. Defaults to [projectRoot] if omitted.
  /// [configPath] is the optional path to a custom `white_label.yaml` file.
  static void generate(
    TenantConfig tenant, {
    required String projectRoot,
    String? ideRoot,
    String? configPath,
  }) {
    final String effectiveIdeRoot = ideRoot ?? projectRoot;
    generateVsCodeConfig(
      tenant,
      projectRoot: projectRoot,
      ideRoot: effectiveIdeRoot,
    );
    generateVsCodeTasks(
      tenant,
      projectRoot: projectRoot,
      ideRoot: effectiveIdeRoot,
      configPath: configPath,
    );
    generateIntelliJConfigs(
      tenant,
      projectRoot: projectRoot,
      ideRoot: effectiveIdeRoot,
      configPath: configPath,
    );
  }

  /// Removes IDE configurations for [tenantId].
  ///
  /// [projectRoot] is the root directory of the Flutter application.
  /// [ideRoot] is the directory where `.vscode` and `.run` configurations
  /// are stored. Defaults to [projectRoot] if omitted.
  static void remove(
    String tenantId, {
    required String projectRoot,
    String? ideRoot,
  }) {
    final String effectiveIdeRoot = ideRoot ?? projectRoot;
    removeVsCodeConfig(
      tenantId,
      projectRoot: projectRoot,
      ideRoot: effectiveIdeRoot,
    );
    removeVsCodeTasks(
      tenantId,
      projectRoot: projectRoot,
      ideRoot: effectiveIdeRoot,
    );
    removeIntelliJConfigs(
      tenantId,
      projectRoot: projectRoot,
      ideRoot: effectiveIdeRoot,
    );
  }

  /// Generates VS Code configurations in `<ideRoot>/.vscode/launch.json`.
  static void generateVsCodeConfig(
    TenantConfig tenant, {
    required String projectRoot,
    String? ideRoot,
  }) {
    final String effectiveIdeRoot = ideRoot ?? projectRoot;
    final vscodeDir = Directory(p.join(effectiveIdeRoot, '.vscode'));
    if (!vscodeDir.existsSync()) {
      vscodeDir.createSync(recursive: true);
    }

    final launchFile = File(p.join(vscodeDir.path, 'launch.json'));
    Map<String, dynamic> data;

    if (launchFile.existsSync()) {
      try {
        final String content = launchFile.readAsStringSync();
        data = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {
        data = <String, dynamic>{
          'version': '0.2.0',
          'configurations': <dynamic>[],
        };
      }
    } else {
      data = <String, dynamic>{
        'version': '0.2.0',
        'configurations': <dynamic>[],
      };
    }

    final List<dynamic> rawConfigs =
        (data['configurations'] as List<dynamic>?) ?? <dynamic>[];
    final List<Map<String, dynamic>> configs = rawConfigs
        .cast<Map<String, dynamic>>();

    // Remove existing configs for this tenant
    configs.removeWhere((c) {
      final List<String> args =
          (c['args'] as List<dynamic>?)?.cast<String>() ?? <String>[];
      final int flavorIdx = args.indexOf('--flavor');
      if (flavorIdx != -1 && flavorIdx + 1 < args.length) {
        return args[flavorIdx + 1] == tenant.id;
      }
      return false;
    });

    final modes = <Map<String, String>>[
      {'suffix': '(debug)', 'mode': 'debug'},
      {'suffix': '(profile)', 'mode': 'profile'},
      {'suffix': '(release)', 'mode': 'release'},
    ];

    final String relProj = p.relative(projectRoot, from: effectiveIdeRoot);
    final String programPath = (relProj == '.' || relProj.isEmpty)
        ? 'lib/main.dart'
        : p.posix.joinAll([...p.split(relProj), 'lib', 'main.dart']);

    for (final mode in modes) {
      final config = <String, dynamic>{
        'name': '${tenant.name} ${mode['suffix']}',
        'request': 'launch',
        'type': 'dart',
        'program': programPath,
        if (mode['mode'] != 'debug') 'flutterMode': mode['mode'],
        'args': <String>[
          '--flavor',
          tenant.id,
          '--dart-define=TENANT_ID=${tenant.id}',
        ],
      };
      configs.add(config);
    }

    data['configurations'] = configs;
    const encoder = JsonEncoder.withIndent('  ');
    launchFile.writeAsStringSync('${encoder.convert(data)}\n');
  }

  /// Generates VS Code 1-click build tasks in `<ideRoot>/.vscode/tasks.json`.
  static void generateVsCodeTasks(
    TenantConfig tenant, {
    required String projectRoot,
    String? ideRoot,
    String? configPath,
  }) {
    final String effectiveIdeRoot = ideRoot ?? projectRoot;
    final vscodeDir = Directory(p.join(effectiveIdeRoot, '.vscode'));
    if (!vscodeDir.existsSync()) {
      vscodeDir.createSync(recursive: true);
    }

    final tasksFile = File(p.join(vscodeDir.path, 'tasks.json'));
    Map<String, dynamic> data;

    if (tasksFile.existsSync()) {
      try {
        final String content = tasksFile.readAsStringSync();
        data = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {
        data = <String, dynamic>{'version': '2.0.0', 'tasks': <dynamic>[]};
      }
    } else {
      data = <String, dynamic>{'version': '2.0.0', 'tasks': <dynamic>[]};
    }

    final List<dynamic> rawTasks =
        (data['tasks'] as List<dynamic>?) ?? <dynamic>[];
    final List<Map<String, dynamic>> tasks = rawTasks
        .cast<Map<String, dynamic>>();

    // Remove existing tasks for this tenant
    tasks.removeWhere((t) {
      final String label = t['label']?.toString() ?? '';
      return label.contains('(${tenant.name})') ||
          label.contains('(${tenant.id})');
    });

    final String relProj = p.relative(projectRoot, from: effectiveIdeRoot);
    final bool isMonorepo = relProj != '.' && relProj.isNotEmpty;
    final String relProjPosix = isMonorepo
        ? p.posix.joinAll(p.split(relProj))
        : '';
    final String relIdeFromProj = isMonorepo
        ? p.posix.joinAll(
            p.split(p.relative(effectiveIdeRoot, from: projectRoot)),
          )
        : '.';

    final String shellEscapedRelProj = relProjPosix.replaceAll("'", r"'\''");
    final String shellEscapedRelIde = relIdeFromProj.replaceAll("'", r"'\''");
    final String configFlag = configPath != null
        ? " --config '${configPath.replaceAll("'", r"'\''")}'"
        : '';

    final String cdPrefix = isMonorepo ? "cd '$shellEscapedRelProj' && " : '';
    final String generateCmd =
        'dart run white_label_kit:generate --tenant ${tenant.id}$configFlag';

    tasks.add({
      'label': '🚀 Build Release APK (${tenant.name})',
      'type': 'shell',
      'command':
          '$cdPrefix$generateCmd && flutter build apk --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
      'group': {'kind': 'build', 'isDefault': true},
      'problemMatcher': <String>[],
    });

    tasks.add({
      'label': '📦 Build Release AppBundle (${tenant.name})',
      'type': 'shell',
      'command':
          '$cdPrefix$generateCmd && flutter build appbundle --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
      'group': 'build',
      'problemMatcher': <String>[],
    });

    tasks.add({
      'label': '🍎 Build Release iOS (${tenant.name})',
      'type': 'shell',
      'command':
          '$cdPrefix$generateCmd && flutter build ios --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
      'group': 'build',
      'problemMatcher': <String>[],
    });

    // Ensure general configure task exists
    final String configureCmd = isMonorepo
        ? "cd '$shellEscapedRelProj' && dart run white_label_kit:configure --ide-root '$shellEscapedRelIde'$configFlag"
        : 'dart run white_label_kit:configure$configFlag';

    tasks.removeWhere((t) => t['label'] == '🔧 Configure White-Label');
    tasks.add({
      'label': '🔧 Configure White-Label',
      'type': 'shell',
      'command': configureCmd,
      'problemMatcher': <String>[],
    });

    data['tasks'] = tasks;
    const encoder = JsonEncoder.withIndent('  ');
    tasksFile.writeAsStringSync('${encoder.convert(data)}\n');
  }

  /// Removes VS Code launch configurations for [tenantId].
  static void removeVsCodeConfig(
    String tenantId, {
    required String projectRoot,
    String? ideRoot,
  }) {
    final String effectiveIdeRoot = ideRoot ?? projectRoot;
    final launchFile = File(p.join(effectiveIdeRoot, '.vscode', 'launch.json'));
    if (!launchFile.existsSync()) {
      return;
    }

    try {
      final String content = launchFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final List<dynamic> rawConfigs =
          (data['configurations'] as List<dynamic>?) ?? <dynamic>[];
      final List<Map<String, dynamic>> configs = rawConfigs
          .cast<Map<String, dynamic>>();

      final int before = configs.length;
      configs.removeWhere((c) {
        final List<String> args =
            (c['args'] as List<dynamic>?)?.cast<String>() ?? <String>[];
        final int flavorIdx = args.indexOf('--flavor');
        if (flavorIdx != -1 && flavorIdx + 1 < args.length) {
          return args[flavorIdx + 1] == tenantId;
        }
        return false;
      });

      if (configs.length != before) {
        data['configurations'] = configs;
        const encoder = JsonEncoder.withIndent('  ');
        launchFile.writeAsStringSync('${encoder.convert(data)}\n');
      }
    } catch (_) {}
  }

  /// Removes VS Code tasks for [tenantId].
  static void removeVsCodeTasks(
    String tenantId, {
    required String projectRoot,
    String? ideRoot,
  }) {
    final String effectiveIdeRoot = ideRoot ?? projectRoot;
    final tasksFile = File(p.join(effectiveIdeRoot, '.vscode', 'tasks.json'));
    if (!tasksFile.existsSync()) {
      return;
    }

    try {
      final String content = tasksFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final List<dynamic> rawTasks =
          (data['tasks'] as List<dynamic>?) ?? <dynamic>[];
      final List<Map<String, dynamic>> tasks = rawTasks
          .cast<Map<String, dynamic>>();

      final int before = tasks.length;
      tasks.removeWhere((t) {
        final String cmd = t['command']?.toString() ?? '';
        return cmd.contains('--flavor $tenantId');
      });

      if (tasks.length != before) {
        data['tasks'] = tasks;
        const encoder = JsonEncoder.withIndent('  ');
        tasksFile.writeAsStringSync('${encoder.convert(data)}\n');
      }
    } catch (_) {}
  }

  /// Generates Android Studio / IntelliJ IDEA run configs in `<ideRoot>/.run/`.
  static void generateIntelliJConfigs(
    TenantConfig tenant, {
    required String projectRoot,
    String? ideRoot,
    String? configPath,
  }) {
    final String effectiveIdeRoot = ideRoot ?? projectRoot;
    final runDir = Directory(p.join(effectiveIdeRoot, '.run'));
    if (!runDir.existsSync()) {
      runDir.createSync(recursive: true);
    }

    final String relProj = p.relative(projectRoot, from: effectiveIdeRoot);
    final bool isMonorepo = relProj != '.' && relProj.isNotEmpty;
    final String relProjPosix = isMonorepo
        ? p.posix.joinAll(p.split(relProj))
        : '';

    final String configFlag = configPath != null
        ? " --config '${configPath.replaceAll("'", r"'\''")}'"
        : '';

    final String filePath = isMonorepo
        ? '\$PROJECT_DIR\$/$relProjPosix/lib/main.dart'
        : '\$PROJECT_DIR\$/lib/main.dart';

    final String scriptWorkingDir = isMonorepo
        ? '\$PROJECT_DIR\$/$relProjPosix'
        : '\$PROJECT_DIR\$';

    // 1. Flutter Debug Run
    final String debugXml = _intellijFlutterRunConfigXml(
      name: '${tenant.name} (debug)',
      flavor: tenant.id,
      filePath: filePath,
    );
    File(p.join(runDir.path, '${tenant.id}_debug.run.xml'))
        .writeAsStringSync(debugXml);

    // 2. Flutter Release Run
    final String releaseXml = _intellijFlutterRunConfigXml(
      name: '${tenant.name} (release)',
      flavor: tenant.id,
      filePath: filePath,
      extraArgs: '--release',
    );
    File(p.join(runDir.path, '${tenant.id}_release.run.xml'))
        .writeAsStringSync(releaseXml);

    // 3. Build Release APK
    final String buildApkXml = _intellijShellRunConfigXml(
      name: '🚀 Build APK (${tenant.name})',
      script:
          'dart run white_label_kit:generate --tenant ${tenant.id}$configFlag && flutter build apk --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
      workingDirectory: scriptWorkingDir,
    );
    File(p.join(runDir.path, '${tenant.id}_build_apk.run.xml'))
        .writeAsStringSync(buildApkXml);

    // 4. Build Release AppBundle
    final String buildAabXml = _intellijShellRunConfigXml(
      name: '📦 Build AppBundle (${tenant.name})',
      script:
          'dart run white_label_kit:generate --tenant ${tenant.id}$configFlag && flutter build appbundle --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
      workingDirectory: scriptWorkingDir,
    );
    File(p.join(runDir.path, '${tenant.id}_build_appbundle.run.xml'))
        .writeAsStringSync(buildAabXml);

    // 5. Build Release iOS
    final String buildIosXml = _intellijShellRunConfigXml(
      name: '🍎 Build iOS (${tenant.name})',
      script:
          'dart run white_label_kit:generate --tenant ${tenant.id}$configFlag && flutter build ios --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
      workingDirectory: scriptWorkingDir,
    );
    File(p.join(runDir.path, '${tenant.id}_build_ios.run.xml'))
        .writeAsStringSync(buildIosXml);

    // 6. Configure White-Label
    final String relIdeFromProj = isMonorepo
        ? p.posix.joinAll(
            p.split(p.relative(effectiveIdeRoot, from: projectRoot)),
          )
        : '.';
    final String shellEscapedRelIde = relIdeFromProj.replaceAll("'", r"'\''");

    final String configureScript = isMonorepo
        ? "dart run white_label_kit:configure --ide-root '$shellEscapedRelIde'$configFlag"
        : 'dart run white_label_kit:configure$configFlag';

    final String configureXml = _intellijShellRunConfigXml(
      name: '🔧 Configure White-Label',
      script: configureScript,
      workingDirectory: scriptWorkingDir,
    );
    File(p.join(runDir.path, 'configure_white_label.run.xml'))
        .writeAsStringSync(configureXml);
  }

  /// Removes Android Studio / IntelliJ IDEA run configs for [tenantId].
  static void removeIntelliJConfigs(
    String tenantId, {
    required String projectRoot,
    String? ideRoot,
  }) {
    final String effectiveIdeRoot = ideRoot ?? projectRoot;
    final runDir = Directory(p.join(effectiveIdeRoot, '.run'));
    if (!runDir.existsSync()) {
      return;
    }

    for (final File file in runDir.listSync().whereType<File>()) {
      final String base = p.basename(file.path);
      if (base.startsWith('${tenantId}_') && base.endsWith('.run.xml')) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
  }

  static String _intellijFlutterRunConfigXml({
    required String name,
    required String flavor,
    String filePath = r'$PROJECT_DIR$/lib/main.dart',
    String? extraArgs,
  }) {
    final String args = [
      '--dart-define=TENANT_ID=$flavor',
      ?extraArgs,
    ].join(' ');

    return '''
<component name="ProjectRunConfigurationManager">
  <!-- Generated by white_label_kit — DO NOT EDIT BY HAND -->
  <configuration default="false" name="$name" type="FlutterRunConfigurationType" factoryName="Flutter">
    <option name="filePath" value="$filePath" />
    <option name="buildFlavor" value="$flavor" />
    <option name="additionalArgs" value="$args" />
    <method v="2" />
  </configuration>
</component>
''';
  }

  static String _intellijShellRunConfigXml({
    required String name,
    required String script,
    String workingDirectory = r'$PROJECT_DIR$',
  }) {
    return '''
<component name="ProjectRunConfigurationManager">
  <!-- Generated by white_label_kit — DO NOT EDIT BY HAND -->
  <configuration default="false" name="$name" type="ShConfigurationType">
    <option name="SCRIPT_TEXT" value="$script" />
    <option name="INDEPENDENT_SCRIPT_PATH" value="true" />
    <option name="SCRIPT_PATH" value="" />
    <option name="SCRIPT_OPTIONS" value="" />
    <option name="INDEPENDENT_SCRIPT_WORKING_DIRECTORY" value="true" />
    <option name="SCRIPT_WORKING_DIRECTORY" value="$workingDirectory" />
    <option name="INDEPENDENT_INTERPRETER_PATH" value="true" />
    <option name="INTERPRETER_PATH" value="/bin/zsh" />
    <option name="INTERPRETER_OPTIONS" value="" />
    <option name="EXECUTE_IN_TERMINAL" value="true" />
    <method v="2" />
  </configuration>
</component>
''';
  }
}
