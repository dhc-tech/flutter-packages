// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlatform extends AppleSignInPlatform {
  bool available = true;
  Object? signInError;
  Object? credentialStateError;
  AppleCredentialState credentialState = AppleCredentialState.authorized;
  AppleCredential? credential;
  final List<Map<String, Object?>> signInCalls = <Map<String, Object?>>[];
  final List<String> credentialStateCalls = <String>[];
  final StreamController<void> revocations = StreamController<void>.broadcast();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AppleCredential> signIn({
    required Set<AppleAuthorizationScope> scopes,
    String? nonce,
    String? state,
  }) async {
    signInCalls.add(<String, Object?>{'scopes': scopes, 'nonce': nonce, 'state': state});
    final Object? error = signInError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return credential ??
        AppleCredential(
          userIdentifier: 'user.1',
          state: state ?? '',
          authorizedScopes: scopes,
          realUserStatus: AppleRealUserStatus.unknown,
        );
  }

  @override
  Future<AppleCredentialState> getCredentialState(String userIdentifier) async {
    credentialStateCalls.add(userIdentifier);
    final Object? error = credentialStateError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return credentialState;
  }

  @override
  Stream<void> get onCredentialRevoked => revocations.stream;
}

class _Adapter implements AppleBackendAdapter {
  final List<AppleCredential> successes = <AppleCredential>[];
  final List<String> revoked = <String>[];
  Object? successError;
  AppleDisconnectResult revokeResult = const AppleDisconnectResult(
    status: AppleDisconnectStatus.revoked,
  );

