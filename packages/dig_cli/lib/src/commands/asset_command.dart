import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';
import 'package:yaml/yaml.dart';

import '../utils/logger.dart';

/// Command to generate asset constants from dig.yaml
class AssetCommand extends Command<void> {
  /// Registers the `build` and `watch` subcommands.
  AssetCommand() {
    addSubcommand(_AssetBuildCommand());
    addSubcommand(_AssetWatchCommand());
  }
  @override
  final name = 'asset';

  @override
  final description = 'Generate asset constants from dig.yaml configuration';
}

class _AssetBuildCommand extends Command<void> {
  @override
  final name = 'build';

  @override
  final description = 'Generate asset constants once';

  @override
  Future<void> run() async {
    await buildAssets();
  }
}

class _AssetWatchCommand extends Command<void> {
  @override
  final name = 'watch';

  @override
  final description = 'Watch and auto-generate asset constants on changes';

  @override
  Future<void> run() async {
    await _watchAssets();
  }
}

/// Scans the configured assets directory and generates asset constant files.
Future<void> buildAssets() async {
  kLog('🎨 Generating asset constants...\n');

  // Read configuration from dig.yaml
  final configFile = File('dig.yaml');
  if (!configFile.existsSync()) {
    kLog('❌ dig.yaml not found!', type: LogType.error);
    kLog('💡 Create dig.yaml file with configuration:');
    kLog('''
assets-dir: assets/
output-dir: lib/gen
''');
    return;
  }

  final String configContent = configFile.readAsStringSync();
  final Map<dynamic, dynamic> config = loadYaml(configContent) as YamlMap;

  final assetsDir = Directory(config['assets-dir'] as String? ?? 'assets/');
  if (!assetsDir.existsSync()) {
    kLog('❌ Assets directory not found: ${assetsDir.path}', type: LogType.error);
    return;
  }

  final String outputDir = config['output-dir'] as String? ?? 'lib/generated';

  // Clean only the assets subfolder inside the output directory.
  // This preserves other generated files (e.g., localization files).
  final assetsOutputDir = Directory('$outputDir/assets');
  if (assetsOutputDir.existsSync()) {
    assetsOutputDir.deleteSync(recursive: true);
  }

  // Also remove the main assets.dart export file so it gets regenerated
  final mainExportFile = File('$outputDir/assets.dart');
  if (mainExportFile.existsSync()) {
    mainExportFile.deleteSync();
  }

  // Get skip/exclude patterns from config
  final skipPatterns = <String>[];
  if (config['skip'] != null) {
    final dynamic skipConfig = config['skip'];
    if (skipConfig is List) {
      skipPatterns.addAll(skipConfig.map((e) => e.toString()));
    } else if (skipConfig is String) {
      skipPatterns.add(skipConfig);
    }
  }

  // Scan assets and organize by category and type
  final Map<String, Map<String, List<_AssetInfo>>> assets = _scanAssets(assetsDir, skipPatterns);

  // Generate all files
  final List<String> generatedFiles = _generateMultipleFiles(assets, outputDir);

  // Auto-update pubspec.yaml with asset folders
  await _updatePubspec(assetsDir);

  // Print summary
  kLog('✅ Generated ${_countTotalAssets(assets)} asset constants\n', type: LogType.success);
  kLog('📁 Generated Files:');
  for (final file in generatedFiles) {
    kLog('  $file');
  }
  kLog('');
}

