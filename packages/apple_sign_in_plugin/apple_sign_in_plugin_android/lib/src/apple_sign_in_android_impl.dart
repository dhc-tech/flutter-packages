// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android implementation of [AppleSignInPlatform].
///
/// Communicates through [MethodChannel] with the native Kotlin plugin layer,
/// which invokes Custom Tabs and intercepts OAuth callbacks via modern Android
/// intent lifecycle handling.
class AppleSignInAndroidImpl extends AppleSignInPlatform {
  /// Constructs [AppleSignInAndroidImpl] and initializes callback handling.
  AppleSignInAndroidImpl() {
    channel.setMethodCallHandler(_handleMethodCall);
  }

  /// The method channel used to communicate with the native Android plugin.
  @visibleForTesting
  final MethodChannel channel =
      const MethodChannel('apple_sign_in_plugin_android');

  static const String _kAuthorizeUrl =
      'https://appleid.apple.com/auth/authorize';

  static const Duration _kCallbackTimeout = Duration(minutes: 5);

  Completer<AppleCredential>? _pendingCompleter;
  String? _pendingState;
  Timer? _timeoutTimer;

  bool get _isInProgress =>
      _pendingCompleter != null && !_pendingCompleter!.isCompleted;

  /// The Android OAuth flow configuration.
  // ignore: use_setters_to_change_properties
  AppleSignInAndroidConfig? config;

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onCallback') {
      final uriString = call.arguments as String?;
      if (uriString != null) {
        final Uri? parsedUri = Uri.tryParse(uriString);
        if (parsedUri != null) {
          handleCallback(parsedUri);
        }
      }
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final bool? result = await channel.invokeMethod<bool>('isAvailable');
      return result ?? true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Future<AppleCredential> signIn({
    required Set<AppleAuthorizationScope> scopes,
    String? nonce,
    String? state,
  }) async {
    final AppleSignInAndroidConfig? currentConfig = config;
    if (currentConfig == null) {
      throw const AppleSignInException(
        AppleSignInErrorCode.invalidConfiguration,
        'AppleSignInAndroidImpl.config must be set before calling signIn(). '
        'Provide an AppleSignInAndroidConfig with your Apple Services ID '
        'and redirect URI. See the README for setup instructions.',
      );
    }
    if (scopes.isEmpty) {
      throw const AppleSignInException(
        AppleSignInErrorCode.invalidArguments,
        'At least one AppleAuthorizationScope must be requested.',
      );
    }
    if (_isInProgress) {
      throw const AppleSignInException(
        AppleSignInErrorCode.alreadyInProgress,
        'A Sign in with Apple request is already in progress.',
      );
    }

    final String effectiveState = state ?? _generateSecureRandom(32);
    _pendingState = effectiveState;

    final completer = Completer<AppleCredential>();
    _pendingCompleter = completer;

    final Uri uri = _buildAuthorizationUri(
      config: currentConfig,
      scopes: scopes,
      nonce: nonce,
      state: effectiveState,
    );

    try {
      final bool? launched = await channel.invokeMethod<bool>(
        'launchAuthUrl',
        <String, Object?>{'url': uri.toString()},
      );
      if (launched != true) {
        _cleanUp();
        throw const AppleSignInException(
          AppleSignInErrorCode.authorizationFailed,
          'Native Android channel could not launch Custom Tabs.',
        );
      }
    } on PlatformException catch (e) {
      _cleanUp();
      throw AppleSignInException(
        AppleSignInErrorCode.authorizationFailed,
        e.message ?? 'Native Android channel failed to launch authorization URL.',
        e.details,
      );
    }

    _timeoutTimer = Timer(_kCallbackTimeout, () {
      if (!completer.isCompleted) {
        _cleanUp();
        completer.completeError(
          const AppleSignInException(
            AppleSignInErrorCode.canceled,
            'Sign in with Apple timed out waiting for the browser callback.',
          ),
        );
      }
    });

    return completer.future;
  }

