// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// The state of a previously-issued Apple credential, as reported by
/// `ASAuthorizationAppleIDProvider.getCredentialState(forUserID:)` on
/// iOS/macOS.
///
/// Query this periodically (Apple recommends on every app launch) to detect
/// that a user has revoked your app's access from their Apple ID settings.
enum AppleCredentialState {
  /// The credential is valid and the user is still authorized.
  authorized,

  /// The user has revoked authorization for your app.
  revoked,

  /// No credential was found for the given user identifier.
  notFound,

  /// The credential was transferred as part of an app/team transfer.
  ///
  /// Apple documents this state for the migration window after a
  /// developer/team transfer. Do **not** treat it as [revoked] — the
  /// credential is still valid, but your app must re-authenticate the user
  /// to receive an updated user identifier. See the README's "App / Team
  /// Transfer" section.
  transferred;

  /// Builds an [AppleCredentialState] from the raw integer Apple's native
  /// `ASAuthorizationAppleIDProvider.CredentialState` enum reports over the
  /// platform channel.
  static AppleCredentialState fromWireValue(int value) => switch (value) {
        0 => AppleCredentialState.authorized,
        1 => AppleCredentialState.revoked,
        3 => AppleCredentialState.transferred,
        _ => AppleCredentialState.notFound,
      };
}
