// Copyright (c) 2026 DHC Tech. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import AuthenticationServices
import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Encodes a native `ASAuthorizationAppleIDCredential` into the wire
/// format expected by `MethodChannelAppleSignIn` on the Dart side, and
/// maps native errors onto this plugin's stable error codes.
enum SignInPayload {
  static func encode(_ credential: ASAuthorizationAppleIDCredential) -> [String: Any?] {
    var authorizedScopes: [String] = []
    if let email = credential.email, !email.isEmpty {
      authorizedScopes.append("email")
    }
    if credential.fullName != nil {
      authorizedScopes.append("fullName")
    }

    return [
      "userIdentifier": credential.user,
      "email": credential.email,
      "namePrefix": credential.fullName?.namePrefix,
      "givenName": credential.fullName?.givenName,
      "middleName": credential.fullName?.middleName,
      "familyName": credential.fullName?.familyName,
      "nameSuffix": credential.fullName?.nameSuffix,
      "nickname": credential.fullName?.nickname,
      "identityToken": credential.identityToken.flatMap {
        String(data: $0, encoding: .utf8)
      },
      "authorizationCode": credential.authorizationCode.flatMap {
        String(data: $0, encoding: .utf8)
      },
      "state": credential.state,
      "authorizedScopes": authorizedScopes,
      "realUserStatus": Int(credential.realUserStatus.rawValue),
    ]
  }

  static func flutterError(for error: Error) -> FlutterError {
    guard let authError = error as? ASAuthorizationError else {
      return FlutterError(
        code: "unknown", message: error.localizedDescription, details: nil)
    }
    let code: String
    switch authError.code {
    case .canceled:
      code = "canceled"
    case .invalidResponse:
      code = "invalid_response"
    case .notHandled:
      code = "authorization_failed"
    case .failed:
      code = "authorization_failed"
    case .notInteractive:
      code = "authorization_failed"
    case .matchedExcludedCredential:
      code = "authorization_failed"
    case .unknown:
      code = "unknown"
    @unknown default:
      // Covers ASAuthorizationError cases added in OS versions newer than
      // this plugin's deployment target — the compiler intentionally warns
      // here on new SDKs so this can be revisited, without breaking the
      // build.
      code = "unknown"
    }
    return FlutterError(
      code: code, message: authError.localizedDescription, details: nil)
  }
}