  /// Handles and validates incoming callback URI from the OAuth flow.
  void handleCallback(Uri callbackUri) {
    final Completer<AppleCredential>? completer = _pendingCompleter;
    final String? expectedState = _pendingState;
    final AppleSignInAndroidConfig? currentConfig = config;

    if (completer == null || completer.isCompleted || expectedState == null || currentConfig == null) {
      return;
    }

    // 1. Strict Scheme & Host Validation
    if (callbackUri.scheme != currentConfig.callbackScheme) {
      _cleanUp();
      completer.completeError(
        const AppleSignInException(
          AppleSignInErrorCode.authorizationFailed,
          'Apple Sign-In callback URI scheme mismatch.',
        ),
      );
      return;
    }

    if (currentConfig.callbackHost != null && callbackUri.host != currentConfig.callbackHost) {
      _cleanUp();
      completer.completeError(
        const AppleSignInException(
          AppleSignInErrorCode.authorizationFailed,
          'Apple Sign-In callback URI host mismatch.',
        ),
      );
      return;
    }

    final Map<String, String> params = callbackUri.queryParameters;

    // 2. Strict State (CSRF) Validation
    final String? returnedState = params['state'];
    if (returnedState == null || returnedState != expectedState) {
      _cleanUp();
      completer.completeError(
        const AppleSignInException(
          AppleSignInErrorCode.authorizationFailed,
          'Apple Sign-In callback state mismatch. The response was rejected '
          'to protect against CSRF attacks.',
        ),
      );
      return;
    }

    // 3. Apple Error Handling
    final String? errorParam = params['error'];
    if (errorParam != null) {
      _cleanUp();
      final AppleSignInErrorCode code =
          errorParam == 'user_cancelled_authorize'
              ? AppleSignInErrorCode.canceled
              : AppleSignInErrorCode.authorizationFailed;
      completer.completeError(
        AppleSignInException(
          code,
          'Apple Sign-In returned an error: $errorParam',
        ),
      );
      return;
    }

    // 4. Authorization code / Opaque Callback Parameter Validation
    final String? code = params['code'] ?? params['auth_code'] ?? params['authorization_code'];
    final String? idToken = params['id_token'];
    final String? userIdentifier = params['user_identifier'] ?? _extractSubFromIdToken(idToken);

    if (code == null && idToken == null && userIdentifier == null) {
      _cleanUp();
      completer.completeError(
        const AppleSignInException(
          AppleSignInErrorCode.invalidResponse,
          'Apple Sign-In callback was missing authorization payload.',
        ),
      );
      return;
    }

    // 5. Parse optional user JSON (First authorization only)
    ApplePersonName? name;
    String? email = params['email'];
    try {
      final String? userJson = params['user'];
      if (userJson != null) {
        final user =
            jsonDecode(userJson) as Map<String, dynamic>;
        email ??= user['email'] as String?;
        final nameMap =
            user['name'] as Map<String, dynamic>?;
        if (nameMap != null) {
          final n = ApplePersonName(
            givenName: nameMap['firstName'] as String?,
            familyName: nameMap['lastName'] as String?,
            middleName: nameMap['middleName'] as String?,
            namePrefix: nameMap['namePrefix'] as String?,
            nameSuffix: nameMap['nameSuffix'] as String?,
            nickname: nameMap['nickname'] as String?,
          );
          name = n.isEmpty ? null : n;
        }
      }
    } catch (_) {
      // Non-fatal: malformed user JSON.
    }

    final credential = AppleCredential(
      userIdentifier: userIdentifier ?? '',
      email: email,
      name: name,
      identityToken: idToken,
      authorizationCode: code,
      state: returnedState,
      authorizedScopes: const <AppleAuthorizationScope>{},
      realUserStatus: AppleRealUserStatus.unsupported,
    );

    _cleanUp();
    completer.complete(credential);
  }

  /// Cancels any in-progress sign-in.
  void cancel() {
    final Completer<AppleCredential>? completer = _pendingCompleter;
    if (completer != null && !completer.isCompleted) {
      _cleanUp();
      completer.completeError(
        const AppleSignInException(
          AppleSignInErrorCode.canceled,
          'Sign in with Apple was canceled.',
        ),
      );
    }
  }

  @override
  Future<AppleCredentialState> getCredentialState(
    String userIdentifier,
  ) async {
    throw const AppleSignInException(
      AppleSignInErrorCode.platformNotSupported,
      'getCredentialState() is not available on Android. Apple does not '
      'expose a native ASAuthorizationAppleIDProvider credential-state API for '
      'non-Apple platforms. Verify token validity on your backend.',
    );
  }

  @override
  Stream<void> get onCredentialRevoked => const Stream<void>.empty();

  /// Injects a pending state and completer for unit testing.
  @visibleForTesting
  void primeForTest(Completer<AppleCredential> completer, String state) {
    _pendingCompleter = completer;
    _pendingState = state;
  }

  Uri _buildAuthorizationUri({
    required AppleSignInAndroidConfig config,
    required Set<AppleAuthorizationScope> scopes,
    required String state,
    String? nonce,
  }) {
    final String scopeString =
        scopes.map((AppleAuthorizationScope s) => s.restApiValue).join(' ');
    final params = <String, String>{
      'client_id': config.serviceId,
      'redirect_uri': config.redirectUri,
      'response_type': 'code id_token',
      'scope': scopeString,
      'response_mode': 'form_post',
      'state': state,
    };
    if (nonce != null) {
      params['nonce'] = nonce;
    }
    return Uri.parse(_kAuthorizeUrl).replace(queryParameters: params);
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

  String _generateSecureRandom(int byteCount) {
    final rng = Random.secure();
    final bytes =
        List<int>.generate(byteCount, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  void _cleanUp() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _pendingCompleter = null;
    _pendingState = null;
  }
}

/// Configuration for the Android Apple Sign-In OAuth flow.
@immutable
class AppleSignInAndroidConfig {
  /// Creates an [AppleSignInAndroidConfig].
  const AppleSignInAndroidConfig({
    required this.serviceId,
    required this.redirectUri,
    required this.callbackScheme,
    this.callbackHost,
  });

  /// Your Apple Services ID.
  final String serviceId;

  /// The HTTPS backend redirect URI.
  final String redirectUri;

  /// The custom URI scheme.
  final String callbackScheme;

  /// Optional expected callback host (e.g. "apple-callback").
  final String? callbackHost;
}
