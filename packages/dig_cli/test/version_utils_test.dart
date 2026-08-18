import 'package:dig_cli/src/utils/version_utils.dart';
import 'package:test/test.dart';

void main() {
  group('VersionUtils Tests', () {
    test('isNewer returns true when latest is greater than current', () {
      expect(VersionUtils.isNewer('1.8.1', '1.8.0'), isTrue);
      expect(VersionUtils.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(VersionUtils.isNewer('1.8.0-beta.2', '1.8.0-beta.1'), isTrue);
    });

    test('isNewer returns false when latest is equal or less than current', () {
      expect(VersionUtils.isNewer('1.8.0', '1.8.0'), isFalse);
      expect(VersionUtils.isNewer('1.7.9', '1.8.0'), isFalse);
      expect(VersionUtils.isNewer('1.0.0', '2.0.0'), isFalse);
    });

    test(
      'isNewer gracefully handles invalid semver strings without crashing',
      () {
        expect(VersionUtils.isNewer('invalid', '1.8.0'), isFalse);
        expect(VersionUtils.isNewer('1.8.0', 'invalid'), isFalse);
        expect(VersionUtils.isNewer('', ''), isFalse);
      },
    );
  });
}
