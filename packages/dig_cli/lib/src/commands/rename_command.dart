import 'dart:io';
import 'package:args/command_runner.dart';
import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';
import '../utils/project_rebrander.dart';

class RenameCommand extends Command {
  @override
  final name = 'rename';
  @override
  final description =
      'Renames the Flutter app and changes the bundle ID / package name.';

  RenameCommand() {
    argParser.addOption('name',
        abbr: 'n', help: 'New display name for the app');
    argParser.addOption('bundle-id',
        abbr: 'b',
        help: 'New bundle ID / package name (e.g., com.example.app)');
  }

  @override
  Future<void> run() async {
    if (!await isFlutterProject()) {
      kLog('❗ This command must be run inside a Flutter project.',
          type: LogType.error);
      return;
    }

    String? newName = argResults?['name'] as String?;
    String? newBundleId = argResults?['bundle-id'] as String?;

    if (newName == null && newBundleId == null) {
      kLog('\n🏷️  APP RENAMING', type: LogType.info);
      stdout.write('Enter new app display name (leave empty to skip): ');
      newName = stdin.readLineSync()?.trim();
      if (newName?.isEmpty ?? true) newName = null;

      stdout.write(
          'Enter new bundle ID (e.g., com.example.app, leave empty to skip): ');
      newBundleId = stdin.readLineSync()?.trim();
      if (newBundleId?.isEmpty ?? true) newBundleId = null;

      if (newName == null && newBundleId == null) {
        kLog('❗ No changes provided.', type: LogType.warning);
        return;
      }
    }

    final currentProjectName = await getProjectName() ?? 'app';
    final currentAppLabel = await getAppLabel() ?? currentProjectName;
    final currentBundleId = await getBundleId() ?? 'com.example.app';

    if (newBundleId != null && !_isValidBundleId(newBundleId)) {
      kLog(
          '❗ Invalid bundle ID format. Expected something like "com.example.app".',
          type: LogType.error);
      return;
    }

    final targetName = newName ?? currentAppLabel;
    final targetBundleId = newBundleId ?? currentBundleId;

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
        type: LogType.info);
  }

  bool _isValidBundleId(String id) {
    return RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(id);
  }
}

Future<void> handleRenameCommand(List<String> args) async {
  final runner = CommandRunner('dg', 'Rename app')..addCommand(RenameCommand());
  await runner.run(args);
}
