import 'dart:io';
import 'package:ansicolor/ansicolor.dart';
import 'package:args/command_runner.dart';
import 'utils/project_utils.dart';
import 'commands/asset_command.dart';
import 'commands/build_command.dart';
import 'commands/ios_build_command.dart';
import 'commands/sha_keys_command.dart';
import 'commands/hash_key_command.dart';
import 'commands/create_jks_command.dart';
import 'commands/create_module_command.dart';
import 'commands/remove_module_command.dart';
import 'commands/setup_aliases_command.dart';
import 'commands/create_project_command.dart';
import 'commands/clean_command.dart';
import 'commands/zip_command.dart';
import 'commands/rename_command.dart';
import 'commands/pub_cache_command.dart';
import 'utils/version_utils.dart';
import 'version_helper.dart';
import 'utils/logger.dart';
import 'ui/box_painter.dart';

/// Interactive dashboard: organized, professional, and easy to navigate.
class InteractiveMenu {
  final BoxPainter _painter = BoxPainter();
  final int _width = 50;

  void _clearScreen() {
    try {
      if (stdout.hasTerminal) {
        stdout.write('\x1B[2J\x1B[0;0H');
      }
    } catch (_) {}
  }

  void _drawPrompt(String range) {
    stdout.write('\n  Select [${_painter.titlePen(range)}] or [0] to exit: ');
  }

  String? _promptUser(String label, {String? defaultValue}) {
    final displayDefault =
        defaultValue != null ? ' (${_painter.textPen(defaultValue)})' : '';
    stdout.write('  $label$displayDefault: ');
    final input = stdin.readLineSync()?.trim();
    return (input == null || input.isEmpty) ? defaultValue : input;
  }

  Future<void> _pause() async {
    kLog('\n  Press Enter to continue...', type: LogType.info);
    stdin.readLineSync();
  }

  Future<void> show() async {
    while (true) {
      _clearScreen();
      final isFlutter = await isFlutterProject();
      final status =
          isFlutter ? 'Flutter Project Detected' : 'No Flutter Project Found';
      final statusPen = isFlutter ? (AnsiPen()..green()) : (AnsiPen()..red());

      _painter.drawHeader('DIG CLI DASHBOARD', width: _width);
      _painter.drawRow('Version', 'v$kDigCliVersion', width: _width);
      _painter.drawRow('Status', statusPen(status), width: _width);
      _painter.drawRow('Developer', 'Digvijaysinh Chauhan', width: _width);
      _painter.drawDivider('MAIN CATEGORIES', width: _width);

      if (isFlutter) {
        _painter.drawMenuItem('1', 'Build & Release', width: _width);
        _painter.drawMenuItem('2', 'Clean & Fix', width: _width);
        _painter.drawMenuItem('3', 'Signing & Keys', width: _width);
        _painter.drawMenuItem('4', 'Configuration', width: _width);
        _painter.drawMenuItem('5', 'Project Management', width: _width);
        _painter.drawMenuItem('6', 'Utilities', width: _width);
        _painter.drawFooter(width: _width);

        _drawPrompt('1-6');
      } else {
        _painter.drawMenuItem('1', 'Project Management (Create)',
            width: _width);
        _painter.drawMenuItem('2', 'Utilities', width: _width);
        _painter.drawFooter(width: _width);

        _drawPrompt('1-2');
      }

      final response = stdin.readLineSync()?.trim();
      if (response == '0') exit(0);
      if (response == null || response.isEmpty) continue;

      if (isFlutter) {
        switch (response) {
          case '1':
            await _buildReleaseMenu();
            break;
          case '2':
            await _cleanFixMenu();
            break;
          case '3':
            await _signingMenu();
            break;
          case '4':
            await _configurationMenu();
            break;
          case '5':
            await _projectMenu();
            break;
          case '6':
            await _utilitiesMenu();
            break;
        }
      } else {
        switch (response) {
          case '1':
            await _projectMenu();
            break;
          case '2':
            await _utilitiesMenu();
            break;
        }
      }
    }
  }

