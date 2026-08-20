// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// The personal data scopes that can be requested from Apple during
/// authorization.
///
/// These map directly to Apple's `ASAuthorization.Scope` values on
/// iOS/macOS and to the `scope` values documented for Sign in with Apple JS
/// and the "Sign in with Apple" REST API for other platforms.
///
/// Apple only guarantees to return the requested data on the **first**
/// authorization for a given user/app pair — see the "Full Name" and
/// "Email" sections of the package README.
enum AppleAuthorizationScope {
  /// Requests the user's email address (or Apple's private relay address).
  email,

  /// Requests the user's full name.
  fullName;

  /// The raw string Apple's REST/JS API expects in the `scope` query
  /// parameter (space separated when combined).
  String get restApiValue => switch (this) {
        AppleAuthorizationScope.email => 'email',
        AppleAuthorizationScope.fullName => 'name',
      };
}
