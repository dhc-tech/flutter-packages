import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';

class CreateJksCommand extends Command {
  @override
  final name = 'create-jks';
  @override
  final description =
      'Generates a new Android JKS keystore and automates signing setup.';
  CreateJksCommand() {
    argParser.addOption('name', help: 'JKS name (without extension)');
    argParser.addOption('location', help: 'Save location path');
    argParser.addOption('alias', help: 'Key alias');
    argParser.addOption('store-pass', help: 'Keystore password');
    argParser.addOption('key-pass', help: 'Key password');
    argParser.addOption('ou', help: 'Organizational Unit');
    argParser.addFlag('no-interactive',
        negatable: false, help: 'Run without user prompts');
  }
  @override
  Future<void> run() async {
    final noInteractive = argResults?['no-interactive'] == true;

    if (!noInteractive) {
      kLog('\n🔐 Android JKS & Signing Setup Tool', type: LogType.info);
    }

    final projectRoot = findProjectRoot();
    final isInsideFlutter = projectRoot != null;

    // 1. Auto-detect JKS Name
    String defaultJksName = 'release_keystore';
    if (isInsideFlutter) {
      final detectedId = await _detectPackageId(projectRoot.path);
      if (detectedId != null) {
        final parts = detectedId.split('.');
        defaultJksName = parts.last;
      }
    }

    String baseName;
    if (argResults?['name'] != null) {
      baseName = argResults!['name'];
    } else if (noInteractive) {
      baseName = defaultJksName;
    } else {
      stdout.write('Enter JKS name (default: $defaultJksName): ');
      String? input = stdin.readLineSync()?.trim();
      baseName = (input == null || input.isEmpty) ? defaultJksName : input;
    }

    if (baseName.toLowerCase().endsWith('.jks')) {
      baseName = baseName.substring(0, baseName.length - 4);
    }
    final fullJksName = '$baseName.jks';

    // 2. Prompt for Save Location
    String defaultSavePath = await getDesktopPath();
    if (isInsideFlutter) {
      defaultSavePath = p.join(projectRoot.path, 'android', 'app');
    }

    String finalDirPath;
    if (argResults?['location'] != null) {
      finalDirPath = argResults!['location'];
    } else if (noInteractive) {
      finalDirPath = defaultSavePath;
    } else {
      stdout.write('Enter save location (default: $defaultSavePath): ');
      String? input = stdin.readLineSync()?.trim();
      finalDirPath = (input == null || input.isEmpty) ? defaultSavePath : input;
    }

    final finalDir = Directory(finalDirPath);
    if (!await finalDir.exists()) {
      await finalDir.create(recursive: true);
    }

    final jksFile = File(p.join(finalDir.path, fullJksName));

    if (await jksFile.exists() && !noInteractive) {
      stdout.write('⚠️  File $fullJksName already exists. Overwrite? (y/N): ');
      if (stdin.readLineSync()?.trim().toLowerCase() != 'y') {
        kLog('Aborted.', type: LogType.warning);
        return;
      }
    }

    // 3. Prompt for credentials
    String alias = argResults?['alias'] ?? 'key';
    if (!noInteractive && argResults?['alias'] == null) {
      stdout.write('Enter key alias (default: key): ');
      String? input = stdin.readLineSync()?.trim();
      if (input != null && input.isNotEmpty) alias = input;
    }

    String storePass = argResults?['store-pass'] ?? '123456';
    if (!noInteractive && argResults?['store-pass'] == null) {
      stdout.write('Enter store password (min 6 chars, default: 123456): ');
      String? input = stdin.readLineSync()?.trim();
      if (input != null && input.isNotEmpty) storePass = input;
    }

    if (storePass.length < 6) {
      kLog('❗ Store password must be at least 6 characters.',
          type: LogType.error);
      return;
    }

    String keyPass = argResults?['key-pass'] ?? storePass;
    if (!noInteractive && argResults?['key-pass'] == null) {
      stdout.write('Enter key password (default: same as store password): ');
      String? input = stdin.readLineSync()?.trim();
      if (input != null && input.isNotEmpty) keyPass = input;
    }

    String ou = argResults?['ou'] ?? 'Android';
    if (!noInteractive && argResults?['ou'] == null) {
      stdout.write('Enter Organizational Unit (e.g., Development): ');
      String? input = stdin.readLineSync()?.trim();
      if (input != null && input.isNotEmpty) ou = input;
    }

    // 4. Generate JKS using keytool
    final dname = 'CN=$alias, OU=$ou, O=$ou, L=City, S=State, C=US';

    // Check if keytool is available
    final keytoolCheck = await Process.run('which', ['keytool']);
    if (keytoolCheck.exitCode != 0) {
      kLog(
          '❗ "keytool" command not found. Please ensure JDK is installed and in your PATH.',
          type: LogType.error);
      return;
    }

    try {
      final result = await runWithSpinner(
        '🚧 Generating JKS file...',
        () => Process.run('keytool', [
          '-genkeypair',
          '-v',
          '-keystore',
          jksFile.path,
          '-alias',
          alias,
          '-keyalg',
          'RSA',
          '-keysize',
          '2048',
          '-validity',
          '10000',
          '-storepass',
          storePass,
          '-keypass',
          keyPass,
          '-dname',
          dname,
        ]),
      );

      if (result.exitCode != 0) {
        kLog('❗ Failed to generate JKS.', type: LogType.error);
        kLog('Error: ${result.stderr}', type: LogType.error);
        return;
      }

      kLog('\n✅ JKS file created: ${jksFile.path}', type: LogType.success);

      // 5. Automated setup if inside Flutter project
      if (isInsideFlutter) {
        await runWithSpinner('📦 Automating Android setup...', () async {
          // Create key.properties in android/
          final keyPropertiesFile =
              File(p.join(projectRoot.path, 'android', 'key.properties'));

          // Use absolute path in key.properties for "0 work" robustness
          final propertiesContent = '''storePassword=$storePass
keyPassword=$keyPass
keyAlias=$alias
storeFile=${p.basename(jksFile.path)}''';

          await keyPropertiesFile.writeAsString(propertiesContent);

          // Update build.gradle
          await _updateBuildGradle(projectRoot.path);
        });
        kLog('✅ Android signing setup complete!', type: LogType.success);
        kLog('📝 key.properties created in android/', type: LogType.info);
      }

      // Final summary
      kLog('\n🚀 Summary:', type: LogType.info);
      kLog('   • JKS Path: ${jksFile.path}', type: LogType.info);
      kLog('   • Alias: $alias', type: LogType.info);
      kLog('   • Passwords: $storePass', type: LogType.info);
      kLog(
          '   • Status: Your project is ready for "flutter build apk --release"',
          type: LogType.success);
    } catch (e) {
      kLog('❌ An error occurred: $e', type: LogType.error);
    }
  }

