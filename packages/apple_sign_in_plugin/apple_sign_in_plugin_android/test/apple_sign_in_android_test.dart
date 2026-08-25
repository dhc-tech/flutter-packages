// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:apple_sign_in_plugin_android/apple_sign_in_plugin_android.dart';
import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member

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

const AppleSignInAndroidConfig _kConfig = AppleSignInAndroidConfig(
  serviceId: 'com.example.service',
  redirectUri: 'https://api.example.com/auth/apple/callback',
  callbackScheme: 'com.example.app',
  callbackHost: 'apple-callback',
);

class _Harness {
  _Harness() : impl = AppleSignInAndroidImpl() {
    impl.config = _kConfig;
  }

  final AppleSignInAndroidImpl impl;
  late final Completer<AppleCredential> completer;

  void prime(String state) {
    completer = Completer<AppleCredential>();
    impl.primeForTest(completer, state);
  }

  Future<Object?> callHandleAndAwait(Uri uri) async {
    impl.handleCallback(uri);
    try {
      return await completer.future.timeout(const Duration(seconds: 2));
    } on AppleSignInException catch (e) {
      return e;
    } on TimeoutException {
      return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppleSignInAndroidImpl', () {
    late AppleSignInAndroidImpl impl;

    setUp(() {
      impl = AppleSignInAndroidImpl();
      impl.config = _kConfig;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(impl.channel, (MethodCall call) async {
        if (call.method == 'isAvailable') {
          return true;
        } else if (call.method == 'launchAuthUrl') {
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
      final unconfigured = AppleSignInAndroidImpl();
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

    test('handleCallback rejects mismatched scheme', () async {
      final h = _Harness();
      h.prime('expected-state');
      final Object? result = await h.callHandleAndAwait(
        Uri.parse(
          'evil.scheme://apple-callback'
          '?code=auth123'
          '&state=expected-state',
        ),
      );
      expect(result, isA<AppleSignInException>());
      expect(
        (result! as AppleSignInException).message,
        contains('scheme mismatch'),
      );
    });

    test('handleCallback rejects mismatched host', () async {
      final h = _Harness();
      h.prime('expected-state');
      final Object? result = await h.callHandleAndAwait(
        Uri.parse(
          'com.example.app://wrong-host'
          '?code=auth123'
          '&state=expected-state',
        ),
      );
      expect(result, isA<AppleSignInException>());
      expect(
        (result! as AppleSignInException).message,
        contains('host mismatch'),
      );
    });

    test('handleCallback rejects mismatched state (CSRF protection)', () async {
      final h = _Harness();
      h.prime('expected-state');
      final Object? result = await h.callHandleAndAwait(
        Uri.parse(
          'com.example.app://apple-callback'
          '?code=auth123'
          '&id_token=${_fakeIdToken("u1")}'
          '&state=WRONG-STATE',
        ),
      );
      expect(result, isA<AppleSignInException>());
      expect(
        (result! as AppleSignInException).code,
        AppleSignInErrorCode.authorizationFailed,
      );
    });

    test('handleCallback maps user_cancelled_authorize to canceled', () async {
      final h = _Harness();
      h.prime('s1');
      final Object? result = await h.callHandleAndAwait(
        Uri.parse(
          'com.example.app://apple-callback'
          '?error=user_cancelled_authorize'
          '&state=s1',
        ),
      );
      expect(result, isA<AppleSignInException>());
      expect(
        (result! as AppleSignInException).code,
        AppleSignInErrorCode.canceled,
      );
    });

    test('handleCallback rejects missing code and id_token', () async {
      final h = _Harness();
      h.prime('s2');
      final Object? result = await h.callHandleAndAwait(
        Uri.parse('com.example.app://apple-callback?state=s2'),
      );
      expect(result, isA<AppleSignInException>());
      expect(
        (result! as AppleSignInException).code,
        AppleSignInErrorCode.invalidResponse,
      );
    });

    test('handleCallback maps credential fields correctly', () async {
      final h = _Harness();
      h.prime('good-state');

      final String userJson = jsonEncode({
        'name': {'firstName': 'Alice', 'lastName': 'Smith'},
        'email': 'alice@example.com',
      });

      final Object? result = await h.callHandleAndAwait(
        Uri.parse(
          'com.example.app://apple-callback'
          '?code=authW1'
          '&id_token=${_fakeIdToken("userW1")}'
          '&state=good-state'
          '&user=${Uri.encodeComponent(userJson)}',
        ),
      );

      expect(result, isA<AppleCredential>());
      final c = result! as AppleCredential;
      expect(c.userIdentifier, 'userW1');
      expect(c.authorizationCode, 'authW1');
      expect(c.email, 'alice@example.com');
      expect(c.name?.givenName, 'Alice');
      expect(c.realUserStatus, AppleRealUserStatus.unsupported);
    });

    test('handleCallback succeeds without user JSON', () async {
      final h = _Harness();
      h.prime('s3');
      final Object? result = await h.callHandleAndAwait(
        Uri.parse(
          'com.example.app://apple-callback'
          '?code=authW2'
          '&id_token=${_fakeIdToken("userW2")}'
          '&state=s3',
        ),
      );
      expect(result, isA<AppleCredential>());
      expect((result! as AppleCredential).email, isNull);
    });

    test('duplicate handleCallback is a no-op after completion', () async {
      final h = _Harness();
      h.prime('s4');
      final Uri uri = Uri.parse(
        'com.example.app://apple-callback'
        '?code=dup'
        '&id_token=${_fakeIdToken("uDup")}'
        '&state=s4',
      );
      h.impl.handleCallback(uri);
      await h.completer.future.timeout(const Duration(seconds: 2));
      expect(() => h.impl.handleCallback(uri), returnsNormally);
    });

    test('handleCallback tolerates malformed user JSON', () async {
      final h = _Harness();
      h.prime('s5');
      final Object? result = await h.callHandleAndAwait(
        Uri.parse(
          'com.example.app://apple-callback'
          '?code=authW3'
          '&id_token=${_fakeIdToken("userW3")}'
          '&state=s5'
          '&user=NOT_VALID_JSON',
        ),
      );
      expect(result, isA<AppleCredential>());
      expect((result! as AppleCredential).email, isNull);
    });
  });
}
