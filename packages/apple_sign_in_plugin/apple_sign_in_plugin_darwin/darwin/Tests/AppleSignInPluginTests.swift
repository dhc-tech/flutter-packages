// Copyright (c) 2026 DHC Tech. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import XCTest

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

@testable import apple_sign_in_plugin_darwin

final class AppleSignInPluginTests: XCTestCase {
  func testIsAvailableAlwaysReturnsTrue() {
    let plugin = AppleSignInPlugin()
    let call = FlutterMethodCall(methodName: "isAvailable", arguments: nil)

    var result: Any?
    plugin.handle(call) { result = $0 }

    XCTAssertEqual(result as? Bool, true)
  }

  func testUnknownMethodReturnsNotImplemented() {
    let plugin = AppleSignInPlugin()
    let call = FlutterMethodCall(methodName: "notARealMethod", arguments: nil)

    var result: Any?
    plugin.handle(call) { result = $0 }

    // FlutterMethodNotImplemented is a singleton sentinel NSObject; identity
    // comparison is the correct way to check for it.
    XCTAssertTrue((result as AnyObject) === (FlutterMethodNotImplemented as AnyObject))
  }

  func testSignInWithMalformedArgumentsReturnsInvalidConfigurationError() {
    let plugin = AppleSignInPlugin()
    let call = FlutterMethodCall(methodName: "signIn", arguments: "not a map")

    var result: Any?
    plugin.handle(call) { result = $0 }

    let error = try? XCTUnwrap(result as? FlutterError)
    XCTAssertEqual(error?.code, "invalid_configuration")
  }

  func testGetCredentialStateWithoutUserIdentifierReturnsInvalidConfigurationError() {
    let plugin = AppleSignInPlugin()
    let call = FlutterMethodCall(methodName: "getCredentialState", arguments: [String: Any]())

    var result: Any?
    plugin.handle(call) { result = $0 }

    let error = try? XCTUnwrap(result as? FlutterError)
    XCTAssertEqual(error?.code, "invalid_configuration")
  }
}
