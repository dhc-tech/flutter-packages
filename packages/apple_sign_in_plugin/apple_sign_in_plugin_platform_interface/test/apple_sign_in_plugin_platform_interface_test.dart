import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppleCredential model', () {
    test('exposes every field as constructed', () {
      const credential = AppleCredential(
        userIdentifier: '001234.abcdef.5678',
        state: 'my-state',
        authorizedScopes: {AppleAuthorizationScope.email},
        realUserStatus: AppleRealUserStatus.likelyReal,
        identityToken: 'mock_identity_token',
        authorizationCode: 'mock_auth_code',
        email: 'john.doe@example.com',
        name: ApplePersonName(givenName: 'John', familyName: 'Doe'),
      );

      expect(credential.userIdentifier, '001234.abcdef.5678');
      expect(credential.email, 'john.doe@example.com');
      expect(credential.name?.givenName, 'John');
      expect(credential.name?.familyName, 'Doe');
      expect(credential.identityToken, 'mock_identity_token');
      expect(credential.authorizationCode, 'mock_auth_code');
      expect(credential.state, 'my-state');
      expect(credential.authorizedScopes, {AppleAuthorizationScope.email});
      expect(credential.realUserStatus, AppleRealUserStatus.likelyReal);
    });

    test('supports null email and name on subsequent sign-ins', () {
      const credential = AppleCredential(
        userIdentifier: '001234.abcdef.5678',
        state: '',
        authorizedScopes: <AppleAuthorizationScope>{},
        realUserStatus: AppleRealUserStatus.unknown,
      );

      expect(credential.email, isNull);
      expect(credential.name, isNull);
      expect(credential.identityToken, isNull);
      expect(credential.authorizationCode, isNull);
    });
  });

  group('ApplePersonName', () {
    test('isEmpty is true only when every component is null', () {
      expect(const ApplePersonName().isEmpty, isTrue);
      expect(const ApplePersonName(givenName: 'John').isEmpty, isFalse);
    });

    test('equality compares every component', () {
      expect(
        const ApplePersonName(givenName: 'John', familyName: 'Doe'),
        const ApplePersonName(givenName: 'John', familyName: 'Doe'),
      );
      expect(
        const ApplePersonName(givenName: 'John'),
        isNot(const ApplePersonName(givenName: 'Jane')),
      );
    });
  });

  group('AppleCredentialState.fromWireValue', () {
    test('maps native ASAuthorizationAppleIDProvider.CredentialState values', () {
      expect(
        AppleCredentialState.fromWireValue(0),
        AppleCredentialState.authorized,
      );
      expect(
        AppleCredentialState.fromWireValue(1),
        AppleCredentialState.revoked,
      );
      expect(
        AppleCredentialState.fromWireValue(2),
        AppleCredentialState.notFound,
      );
      expect(
        AppleCredentialState.fromWireValue(3),
        AppleCredentialState.transferred,
      );
    });
  });

  group('AppleRealUserStatus.fromWireValue', () {
    test('maps native ASUserDetectionStatus values', () {
      expect(
        AppleRealUserStatus.fromWireValue(null),
        AppleRealUserStatus.unsupported,
      );
      expect(
        AppleRealUserStatus.fromWireValue(0),
        AppleRealUserStatus.unsupported,
      );
      expect(
        AppleRealUserStatus.fromWireValue(1),
        AppleRealUserStatus.unknown,
      );
      expect(
        AppleRealUserStatus.fromWireValue(2),
        AppleRealUserStatus.likelyReal,
      );
    });
  });

  group('AppleSignInException', () {
    test('toString includes the error code and message', () {
      const exception = AppleSignInException(
        AppleSignInErrorCode.canceled,
        'The user canceled the authorization sheet.',
      );
      expect(exception.toString(), contains('canceled'));
      expect(
        exception.toString(),
        contains('The user canceled the authorization sheet.'),
      );
    });
  });

  group('MethodChannelAppleSignIn', () {
    late MethodChannelAppleSignIn platform;
    final log = <MethodCall>[];

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform = MethodChannelAppleSignIn();
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.channel, (
        MethodCall call,
      ) async {
        log.add(call);
        switch (call.method) {
          case 'isAvailable':
            return true;
          case 'signIn':
            return <String, Object?>{
              'userIdentifier': '001234.abcdef.5678',
              'email': 'john.doe@example.com',
              'givenName': 'John',
              'familyName': 'Doe',
              'identityToken': 'mock_identity_token',
              'authorizationCode': 'mock_auth_code',
              'state': 'my-state',
              'authorizedScopes': <String>['email', 'fullName'],
              'realUserStatus': 2,
            };
          case 'getCredentialState':
            return 0;
          default:
            throw MissingPluginException();
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('signIn parses the native response into an AppleCredential', () async {
      final AppleCredential credential = await platform.signIn(
        scopes: {
          AppleAuthorizationScope.email,
          AppleAuthorizationScope.fullName,
        },
      );

      expect(credential.userIdentifier, '001234.abcdef.5678');
      expect(credential.email, 'john.doe@example.com');
      expect(credential.name?.givenName, 'John');
      expect(credential.name?.familyName, 'Doe');
      expect(
        credential.authorizedScopes,
        {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
      );
      expect(credential.realUserStatus, AppleRealUserStatus.likelyReal);
      expect(log.single.method, 'signIn');
    });

    test('signIn rejects an empty scope set without calling the channel', () async {
      expect(
        () => platform.signIn(scopes: <AppleAuthorizationScope>{}),
        throwsA(
          isA<AppleSignInException>().having(
            (AppleSignInException e) => e.code,
            'code',
            AppleSignInErrorCode.invalidArguments,
          ),
        ),
      );
      expect(log, isEmpty);
    });

    test('getCredentialState maps the native integer', () async {
      final AppleCredentialState state = await platform.getCredentialState(
        '001234.abcdef.5678',
      );
      expect(state, AppleCredentialState.authorized);
      expect(log.single.method, 'getCredentialState');
    });

    test('isAvailable forwards the native result', () async {
      expect(await platform.isAvailable(), isTrue);
    });
  });
}
