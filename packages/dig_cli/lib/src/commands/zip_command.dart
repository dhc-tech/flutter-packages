import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';

class IgnoreRules {
  final Set<String> exactDirs;
  final Set<String> exactFiles;
  final Set<String> extensions;

  IgnoreRules(this.exactDirs, this.exactFiles, this.extensions);

  static IgnoreRules fromGitignore() {
    final file = File('.gitignore');
    if (!file.existsSync()) {
      kLog('⚠️ .gitignore not found. ZIP may include unnecessary files.',
          type: LogType.warning);
      return IgnoreRules({}, {}, {});
    }

    final lines = file.readAsLinesSync();
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

  bool shouldIgnore(String relativePath, FileSystemEntity entity) {
    final parts = relativePath.split(p.separator);
    final entityName = p.basename(relativePath);

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

class ZipCommand extends Command {
  @override
  final name = 'zip';
  @override
  final description = 'Creates a clean ZIP archive of the project.';

  ZipCommand() {
    argParser.addOption('output', abbr: 'o', help: 'Specify output directory');
  }

  @override
  Future<void> run() async {
    final root = findProjectRoot();

    if (root == null) {
      kLog('❗ This command must be run inside a Flutter project.',
          type: LogType.error);
      exit(1);
    }
    Directory.current = root;

    try {
      // Run 'flutter clean' before starting zip
      await runWithSpinner('🧹 Running flutter clean before zipping...',
          () async {
        final cleanResult = await Process.run('flutter', ['clean']);
        if (cleanResult.exitCode != 0) {
          throw Exception('flutter clean failed: ${cleanResult.stderr}');
        }
      });

      final projectName = await getProjectName() ?? 'project';

      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final hour = now.hour.toString().padLeft(2, '0');
      final minute = now.minute.toString().padLeft(2, '0');
      final zipFileName = '$projectName-$date-$hour-$minute.zip';

      final defaultPath = await getDesktopPath();

      String? location = argResults?['output'] as String?;
      if (location == null || location.isEmpty) {
        stdout.write('Enter save location (default: Desktop): ');
        location = stdin.readLineSync()?.trim();
        if (location == null || location.isEmpty) {
          location = defaultPath;
        }
      }

      final outputPath = p.join(location, zipFileName);

      await runWithSpinner('📦 Creating clean ZIP archive...', () async {
        final encoder = ZipFileEncoder();
        encoder.create(outputPath);
        final rules = IgnoreRules.fromGitignore();
        final projectDir = Directory.current;
        final entities =
            projectDir.listSync(recursive: true, followLinks: false);

        for (final entity in entities) {
          final relativePath = p.relative(entity.path, from: projectDir.path);

          if (!rules.shouldIgnore(relativePath, entity) && entity is File) {
            encoder.addFileSync(entity, p.join(projectName, relativePath));
          }
        }
        encoder.close();
      });

      kLog('✅ ZIP file created successfully!', type: LogType.success);
      kLog('📁 Location: $outputPath', type: LogType.info);
    } catch (e) {
      kLog('❌ An error occurred while creating ZIP: $e', type: LogType.error);
      exit(1);
    }
  }
}

// For backward compatibility while refactoring others
Future<void> handleZipCommand() async {
  await ZipCommand().run();
}
