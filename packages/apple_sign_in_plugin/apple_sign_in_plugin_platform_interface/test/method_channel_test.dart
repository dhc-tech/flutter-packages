// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePlatform extends AppleSignInPlatform {}

class _ImplementsPlatform implements AppleSignInPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Matcher _exception(AppleSignInErrorCode code) =>
    throwsA(isA<AppleSignInException>().having((AppleSignInException e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppleSignInPlatform', () {
    final AppleSignInPlatform original = AppleSignInPlatform.instance;

    tearDown(() => AppleSignInPlatform.instance = original);

    test('default instance is the method channel implementation', () {
      expect(original, isA<MethodChannelAppleSignIn>());
    });

    test('base methods throw UnimplementedError', () {
      final p = _FakePlatform();
      expect(p.isAvailable, throwsUnimplementedError);
      expect(() => p.signIn(scopes: {AppleAuthorizationScope.email}), throwsUnimplementedError);
      expect(() => p.getCredentialState('u'), throwsUnimplementedError);
      expect(() => p.onCredentialRevoked, throwsUnimplementedError);
    });

    test('instance setter accepts subclasses', () {
      final fake = _FakePlatform();
      AppleSignInPlatform.instance = fake;
      expect(AppleSignInPlatform.instance, same(fake));
    });

    test('instance setter rejects implementers that skip the token', () {
      expect(() => AppleSignInPlatform.instance = _ImplementsPlatform(), throwsAssertionError);
    });

    test('PlatformInterface.verify is used by the setter', () {
      expect(() => PlatformInterface.verify(_ImplementsPlatform(), Object()), throwsAssertionError);
    });
  });

  group('MethodChannelAppleSignIn', () {
    late MethodChannelAppleSignIn platform;
    late List<MethodCall> log;
    Object? Function(MethodCall call) handler = (MethodCall call) => null;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      platform = MethodChannelAppleSignIn();
      log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        platform.channel,
        (MethodCall call) async {
          log.add(call);
          return handler(call);
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        platform.channel,
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    group('unsupported platforms', () {
      setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

      test('isAvailable is false without calling native', () async {
        expect(await platform.isAvailable(), isFalse);
        expect(log, isEmpty);
      });

      test('signIn and getCredentialState throw platformNotSupported', () {
        expect(
          () => platform.signIn(scopes: {AppleAuthorizationScope.email}),
          _exception(AppleSignInErrorCode.platformNotSupported),
        );
        expect(
          () => platform.getCredentialState('u'),
          _exception(AppleSignInErrorCode.platformNotSupported),
        );
      });

      test('onCredentialRevoked is an empty stream', () async {
        expect(await platform.onCredentialRevoked.toList(), isEmpty);
      });
    });

    test('macOS counts as supported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      handler = (MethodCall call) => true;
      expect(await platform.isAvailable(), isTrue);
    });

    test('isAvailable treats a null native result as false', () async {
      handler = (MethodCall call) => null;
      expect(await platform.isAvailable(), isFalse);
    });

    group('signIn', () {
      test('sends scope names, nonce and state', () async {
        handler = (MethodCall call) => <String, Object?>{'userIdentifier': 'u'};
        await platform.signIn(scopes: {AppleAuthorizationScope.fullName}, nonce: 'n', state: 's');
        expect(log.single.arguments, <String, Object?>{
          'scopes': <String>['fullName'],
          'nonce': 'n',
          'state': 's',
        });
      });

      test('applies defaults for a minimal response', () async {
        handler = (MethodCall call) => <String, Object?>{'userIdentifier': 'u'};
        final AppleCredential c = await platform.signIn(scopes: {AppleAuthorizationScope.email});
        expect(c.userIdentifier, 'u');
        expect(c.name, isNull);
        expect(c.email, isNull);
        expect(c.state, '');
        expect(c.authorizedScopes, isEmpty);
        expect(c.realUserStatus, AppleRealUserStatus.unsupported);
      });

      test('maps all name parts and unknown scopes fall back to email', () async {
        handler = (MethodCall call) => <String, Object?>{
          'userIdentifier': 'u',
          'namePrefix': 'Dr',
          'givenName': 'G',
          'middleName': 'M',
          'familyName': 'F',
          'nameSuffix': 'Jr',
          'nickname': 'N',
          'authorizedScopes': <Object?>['bogus'],
          'realUserStatus': 1,
        };
        final AppleCredential c = await platform.signIn(scopes: {AppleAuthorizationScope.email});
        expect(
          c.name,
          const ApplePersonName(
            namePrefix: 'Dr',
            givenName: 'G',
            middleName: 'M',
            familyName: 'F',
            nameSuffix: 'Jr',
            nickname: 'N',
          ),
        );
        expect(c.authorizedScopes, {AppleAuthorizationScope.email});
        expect(c.realUserStatus, AppleRealUserStatus.unknown);
      });

      test('null response is invalidResponse', () {
        handler = (MethodCall call) => null;
        expect(
          () => platform.signIn(scopes: {AppleAuthorizationScope.email}),
          _exception(AppleSignInErrorCode.invalidResponse),
        );
      });

      test('response without userIdentifier is invalidResponse', () {
        handler = (MethodCall call) => <String, Object?>{'email': 'e'};
        expect(
          () => platform.signIn(scopes: {AppleAuthorizationScope.email}),
          _exception(AppleSignInErrorCode.invalidResponse),
        );
      });

      test('maps PlatformException codes to AppleSignInErrorCode', () async {
        const expected = <String, AppleSignInErrorCode>{
          'canceled': AppleSignInErrorCode.canceled,
          'already_in_progress': AppleSignInErrorCode.alreadyInProgress,
          'not_available': AppleSignInErrorCode.notAvailable,
          'invalid_configuration': AppleSignInErrorCode.invalidConfiguration,
          'authorization_failed': AppleSignInErrorCode.authorizationFailed,
          'invalid_response': AppleSignInErrorCode.invalidResponse,
          'network_failed': AppleSignInErrorCode.networkFailed,
          'something_else': AppleSignInErrorCode.unknown,
        };
        for (final MapEntry<String, AppleSignInErrorCode> entry in expected.entries) {
          handler = (MethodCall call) =>
              throw PlatformException(code: entry.key, message: 'msg', details: 'd');
          await expectLater(
            platform.signIn(scopes: {AppleAuthorizationScope.email}),
            throwsA(
              isA<AppleSignInException>()
                  .having((AppleSignInException e) => e.code, 'code', entry.value)
                  .having((AppleSignInException e) => e.message, 'message', 'msg')
                  .having((AppleSignInException e) => e.details, 'details', 'd'),
            ),
          );
        }
      });

      test('PlatformException without message gets a default message', () {
        handler = (MethodCall call) => throw PlatformException(code: 'canceled');
        expect(
          () => platform.signIn(scopes: {AppleAuthorizationScope.email}),
          throwsA(
            isA<AppleSignInException>().having(
              (AppleSignInException e) => e.message,
              'message',
              'Apple Sign-In failed (canceled).',
            ),
          ),
        );
      });
    });

    group('getCredentialState', () {
      test('sends the user identifier and maps the result', () async {
        handler = (MethodCall call) => 1;
        expect(await platform.getCredentialState('abc'), AppleCredentialState.revoked);
        expect(log.single.arguments, <String, Object?>{'userIdentifier': 'abc'});
      });

      test('null result is credentialStateFailed', () {
        handler = (MethodCall call) => null;
        expect(
          () => platform.getCredentialState('abc'),
          _exception(AppleSignInErrorCode.credentialStateFailed),
        );
      });

      test('PlatformException becomes credentialStateFailed', () {
        handler = (MethodCall call) => throw PlatformException(code: 'x', details: 'dd');
        expect(
          () => platform.getCredentialState('abc'),
          throwsA(
            isA<AppleSignInException>()
                .having(
                  (AppleSignInException e) => e.code,
                  'code',
                  AppleSignInErrorCode.credentialStateFailed,
                )
                .having(
                  (AppleSignInException e) => e.message,
                  'message',
                  'getCredentialState() failed.',
                )
                .having((AppleSignInException e) => e.details, 'details', 'dd'),
          ),
        );
      });
    });

    test('onCredentialRevoked is cached and emits for each native event', () async {
      final eventMethods = MethodChannel(platform.revocationChannel.name);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        eventMethods,
        (MethodCall call) async => null,
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(eventMethods, null),
      );
      final Stream<void> first = platform.onCredentialRevoked;
      expect(platform.onCredentialRevoked, same(first));

      final Future<List<void>> events = first.take(1).toList();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        platform.revocationChannel.name,
        const StandardMethodCodec().encodeSuccessEnvelope('revoked'),
        (ByteData? data) {},
      );
      expect(await events, hasLength(1));
    });
  });
}
