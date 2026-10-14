// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_darwin/apple_sign_in_plugin_darwin.dart';
import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('apple_sign_in_plugin');
  const revocation = EventChannel('apple_sign_in_plugin/credential_revoked');

  late List<MethodCall> calls;
  Object? Function(MethodCall call) handler = (call) => null;

  setUp(() {
    calls = <MethodCall>[];
    handler = (call) => null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
    AppleSignInPluginDarwin.registerWith();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockStreamHandler(revocation, null);
  });

  AppleSignInPlatform platform() => AppleSignInPlatform.instance;

  TypeMatcher<AppleSignInException> exception(AppleSignInErrorCode code, [Object? message]) =>
      isA<AppleSignInException>()
          .having((e) => e.code, 'code', code)
          .having((e) => e.message, 'message', message ?? isNotEmpty);

  group('registerWith', () {
    test('installs a MethodChannelAppleSignIn as the platform instance', () {
      AppleSignInPlatform.instance = _FakePlatform();
      AppleSignInPluginDarwin.registerWith();
      expect(AppleSignInPlatform.instance, isA<MethodChannelAppleSignIn>());
    });

    test('creates a fresh instance on every call', () {
      final AppleSignInPlatform first = AppleSignInPlatform.instance;
      AppleSignInPluginDarwin.registerWith();
      expect(AppleSignInPlatform.instance, isNot(same(first)));
    });

    test('the registered instance talks over the apple_sign_in_plugin '
        'channels', () {
      final instance = AppleSignInPlatform.instance as MethodChannelAppleSignIn;
      expect(instance.channel.name, 'apple_sign_in_plugin');
      expect(instance.revocationChannel.name, 'apple_sign_in_plugin/credential_revoked');
    });

    test('can be constructed (the class carries no state)', () {
      expect(AppleSignInPluginDarwin(), isA<AppleSignInPluginDarwin>());
    });
  });

  for (final TargetPlatform target in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    group('on $target', () {
      setUp(() => debugDefaultTargetPlatformOverride = target);

      group('isAvailable', () {
        test('returns the native answer', () async {
          handler = (call) => true;
          expect(await platform().isAvailable(), isTrue);
          handler = (call) => false;
          expect(await platform().isAvailable(), isFalse);
          expect(calls.map((c) => c.method), ['isAvailable', 'isAvailable']);
          expect(calls.first.arguments, isNull);
        });

        test('treats a null native answer as unavailable', () async {
          expect(await platform().isAvailable(), isFalse);
        });

        test('propagates native failures', () async {
          handler = (call) => throw PlatformException(code: 'boom');
          await expectLater(platform().isAvailable(), throwsA(isA<PlatformException>()));
        });
      });

      group('signIn arguments', () {
        Map<String, Object?> minimalReply() => {'userIdentifier': 'u1'};

        test('sends scope names, nonce and state', () async {
          handler = (call) => minimalReply();
          await platform().signIn(
            scopes: {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
            nonce: 'n-123',
            state: 's-456',
          );

          expect(calls.single.method, 'signIn');
          expect(calls.single.arguments, {
            'scopes': ['email', 'fullName'],
            'nonce': 'n-123',
            'state': 's-456',
          });
        });

        test('sends null for omitted nonce and state', () async {
          handler = (call) => minimalReply();
          await platform().signIn(scopes: {AppleAuthorizationScope.email});
          expect(calls.single.arguments, {
            'scopes': ['email'],
            'nonce': null,
            'state': null,
          });
        });

        test('passes empty, whitespace, unicode and very long values '
            'unchanged', () async {
          handler = (call) => minimalReply();
          final String long = 'x' * 100000;
          for (final v in ['', '  \n', 'é\u{1F600}', long]) {
            calls.clear();
            await platform().signIn(scopes: {AppleAuthorizationScope.email}, nonce: v, state: v);
            expect((calls.single.arguments as Map<Object?, Object?>)['nonce'], v);
            expect((calls.single.arguments as Map<Object?, Object?>)['state'], v);
          }
        });

        test('rejects an empty scope set without calling native', () async {
          await expectLater(
            platform().signIn(scopes: {}),
            throwsA(exception(AppleSignInErrorCode.invalidArguments)),
          );
          expect(calls, isEmpty);
        });
      });

      group('signIn result mapping', () {
        Future<AppleCredential> signIn() =>
            platform().signIn(scopes: {AppleAuthorizationScope.email});

        test('maps a complete first-authorization response', () async {
          handler = (call) => {
            'userIdentifier': 'user.1',
            'email': 'a@example.com',
            'identityToken': 'jwt',
            'authorizationCode': 'code',
            'state': 'st',
            'namePrefix': 'Dr',
            'givenName': 'Ada',
            'middleName': 'M',
            'familyName': 'Lovelace',
            'nameSuffix': 'Jr',
            'nickname': 'ada',
            'authorizedScopes': ['email', 'fullName'],
            'realUserStatus': 2,
          };

          final AppleCredential credential = await signIn();

          expect(credential.userIdentifier, 'user.1');
          expect(credential.email, 'a@example.com');
          expect(credential.identityToken, 'jwt');
          expect(credential.authorizationCode, 'code');
          expect(credential.state, 'st');
          expect(
            credential.name,
            const ApplePersonName(
              namePrefix: 'Dr',
              givenName: 'Ada',
              middleName: 'M',
              familyName: 'Lovelace',
              nameSuffix: 'Jr',
              nickname: 'ada',
            ),
          );
          expect(credential.authorizedScopes, {
            AppleAuthorizationScope.email,
            AppleAuthorizationScope.fullName,
          });
          expect(credential.realUserStatus, AppleRealUserStatus.likelyReal);
          expect(credential.receivedEmail, isTrue);
          expect(credential.receivedName, isTrue);
        });

        test('a returning-user response has no name and defaults', () async {
          handler = (call) => {'userIdentifier': 'user.2'};

          final AppleCredential credential = await signIn();

          expect(credential.name, isNull);
          expect(credential.email, isNull);
          expect(credential.identityToken, isNull);
          expect(credential.authorizationCode, isNull);
          expect(credential.state, '');
          expect(credential.authorizedScopes, isEmpty);
          expect(credential.realUserStatus, AppleRealUserStatus.unsupported);
          expect(credential.receivedName, isFalse);
          expect(credential.receivedEmail, isFalse);
        });

        test('only some name parts present still yields a name', () async {
          handler = (call) => {'userIdentifier': 'u', 'givenName': 'Ada'};
          final AppleCredential credential = await signIn();
          expect(credential.name, const ApplePersonName(givenName: 'Ada'));
        });

        test('real user status wire values map to the enum', () async {
          final Map<int?, AppleRealUserStatus> expected = {
            null: AppleRealUserStatus.unsupported,
            0: AppleRealUserStatus.unsupported,
            1: AppleRealUserStatus.unknown,
            2: AppleRealUserStatus.likelyReal,
            99: AppleRealUserStatus.unsupported,
            -1: AppleRealUserStatus.unsupported,
          };
          for (final MapEntry<int?, AppleRealUserStatus> entry in expected.entries) {
            handler = (call) => {'userIdentifier': 'u', 'realUserStatus': entry.key};
            expect((await signIn()).realUserStatus, entry.value, reason: 'wire ${entry.key}');
          }
        });

        test('unknown scope strings fall back to email', () async {
          handler = (call) => {
            'userIdentifier': 'u',
            'authorizedScopes': ['email', 'bogus', 'fullName'],
          };
          expect((await signIn()).authorizedScopes, {
            AppleAuthorizationScope.email,
            AppleAuthorizationScope.fullName,
          });
        });

        test('duplicate scopes collapse to a set', () async {
          handler = (call) => {
            'userIdentifier': 'u',
            'authorizedScopes': ['email', 'email'],
          };
          expect((await signIn()).authorizedScopes, {AppleAuthorizationScope.email});
        });

        test('a missing userIdentifier is an invalidResponse', () async {
          handler = (call) => {'email': 'a@example.com'};
          await expectLater(
            signIn(),
            throwsA(exception(AppleSignInErrorCode.invalidResponse, contains('userIdentifier'))),
          );
        });

        test('an empty map response is an invalidResponse', () async {
          handler = (call) => <String, Object?>{};
          await expectLater(signIn(), throwsA(exception(AppleSignInErrorCode.invalidResponse)));
        });

        test('a null response is an invalidResponse', () async {
          handler = (call) => null;
          await expectLater(
            signIn(),
            throwsA(exception(AppleSignInErrorCode.invalidResponse, contains('no data'))),
          );
        });

        test('a wrongly-typed field is rejected with a type error', () async {
          handler = (call) => {'userIdentifier': 42};
          await expectLater(signIn(), throwsA(isA<TypeError>()));
        });
      });

      group('signIn error mapping', () {
        Future<AppleCredential> signIn() =>
            platform().signIn(scopes: {AppleAuthorizationScope.email});

        test('maps every documented native error code', () async {
          const Map<String, AppleSignInErrorCode> mapping = {
            'canceled': AppleSignInErrorCode.canceled,
            'already_in_progress': AppleSignInErrorCode.alreadyInProgress,
            'not_available': AppleSignInErrorCode.notAvailable,
            'invalid_configuration': AppleSignInErrorCode.invalidConfiguration,
            'authorization_failed': AppleSignInErrorCode.authorizationFailed,
            'invalid_response': AppleSignInErrorCode.invalidResponse,
            'network_failed': AppleSignInErrorCode.networkFailed,
          };
          for (final MapEntry<String, AppleSignInErrorCode> entry in mapping.entries) {
            handler = (call) => throw PlatformException(
              code: entry.key,
              message: 'native says ${entry.key}',
              details: {'k': entry.key},
            );
            await expectLater(
              signIn(),
              throwsA(
                exception(
                  entry.value,
                  'native says ${entry.key}',
                ).having((e) => e.details, 'details', {'k': entry.key}),
              ),
              reason: entry.key,
            );
          }
        });

        test('the user cancelling is reported as canceled', () async {
          handler = (call) => throw PlatformException(code: 'canceled');
          await expectLater(signIn(), throwsA(exception(AppleSignInErrorCode.canceled)));
        });

        test('unrecognised codes map to unknown and keep the code in the '
            'message when none was supplied', () async {
          handler = (call) => throw PlatformException(code: 'weird_code');
          await expectLater(
            signIn(),
            throwsA(exception(AppleSignInErrorCode.unknown, contains('weird_code'))),
          );
        });

        test('code matching is case-sensitive and exact', () async {
          for (final code in ['CANCELED', 'canceled ', '', 'cancelled']) {
            handler = (call) => throw PlatformException(code: code);
            await expectLater(
              signIn(),
              throwsA(exception(AppleSignInErrorCode.unknown)),
              reason: 'code "$code"',
            );
          }
        });

        test('a missing native handler surfaces MissingPluginException', () async {
          messenger.setMockMethodCallHandler(channel, null);
          await expectLater(signIn(), throwsA(isA<MissingPluginException>()));
        });
      });

      group('signIn concurrency', () {
        test('parallel calls are each forwarded and resolved independently', () async {
          handler = (call) => {'userIdentifier': 'id-${(call.arguments as Map)['nonce']}'};
          final List<AppleCredential> results = await Future.wait([
            for (var i = 0; i < 5; i++)
              platform().signIn(scopes: {AppleAuthorizationScope.email}, nonce: '$i'),
          ]);
          expect(results.map((c) => c.userIdentifier), ['id-0', 'id-1', 'id-2', 'id-3', 'id-4']);
          expect(calls, hasLength(5));
        });

        test('an already_in_progress rejection does not poison later calls', () async {
          handler = (call) => throw PlatformException(code: 'already_in_progress');
          await expectLater(
            platform().signIn(scopes: {AppleAuthorizationScope.email}),
            throwsA(exception(AppleSignInErrorCode.alreadyInProgress)),
          );
          handler = (call) => {'userIdentifier': 'ok'};
          expect(
            (await platform().signIn(scopes: {AppleAuthorizationScope.email})).userIdentifier,
            'ok',
          );
        });
      });

      group('getCredentialState', () {
        test('sends the user identifier', () async {
          handler = (call) => 0;
          await platform().getCredentialState('user.1');
          expect(calls.single.method, 'getCredentialState');
          expect(calls.single.arguments, {'userIdentifier': 'user.1'});
        });

        test('maps wire values to states', () async {
          const Map<int, AppleCredentialState> expected = {
            0: AppleCredentialState.authorized,
            1: AppleCredentialState.revoked,
            2: AppleCredentialState.notFound,
            3: AppleCredentialState.transferred,
            4: AppleCredentialState.notFound,
            -1: AppleCredentialState.notFound,
          };
          for (final MapEntry<int, AppleCredentialState> entry in expected.entries) {
            handler = (call) => entry.key;
            expect(
              await platform().getCredentialState('u'),
              entry.value,
              reason: 'wire ${entry.key}',
            );
          }
        });

        test('forwards empty and very long identifiers', () async {
          handler = (call) => 0;
          for (final String id in ['', ' ', 'u' * 50000]) {
            calls.clear();
            await platform().getCredentialState(id);
            expect(calls.single.arguments, {'userIdentifier': id});
          }
        });

        test('a null native response is credentialStateFailed', () async {
          await expectLater(
            platform().getCredentialState('u'),
            throwsA(exception(AppleSignInErrorCode.credentialStateFailed)),
          );
        });

        test('native failures become credentialStateFailed regardless of '
            'code', () async {
          handler = (call) =>
              throw PlatformException(code: 'canceled', message: 'lookup failed', details: 7);
          await expectLater(
            platform().getCredentialState('u'),
            throwsA(
              exception(
                AppleSignInErrorCode.credentialStateFailed,
                'lookup failed',
              ).having((e) => e.details, 'details', 7),
            ),
          );
        });

        test('uses a default message when native supplies none', () async {
          handler = (call) => throw PlatformException(code: 'x');
          await expectLater(
            platform().getCredentialState('u'),
            throwsA(
              exception(AppleSignInErrorCode.credentialStateFailed, 'getCredentialState() failed.'),
            ),
          );
        });
      });

      group('onCredentialRevoked', () {
        test('emits one event per native revocation notification', () async {
          messenger.setMockStreamHandler(
            revocation,
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success(null);
                sink.success('revoked');
                sink.endOfStream();
              },
            ),
          );
          var count = 0;
          await platform().onCredentialRevoked.forEach((_) => count++);
          expect(count, 2);
        });

        test('returns the same cached broadcast stream every time', () {
          final Stream<void> a = platform().onCredentialRevoked;
          final Stream<void> b = platform().onCredentialRevoked;
          expect(identical(a, b), isTrue);
          expect(a.isBroadcast, isTrue);
        });

        test('multiple listeners each receive events', () async {
          messenger.setMockStreamHandler(
            revocation,
            MockStreamHandler.inline(
              onListen: (arguments, sink) {
                sink.success(1);
                sink.endOfStream();
              },
            ),
          );
          final Stream<void> stream = platform().onCredentialRevoked;
          final Future<int> a = stream.length;
          final Future<int> b = stream.length;
          expect(await Future.wait([a, b]), [1, 1]);
        });
      });
    });
  }

  group('on unsupported platforms', () {
    for (final TargetPlatform target in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      group('$target', () {
        setUp(() => debugDefaultTargetPlatformOverride = target);

        test('isAvailable is false without touching the channel', () async {
          handler = (call) => true;
          expect(await platform().isAvailable(), isFalse);
          expect(calls, isEmpty);
        });

        test('signIn throws platformNotSupported without touching the '
            'channel', () async {
          await expectLater(
            platform().signIn(scopes: {AppleAuthorizationScope.email}),
            throwsA(exception(AppleSignInErrorCode.platformNotSupported)),
          );
          expect(calls, isEmpty);
        });

        test('platform support is checked before argument validation', () async {
          await expectLater(
            platform().signIn(scopes: {}),
            throwsA(exception(AppleSignInErrorCode.platformNotSupported)),
          );
        });

        test('getCredentialState throws platformNotSupported', () async {
          await expectLater(
            platform().getCredentialState('u'),
            throwsA(exception(AppleSignInErrorCode.platformNotSupported)),
          );
          expect(calls, isEmpty);
        });

        test('onCredentialRevoked is an empty stream', () async {
          expect(await platform().onCredentialRevoked.toList(), isEmpty);
        });
      });
    }
  });

  group('AppleSignInException', () {
    test('toString includes the code name and message', () {
      const e = AppleSignInException(AppleSignInErrorCode.canceled, 'nope');
      expect(e.toString(), 'AppleSignInException(canceled): nope');
      expect(e.details, isNull);
    });
  });
}

class _FakePlatform extends AppleSignInPlatform {}
