// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

const _capabilities = AppleSignInCapabilities(
  platformName: 'iOS',
  isSupported: true,
  nativeCredentialState: true,
  revocationEvents: true,
  browserAuthorization: false,
  webAppleJs: false,
  wasmWeb: false,
  backendRevocation: false,
  supportedScopes: {AppleAuthorizationScope.email},
);

void main() {
  group('AppleAuthIdentity.formattedName', () {
    test('is null without a name or with an empty name', () {
      expect(const AppleAuthIdentity(userIdentifier: 'u').formattedName, isNull);
      expect(
        const AppleAuthIdentity(userIdentifier: 'u', name: ApplePersonName()).formattedName,
        isNull,
      );
    });

    test('joins given and family names, skipping missing or blank parts', () {
      AppleAuthIdentity identity(ApplePersonName n) =>
          AppleAuthIdentity(userIdentifier: 'u', name: n);
      expect(
        identity(const ApplePersonName(givenName: 'Ada', familyName: 'Lovelace')).formattedName,
        'Ada Lovelace',
      );
      expect(identity(const ApplePersonName(givenName: 'Ada')).formattedName, 'Ada');
      expect(identity(const ApplePersonName(familyName: 'Lovelace')).formattedName, 'Lovelace');
      expect(identity(const ApplePersonName(givenName: '', familyName: '')).formattedName, isNull);
      expect(identity(const ApplePersonName(nickname: 'nick')).formattedName, isNull);
    });

    test('toString includes the formatted name', () {
      expect(
        const AppleAuthIdentity(
          userIdentifier: 'u',
          email: 'e@x.y',
          name: ApplePersonName(givenName: 'Ada'),
        ).toString(),
        'AppleAuthIdentity(userIdentifier: u, email: e@x.y, name: Ada)',
      );
    });
  });

  group('AppleAuthSession', () {
    test('fromCredential maps every section', () {
      const credential = AppleCredential(
        userIdentifier: 'u1',
        email: 'e@x.y',
        name: ApplePersonName(givenName: 'Ada'),
        identityToken: 'tok',
        authorizationCode: 'code',
        state: 'st',
        authorizedScopes: {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
        realUserStatus: AppleRealUserStatus.likelyReal,
      );
      final before = DateTime.now();
      final session = AppleAuthSession.fromCredential(
        credential: credential,
        capabilities: _capabilities,
        nonce: 'n',
        credentialState: AppleCredentialState.authorized,
      );

      expect(session.identity.userIdentifier, 'u1');
      expect(session.identity.email, 'e@x.y');
      expect(session.identity.name, const ApplePersonName(givenName: 'Ada'));
      expect(session.authentication.identityToken, 'tok');
      expect(session.authentication.authorizationCode, 'code');
      expect(session.authentication.state, 'st');
      expect(session.authentication.nonce, 'n');
      expect(session.authorization.scopes, credential.authorizedScopes);
      expect(session.authorization.realUserStatus, AppleRealUserStatus.likelyReal);
      expect(session.lifecycle.isAuthorized, isTrue);
      expect(session.lifecycle.isFirstAuthorization, isTrue);
      expect(session.lifecycle.credentialState, AppleCredentialState.authorized);
      expect(session.metadata.receivedName, isTrue);
      expect(session.metadata.receivedEmail, isTrue);
      expect(session.metadata.capabilities, _capabilities);
      expect(session.metadata.createdAt.isBefore(before), isFalse);
      expect(session.rawCredential, credential);
    });

    test('fromCredential with no optional data', () {
      final session = AppleAuthSession.fromCredential(
        credential: const AppleCredential(
          userIdentifier: 'u',
          state: '',
          authorizedScopes: {},
          realUserStatus: AppleRealUserStatus.unsupported,
        ),
        capabilities: _capabilities,
      );
      expect(session.identity.email, isNull);
      expect(session.authentication.nonce, isNull);
      expect(session.lifecycle.credentialState, isNull);
      expect(session.lifecycle.isFirstAuthorization, isFalse);
      expect(session.metadata.receivedName, isFalse);
      expect(session.metadata.receivedEmail, isFalse);
    });

    test('toString implementations summarize without leaking tokens', () {
      final session = AppleAuthSession.fromCredential(
        credential: const AppleCredential(
          userIdentifier: 'u',
          email: 'e@x.y',
          identityToken: 'SECRET',
          authorizationCode: 'SECRET2',
          state: 'st',
          authorizedScopes: {AppleAuthorizationScope.email},
          realUserStatus: AppleRealUserStatus.unknown,
        ),
        capabilities: _capabilities,
        credentialState: AppleCredentialState.revoked,
      );
      expect(
        session.authentication.toString(),
        'AppleAuthTokens(hasIdentityToken: true, hasAuthCode: true, state: st)',
      );
      expect(
        session.authorization.toString(),
        'AppleAuthAuthorization(scopes: {AppleAuthorizationScope.email}, '
        'realUserStatus: AppleRealUserStatus.unknown)',
      );
      expect(
        session.lifecycle.toString(),
        'AppleAuthLifecycle(isAuthorized: true, isFirstAuth: false, '
        'credentialState: AppleCredentialState.revoked)',
      );
      expect(
        session.metadata.toString(),
        'AppleAuthMetadata(receivedName: false, receivedEmail: true, platform: iOS)',
      );
      final text = session.toString();
      expect(text, startsWith('AppleAuthSession(identity: AppleAuthIdentity('));
      expect(text, isNot(contains('SECRET')));
      expect(
        const AppleAuthTokens(state: 's').toString(),
        'AppleAuthTokens(hasIdentityToken: false, hasAuthCode: false, state: s)',
      );
    });
  });
}
