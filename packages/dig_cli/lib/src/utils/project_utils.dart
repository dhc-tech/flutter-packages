import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Directory? _cachedProjectRoot;

/// Finds the project root by searching upwards for a pubspec.yaml file.
Directory? findProjectRoot() {
  if (_cachedProjectRoot != null) {
    return _cachedProjectRoot;
  }

  Directory dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      _cachedProjectRoot = dir;
      return dir;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      // Reached filesystem root and found nothing
      return null;
    }
    dir = parent;
  }
}

/// Resets the cached project root, forcing the next lookup to re-search.
void resetProjectRootCache() {
  _cachedProjectRoot = null;
}

/// Checks if the current directory or its root is a Flutter project.
Future<bool> isFlutterProject() async {
  final Directory? root = findProjectRoot();
  if (root == null) {
    return false;
  }
  return File(p.join(root.path, 'pubspec.yaml')).existsSync();
}

/// Gets the project name from pubspec.yaml.
Future<String?> getProjectName() async {
  final Directory? root = findProjectRoot();
  if (root == null) {
    return null;
  }
  final pubspecFile = File(p.join(root.path, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    return null;
  }

  final String content = await pubspecFile.readAsString();
  final dynamic yaml = loadYaml(content);
  return (yaml as Map)['name'] as String?;
}

/// Gets the user's desktop path.
Future<String> getDesktopPath() async {
  final String? home = Platform.isWindows
      ? Platform.environment['USERPROFILE']
      : Platform.environment['HOME'];
  if (home == null) {
    throw Exception('Could not find home directory.');
  }
  return p.join(home, 'Desktop');
}

/// Gets the current Android bundle ID (applicationId) from build.gradle
Future<String?> getBundleId() async {
  final Directory? root = findProjectRoot();
  if (root == null) {
    return null;
  }

  File? gradleFile;
  final groovy = File(p.join(root.path, 'android/app/build.gradle'));
  final kotlin = File(p.join(root.path, 'android/app/build.gradle.kts'));

  if (kotlin.existsSync()) {
    gradleFile = kotlin;
  } else if (groovy.existsSync()) {
    gradleFile = groovy;
  }
  if (gradleFile == null) {
    return null;
  }

  final String content = await gradleFile.readAsString();
  final RegExpMatch? match =
      RegExp(r'applicationId\s*[=]?\s*"([^"]+)"').firstMatch(content);
  return match?.group(1);
}

/// Gets the current App Label from AndroidManifest
Future<String?> getAppLabel() async {
  final Directory? root = findProjectRoot();
  if (root == null) {
    return null;
  }

  final manifest = File(
    p.join(root.path, 'android/app/src/main/AndroidManifest.xml'),
  );
  if (!manifest.existsSync()) {
    return null;
  }

  final String content = await manifest.readAsString();
  final RegExpMatch? match =
      RegExp(r'android:label="([^"]*)"').firstMatch(content);
  return match?.group(1);
}
