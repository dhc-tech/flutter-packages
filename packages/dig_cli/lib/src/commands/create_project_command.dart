import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';
import 'asset_command.dart';
import 'create_jks_command.dart';
import '../utils/project_rebrander.dart';
import '../ui/box_painter.dart';

class CreateProjectCommand extends Command {
  String _githubRepo = 'Digvijaysinh2204/dig_template';
  String _githubBranch = 'main';

  @override
  final name = 'create-project';
  @override
  final description =
      'Creates a new Flutter project from a template and sets up signing.';

  CreateProjectCommand() {
    argParser.addOption('name',
        abbr: 'n',
        help: 'The name of the new project folder/slug (e.g., "my_app")');
    argParser.addOption('app-name',
        abbr: 'a', help: 'The app display name (e.g., "My Awesome App")');
    argParser.addOption('bundle-id',
        abbr: 'b', help: 'The bundle ID/package name (e.g., com.example.app)');
    argParser.addOption('output',
        abbr: 'o', help: 'The directory where the project should be created');
    argParser.addFlag('github',
        abbr: 'g',
        help:
            'Fetch the template from GitHub (always gets the latest version).',
        defaultsTo: false);
    argParser.addOption('github-repo',
        help: 'GitHub repository to fetch template from (user/repo)',
        defaultsTo: 'Digvijaysinh2204/dig_template');
    argParser.addOption('github-branch',
        help: 'Branch to fetch template from', defaultsTo: 'main');
  }

  @override
  Future<void> run() async {
    kLog('\n🚀 CREATE PROJECT FROM TEMPLATE', type: LogType.info);

    _githubRepo = argResults?['github-repo'] ?? 'Digvijaysinh2204/dig_template';
    _githubBranch = argResults?['github-branch'] ?? 'main';

    // No longer prompting for y/n since local is gone.
    // If they want to use a specific branch/repo, they use flags.

    // 1. Get Project Details
    String? projectName = argResults?['name'] as String?;
    if (projectName == null || projectName.isEmpty) {
      stdout.write('Enter project name (for folder & pubspec, e.g., my_app): ');
      projectName = stdin.readLineSync()?.trim();
    }
    if (projectName == null || projectName.isEmpty) {
      kLog('❗ Project name is required.', type: LogType.error);
      return;
    }

    // Slugify the project name for safety
    final slug =
        projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');

    String? appName = argResults?['app-name'] as String?;
    if (appName == null || appName.isEmpty) {
      stdout.write('Enter app display name (e.g., My Awesome App): ');
      appName = stdin.readLineSync()?.trim();
    }
    if (appName == null || appName.isEmpty) {
      appName = projectName; // Fallback to project name
    }

    String? bundleId = argResults?['bundle-id'] as String?;
    if (bundleId == null || bundleId.isEmpty) {
      stdout.write('Enter bundle ID (e.g., com.awesome.app): ');
      bundleId = stdin.readLineSync()?.trim();
    }
    if (bundleId == null ||
        bundleId.isEmpty ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)*$')
            .hasMatch(bundleId)) {
      kLog(
          '❗ Valid bundle ID is required (e.g., com.example.app or com.example).',
          type: LogType.error);
      return;
    }

    String? outputDir = argResults?['output'] as String?;
    if (outputDir == null || outputDir.isEmpty) {
      stdout.write('Enter output path (press enter for default ./$slug): ');
      final input = stdin.readLineSync()?.trim();
      if (input != null && input.isNotEmpty) {
        outputDir = input;
      }
    }

    final targetDir = outputDir != null && outputDir.isNotEmpty
        ? Directory(p.absolute(outputDir))
        : Directory(p.join(Directory.current.path, slug));

    if (await targetDir.exists()) {
      kLog('❗ Directory ${targetDir.path} already exists.',
          type: LogType.error);
      return;
    }

    // 2. Locate Template
    String? templatePath = await _findTemplatePath();
    if (templatePath == null) {
      kLog(
          '❗ Template structure not found. Please ensure you are running the command from a valid installation.',
          type: LogType.error);
      return;
    }