  Future<void> _buildReleaseMenu() async {
    while (true) {
      _clearScreen();
      _painter.drawHeader('BUILD & RELEASE', width: _width);
      _painter.drawMenuItem('1', 'Build APK (Release)', width: _width);
      _painter.drawMenuItem('2', 'Build App Bundle (AAB)', width: _width);
      _painter.drawMenuItem('3', 'Build iOS (IPA)', width: _width);
      _painter.drawFooter(width: _width);

      _drawPrompt('1-3');
      final r = stdin.readLineSync()?.trim();
      if (r == '0' || r == null || r.isEmpty) return;

      final runner = CommandRunner('dg', 'temp');
      switch (r) {
        case '1':
        case '2':
          final type = r == '1' ? 'apk' : 'bundle';
          final out = _promptUser('Output directory', defaultValue: 'Desktop');
          final name = _promptUser('Custom name prefix (optional)');
          final args = ['create', type];
          if (out != 'Desktop') args.addAll(['--output', out!]);
          if (name != null && name.isNotEmpty) args.addAll(['--name', name]);
          runner.addCommand(BuildCommand());
          await runner.run(args);
          await _pause();
          break;
        case '3':
          final out = _promptUser('Output directory', defaultValue: 'Desktop');
          final name = _promptUser('Custom name prefix (optional)');
          final args = ['ios'];
          if (out != 'Desktop') args.addAll(['--output', out!]);
          if (name != null && name.isNotEmpty) args.addAll(['--name', name]);
          runner.addCommand(IosBuildCommand());
          await runner.run(args);
          await _pause();
          break;
      }
    }
  }

  Future<void> _cleanFixMenu() async {
    while (true) {
      _clearScreen();
      _painter.drawHeader('CLEAN & FIX', width: _width);
      _painter.drawMenuItem('1', 'Flutter Clean', width: _width);
      _painter.drawMenuItem('2', 'Deep Reset (Wipe Caches)', width: _width);
      _painter.drawMenuItem('3', 'Repair Pub Cache', width: _width);
      _painter.drawFooter(width: _width);

      _drawPrompt('1-3');
      final r = stdin.readLineSync()?.trim();
      if (r == '0' || r == null || r.isEmpty) return;

      switch (r) {
        case '1':
          await Process.run('flutter', ['clean']);
          kLog('  Clean completed.', type: LogType.success);
          await _pause();
          break;
        case '2':
          await _handleFullReset();
          await _pause();
          break;
        case '3':
          final pubRunner = CommandRunner('dg', 'temp')
            ..addCommand(PubCacheCommand());
          await pubRunner.run(['pub-cache']);
          await _pause();
          break;
      }
    }
  }

  Future<void> _signingMenu() async {
    while (true) {
      _clearScreen();
      _painter.drawHeader('SIGNING & KEYS', width: _width);
      _painter.drawMenuItem('1', 'Create JKS Keystore', width: _width);
      _painter.drawMenuItem('2', 'Get SHA Keys (Report)', width: _width);
      _painter.drawMenuItem('3', 'Get Facebook/Google Hash', width: _width);
      _painter.drawFooter(width: _width);

      _drawPrompt('1-3');
      final r = stdin.readLineSync()?.trim();
      if (r == '0' || r == null || r.isEmpty) return;

      final runner = CommandRunner('dg', 'temp');
      switch (r) {
        case '1':
          runner.addCommand(CreateJksCommand());
          await runner.run(['create-jks']);
          await _pause();
          break;
        case '2':
          runner.addCommand(ShaKeysCommand());
          await runner.run(['sha-keys']);
          await _pause();
          break;
        case '3':
          stdout.write('Generate for Debug or Release? (d/R): ');
          final ans = stdin.readLineSync()?.trim().toLowerCase();
          final flag = (ans == 'd') ? '--debug' : '--release';
          runner.addCommand(HashKeyCommand());
          await runner.run(['hash-key', flag]);
          await _pause();
          break;
      }
    }
  }

  Future<void> _configurationMenu() async {
    while (true) {
      _clearScreen();
      _painter.drawHeader('CONFIGURATION', width: _width);
      _painter.drawMenuItem('1', 'Auto-Setup Assets', width: _width);
      _painter.drawFooter(width: _width);

      _drawPrompt('1');
      final r = stdin.readLineSync()?.trim();
      if (r == '0' || r == null || r.isEmpty) return;

      if (r == '1') {
        await handleAssetSetup();
        await _pause();
      }
    }
  }