Future<void> _watchAssets() async {
  // Read configuration from dig.yaml
  final configFile = File('dig.yaml');
  var assetsPath = 'assets';

  if (configFile.existsSync()) {
    try {
      final String configContent = configFile.readAsStringSync();
      final Map<dynamic, dynamic> config = loadYaml(configContent) as YamlMap;
      assetsPath = config['assets-dir'] as String? ?? 'assets';
    } catch (_) {
      // Use default if yaml is invalid
    }
  }

  final assetsDir = Directory(assetsPath);
  if (!assetsDir.existsSync()) {
    kLog('❌ Assets directory not found: ${assetsDir.path}', type: LogType.error);
    exit(1);
  }

  kLog('👀 Watching ${assetsDir.path} directory for changes...\n');

  // Generate once on start
  await buildAssets();

  // Watch for changes using watcher package for robust cross-platform support
  final watcher = DirectoryWatcher(assetsDir.path);
  final StreamSubscription<WatchEvent> subscription = watcher.events.listen((event) {
    final String path = event.path;
    final String extension = path.split('.').last.toLowerCase();

    const allowedExtensions = {
      'svg',
      'png',
      'jpg',
      'jpeg',
      'ttf',
      'otf',
      'webp',
      'gif',
    };

    if (allowedExtensions.contains(extension)) {
      final String fileName = path.split(Platform.pathSeparator).last;
      kLog('\n📁 Detected change (${event.type}): $fileName');
      buildAssets();
    }
  });

  kLog('\n🔄 Watching for changes... (Press Ctrl+C to stop)');

  // Keep the process running
  try {
    await ProcessSignal.sigint.watch().first;
  } catch (_) {
    // Fallback if SIGINT watch is not supported
    await Future<void>.delayed(const Duration(days: 365));
  } finally {
    await subscription.cancel();
    kLog('\n👋 Stopped watching');
    exit(0);
  }
}

