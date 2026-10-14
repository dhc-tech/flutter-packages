// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:dig_cli/src/utils/logger.dart';
import 'package:test/test.dart';

import 'helpers/capture.dart';

void main() {
  group('Logger Tests', () {
    test('kLog executes safely for all LogType variants', () {
      expect(() => kLog('Info message'), returnsNormally);
      expect(() => kLog('Success message', type: .success), returnsNormally);
      expect(() => kLog('Warning message', type: .warning), returnsNormally);
      expect(() => kLog('Error message', type: .error), returnsNormally);
    });

    test('kAnsiStdoutEnabled returns boolean without crashing', () {
      final bool isEnabled = kAnsiStdoutEnabled;
      expect(isEnabled, isA<bool>());
    });

    test('non-error types go through print, with the text preserved', () async {
      final lines = await capturePrints(() {
        kLog('info text');
        kLog('ok text', type: .success);
        kLog('warn text', type: .warning);
      });

      expect(lines, hasLength(3));
      expect(lines[0], contains('info text'));
      expect(lines[1], contains('ok text'));
      expect(lines[2], contains('warn text'));
    });

    test('plain output is uncolored when ANSI is disabled', () async {
      // ANSI is only enabled on a real terminal; guard so the test is also
      // valid when run interactively.
      if (kAnsiStdoutEnabled) {
        return;
      }
      final lines = await capturePrints(() => kLog('plain'));
      expect(lines, ['plain']);
    });

    test('error messages bypass print (they go to stderr)', () async {
      final lines = await capturePrints(() => kLog('boom', type: .error));
      expect(lines, isEmpty);
    });

    test('LogType exposes the four documented categories', () {
      expect(LogType.values.map((t) => t.name), [
        'info',
        'success',
        'warning',
        'error',
      ]);
    });
  });
}