  Future<String?> _detectPackageId(String projectPath) async {
    return await getBundleId();
  }

  Future<void> _updateBuildGradle(String projectPath) async {
    final appDir = p.join(projectPath, 'android', 'app');
    File? buildGradleFile;
    bool isKotlin = false;

    if (await File(p.join(appDir, 'build.gradle.kts')).exists()) {
      buildGradleFile = File(p.join(appDir, 'build.gradle.kts'));
      isKotlin = true;
    } else if (await File(p.join(appDir, 'build.gradle')).exists()) {
      buildGradleFile = File(p.join(appDir, 'build.gradle'));
    }

    if (buildGradleFile == null) return;

    String content = await buildGradleFile.readAsString();

    // 1. Add Imports
    if (!content.contains('java.util.Properties')) {
      content =
          'import java.util.Properties\nimport java.io.FileInputStream\n$content';
    }

    // 2. Add properties loading logic
    final loadingSnippet = isKotlin
        ? '''
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
'''
        : '''
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
''';

    if (!content.contains('keystorePropertiesFile')) {
      if (content.contains('plugins {')) {
        int pluginsEnd = content.indexOf('}', content.indexOf('plugins {')) + 1;
        content =
            '${content.substring(0, pluginsEnd)}\n$loadingSnippet${content.substring(pluginsEnd)}';
      } else {
        content = '$loadingSnippet\n$content';
      }
    }

    // 3. Define signing configs
    final releaseConfig = isKotlin
        ? '''        create("release") {
            keyAlias = keystoreProperties["keyAlias"]?.toString()
            keyPassword = keystoreProperties["keyPassword"]?.toString()
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"]?.toString()
        }'''
        : '''        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }''';

    // Update or Insert signingConfigs
    if (content.contains('signingConfigs {')) {
      if (!content.contains('release {') &&
          !content.contains('create("release")')) {
        content = content.replaceFirst(
            'signingConfigs {', 'signingConfigs {\n$releaseConfig');
      }
    } else if (content.contains('android {')) {
      content = content.replaceFirst('android {',
          'android {\n    signingConfigs {\n$releaseConfig\n    }\n');
    }

    // 4. Update buildTypes
    if (content.contains('buildTypes {')) {
      if (content.contains('release {')) {
        if (!content.contains('signingConfig')) {
          final signingLine = isKotlin
              ? '            signingConfig = signingConfigs.getByName("release")'
              : '            signingConfig signingConfigs.release';
          content =
              content.replaceFirst('release {', 'release {\n$signingLine');
        }
      }
    }

    await buildGradleFile.writeAsString(content);
  }
}

Future<void> handleCreateJksCommand() async {
  final command = CreateJksCommand();
  await command.run();
}