/// Scan assets and organize by subfolder and file type
/// Returns: {
///   'bottom_bar': {
///     'png': [AssetInfo...],
///     'svg': [AssetInfo...],
///   },
///   'top_bar': {
///     'svg': [AssetInfo...],
///   },
///   'fonts': {
///     'ttf': [AssetInfo...],
///   }
/// }
Map<String, Map<String, List<_AssetInfo>>> _scanAssets(
  Directory dir,
  List<String> skipPatterns,
) {
  final assets = <String, Map<String, List<_AssetInfo>>>{};

  final List<FileSystemEntity> allFiles = dir.listSync(recursive: true);

  for (final entity in allFiles) {
    if (entity is File) {
      // Get relative path from assets directory using path package
      final String relativePath = p.relative(entity.path, from: dir.path);

      // Normalize to forward slashes for internal logic and constants
      final String normalizedPath = relativePath.replaceAll(r'\', '/');
      final List<String> pathParts = normalizedPath.split('/');

      final String extension = p.extension(entity.path).toLowerCase().replaceAll('.', '');

      // Check if this path should be skipped
      // The relative path for skipping should include the base folder if it matches existing logic
      // But _shouldSkip expects 'assets/...' or '/pattern/'.
      // This is still a bit brittle, but I'll improve _shouldSkip too.
      final String fullRelativePath =
          p.join(p.basename(dir.path), normalizedPath).replaceAll(r'\', '/');

      if (_shouldSkip(fullRelativePath, skipPatterns)) {
        continue;
      }

      // Extract category from subfolders
      // Example: data/icons/home/svg/icon.svg (where dir is data/)
      // normalizedPath: icons/home/svg/icon.svg
      // pathParts: [icons, home, svg, icon.svg]

      if (pathParts.length < 2) {
        continue; // Need at least folder/file
      }

      List<String> subfolders = pathParts.sublist(0, pathParts.length - 1);

      // If the last subfolder matches the file extension, remove it
      if (subfolders.isNotEmpty && subfolders.last == extension) {
        subfolders = subfolders.sublist(0, subfolders.length - 1);
      }

      if (subfolders.isEmpty) {
        continue;
      }

      final String category = subfolders.join('_');

      // Determine file type
      String? fileType;
      if (extension == 'png' ||
          extension == 'jpg' ||
          extension == 'jpeg' ||
          extension == 'svg' ||
          extension == 'webp' ||
          extension == 'gif') {
        fileType = extension == 'jpeg' ? 'jpg' : extension;
      } else if (extension == 'ttf' || extension == 'otf') {
        fileType = extension;
      }

      if (fileType != null) {
        assets.putIfAbsent(category, () => {});
        assets[category]!.putIfAbsent(fileType, () => []);

        final String fileName = p.basenameWithoutExtension(entity.path);
        final String constantName = _toConstantName(fileName);

        // The path in the constant should be the full path relative to the project root
        // which is basically p.join(dir.path, relativePath)
        final String projectRelativePath = p.join(dir.path, relativePath).replaceAll(r'\', '/');

        assets[category]![fileType]!.add(
          _AssetInfo(constantName, projectRelativePath),
        );
      }
    }
  }

  return assets;
}

String _toConstantName(String fileName) {
  // Convert any file name format to proper camelCase
  // Examples:
  // - ic_back.svg -> icBack
  // - my_icon.svg -> myIcon
  // - some-icon.svg -> someIcon
  // - SOmeIcon.svg -> someIcon
  // - MyIcon.svg -> myIcon
  // - 4.png -> a4

  // 1. Remove special chars (parens, brackets, etc.)
  // 2. Convert spaces to underscores
  // 3. Convert hyphens to underscores
  // 4. Merge multiple underscores
  final String normalized = fileName
      .replaceAll(RegExp(r'[^a-zA-Z0-9\-_ ]'), '')
      .replaceAll(' ', '_')
      .replaceAll('-', '_')
      .replaceAll(RegExp(r'_+'), '_');

  if (normalized.isEmpty) {
    return 'unknownAsset';
  }

  // Split by underscore
  final List<String> parts = normalized.split('_').where((p) => p.isNotEmpty).toList();

  if (parts.isEmpty) {
    return 'unknownAsset';
  }

  String result;

  if (parts.length == 1) {
    final String part = parts.first;
    result = part[0].toLowerCase() + part.substring(1);
  } else {
    final String first = parts.first.toLowerCase();
    final Iterable<String> rest =
        parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase());
    result = first + rest.join();
  }

  // Dart variables cannot start with a number.
  if (result.isNotEmpty && RegExp(r'^[0-9]').hasMatch(result)) {
    result = 'ic$result';
  }

  return result;
}

/// Generate multiple files organized by category and type
/// Returns list of generated file paths
List<String> _generateMultipleFiles(
  Map<String, Map<String, List<_AssetInfo>>> assets,
  String outputDir,
) {
  final generatedFiles = <String>[];

  // Create output directory
  final baseDir = Directory(outputDir);
  if (!baseDir.existsSync()) {
    baseDir.createSync(recursive: true);
  }

  final categoryExports = <String>[];

  // Generate files for each category
  for (final MapEntry<String, Map<String, List<_AssetInfo>>> categoryEntry in assets.entries) {
    final String category = categoryEntry.key;
    final Map<String, List<_AssetInfo>> typeMap = categoryEntry.value;

    if (typeMap.isEmpty) {
      continue;
    }

    final typeExports = <String>[];

    // Generate type-specific files (e.g., icons_png.dart, icons_svg.dart)
    for (final MapEntry<String, List<_AssetInfo>> typeEntry in typeMap.entries) {
      final String fileType = typeEntry.key;
      final List<_AssetInfo> assetList = typeEntry.value;

      if (assetList.isEmpty) {
        continue;
      }

      final String className = _toCategoryClassName(category, fileType);
      final fileName = '${category}_$fileType.dart';
      final filePath = '$outputDir/assets/$category/$fileName';

      final String typeFileContent = _generateTypeFile(
        className,
        assetList,
        category,
        fileType,
      );

      final typeFile = File(filePath);
      typeFile.createSync(recursive: true);
      typeFile.writeAsStringSync(typeFileContent);

      generatedFiles.add(filePath);
      typeExports.add("export '$category/$fileName';");
    }

    // Generate category export file (e.g., icons.dart)
    if (typeExports.isNotEmpty) {
      final categoryFilePath = '$outputDir/assets/$category.dart';
      final String categoryFileContent = _generateCategoryFile(typeExports);

      final categoryFile = File(categoryFilePath);
      categoryFile.createSync(recursive: true);
      categoryFile.writeAsStringSync(categoryFileContent);

      generatedFiles.add(categoryFilePath);
      categoryExports.add("export 'assets/$category.dart';");
    }
  }

  // Generate main export file (assets.dart)
  if (categoryExports.isNotEmpty) {
    final mainFilePath = '$outputDir/assets.dart';
    final String mainFileContent = _generateMainFile(categoryExports);

    final mainFile = File(mainFilePath);
    mainFile.writeAsStringSync(mainFileContent);

    generatedFiles.insert(0, mainFilePath);
  }

  return generatedFiles;
}

String _toCategoryClassName(String category, String fileType) {
  // bottom_bar + svg → BottomBarSvg
  // top_bar + png → TopBarPng
  // icons_home + svg → IconsHomeSvg

  // Split category by underscore and capitalize each part
  final List<String> categoryParts = category.split('_');
  final String categoryCapitalized =
      categoryParts.map((part) => part[0].toUpperCase() + part.substring(1)).join();

  final String typeCapitalized = fileType[0].toUpperCase() + fileType.substring(1);
  return '$categoryCapitalized$typeCapitalized';
}

String _generateTypeFile(
  String className,
  List<_AssetInfo> assets,
  String category,
  String fileType,
) {
  final buffer = StringBuffer();

  buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  buffer.writeln('// Generated by: dg asset build');
  buffer.writeln();
  buffer.writeln('// ignore_for_file: type=lint');
  buffer.writeln();
  buffer.writeln('/// ${fileType.toUpperCase()} $category assets');
  buffer.writeln('class $className {');
  buffer.writeln('  const $className._();');
  buffer.writeln();

  assets.sort((a, b) => a.name.compareTo(b.name));

  for (final asset in assets) {
    // Ensure constant name is a valid Dart identifier
    final String safeName = RegExp(r'^[0-9]').hasMatch(asset.name) ? 'ic${asset.name}' : asset.name;
    buffer.writeln('  /// ${asset.path}');
    buffer.writeln("  static const String $safeName = '${asset.path}';");
    if (asset != assets.last) {
      buffer.writeln();
    }
  }

  buffer.writeln('}');
  buffer.writeln();

  return buffer.toString();
}

String _generateCategoryFile(List<String> exports) {
  final buffer = StringBuffer();

  buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  buffer.writeln('// Generated by: dg asset build');
  buffer.writeln();
  buffer.writeln('// ignore_for_file: type=lint');
  buffer.writeln();

  exports.forEach(buffer.writeln);

  return buffer.toString();
}

String _generateMainFile(List<String> categoryExports) {
  final buffer = StringBuffer();

  buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  buffer.writeln('// Generated by: dg asset build');
  buffer.writeln('// Configuration: dig.yaml');
  buffer.writeln();
  buffer.writeln('// ignore_for_file: type=lint');
  buffer.writeln();
  buffer.writeln('/// Asset constants generated from your assets directory.');
  buffer.writeln('///');
  buffer.writeln('/// To use these assets in your application:');
  buffer.writeln('///');
  buffer.writeln('/// ```dart');
  buffer.writeln("/// import 'package:flutter_svg/flutter_svg.dart';");
  buffer.writeln("/// import 'package:your_app/gen/assets.dart';");
  buffer.writeln('///');
  buffer.writeln('/// // For SVG icons');
  buffer.writeln('/// SvgPicture.asset(IconsSvg.icBack);');
  buffer.writeln('///');
  buffer.writeln('/// // For PNG images');
  buffer.writeln('/// Image.asset(ImagesPng.logo);');
  buffer.writeln('///');
  buffer.writeln('/// // For fonts');
  buffer.writeln('/// TextStyle(fontFamily: FontsTtf.regular);');
  buffer.writeln('/// ```');
  buffer.writeln('///');
  buffer.writeln('/// ## Regenerating Assets');
  buffer.writeln('///');
  buffer.writeln('/// To regenerate this file after adding/removing assets:');
  buffer.writeln('///');
  buffer.writeln('/// ```bash');
  buffer.writeln('/// dg asset build');
  buffer.writeln('/// ```');
  buffer.writeln('///');
  buffer.writeln('/// Or use watch mode for automatic regeneration:');
  buffer.writeln('///');
  buffer.writeln('/// ```bash');
  buffer.writeln('/// dg asset watch');
  buffer.writeln('/// ```');
  buffer.writeln('///');
  buffer.writeln('/// ⚠️ **WARNING**: Do not modify this file manually.');
  buffer.writeln('/// All changes will be overwritten on next generation.');
  buffer.writeln();

  categoryExports.forEach(buffer.writeln);

  return buffer.toString();
}

int _countTotalAssets(Map<String, Map<String, List<_AssetInfo>>> assets) {
  var count = 0;
  for (final Map<String, List<_AssetInfo>> typeMap in assets.values) {
    for (final List<_AssetInfo> assetList in typeMap.values) {
      count += assetList.length;
    }
  }
  return count;
}

/// Automatically update pubspec.yaml with asset folders and .env.
///
/// Only manages entries that belong to the configured [assetsDir].
/// Localization files, `.env`, and other manually-added paths are
/// preserved and never removed.
Future<void> _updatePubspec(Directory assetsDir) async {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    return;
  }

  final String content = await pubspecFile.readAsString();
  final List<String> lines = content.split('\n');

  // 1. Identify folders containing image/font assets
  final requiredAssets = <String>{};

  // Normalize assetsDir path relative to project root
  final String baseAssetsPath =
      p.relative(assetsDir.path, from: Directory.current.path).replaceAll(r'\', '/');
  final normalizedBase = baseAssetsPath.endsWith('/') ? baseAssetsPath : '$baseAssetsPath/';

  requiredAssets.add(normalizedBase);

  final List<FileSystemEntity> allEntities = assetsDir.listSync(recursive: true);
  for (final entity in allEntities) {
    if (entity is File) {
      final String folderPath =
          p.dirname(p.relative(entity.path, from: Directory.current.path)).replaceAll(r'\', '/');

      requiredAssets.add('$folderPath/');
    }
  }

  if (File('.env').existsSync()) {
    requiredAssets.add('.env');
  }

  // 2. Find top-level flutter: section
  var flutterIndex = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('flutter:')) {
      flutterIndex = i;
      break;
    }
  }

  // 3. Find assets: section under flutter:
  var assetsIndex = -1;
  if (flutterIndex != -1) {
    for (int i = flutterIndex + 1; i < lines.length; i++) {
      final String line = lines[i];
      if (line.startsWith('  assets:')) {
        assetsIndex = i;
        break;
      }
      // If we hit another top-level key (no leading spaces)
      if (line.isNotEmpty && !line.startsWith(' ')) {
        break;
      }
    }
  }

  // 4. Update or Create sections
  final newLines = List<String>.from(lines);

  if (flutterIndex == -1) {
    // Add flutter section at the end if it doesn't exist
    newLines.add('');
    newLines.add('flutter:');
    newLines.add('  assets:');
    final List<String> sorted = requiredAssets.toList()..sort();
    for (final asset in sorted) {
      newLines.add('    - $asset');
    }
  } else if (assetsIndex == -1) {
    // Add assets section under flutter
    newLines.insert(flutterIndex + 1, '  assets:');
    int insertPos = flutterIndex + 2;
    final List<String> sorted = requiredAssets.toList()..sort();
    for (final asset in sorted) {
      newLines.insert(insertPos++, '    - $asset');
    }
  } else {
    // Update existing assets section: add new + remove stale
    final existingAssetLines = <int, String>{};
    var lastAssetIndex = assetsIndex;

    for (int i = assetsIndex + 1; i < newLines.length; i++) {
      final String line = newLines[i];
      final String trimmed = line.trim();

      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      if (line.startsWith('    -')) {
        final String assetPath =
            trimmed.substring(1).trim().replaceAll("'", '').replaceAll('"', '');
        existingAssetLines[i] = assetPath;
        lastAssetIndex = i;
      } else if (!line.startsWith('   ')) {
        break;
      } else {
        lastAssetIndex = i;
      }
    }

    final Set<String> existingAssets = existingAssetLines.values.toSet();

    // Determine which existing entries to remove:
    // Only remove entries that are within the configured assets directory
    // but no longer exist on disk. Do NOT touch .env, localization paths,
    // or anything outside the assets directory.
    final staleEntries = <String>{};
    for (final entry in existingAssets) {
      final bool isWithinAssetsDir = entry.startsWith(normalizedBase);
      if (!isWithinAssetsDir) {
        continue;
      }

      if (!requiredAssets.contains(entry)) {
        staleEntries.add(entry);
      }
    }

    final Set<String> assetsToAdd = requiredAssets.difference(existingAssets);

    if (assetsToAdd.isEmpty && staleEntries.isEmpty) {
      return;
    }

    // Remove stale entries (iterate in reverse to keep indices stable)
    if (staleEntries.isNotEmpty) {
      final List<int> linesToRemove = existingAssetLines.entries
          .where((e) => staleEntries.contains(e.value))
          .map((e) => e.key)
          .toList()
        ..sort((a, b) => b.compareTo(a));

      linesToRemove.forEach(newLines.removeAt);

      if (staleEntries.isNotEmpty) {
        kLog(
          '🗑️  Removed ${staleEntries.length} stale '
          'asset entries from pubspec.yaml',
        );
        for (final entry in staleEntries) {
          kLog('    - $entry');
        }
      }

      // Recalculate lastAssetIndex after removing lines
      lastAssetIndex = assetsIndex;
      for (int i = assetsIndex + 1; i < newLines.length; i++) {
        final String line = newLines[i];
        final String trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) {
          continue;
        }
        if (line.startsWith('    -')) {
          lastAssetIndex = i;
        } else if (!line.startsWith('   ')) {
          break;
        } else {
          lastAssetIndex = i;
        }
      }
    }

    // Add new entries
    if (assetsToAdd.isNotEmpty) {
      int insertPos = lastAssetIndex + 1;
      final List<String> sortedAssets = assetsToAdd.toList()..sort();
      for (final asset in sortedAssets) {
        newLines.insert(insertPos++, '    - $asset');
      }
    }
  }

  await pubspecFile.writeAsString(newLines.join('\n'));
}

