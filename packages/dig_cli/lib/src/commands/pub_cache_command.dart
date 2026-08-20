// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:args/command_runner.dart';

import '../utils/logger.dart';
import '../utils/spinner.dart';

/// Command to repair the pub cache
class PubCacheCommand extends Command<void> {
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
  kLog('\n🔧 Repairing Pub Cache...');
  kLog(
    '💡 This may take a few minutes depending on cache size.\n',
  );

  try {
    final ProcessResult result = await runWithSpinner(
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
    final String output = result.stdout.toString().trim();
    if (output.isNotEmpty) {
      kLog(output);
    }

    kLog('\n✅ Pub cache repaired successfully!', type: LogType.success);
  } catch (e) {
    kLog('❌ An error occurred: $e', type: LogType.error);
  }
}
