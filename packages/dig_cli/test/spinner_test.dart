// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:ansicolor/ansicolor.dart';
import 'package:dig_cli/src/utils/spinner.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    ansiColorDisabled = true;
  });

  group('runWithSpinner', () {
    test('returns the value produced by the wrapped future', () async {
      final int result = await runWithSpinner('Working', () async => 42);
      expect(result, 42);
    });

    test('supports nullable and void results', () async {
      expect(
        await runWithSpinner<String?>('Working', () async => null),
        isNull,
      );
      await runWithSpinner<void>('Working', () async {});
    });

    test('rethrows the original error unchanged', () async {
      final error = StateError('nope');
      await expectLater(
        runWithSpinner<int>('Working', () async => throw error),
        throwsA(same(error)),
      );
    });

    test('rethrows synchronous-style exceptions with their type', () async {
      await expectLater(
        runWithSpinner<void>('Working', () async {
          throw const FormatException('bad input');
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'bad input',
          ),
        ),
      );
    });
  });
}
