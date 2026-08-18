import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';

/// Command to build iOS IPA and save it to desktop
class IosBuildCommand extends Command {
  @override
  final name = 'ios';
  @override
  final description = 'Builds the Flutter project into an iOS IPA file.';

  IosBuildCommand() {
    argParser.addOption('output', abbr: 'o', help: 'Specify output directory');
    argParser.addOption(
      'name',
      abbr: 'n',
      help: 'Custom name prefix for the output file',
    );
    argParser.addOption(
      'method',
      abbr: 'm',
      help: 'The export method (ad-hoc, development, enterprise, or app-store)',
      allowed: ['ad-hoc', 'development', 'enterprise', 'app-store'],
      defaultsTo: 'app-store',
    );
    argParser.addFlag(
      'timestamp',
      defaultsTo: true,
      help: 'Include date and time in the filename',
    );
  }

  @override
  Future<void> run() async {
    String? outputDir = argResults?['output'] as String?;
    String? customName = argResults?['name'] as String?;
    String? method = argResults?['method'] as String?;
    bool includeTimestamp = argResults?['timestamp'] as bool? ?? true;

    if (stdin.hasTerminal && outputDir == null && customName == null) {
      kLog('\n🍎 iOS BUILD CONFIGURATION', type: LogType.info);
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
    method ??= 'app-store';

    await buildIos(
      outputDir: outputDir,
      customName: customName,
      method: method,
      includeTimestamp: includeTimestamp,
    );
  }
}

Future<void> buildIos({
  String? outputDir,
  String? customName,
  String method = 'app-store',
  bool includeTimestamp = true,
}) async {
  // Check if running on macOS
  if (!Platform.isMacOS) {
    kLog('❗ iOS builds can only be created on macOS.', type: LogType.error);
    return;
  }

  if (!await isFlutterProject()) {
    kLog(
      '❗ This command must be run inside a Flutter project.',
      type: LogType.error,
    );
    return;
  }

  final savePath = outputDir ?? await getDesktopPath();

  try {
    final projectName = customName ?? await getProjectName();
    if (projectName == null || projectName.isEmpty) {
      kLog(
        '❗ Project name not found and no custom name was provided!',
        type: LogType.error,
      );
      return;
    }

    String filename;
    if (includeTimestamp) {
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final hour = now.hour.toString().padLeft(2, '0');
      final minute = now.minute.toString().padLeft(2, '0');
      filename = '$projectName-$date-$hour-$minute.ipa';

      kLog('\n🍎 iOS BUILD', type: LogType.info);
      kLog('📱 APP PREFIX: $projectName');
      kLog('📅 Date: $date @ $hour:$minute');
      kLog('🛠️  METHOD: $method');
    } else {
      filename = '$projectName.ipa';
      kLog('\n🍎 iOS BUILD', type: LogType.info);
      kLog('📱 APP PREFIX: $projectName');
      kLog('🛠️  METHOD: $method');
    }

    final projectRoot = findProjectRoot();
    if (projectRoot == null) {
      kLog('❗ Could not find project root.', type: LogType.error);
      return;
    }

    // Step 1: Build the iOS archive using Flutter
    kLog('\n📦 Building iOS IPA...', type: LogType.info);

    final buildResult = await runWithSpinner(
      '🚧 Running flutter build ipa --release --export-method $method...',
      () => Process.run(
        'flutter',
        ['build', 'ipa', '--release', '--export-method', method],
        workingDirectory: projectRoot.path,
      ),
    );

    if (buildResult.exitCode != 0) {
      kLog('❗ iOS build failed. See error below:', type: LogType.error);
      if (buildResult.stdout.toString().trim().isNotEmpty) {
        kLog('\n--- Build Output ---', type: LogType.info);
        print(buildResult.stdout);
      }
      if (buildResult.stderr.toString().trim().isNotEmpty) {
        kLog('\n--- Error Log ---', type: LogType.error);
        print(buildResult.stderr);
      }
      kLog('\n💡 Common fixes for iOS installation issues:',
          type: LogType.info);
      kLog(
          '   • Make sure you use "ad-hoc" or "development" for testing on devices.',
          type: LogType.info);
      kLog(
          '   • Verify your UDIDs are added to the provisioning profile (for ad-hoc).',
          type: LogType.info);
      kLog('   • App Store builds cannot be installed directly on devices.',
          type: LogType.info);
      return;
    }

    // Find the IPA file in build/ios/ipa/
    final ipaDir = Directory(p.join(projectRoot.path, 'build', 'ios', 'ipa'));

    if (!await ipaDir.exists()) {
      kLog('❗ IPA output directory not found.', type: LogType.error);
      return;
    }

    final ipaFiles = await ipaDir
        .list()
        .where((entity) => entity.path.endsWith('.ipa'))
        .toList();

    if (ipaFiles.isEmpty) {
      kLog('❗ No IPA file found in build output.', type: LogType.error);
      return;
    }

    // Copy and rename the IPA to the destination
    final srcFile = File(ipaFiles.first.path);
    final destFile = File(p.join(savePath, filename));

    await srcFile.copy(destFile.path);

    // Delete the source IPA after copying
    await srcFile.delete();

    final fileSize = await destFile.length();
    final sizeInMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);

    kLog('\n✅ iOS IPA created successfully!', type: LogType.success);
    kLog('-------------------------------------------');
    kLog('📁 Location: ${destFile.path}', type: LogType.success);
    kLog('📊 Size: ${sizeInMB}MB', type: LogType.info);
    kLog('-------------------------------------------\n');

    kLog('\n📲 To install on device:', type: LogType.info);
    kLog('   1. Connect your iPhone to this Mac.', type: LogType.info);
    kLog('   2. Open "Finder" or "Apple Configurator 2".', type: LogType.info);
    kLog('   3. Drag and drop the .ipa file onto your device.',
        type: LogType.info);
    if (method == 'app-store') {
      kLog(
          '\n⚠️  Warning: App Store builds cannot be installed directly. Use ad-hoc or development.',
          type: LogType.warning);
    }
  } catch (e) {
    kLog(
      '❌ An unexpected error occurred during the iOS build: $e',
      type: LogType.error,
    );
  }
}

/// Handles the iOS build command from the interactive menu
Future<void> handleIosBuildCommand(List<String> args) async {
  final runner = CommandRunner('dig', 'DIG CLI tool');
  runner.addCommand(IosBuildCommand());
  await runner.run(['ios', ...args]);
}
