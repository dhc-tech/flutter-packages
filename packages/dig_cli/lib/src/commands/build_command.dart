import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';

class BuildCommand extends Command {
  @override
  final name =
      'create'; // Kept as 'create' for compatibility with previous version
  @override
  final description = 'Builds the Flutter project into an APK or App Bundle.';

  BuildCommand() {
    argParser.addOption('output', abbr: 'o', help: 'Specify output directory');
    argParser.addOption(
      'name',
      abbr: 'n',
      help: 'Custom name prefix for the output file',
    );
    argParser.addFlag(
      'timestamp',
      defaultsTo: true,
      help: 'Include date and time in the filename',
    );
  }

  @override
  Future<void> run() async {
    final buildType =
        argResults?.rest.isNotEmpty == true ? argResults!.rest.first : 'apk';
    String? outputDir = argResults?['output'] as String?;
    String? customName = argResults?['name'] as String?;
    bool includeTimestamp = argResults?['timestamp'] as bool? ?? true;

    if (stdin.hasTerminal && outputDir == null && customName == null) {
      kLog('\n🏗️  BUILD CONFIGURATION', type: LogType.info);
      stdout.write('Enter output directory (press enter for Desktop): ');
      final outInput = stdin.readLineSync()?.trim();
      if (outInput != null && outInput.isNotEmpty) {
        outputDir = outInput;
      }

      stdout.write(
          'Enter custom name prefix (press enter to use project name): ');
      final nameInput = stdin.readLineSync()?.trim();
      if (nameInput != null && nameInput.isNotEmpty) {
        customName = nameInput;
      }

      stdout.write('Include date and time in filename? (Y/n): ');
      final timeInput = stdin.readLineSync()?.trim().toLowerCase();
      if (timeInput == 'n' || timeInput == 'no') {
        includeTimestamp = false;
      }
    }

    outputDir ??= await getDesktopPath();

    if (buildType == 'apk' || buildType == 'build') {
      await _runBuildProcess(
        outputDir: outputDir,
        customName: customName,
        includeTimestamp: includeTimestamp,
        buildDisplayType: 'APK',
        buildArgs: ['build', 'apk', '--release'],
        sourcePath: p.join(
          'build',
          'app',
          'outputs',
          'flutter-apk',
          'app-release.apk',
        ),
        fileExtension: 'apk',
      );
    } else if (buildType == 'bundle') {
      await _runBuildProcess(
        outputDir: outputDir,
        customName: customName,
        includeTimestamp: includeTimestamp,
        buildDisplayType: 'App Bundle',
        buildArgs: ['build', 'appbundle', '--release'],
        sourcePath: p.join(
          'build',
          'app',
          'outputs',
          'bundle',
          'release',
          'app-release.aab',
        ),
        fileExtension: 'aab',
      );
    } else {
      kLog(
        'Unknown build type: "$buildType". Use "apk" or "bundle".',
        type: LogType.error,
      );
      exit(64);
    }
  }

  Future<void> _runBuildProcess({
    required String outputDir,
    String? customName,
    bool includeTimestamp = true,
    required String buildDisplayType,
    required List<String> buildArgs,
    required String sourcePath,
    required String fileExtension,
  }) async {
    if (!await isFlutterProject()) {
      kLog(
        '❗ This command must be run inside a Flutter project.',
        type: LogType.error,
      );
      exit(1);
    }

    try {
      final projectName = customName ?? await getProjectName();
      if (projectName == null || projectName.isEmpty) {
        kLog(
          '❗ Project name not found and no custom name was provided!',
          type: LogType.error,
        );
        exit(1);
      }

      String filename;
      if (includeTimestamp) {
        final now = DateTime.now();
        final date =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final hour = now.hour.toString().padLeft(2, '0');
        final minute = now.minute.toString().padLeft(2, '0');
        filename = '$projectName-$date-$hour-$minute.$fileExtension';
        kLog('📅 Date: $date @ $hour:$minute');
      } else {
        filename = '$projectName.$fileExtension';
      }

      kLog('📱 APP PREFIX: $projectName');

      final result = await runWithSpinner(
        '🚧 Building $buildDisplayType (release)...',
        () => Process.run('flutter', buildArgs),
      );

      if (result.exitCode != 0) {
        kLog('❗ Build failed. See error below:', type: LogType.error);
        stderr.writeln(result.stderr);
        exit(1);
      }

      final srcFile = File(sourcePath);
      if (!await srcFile.exists()) {
        kLog(
          '❗ Build failed. Output file not found at: $sourcePath',
          type: LogType.error,
        );
        exit(1);
      }

      final destFile = File(p.join(outputDir, filename));
      await srcFile.copy(destFile.path);
      await srcFile.delete();

      final fileSize = await destFile.length();
      final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);

      kLog('\n✅ $buildDisplayType created successfully!',
          type: LogType.success);
      kLog('-------------------------------------------');
      kLog('📁 Location: ${destFile.path}', type: LogType.success);
      kLog('📊 Size: ${sizeInMB}MB', type: LogType.info);
      kLog('-------------------------------------------\n');
    } catch (e) {
      kLog(
        '❌ An unexpected error occurred during the build: $e',
        type: LogType.error,
      );
      exit(1);
    }
  }
}

// For backward compatibility while refactoring others
Future<void> handleBuildCommand(List<String> args) async {
  final runner = CommandRunner('dig', 'DIG CLI tool');
  runner.addCommand(BuildCommand());
  await runner.run(['create', ...args]);
}
