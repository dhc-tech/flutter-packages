import 'dart:io';

import 'package:args/command_runner.dart';

import '../utils/logger.dart';
import '../utils/spinner.dart';

/// Command to repair the pub cache
class PubCacheCommand extends Command {
  @override
  final name = 'pub-cache';
  @override
  final description = 'Repairs the Dart/Flutter pub cache.';

  @override
  Future<void> run() async {
    await repairPubCache();
  }
}

/// Repairs the pub cache by running `flutter pub cache repair`
Future<void> repairPubCache() async {
  kLog('\n🔧 Repairing Pub Cache...', type: LogType.info);
  kLog(
    '💡 This may take a few minutes depending on cache size.\n',
    type: LogType.info,
  );

  try {
    final result = await runWithSpinner(
      '🔄 Running pub cache repair...',
      () =>
          Process.run('flutter', ['pub', 'cache', 'repair'], runInShell: true),
    );

    if (result.exitCode != 0) {
      kLog('❗ Pub cache repair failed.', type: LogType.error);
      kLog('Error: ${result.stderr}', type: LogType.error);
      return;
    }

    // Print the output
    final output = result.stdout.toString().trim();
    if (output.isNotEmpty) {
      print(output);
    }

    kLog('\n✅ Pub cache repaired successfully!', type: LogType.success);
  } catch (e) {
    kLog('❌ An error occurred: $e', type: LogType.error);
  }
}
