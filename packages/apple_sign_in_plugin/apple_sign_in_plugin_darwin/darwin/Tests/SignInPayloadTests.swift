// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright (c) 2026 DHC Tech. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import AuthenticationServices
import XCTest

@testable import apple_sign_in_plugin_darwin

final class SignInPayloadTests: XCTestCase {
  private func authError(_ code: ASAuthorizationError.Code) -> Error {
    NSError(domain: ASAuthorizationErrorDomain, code: code.rawValue)
  }

  func testCanceledMapsToCanceled() {
    let error = SignInPayload.flutterError(for: authError(.canceled))
    XCTAssertEqual(error.code, "canceled")
  }

  func testInvalidResponseMapsToInvalidResponse() {
    let error = SignInPayload.flutterError(for: authError(.invalidResponse))
    XCTAssertEqual(error.code, "invalid_response")
  }

  func testFailedMapsToAuthorizationFailed() {
    let error = SignInPayload.flutterError(for: authError(.failed))
    XCTAssertEqual(error.code, "authorization_failed")
  }

  func testNotHandledMapsToAuthorizationFailed() {
    let error = SignInPayload.flutterError(for: authError(.notHandled))
    XCTAssertEqual(error.code, "authorization_failed")
  }

  func testUnknownAuthorizationErrorMapsToUnknown() {
    let error = SignInPayload.flutterError(for: authError(.unknown))
    XCTAssertEqual(error.code, "unknown")
  }

  func testNonAuthorizationErrorMapsToUnknown() {
    struct SomeOtherError: Error {}
    let error = SignInPayload.flutterError(for: SomeOtherError())
    XCTAssertEqual(error.code, "unknown")
  }

  func testFlutterErrorCarriesTheLocalizedDescription() {
    let underlying = authError(.canceled) as NSError
    let error = SignInPayload.flutterError(for: underlying)
    XCTAssertEqual(error.message, underlying.localizedDescription)
  }
}