    kLog('📂 Creating project at: ${targetDir.path}', type: LogType.info);
    kLog('🏗️  Using template: $templatePath', type: LogType.info);

    try {
      // 3. Run Flutter Create as Base
      await runWithSpinner('🚀 Running flutter create...', () async {
        // Calculate org from bundleId
        String org = 'com.example';
        if (bundleId!.contains('.')) {
          final parts = bundleId.split('.');
          org = parts.sublist(0, parts.length - 1).join('.');
        }

        final result = await Process.run('flutter', [
          'create',
          '--project-name',
          slug,
          '--org',
          org,
          '--description',
          'Created using DIG CLI',
          targetDir.path,
        ]);

        if (result.exitCode != 0) {
          throw Exception('flutter create failed: ${result.stderr}');
        }
      });

      // 3.5 Cleanup Default Assets (To prevent duplicates/ghost files)
      await runWithSpinner('🧹 Clearing default Flutter assets...', () async {
        await _cleanupDefaultFlutterAssets(targetDir);
      });

      // 4. Overlay Template Structure (File-by-File Overlay)
      await runWithSpinner('📝 Applying template overlay...', () async {
        // Iterate through template files (skipping test/)
        await _overlayTemplateFiles(Directory(templatePath), targetDir);

        // C. Merge Pubspec Dependencies
        await _mergePubspec(targetDir, templatePath, slug);
      });

      // 5. Rebranding & Configuration
      await runWithSpinner('🏷️  Finalizing configuration...', () async {
        final rebrander = ProjectRebrander(
          projectDir: targetDir,
          newSlug: slug,
          newAppName: appName!,
          newBundleId: bundleId!,
        );

        await rebrander.rebrand();

        // Android Signing Logic (Specific to creation flow)
        await _configureAndroidSigning(targetDir);

        // README & Environment
        await _updateReadme(targetDir, projectName!);
        await _generateAndInjectSecureKey(targetDir);
      });

      // 6. Generate JKS
      kLog('\n🔑 Setting up Android Signing (0-Work)...', type: LogType.info);
      final originalCwd = Directory.current;
      Directory.current = targetDir;
      resetProjectRootCache();

      final jksRunner = CommandRunner('dg', 'temp')
        ..addCommand(CreateJksCommand());

      await jksRunner.run([
        'create-jks',
        '--no-interactive',
        '--location',
        p.join(targetDir.path, 'android', 'app'),
        '--name',
        slug,
        '--store-pass',
        '123456',
        '--key-pass',
        '123456',
        '--alias',
        'key',
      ]);

      // 7. Cleanup & Finish
      await runWithSpinner('🧹 Cleaning up...', () async {
        // Ensure sample.jks is gone if it somehow got copied
        final sampleJks =
            File(p.join(targetDir.path, 'android', 'app', 'sample.jks'));
        if (await sampleJks.exists()) {
          await sampleJks.delete();
        }

        // Run pub get
        final result = await Process.run('flutter', ['pub', 'get']);
        if (result.exitCode != 0) {
          kLog('⚠️  flutter pub get failed, you might need to run it manually.',
              type: LogType.warning);
        }

        // Run asset generation
        try {
          await buildAssets();
        } catch (e) {
          kLog('⚠️  Initial asset generation failed: $e',
              type: LogType.warning);
        }
      });

      Directory.current = originalCwd;

      // Final summary
      final painter = BoxPainter();
      print('');
      painter.drawHeader('PROJECT CREATED SUCCESSFULLY', width: 60);
      painter.drawRow('Project Name', projectName, width: 60);
      painter.drawRow('Slug', slug, width: 60);
      painter.drawRow('Bundle ID', bundleId, width: 60);
      painter.drawRow('Location', targetDir.path, width: 60);
      painter.drawFooter(width: 60);

      kLog('\n🚀 Summary:', type: LogType.success);
      kLog('   • Your project is ready for development!',
          type: LogType.success);
      kLog('   • Run "cd $slug && flutter run" to start.', type: LogType.info);
    } catch (e) {
      kLog('❌ An error occurred: $e', type: LogType.error);
    }
  }

  Future<String?> _findTemplatePath() async {
    // Only GitHub templates are supported now as local templates have been removed.
    return await _downloadTemplateFromGithub();
  }

  Future<String?> _downloadTemplateFromGithub() async {
    try {
      final repo = _githubRepo;
      final branch = _githubBranch;
      final url =
          Uri.parse('https://github.com/$repo/archive/refs/heads/$branch.zip');

      return await runWithSpinner(
          '🌐 Downloading latest template from GitHub ($repo)...', () async {
        final response = await http.get(url);
        if (response.statusCode != 200) {
          throw Exception(
              'Failed to download template. Status: ${response.statusCode}');
        }

        final bytes = response.bodyBytes;
        final archive = ZipDecoder().decodeBytes(bytes);

        final tempDir =
            await Directory.systemTemp.createTemp('dig_cli_template_');

        for (final file in archive) {
          final filename = file.name;
          if (file.isFile) {
            final data = file.content as List<int>;
            File(p.join(tempDir.path, filename))
              ..createSync(recursive: true)
              ..writeAsBytesSync(data);
          } else {
            Directory(p.join(tempDir.path, filename))
                .createSync(recursive: true);
          }
        }

        // GitHub zip has a root folder named {repo_name}-{branch_name}
        // Inside it, the code is now at the root
        // GitHub zip has a root folder named {repo_name}-{branch_name}
        final rootFolderName = archive.first.name.split('/').first;
        final templatePath = p.join(tempDir.path, rootFolderName);

        String? detectedPath;
        if (await File(p.join(templatePath, 'pubspec.yaml')).exists()) {
          detectedPath = templatePath;
        } else {
          // Fallback search: Look for the first directory that contains pubspec.yaml
          await for (var entity in tempDir.list(recursive: true)) {
            if (entity is File && p.basename(entity.path) == 'pubspec.yaml') {
              detectedPath = p.dirname(entity.path);
              break;
            }
          }
        }

        if (detectedPath != null) {
          return detectedPath;
        } else {
          throw Exception(
              'Template structure not found in the downloaded archive.');
        }
      });
    } catch (e) {
      kLog('❌ Error downloading template: $e', type: LogType.error);
      return null;
    }
  }

  Future<void> _overlayTemplateFiles(
      Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (var entity in source.list(recursive: false)) {
      final base = p.basename(entity.path);

      if (entity is Directory) {
        if (base == 'build' ||
            base == 'Pods' ||
            base == '.dart_tool' ||
            base == '.idea' ||
            base == '.vscode' ||
            base == '.git') {
          continue;
        }
        final newDirectory = Directory(p.join(destination.path, base));
        await _overlayTemplateFiles(entity, newDirectory);
      } else if (entity is File) {
        if (base == '.DS_Store' ||
            base == 'pubspec.lock' ||
            base == 'Podfile.lock' ||
            base.startsWith('.flutter-plugins')) {
          continue;
        }

        // 2. Overwrite or Create
        await entity.copy(p.join(destination.path, base));
      }
    }
  }

  Future<void> _updateReadme(Directory projectDir, String projectName) async {
    final readmeFile = File(p.join(projectDir.path, 'README.md'));
    String content = '';

    if (await readmeFile.exists()) {
      content = await readmeFile.readAsString();
      if (!content.contains('DIG CLI')) {
        content +=
            '\n\n---\nGenerated by [DIG CLI](https://pub.dev/packages/dig_cli) 🚀';
      }
    } else {
      content = '''# 📱 $projectName

Created with building blocks from **DIG CLI**.

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)

## ✨ Features
This project comes pre-configured with a robust foundation:
- 🏗️ **Solid Architecture**: Standardized folder structure for scalability.
- 🔐 **Secure Defaults**: Auto-generated `API_KEY` and `.env` setup.
- 🤖 **Android Ready**: Automated JKS signing configuration.
- 🖼️ **Asset Generation**: Type-safe asset management pre-configured.

## 🚀 Getting Started

### 1️⃣ Setup Environment
```bash
# Get dependencies
flutter pub get
```

### 2️⃣ Asset Generation
Type-safe asset classes are automatically generated from your `assets/` folder.
- **Generate once**: `dg asset build`
- **Watch mode**: `dg asset watch`

For more details, see [ASSET_GENERATION_GUIDE.md](ASSET_GENERATION_GUIDE.md).

### 3️⃣ Run the App
```bash
# Development
flutter run

# Release Build
flutter build apk --release
```

## 📂 Project Structure
```text
lib/
├── main.dart          # Entry point
├── core/              # Shared utilities & configs
└── features/          # Feature-based organization
```

---
Generated by [DIG CLI](https://pub.dev/packages/dig_cli) 🚀
''';
    }
    await readmeFile.writeAsString(content);
  }

  Future<void> _mergePubspec(
      Directory projectDir, String templatePath, String slug) async {
    final targetPubspec = File(p.join(projectDir.path, 'pubspec.yaml'));
    final templatePubspec = File(p.join(templatePath, 'pubspec.yaml'));

    if (await targetPubspec.exists() && await templatePubspec.exists()) {
      String templateContent = await templatePubspec.readAsString();
      // Update name to match the new project slug
      templateContent =
          templateContent.replaceFirst(RegExp(r'name:\s+.*'), 'name: $slug');
      // Update description
      templateContent = templateContent.replaceFirst(
          RegExp(r'description:\s+.*'), 'description: Created using DIG CLI');

      // Write the template's pubspec (with updated name) to the target,
      // effectively "merging" by overwriting with our desired structure.
      // This ensures all assets, fonts, and dependencies are exactly as in template.
      await targetPubspec.writeAsString(templateContent);
    }
  }

  Future<void> _configureAndroidSigning(Directory projectDir) async {
    // Inject signing config into android/app/build.gradle
    final buildGradle =
        File(p.join(projectDir.path, 'android', 'app', 'build.gradle'));
    if (await buildGradle.exists()) {
      String content = await buildGradle.readAsString();

      // 1. Add keystore loading logic before android {} block
      const keystoreLoader = '''
def keystorePropertiesFile = rootProject.file("key.properties")
def keystoreProperties = new Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

''';
      if (!content.contains('def keystoreProperties')) {
        content = keystoreLoader + content;
      }

      // 2. Add signingConfigs inside android {}
      if (!content.contains('signingConfigs {')) {
        final signingConfig = '''
    signingConfigs {
        release {
            keyAlias = keystoreProperties['keyAlias']
            keyPassword = keystoreProperties['keyPassword']
            storeFile = keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword = keystoreProperties['storePassword']
        }
    }
''';
        // Insert at start of android { block
        content =
            content.replaceFirst('android {', 'android {\n$signingConfig');
      }

      // 3. Apply signingConfig to release buildType
      if (!content.contains('signingConfig signingConfigs.release')) {
        content = content.replaceFirst('buildTypes {\n        release {',
            'buildTypes {\n        release {\n            signingConfig signingConfigs.release');
      }

      await buildGradle.writeAsString(content);
    }
  }

  Future<void> _generateAndInjectSecureKey(Directory projectDir) async {
    final envFile = File(p.join(projectDir.path, '.env'));
    if (await envFile.exists()) {
      // Generate 32 bytes of secure random data
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      final secureKey = base64UrlEncode(values);

      String content = await envFile.readAsString();
      // Replace existing API key or append if missing
      if (content.contains('API_KEY=')) {
        content =
            content.replaceFirst(RegExp(r'API_KEY=.*'), 'API_KEY=$secureKey');
      } else {
        content += '\nAPI_KEY=$secureKey';
      }
      await envFile.writeAsString(content);
      kLog('🔐 Generated secure API_KEY in .env', type: LogType.info);
    }
  }

  Future<void> _cleanupDefaultFlutterAssets(Directory projectDir) async {
    final pathsToDelete = [
      // Android: Remove default resources (icons, styles) and sources (kotlin/java)
      // We want our template to be the source of truth, not a merge.
      'android/app/src/main/res',
      'android/app/src/main/kotlin',
      'android/app/src/main/java',
      // iOS: Remove default assets (AppIcon)
      'ios/Runner/Assets.xcassets',
    ];

    for (final path in pathsToDelete) {
      final dir = Directory(p.join(projectDir.path, path));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }
}
