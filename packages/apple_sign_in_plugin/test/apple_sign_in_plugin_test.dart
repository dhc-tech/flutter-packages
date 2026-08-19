import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppleSignInResult Model Tests', () {
    test('AppleSignInResult instantiates and exposes all fields', () {
      final result = AppleSignInResult(
        idToken: 'mock_id_token',
        accessToken: 'mock_access_token',
        refreshToken: 'mock_refresh_token',
        authorizationCode: 'mock_auth_code',
        userIdentifier: '001234.abcdef.5678',
        givenName: 'John',
        familyName: 'Doe',
        email: 'john.doe@example.com',
      );

      expect(result.idToken, equals('mock_id_token'));
      expect(result.accessToken, equals('mock_access_token'));
      expect(result.refreshToken, equals('mock_refresh_token'));
      expect(result.authorizationCode, equals('mock_auth_code'));
      expect(result.userIdentifier, equals('001234.abcdef.5678'));
      expect(result.givenName, equals('John'));
      expect(result.familyName, equals('Doe'));
      expect(result.email, equals('john.doe@example.com'));
    });

    test('AppleSignInResult supports nullable email and names', () {
      final result = AppleSignInResult(
        idToken: 'mock_id_token',
        accessToken: 'mock_access_token',
        refreshToken: 'mock_refresh_token',
        authorizationCode: 'mock_auth_code',
        userIdentifier: '001234.abcdef.5678',
      );

      expect(result.email, isNull);
      expect(result.givenName, isNull);
      expect(result.familyName, isNull);
    });
  });

  group('AppleSignInPlugin Initialization Tests', () {
    test('initialize throws ArgumentError when parameters are empty', () async {
      expect(
        () => AppleSignInPlugin.initialize(
          pemKeyPath: '',
          keyId: 'ABC1234567',
          teamId: 'XYZ1234567',
          bundleId: 'com.example.app',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => AppleSignInPlugin.initialize(
          pemKeyPath: 'assets/apple.pem',
          keyId: '',
          teamId: 'XYZ1234567',
          bundleId: 'com.example.app',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'initialize throws ArgumentError when placeholder credentials are used',
      () async {
        expect(
          () => AppleSignInPlugin.initialize(
            pemKeyPath: 'assets/apple.pem',
            keyId: 'YOUR_KEY_ID',
            teamId: 'XYZ1234567',
            bundleId: 'com.example.app',
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => AppleSignInPlugin.initialize(
            pemKeyPath: 'assets/apple.pem',
            keyId: 'ABC1234567',
            teamId: 'YOUR_TEAM_ID',
            bundleId: 'com.example.app',
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => AppleSignInPlugin.initialize(
            pemKeyPath: 'assets/apple.pem',
            keyId: 'ABC1234567',
            teamId: 'XYZ1234567',
            bundleId: 'YOUR_BUNDLE_ID',
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });
}
