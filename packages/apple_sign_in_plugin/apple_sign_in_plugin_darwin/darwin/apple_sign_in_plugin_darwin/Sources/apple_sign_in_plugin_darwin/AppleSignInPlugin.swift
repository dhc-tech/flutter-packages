// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright (c) 2026 DHC Tech. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// Native Sign in with Apple implementation, shared between iOS and macOS,
// built directly on Apple's AuthenticationServices framework. This file
// contains no third-party Apple Sign-In SDK code.

import AuthenticationServices
import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// The Flutter plugin entry point for `apple_sign_in_plugin` on iOS/macOS.
public class AppleSignInPlugin: NSObject, FlutterPlugin {
  private static let channelName = "apple_sign_in_plugin"
  private static let revocationChannelName = "apple_sign_in_plugin/credential_revoked"

  /// Keeps in-flight `AuthorizationSession` instances alive for the
  /// duration of their `ASAuthorizationController` delegate callbacks.
  private var activeSessions: [AuthorizationSession] = []
  private var revocationStreamHandler: RevocationStreamHandler?

  #if os(iOS)
    public static func register(with registrar: FlutterPluginRegistrar) {
      let channel = FlutterMethodChannel(
        name: channelName, binaryMessenger: registrar.messenger())
      let eventChannel = FlutterEventChannel(
        name: revocationChannelName, binaryMessenger: registrar.messenger())
      let instance = AppleSignInPlugin()
      registrar.addMethodCallDelegate(instance, channel: channel)
      let streamHandler = RevocationStreamHandler()
      instance.revocationStreamHandler = streamHandler
      eventChannel.setStreamHandler(streamHandler)
    }
  #elseif os(macOS)
    public static func register(with registrar: FlutterPluginRegistrar) {
      let channel = FlutterMethodChannel(
        name: channelName, binaryMessenger: registrar.messenger)
      let eventChannel = FlutterEventChannel(
        name: revocationChannelName, binaryMessenger: registrar.messenger)
      let instance = AppleSignInPlugin()
      registrar.addMethodCallDelegate(instance, channel: channel)
      let streamHandler = RevocationStreamHandler()
      instance.revocationStreamHandler = streamHandler
      eventChannel.setStreamHandler(streamHandler)
    }
  #endif

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      // ASAuthorizationAppleIDProvider has been available since iOS 13 /
      // macOS 10.15, which are both below this plugin's deployment target,
      // so Sign in with Apple is always available where this plugin runs.
      result(true)
    case "signIn":
      guard let args = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "invalid_configuration",
            message: "signIn() call arguments were malformed.",
            details: nil))
        return
      }
      handleSignIn(arguments: args, result: result)
    case "getCredentialState":
      guard let args = call.arguments as? [String: Any],
        let userIdentifier = args["userIdentifier"] as? String
      else {
        result(
          FlutterError(
            code: "invalid_configuration",
            message: "getCredentialState() requires a userIdentifier.",
            details: nil))
        return
      }
      handleGetCredentialState(userIdentifier: userIdentifier, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleSignIn(arguments: [String: Any], result: @escaping FlutterResult) {
    let requestedScopeNames = arguments["scopes"] as? [String] ?? []
    let scopes: [ASAuthorization.Scope] = requestedScopeNames.compactMap { name in
      switch name {
      case "email": return .email
      case "fullName": return .fullName
      default: return nil
      }
    }

    let provider = ASAuthorizationAppleIDProvider()
    let request = provider.createRequest()
    request.requestedScopes = scopes
    request.nonce = arguments["nonce"] as? String
    request.state = arguments["state"] as? String

    let controller = ASAuthorizationController(authorizationRequests: [request])
    let session = AuthorizationSession(controller: controller) { [weak self] outcome in
      self?.finishSignIn(outcome: outcome, result: result)
    }
    activeSessions.append(session)
    controller.delegate = session
    controller.presentationContextProvider = session
    controller.performRequests()
  }

  private func finishSignIn(
    outcome: Result<ASAuthorizationAppleIDCredential, Error>,
    result: @escaping FlutterResult
  ) {
    activeSessions.removeAll { $0.isFinished }

    switch outcome {
    case .success(let credential):
      result(SignInPayload.encode(credential))
    case .failure(let error):
      result(SignInPayload.flutterError(for: error))
    }
  }

  private func handleGetCredentialState(
    userIdentifier: String, result: @escaping FlutterResult
  ) {
    let provider = ASAuthorizationAppleIDProvider()
    provider.getCredentialState(forUserID: userIdentifier) { state, error in
      DispatchQueue.main.async {
        if let error = error {
          result(
            FlutterError(
              code: "authorization_failed",
              message: error.localizedDescription,
              details: nil))
          return
        }
        result(Int(state.rawValue))
      }
    }
  }
}
