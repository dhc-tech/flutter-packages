// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

String _createTestJwt(Map<String, dynamic> payload) {
  String toBase64Url(Map<String, dynamic> jsonMap) {
    return base64Url
        .encode(utf8.encode(jsonEncode(jsonMap)))
        .replaceAll('=', '');
  }

  final String h = toBase64Url({'alg': 'HS256', 'typ': 'JWT'});
  final String p = toBase64Url(payload);
  final String s = base64Url.encode(utf8.encode('sig')).replaceAll('=', '');
  return '$h.$p.$s';
}

const _capabilities = AppleSignInCapabilities(
  platformName: 'iOS',
  isSupported: true,
  nativeCredentialState: true,
  revocationEvents: true,
  browserAuthorization: false,
  webAppleJs: false,
  wasmWeb: false,
  backendRevocation: false,
  supportedScopes: {
    AppleAuthorizationScope.email,
    AppleAuthorizationScope.fullName,
  },
);

void main() {
  group('AppleAuthSession.fromCredential email fallback', () {
    test(
        'uses credential.email directly when present, without decoding the token',
        () {
      final credential = AppleCredential(
        userIdentifier: 'user-1',
        email: 'direct@example.com',
        state: '',
        authorizedScopes: const {AppleAuthorizationScope.email},
        realUserStatus: AppleRealUserStatus.unknown,
        identityToken: _createTestJwt({'email': 'from-token@example.com'}),
      );

      final session = AppleAuthSession.fromCredential(
        credential: credential,
        capabilities: _capabilities,
      );

      // The direct field wins even though the token has a different value.
      expect(session.identity.email, 'direct@example.com');
      expect(session.metadata.receivedEmail, isTrue);
    });

    test(
        'falls back to decoding the email claim from identityToken when credential.email is null',
        () {
      final credential = AppleCredential(
        userIdentifier: 'user-2',
        state: '',
        authorizedScopes: const {AppleAuthorizationScope.email},
        realUserStatus: AppleRealUserStatus.unknown,
        identityToken: _createTestJwt({'email': 'from-token@example.com'}),
      );

      final session = AppleAuthSession.fromCredential(
        credential: credential,
        capabilities: _capabilities,
      );

      expect(session.identity.email, 'from-token@example.com');
      expect(session.metadata.receivedEmail, isTrue);
    });

    test('leaves email null when neither the credential nor the token has one',
        () {
      final credential = AppleCredential(
        userIdentifier: 'user-3',
        state: '',
        authorizedScopes: const <AppleAuthorizationScope>{},
        realUserStatus: AppleRealUserStatus.unknown,
        identityToken: _createTestJwt({'sub': 'user-3'}),
      );

      final session = AppleAuthSession.fromCredential(
        credential: credential,
        capabilities: _capabilities,
      );

      expect(session.identity.email, isNull);
      expect(session.metadata.receivedEmail, isFalse);
    });

    test('never throws when identityToken is malformed', () {
      const credential = AppleCredential(
        userIdentifier: 'user-4',
        state: '',
        authorizedScopes: <AppleAuthorizationScope>{},
        realUserStatus: AppleRealUserStatus.unknown,
        identityToken: 'not-a-real-jwt',
      );

      expect(
        () => AppleAuthSession.fromCredential(
          credential: credential,
          capabilities: _capabilities,
        ),
        returnsNormally,
      );
    });

    test('never fabricates a name — no fallback exists for it', () {
      final credential = AppleCredential(
        userIdentifier: 'user-5',
        state: '',
        authorizedScopes: const <AppleAuthorizationScope>{},
        realUserStatus: AppleRealUserStatus.unknown,
        // Some providers put a "name" string claim in the token, but Apple's
        // identity token never does — and even if a claim were present, the
        // plugin must not synthesize an ApplePersonName from it.
        identityToken: _createTestJwt({'name': 'Someone Entirely Different'}),
      );

      final session = AppleAuthSession.fromCredential(
        credential: credential,
        capabilities: _capabilities,
      );

      expect(session.identity.name, isNull);
      expect(session.metadata.receivedName, isFalse);
    });
  });
}