/// Helper function for interactive menu to setup assets automatically
Future<void> handleAssetSetup() async {
  final configFile = File('dig.yaml');
  final assetsDir = Directory('assets');

  if (configFile.existsSync() && assetsDir.existsSync()) {
    kLog(
      '✅ Assets already configured! (dig.yaml & assets/ folder present)',
      type: LogType.success,
    );
  } else {
    if (!configFile.existsSync()) {
      kLog('📝 Creating default dig.yaml...');
      await configFile.writeAsString('''
assets-dir: assets/
output-dir: lib/generated
''');
    }

    if (!assetsDir.existsSync()) {
      kLog('📁 Creating assets/ directory...');
      await assetsDir.create(recursive: true);
    }
  }

  await buildAssets();
}

/// Check if a path should be skipped based on skip patterns
bool _shouldSkip(String path, List<String> skipPatterns) {
  for (final pattern in skipPatterns) {
    // Normalize pattern
    final String normalizedPattern = pattern.replaceAll(r'\', '/');

    // Check if path matches the pattern
    // Examples:
    // - 'icons' matches 'assets/icons/...'
    // - 'icons/svg' matches 'assets/icons/svg/...'
    // - 'fonts' matches 'assets/fonts/...'
    if (path.contains('/$normalizedPattern/') || path.startsWith('assets/$normalizedPattern/')) {
      return true;
    }
  }
  return false;
}

class _AssetInfo {
  _AssetInfo(this.name, this.path);
  final String name;
  final String path;
}
