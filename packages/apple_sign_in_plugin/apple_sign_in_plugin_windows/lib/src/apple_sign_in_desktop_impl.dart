// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Base class for Windows and Linux Apple Sign-In implementations.
///
/// Communicates through [MethodChannel] with the native C++/GTK platform layers,
/// which own browser invocation, native request lifecycle, timeout handling,
/// and native callback validation.
abstract class AppleSignInDesktopImpl extends AppleSignInPlatform {
  /// Constructs [AppleSignInDesktopImpl] with specific channel name.
  AppleSignInDesktopImpl({required String channelName})
      : channel = MethodChannel(channelName);

  /// The platform method channel.
  @visibleForTesting
  final MethodChannel channel;

  static const String _kAuthorizeUrl =
      'https://appleid.apple.com/auth/authorize';

  /// Configuration for desktop OAuth flow.
  // ignore: use_setters_to_change_properties
  AppleSignInDesktopConfig? config;

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
    final AppleSignInDesktopConfig? currentConfig = config;
    if (currentConfig == null) {
      throw const AppleSignInException(
        AppleSignInErrorCode.invalidConfiguration,
        'config must be set before signIn(). Provide an '
        'AppleSignInDesktopConfig with your Apple Services ID and redirect '
        'URI. See the README for setup instructions.',
      );
    }
    if (scopes.isEmpty) {
      throw const AppleSignInException(
        AppleSignInErrorCode.invalidArguments,
        'At least one AppleAuthorizationScope must be requested.',
      );
    }

    final String effectiveState = state ?? _generateSecureRandom(32);

    final Uri uri = _buildAuthorizationUri(
      config: currentConfig,
      scopes: scopes,
      nonce: nonce,
      state: effectiveState,
    );

    try {
      // Delegate complete authorization request & lifecycle to native C++ channel.
      final dynamic rawResult = await channel.invokeMethod<dynamic>(
        'signIn',
        <String, Object?>{
          'url': uri.toString(),
          'state': effectiveState,
          'callbackScheme': currentConfig.callbackScheme,
          'callbackHost': currentConfig.callbackHost,
        },
      );

      if (rawResult is! Map<dynamic, dynamic>) {
        throw const AppleSignInException(
          AppleSignInErrorCode.invalidResponse,
          'Native channel returned an unexpected response format.',
        );
      }

      final resultMap = Map<String, dynamic>.from(rawResult);
      final callbackUrl = resultMap['callbackUrl'] as String?;
      if (callbackUrl == null) {
        throw const AppleSignInException(
          AppleSignInErrorCode.invalidResponse,
          'Native channel response missing callbackUrl.',
        );
      }

      return _parseCallbackUri(Uri.parse(callbackUrl), effectiveState);
    } on PlatformException catch (e) {
      throw _exceptionFromPlatformException(e);
    }
  }

  /// Ingests an incoming deep-link callback URI into the native plugin channel.
  ///
  /// The host application invokes this method when receiving deep links from
  /// Windows or Linux OS application protocol handlers.
  Future<bool> handleCallback(Uri callbackUri) async {
    try {
      final bool? accepted = await channel.invokeMethod<bool>(
        'onNativeCallback',
        <String, Object?>{'callbackUrl': callbackUri.toString()},
      );
      return accepted ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Cancels any in-progress sign-in at the native level.
  Future<void> cancel() async {
    try {
      await channel.invokeMethod<bool>('cancelSignIn');
    } on PlatformException {
      // Ignore cleanup failures.
    }
  }

  @override
  Future<AppleCredentialState> getCredentialState(
    String userIdentifier,
  ) async {
    throw const AppleSignInException(
      AppleSignInErrorCode.platformNotSupported,
      'getCredentialState() is not available on desktop platforms. Apple '
      'does not expose a native ASAuthorizationAppleIDProvider credential-state API '
      'for non-Apple platforms. Verify token validity on your backend.',
    );
  }

  @override
  Stream<void> get onCredentialRevoked => const Stream<void>.empty();

  Uri _buildAuthorizationUri({
    required AppleSignInDesktopConfig config,
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

  AppleCredential _parseCallbackUri(Uri callbackUri, String expectedState) {
    final Map<String, String> params = callbackUri.queryParameters;

    final String? returnedState = params['state'];
    if (returnedState == null || returnedState != expectedState) {
      throw const AppleSignInException(
        AppleSignInErrorCode.authorizationFailed,
        'Apple Sign-In callback state mismatch. The response was rejected '
        'to protect against CSRF attacks.',
      );
    }

    final String? errorParam = params['error'];
    if (errorParam != null) {
      final AppleSignInErrorCode code = errorParam == 'user_cancelled_authorize'
          ? AppleSignInErrorCode.canceled
          : AppleSignInErrorCode.authorizationFailed;
      throw AppleSignInException(
        code,
        'Apple Sign-In returned an error: $errorParam',
      );
    }

    final String? code = params['code'] ?? params['auth_code'] ?? params['authorization_code'];
    final String? idToken = params['id_token'];
    final String? userIdentifier = params['user_identifier'] ?? _extractSubFromIdToken(idToken);

    if (code == null && idToken == null && userIdentifier == null) {
      throw const AppleSignInException(
        AppleSignInErrorCode.invalidResponse,
        'Apple Sign-In callback was missing authorization payload.',
      );
    }

    ApplePersonName? name;
    String? email = params['email'] ?? _extractEmailFromIdToken(idToken);
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

    return AppleCredential(
      userIdentifier: userIdentifier ?? '',
      email: email,
      name: name,
      identityToken: idToken,
      authorizationCode: code,
      state: returnedState,
      authorizedScopes: const <AppleAuthorizationScope>{},
      realUserStatus: AppleRealUserStatus.unsupported,
    );
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
    final bytes =
        List<int>.generate(byteCount, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  AppleSignInException _exceptionFromPlatformException(PlatformException e) {
    final AppleSignInErrorCode code;
    switch (e.code) {
      case 'canceled':
        code = AppleSignInErrorCode.canceled;
      case 'already_in_progress':
        code = AppleSignInErrorCode.alreadyInProgress;
      case 'invalid_arguments':
        code = AppleSignInErrorCode.invalidArguments;
      case 'invalid_configuration':
        code = AppleSignInErrorCode.invalidConfiguration;
      case 'network_failed':
        code = AppleSignInErrorCode.networkFailed;
      case 'authorization_failed':
      default:
        code = AppleSignInErrorCode.authorizationFailed;
    }
    return AppleSignInException(code, e.message ?? 'Native authorization failed.', e.details);
  }
}

/// Configuration for desktop Apple Sign-In OAuth flow.
@immutable
class AppleSignInDesktopConfig {
  /// Creates an [AppleSignInDesktopConfig].
  const AppleSignInDesktopConfig({
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

  /// Optional expected callback host.
  final String? callbackHost;
}
