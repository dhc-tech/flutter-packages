import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/tenant_config.dart';

/// Generates IDE run/debug and build task configurations for VS Code and Android Studio / IntelliJ.
///
/// Enables developers to 1-click Run, Debug, and Build any tenant flavor directly
/// from IDE UI menus without typing commands in terminal.
class IdeGenerator {
  const IdeGenerator();

  /// Generates or updates IDE configurations for [tenant] in [projectRoot].
  static void generate(TenantConfig tenant, {required String projectRoot}) {
    generateVsCodeConfig(tenant, projectRoot: projectRoot);
    generateVsCodeTasks(tenant, projectRoot: projectRoot);
    generateIntelliJConfigs(tenant, projectRoot: projectRoot);
  }

  /// Removes IDE configurations for [tenantId] from [projectRoot].
  static void remove(String tenantId, {required String projectRoot}) {
    removeVsCodeConfig(tenantId, projectRoot: projectRoot);
    removeVsCodeTasks(tenantId, projectRoot: projectRoot);
    removeIntelliJConfigs(tenantId, projectRoot: projectRoot);
  }

  /// Generates VS Code configurations in `<projectRoot>/.vscode/launch.json`.
  static void generateVsCodeConfig(
    TenantConfig tenant, {
    required String projectRoot,
  }) {
    final vscodeDir = Directory(p.join(projectRoot, '.vscode'));
    if (!vscodeDir.existsSync()) {
      vscodeDir.createSync(recursive: true);
    }

    final launchFile = File(p.join(vscodeDir.path, 'launch.json'));
    Map<String, dynamic> data;

    if (launchFile.existsSync()) {
      try {
        final content = launchFile.readAsStringSync();
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

    final rawConfigs =
        (data['configurations'] as List<dynamic>?) ?? <dynamic>[];
    final configs = rawConfigs.cast<Map<String, dynamic>>();

    // Remove existing configs for this tenant
    configs.removeWhere((c) {
      final args = (c['args'] as List<dynamic>?)?.cast<String>() ?? <String>[];
      final flavorIdx = args.indexOf('--flavor');
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

    for (final mode in modes) {
      final config = <String, dynamic>{
        'name': '${tenant.name} ${mode['suffix']}',
        'request': 'launch',
        'type': 'dart',
        'program': 'lib/main.dart',
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

  /// Generates VS Code 1-click build tasks in `<projectRoot>/.vscode/tasks.json`.
  static void generateVsCodeTasks(
    TenantConfig tenant, {
    required String projectRoot,
  }) {
    final vscodeDir = Directory(p.join(projectRoot, '.vscode'));
    if (!vscodeDir.existsSync()) {
      vscodeDir.createSync(recursive: true);
    }

    final tasksFile = File(p.join(vscodeDir.path, 'tasks.json'));
    Map<String, dynamic> data;

    if (tasksFile.existsSync()) {
      try {
        final content = tasksFile.readAsStringSync();
        data = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {
        data = <String, dynamic>{'version': '2.0.0', 'tasks': <dynamic>[]};
      }
    } else {
      data = <String, dynamic>{'version': '2.0.0', 'tasks': <dynamic>[]};
    }

    final rawTasks = (data['tasks'] as List<dynamic>?) ?? <dynamic>[];
    final tasks = rawTasks.cast<Map<String, dynamic>>();

    // Remove existing tasks for this tenant
    tasks.removeWhere((t) {
      final label = t['label']?.toString() ?? '';
      return label.contains('(${tenant.name})') ||
          label.contains('(${tenant.id})');
    });

    tasks.add({
      'label': '🚀 Build Release APK (${tenant.name})',
      'type': 'shell',
      'command':
          'dart run white_label_kit:generate --tenant ${tenant.id} && flutter build apk --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
      'group': {'kind': 'build', 'isDefault': true},
      'problemMatcher': <String>[],
    });

    tasks.add({
      'label': '📦 Build Release AppBundle (${tenant.name})',
      'type': 'shell',
      'command':
          'dart run white_label_kit:generate --tenant ${tenant.id} && flutter build appbundle --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
      'group': 'build',
      'problemMatcher': <String>[],
    });

    tasks.add({
      'label': '🍎 Build Release iOS (${tenant.name})',
      'type': 'shell',
      'command':
          'dart run white_label_kit:generate --tenant ${tenant.id} && flutter build ios --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
      'group': 'build',
      'problemMatcher': <String>[],
    });

    // Ensure general configure task exists
    if (!tasks.any((t) => t['label'] == '🔧 Configure White-Label')) {
      tasks.add({
        'label': '🔧 Configure White-Label',
        'type': 'shell',
        'command': 'dart run white_label_kit:configure',
        'problemMatcher': <String>[],
      });
    }

    data['tasks'] = tasks;
    const encoder = JsonEncoder.withIndent('  ');
    tasksFile.writeAsStringSync('${encoder.convert(data)}\n');
  }

  /// Removes VS Code launch configurations for [tenantId].
  static void removeVsCodeConfig(
    String tenantId, {
    required String projectRoot,
  }) {
    final launchFile = File(p.join(projectRoot, '.vscode', 'launch.json'));
    if (!launchFile.existsSync()) return;

    try {
      final content = launchFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final rawConfigs =
          (data['configurations'] as List<dynamic>?) ?? <dynamic>[];
      final configs = rawConfigs.cast<Map<String, dynamic>>();

      final before = configs.length;
      configs.removeWhere((c) {
        final args =
            (c['args'] as List<dynamic>?)?.cast<String>() ?? <String>[];
        final flavorIdx = args.indexOf('--flavor');
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
  }) {
    final tasksFile = File(p.join(projectRoot, '.vscode', 'tasks.json'));
    if (!tasksFile.existsSync()) return;

    try {
      final content = tasksFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final rawTasks = (data['tasks'] as List<dynamic>?) ?? <dynamic>[];
      final tasks = rawTasks.cast<Map<String, dynamic>>();

      final before = tasks.length;
      tasks.removeWhere((t) {
        final cmd = t['command']?.toString() ?? '';
        return cmd.contains('--flavor $tenantId');
      });

      if (tasks.length != before) {
        data['tasks'] = tasks;
        const encoder = JsonEncoder.withIndent('  ');
        tasksFile.writeAsStringSync('${encoder.convert(data)}\n');
      }
    } catch (_) {}
  }

  /// Generates Android Studio / IntelliJ IDEA run configs in `<projectRoot>/.run/`.
  static void generateIntelliJConfigs(
    TenantConfig tenant, {
    required String projectRoot,
  }) {
    final runDir = Directory(p.join(projectRoot, '.run'));
    if (!runDir.existsSync()) {
      runDir.createSync(recursive: true);
    }

    // 1. Flutter Debug Run
    final debugXml = _intellijFlutterRunConfigXml(
      name: '${tenant.name} (debug)',
      flavor: tenant.id,
    );
    File(p.join(runDir.path, '${tenant.id}_debug.run.xml'))
        .writeAsStringSync(debugXml);

    // 2. Flutter Release Run
    final releaseXml = _intellijFlutterRunConfigXml(
      name: '${tenant.name} (release)',
      flavor: tenant.id,
      extraArgs: '--release',
    );
    File(p.join(runDir.path, '${tenant.id}_release.run.xml'))
        .writeAsStringSync(releaseXml);

    // 3. Build Release APK
    final buildApkXml = _intellijShellRunConfigXml(
      name: '🚀 Build APK (${tenant.name})',
      script:
          'dart run white_label_kit:generate --tenant ${tenant.id} && flutter build apk --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
    );
    File(p.join(runDir.path, '${tenant.id}_build_apk.run.xml'))
        .writeAsStringSync(buildApkXml);

    // 4. Build Release AppBundle
    final buildAabXml = _intellijShellRunConfigXml(
      name: '📦 Build AppBundle (${tenant.name})',
      script:
          'dart run white_label_kit:generate --tenant ${tenant.id} && flutter build appbundle --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
    );
    File(p.join(runDir.path, '${tenant.id}_build_appbundle.run.xml'))
        .writeAsStringSync(buildAabXml);

    // 5. Build Release iOS
    final buildIosXml = _intellijShellRunConfigXml(
      name: '🍎 Build iOS (${tenant.name})',
      script:
          'dart run white_label_kit:generate --tenant ${tenant.id} && flutter build ios --release --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
    );
    File(p.join(runDir.path, '${tenant.id}_build_ios.run.xml'))
        .writeAsStringSync(buildIosXml);

    // 6. Configure White-Label
    final configureXml = _intellijShellRunConfigXml(
      name: '🔧 Configure White-Label',
      script: 'dart run white_label_kit:configure',
    );
    File(p.join(runDir.path, 'configure_white_label.run.xml'))
        .writeAsStringSync(configureXml);
  }

  /// Removes Android Studio / IntelliJ IDEA run configs for [tenantId].
  static void removeIntelliJConfigs(
    String tenantId, {
    required String projectRoot,
  }) {
    final runDir = Directory(p.join(projectRoot, '.run'));
    if (!runDir.existsSync()) return;

    for (final file in runDir.listSync().whereType<File>()) {
      final base = p.basename(file.path);
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
    String? extraArgs,
  }) {
    final args = ['--dart-define=TENANT_ID=$flavor', ?extraArgs].join(' ');

    return '''<component name="ProjectRunConfigurationManager">
  <!-- Generated by white_label_kit — DO NOT EDIT BY HAND -->
  <configuration default="false" name="$name" type="FlutterRunConfigurationType" factoryName="Flutter">
    <option name="filePath" value="\$PROJECT_DIR\$/lib/main.dart" />
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
  }) {
    return '''<component name="ProjectRunConfigurationManager">
  <!-- Generated by white_label_kit — DO NOT EDIT BY HAND -->
  <configuration default="false" name="$name" type="ShConfigurationType">
    <option name="SCRIPT_TEXT" value="$script" />
    <option name="INDEPENDENT_SCRIPT_PATH" value="true" />
    <option name="SCRIPT_PATH" value="" />
    <option name="SCRIPT_OPTIONS" value="" />
    <option name="INDEPENDENT_SCRIPT_WORKING_DIRECTORY" value="true" />
    <option name="SCRIPT_WORKING_DIRECTORY" value="\$PROJECT_DIR\$" />
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
