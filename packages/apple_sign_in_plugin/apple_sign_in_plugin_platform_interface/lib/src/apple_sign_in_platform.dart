// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'apple_authorization_scope.dart';
import 'apple_credential.dart';
import 'apple_credential_state.dart';
import 'method_channel_apple_sign_in.dart';

/// The interface that platform-specific implementations of this plugin
/// must implement.
///
/// This package currently ships one implementation
/// ([MethodChannelAppleSignIn]) covering iOS and macOS. Keeping this as a
/// `PlatformInterface` — rather than calling `MethodChannel` directly from
/// the public API — means additional platforms (Android, web, Windows,
/// Linux) can be added later, including as separate federated packages,
/// without a breaking change to the public Dart API.
///
/// Platform implementations should extend this class rather than implement
/// it, so that new methods added here don't break existing
/// implementations at compile time (per Flutter's federated plugin
/// guidance).
abstract class AppleSignInPlatform extends PlatformInterface {
  /// Constructs an [AppleSignInPlatform].
  AppleSignInPlatform() : super(token: _token);

  static final Object _token = Object();

  static AppleSignInPlatform _instance = MethodChannelAppleSignIn();

  /// The active platform implementation.
  ///
  /// Defaults to [MethodChannelAppleSignIn]. Platform packages set this in
  /// their own registration code.
  static AppleSignInPlatform get instance => _instance;

  /// Platform-specific packages should set this with their own
  /// platform-specific class that extends [AppleSignInPlatform] when they
  /// register themselves.
  static set instance(AppleSignInPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Whether Sign in with Apple is available on this device/platform.
  Future<bool> isAvailable() {
    throw UnimplementedError('isAvailable() has not been implemented.');
  }

  /// Starts an Apple authorization request.
  Future<AppleCredential> signIn({
    required Set<AppleAuthorizationScope> scopes,
    String? nonce,
    String? state,
  }) {
    throw UnimplementedError('signIn() has not been implemented.');
  }

  /// Queries Apple for the current state of a previously-issued
  /// credential.
  Future<AppleCredentialState> getCredentialState(String userIdentifier) {
    throw UnimplementedError(
      'getCredentialState() has not been implemented.',
    );
  }

  /// A broadcast stream that emits an event whenever Apple reports that
  /// *some* credential for this app was revoked, on platforms with a
  /// native revocation-notification mechanism.
  ///
  /// Apple's underlying native notification does not identify which user
  /// was affected, so this stream does not either — treat each event as a
  /// prompt to re-check every Apple user identifier your app has stored,
  /// via [getCredentialState].
  ///
  /// Emits nothing on platforms without a native revocation-notification
  /// mechanism (see the README's "Revocation" section) — poll
  /// [getCredentialState] instead on those platforms.
  Stream<void> get onCredentialRevoked {
    throw UnimplementedError(
      'onCredentialRevoked has not been implemented.',
    );
  }
}
