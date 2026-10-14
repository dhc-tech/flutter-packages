// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:apple_sign_in_plugin_web/apple_sign_in_plugin_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

const _sdkUrl =
    'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';

const _config = AppleSignInWebConfig(
  serviceId: 'com.example.service',
  redirectUri: 'https://example.com/callback',
);

/// Runs [code] as an inline script so tests can drive a fake `AppleID` SDK.
void _js(String code) {
  final script = web.HTMLScriptElement()..text = code;
  web.document.head!.append(script);
  script.remove();
}

String _b64(Object? m) => base64Url.encode(utf8.encode(jsonEncode(m)));

String _jwt(Map<String, Object?> payload) => '${_b64({'alg': 'none'})}.${_b64(payload)}.sig';

/// Installs a fake SDK whose `signIn` evaluates [signInBody] (a JS expression
/// returning a promise). The global is non-writable so a late real SDK load
/// cannot replace it.
void _installSdk(String signInBody, {String? initThrows}) {
  _js('''
    window.__initCalls = [];
    Object.defineProperty(window, 'AppleID', {
      configurable: true,
      writable: false,
      value: {
        auth: {
          init: function (c) {
            window.__initCalls.push(JSON.stringify(c));
            ${initThrows == null ? '' : "throw new Error('$initThrows');"}
          },
          signIn: function () { return $signInBody; }
        }
      }
    });
  ''');
}

String _response({String? code, String? idToken, String? state, Map<String, Object?>? user}) =>
    jsonEncode(<String, Object?>{
      'authorization': <String, Object?>{'code': code, 'id_token': idToken, 'state': state},
      'user': ?user,
    });

List<Map<String, Object?>> _initCalls() {
  final JSAny? raw = web.window.getProperty<JSAny?>('__initCalls'.toJS);
  final List<JSAny?> items = (raw! as JSArray<JSAny?>).toDart;
  return items
      .map((JSAny? e) => jsonDecode((e! as JSString).toDart) as Map<String, Object?>)
      .toList();
}

int _sdkScriptCount() => web.document.querySelectorAll('script[src="$_sdkUrl"]').length;

/// Starts a sign-in, then simulates the SDK script finishing loading.
Future<AppleCredential> _signIn(
  AppleSignInWebImpl impl, {
  Set<AppleAuthorizationScope> scopes = const {AppleAuthorizationScope.email},
  String? nonce,
  String? state = 'st',
}) {
  final Future<AppleCredential> future = impl.signIn(scopes: scopes, nonce: nonce, state: state);
  _fireSdkEvent('load');
  return future;
}

void _fireSdkEvent(String type) {
  final web.NodeList scripts = web.document.querySelectorAll('script[src="$_sdkUrl"]');
  final web.Node last = scripts.item(scripts.length - 1)!;
  last.dispatchEvent(web.Event(type));
}

Matcher _throwsCode(AppleSignInErrorCode code) =>
    throwsA(isA<AppleSignInException>().having((AppleSignInException e) => e.code, 'code', code));

