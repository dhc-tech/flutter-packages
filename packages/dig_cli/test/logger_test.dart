import 'package:dig_cli/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('Logger Tests', () {
    test('kLog executes safely for all LogType variants', () {
      expect(() => kLog('Info message', type: LogType.info), returnsNormally);
      expect(
        () => kLog('Success message', type: LogType.success),
        returnsNormally,
      );
      expect(
        () => kLog('Warning message', type: LogType.warning),
        returnsNormally,
      );
      expect(() => kLog('Error message', type: LogType.error), returnsNormally);
    });

    test('kAnsiStdoutEnabled returns boolean without crashing', () {
      final isEnabled = kAnsiStdoutEnabled;
      expect(isEnabled, isA<bool>());
    });
  });
}
