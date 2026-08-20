// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:apple_sign_in_plugin_web/apple_sign_in_plugin_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppleSignInWebImpl', () {
    late AppleSignInWebImpl impl;

    setUp(() {
      impl = AppleSignInWebImpl();
    });

    test('isAvailable returns true on web', () async {
      expect(await impl.isAvailable(), isTrue);
    });

    test('signIn throws invalidConfiguration when not configured', () {
      expect(
        () => impl.signIn(scopes: {AppleAuthorizationScope.email}),
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
      impl.config = const AppleSignInWebConfig(
        serviceId: 'com.example.service',
        redirectUri: 'https://api.example.com/auth/apple/callback',
      );
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

    test('AppleSignInWebConfig.usePopup defaults to true', () {
      const config = AppleSignInWebConfig(
        serviceId: 'com.example',
        redirectUri: 'https://example.com/callback',
      );
      expect(config.usePopup, isTrue);
    });

    test('AppleSignInWebConfig.usePopup can be set to false', () {
      const config = AppleSignInWebConfig(
        serviceId: 'com.example',
        redirectUri: 'https://example.com/callback',
        usePopup: false,
      );
      expect(config.usePopup, isFalse);
    });

    test('getCredentialState throws platformNotSupported on web', () {
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

    test('onCredentialRevoked is an empty stream on web', () {
      expect(impl.onCredentialRevoked, emitsDone);
    });

    test('config can be updated multiple times', () {
      impl.config = const AppleSignInWebConfig(
        serviceId: 'com.example.v1',
        redirectUri: 'https://v1.example.com/callback',
      );
      impl.config = const AppleSignInWebConfig(
        serviceId: 'com.example.v2',
        redirectUri: 'https://v2.example.com/callback',
      );
      expect(impl.config?.serviceId, 'com.example.v2');
    });
  });
}
