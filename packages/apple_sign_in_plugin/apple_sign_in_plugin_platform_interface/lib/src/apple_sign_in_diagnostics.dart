// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

import 'apple_sign_in_capabilities.dart';

/// Diagnostics information containing safe platform and configuration status.
///
/// **Zero sensitive tokens, private keys, or credentials are ever exposed.**
@immutable
class AppleSignInDiagnostics {
  /// Creates an [AppleSignInDiagnostics].
  const AppleSignInDiagnostics({
    required this.platformName,
    required this.isAvailable,
    required this.capabilities,
    required this.isConfigured,
    required this.configurationDetails,
    required this.hasBackendAdapter,
  });

  /// The active operating system name.
  final String platformName;

  /// Whether the plugin is currently available to process sign-in requests.
  final bool isAvailable;

  /// The capability matrix for this platform.
  final AppleSignInCapabilities capabilities;

  /// Whether platform-specific configuration (e.g. Services ID, redirect URI) has been set.
  final bool isConfigured;

  /// Non-sensitive configuration summary (e.g. Service ID presence, callback scheme).
  final Map<String, String> configurationDetails;

  /// Whether a custom [AppleBackendAdapter] has been registered.
  final bool hasBackendAdapter;

  /// Formats diagnostics into a safe, copy-paste-ready string for GitHub issues.
  String toSafeString() {
    final buffer = StringBuffer()
      ..writeln('=== Apple Sign-In Diagnostics ===')
      ..writeln('Platform: $platformName')
      ..writeln('Available: $isAvailable')
      ..writeln('Configured: $isConfigured')
      ..writeln(
          'Native Credential State Supported: ${capabilities.nativeCredentialState}')
      ..writeln('Revocation Stream Supported: ${capabilities.revocationEvents}')
      ..writeln('WebAssembly Supported: ${capabilities.wasmWeb}')
      ..writeln('Backend Adapter Registered: $hasBackendAdapter');
    return buffer.toString();
  }

  @override
  String toString() => toSafeString();
}
