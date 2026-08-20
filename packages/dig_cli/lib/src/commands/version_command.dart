// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:args/command_runner.dart';

import '../utils/version_utils.dart';
import '../version_helper.dart';

/// Shows the current DIG CLI version and update status.
class VersionCommand extends Command<dynamic> {
  @override
  final name = 'version';
  @override
  final description =
      'Shows the current version and information about DIG CLI.';

  @override
  Future<void> run() async {
    const String currentVersion = kDigCliVersion;
    final String? latestVersion = await VersionUtils.getLatestStableVersion();

    final borderPen = AnsiPen()..blue();
    final titlePen = AnsiPen()..white(bold: true);
    final textPen = AnsiPen()..cyan();
    final versionPen = AnsiPen()..green();
    final warningPen = AnsiPen()..yellow();

    const title = 'DIG CLI TOOL';
    const author = 'Made with ❤️ by Digvijaysinh Chauhan';
    const totalWidth = 50; // Increased width for version info

    final topBorder = '╔${'═' * (totalWidth - 2)}╗';
    final bottomBorder = '╚${'═' * (totalWidth - 2)}╝';

    // Structured box-drawing output printed directly to stdout by design.
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print(borderPen(topBorder));

    // Title
    // ignore: avoid_print
    print(
      borderPen('║') +
          ' ' * ((totalWidth - title.length - 2) / 2).floor() +
          titlePen(title) +
          ' ' * ((totalWidth - title.length - 2) / 2).ceil() +
          borderPen('║'),
    );

    // ignore: avoid_print
    print(borderPen('║') + ' ' * (totalWidth - 2) + borderPen('║'));

    // Version Info
    const installedText = 'Installed: v$currentVersion';
    // ignore: avoid_print
    print(
      borderPen('║') +
          ' ' * ((totalWidth - installedText.length - 2) / 2).floor() +
          textPen(installedText) +
          ' ' * ((totalWidth - installedText.length - 2) / 2).ceil() +
          borderPen('║'),
    );

    // Executable Path (Local verification)
    final String scriptPath = Platform.script.toFilePath();
    // Truncate if too long
    final displayPath = scriptPath.length > (totalWidth - 4)
        ? '...${scriptPath.substring(scriptPath.length - (totalWidth - 7))}'
        : scriptPath;

    // ignore: avoid_print
    print(
      borderPen('║') +
          ' ' * ((totalWidth - displayPath.length - 2) / 2).floor() +
          (AnsiPen()..gray(level: 0.5))(displayPath) +
          ' ' * ((totalWidth - displayPath.length - 2) / 2).ceil() +
          borderPen('║'),
    );

    if (latestVersion != null) {
      final latestText = 'Latest: v$latestVersion';
      // ignore: avoid_print
      print(
        borderPen('║') +
            ' ' * ((totalWidth - latestText.length - 2) / 2).floor() +
            (VersionUtils.isNewer(latestVersion, currentVersion)
                ? warningPen(latestText)
                : versionPen(latestText)) +
            ' ' * ((totalWidth - latestText.length - 2) / 2).ceil() +
            borderPen('║'),
      );

      if (VersionUtils.isNewer(latestVersion, currentVersion)) {
        // ignore: avoid_print
        print(borderPen('║') + ' ' * (totalWidth - 2) + borderPen('║'));
        const updateMsg = 'Update available!';
        // ignore: avoid_print
        print(
          borderPen('║') +
              ' ' * ((totalWidth - updateMsg.length - 2) / 2).floor() +
              warningPen(updateMsg) +
              ' ' * ((totalWidth - updateMsg.length - 2) / 2).ceil() +
              borderPen('║'),
        );
      }
    } else {
      const checkingText = 'Latest: (Check failed)';
      // ignore: avoid_print
      print(
        borderPen('║') +
            ' ' * ((totalWidth - checkingText.length - 2) / 2).floor() +
            warningPen(checkingText) +
            ' ' * ((totalWidth - checkingText.length - 2) / 2).ceil() +
            borderPen('║'),
      );
    }

    // ignore: avoid_print
    print(borderPen('║') + ' ' * (totalWidth - 2) + borderPen('║'));

    // Author
    final authorPen = AnsiPen()..yellow(bold: true);
    // ignore: avoid_print
    print(
      borderPen('║') +
          ' ' * ((totalWidth - author.length - 2) / 2).floor() +
          authorPen(author) +
          ' ' * ((totalWidth - author.length - 2) / 2).ceil() +
          borderPen('║'),
    );
    // ignore: avoid_print
    print(borderPen(bottomBorder));
    // ignore: avoid_print
    print('');
  }
}

/// For backward compatibility while refactoring others.
Future<void> handleShowVersionCommand() async {
  await VersionCommand().run();
}
