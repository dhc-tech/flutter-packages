// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:apple_sign_in_plugin_linux/apple_sign_in_plugin_linux.dart';
import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = AppleSignInDesktopConfig(
  serviceId: 'com.example.service',
  redirectUri: 'https://api.example.com/auth/apple/callback',
  callbackScheme: 'com.example.app',
  callbackHost: 'apple-callback',
);

String _b64(Object? m) => base64Url.encode(utf8.encode(jsonEncode(m)));

String _idToken(Map<String, Object?> payload) => '${_b64({'alg': 'none'})}.${_b64(payload)}.sig';

String _callback(Map<String, String> params) =>
    Uri(scheme: 'com.example.app', host: 'apple-callback', queryParameters: params).toString();

Matcher _throwsCode(AppleSignInErrorCode code) =>
    throwsA(isA<AppleSignInException>().having((AppleSignInException e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppleSignInLinuxImpl impl;
  late List<MethodCall> log;
  Object? Function(MethodCall call) native = (MethodCall call) => null;

  setUp(() {
    impl = AppleSignInLinuxImpl()..config = _config;
    log = <MethodCall>[];
    native = (MethodCall call) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      impl.channel,
      (MethodCall call) async {
        log.add(call);
        return native(call);
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      impl.channel,
      null,
    );
  });

  /// Makes native `signIn` answer with [callbackUrl].
  void nativeReturns(String callbackUrl) {
    native = (MethodCall call) => <String, Object?>{'callbackUrl': callbackUrl};
  }

  Future<AppleCredential> signIn({String? nonce, String? state = 'st'}) =>
      impl.signIn(scopes: {AppleAuthorizationScope.email}, nonce: nonce, state: state);

  test('registerWith installs the linux implementation', () {
    final AppleSignInPlatform original = AppleSignInPlatform.instance;
    addTearDown(() => AppleSignInPlatform.instance = original);
    AppleSignInPluginLinux.registerWith();
    expect(AppleSignInPlatform.instance, isA<AppleSignInLinuxImpl>());
  });

  test('uses the platform specific channel name', () {
    expect(impl.channel.name, 'apple_sign_in_plugin_linux');
  });

  group('isAvailable', () {
    test('forwards a false answer', () async {
      native = (MethodCall call) => false;
      expect(await impl.isAvailable(), isFalse);
    });

    test('null answer defaults to true', () async {
      expect(await impl.isAvailable(), isTrue);
    });

    test('PlatformException defaults to true', () async {
      native = (MethodCall call) => throw PlatformException(code: 'x');
      expect(await impl.isAvailable(), isTrue);
    });
  });

  group('signIn request', () {
    test('sends the authorize URL, state and callback settings to native', () async {
      nativeReturns(_callback({'state': 'st', 'code': 'c'}));
      await impl.signIn(
        scopes: {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
        nonce: 'nn',
        state: 'st',
      );
      final args = log.single.arguments as Map<Object?, Object?>;
      expect(args['state'], 'st');
      expect(args['callbackScheme'], 'com.example.app');
      expect(args['callbackHost'], 'apple-callback');
      final Uri url = Uri.parse(args['url']! as String);
      expect(url.origin, 'https://appleid.apple.com');
      expect(url.path, '/auth/authorize');
      expect(url.queryParameters, <String, String>{
        'client_id': 'com.example.service',
        'redirect_uri': 'https://api.example.com/auth/apple/callback',
        'response_type': 'code id_token',
        'scope': 'email name',
        'response_mode': 'form_post',
        'state': 'st',
        'nonce': 'nn',
      });
    });

    test('omits the nonce and sends a null host when not configured', () async {
      impl.config = const AppleSignInDesktopConfig(
        serviceId: 's',
        redirectUri: 'https://r',
        callbackScheme: 'com.example.app',
      );
      nativeReturns(_callback({'state': 'st', 'code': 'c'}));
      await signIn();
      final args = log.single.arguments as Map<Object?, Object?>;
      expect(args['callbackHost'], isNull);
      expect(Uri.parse(args['url']! as String).queryParameters.containsKey('nonce'), isFalse);
    });

    test('generates a 32-byte random state when none is given', () async {
      native = (MethodCall call) {
        final state = (call.arguments as Map<Object?, Object?>)['state']! as String;
        return <String, Object?>{
          'callbackUrl': _callback({'state': state, 'code': 'c'}),
        };
      };
      final AppleCredential c = await signIn(state: null);
      expect(base64Url.decode(c.state), hasLength(32));
    });

    test('validates config before scopes and never calls native', () async {
      await expectLater(
        impl.signIn(scopes: <AppleAuthorizationScope>{}),
        _throwsCode(AppleSignInErrorCode.invalidArguments),
      );
      impl.config = null;
      await expectLater(
        impl.signIn(scopes: <AppleAuthorizationScope>{}),
        _throwsCode(AppleSignInErrorCode.invalidConfiguration),
      );
      expect(log, isEmpty);
    });
  });

  group('native response handling', () {
    test('a non-map response is invalidResponse', () {
      native = (MethodCall call) => 'oops';
      expect(signIn(), _throwsCode(AppleSignInErrorCode.invalidResponse));
    });

    test('a null response is invalidResponse', () {
      expect(signIn(), _throwsCode(AppleSignInErrorCode.invalidResponse));
    });

    test('a map without callbackUrl is invalidResponse', () {
      native = (MethodCall call) => <String, Object?>{'other': 1};
      expect(signIn(), _throwsCode(AppleSignInErrorCode.invalidResponse));
    });

    test('maps every native PlatformException code', () async {
      const expected = <String, AppleSignInErrorCode>{
        'canceled': AppleSignInErrorCode.canceled,
        'already_in_progress': AppleSignInErrorCode.alreadyInProgress,
        'invalid_arguments': AppleSignInErrorCode.invalidArguments,
        'invalid_configuration': AppleSignInErrorCode.invalidConfiguration,
        'network_failed': AppleSignInErrorCode.networkFailed,
        'authorization_failed': AppleSignInErrorCode.authorizationFailed,
        'whatever': AppleSignInErrorCode.authorizationFailed,
      };
      for (final MapEntry<String, AppleSignInErrorCode> e in expected.entries) {
        native = (MethodCall call) =>
            throw PlatformException(code: e.key, message: 'm', details: 'd');
        await expectLater(
          signIn(),
          throwsA(
            isA<AppleSignInException>()
                .having((AppleSignInException x) => x.code, 'code', e.value)
                .having((AppleSignInException x) => x.message, 'message', 'm')
                .having((AppleSignInException x) => x.details, 'details', 'd'),
          ),
        );
      }
    });

    test('a PlatformException without a message gets a default message', () {
      native = (MethodCall call) => throw PlatformException(code: 'canceled');
      expect(
        signIn(),
        throwsA(
          isA<AppleSignInException>().having(
            (AppleSignInException e) => e.message,
            'message',
            'Native authorization failed.',
          ),
        ),
      );
    });
  });

  group('callback parsing', () {
    Future<AppleCredential> withCallback(Map<String, String> params) {
      nativeReturns(_callback(params));
      return signIn();
    }

    test('a state mismatch or missing state is rejected before anything else', () async {
      await expectLater(
        withCallback({'state': 'forged', 'error': 'user_cancelled_authorize'}),
        _throwsCode(AppleSignInErrorCode.authorizationFailed),
      );
      await expectLater(
        withCallback({'code': 'c'}),
        _throwsCode(AppleSignInErrorCode.authorizationFailed),
      );
    });

    test('user_cancelled_authorize is canceled; other errors are failures', () async {
      await expectLater(
        withCallback({'state': 'st', 'error': 'user_cancelled_authorize'}),
        _throwsCode(AppleSignInErrorCode.canceled),
      );
      await expectLater(
        withCallback({'state': 'st', 'error': 'invalid_request'}),
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

    test('a callback without any payload is invalidResponse', () {
      expect(withCallback({'state': 'st'}), _throwsCode(AppleSignInErrorCode.invalidResponse));
    });

    test('accepts the code aliases', () async {
      expect((await withCallback({'state': 'st', 'auth_code': 'a'})).authorizationCode, 'a');
      expect(
        (await withCallback({'state': 'st', 'authorization_code': 'b'})).authorizationCode,
        'b',
      );
      expect(
        (await withCallback({'state': 'st', 'code': 'c', 'auth_code': 'x'})).authorizationCode,
        'c',
      );
    });

    test('identifier comes from user_identifier first, then the token sub', () async {
      final String token = _idToken({'sub': 'tok-sub', 'email': 'tok@example.com'});
      final AppleCredential fromToken = await withCallback({'state': 'st', 'id_token': token});
      expect(fromToken.userIdentifier, 'tok-sub');
      expect(fromToken.email, 'tok@example.com');
      expect(fromToken.identityToken, token);

      final AppleCredential explicit = await withCallback({
        'state': 'st',
        'id_token': token,
        'user_identifier': 'explicit',
      });
      expect(explicit.userIdentifier, 'explicit');

      expect((await withCallback({'state': 'st', 'user_identifier': 'u'})).userIdentifier, 'u');
    });

    test('malformed id_tokens give an empty identifier and no email', () async {
      for (final token in <String>[
        'not-a-jwt',
        'a.%%%.c',
        'a.${_b64([1])}.c',
        _idToken({'other': 'x'}),
      ]) {
        final AppleCredential c = await withCallback({'state': 'st', 'id_token': token});
        expect(c.userIdentifier, '', reason: token);
        expect(c.email, isNull, reason: token);
      }
    });

    test('email precedence is query param, token claim, then user JSON', () async {
      final String token = _idToken({'sub': 's', 'email': 'tok@example.com'});
      final String user = jsonEncode({'email': 'json@example.com'});
      expect(
        (await withCallback({'state': 'st', 'email': 'q@example.com', 'id_token': token})).email,
        'q@example.com',
      );
      expect(
        (await withCallback({'state': 'st', 'id_token': token, 'user': user})).email,
        'tok@example.com',
      );
      expect(
        (await withCallback({'state': 'st', 'code': 'c', 'user': user})).email,
        'json@example.com',
      );
    });

    test('parses every name part from the user JSON', () async {
      final AppleCredential c = await withCallback({
        'state': 'st',
        'code': 'c',
        'user': jsonEncode({
          'name': {
            'firstName': 'Ada',
            'lastName': 'Lovelace',
            'middleName': 'K',
            'namePrefix': 'Countess',
            'nameSuffix': 'III',
            'nickname': 'A',
          },
        }),
      });
      expect(
        c.name,
        const ApplePersonName(
          givenName: 'Ada',
          familyName: 'Lovelace',
          middleName: 'K',
          namePrefix: 'Countess',
          nameSuffix: 'III',
          nickname: 'A',
        ),
      );
      expect(c.state, 'st');
      expect(c.authorizedScopes, isEmpty);
      expect(c.realUserStatus, AppleRealUserStatus.unsupported);
    });

    test('an empty name object gives a null name', () async {
      final AppleCredential c = await withCallback({
        'state': 'st',
        'code': 'c',
        'user': jsonEncode({'name': <String, Object?>{}}),
      });
      expect(c.name, isNull);
    });

    test('malformed user JSON is tolerated', () async {
      for (final user in <String>['{not json', '[1,2]', '"str"', '']) {
        final AppleCredential c = await withCallback({'state': 'st', 'code': 'c', 'user': user});
        expect(c.name, isNull, reason: user);
        expect(c.authorizationCode, 'c');
      }
    });
  });

  group('handleCallback', () {
    test('forwards the URL and returns the native answer', () async {
      native = (MethodCall call) => true;
      final Uri uri = Uri.parse('com.example.app://apple-callback?code=1&state=s');
      expect(await impl.handleCallback(uri), isTrue);
      expect(log.single.method, 'onNativeCallback');
      expect(log.single.arguments, <String, Object?>{'callbackUrl': uri.toString()});
    });

    test('false, null and PlatformException all report not accepted', () async {
      final Uri uri = Uri.parse('com.example.app://x');
      native = (MethodCall call) => false;
      expect(await impl.handleCallback(uri), isFalse);
      native = (MethodCall call) => null;
      expect(await impl.handleCallback(uri), isFalse);
      native = (MethodCall call) => throw PlatformException(code: 'x');
      expect(await impl.handleCallback(uri), isFalse);
    });
  });

  group('cancel', () {
    test('invokes cancelSignIn', () async {
      native = (MethodCall call) => true;
      await impl.cancel();
      expect(log.single.method, 'cancelSignIn');
    });

    test('swallows PlatformException', () async {
      native = (MethodCall call) => throw PlatformException(code: 'x');
      await expectLater(impl.cancel(), completes);
    });
  });

  test('getCredentialState is platformNotSupported for any identifier', () async {
    for (final id in <String>['', ' ', 'x' * 5000]) {
      await expectLater(
        impl.getCredentialState(id),
        _throwsCode(AppleSignInErrorCode.platformNotSupported),
      );
    }
    expect(await impl.onCredentialRevoked.toList(), isEmpty);
  });
}
