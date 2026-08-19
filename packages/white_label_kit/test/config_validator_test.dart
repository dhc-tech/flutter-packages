import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  group('tenantId', () {
    test('accepts a valid lowercase id', () {
      expect(ConfigValidator.tenantId('acme'), isA<Valid>());
    });
    test('rejects uppercase/leading digit', () {
      expect(ConfigValidator.tenantId('Acme'), isA<Invalid>());
      expect(ConfigValidator.tenantId('1acme'), isA<Invalid>());
    });
    test('rejects the Gradle-reserved "test" prefix', () {
      expect(ConfigValidator.tenantId('testacme'), isA<Invalid>());
    });
  });

  group('androidApplicationId', () {
    test('accepts reverse-DNS form', () {
      expect(
        ConfigValidator.androidApplicationId('com.example.acme'),
        isA<Valid>(),
      );
    });
    test('rejects a display-name-shaped value', () {
      final ValidationResult result = ConfigValidator.androidApplicationId('Acme App');
      expect(result, isA<Invalid>());
      expect((result as Invalid).message, contains('com.company.appname'));
    });
    test('rejects a single segment', () {
      expect(ConfigValidator.androidApplicationId('acme'), isA<Invalid>());
    });
  });

  group('iosBundleId', () {
    test('accepts hyphens (unlike Android)', () {
      expect(ConfigValidator.iosBundleId('com.example.acme-app'), isA<Valid>());
    });
    test('rejects underscores (iOS does not allow them)', () {
      expect(
        ConfigValidator.iosBundleId('com.example.acme_app'),
        isA<Invalid>(),
      );
    });
  });

  group('colorHex', () {
    test('accepts #RRGGBB and #AARRGGBB', () {
      expect(ConfigValidator.colorHex('#2563EB'), isA<Valid>());
      expect(ConfigValidator.colorHex('#FF2563EB'), isA<Valid>());
    });
    test('rejects missing #', () {
      expect(ConfigValidator.colorHex('2563EB'), isA<Invalid>());
    });
  });

  group('url', () {
    test('accepts absolute https URL', () {
      expect(ConfigValidator.url('https://api.acme.com'), isA<Valid>());
    });
    test('rejects a bare host', () {
      expect(ConfigValidator.url('api.acme.com'), isA<Invalid>());
    });
  });

  group('assetPath', () {
    test('rejects absolute paths', () {
      expect(
        ConfigValidator.assetPath('/etc/passwd', tenantId: 'acme'),
        isA<Invalid>(),
      );
    });
    test('rejects .. traversal', () {
      expect(
        ConfigValidator.assetPath(
          'tenants/acme/../beta/logo.png',
          tenantId: 'acme',
        ),
        isA<Invalid>(),
      );
    });
    test('rejects pointing at a different tenant', () {
      expect(
        ConfigValidator.assetPath(
          'tenants/beta/assets/logo.png',
          tenantId: 'acme',
        ),
        isA<Invalid>(),
      );
    });
    test("accepts a path under the tenant's own directory", () {
      expect(
        ConfigValidator.assetPath(
          'tenants/acme/assets/logo.png',
          tenantId: 'acme',
        ),
        isA<Valid>(),
      );
    });
  });
}
