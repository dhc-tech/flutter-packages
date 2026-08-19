// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:args/command_runner.dart';

import '../utils/logger.dart';
import '../utils/project_rebrander.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';

/// Command to rename the Flutter app and change its bundle ID / package name.
class RenameCommand extends Command<void> {
  /// Creates the rename command and registers its options.
  RenameCommand() {
    argParser.addOption(
      'name',
      abbr: 'n',
      help: 'New display name for the app',
    );
    argParser.addOption(
      'bundle-id',
      abbr: 'b',
      help: 'New bundle ID / package name (e.g., com.example.app)',
    );
  }
  @override
  final name = 'rename';
  @override
  final description =
      'Renames the Flutter app and changes the bundle ID / package name.';

  @override
  Future<void> run() async {
    if (!await isFlutterProject()) {
      kLog(
        '❗ This command must be run inside a Flutter project.',
        type: LogType.error,
      );
      return;
    }

    var newName = argResults?['name'] as String?;
    var newBundleId = argResults?['bundle-id'] as String?;

    if (newName == null && newBundleId == null) {
      kLog('\n🏷️  APP RENAMING');
      stdout.write('Enter new app display name (leave empty to skip): ');
      newName = stdin.readLineSync()?.trim();
      if (newName?.isEmpty ?? true) {
        newName = null;
      }

      stdout.write(
        'Enter new bundle ID (e.g., com.example.app, leave empty to skip): ',
      );
      newBundleId = stdin.readLineSync()?.trim();
      if (newBundleId?.isEmpty ?? true) {
        newBundleId = null;
      }

      if (newName == null && newBundleId == null) {
        kLog('❗ No changes provided.', type: LogType.warning);
        return;
      }
    }

    final String currentProjectName = await getProjectName() ?? 'app';
    final String currentAppLabel = await getAppLabel() ?? currentProjectName;
    final String currentBundleId = await getBundleId() ?? 'com.example.app';

    if (newBundleId != null && !_isValidBundleId(newBundleId)) {
      kLog(
        '❗ Invalid bundle ID format. Expected something like "com.example.app".',
        type: LogType.error,
      );
      return;
    }

    final String targetName = newName ?? currentAppLabel;
    final String targetBundleId = newBundleId ?? currentBundleId;

    await runWithSpinner('🏗️  Rebranding project...', () async {
      final rebrander = ProjectRebrander(
        projectDir: findProjectRoot()!,
        newSlug: currentProjectName,
        newAppName: targetName,
        newBundleId: targetBundleId,
      );
      await rebrander.rebrand();
    });

    kLog('✅ App successfully renamed!', type: LogType.success);
    kLog(
      '💡 Run "flutter clean" and "flutter pub get" to refresh all artifacts.',
    );
  }

  bool _isValidBundleId(String id) {
    return RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(id);
  }
}

/// Handles the rename command from the interactive menu.
Future<void> handleRenameCommand(List<String> args) async {
  final CommandRunner<dynamic> runner = CommandRunner('dg', 'Rename app')
    ..addCommand(RenameCommand());
  await runner.run(args);
}
