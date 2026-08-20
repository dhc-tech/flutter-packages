// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';

/// The iOS/macOS implementation of `apple_sign_in_plugin`.
///
/// This class registers the shared [MethodChannelAppleSignIn]
/// implementation as [AppleSignInPlatform.instance] — the platform
/// difference for this plugin is entirely in the native Swift code under
/// `darwin/`, so no Darwin-specific Dart subclass is needed.
class AppleSignInPluginDarwin {
  /// Registers this class as the default instance of [AppleSignInPlatform].
  static void registerWith() {
    AppleSignInPlatform.instance = MethodChannelAppleSignIn();
  }
}
