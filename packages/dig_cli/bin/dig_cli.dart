import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:args/src/arg_results.dart';
import 'package:dig_cli/src/commands/asset_command.dart';
import 'package:dig_cli/src/commands/build_command.dart';
import 'package:dig_cli/src/commands/clean_command.dart';
import 'package:dig_cli/src/commands/create_jks_command.dart';
import 'package:dig_cli/src/commands/create_module_command.dart';
import 'package:dig_cli/src/commands/create_project_command.dart';
import 'package:dig_cli/src/commands/hash_key_command.dart';
import 'package:dig_cli/src/commands/ios_build_command.dart';
import 'package:dig_cli/src/commands/pub_cache_command.dart';
import 'package:dig_cli/src/commands/remove_module_command.dart';
import 'package:dig_cli/src/commands/rename_command.dart';
import 'package:dig_cli/src/commands/setup_aliases_command.dart';
import 'package:dig_cli/src/commands/sha_keys_command.dart';
import 'package:dig_cli/src/commands/version_command.dart';
import 'package:dig_cli/src/commands/zip_command.dart';
import 'package:dig_cli/src/interactive_menu.dart';

void main(List<String> arguments) async {
  final CommandRunner<dynamic> runner = CommandRunner('dg', 'DIG CLI - A powerful Flutter companion')
    ..addCommand(BuildCommand())
    ..addCommand(CleanCommand())
    ..addCommand(ZipCommand())
    ..addCommand(RenameCommand())
    ..addCommand(ShaKeysCommand())
    ..addCommand(HashKeyCommand())
    ..addCommand(CreateJksCommand())
    ..addCommand(CreateProjectCommand())
    ..addCommand(CreateModuleCommand())
    ..addCommand(RemoveModuleCommand())
    ..addCommand(SetupAliasesCommand())
    ..addCommand(IosBuildCommand())
    ..addCommand(AssetCommand())
    ..addCommand(PubCacheCommand())
    ..addCommand(VersionCommand());

  // Add global version flag
  runner.argParser.addFlag(
    'version',
    abbr: 'v',
    negatable: false,
    help: 'Show version',
  );

  if (arguments.isEmpty) {
    await showInteractiveMenu();
    return;
  }

  // Handle global flags before commands
  try {
    final ArgResults argResults = runner.argParser.parse(arguments);
    if (argResults['version'] as bool) {
      await handleShowVersionCommand();
      return;
    }
  } catch (_) {
    // If parsing fails here, let the runner handle it
  }

  try {
    await runner.run(arguments);
  } on UsageException catch (e) {
    // ignore: avoid_print
    print(e);
    exit(64);
  } catch (e) {
    // ignore: avoid_print
    print('❌ An error occurred: $e');
    exit(1);
  }
}
