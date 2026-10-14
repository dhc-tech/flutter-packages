// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:ansicolor/ansicolor.dart';
import 'package:args/command_runner.dart';
import 'package:dig_cli/src/commands/version_command.dart';
import 'package:dig_cli/src/version_helper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'helpers/capture.dart';

Future<String> runVersion(http.Response Function() respond) async {
  final List<String> lines = await capturePrints(
    () => http.runWithClient(
      () => VersionCommand().run(),
      () => MockClient((_) async => respond()),
    ),
  );
  return lines.join('\n');
}

http.Response latest(String v) => http.Response(
  jsonEncode({
    'latest': {'version': v},
  }),
  200,
);

void main() {
  setUp(() {
    ansiColorDisabled = true;
  });

  group('VersionCommand', () {
    test('has the expected name and description', () {
      final command = VersionCommand();
      expect(command.name, 'version');
      expect(command.description, isNotEmpty);
    });

    test('shows installed version and flags an available update', () async {
      final String out = await runVersion(() => latest('999.0.0'));

      expect(out, contains('DIG CLI TOOL'));
      expect(out, contains('Installed: v$kDigCliVersion'));
      expect(out, contains('Latest: v999.0.0'));
      expect(out, contains('Update available!'));
    });

    test('does not announce an update when already current', () async {
      final String out = await runVersion(() => latest(kDigCliVersion));

      expect(out, contains('Latest: v$kDigCliVersion'));
      expect(out, isNot(contains('Update available!')));
    });

    test('reports a failed check when pub.dev cannot be reached', () async {
      final String out = await runVersion(() => http.Response('', 500));

      expect(out, contains('Latest: (Check failed)'));
      expect(out, isNot(contains('Update available!')));
    });

    test('renders a box with consistent border widths', () async {
      final String out = await runVersion(() => latest(kDigCliVersion));
      final borders = out
          .split('\n')
          .where((l) => l.startsWith('╔') || l.startsWith('╚'))
          .toList();

      expect(borders, hasLength(2));
      expect(borders.every((l) => l.length == 50), isTrue);
    });

    test('runs through CommandRunner and handleShowVersionCommand', () async {
      final runner = CommandRunner<dynamic>('dg', 'test')
        ..addCommand(VersionCommand());
      final List<String> lines = await capturePrints(
        () => http.runWithClient(() async {
          await runner.run(['version']);
          await handleShowVersionCommand();
        }, () => MockClient((_) async => http.Response('', 500))),
      );

      expect(
        lines.where((l) => l.contains('Installed: v$kDigCliVersion')),
        hasLength(2),
      );
    });
  });
}