  Future<void> _projectMenu() async {
    while (true) {
      _clearScreen();
      final isFlutter = await isFlutterProject();

      _painter.drawHeader('PROJECT MANAGEMENT', width: _width);
      if (isFlutter) {
        _painter.drawMenuItem('1', 'Create From Template', width: _width);
        _painter.drawMenuItem('2', 'Create GetX Module', width: _width);
        _painter.drawMenuItem('3', 'Remove GetX Module', width: _width);
        _painter.drawMenuItem('4', 'Rename / Rebrand App', width: _width);
        _painter.drawFooter(width: _width);
        _drawPrompt('1-4');
      } else {
        _painter.drawMenuItem('1', 'Create From Template', width: _width);
        _painter.drawFooter(width: _width);
        _drawPrompt('1');
      }

      final r = stdin.readLineSync()?.trim();
      if (r == '0' || r == null || r.isEmpty) return;

      final runner = CommandRunner('dg', 'temp');

      if (isFlutter) {
        switch (r) {
          case '1':
            final name = _promptUser('New Project Name');
            if (name == null || name.isEmpty) break;
            runner.addCommand(CreateProjectCommand());
            await runner.run(['create-project', '--name', name]);
            await _pause();
            break;
          case '2':
            final name = _promptUser('New Module Name');
            if (name == null || name.isEmpty) break;
            runner.addCommand(CreateModuleCommand());
            await runner.run(['create-module', '--name', name]);
            await _pause();
            break;
          case '3':
            final name = _promptUser('Module Name to Remove');
            if (name == null || name.isEmpty) break;
            runner.addCommand(RemoveModuleCommand());
            await runner.run(['remove-module', '--name', name]);
            await _pause();
            break;
          case '4':
            final name = _promptUser('New display name (optional)');
            final bundle = _promptUser('New bundle ID (optional)');
            final args = ['rename'];
            if (name != null && name.isNotEmpty) args.addAll(['--name', name]);
            if (bundle != null && bundle.isNotEmpty) {
              args.addAll(['--bundle-id', bundle]);
            }

            if (args.length == 1) {
              kLog('  No changes provided.', type: LogType.warning);
            } else {
              runner.addCommand(RenameCommand());
              await runner.run(args);
              await _pause();
            }
            break;
        }
      } else {
        if (r == '1') {
          final name = _promptUser('New Project Name');
          if (name == null || name.isEmpty) break;
          runner.addCommand(CreateProjectCommand());
          await runner.run(['create-project', '--name', name]);
          await _pause();
        }
      }
    }
  }

  Future<void> _utilitiesMenu() async {
    while (true) {
      _clearScreen();
      _painter.drawHeader('UTILITIES', width: _width);
      _painter.drawMenuItem('1', 'Zip Source Code', width: _width);
      _painter.drawMenuItem('2', 'Setup Shell Aliases', width: _width);
      _painter.drawMenuItem('3', 'Check For Updates', width: _width);
      _painter.drawMenuItem('4', 'Beta Channel Update', width: _width);
      _painter.drawFooter(width: _width);

      _drawPrompt('1-4');
      final r = stdin.readLineSync()?.trim();
      if (r == '0' || r == null || r.isEmpty) return;

      final runner = CommandRunner('dg', 'temp');
      switch (r) {
        case '1':
          runner.addCommand(ZipCommand());
          await runner.run(['zip']);
          await _pause();
          break;
        case '2':
          runner.addCommand(SetupAliasesCommand());
          await runner.run(['setup-aliases']);
          await _pause();
          break;
        case '3':
          await _handleUpdateCheck(false);
          await _pause();
          break;
        case '4':
          await _handleUpdateCheck(true);
          await _pause();
          break;
      }
    }
  }

  Future<void> _handleFullReset() async {
    stdout.write('  Wipe global build caches (Xcode/Gradle)? (y/N): ');
    final response = stdin.readLineSync()?.trim().toLowerCase();
    final args = response == 'y' ? ['clean', '--global'] : ['clean'];
    final runner = CommandRunner('dg', 'temp')..addCommand(CleanCommand());
    await runner.run(args);
  }

  Future<void> _handleUpdateCheck(bool beta) async {
    kLog('  Checking for updates...', type: LogType.info);
    final latest = beta
        ? await VersionUtils.getLatestPreReleaseVersion()
        : await VersionUtils.getLatestStableVersion();

    if (latest != null && VersionUtils.isNewer(latest, kDigCliVersion)) {
      stdout.write('  New version v$latest available. Install? (y/N): ');
      if (stdin.readLineSync()?.trim().toLowerCase() == 'y') {
        final verArg = beta ? latest : '';
        await Process.start(
            'dart', ['pub', 'global', 'activate', 'dig_cli', verArg],
            mode: ProcessStartMode.inheritStdio);
      }
    } else {
      kLog('  You are on the latest version.', type: LogType.success);
    }
  }
}

Future<void> showInteractiveMenu() async {
  await InteractiveMenu().show();
}
