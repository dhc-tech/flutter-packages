// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright (c) 2026 DHC Tech. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import AuthenticationServices
import Foundation

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

/// Holds the delegate/presentation-context state for a single in-flight
/// `ASAuthorizationController` request so that concurrent sign-in requests
/// (however unlikely) never interfere with each other.
class AuthorizationSession: NSObject, ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding
{
  private let controller: ASAuthorizationController
  private let completion: (Result<ASAuthorizationAppleIDCredential, Error>) -> Void
  private(set) var isFinished = false

  init(
    controller: ASAuthorizationController,
    completion: @escaping (Result<ASAuthorizationAppleIDCredential, Error>) -> Void
  ) {
    self.controller = controller
    self.completion = completion
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    isFinished = true
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      completion(
        .failure(
          NSError(
            domain: "apple_sign_in_plugin", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unexpected credential type."])))
      return
    }
    completion(.success(credential))
  }

  func authorizationController(
    controller: ASAuthorizationController, didCompleteWithError error: Error
  ) {
    isFinished = true
    completion(.failure(error))
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    #if os(iOS)
      let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
      if let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first {
        return window
      }
      return UIWindow()
    #elseif os(macOS)
      return NSApplication.shared.windows.first ?? NSWindow()
    #endif
  }
}
