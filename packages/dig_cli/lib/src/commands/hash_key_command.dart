import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';

/// Command to generate base64-encoded SHA1 hash key for Android.
class HashKeyCommand extends Command<void> {
  /// Creates the hash-key command and registers its options/flags.
  HashKeyCommand() {
    argParser.addFlag('debug', help: 'Use debug keystore');
    argParser.addFlag('release', help: 'Use release keystore');
    argParser.addOption('keystore', abbr: 'k', help: 'Path to keystore file');
    argParser.addOption('alias', abbr: 'a', help: 'Key alias');
    argParser.addOption('storepass', help: 'Keystore password');
    argParser.addOption('keypass', help: 'Key password');
  }
  @override
  final name = 'hash-key';
  @override
  final description = 'Generates base64-encoded SHA1 hash key for Android.';

  @override
  Future<void> run() async {
    final bool isDebug = argResults?['debug'] as bool? ?? false;
    final bool isRelease = argResults?['release'] as bool? ?? false;

    if (isDebug) {
      await _generateDebugHash();
    } else if (isRelease) {
      await _generateReleaseHash();
    } else {
      kLog('❗ Please specify --debug or --release', type: LogType.error);
      kLog(usage);
    }
  }

  Future<void> _generateDebugHash() async {
    final String home = Platform.environment['HOME'] ?? '';
    final String debugKeystorePath = p.join(home, '.android', 'debug.keystore');

    if (!File(debugKeystorePath).existsSync()) {
      kLog(
        '❗ Debug keystore not found at $debugKeystorePath',
        type: LogType.error,
      );
      return;
    }

    await _runHashCommand(
      keystore: debugKeystorePath,
      alias: 'androiddebugkey',
      storepass: 'android',
      keypass: 'android',
      label: 'DEBUG',
    );
  }

  Future<void> _generateReleaseHash() async {
    var keystore = argResults?['keystore'] as String?;
    var alias = argResults?['alias'] as String?;
    var storepass = argResults?['storepass'] as String?;
    var keypass = argResults?['keypass'] as String?;

    if (keystore == null ||
        alias == null ||
        storepass == null ||
        keypass == null) {
      // Auto-detect project key.properties
      final Map<String, String>? projectConfig =
          await _tryReadProjectKeyProperties();
      if (projectConfig != null && projectConfig.containsKey('storeFile')) {
        final String? stFile = projectConfig['storeFile'];
        kLog(
          '\n✨ Found key.properties in current project.',
          type: LogType.success,
        );
        kLog('   Keystore: $stFile');
        kLog('   Alias: ${projectConfig['keyAlias']}');

        stdout.write('\nUse this project release key? (Y/n): ');
        final String? ans = stdin.readLineSync()?.trim().toLowerCase();
        if (ans == null || ans.isEmpty || ans == 'y') {
          keystore = stFile;
          alias = projectConfig['keyAlias'];
          storepass = projectConfig['storePassword'];
          keypass = projectConfig['keyPassword'];
        }
      }

      // If user declined or not fully resolved via key.properties, ask manually
      if (keystore == null ||
          alias == null ||
          storepass == null ||
          keypass == null) {
        kLog('\n🔑 Release Key Details Required', type: LogType.warning);

        if (keystore == null) {
          stdout.write('Enter keystore path (e.g., /path/to/my.jks): ');
          keystore = stdin.readLineSync()?.trim();
        }
        if (alias == null) {
          stdout.write('Enter key alias: ');
          alias = stdin.readLineSync()?.trim();
        }
        if (storepass == null) {
          stdout.write('Enter store password: ');
          storepass = stdin.readLineSync()?.trim();
        }
        if (keypass == null) {
          stdout.write('Enter key password: ');
          keypass = stdin.readLineSync()?.trim();
        }
      }
    }

    if (keystore == null ||
        keystore.isEmpty ||
        alias == null ||
        alias.isEmpty ||
        storepass == null ||
        storepass.isEmpty ||
        keypass == null ||
        keypass.isEmpty) {
      kLog(
        '❗ All fields are required for release hash key.',
        type: LogType.error,
      );
      return;
    }

    if (!File(keystore).existsSync()) {
      kLog('❗ Keystore file not found at $keystore', type: LogType.error);
      return;
    }

    await _runHashCommand(
      keystore: keystore,
      alias: alias,
      storepass: storepass,
      keypass: keypass,
      label: 'RELEASE',
    );
  }

