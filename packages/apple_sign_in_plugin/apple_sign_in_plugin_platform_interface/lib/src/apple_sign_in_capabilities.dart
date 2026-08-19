// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

import 'apple_authorization_scope.dart';

/// Exposes the precise, genuine Apple authentication capabilities supported on the active platform.
@immutable
class AppleSignInCapabilities {
  /// Creates an [AppleSignInCapabilities].
  const AppleSignInCapabilities({
    required this.platformName,
    required this.isSupported,
    required this.nativeCredentialState,
    required this.revocationEvents,
    required this.browserAuthorization,
    required this.webAppleJs,
    required this.wasmWeb,
    required this.backendRevocation,
    required this.supportedScopes,
  });

  /// The name of the active operating system / platform.
  final String platformName;

  /// Whether Sign in with Apple is supported on this platform.
  final bool isSupported;

  /// Whether native `ASAuthorizationAppleIDProvider.getCredentialState` is supported.
  final bool nativeCredentialState;

  /// Whether native OS credential revocation notifications (`credentialRevokedNotification`) are supported.
  final bool revocationEvents;

  /// Whether authentication uses external system browser / Chrome Custom Tabs.
  final bool browserAuthorization;

  /// Whether authentication uses official Apple JS SDK (`AppleID.auth`).
  final bool webAppleJs;

  /// Whether Flutter WebAssembly (WasmGC) build is supported.
  final bool wasmWeb;

  /// Whether backend assistance is required for true programmatic `/auth/revoke`.
  final bool backendRevocation;

  /// The set of authorization scopes supported on this platform.
  final Set<AppleAuthorizationScope> supportedScopes;

  @override
  String toString() =>
      'AppleSignInCapabilities(platform: $platformName, nativeState: $nativeCredentialState, revocationEvents: $revocationEvents, wasm: $wasmWeb)';
}
