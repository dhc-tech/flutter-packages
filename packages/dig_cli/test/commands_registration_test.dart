// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';
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
import 'package:test/test.dart';

/// Mirrors the wiring in bin/dig_cli.dart.
CommandRunner<dynamic> buildRunner() => CommandRunner('dg', 'DIG CLI')
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

void main() {
  group('command registration', () {
    test('all commands register without option or name collisions', () {
      expect(buildRunner().commands.keys, {
        'create',
        'clean',
        'zip',
        'rename',
        'sha-keys',
        'hash-key',
        'create-jks',
        'create-project',
        'create-module',
        'add-module',
        'remove-module',
        'setup-aliases',
        'ios',
        'asset',
        'pub-cache',
        'version',
        'help',
      });
    });

    test('every command has a description and generates usage text', () {
      final CommandRunner<dynamic> runner = buildRunner();
      for (final Command<dynamic> c in runner.commands.values) {
        expect(c.description, isNotEmpty, reason: c.name);
        expect(c.usage, contains(c.description), reason: c.name);
      }
      expect(runner.usage, contains('create-project'));
    });

    test('registering the same command twice is rejected', () {
      expect(
        () => buildRunner().addCommand(RenameCommand()),
        throwsArgumentError,
      );
    });

    test('build option defaults', () {
      final parsed = BuildCommand().argParser.parse(['apk']);
      expect(parsed['timestamp'], isTrue);
      expect(parsed['output'], isNull);
      expect(parsed['name'], isNull);
      expect(parsed.rest, ['apk']);
      expect(
        BuildCommand().argParser.parse(['--no-timestamp'])['timestamp'],
        isFalse,
      );
    });

    test('ios exposes only the supported export methods', () {
      final parser = IosBuildCommand().argParser;
      expect(parser.parse([])['method'], 'app-store');
      for (final m in ['ad-hoc', 'development', 'enterprise', 'app-store']) {
        expect(parser.parse(['-m', m])['method'], m);
      }
      expect(() => parser.parse(['-m', 'other']), throwsFormatException);
      expect(() => parser.parse(['-m']), throwsFormatException);
    });

    test('create-project defaults point at the template repo', () {
      final r = CreateProjectCommand().argParser.parse([]);
      expect(r['github-repo'], 'Digvijaysinh2204/dig_template');
      expect(r['github-branch'], 'main');
      expect(r['github'], isFalse);
    });

    test('abbreviations resolve to their long options', () {
      final r = CreateProjectCommand().argParser.parse([
        '-n',
        'x',
        '-a',
        'X App',
        '-b',
        'com.x.y',
        '-o',
        '/tmp/o',
        '-g',
      ]);
      expect(r['name'], 'x');
      expect(r['app-name'], 'X App');
      expect(r['bundle-id'], 'com.x.y');
      expect(r['output'], '/tmp/o');
      expect(r['github'], isTrue);
    });

    test('options requiring a value reject a missing value', () {
      expect(() => ZipCommand().argParser.parse(['-o']), throwsFormatException);
      expect(
        () => HashKeyCommand().argParser.parse(['--keystore']),
        throwsFormatException,
      );
      expect(
        () => CleanCommand().argParser.parse(['--global=1']),
        throwsFormatException,
      );
    });

    test('clean --global is a non-negatable flag', () {
      expect(CleanCommand().argParser.parse(['-g'])['global'], isTrue);
      expect(CleanCommand().argParser.parse([])['global'], isFalse);
      expect(
        () => CleanCommand().argParser.parse(['--no-global']),
        throwsFormatException,
      );
    });

    test('create-module and remove-module expose -n/--name', () {
      for (final parser in [
        CreateModuleCommand().argParser,
        RemoveModuleCommand().argParser,
      ]) {
        expect(parser.parse(['-n', 'auth'])['name'], 'auth');
        expect(parser.parse(['--name=billing'])['name'], 'billing');
      }
      expect(CreateModuleCommand().aliases, ['add-module']);
    });

    test('InteractiveMenu is constructible without side effects', () {
      expect(InteractiveMenu(), isA<InteractiveMenu>());
    });

    test(
      'runner reports unknown commands as UsageException with usage',
      () async {
        await expectLater(
          buildRunner().run(['nope']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('"nope"'),
            ),
          ),
        );
      },
    );

    test('runner reports a bad option for a subcommand', () async {
      await expectLater(
        buildRunner().run(['create', '--bogus']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
