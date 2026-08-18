import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'logger.dart';

/// Helper class to handle project rebranding (renaming app, bundle ID, updating imports).
class ProjectRebrander {
  final Directory projectDir;
  final String newSlug;
  final String newAppName;
  final String newBundleId;

  ProjectRebrander({
    required this.projectDir,
    required this.newSlug,
    required this.newAppName,
    required this.newBundleId,
  });

  Future<void> rebrand() async {
    // 1. Detect old slug from pubspec.yaml
    final oldSlug = await _detectOldSlug();

    // 2. Perform replacements
    await _updateDartImports(oldSlug);
    await _updateAllAppNames();
    await _updateAllBundleIds();
  }

  Future<String?> _detectOldSlug() async {
    final pubspec = File(p.join(projectDir.path, 'pubspec.yaml'));
    if (await pubspec.exists()) {
      final content = await pubspec.readAsString();
      final yaml = loadYaml(content);
      return yaml['name'] as String?;
    }
    return null;
  }

  Future<void> _updateDartImports(String? oldSlug) async {
    try {
      final absolutePath = p.absolute(projectDir.path);
      final dirsToProcess = [
        Directory(p.join(absolutePath, 'lib')),
        Directory(p.join(absolutePath, 'test')),
        Directory(p.join(absolutePath, 'android')),
        Directory(p.join(absolutePath, 'ios')),
        Directory(p.join(absolutePath, 'macos')),
        Directory(p.join(absolutePath, 'windows')),
        Directory(p.join(absolutePath, 'linux')),
        Directory(p.join(absolutePath, 'web')),
      ];

      for (final dir in dirsToProcess) {
        if (!await dir.exists()) continue;
        await _processDirectoryForImports(dir, oldSlug);
      }
      await _processDirectoryForImports(Directory(absolutePath), oldSlug,
          recursive: false);
    } catch (e) {
      kLog('Error in _updateDartImports: $e', type: LogType.error);
    }
  }

