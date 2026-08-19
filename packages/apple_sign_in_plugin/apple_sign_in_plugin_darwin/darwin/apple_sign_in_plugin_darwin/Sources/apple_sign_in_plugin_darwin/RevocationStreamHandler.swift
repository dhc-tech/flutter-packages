// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

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

/// Bridges Apple's
/// `ASAuthorizationAppleIDProvider.credentialRevokedNotification` to a
/// Flutter `EventChannel` broadcast stream.
class RevocationStreamHandler: NSObject, FlutterStreamHandler {
  private var observer: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    observer = NotificationCenter.default.addObserver(
      forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
      object: nil,
      queue: .main
    ) { _ in
      // Apple's notification does not include the affected user
      // identifier — apps are expected to re-check every user identifier
      // they have stored via `getCredentialState`. This plugin cannot
      // know which identifiers the host app is tracking, so it emits a
      // bare "re-check now" signal; the Dart API exposes this as
      // `Stream<void>` rather than a user identifier stream.
      events(true)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
    }
    observer = nil
    return nil
  }

  deinit {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
