import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';
import '../ui/box_painter.dart';

class SetupAliasesCommand extends Command {
  @override
  final String name = 'setup-aliases';
  @override
  final String description =
      'Automatically injects DIG CLI aliases (dgm, dgp, dga, etc.) into your shell profile.';

  @override
  Future<void> run() async {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) {
      kLog('❗ Could not determine home directory to set up aliases.',
          type: LogType.error);
      return;
    }

    File? targetProfile;
    String profileName = '';

    if (Platform.isWindows) {
      // Windows PowerShell Profile
      final psProfileDir = p.join(home, 'Documents', 'PowerShell');
      final psProfile =
          File(p.join(psProfileDir, 'Microsoft.PowerShell_profile.ps1'));

      if (!await Directory(psProfileDir).exists()) {
        await Directory(psProfileDir).create(recursive: true);
      }

      targetProfile = psProfile;
      profileName = 'PowerShell Profile';
    } else {
      // Unix-like (MacOS / Linux)
      final zshrc = File(p.join(home, '.zshrc'));
      final bashrc = File(p.join(home, '.bashrc'));
      final bashProfile = File(p.join(home, '.bash_profile'));

      if (await zshrc.exists()) {
        targetProfile = zshrc;
      } else if (await bashrc.exists()) {
        targetProfile = bashrc;
      } else if (await bashProfile.exists()) {
        targetProfile = bashProfile;
      } else {
        // Fallback to .zshrc on Mac or .bashrc on Linux
        targetProfile = Platform.isMacOS ? zshrc : bashrc;
        kLog('  Creating new profile file: ${p.basename(targetProfile.path)}',
            type: LogType.info);
      }
      profileName = p.basename(targetProfile.path);
    }

    // Prompt for custom prefix
    stdout.write('  Enter your preferred shortcut prefix (default: dg): ');
    final input = stdin.readLineSync()?.trim();
    final String prefix = (input == null || input.isEmpty) ? 'dg' : input;

    String aliasesBlock = '';

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

    String content = '';
    if (await targetProfile.exists()) {
      content = await targetProfile.readAsString();
    }

    if (content.contains('# --- DIG CLI Custom Aliases ---')) {
      kLog('✅ DIG CLI aliases are already installed in $profileName',
          type: LogType.success);
      return;
    }

    await targetProfile.writeAsString(aliasesBlock, mode: FileMode.append);

    final painter = BoxPainter();
    print('');
    painter.drawHeader('ALIASES INSTALLED SUCCESSFULLY', width: 50);
    painter.drawRow('Profile', profileName, width: 50);
    painter.drawRow('Prefix', prefix, width: 50);
    painter.drawRow('Example', '${prefix}m (create-module)', width: 50);
    painter.drawRow('Example', '${prefix}p (create-project)', width: 50);
    painter.drawFooter(width: 50);

    if (Platform.isWindows) {
      kLog('\n🚀 Restart PowerShell or run ". \$PROFILE" to activate them.',
          type: LogType.info);
    } else {
      kLog('\n🚀 Run "source ~/$profileName" to activate them immediately.',
          type: LogType.info);
    }
  }
}
