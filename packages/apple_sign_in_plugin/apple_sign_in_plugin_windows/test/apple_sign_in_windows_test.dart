// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:apple_sign_in_plugin_windows/apple_sign_in_plugin_windows.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String _fakeIdToken(String sub, [String? email]) {
  String b64(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m)));
  final String header = b64({'alg': 'RS256', 'kid': 'testkey'});
  final payloadMap = <String, dynamic>{
    'sub': sub,
    'iss': 'https://appleid.apple.com',
    'aud': 'com.example.service',
  };
  if (email != null) {
    payloadMap['email'] = email;
  }
  final String payload = b64(payloadMap);
  return '$header.$payload.fakesig';
}

const AppleSignInDesktopConfig _kConfig = AppleSignInDesktopConfig(
  serviceId: 'com.example.service',
  redirectUri: 'https://api.example.com/auth/apple/callback',
  callbackScheme: 'com.example.app',
  callbackHost: 'apple-callback',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppleSignInWindowsImpl', () {
    late AppleSignInWindowsImpl impl;
    String? mockCallbackUrl;
    PlatformException? mockPlatformError;

    setUp(() {
      impl = AppleSignInWindowsImpl();
      impl.config = _kConfig;
      mockCallbackUrl = null;
      mockPlatformError = null;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(impl.channel, (MethodCall call) async {
        if (call.method == 'isAvailable') {
          return true;
        } else if (call.method == 'signIn') {
          if (mockPlatformError != null) {
            throw mockPlatformError!;
          }
          final arguments = call.arguments as Map<Object?, Object?>;
          return <String, dynamic>{
            'callbackUrl': mockCallbackUrl ??
                'com.example.app://apple-callback?code=auth123&state=${arguments['state']}&id_token=${_fakeIdToken("user123", "user@example.com")}',
            'expectedState': arguments['state'],
          };
        } else if (call.method == 'onNativeCallback') {
          return true;
        } else if (call.method == 'cancelSignIn') {
          return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(impl.channel, null);
    });

    test('isAvailable returns true', () async {
      expect(await impl.isAvailable(), isTrue);
    });

    test('signIn throws invalidConfiguration when not configured', () {
      final unconfigured = AppleSignInWindowsImpl();
      expect(
        () => unconfigured.signIn(scopes: {AppleAuthorizationScope.email}),
        throwsA(
          isA<AppleSignInException>().having(
            (e) => e.code,
            'code',
            AppleSignInErrorCode.invalidConfiguration,
          ),
        ),
      );
    });

    test('signIn throws invalidArguments for empty scope set', () {
      expect(
        () => impl.signIn(scopes: {}),
        throwsA(
          isA<AppleSignInException>().having(
            (e) => e.code,
            'code',
            AppleSignInErrorCode.invalidArguments,
          ),
        ),
      );
    });

    test('getCredentialState throws platformNotSupported', () {
      expect(
        () => impl.getCredentialState('user123'),
        throwsA(
          isA<AppleSignInException>().having(
            (e) => e.code,
            'code',
            AppleSignInErrorCode.platformNotSupported,
          ),
        ),
      );
    });

    test('onCredentialRevoked is an empty stream', () {
      expect(impl.onCredentialRevoked, emitsDone);
    });

    test('signIn maps successful native channel result correctly', () async {
      final String userJson = jsonEncode({
        'name': {'firstName': 'Alice', 'lastName': 'Smith'},
        'email': 'alice@example.com',
      });
      mockCallbackUrl =
          'com.example.app://apple-callback?code=authNative1&state=test-state&id_token=${_fakeIdToken("uNative1")}&user=${Uri.encodeComponent(userJson)}';

      final AppleCredential credential = await impl.signIn(
        scopes: {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
        state: 'test-state',
      );

      expect(credential.userIdentifier, 'uNative1');
      expect(credential.authorizationCode, 'authNative1');
      expect(credential.email, 'alice@example.com');
      expect(credential.name?.givenName, 'Alice');
      expect(credential.name?.familyName, 'Smith');
      expect(credential.realUserStatus, AppleRealUserStatus.unsupported);
    });

    test('signIn maps native platform exception correctly', () async {
      mockPlatformError = PlatformException(
        code: 'canceled',
        message: 'User cancelled authentication.',
      );

      expect(
        () => impl.signIn(
          scopes: {AppleAuthorizationScope.email},
          state: 'state1',
        ),
        throwsA(
          isA<AppleSignInException>().having(
            (e) => e.code,
            'code',
            AppleSignInErrorCode.canceled,
          ),
        ),
      );
    });

    test('handleCallback forwards URL to native channel', () async {
      final bool accepted = await impl.handleCallback(
        Uri.parse('com.example.app://apple-callback?code=123&state=abc'),
      );
      expect(accepted, isTrue);
    });

    test('cancel invokes native cancelSignIn', () async {
      await expectLater(impl.cancel(), completes);
    });
  });
}
