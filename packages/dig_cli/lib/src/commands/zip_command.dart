import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';

/// Rules describing which files/directories to exclude from a ZIP archive,
/// derived from a project's `.gitignore`.
class IgnoreRules {
  /// Creates ignore rules from explicit sets of directory names, file names,
  /// and file extensions.
  IgnoreRules(this.exactDirs, this.exactFiles, this.extensions);

  /// Directory names to ignore.
  final Set<String> exactDirs;

  /// File names to ignore.
  final Set<String> exactFiles;

  /// File extensions to ignore (including the leading dot).
  final Set<String> extensions;

  /// Parses the project's `.gitignore` (if present) into [IgnoreRules].
  static IgnoreRules fromGitignore() {
    final file = File('.gitignore');
    if (!file.existsSync()) {
      kLog(
        '⚠️ .gitignore not found. ZIP may include unnecessary files.',
        type: LogType.warning,
      );
      return IgnoreRules({}, {}, {});
    }

    final List<String> lines = file.readAsLinesSync();
    final exactDirs = <String>{};
    final exactFiles = <String>{};
    final extensions = <String>{};

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
        continue;
      }

      if (line.startsWith('*.')) {
        extensions.add(line.substring(1));
      } else if (line.endsWith('/')) {
        exactDirs.add(line.substring(0, line.length - 1));
      } else {
        exactFiles.add(line);
      }
    }
    return IgnoreRules(exactDirs, exactFiles, extensions);
  }

  /// Returns true if [relativePath]/[entity] matches one of these ignore rules.
  bool shouldIgnore(String relativePath, FileSystemEntity entity) {
    final List<String> parts = relativePath.split(p.separator);
    final String entityName = p.basename(relativePath);

    // Ignore hidden files/dirs by default
    if (parts.any((part) => part.startsWith('.'))) {
      return true;
    }

    // Check exact dirs
    if (parts.any((part) => exactDirs.contains(part))) {
      return true;
    }

    // Check exact files
    if (exactFiles.contains(entityName)) {
      return true;
    }

    // Check extensions
    if (extensions.any((ext) => entityName.endsWith(ext))) {
      return true;
    }

    return false;
  }
}

/// Command that packages the current Flutter project into a clean ZIP
/// archive, excluding files matched by `.gitignore`.
class ZipCommand extends Command<void> {
  /// Registers the `--output` option.
  ZipCommand() {
    argParser.addOption('output', abbr: 'o', help: 'Specify output directory');
  }
  @override
  final name = 'zip';
  @override
  final description = 'Creates a clean ZIP archive of the project.';

  @override
  Future<void> run() async {
    final Directory? root = findProjectRoot();

    if (root == null) {
      kLog(
        '❗ This command must be run inside a Flutter project.',
        type: LogType.error,
      );
      exit(1);
    }
    Directory.current = root;

    try {
      // Run 'flutter clean' before starting zip
      await runWithSpinner(
        '🧹 Running flutter clean before zipping...',
        () async {
          final ProcessResult cleanResult =
              await Process.run('flutter', ['clean']);
          if (cleanResult.exitCode != 0) {
            throw Exception('flutter clean failed: ${cleanResult.stderr}');
          }
        },
      );

      final String projectName = await getProjectName() ?? 'project';

      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final String hour = now.hour.toString().padLeft(2, '0');
      final String minute = now.minute.toString().padLeft(2, '0');
      final zipFileName = '$projectName-$date-$hour-$minute.zip';

      final String defaultPath = await getDesktopPath();

      var location = argResults?['output'] as String?;
      if (location == null || location.isEmpty) {
        stdout.write('Enter save location (default: Desktop): ');
        location = stdin.readLineSync()?.trim();
        if (location == null || location.isEmpty) {
          location = defaultPath;
        }
      }

      final String outputPath = p.join(location, zipFileName);

      await runWithSpinner('📦 Creating clean ZIP archive...', () async {
        final encoder = ZipFileEncoder();
        encoder.create(outputPath);
        final IgnoreRules rules = IgnoreRules.fromGitignore();
        final Directory projectDir = Directory.current;
        final List<FileSystemEntity> entities = projectDir.listSync(
          recursive: true,
          followLinks: false,
        );

        for (final entity in entities) {
          final String relativePath =
              p.relative(entity.path, from: projectDir.path);

          if (!rules.shouldIgnore(relativePath, entity) && entity is File) {
            encoder.addFileSync(entity, p.join(projectName, relativePath));
          }
        }
        await encoder.close();
      });

      kLog('✅ ZIP file created successfully!', type: LogType.success);
      kLog('📁 Location: $outputPath');
    } catch (e) {
      kLog('❌ An error occurred while creating ZIP: $e', type: LogType.error);
      exit(1);
    }
  }
}

/// For backward compatibility while refactoring others.
Future<void> handleZipCommand() async {
  await ZipCommand().run();
}
