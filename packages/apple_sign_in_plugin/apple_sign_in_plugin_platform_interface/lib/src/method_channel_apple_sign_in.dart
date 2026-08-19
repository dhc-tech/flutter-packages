import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'apple_authorization_scope.dart';
import 'apple_credential.dart';
import 'apple_credential_state.dart';
import 'apple_person_name.dart';
import 'apple_real_user_status.dart';
import 'apple_sign_in_exception.dart';
import 'apple_sign_in_platform.dart';

/// The default [AppleSignInPlatform] implementation, backed by a
/// [MethodChannel]/[EventChannel] pair to native Swift code shared between
/// iOS and macOS (see `darwin/Classes/AppleSignInPlugin.swift`).
///
/// On any other platform, every method throws
/// [AppleSignInErrorCode.platformNotSupported] rather than silently
/// forwarding calls the native side does not implement — see the
/// package README's platform-support table for the current status of
/// Android, web, Windows, and Linux.
class MethodChannelAppleSignIn extends AppleSignInPlatform {
  /// The method channel used to talk to the native Apple platforms.
  @visibleForTesting
  final MethodChannel channel = const MethodChannel('apple_sign_in_plugin');

  /// The event channel used to receive native credential-revocation
  /// notifications on Apple platforms.
  @visibleForTesting
  final EventChannel revocationChannel = const EventChannel(
    'apple_sign_in_plugin/credential_revoked',
  );

  Stream<void>? _onCredentialRevoked;

  static const Set<TargetPlatform> _supportedPlatforms = {
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  };

  bool get _isSupportedPlatform =>
      _supportedPlatforms.contains(defaultTargetPlatform);

  Never _throwUnsupported() {
    throw const AppleSignInException(
      AppleSignInErrorCode.platformNotSupported,
      'Sign in with Apple is only implemented on iOS and macOS in this '
      'version of apple_sign_in_plugin. See the README for the current '
      'platform-support table.',
    );
  }

  @override
  Future<bool> isAvailable() async {
    if (!_isSupportedPlatform) {
      return false;
    }
    final bool? result = await channel.invokeMethod<bool>('isAvailable');
    return result ?? false;
  }

  @override
  Future<AppleCredential> signIn({
    required Set<AppleAuthorizationScope> scopes,
    String? nonce,
    String? state,
  }) async {
    if (!_isSupportedPlatform) {
      _throwUnsupported();
    }
    if (scopes.isEmpty) {
      throw const AppleSignInException(
        AppleSignInErrorCode.invalidArguments,
        'At least one AppleAuthorizationScope must be requested.',
      );
    }

    try {
      final Map<Object?, Object?>? raw = await channel
          .invokeMapMethod<Object?, Object?>('signIn', <String, Object?>{
            'scopes': scopes.map((AppleAuthorizationScope s) => s.name).toList(),
            'nonce': nonce,
            'state': state,
          });
      if (raw == null) {
        throw const AppleSignInException(
          AppleSignInErrorCode.invalidResponse,
          'Native signIn() call returned no data.',
        );
      }
      return _credentialFromWire(raw);
    } on PlatformException catch (e) {
      throw _exceptionFromPlatformException(e);
    }
  }

  @override
  Future<AppleCredentialState> getCredentialState(
    String userIdentifier,
  ) async {
    if (!_isSupportedPlatform) {
      _throwUnsupported();
    }
    try {
      final int? raw = await channel.invokeMethod<int>(
        'getCredentialState',
        <String, Object?>{'userIdentifier': userIdentifier},
      );
      if (raw == null) {
        throw const AppleSignInException(
          AppleSignInErrorCode.credentialStateFailed,
          'Native getCredentialState() call returned no data.',
        );
      }
      return AppleCredentialState.fromWireValue(raw);
    } on PlatformException catch (e) {
      throw AppleSignInException(
        AppleSignInErrorCode.credentialStateFailed,
        e.message ?? 'getCredentialState() failed.',
        e.details,
      );
    }
  }

  @override
  Stream<void> get onCredentialRevoked {
    if (!_isSupportedPlatform) {
      return const Stream<void>.empty();
    }
    return _onCredentialRevoked ??= revocationChannel
        .receiveBroadcastStream()
        .map((Object? event) {});
  }

  AppleCredential _credentialFromWire(Map<Object?, Object?> raw) {
    final userIdentifier = raw['userIdentifier'] as String?;
    if (userIdentifier == null) {
      throw const AppleSignInException(
        AppleSignInErrorCode.invalidResponse,
        'Native signIn() response was missing "userIdentifier".',
      );
    }

    final name = ApplePersonName(
      namePrefix: raw['namePrefix'] as String?,
      givenName: raw['givenName'] as String?,
      middleName: raw['middleName'] as String?,
      familyName: raw['familyName'] as String?,
      nameSuffix: raw['nameSuffix'] as String?,
      nickname: raw['nickname'] as String?,
    );

    final List<Object?> rawScopes =
        raw['authorizedScopes'] as List<Object?>? ?? const <Object?>[];
    final Set<AppleAuthorizationScope> authorizedScopes = rawScopes
        .map((Object? value) => value! as String)
        .map(
          (String value) => AppleAuthorizationScope.values.firstWhere(
            (AppleAuthorizationScope scope) => scope.name == value,
            orElse: () => AppleAuthorizationScope.email,
          ),
        )
        .toSet();

    return AppleCredential(
      userIdentifier: userIdentifier,
      email: raw['email'] as String?,
      name: name.isEmpty ? null : name,
      identityToken: raw['identityToken'] as String?,
      authorizationCode: raw['authorizationCode'] as String?,
      state: raw['state'] as String? ?? '',
      authorizedScopes: authorizedScopes,
      realUserStatus: AppleRealUserStatus.fromWireValue(
        raw['realUserStatus'] as int?,
      ),
    );
  }

  AppleSignInException _exceptionFromPlatformException(PlatformException e) {
    final AppleSignInErrorCode code = switch (e.code) {
      'canceled' => AppleSignInErrorCode.canceled,
      'already_in_progress' => AppleSignInErrorCode.alreadyInProgress,
      'not_available' => AppleSignInErrorCode.notAvailable,
      'invalid_configuration' => AppleSignInErrorCode.invalidConfiguration,
      'authorization_failed' => AppleSignInErrorCode.authorizationFailed,
      'invalid_response' => AppleSignInErrorCode.invalidResponse,
      'network_failed' => AppleSignInErrorCode.networkFailed,
      _ => AppleSignInErrorCode.unknown,
    };
    return AppleSignInException(
      code,
      e.message ?? 'Apple Sign-In failed (${e.code}).',
      e.details,
    );
  }
}
