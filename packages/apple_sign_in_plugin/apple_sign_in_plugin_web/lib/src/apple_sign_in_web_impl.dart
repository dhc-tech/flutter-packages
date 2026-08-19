// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

// ---------------------------------------------------------------------------
// JS interop — Apple ID Auth SDK
// ---------------------------------------------------------------------------

@JS('AppleID')
external _AppleIDNamespace get _appleID;

@JS()
@staticInterop
class _AppleIDNamespace {}

extension on _AppleIDNamespace {
  external _AppleIDAuth get auth;
}

@JS()
@staticInterop
class _AppleIDAuth {}

extension on _AppleIDAuth {
  external void init(JSObject config);
  external JSPromise<JSObject> signIn();
}

@JS()
@staticInterop
class _AppleSignInResponse {}

extension on _AppleSignInResponse {
  external _AppleIDAuthorizationResponse get authorization;
  external _AppleIDUser? get user;
}

@JS()
@staticInterop
class _AppleIDAuthorizationResponse {}

extension on _AppleIDAuthorizationResponse {
  external String? get code;
  @JS('id_token')
  external String? get idToken;
  external String? get state;
}

@JS()
@staticInterop
class _AppleIDUser {}

extension on _AppleIDUser {
  external String? get email;
  external _AppleIDName? get name;
}

@JS()
@staticInterop
class _AppleIDName {}

extension on _AppleIDName {
  external String? get firstName;
  external String? get lastName;
  external String? get middleName;
}

/// The Flutter Web implementation of [AppleSignInPlatform].
///
/// Uses Apple's official **Sign in with Apple JS SDK**
/// (`https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js`).
class AppleSignInWebImpl extends AppleSignInPlatform {
  static const String _kSdkUrl =
      'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';

  /// Configuration for the web flow.
  // ignore: use_setters_to_change_properties
  AppleSignInWebConfig? config;

  bool _sdkLoaded = false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AppleCredential> signIn({
    required Set<AppleAuthorizationScope> scopes,
    String? nonce,
    String? state,
  }) async {
    final AppleSignInWebConfig? currentConfig = config;
    if (currentConfig == null) {
      throw const AppleSignInException(
        AppleSignInErrorCode.invalidConfiguration,
        'config must be set before signIn(). '
        'Provide an AppleSignInWebConfig with your Apple Services ID and '
        'redirect URI. See the README for setup instructions.',
      );
    }
    if (scopes.isEmpty) {
      throw const AppleSignInException(
        AppleSignInErrorCode.invalidArguments,
        'At least one AppleAuthorizationScope must be requested.',
      );
    }

    await _ensureSdkLoaded();

    final String effectiveState = state ?? _generateSecureRandom(32);
    final String scopeString =
        scopes.map((AppleAuthorizationScope s) => s.restApiValue).join(' ');

    final initConfig = <String, Object?>{
      'clientId': currentConfig.serviceId,
      'scope': scopeString,
      'redirectURI': currentConfig.redirectUri,
      'state': effectiveState,
      'usePopup': currentConfig.usePopup,
    };
    if (nonce != null) {
      initConfig['nonce'] = nonce;
    }

    try {
      _appleID.auth.init(initConfig.jsify()! as JSObject);

      final JSObject response = await _appleID.auth.signIn().toDart;
      final typed = response as _AppleSignInResponse;
      final _AppleIDAuthorizationResponse authorization = typed.authorization;

      final String? returnedCode = authorization.code;
      final String? returnedIdToken = authorization.idToken;
      final String? returnedState = authorization.state;

      if (returnedState != effectiveState) {
        throw const AppleSignInException(
          AppleSignInErrorCode.authorizationFailed,
          'Apple Sign-In response state mismatch. The response was rejected '
          'to protect against CSRF attacks.',
        );
      }

      // Name object is provided only on first authorization.
      // Email is provided in the user object on first authorization and
      // in the identity token JWT claims on both first and subsequent authorizations.
      ApplePersonName? name;
      String? email = _extractEmailFromIdToken(returnedIdToken);
      final _AppleIDUser? userInfo = typed.user;
      if (userInfo != null) {
        email ??= userInfo.email;
        final _AppleIDName? nameInfo = userInfo.name;
        if (nameInfo != null) {
          final n = ApplePersonName(
            givenName: nameInfo.firstName,
            familyName: nameInfo.lastName,
            middleName: nameInfo.middleName,
          );
          name = n.isEmpty ? null : n;
        }
      }

      return AppleCredential(
        userIdentifier: _extractSubFromIdToken(returnedIdToken) ?? '',
        email: email,
        name: name,
        identityToken: returnedIdToken,
        authorizationCode: returnedCode,
        state: returnedState ?? '',
        authorizedScopes: const <AppleAuthorizationScope>{},
        realUserStatus: AppleRealUserStatus.unsupported,
      );
    } on AppleSignInException {
      rethrow;
    } catch (e) {
      final String errorString = e.toString().toLowerCase();
      if (errorString.contains('user_cancelled') ||
          errorString.contains('cancel') ||
          errorString.contains('popup_closed')) {
        throw const AppleSignInException(
          AppleSignInErrorCode.canceled,
          'Sign in with Apple was canceled by the user.',
        );
      }
      throw AppleSignInException(
        AppleSignInErrorCode.authorizationFailed,
        'Apple Sign-In JS SDK returned an error: $e',
      );
    }
  }

  @override
  Future<AppleCredentialState> getCredentialState(
    String userIdentifier,
  ) async {
    throw const AppleSignInException(
      AppleSignInErrorCode.platformNotSupported,
      'getCredentialState() is not available on Web. Apple does not expose '
      'a native ASAuthorizationAppleIDProvider credential-state API for '
      'web applications. Verify token validity on your backend.',
    );
  }

  @override
  Stream<void> get onCredentialRevoked => const Stream<void>.empty();

  Future<void> _ensureSdkLoaded() async {
    if (_sdkLoaded) {
      return;
    }

    final completer = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = _kSdkUrl
      ..crossOrigin = 'anonymous'
      ..async = true;

    script.onload = (web.Event _) {
      _sdkLoaded = true;
      if (!completer.isCompleted) {
        completer.complete();
      }
    }.toJS;
    script.onerror = (web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          const AppleSignInException(
            AppleSignInErrorCode.networkFailed,
            'Failed to load the Apple Sign in with Apple JS SDK from Apple CDN.',
          ),
        );
      }
    }.toJS;

    web.document.head!.append(script);
    await completer.future;
  }

  String? _extractSubFromIdToken(String? idToken) {
    if (idToken == null) {
      return null;
    }
    try {
      final List<String> parts = idToken.split('.');
      if (parts.length != 3) {
        return null;
      }
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      return payload['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _extractEmailFromIdToken(String? idToken) {
    if (idToken == null) {
      return null;
    }
    try {
      final List<String> parts = idToken.split('.');
      if (parts.length != 3) {
        return null;
      }
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      return payload['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _generateSecureRandom(int byteCount) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }
}

/// Configuration for the Web Apple Sign-In flow.
@immutable
class AppleSignInWebConfig {
  /// Creates an [AppleSignInWebConfig].
  const AppleSignInWebConfig({
    required this.serviceId,
    required this.redirectUri,
    this.usePopup = true,
  });

  /// Your Apple Services ID (`client_id` for the web flow).
  final String serviceId;

  /// The return URL registered in your Apple Services ID configuration.
  final String redirectUri;

  /// Whether to use a popup window for authentication.
  final bool usePopup;
}