  Future<void> _runHashCommand({
    required String keystore,
    required String alias,
    required String storepass,
    required String keypass,
    required String label,
  }) async {
    kLog('\n🔐 Generating $label Hash Key...');

    try {
      // 1. Check for required tools
      final ProcessResult keytoolCheck =
          await Process.run('which', ['keytool']);
      final ProcessResult opensslCheck =
          await Process.run('which', ['openssl']);

      if (keytoolCheck.exitCode != 0) {
        kLog(
          '❗ "keytool" command not found. Please ensure JDK is installed and in your PATH.',
          type: LogType.error,
        );
        return;
      }
      if (opensslCheck.exitCode != 0) {
        kLog(
          '❗ "openssl" command not found. Please install openssl.',
          type: LogType.error,
        );
        return;
      }

      final ProcessResult result =
          await runWithSpinner('🔍 Processing...', () async {
        // We use piping manually in Dart for better security (avoids sh -c issues)
        final Process keytoolProc = await Process.start('keytool', [
          '-exportcert',
          '-alias',
          alias,
          '-keystore',
          keystore,
          '-storepass',
          storepass,
          '-keypass',
          keypass,
        ]);

        final Process sha1Proc =
            await Process.start('openssl', ['sha1', '-binary']);
        final Process base64Proc = await Process.start('openssl', ['base64']);

        // Pipe: keytool -> sha1 -> base64
        await keytoolProc.stdout.pipe(sha1Proc.stdin);
        await sha1Proc.stdout.pipe(base64Proc.stdin);

        final String hashResult =
            await base64Proc.stdout.transform(const Utf8Decoder()).join();
        final int keytoolExit = await keytoolProc.exitCode;
        final int sha1Exit = await sha1Proc.exitCode;
        final int base64Exit = await base64Proc.exitCode;

        final String stderrOutput =
            await keytoolProc.stderr.transform(const Utf8Decoder()).join();

        final finalExitCode = (keytoolExit != 0)
            ? keytoolExit
            : (sha1Exit != 0 ? sha1Exit : base64Exit);

        return ProcessResult(0, finalExitCode, hashResult, stderrOutput);
      });

      if (result.exitCode == 0) {
        final String hash = result.stdout.toString().trim();
        if (hash.isEmpty) {
          kLog(
            '❗ Generated hash key is empty. Check if the alias and passwords are correct.',
            type: LogType.error,
          );
          return;
        }
        kLog('\n✅ $label Hash Key (Base64):', type: LogType.success);
        kLog('   $hash', type: LogType.success);
        kLog(
          '\n💡 This is used for Google Sign-In and Facebook Login.',
        );
      } else {
        kLog('❗ Failed to generate hash key.', type: LogType.error);
        kLog('Error: ${result.stderr}', type: LogType.error);
      }
    } catch (e) {
      kLog('❌ An error occurred: $e', type: LogType.error);
    }
  }

  Future<Map<String, String>?> _tryReadProjectKeyProperties() async {
    final Directory? projectRoot = findProjectRoot();
    if (projectRoot == null) {
      return null;
    }

    final keyPropFile = File(
      p.join(projectRoot.path, 'android', 'key.properties'),
    );
    if (!keyPropFile.existsSync()) {
      return null;
    }

    final config = <String, String>{};
    final List<String> lines = await keyPropFile.readAsLines();
    for (final line in lines) {
      if (line.trim().isEmpty || line.startsWith('#')) {
        continue;
      }
      final List<String> parts = line.split('=');
      if (parts.length >= 2) {
        config[parts[0].trim()] = parts.sublist(1).join('=').trim();
      }
    }

    if (config.containsKey('storeFile')) {
      final String storeFile = config['storeFile']!;
      if (!p.isAbsolute(storeFile)) {
        final String appDir = p.join(projectRoot.path, 'android', 'app');
        final String androidDir = p.join(projectRoot.path, 'android');
        if (File(p.join(appDir, storeFile)).existsSync()) {
          config['storeFile'] = p.normalize(p.join(appDir, storeFile));
        } else if (File(p.join(androidDir, storeFile)).existsSync()) {
          config['storeFile'] = p.normalize(p.join(androidDir, storeFile));
        } else {
          // Unresolvable relative path fallback
        }
      }
    }
    return config;
  }
}

/// Handles the hash-key command from the interactive menu.
Future<void> handleHashKeyCommand(List<String> args) async {
  final command = HashKeyCommand();
  final CommandRunner<dynamic> runner = CommandRunner('dg', 'Hash Key')
    ..addCommand(command);
  await runner.run(['hash-key', ...args]);
}
