// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter/foundation.dart';

export 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';

/// Complete, production-grade Apple Authentication Lifecycle controller for Flutter.
///
/// Provides a unified, cross-platform Dart API across iOS, macOS, Android,
/// Web (JavaScript & WasmGC), Windows, and Linux.
class AppleSignIn {
  AppleSignIn._();

  /// The shared singleton instance of [AppleSignIn].
  static final AppleSignIn instance = AppleSignIn._();

  AppleAuthSession? _currentSession;
  final StreamController<AppleAuthEvent> _eventController =
      StreamController<AppleAuthEvent>.broadcast();
  StreamSubscription<void>? _platformRevocationSub;

  /// Optional backend adapter for server-side token exchange and true Apple revocation.
  AppleBackendAdapter? backendAdapter;

  /// The most recent active [AppleAuthSession], if any.
  AppleAuthSession? get currentSession => _currentSession;

  /// High-level stream of authentication lifecycle events.
  Stream<AppleAuthEvent> get events {
    _platformRevocationSub?.cancel();
    _platformRevocationSub =
        AppleSignInPlatform.instance.onCredentialRevoked.listen((_) {
      _eventController.add(
        const AppleAuthEvent(
          type: AppleAuthEventType.credentialRevoked,
          message:
              'Received native credentialRevokedNotification from Apple OS.',
        ),
      );
    });
    return _eventController.stream;
  }

  /// Checks whether Sign in with Apple is available on the current device and platform.
  Future<bool> isAvailable() => AppleSignInPlatform.instance.isAvailable();

  /// Initiates the Sign in with Apple authentication flow and returns an [AppleAuthSession].
  Future<AppleAuthSession> signIn({
    required Set<AppleAuthorizationScope> scopes,
    String? nonce,
    String? state,
  }) async {
    try {
      final AppleCredential credential =
          await AppleSignInPlatform.instance.signIn(
        scopes: scopes,
        nonce: nonce,
        state: state,
      );

      final AppleSignInCapabilities caps = await capabilities();
      final session = AppleAuthSession.fromCredential(
        credential: credential,
        capabilities: caps,
        nonce: nonce,
      );
      _currentSession = session;

      _eventController.add(
        AppleAuthEvent(
          type: AppleAuthEventType.signedIn,
          credential: credential,
          userIdentifier: credential.userIdentifier,
        ),
      );

      final AppleBackendAdapter? adapter = backendAdapter;
      if (adapter != null) {
        unawaited(adapter.onAuthorizationSuccess(credential));
      }

      return session;
    } on AppleSignInException catch (e) {
      if (e.code == AppleSignInErrorCode.canceled) {
        _eventController.add(
          const AppleAuthEvent(
            type: AppleAuthEventType.authorizationCancelled,
            message: 'User cancelled Sign in with Apple.',
          ),
        );
      }
      rethrow;
    }
  }

  /// Signs the user out locally from the application session.
  ///
  /// **Note:** This clears local application state and does NOT revoke Apple authorization.
  Future<void> signOut({String? userIdentifier}) async {
    final String? effectiveId =
        userIdentifier ?? _currentSession?.identity.userIdentifier;
    _currentSession = null;

    _eventController.add(
      AppleAuthEvent(
        type: AppleAuthEventType.signedOut,
        userIdentifier: effectiveId,
        message: 'User signed out locally from application session.',
      ),
    );
  }

  /// Queries Apple for the current state of a user's credential.
  ///
  /// **Platform Availability:** Native Apple platforms (iOS, macOS) only.
  /// Calling this on non-Apple platforms throws an [AppleSignInException]
  /// with [AppleSignInErrorCode.platformNotSupported].
  Future<AppleCredentialState> getCredentialState(String userIdentifier) async {
    final AppleCredentialState state =
        await AppleSignInPlatform.instance.getCredentialState(userIdentifier);

    if (state == AppleCredentialState.transferred) {
      _eventController.add(
        AppleAuthEvent(
          type: AppleAuthEventType.credentialTransferred,
          userIdentifier: userIdentifier,
          message: 'App was transferred to a new team; migration needed.',
        ),
      );
    }

    return state;
  }

  /// Listens for native credential revocation events on iOS and macOS.
  Stream<void> get onCredentialRevoked =>
      AppleSignInPlatform.instance.onCredentialRevoked;

