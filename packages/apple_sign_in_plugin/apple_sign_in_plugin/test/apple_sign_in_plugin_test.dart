// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlatform extends AppleSignInPlatform {
  bool isAvailableResult = true;
  AppleCredential? credentialResult;
  AppleCredentialState credentialStateResult = AppleCredentialState.authorized;
  final StreamController<void> revocationController =
      StreamController<void>.broadcast();

  @override
  Future<bool> isAvailable() async => isAvailableResult;

  @override
  Future<AppleCredential> signIn({
    required Set<AppleAuthorizationScope> scopes,
    String? nonce,
    String? state,
  }) async {
    return credentialResult ??
        AppleCredential(
          userIdentifier: 'test.user.123',
          email: 'test@example.com',
          name: const ApplePersonName(givenName: 'Test', familyName: 'User'),
          identityToken: 'fake.jwt.token',
          authorizationCode: 'auth_code_123',
          state: state ?? 'state_123',
          authorizedScopes: scopes,
          realUserStatus: AppleRealUserStatus.likelyReal,
        );
  }

  @override
  Future<AppleCredentialState> getCredentialState(String userIdentifier) async {
    return credentialStateResult;
  }

  @override
  Stream<void> get onCredentialRevoked => revocationController.stream;
}

class _MockBackendAdapter implements AppleBackendAdapter {
  bool exchangeCalled = false;
  bool revokeCalled = false;

  @override
  Future<void> onAuthorizationSuccess(AppleCredential credential) async {
    exchangeCalled = true;
  }

  @override
  Future<AppleDisconnectResult> revokeAuthorization(
      String userIdentifier) async {
    revokeCalled = true;
    return const AppleDisconnectResult(
      status: AppleDisconnectStatus.revoked,
      message: 'Revoked via backend.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppleSignIn Complete Lifecycle & AppleAuthSession', () {
    late _FakePlatform fakePlatform;

    setUp(() {
      fakePlatform = _FakePlatform();
      AppleSignInPlatform.instance = fakePlatform;
      AppleSignIn.instance.backendAdapter = null;
    });

    test('isAvailable forwards to platform instance', () async {
      expect(await AppleSignIn.instance.isAvailable(), isTrue);
      fakePlatform.isAvailableResult = false;
      expect(await AppleSignIn.instance.isAvailable(), isFalse);
    });

    test(
        'signIn returns strongly-typed AppleAuthSession and emits signedIn event',
        () async {
      final adapter = _MockBackendAdapter();
      AppleSignIn.instance.backendAdapter = adapter;

      final events = <AppleAuthEvent>[];
      final StreamSubscription<AppleAuthEvent> subscription =
          AppleSignIn.instance.events.listen(events.add);

      final AppleAuthSession session = await AppleSignIn.instance.signIn(
        scopes: {
          AppleAuthorizationScope.email,
          AppleAuthorizationScope.fullName
        },
        nonce: 'test_nonce_abc',
      );

      // 1. Identity
      expect(session.identity.userIdentifier, 'test.user.123');
      expect(session.identity.email, 'test@example.com');
      expect(session.identity.name?.givenName, 'Test');
      expect(session.identity.formattedName, 'Test User');

      // 2. Authentication
      expect(session.authentication.identityToken, 'fake.jwt.token');
      expect(session.authentication.authorizationCode, 'auth_code_123');
      expect(session.authentication.nonce, 'test_nonce_abc');

      // 3. Lifecycle
      expect(session.lifecycle.isAuthorized, isTrue);
      expect(session.lifecycle.isFirstAuthorization, isTrue);

      // 4. Metadata
      expect(session.metadata.receivedName, isTrue);
      expect(session.metadata.receivedEmail, isTrue);

      await pumpEventQueue();
      expect(events.length, 1);
      expect(events.first.type, AppleAuthEventType.signedIn);
      expect(events.first.userIdentifier, 'test.user.123');
      expect(adapter.exchangeCalled, isTrue);

      await subscription.cancel();
    });

    test('signOut clears active session and emits signedOut event', () async {
      final events = <AppleAuthEvent>[];
      final StreamSubscription<AppleAuthEvent> subscription =
          AppleSignIn.instance.events.listen(events.add);

      await AppleSignIn.instance
          .signIn(scopes: {AppleAuthorizationScope.email});
      expect(AppleSignIn.instance.currentSession, isNotNull);

      await AppleSignIn.instance.signOut();
      expect(AppleSignIn.instance.currentSession, isNull);

      await pumpEventQueue();
      expect(events.where((e) => e.type == AppleAuthEventType.signedOut).length,
          1);

      await subscription.cancel();
    });

    test('native onCredentialRevoked emits credentialRevoked event', () async {
      final events = <AppleAuthEvent>[];
      final StreamSubscription<AppleAuthEvent> subscription =
          AppleSignIn.instance.events.listen(events.add);

      fakePlatform.revocationController.add(null);

      await pumpEventQueue();
      expect(events.length, 1);
      expect(events.first.type, AppleAuthEventType.credentialRevoked);

      await subscription.cancel();
    });

    test(
        'getCredentialState emits credentialTransferred event on transferred state',
        () async {
      fakePlatform.credentialStateResult = AppleCredentialState.transferred;

      final events = <AppleAuthEvent>[];
      final StreamSubscription<AppleAuthEvent> subscription =
          AppleSignIn.instance.events.listen(events.add);

      final AppleCredentialState state =
          await AppleSignIn.instance.getCredentialState('user_transferred');
      expect(state, AppleCredentialState.transferred);

      await pumpEventQueue();
      expect(events.length, 1);
      expect(events.first.type, AppleAuthEventType.credentialTransferred);

      await subscription.cancel();
    });

    test('disconnect delegates to backend adapter when present', () async {
      final adapter = _MockBackendAdapter();
      AppleSignIn.instance.backendAdapter = adapter;

      final AppleDisconnectResult result =
          await AppleSignIn.instance.disconnect(userIdentifier: 'user789');
      expect(result.status, AppleDisconnectStatus.revoked);
      expect(result.isSuccessful, isTrue);
      expect(adapter.revokeCalled, isTrue);
    });

    test('capabilities reflects platform matrix accurately', () async {
      final AppleSignInCapabilities caps =
          await AppleSignIn.instance.capabilities();
      expect(caps.isSupported, isTrue);
      expect(caps.supportedScopes, contains(AppleAuthorizationScope.email));
    });

    test('diagnostics returns safe metadata without secrets', () async {
      final AppleSignInDiagnostics diag =
          await AppleSignIn.instance.diagnostics();
      expect(diag.isAvailable, isTrue);
      expect(
          diag.toSafeString(), contains('=== Apple Sign-In Diagnostics ==='));
      expect(diag.toSafeString(), isNot(contains('fake.jwt.token')));
    });

    test('AppleSignInPlugin compatibility wrapper returns AppleCredential',
        () async {
      final AppleCredential cred = await AppleSignInPlugin.signIn(
        scopes: {AppleAuthorizationScope.email},
      );
      expect(cred, isA<AppleCredential>());
      expect(cred.userIdentifier, 'test.user.123');
    });
  });
}
