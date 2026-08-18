import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';

class CleanCommand extends Command {
  @override
  final name = 'clean';
  @override
  final description =
      'Thoroughly cleans the Flutter project and build artifacts.';

  CleanCommand() {
    argParser.addFlag(
      'global',
      abbr: 'g',
      negatable: false,
      help: 'Also clean global caches (Xcode DerivedData, Gradle caches)',
    );
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

    final bool cleanGlobal = argResults?['global'] ?? false;

    try {
      kLog('🚀 Starting thorough project cleanup...', type: LogType.info);

      await runWithSpinner(
        '🧹 Cleaning Flutter project (flutter clean)',
        () async {
          final result = await Process.run('flutter', ['clean']);
          if (result.exitCode != 0) {
            throw Exception(
                'flutter clean failed with exit code ${result.exitCode}\n${result.stderr}');
          }
        },
      );

      await _deleteIfExists('build');
      kLog('🗑️  Removed build directory', type: LogType.info);

      await runWithSpinner(
        '📦 Getting Dart packages (flutter pub get)',
        () async {
          final result = await Process.run('flutter', ['pub', 'get']);
          if (result.exitCode != 0) {
            throw Exception(
                'flutter pub get failed with exit code ${result.exitCode}\n${result.stderr}');
          }
        },
      );

      final homeDir = Platform.isWindows
          ? Platform.environment['USERPROFILE']
          : Platform.environment['HOME'];

      if (Platform.isMacOS) {
        kLog(' macOS: Running iOS specific cleanup...', type: LogType.info);
        await runWithSpinner(
          '📦 Pre-caching Flutter iOS artifacts',
          () async => await Process.run('flutter', ['precache', '--ios']),
        );

        final iosDir = Directory('ios');
        final podfile = File(p.join(iosDir.path, 'Podfile'));
        if (await iosDir.exists() && await podfile.exists()) {
          await _deleteIfExists(p.join(iosDir.path, '.symlinks'));
          await _deleteIfExists(p.join(iosDir.path, 'Podfile.lock'));
          await _deleteIfExists(p.join(iosDir.path, 'Pods'));
          await _deleteIfExists(p.join(iosDir.path, 'build'));
          kLog('🧼 Cleaned local iOS workspace.', type: LogType.info);

          await runWithSpinner(
            '📥 Installing CocoaPods (pod install)',
            () async {
              final result = await Process.run('pod', ['install'],
                  workingDirectory: iosDir.path);
              if (result.exitCode != 0) {
                kLog(
                    '⚠️ pod install failed. You might need to run it manually.',
                    type: LogType.warning);
              }
            },
          );
        }

        if (cleanGlobal && homeDir != null) {
          final derivedData = Directory(
              p.join(homeDir, 'Library', 'Developer', 'Xcode', 'DerivedData'));
          if (await derivedData.exists()) {
            kLog('🧹 Cleaning global Xcode DerivedData...', type: LogType.info);
            await derivedData.delete(recursive: true);
          }
        }
      } else if (Platform.isWindows) {
        kLog('🪟 Windows: Running platform specific cleanup...',
            type: LogType.info);
        await _deleteIfExists('windows/build');
        await _deleteIfExists('windows/flutter/ephemeral');
        kLog('🧼 Cleaned local Windows build artifacts.', type: LogType.info);

        if (cleanGlobal && homeDir != null) {
          final gradleCache = Directory(p.join(homeDir, '.gradle', 'caches'));
          if (await gradleCache.exists()) {
            kLog('🧹 Cleaning global Gradle caches...', type: LogType.info);
            await gradleCache.delete(recursive: true);
          }
        }
      } else if (Platform.isLinux) {
        kLog('🐧 Linux: Running platform specific cleanup...',
            type: LogType.info);
        await _deleteIfExists('linux/build');
        await _deleteIfExists('linux/flutter/ephemeral');
        kLog('🧼 Cleaned local Linux build artifacts.', type: LogType.info);

        if (cleanGlobal && homeDir != null) {
          final gradleCache = Directory(p.join(homeDir, '.gradle', 'caches'));
          if (await gradleCache.exists()) {
            kLog('🧹 Cleaning global Gradle caches...', type: LogType.info);
            await gradleCache.delete(recursive: true);
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
      if (await entity.exists()) {
        await entity.delete(recursive: true);
      } else {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      kLog('⚠️  Could not delete "$path": $e', type: LogType.warning);
    }
  }
}

// For backward compatibility while refactoring others
Future<void> handleCleanCommand() async {
  await CleanCommand().run();
}
