// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../ui/box_painter.dart';
import '../utils/logger.dart';

/// Command that injects DIG CLI shell aliases into the user's shell profile.
class SetupAliasesCommand extends Command<void> {
  @override
  final String name = 'setup-aliases';
  @override
  final String description =
      'Automatically injects DIG CLI aliases (dgm, dgp, dga, etc.) into your shell profile.';

  @override
  Future<void> run() async {
    final String? home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) {
      kLog(
        '❗ Could not determine home directory to set up aliases.',
        type: LogType.error,
      );
      return;
    }

    File? targetProfile;
    var profileName = '';

    if (Platform.isWindows) {
      // Windows PowerShell Profile
      final String psProfileDir = p.join(home, 'Documents', 'PowerShell');
      final psProfile = File(
        p.join(psProfileDir, 'Microsoft.PowerShell_profile.ps1'),
      );

      if (!Directory(psProfileDir).existsSync()) {
        Directory(psProfileDir).createSync(recursive: true);
      }

      targetProfile = psProfile;
      profileName = 'PowerShell Profile';
    } else {
      // Unix-like (MacOS / Linux)
      final zshrc = File(p.join(home, '.zshrc'));
      final bashrc = File(p.join(home, '.bashrc'));
      final bashProfile = File(p.join(home, '.bash_profile'));

      if (zshrc.existsSync()) {
        targetProfile = zshrc;
      } else if (bashrc.existsSync()) {
        targetProfile = bashrc;
      } else if (bashProfile.existsSync()) {
        targetProfile = bashProfile;
      } else {
        // Fallback to .zshrc on Mac or .bashrc on Linux
        targetProfile = Platform.isMacOS ? zshrc : bashrc;
        kLog(
          '  Creating new profile file: ${p.basename(targetProfile.path)}',
        );
      }
      profileName = p.basename(targetProfile.path);
    }

    // Prompt for custom prefix
    stdout.write('  Enter your preferred shortcut prefix (default: dg): ');
    final String? input = stdin.readLineSync()?.trim();
    final String prefix = (input == null || input.isEmpty) ? 'dg' : input;

    var aliasesBlock = '';

    if (Platform.isWindows) {
      aliasesBlock = '''

# --- DIG CLI Custom Aliases ---
function ${prefix}p { dg create-project \$args }
function ${prefix}m { dg create-module \$args }
function ${prefix}rm { dg remove-module \$args }
function ${prefix}c { dg clean \$args }
function ${prefix}a { dg asset build \$args }
function ${prefix}i { dg ios \$args }
function ${prefix}apk { dg create apk \$args }
# ------------------------------
''';
    } else {
      aliasesBlock = '''

# --- DIG CLI Custom Aliases ---
alias ${prefix}p="dg create-project"
alias ${prefix}m="dg create-module"
alias ${prefix}rm="dg remove-module"
alias ${prefix}c="dg clean"
alias ${prefix}a="dg asset build"
alias ${prefix}i="dg ios"
alias ${prefix}apk="dg create apk"
# ------------------------------
''';
    }

    var content = '';
    if (targetProfile.existsSync()) {
      content = targetProfile.readAsStringSync();
    }

    if (content.contains('# --- DIG CLI Custom Aliases ---')) {
      kLog(
        '✅ DIG CLI aliases are already installed in $profileName',
        type: LogType.success,
      );
      return;
    }

    await targetProfile.writeAsString(aliasesBlock, mode: FileMode.append);

    final painter = BoxPainter();
    kLog('');
    painter.drawHeader('ALIASES INSTALLED SUCCESSFULLY');
    painter.drawRow('Profile', profileName);
    painter.drawRow('Prefix', prefix);
    painter.drawRow('Example', '${prefix}m (create-module)');
    painter.drawRow('Example', '${prefix}p (create-project)');
    painter.drawFooter();

    if (Platform.isWindows) {
      kLog(
        '\n🚀 Restart PowerShell or run ". \$PROFILE" to activate them.',
      );
    } else {
      kLog(
        '\n🚀 Run "source ~/$profileName" to activate them immediately.',
      );
    }
  }
}
