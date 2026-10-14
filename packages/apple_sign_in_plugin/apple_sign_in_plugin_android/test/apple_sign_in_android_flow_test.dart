// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:apple_sign_in_plugin_android/apple_sign_in_plugin_android.dart';
import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member

const _config = AppleSignInAndroidConfig(
  serviceId: 'com.example.service',
  redirectUri: 'https://api.example.com/auth/apple/callback',
  callbackScheme: 'com.example.app',
  callbackHost: 'apple-callback',
);

String _b64(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m)));

String _idToken(Map<String, dynamic> payload) => '${_b64({'alg': 'none'})}.${_b64(payload)}.sig';

Uri _callback(Map<String, String> params, {String host = 'apple-callback'}) =>
    Uri(scheme: 'com.example.app', host: host, queryParameters: params);

Matcher _throwsCode(AppleSignInErrorCode code) =>
    throwsA(isA<AppleSignInException>().having((AppleSignInException e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppleSignInAndroidImpl impl;
  late List<MethodCall> log;
  Object? Function(MethodCall call) nativeHandler = (MethodCall call) => true;

  setUp(() {
    impl = AppleSignInAndroidImpl()..config = _config;
    log = <MethodCall>[];
    nativeHandler = (MethodCall call) => true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      impl.channel,
      (MethodCall call) async {
        log.add(call);
        return nativeHandler(call);
      },
    );
  });

  tearDown(() {
    impl.cancel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      impl.channel,
      null,
    );
  });

  Future<AppleCredential> startSignIn({
    Set<AppleAuthorizationScope> scopes = const {AppleAuthorizationScope.email},
    String? nonce,
    String? state = 'st',
  }) {
    final Future<AppleCredential> future = impl.signIn(scopes: scopes, nonce: nonce, state: state);
    unawaited(future.then<void>((_) {}, onError: (Object _) {}));
    return future;
  }

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('registerWith installs the Android implementation', () {
    final AppleSignInPlatform original = AppleSignInPlatform.instance;
    addTearDown(() => AppleSignInPlatform.instance = original);
    AppleSignInPluginAndroid.registerWith();
    expect(AppleSignInPlatform.instance, isA<AppleSignInAndroidImpl>());
  });

  group('isAvailable', () {
    test('falls back to true when native returns null', () async {
      nativeHandler = (MethodCall call) => null;
      expect(await impl.isAvailable(), isTrue);
    });

    test('forwards a false native answer', () async {
      nativeHandler = (MethodCall call) => false;
      expect(await impl.isAvailable(), isFalse);
    });

    test('falls back to true on PlatformException', () async {
      nativeHandler = (MethodCall call) => throw PlatformException(code: 'x');
      expect(await impl.isAvailable(), isTrue);
    });
  });

  group('signIn', () {
    test('launches an authorize URL carrying all parameters', () async {
      final Future<AppleCredential> future = startSignIn(
        scopes: {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
        nonce: 'nnn',
      );
      await flush();

      final MethodCall call = log.singleWhere((MethodCall c) => c.method == 'launchAuthUrl');
      final Uri url = Uri.parse((call.arguments as Map<Object?, Object?>)['url']! as String);
      expect(url.origin, 'https://appleid.apple.com');
      expect(url.path, '/auth/authorize');
      expect(url.queryParameters, <String, String>{
        'client_id': 'com.example.service',
        'redirect_uri': 'https://api.example.com/auth/apple/callback',
        'response_type': 'code id_token',
        'scope': 'email name',
        'response_mode': 'form_post',
        'state': 'st',
        'nonce': 'nnn',
      });

      impl.handleCallback(_callback({'state': 'st', 'code': 'c'}));
      expect((await future).authorizationCode, 'c');
    });

    test('omits nonce when none is given and generates a random state', () async {
      final Future<AppleCredential> future = startSignIn(state: null);
      await flush();
      final MethodCall call = log.singleWhere((MethodCall c) => c.method == 'launchAuthUrl');
      final Uri url = Uri.parse((call.arguments as Map<Object?, Object?>)['url']! as String);
      expect(url.queryParameters.containsKey('nonce'), isFalse);
      final String state = url.queryParameters['state']!;
      expect(base64Url.decode(state), hasLength(32));

      impl.handleCallback(_callback({'state': state, 'code': 'c'}));
      expect((await future).state, state);
    });

    test('a second sign-in while one is pending fails with alreadyInProgress', () async {
      final Future<AppleCredential> first = startSignIn();
      await flush();
      await expectLater(startSignIn(), _throwsCode(AppleSignInErrorCode.alreadyInProgress));
      impl.cancel();
      await expectLater(first, _throwsCode(AppleSignInErrorCode.canceled));
    });

    test('sign-in can be started again after completion', () async {
      final Future<AppleCredential> first = startSignIn();
      await flush();
      impl.handleCallback(_callback({'state': 'st', 'code': 'c'}));
      await first;
      final Future<AppleCredential> second = startSignIn(state: 'two');
      await flush();
      impl.handleCallback(_callback({'state': 'two', 'code': 'c2'}));
      expect((await second).authorizationCode, 'c2');
    });

    test('native false from launchAuthUrl is authorizationFailed and cleans up', () async {
      nativeHandler = (MethodCall call) => false;
      await expectLater(startSignIn(), _throwsCode(AppleSignInErrorCode.authorizationFailed));
      nativeHandler = (MethodCall call) => true;
      final Future<AppleCredential> retry = startSignIn();
      await flush();
      impl.cancel();
      await expectLater(retry, _throwsCode(AppleSignInErrorCode.canceled));
    });

    test('native null from launchAuthUrl is authorizationFailed', () {
      nativeHandler = (MethodCall call) => null;
      expect(startSignIn(), _throwsCode(AppleSignInErrorCode.authorizationFailed));
    });

    test('PlatformException from launchAuthUrl keeps message and details', () {
      nativeHandler = (MethodCall call) =>
          throw PlatformException(code: 'x', message: 'no browser', details: 'det');
      expect(
        startSignIn(),
        throwsA(
          isA<AppleSignInException>()
              .having(
                (AppleSignInException e) => e.code,
                'code',
                AppleSignInErrorCode.authorizationFailed,
              )
              .having((AppleSignInException e) => e.message, 'message', 'no browser')
              .having((AppleSignInException e) => e.details, 'details', 'det'),
        ),
      );
    });

    test('PlatformException without message gets a default message', () {
      nativeHandler = (MethodCall call) => throw PlatformException(code: 'x');
      expect(
        startSignIn(),
        throwsA(
          isA<AppleSignInException>().having(
            (AppleSignInException e) => e.message,
            'message',
            contains('failed to launch'),
          ),
        ),
      );
    });

    testWidgets('times out after five minutes with canceled', (WidgetTester tester) async {
      final Future<AppleCredential> future = startSignIn();
      final Future<void> check = expectLater(future, _throwsCode(AppleSignInErrorCode.canceled));
      await tester.pump();
      await tester.pump(const Duration(minutes: 4, seconds: 59));
      await tester.pump(const Duration(seconds: 2));
      await check;
    });
  });

  group('handleCallback', () {
    Future<AppleCredential> pending() => startSignIn();

    test('is ignored when nothing is pending', () {
      expect(() => impl.handleCallback(_callback({'state': 'st'})), returnsNormally);
    });

    test('is ignored when config was cleared', () async {
      final Future<AppleCredential> future = pending();
      await flush();
      impl.config = null;
      impl.handleCallback(_callback({'state': 'st', 'code': 'c'}));
      impl.config = _config;
      impl.cancel();
      await expectLater(future, _throwsCode(AppleSignInErrorCode.canceled));
    });

    test('a null callbackHost accepts any host', () async {
      impl.config = const AppleSignInAndroidConfig(
        serviceId: 's',
        redirectUri: 'https://r',
        callbackScheme: 'com.example.app',
      );
      final Future<AppleCredential> future = pending();
      await flush();
      impl.handleCallback(_callback({'state': 'st', 'code': 'c'}, host: 'anything'));
      expect((await future).authorizationCode, 'c');
    });

    test('non-cancel Apple errors are authorizationFailed', () async {
      final Future<AppleCredential> future = pending();
      await flush();
      impl.handleCallback(_callback({'state': 'st', 'error': 'invalid_request'}));
      await expectLater(
        future,
        throwsA(
          isA<AppleSignInException>()
              .having(
                (AppleSignInException e) => e.code,
                'code',
                AppleSignInErrorCode.authorizationFailed,
              )
              .having(
                (AppleSignInException e) => e.message,
                'message',
                contains('invalid_request'),
              ),
        ),
      );
    });

    test('state check happens before Apple error handling', () async {
      final Future<AppleCredential> future = pending();
      await flush();
      impl.handleCallback(_callback({'state': 'forged', 'error': 'user_cancelled_authorize'}));
      await expectLater(future, _throwsCode(AppleSignInErrorCode.authorizationFailed));
    });

    test('missing state is rejected', () async {
      final Future<AppleCredential> future = pending();
      await flush();
      impl.handleCallback(_callback({'code': 'c'}));
      await expectLater(future, _throwsCode(AppleSignInErrorCode.authorizationFailed));
    });

    test('accepts auth_code and authorization_code aliases', () async {
      Future<AppleCredential> future = pending();
      await flush();
      impl.handleCallback(_callback({'state': 'st', 'auth_code': 'a1'}));
      expect((await future).authorizationCode, 'a1');

      future = pending();
      await flush();
      impl.handleCallback(_callback({'state': 'st', 'authorization_code': 'a2'}));
      expect((await future).authorizationCode, 'a2');
    });

    test('derives the user identifier from the id_token sub claim', () async {
      final Future<AppleCredential> future = pending();
      await flush();
      final String token = _idToken({'sub': 'apple-sub'});
      impl.handleCallback(_callback({'state': 'st', 'id_token': token}));
      final AppleCredential c = await future;
      expect(c.userIdentifier, 'apple-sub');
      expect(c.identityToken, token);
      expect(c.authorizationCode, isNull);
      expect(c.realUserStatus, AppleRealUserStatus.unsupported);
      expect(c.authorizedScopes, isEmpty);
    });

    test('explicit user_identifier wins over the token sub', () async {
      final Future<AppleCredential> future = pending();
      await flush();
      impl.handleCallback(
        _callback({
          'state': 'st',
          'user_identifier': 'explicit',
          'id_token': _idToken({'sub': 'other'}),
        }),
      );
      expect((await future).userIdentifier, 'explicit');
    });

    test('a user_identifier alone is a valid payload', () async {
      final Future<AppleCredential> future = pending();
      await flush();
      impl.handleCallback(_callback({'state': 'st', 'user_identifier': 'only'}));
      expect((await future).userIdentifier, 'only');
    });

    test('malformed id_tokens yield an empty identifier but still succeed', () async {
      for (final token in <String>[
        'not-a-jwt',
        'a.%%%.c',
        'a.${base64Url.encode(utf8.encode('[1]'))}.c',
        _idToken({'no': 'sub'}),
      ]) {
        final Future<AppleCredential> future = pending();
        await flush();
        impl.handleCallback(_callback({'state': 'st', 'id_token': token}));
        final AppleCredential c = await future;
        expect(c.userIdentifier, '', reason: token);
        expect(c.identityToken, token);
      }
    });

    test('parses every name part and email from the user JSON', () async {
      final Future<AppleCredential> future = pending();
      await flush();
      impl.handleCallback(
        _callback({
          'state': 'st',
          'code': 'c',
          'user': jsonEncode({
            'email': 'json@example.com',
            'name': {
              'firstName': 'Ada',
              'lastName': 'Lovelace',
              'middleName': 'K',
              'namePrefix': 'Countess',
              'nameSuffix': 'III',
              'nickname': 'Ada',
            },
          }),
        }),
      );
      final AppleCredential c = await future;
      expect(c.email, 'json@example.com');
      expect(
        c.name,
        const ApplePersonName(
          givenName: 'Ada',
          familyName: 'Lovelace',
          middleName: 'K',
          namePrefix: 'Countess',
          nameSuffix: 'III',
          nickname: 'Ada',
        ),
      );
    });

    test('the email query parameter wins over the user JSON email', () async {
      final Future<AppleCredential> future = pending();
      await flush();
      impl.handleCallback(
        _callback({
          'state': 'st',
          'code': 'c',
          'email': 'param@example.com',
          'user': jsonEncode({'email': 'json@example.com'}),
        }),
      );
      expect((await future).email, 'param@example.com');
    });

    test('an empty name object results in a null name', () async {
      final Future<AppleCredential> future = pending();
      await flush();
      impl.handleCallback(
        _callback({
          'state': 'st',
          'code': 'c',
          'user': jsonEncode({'name': <String, Object?>{}}),
        }),
      );
      expect((await future).name, isNull);
    });
  });

  group('cancel', () {
    test('without a pending sign-in is a no-op', () {
      expect(() => impl.cancel(), returnsNormally);
    });

    test('completes a pending sign-in with canceled', () async {
      final Future<AppleCredential> future = startSignIn();
      await flush();
      impl.cancel();
      await expectLater(future, _throwsCode(AppleSignInErrorCode.canceled));
    });
  });

  group('native onCallback channel call', () {
    Future<void> sendCallback(Object? arguments) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        impl.channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('onCallback', arguments)),
        (ByteData? data) {},
      );
    }

    test('routes the URI to handleCallback', () async {
      final Future<AppleCredential> future = startSignIn();
      await flush();
      await sendCallback(_callback({'state': 'st', 'code': 'native'}).toString());
      expect((await future).authorizationCode, 'native');
    });

    test('null, unparsable and unrelated calls are ignored', () async {
      final Future<AppleCredential> future = startSignIn();
      await flush();
      await sendCallback(null);
      await sendCallback('http://[bad');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        impl.channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('other')),
        (ByteData? data) {},
      );
      impl.cancel();
      await expectLater(future, _throwsCode(AppleSignInErrorCode.canceled));
    });
  });
}