  @override
  Future<void> onAuthorizationSuccess(AppleCredential credential) async {
    successes.add(credential);
    final Object? error = successError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  Future<AppleDisconnectResult> revokeAuthorization(String userIdentifier) async {
    revoked.add(userIdentifier);
    return revokeResult;
  }
}

Matcher _throwsCode(AppleSignInErrorCode code) =>
    throwsA(isA<AppleSignInException>().having((AppleSignInException e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform platform;
  late List<AppleAuthEvent> events;
  late StreamSubscription<AppleAuthEvent> subscription;
  final AppleSignIn sut = AppleSignIn.instance;

  setUp(() async {
    platform = _FakePlatform();
    AppleSignInPlatform.instance = platform;
    sut.backendAdapter = null;
    await sut.signOut();
    events = <AppleAuthEvent>[];
    subscription = sut.events.listen(events.add);
    await pumpEventQueue();
    events.clear();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await subscription.cancel();
  });

  test('AppleSignIn is a singleton', () {
    expect(AppleSignIn.instance, same(sut));
  });

  group('signIn', () {
    test('forwards scopes, nonce and state to the platform', () async {
      await sut.signIn(scopes: {AppleAuthorizationScope.fullName}, nonce: 'n', state: 's');
      expect(platform.signInCalls.single, <String, Object?>{
        'scopes': {AppleAuthorizationScope.fullName},
        'nonce': 'n',
        'state': 's',
      });
    });

    test('stores the current session and exposes the nonce', () async {
      final AppleAuthSession session = await sut.signIn(
        scopes: {AppleAuthorizationScope.email},
        nonce: 'n',
      );
      expect(sut.currentSession, same(session));
      expect(session.authentication.nonce, 'n');
      expect(session.metadata.capabilities.backendRevocation, isFalse);
    });

    test('records backend adapter presence in the session capabilities', () async {
      sut.backendAdapter = _Adapter();
      final AppleAuthSession session = await sut.signIn(scopes: {AppleAuthorizationScope.email});
      expect(session.metadata.capabilities.backendRevocation, isTrue);
    });

    test('notifies the backend adapter with the raw credential', () async {
      final adapter = _Adapter();
      sut.backendAdapter = adapter;
      final AppleAuthSession session = await sut.signIn(scopes: {AppleAuthorizationScope.email});
      await pumpEventQueue();
      expect(adapter.successes.single, session.rawCredential);
    });

    test('an adapter failure does not fail sign-in and is reported, not left uncaught', () async {
      final adapter = _Adapter()..successError = StateError('backend down');
      sut.backendAdapter = adapter;
      final reported = <FlutterErrorDetails>[];
      final FlutterExceptionHandler? previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final uncaught = <Object>[];
      late AppleAuthSession session;
      await runZonedGuarded(() async {
        session = await sut.signIn(scopes: {AppleAuthorizationScope.email});
        await pumpEventQueue();
      }, (Object error, StackTrace _) => uncaught.add(error));
      expect(session.identity.userIdentifier, 'user.1');
      expect(uncaught, isEmpty);
      expect(reported.single.exception, isA<StateError>());
      expect(reported.single.library, 'apple_sign_in_plugin');
    });

    test('emits signedIn with the credential and user identifier', () async {
      final AppleAuthSession session = await sut.signIn(scopes: {AppleAuthorizationScope.email});
      await pumpEventQueue();
      expect(events, hasLength(1));
      expect(events.single.type, AppleAuthEventType.signedIn);
      expect(events.single.credential, session.rawCredential);
      expect(events.single.userIdentifier, 'user.1');
    });

    test('canceled errors emit authorizationCancelled and rethrow', () async {
      platform.signInError = const AppleSignInException(AppleSignInErrorCode.canceled, 'x');
      await expectLater(
        sut.signIn(scopes: {AppleAuthorizationScope.email}),
        _throwsCode(AppleSignInErrorCode.canceled),
      );
      await pumpEventQueue();
      expect(events.single.type, AppleAuthEventType.authorizationCancelled);
      expect(sut.currentSession, isNull);
    });

    test('other Apple errors rethrow without an event', () async {
      for (final AppleSignInErrorCode code in AppleSignInErrorCode.values) {
        if (code == AppleSignInErrorCode.canceled) {
          continue;
        }
        platform.signInError = AppleSignInException(code, 'x');
        await expectLater(sut.signIn(scopes: {AppleAuthorizationScope.email}), _throwsCode(code));
      }
      await pumpEventQueue();
      expect(events, isEmpty);
    });

    test('non-Apple errors propagate untouched', () async {
      platform.signInError = StateError('boom');
      await expectLater(
        sut.signIn(scopes: {AppleAuthorizationScope.email}),
        throwsA(isA<StateError>()),
      );
      expect(events, isEmpty);
    });

    test('a failed sign-in keeps the previous session', () async {
      final AppleAuthSession first = await sut.signIn(scopes: {AppleAuthorizationScope.email});
      platform.signInError = const AppleSignInException(AppleSignInErrorCode.unknown, 'x');
      await expectLater(
        sut.signIn(scopes: {AppleAuthorizationScope.email}),
        _throwsCode(AppleSignInErrorCode.unknown),
      );
      expect(sut.currentSession, same(first));
    });

    test('concurrent sign-ins each produce a session; the last one wins', () async {
      final List<AppleAuthSession> sessions = await Future.wait(<Future<AppleAuthSession>>[
        sut.signIn(scopes: {AppleAuthorizationScope.email}, state: 'a'),
        sut.signIn(scopes: {AppleAuthorizationScope.email}, state: 'b'),
      ]);
      expect(sessions.map((AppleAuthSession s) => s.authentication.state), <String>['a', 'b']);
      expect(sut.currentSession, isNotNull);
      expect(platform.signInCalls, hasLength(2));
    });

    test('empty and very long nonce or state values pass through unchanged', () async {
      final String long = 'x' * 10000;
      final AppleAuthSession session = await sut.signIn(
        scopes: {AppleAuthorizationScope.email},
        nonce: '',
        state: long,
      );
      expect(session.authentication.nonce, '');
      expect(session.authentication.state, long);
    });
  });

  group('signOut', () {
    test('uses the session user id when none is given', () async {
      await sut.signIn(scopes: {AppleAuthorizationScope.email});
      await pumpEventQueue();
      events.clear();
      await sut.signOut();
      await pumpEventQueue();
      expect(sut.currentSession, isNull);
      expect(events.single.type, AppleAuthEventType.signedOut);
      expect(events.single.userIdentifier, 'user.1');
    });

    test('an explicit user id wins over the session id', () async {
      await sut.signIn(scopes: {AppleAuthorizationScope.email});
      await pumpEventQueue();
      events.clear();
      await sut.signOut(userIdentifier: 'explicit');
      await pumpEventQueue();
      expect(events.single.userIdentifier, 'explicit');
    });

    test('without a session emits an event with a null user id', () async {
      await sut.signOut();
      await pumpEventQueue();
      expect(events.single.userIdentifier, isNull);
    });

    test('is idempotent', () async {
      await sut.signOut();
      await sut.signOut();
      await pumpEventQueue();
      expect(
        events.where((AppleAuthEvent e) => e.type == AppleAuthEventType.signedOut),
        hasLength(2),
      );
    });
  });

  group('getCredentialState', () {
    test('returns non-transferred states without an event', () async {
      for (final state in <AppleCredentialState>[
        AppleCredentialState.authorized,
        AppleCredentialState.revoked,
        AppleCredentialState.notFound,
      ]) {
        platform.credentialState = state;
        expect(await sut.getCredentialState('u'), state);
      }
      await pumpEventQueue();
      expect(events, isEmpty);
      expect(platform.credentialStateCalls, <String>['u', 'u', 'u']);
    });

    test('transferred emits an event carrying the user id', () async {
      platform.credentialState = AppleCredentialState.transferred;
      await sut.getCredentialState('moved');
      await pumpEventQueue();
      expect(events.single.type, AppleAuthEventType.credentialTransferred);
      expect(events.single.userIdentifier, 'moved');
    });

    test('platform errors propagate', () async {
      platform.credentialStateError = const AppleSignInException(
        AppleSignInErrorCode.platformNotSupported,
        'x',
      );
      await expectLater(
        sut.getCredentialState(''),
        _throwsCode(AppleSignInErrorCode.platformNotSupported),
      );
    });
  });

  group('events and revocation', () {
    test('every native revocation becomes a credentialRevoked event', () async {
      platform.revocations
        ..add(null)
        ..add(null);
      await pumpEventQueue();
      expect(
        events.map((AppleAuthEvent e) => e.type),
        everyElement(AppleAuthEventType.credentialRevoked),
      );
      expect(events, hasLength(2));
    });

    test('requesting events again does not duplicate platform subscriptions', () async {
      final second = <AppleAuthEvent>[];
      final StreamSubscription<AppleAuthEvent> sub2 = sut.events.listen(second.add);
      platform.revocations.add(null);
      await pumpEventQueue();
      expect(events, hasLength(1));
      expect(second, hasLength(1));
      await sub2.cancel();
    });

    test('events is a broadcast stream', () {
      expect(sut.events.isBroadcast, isTrue);
    });

    test('onCredentialRevoked passes the platform stream through', () async {
      final Future<List<void>> got = sut.onCredentialRevoked.take(1).toList();
      platform.revocations.add(null);
      expect(await got, hasLength(1));
    });
  });

  group('disconnect', () {
    test('with a backend adapter delegates revocation and clears the session', () async {
      final adapter = _Adapter()
        ..revokeResult = const AppleDisconnectResult(
          status: AppleDisconnectStatus.failed,
          message: 'nope',
        );
      sut.backendAdapter = adapter;
      await sut.signIn(scopes: {AppleAuthorizationScope.email});
      final AppleDisconnectResult result = await sut.disconnect();
      expect(adapter.revoked, <String>['user.1']);
      expect(result.status, AppleDisconnectStatus.failed);
      expect(result.isSuccessful, isFalse);
      expect(sut.currentSession, isNull);
    });

    test('forceLocalSignOut false keeps the session', () async {
      sut.backendAdapter = _Adapter();
      await sut.signIn(scopes: {AppleAuthorizationScope.email});
      await sut.disconnect(forceLocalSignOut: false);
      expect(sut.currentSession, isNotNull);
    });

    test('an adapter is bypassed when there is no user id', () async {
      final adapter = _Adapter();
      sut.backendAdapter = adapter;
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      final AppleDisconnectResult result = await sut.disconnect();
      expect(adapter.revoked, isEmpty);
      expect(result.status, AppleDisconnectStatus.unsupported);
    });

    group('on Apple platforms', () {
      setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

      test('a revoked credential reports alreadyRevoked', () async {
        platform.credentialState = AppleCredentialState.revoked;
        final AppleDisconnectResult r = await sut.disconnect(userIdentifier: 'u');
        expect(r.status, AppleDisconnectStatus.alreadyRevoked);
        expect(r.isSuccessful, isTrue);
      });

      for (final state in <AppleCredentialState>[
        AppleCredentialState.authorized,
        AppleCredentialState.notFound,
        AppleCredentialState.transferred,
      ]) {
        test('$state requires manual action', () async {
          platform.credentialState = state;
          final AppleDisconnectResult r = await sut.disconnect(userIdentifier: 'u');
          expect(r.status, AppleDisconnectStatus.manualActionRequired);
          expect(r.message, contains('Apple ID Settings'));
        });
      }

      test('a credential-state failure still reports manualActionRequired', () async {
        platform.credentialStateError = StateError('x');
        final AppleDisconnectResult r = await sut.disconnect(userIdentifier: 'u');
        expect(r.status, AppleDisconnectStatus.manualActionRequired);
        expect(r.message, contains('AppleBackendAdapter'));
      });

      test('uses the session user id when none is passed', () async {
        await sut.signIn(scopes: {AppleAuthorizationScope.email});
        await sut.disconnect();
        expect(platform.credentialStateCalls, <String>['user.1']);
      });

      test('without any user id the result is unsupported', () async {
        final AppleDisconnectResult r = await sut.disconnect();
        expect(r.status, AppleDisconnectStatus.unsupported);
        expect(platform.credentialStateCalls, isEmpty);
      });
    });

    for (final p in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      test('$p requires a backend', () async {
        debugDefaultTargetPlatformOverride = p;
        final AppleDisconnectResult r = await sut.disconnect(userIdentifier: 'u');
        expect(r.status, AppleDisconnectStatus.backendRequired);
        expect(r.isSuccessful, isFalse);
      });
    }

    test('fuchsia is unsupported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      final AppleDisconnectResult r = await sut.disconnect(userIdentifier: 'u');
      expect(r.status, AppleDisconnectStatus.unsupported);
    });

    test('emits a signedOut event only when forceLocalSignOut is true', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      await sut.disconnect(userIdentifier: 'u', forceLocalSignOut: false);
      await pumpEventQueue();
      expect(events, isEmpty);
      await sut.disconnect(userIdentifier: 'u');
      await pumpEventQueue();
      expect(events.single.type, AppleAuthEventType.signedOut);
      expect(events.single.userIdentifier, 'u');
    });
  });

  group('capabilities', () {
    const matrix = <TargetPlatform, List<Object>>{
      // name, nativeCredentialState, revocationEvents, browserAuthorization
      TargetPlatform.iOS: ['iOS', true, true, false],
      TargetPlatform.macOS: ['macOS', true, true, false],
      TargetPlatform.android: ['Android', false, false, true],
      TargetPlatform.windows: ['Windows', false, false, true],
      TargetPlatform.linux: ['Linux', false, false, true],
      TargetPlatform.fuchsia: ['Unknown', false, false, false],
    };

    for (final MapEntry<TargetPlatform, List<Object>> entry in matrix.entries) {
      test('${entry.key} flags', () async {
        debugDefaultTargetPlatformOverride = entry.key;
        final AppleSignInCapabilities caps = await sut.capabilities();
        expect(caps.platformName, entry.value[0]);
        expect(caps.nativeCredentialState, entry.value[1]);
        expect(caps.revocationEvents, entry.value[2]);
        expect(caps.browserAuthorization, entry.value[3]);
        expect(caps.webAppleJs, isFalse);
        expect(caps.wasmWeb, isFalse);
        expect(caps.isSupported, isTrue);
        expect(caps.supportedScopes, AppleAuthorizationScope.values.toSet());
      });
    }

    test('backendRevocation follows the adapter', () async {
      expect((await sut.capabilities()).backendRevocation, isFalse);
      sut.backendAdapter = _Adapter();
      expect((await sut.capabilities()).backendRevocation, isTrue);
    });
  });

  group('diagnostics', () {
    test('reflects availability and adapter configuration', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      platform.available = false;
      sut.backendAdapter = _Adapter();
      final AppleSignInDiagnostics d = await sut.diagnostics();
      expect(d.platformName, 'Android');
      expect(d.isAvailable, isFalse);
      expect(d.isConfigured, isTrue);
      expect(d.hasBackendAdapter, isTrue);
      expect(d.configurationDetails, <String, String>{
        'platform': 'Android',
        'backendAdapterConfigured': 'true',
      });
      expect(d.toSafeString(), contains('Backend Adapter Registered: true'));
    });

    test('without an adapter reports false', () async {
      final AppleSignInDiagnostics d = await sut.diagnostics();
      expect(d.hasBackendAdapter, isFalse);
      expect(d.configurationDetails['backendAdapterConfigured'], 'false');
    });
  });

