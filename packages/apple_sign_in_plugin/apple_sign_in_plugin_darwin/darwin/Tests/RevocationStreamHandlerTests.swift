// Copyright (c) 2026 DHC Tech. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import AuthenticationServices
import XCTest

@testable import apple_sign_in_plugin_darwin

final class RevocationStreamHandlerTests: XCTestCase {
  func testOnListenForwardsRevocationNotificationsToTheEventSink() {
    let handler = RevocationStreamHandler()
    var receivedEvents: [Any?] = []

    let error = handler.onListen(
      withArguments: nil,
      eventSink: { event in receivedEvents.append(event) }
    )
    XCTAssertNil(error)

    NotificationCenter.default.post(
      name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
      object: nil
    )

    let expectation = XCTestExpectation(description: "event delivered on main queue")
    DispatchQueue.main.async { expectation.fulfill() }
    wait(for: [expectation], timeout: 1.0)

    XCTAssertEqual(receivedEvents.count, 1)

    _ = handler.onCancel(withArguments: nil)
  }

  func testOnCancelStopsFurtherNotifications() {
    let handler = RevocationStreamHandler()
    var eventCount = 0

    _ = handler.onListen(withArguments: nil, eventSink: { _ in eventCount += 1 })
    _ = handler.onCancel(withArguments: nil)

    NotificationCenter.default.post(
      name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
      object: nil
    )

    let expectation = XCTestExpectation(description: "no event delivered")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
    wait(for: [expectation], timeout: 1.0)

    XCTAssertEqual(eventCount, 0)
  }
}