  Future<void> _processDirectoryForImports(Directory dir, String? oldSlug,
      {bool recursive = true}) async {
    try {
      final entities = dir.listSync(recursive: recursive);
      for (var entity in entities) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path);
        if (const {
          '.dart',
          '.yaml',
          '.gradle',
          '.kts',
          '.xml',
          '.plist',
          '.json',
          '.md',
          '.rc',
          '.cpp',
          '.cc',
          '.txt'
        }.contains(ext)) {
          try {
            String content = await entity.readAsString();
            bool changed = false;

            // Replace PROJECT_NAME placeholder
            if (content.contains('PROJECT_NAME')) {
              content = content.replaceAll('PROJECT_NAME', newSlug);
              changed = true;
            }

            // Replace hardcoded package imports
            if (oldSlug != null && content.contains('package:$oldSlug/')) {
              content =
                  content.replaceAll('package:$oldSlug/', 'package:$newSlug/');
              changed = true;
            }

            // Fallback for common template names if oldSlug detection was insufficient
            if (content.contains('package:structure/')) {
              content =
                  content.replaceAll('package:structure/', 'package:$newSlug/');
              changed = true;
            }

            if (changed) {
              await entity.writeAsString(content);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _updateAllAppNames() async {
    // Android Manifest
    final manifestFile = File(
        p.join(projectDir.path, 'android/app/src/main/AndroidManifest.xml'));
    if (await manifestFile.exists()) {
      String content = await manifestFile.readAsString();
      content = content.replaceFirst(
          RegExp(r'android:label="[^"]*"'), 'android:label="$newAppName"');
      await manifestFile.writeAsString(content);
    }

    // iOS Info.plist
    final infoPlist = File(p.join(projectDir.path, 'ios/Runner/Info.plist'));
    if (await infoPlist.exists()) {
      String content = await infoPlist.readAsString();
      content = content.replaceFirst(
        RegExp(r'<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>'),
        '<key>CFBundleDisplayName</key>\n\t<string>$newAppName</string>',
      );
      content = content.replaceFirst(
        RegExp(r'<key>CFBundleName</key>\s*<string>[^<]*</string>'),
        '<key>CFBundleName</key>\n\t<string>$newAppName</string>',
      );
      await infoPlist.writeAsString(content);
    }

    // macOS Info.plist & AppInfo.xcconfig
    final macPlist = File(p.join(projectDir.path, 'macos/Runner/Info.plist'));
    if (await macPlist.exists()) {
      String content = await macPlist.readAsString();
      content = content.replaceFirst(
        RegExp(r'<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>'),
        '<key>CFBundleDisplayName</key>\n\t<string>$newAppName</string>',
      );
      content = content.replaceFirst(
        RegExp(r'<key>CFBundleName</key>\s*<string>[^<]*</string>'),
        '<key>CFBundleName</key>\n\t<string>$newAppName</string>',
      );
      await macPlist.writeAsString(content);
    }
    final macConfig =
        File(p.join(projectDir.path, 'macos/Runner/Configs/AppInfo.xcconfig'));
    if (await macConfig.exists()) {
      String content = await macConfig.readAsString();
      content = content.replaceFirst(
          RegExp(r'PRODUCT_NAME = .*'), 'PRODUCT_NAME = $newAppName');
      await macConfig.writeAsString(content);
    }

    // Windows rc & cpp
    final winRc = File(p.join(projectDir.path, 'windows/runner/Runner.rc'));
    if (await winRc.exists()) {
      String content = await winRc.readAsString();
      content = content.replaceFirst(RegExp(r'VALUE "ProductName", "[^"]*"'),
          'VALUE "ProductName", "$newAppName"');
      await winRc.writeAsString(content);
    }
    final winCpp = File(p.join(projectDir.path, 'windows/runner/main.cpp'));
    if (await winCpp.exists()) {
      String content = await winCpp.readAsString();
      content = content.replaceFirst(RegExp(r'window.CreateAndShow\(L"[^"]*"'),
          'window.CreateAndShow(L"$newAppName"');
      await winCpp.writeAsString(content);
    }

    // Linux CMake
    final linCMake = File(p.join(projectDir.path, 'linux/CMakeLists.txt'));
    if (await linCMake.exists()) {
      String content = await linCMake.readAsString();
      content = content.replaceFirst(RegExp(r'set\(BINARY_NAME "[^"]*"\)'),
          'set(BINARY_NAME "$newAppName")');
      await linCMake.writeAsString(content);
    }

    // Web index.html & manifest.json
    final webHtml = File(p.join(projectDir.path, 'web/index.html'));
    if (await webHtml.exists()) {
      String content = await webHtml.readAsString();
      content = content.replaceFirst(
          RegExp(r'<title>[^<]*</title>'), '<title>$newAppName</title>');
      content = content.replaceFirst(
        RegExp(r'content="[^"]*"\s+name="apple-mobile-web-app-title"'),
        'content="$newAppName" name="apple-mobile-web-app-title"',
      );
      await webHtml.writeAsString(content);
    }
    final webManifest = File(p.join(projectDir.path, 'web/manifest.json'));
    if (await webManifest.exists()) {
      String content = await webManifest.readAsString();
      content = content.replaceFirst(
          RegExp(r'"name": "[^"]*"'), '"name": "$newAppName"');
      content = content.replaceFirst(
          RegExp(r'"short_name": "[^"]*"'), '"short_name": "$newAppName"');
      await webManifest.writeAsString(content);
    }

    // App Constants - Try to find standard appName definition
    final appConstantFile =
        File(p.join(projectDir.path, 'lib/app/constants/app_constant.dart'));
    if (await appConstantFile.exists()) {
      String content = await appConstantFile.readAsString();
      content = content.replaceFirst(
        RegExp(r"static const String appName = '[^']*'"),
        "static const String appName = '$newAppName'",
      );
      await appConstantFile.writeAsString(content);
    }
  }

  Future<void> _updateAllBundleIds() async {
    File? buildGradle;
    final gradleKts =
        File(p.join(projectDir.path, 'android/app/build.gradle.kts'));
    final gradle = File(p.join(projectDir.path, 'android/app/build.gradle'));

    if (await gradleKts.exists()) {
      buildGradle = gradleKts;
    } else if (await gradle.exists()) {
      buildGradle = gradle;
    }

    if (buildGradle != null) {
      String content = await buildGradle.readAsString();
      final appIdMatch =
          RegExp(r'applicationId\s*[=]?\s*"([^"]+)"').firstMatch(content);
      final oldId = appIdMatch?.group(1);

      content = content
          .replaceAllMapped(RegExp(r'applicationId\s*(=)?\s*"[^"]+"'), (match) {
        return match.group(1) != null
            ? 'applicationId = "$newBundleId"'
            : 'applicationId "$newBundleId"';
      });
      content = content.replaceAllMapped(RegExp(r'namespace\s*(=)?\s*"[^"]+"'),
          (match) {
        return match.group(1) != null
            ? 'namespace = "$newBundleId"'
            : 'namespace "$newBundleId"';
      });

      // Update package declaration in Manifest
      final manifestFile = File(
          p.join(projectDir.path, 'android/app/src/main/AndroidManifest.xml'));
      if (await manifestFile.exists()) {
        String mContent = await manifestFile.readAsString();
        mContent = mContent.replaceAll(
            RegExp(r'package="[^"]*"'), 'package="$newBundleId"');
        await manifestFile.writeAsString(mContent);
      }

      await buildGradle.writeAsString(content);

      if (oldId != null && oldId != newBundleId) {
        // Global search and replace of the old bundle ID in all code files
        // (to catch things like firebase_options.dart, constants, etc.)
        await _globalReplaceBundleId(oldId, newBundleId);
        await _restructureAndroidDirs(oldId, newBundleId);
      }
    }

    // iOS and macOS Project
    final iosProj =
        File(p.join(projectDir.path, 'ios/Runner.xcodeproj/project.pbxproj'));
    if (await iosProj.exists()) {
      String content = await iosProj.readAsString();
      content = content.replaceAll(
          RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;'),
          'PRODUCT_BUNDLE_IDENTIFIER = $newBundleId;');
      await iosProj.writeAsString(content);
    }
    final macProj =
        File(p.join(projectDir.path, 'macos/Runner.xcodeproj/project.pbxproj'));
    if (await macProj.exists()) {
      String content = await macProj.readAsString();
      content = content.replaceAll(
          RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;'),
          'PRODUCT_BUNDLE_IDENTIFIER = $newBundleId;');
      await macProj.writeAsString(content);
    }

    // iOS Info.plist Identifier (if hardcoded)
    final iosPlist = File(p.join(projectDir.path, 'ios/Runner/Info.plist'));
    if (await iosPlist.exists()) {
      String content = await iosPlist.readAsString();
      if (!content.contains(r'$(PRODUCT_BUNDLE_IDENTIFIER)')) {
        content = content.replaceFirst(
          RegExp(r'<key>CFBundleIdentifier</key>\s*<string>[^<]+</string>'),
          '<key>CFBundleIdentifier</key>\n\t<string>$newBundleId</string>',
        );
      }
      await iosPlist.writeAsString(content);
    }
  }

  Future<void> _globalReplaceBundleId(String oldId, String newId) async {
    try {
      final absolutePath = p.absolute(projectDir.path);
      final dirsToProcess = [
        Directory(p.join(absolutePath, 'lib')),
        Directory(p.join(absolutePath, 'android')),
        Directory(p.join(absolutePath, 'ios')),
        Directory(p.join(absolutePath, 'macos')),
        Directory(p.join(absolutePath, 'web')),
      ];

      for (final dir in dirsToProcess) {
        if (!await dir.exists()) continue;
        final entities = dir.listSync(recursive: true);
        for (var entity in entities) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path);
          if (const {
            '.dart',
            '.xml',
            '.plist',
            '.json',
            '.gradle',
            '.kts',
            '.html'
          }.contains(ext)) {
            try {
              String content = await entity.readAsString();
              if (content.contains(oldId)) {
                content = content.replaceAll(oldId, newId);
                await entity.writeAsString(content);
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _restructureAndroidDirs(String oldId, String newId) async {
    final oldPath = oldId.replaceAll('.', '/');
    final newPath = newId.replaceAll('.', '/');
    final appSrc = p.join(projectDir.path, 'android/app/src');

    for (var type in ['main', 'debug', 'profile']) {
      for (var lang in ['kotlin', 'java']) {
        final sourceDir = Directory(p.join(appSrc, type, lang, oldPath));
        if (await sourceDir.exists()) {
          final targetPath = p.join(appSrc, type, lang, newPath);
          await Directory(targetPath).create(recursive: true);

          await for (var entity in sourceDir.list()) {
            final base = p.basename(entity.path);
            await entity.rename(p.join(targetPath, base));
          }

          // Cleanup empty parent directories
          var current = sourceDir;
          while (current.path != p.join(appSrc, type, lang) &&
              (await current.list().isEmpty)) {
            final parent = current.parent;
            await current.delete();
            current = parent;
          }
        }
      }
    }

    // Update package declarations
    final newPathSegment = newId.replaceAll('.', '/');
    for (var type in ['main', 'debug', 'profile']) {
      for (var lang in ['kotlin', 'java']) {
        final sourceDir = Directory(p.join(appSrc, type, lang, newPathSegment));
        if (await sourceDir.exists()) {
          await for (var entity in sourceDir.list(recursive: true)) {
            if (entity is File &&
                (entity.path.endsWith('.kt') ||
                    entity.path.endsWith('.java'))) {
              String content = await entity.readAsString();
              content = content.replaceFirst(
                RegExp(r'^package\s+[\w\.]+', multiLine: true),
                'package $newId',
              );
              await entity.writeAsString(content);
            }
          }
        }
      }
    }
  }
}