  group('AppleSignInPlugin static wrapper', () {
    test('isAvailable forwards', () async {
      platform.available = false;
      expect(await AppleSignInPlugin.isAvailable(), isFalse);
    });

    test('signIn forwards arguments and returns the raw credential', () async {
      final AppleCredential c = await AppleSignInPlugin.signIn(
        scopes: {AppleAuthorizationScope.email},
        nonce: 'n',
        state: 's',
      );
      expect(c.userIdentifier, 'user.1');
      expect(c.state, 's');
      expect(platform.signInCalls.single['nonce'], 'n');
    });

    test('signIn propagates exceptions', () async {
      platform.signInError = const AppleSignInException(AppleSignInErrorCode.networkFailed, 'x');
      await expectLater(
        AppleSignInPlugin.signIn(scopes: {AppleAuthorizationScope.email}),
        _throwsCode(AppleSignInErrorCode.networkFailed),
      );
    });

    test('getCredentialState forwards', () async {
      platform.credentialState = AppleCredentialState.revoked;
      expect(await AppleSignInPlugin.getCredentialState('u'), AppleCredentialState.revoked);
    });

    test('onCredentialRevoked forwards', () async {
      final Future<List<void>> got = AppleSignInPlugin.onCredentialRevoked.take(1).toList();
      platform.revocations.add(null);
      expect(await got, hasLength(1));
    });
  });
}
