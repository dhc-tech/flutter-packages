// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

/// The status resulting from an `AppleSignIn.disconnect` operation.
enum AppleDisconnectStatus {
  /// The Apple token was programmatically revoked via the backend `/auth/revoke` API.
  revoked,

  /// The token or credential was already revoked prior to disconnect.
  alreadyRevoked,

  /// The user is not currently authorized or no active session was found.
  notAuthorized,

  /// True Apple revocation requires the user to revoke permission manually in Apple ID Settings.
  manualActionRequired,

  /// True Apple revocation requires a configured [AppleBackendAdapter] to call Apple's `/auth/revoke` endpoint.
  backendRequired,

  /// Programmatic revocation is not supported on this platform without backend assistance.
  unsupported,

  /// An error occurred during the disconnect request.
  failed,
}

/// The result of an `AppleSignIn.disconnect` operation.
@immutable
class AppleDisconnectResult {
  /// Creates an [AppleDisconnectResult].
  const AppleDisconnectResult({
    required this.status,
    this.message,
  });

  /// The disconnect status.
  final AppleDisconnectStatus status;

  /// Detailed contextual message explaining the outcome.
  final String? message;

  /// Whether the disconnect was completely successful (either revoked or already revoked).
  bool get isSuccessful =>
      status == AppleDisconnectStatus.revoked || status == AppleDisconnectStatus.alreadyRevoked;

  @override
  String toString() => 'AppleDisconnectResult(status: $status, message: $message)';
}
