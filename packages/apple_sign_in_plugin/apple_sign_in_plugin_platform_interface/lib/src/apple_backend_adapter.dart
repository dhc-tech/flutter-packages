// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'apple_credential.dart';
import 'apple_disconnect_result.dart';

/// Optional abstraction for developers integrating their own backend server
/// for authorization code exchange, refresh token management, and true Apple token revocation.
abstract class AppleBackendAdapter {
  /// Called after successful client authorization to exchange the authorization code
  /// on the backend and initiate server-side session management.
  Future<void> onAuthorizationSuccess(AppleCredential credential);

  /// Requests the backend server to revoke the user's Apple authorization via `POST https://appleid.apple.com/auth/revoke`.
  Future<AppleDisconnectResult> revokeAuthorization(String userIdentifier);
}