  /// High-level user disconnect operation.
  ///
  /// Strictly capability-driven: checks native credential state where supported,
  /// delegates to an [AppleBackendAdapter] when registered, and provides honest
  /// status codes when manual action is required.
  Future<AppleDisconnectResult> disconnect({
    String? userIdentifier,
    bool forceLocalSignOut = true,
  }) async {
    final String? effectiveId =
        userIdentifier ?? _currentSession?.identity.userIdentifier;

    if (forceLocalSignOut) {
      await signOut(userIdentifier: effectiveId);
    }

    final AppleBackendAdapter? adapter = backendAdapter;
    if (adapter != null && effectiveId != null) {
      return adapter.revokeAuthorization(effectiveId);
    }

    final AppleSignInCapabilities caps = await capabilities();

    // If native credential state query is available (iOS/macOS), inspect current authorization.
    if (caps.nativeCredentialState && effectiveId != null) {
      try {
        final AppleCredentialState state =
            await getCredentialState(effectiveId);
        if (state == AppleCredentialState.revoked) {
          return const AppleDisconnectResult(
            status: AppleDisconnectStatus.alreadyRevoked,
            message: 'Apple ID credential has already been revoked.',
          );
        }
        return const AppleDisconnectResult(
          status: AppleDisconnectStatus.manualActionRequired,
          message:
              'Local session cleared. To revoke authorization, the user can remove the app in Apple ID Settings, or configure an AppleBackendAdapter for programmatic revocation.',
        );
      } catch (_) {
        return const AppleDisconnectResult(
          status: AppleDisconnectStatus.manualActionRequired,
          message:
              'Local session cleared. Configure an AppleBackendAdapter for programmatic token revocation.',
        );
      }
    }

    if (caps.webAppleJs || caps.browserAuthorization) {
      return const AppleDisconnectResult(
        status: AppleDisconnectStatus.backendRequired,
        message:
            'On non-Apple platforms, true Apple token revocation requires an AppleBackendAdapter to call /auth/revoke.',
      );
    }

    return const AppleDisconnectResult(
      status: AppleDisconnectStatus.unsupported,
      message:
          'Programmatic revocation is unsupported on this platform without a backend adapter.',
    );
  }

  /// Inspects genuine Apple authentication capabilities for the active platform.
  Future<AppleSignInCapabilities> capabilities() async {
    final String platformName;
    final bool nativeState;
    final bool revocationEvents;
    final bool browserAuth;
    final bool webJs;
    final bool wasmWeb;

    if (kIsWeb) {
      platformName = 'Web';
      nativeState = false;
      revocationEvents = false;
      browserAuth = false;
      webJs = true;
      wasmWeb = true;
    } else {
      webJs = false;
      wasmWeb = false;
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          platformName = 'iOS';
          nativeState = true;
          revocationEvents = true;
          browserAuth = false;
        case TargetPlatform.macOS:
          platformName = 'macOS';
          nativeState = true;
          revocationEvents = true;
          browserAuth = false;
        case TargetPlatform.android:
          platformName = 'Android';
          nativeState = false;
          revocationEvents = false;
          browserAuth = true;
        case TargetPlatform.windows:
          platformName = 'Windows';
          nativeState = false;
          revocationEvents = false;
          browserAuth = true;
        case TargetPlatform.linux:
          platformName = 'Linux';
          nativeState = false;
          revocationEvents = false;
          browserAuth = true;
        case TargetPlatform.fuchsia:
          platformName = 'Unknown';
          nativeState = false;
          revocationEvents = false;
          browserAuth = false;
      }
    }

    return AppleSignInCapabilities(
      platformName: platformName,
      isSupported: true,
      nativeCredentialState: nativeState,
      revocationEvents: revocationEvents,
      browserAuthorization: browserAuth,
      webAppleJs: webJs,
      wasmWeb: wasmWeb,
      backendRevocation: backendAdapter != null,
      supportedScopes: const {
        AppleAuthorizationScope.email,
        AppleAuthorizationScope.fullName,
      },
    );
  }

  /// Returns safe diagnostics metadata about platform status and configuration.
  ///
  /// **Zero sensitive tokens or secrets are included in diagnostics.**
  Future<AppleSignInDiagnostics> diagnostics() async {
    final AppleSignInCapabilities caps = await capabilities();
    final bool available = await isAvailable();

    return AppleSignInDiagnostics(
      platformName: caps.platformName,
      isAvailable: available,
      capabilities: caps,
      isConfigured: true,
      configurationDetails: <String, String>{
        'platform': caps.platformName,
        'backendAdapterConfigured': (backendAdapter != null).toString(),
      },
      hasBackendAdapter: backendAdapter != null,
    );
  }
}

/// Backwards compatibility alias pointing to [AppleSignIn.instance].
class AppleSignInPlugin {
  /// Calls [AppleSignIn.instance.isAvailable].
  static Future<bool> isAvailable() => AppleSignIn.instance.isAvailable();

  /// Calls [AppleSignIn.instance.signIn] and returns the underlying [AppleCredential].
  static Future<AppleCredential> signIn({
    required Set<AppleAuthorizationScope> scopes,
    String? nonce,
    String? state,
  }) async {
    final AppleAuthSession session = await AppleSignIn.instance.signIn(
      scopes: scopes,
      nonce: nonce,
      state: state,
    );
    return session.rawCredential;
  }

  /// Calls [AppleSignIn.instance.getCredentialState].
  static Future<AppleCredentialState> getCredentialState(
    String userIdentifier,
  ) =>
      AppleSignIn.instance.getCredentialState(userIdentifier);

  /// Calls [AppleSignIn.instance.onCredentialRevoked].
  static Stream<void> get onCredentialRevoked =>
      AppleSignIn.instance.onCredentialRevoked;
}