void main() {
  late AppleSignInWebImpl impl;

  setUp(() {
    impl = AppleSignInWebImpl()..config = _config;
    _installSdk('Promise.resolve(${_response(code: 'c', state: 'st')})');
  });

  group('registration', () {
    test('registerWith installs the web implementation', () {
      final AppleSignInPlatform original = AppleSignInPlatform.instance;
      addTearDown(() => AppleSignInPlatform.instance = original);
      AppleSignInPluginWeb.registerWith();
      expect(AppleSignInPlatform.instance, isA<AppleSignInWebImpl>());
      const AppleSignInPluginWeb();
    });
  });

  group('SDK loading', () {
    test('appends the Apple SDK script with CORS settings', () async {
      final int before = _sdkScriptCount();
      final Future<AppleCredential> future = _signIn(impl);
      expect(_sdkScriptCount(), before + 1);
      final script =
          web.document.querySelectorAll('script[src="$_sdkUrl"]').item(before)!
              as web.HTMLScriptElement;
      expect(script.crossOrigin, 'anonymous');
      expect(script.async, isTrue);
      await future;
    });

    test('is loaded only once per instance', () async {
      await _signIn(impl);
      final int after = _sdkScriptCount();
      await impl.signIn(scopes: {AppleAuthorizationScope.email}, state: 'st');
      expect(_sdkScriptCount(), after);
    });

    test('a load error is networkFailed and a retry loads again', () async {
      final Future<AppleCredential> failing = impl.signIn(
        scopes: {AppleAuthorizationScope.email},
        state: 'st',
      );
      final Future<void> check = expectLater(
        failing,
        _throwsCode(AppleSignInErrorCode.networkFailed),
      );
      _fireSdkEvent('error');
      await check;

      final int before = _sdkScriptCount();
      final Future<AppleCredential> retry = _signIn(impl);
      expect(_sdkScriptCount(), before + 1);
      expect((await retry).authorizationCode, 'c');
    });

    test('duplicate load/error events after completion are ignored', () async {
      final Future<AppleCredential> future = _signIn(impl);
      _fireSdkEvent('load');
      _fireSdkEvent('error');
      expect((await future).authorizationCode, 'c');
    });
  });

  group('validation before loading the SDK', () {
    test('missing config and empty scopes never touch the DOM', () async {
      final int before = _sdkScriptCount();
      await expectLater(
        AppleSignInWebImpl().signIn(scopes: {AppleAuthorizationScope.email}),
        _throwsCode(AppleSignInErrorCode.invalidConfiguration),
      );
      await expectLater(
        impl.signIn(scopes: {}),
        _throwsCode(AppleSignInErrorCode.invalidArguments),
      );
      expect(_sdkScriptCount(), before);
    });

    test('config is checked before scopes', () {
      expect(
        AppleSignInWebImpl().signIn(scopes: {}),
        _throwsCode(AppleSignInErrorCode.invalidConfiguration),
      );
    });
  });

  group('init configuration', () {
    test('passes client id, scopes, redirect, state and popup flag', () async {
      await _signIn(
        impl,
        scopes: {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
        nonce: 'nn',
      );
      expect(_initCalls().single, <String, Object?>{
        'clientId': 'com.example.service',
        'scope': 'email name',
        'redirectURI': 'https://example.com/callback',
        'state': 'st',
        'usePopup': true,
        'nonce': 'nn',
      });
    });

    test('omits nonce when null and forwards usePopup false', () async {
      impl.config = const AppleSignInWebConfig(
        serviceId: 's',
        redirectUri: 'https://r',
        usePopup: false,
      );
      await _signIn(impl);
      final Map<String, Object?> init = _initCalls().single;
      expect(init.containsKey('nonce'), isFalse);
      expect(init['usePopup'], isFalse);
    });

    test('generates a 32-byte random state when none is given', () async {
      _installSdk(
        'Promise.resolve({authorization: {code: "c", state: JSON.parse(window.__initCalls[0]).state}})',
      );
      final AppleCredential c = await _signIn(impl, state: null);
      expect(base64Url.decode(c.state), hasLength(32));
      expect(_initCalls().single['state'], c.state);
    });

    test('an empty-string nonce is still forwarded', () async {
      await _signIn(impl, nonce: '');
      expect(_initCalls().single['nonce'], '');
    });
  });

  group('response parsing', () {
    test('maps the full first-authorization response', () async {
      final String token = _jwt({'sub': 'apple.sub', 'email': 'token@example.com'});
      _installSdk(
        'Promise.resolve(${_response(code: 'code1', idToken: token, state: 'st', user: {
          'email': 'user@example.com',
          'name': {'firstName': 'Ada', 'lastName': 'Lovelace', 'middleName': 'K'},
        })})',
      );
      final AppleCredential c = await _signIn(impl);
      expect(c.userIdentifier, 'apple.sub');
      expect(c.email, 'token@example.com');
      expect(c.identityToken, token);
      expect(c.authorizationCode, 'code1');
      expect(c.state, 'st');
      expect(
        c.name,
        const ApplePersonName(givenName: 'Ada', familyName: 'Lovelace', middleName: 'K'),
      );
      expect(c.authorizedScopes, isEmpty);
      expect(c.realUserStatus, AppleRealUserStatus.unsupported);
    });

    test('falls back to the user object email when the token has none', () async {
      _installSdk(
        'Promise.resolve(${_response(idToken: _jwt({'sub': 's'}), state: 'st', user: {'email': 'user@example.com'})})',
      );
      final AppleCredential c = await _signIn(impl);
      expect(c.email, 'user@example.com');
      expect(c.name, isNull);
    });

    test('subsequent sign-in without a user object has no name', () async {
      _installSdk(
        'Promise.resolve(${_response(idToken: _jwt({'sub': 's', 'email': 'e@x.y'}), state: 'st')})',
      );
      final AppleCredential c = await _signIn(impl);
      expect(c.name, isNull);
      expect(c.email, 'e@x.y');
    });

    test('an empty user name object yields a null name', () async {
      _installSdk(
        'Promise.resolve(${_response(code: 'c', state: 'st', user: {'name': <String, Object?>{}})})',
      );
      expect((await _signIn(impl)).name, isNull);
    });

    test('a missing or malformed id_token yields an empty identifier', () async {
      for (final token in <String?>[
        null,
        'not-a-jwt',
        'a.%%%.c',
        'a.${_b64([1])}.c',
        _jwt({'no': 'sub'}),
      ]) {
        _installSdk('Promise.resolve(${_response(code: 'c', idToken: token, state: 'st')})');
        final AppleCredential c = await _signIn(AppleSignInWebImpl()..config = _config);
        expect(c.userIdentifier, '', reason: '$token');
        expect(c.email, isNull, reason: '$token');
        expect(c.identityToken, token);
      }
    });

    test('a state mismatch is rejected as authorizationFailed', () async {
      _installSdk('Promise.resolve(${_response(code: 'c', state: 'forged')})');
      await expectLater(
        _signIn(impl),
        throwsA(
          isA<AppleSignInException>()
              .having(
                (AppleSignInException e) => e.code,
                'code',
                AppleSignInErrorCode.authorizationFailed,
              )
              .having((AppleSignInException e) => e.message, 'message', contains('CSRF')),
        ),
      );
    });

    test('a missing returned state is rejected', () async {
      _installSdk('Promise.resolve(${_response(code: 'c')})');
      await expectLater(_signIn(impl), _throwsCode(AppleSignInErrorCode.authorizationFailed));
    });

    test('a response without an authorization object is authorizationFailed', () async {
      _installSdk('Promise.resolve({})');
      await expectLater(_signIn(impl), _throwsCode(AppleSignInErrorCode.authorizationFailed));
    });
  });

  group('SDK errors', () {
    for (final message in <String>[
      'user_cancelled_authorize',
      'popup_closed_by_user',
      'The user CANCELLED it',
    ]) {
      test('an Error mentioning "$message" is canceled', () async {
        _installSdk('Promise.reject(new Error("$message"))');
        await expectLater(_signIn(impl), _throwsCode(AppleSignInErrorCode.canceled));
      });
    }

    test('init throwing a cancel error is canceled', () async {
      _installSdk('Promise.resolve({})', initThrows: 'popup_closed_by_user');
      await expectLater(_signIn(impl), _throwsCode(AppleSignInErrorCode.canceled));
    });

    test('other errors become authorizationFailed with the cause', () async {
      _installSdk('Promise.reject(new Error("invalid_client"))');
      await expectLater(
        _signIn(impl),
        throwsA(
          isA<AppleSignInException>()
              .having(
                (AppleSignInException e) => e.code,
                'code',
                AppleSignInErrorCode.authorizationFailed,
              )
              .having((AppleSignInException e) => e.message, 'message', contains('invalid_client')),
        ),
      );
    });

    test('Apple rejects with a plain {error} object (the SDK real shape)', () async {
      _installSdk('Promise.reject({error: "popup_closed_by_user"})');
      await expectLater(_signIn(impl), _throwsCode(AppleSignInErrorCode.canceled));
    });
  });

  test('repeated sign-ins reuse the instance and each call re-initialises the SDK', () async {
    await _signIn(impl);
    await impl.signIn(scopes: {AppleAuthorizationScope.email}, state: 'st');
    expect(_initCalls(), hasLength(2));
  });
}
