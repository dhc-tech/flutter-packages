// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:dig_cli/src/utils/logger.dart';
import 'package:test/test.dart';

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
  });
}
