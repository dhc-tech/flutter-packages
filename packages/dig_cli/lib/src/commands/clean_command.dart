import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';

/// Command to thoroughly clean the Flutter project and build artifacts.
class CleanCommand extends Command<void> {
  /// Creates the clean command and registers its flags.
  CleanCommand() {
    argParser.addFlag(
      'global',
      abbr: 'g',
      negatable: false,
      help: 'Also clean global caches (Xcode DerivedData, Gradle caches)',
    );
  }
  @override
  final name = 'clean';
  @override
  final description =
      'Thoroughly cleans the Flutter project and build artifacts.';

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

    final bool cleanGlobal = argResults?['global'] as bool? ?? false;

    try {
      kLog('🚀 Starting thorough project cleanup...');

      await runWithSpinner('🧹 Cleaning Flutter project (flutter clean)',
          () async {
        final ProcessResult result = await Process.run('flutter', ['clean']);
        if (result.exitCode != 0) {
          throw Exception(
            'flutter clean failed with exit code ${result.exitCode}\n${result.stderr}',
          );
        }
      });

      await _deleteIfExists('build');
      kLog('🗑️  Removed build directory');

      await runWithSpinner('📦 Getting Dart packages (flutter pub get)',
          () async {
        final ProcessResult result =
            await Process.run('flutter', ['pub', 'get']);
        if (result.exitCode != 0) {
          throw Exception(
            'flutter pub get failed with exit code ${result.exitCode}\n${result.stderr}',
          );
        }
      });

      final String? homeDir = Platform.isWindows
          ? Platform.environment['USERPROFILE']
          : Platform.environment['HOME'];

      if (Platform.isMacOS) {
        kLog(' macOS: Running iOS specific cleanup...');
        await runWithSpinner(
          '📦 Pre-caching Flutter iOS artifacts',
          () async => Process.run('flutter', ['precache', '--ios']),
        );

        final iosDir = Directory('ios');
        final podfile = File(p.join(iosDir.path, 'Podfile'));
        if (iosDir.existsSync() && podfile.existsSync()) {
          await _deleteIfExists(p.join(iosDir.path, '.symlinks'));
          await _deleteIfExists(p.join(iosDir.path, 'Podfile.lock'));
          await _deleteIfExists(p.join(iosDir.path, 'Pods'));
          await _deleteIfExists(p.join(iosDir.path, 'build'));
          kLog('🧼 Cleaned local iOS workspace.');

          await runWithSpinner(
            '📥 Installing CocoaPods (pod install)',
            () async {
              final ProcessResult result = await Process.run(
                  'pod',
                  [
                    'install',
                  ],
                  workingDirectory: iosDir.path);
              if (result.exitCode != 0) {
                kLog(
                  '⚠️ pod install failed. You might need to run it manually.',
                  type: LogType.warning,
                );
              }
            },
          );
        }

        if (cleanGlobal && homeDir != null) {
          final derivedData = Directory(
            p.join(homeDir, 'Library', 'Developer', 'Xcode', 'DerivedData'),
          );
          if (derivedData.existsSync()) {
            kLog('🧹 Cleaning global Xcode DerivedData...');
            derivedData.deleteSync(recursive: true);
          }
        }
      } else if (Platform.isWindows) {
        kLog(
          '🪟 Windows: Running platform specific cleanup...',
        );
        await _deleteIfExists('windows/build');
        await _deleteIfExists('windows/flutter/ephemeral');
        kLog('🧼 Cleaned local Windows build artifacts.');

        if (cleanGlobal && homeDir != null) {
          final gradleCache = Directory(p.join(homeDir, '.gradle', 'caches'));
          if (gradleCache.existsSync()) {
            kLog('🧹 Cleaning global Gradle caches...');
            gradleCache.deleteSync(recursive: true);
          }
        }
      } else if (Platform.isLinux) {
        kLog(
          '🐧 Linux: Running platform specific cleanup...',
        );
        await _deleteIfExists('linux/build');
        await _deleteIfExists('linux/flutter/ephemeral');
        kLog('🧼 Cleaned local Linux build artifacts.');

        if (cleanGlobal && homeDir != null) {
          final gradleCache = Directory(p.join(homeDir, '.gradle', 'caches'));
          if (gradleCache.existsSync()) {
            kLog('🧹 Cleaning global Gradle caches...');
            gradleCache.deleteSync(recursive: true);
          }
        }
      }

      kLog('✅ All Clean! Project reset complete.', type: LogType.success);
    } catch (e) {
      kLog('❌ An error occurred during cleanup: $e', type: LogType.error);
      exit(1);
    }
  }

  Future<void> _deleteIfExists(String path) async {
    try {
      final entity = Directory(path);
      if (entity.existsSync()) {
        entity.deleteSync(recursive: true);
      } else {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    } catch (e) {
      kLog('⚠️  Could not delete "$path": $e', type: LogType.warning);
    }
  }
}

/// Handles the clean command from the interactive menu (for backward compatibility while refactoring others).
Future<void> handleCleanCommand() async {
  await CleanCommand().run();
}
