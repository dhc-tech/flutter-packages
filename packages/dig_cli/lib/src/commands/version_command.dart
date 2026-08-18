import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:args/command_runner.dart';

import '../utils/version_utils.dart';
import '../version_helper.dart';

class VersionCommand extends Command {
  @override
  final name = 'version';
  @override
  final description =
      'Shows the current version and information about DIG CLI.';

  @override
  Future<void> run() async {
    const currentVersion = kDigCliVersion;
    final String? latestVersion = await VersionUtils.getLatestStableVersion();

    final borderPen = AnsiPen()..blue();
    final titlePen = AnsiPen()..white(bold: true);
    final textPen = AnsiPen()..cyan();
    final versionPen = AnsiPen()..green();
    final warningPen = AnsiPen()..yellow();

    final title = 'DIG CLI TOOL';
    final author = 'Made with ❤️ by Digvijaysinh Chauhan';
    final totalWidth = 50; // Increased width for version info

    final topBorder = '╔${'═' * (totalWidth - 2)}╗';
    final bottomBorder = '╚${'═' * (totalWidth - 2)}╝';

    print('');
    print(borderPen(topBorder));

    // Title
    print(borderPen('║') +
        ' ' * ((totalWidth - title.length - 2) / 2).floor() +
        titlePen(title) +
        ' ' * ((totalWidth - title.length - 2) / 2).ceil() +
        borderPen('║'));

    print(borderPen('║') + ' ' * (totalWidth - 2) + borderPen('║'));

    // Version Info
    final installedText = 'Installed: v$currentVersion';
    print(borderPen('║') +
        ' ' * ((totalWidth - installedText.length - 2) / 2).floor() +
        textPen(installedText) +
        ' ' * ((totalWidth - installedText.length - 2) / 2).ceil() +
        borderPen('║'));

    // Executable Path (Local verification)
    final scriptPath = Platform.script.toFilePath();
    // Truncate if too long
    final displayPath = scriptPath.length > (totalWidth - 4)
        ? '...${scriptPath.substring(scriptPath.length - (totalWidth - 7))}'
        : scriptPath;

    print(borderPen('║') +
        ' ' * ((totalWidth - displayPath.length - 2) / 2).floor() +
        (AnsiPen()..gray(level: 0.5))(displayPath) +
        ' ' * ((totalWidth - displayPath.length - 2) / 2).ceil() +
        borderPen('║'));

    if (latestVersion != null) {
      final latestText = 'Latest: v$latestVersion';
      print(borderPen('║') +
          ' ' * ((totalWidth - latestText.length - 2) / 2).floor() +
          (VersionUtils.isNewer(latestVersion, currentVersion)
              ? warningPen(latestText)
              : versionPen(latestText)) +
          ' ' * ((totalWidth - latestText.length - 2) / 2).ceil() +
          borderPen('║'));

      if (VersionUtils.isNewer(latestVersion, currentVersion)) {
        print(borderPen('║') + ' ' * (totalWidth - 2) + borderPen('║'));
        final updateMsg = 'Update available!';
        print(borderPen('║') +
            ' ' * ((totalWidth - updateMsg.length - 2) / 2).floor() +
            warningPen(updateMsg) +
            ' ' * ((totalWidth - updateMsg.length - 2) / 2).ceil() +
            borderPen('║'));
      }
    } else {
      final checkingText = 'Latest: (Check failed)';
      print(borderPen('║') +
          ' ' * ((totalWidth - checkingText.length - 2) / 2).floor() +
          warningPen(checkingText) +
          ' ' * ((totalWidth - checkingText.length - 2) / 2).ceil() +
          borderPen('║'));
    }

    print(borderPen('║') + ' ' * (totalWidth - 2) + borderPen('║'));

    // Author
    final authorPen = AnsiPen()..yellow(bold: true);
    print(borderPen('║') +
        ' ' * ((totalWidth - author.length - 2) / 2).floor() +
        authorPen(author) +
        ' ' * ((totalWidth - author.length - 2) / 2).ceil() +
        borderPen('║'));
    print(borderPen(bottomBorder));
    print('');
  }
}

// For backward compatibility while refactoring others
Future<void> handleShowVersionCommand() async {
  await VersionCommand().run();
}
