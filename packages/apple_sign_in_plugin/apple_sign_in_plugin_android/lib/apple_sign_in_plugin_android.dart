// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'src/apple_sign_in_android_impl.dart';

export 'src/apple_sign_in_android_impl.dart' show AppleSignInAndroidConfig, AppleSignInAndroidImpl;

/// The Android implementation of `apple_sign_in_plugin`.
///
/// This class registers [AppleSignInAndroidImpl] as the active
/// [AppleSignInPlatform] instance when the plugin is loaded on Android.
///
/// Application code should interact with `AppleSignIn` from
/// `package:apple_sign_in_plugin/apple_sign_in_plugin.dart` rather
/// than with this class directly. The one exception is configuration:
/// set [AppleSignInAndroidImpl.config] (accessed via
/// [AppleSignInPlatform.instance]) before the first `signIn()` call.
class AppleSignInPluginAndroid {
  /// Registers the Android implementation as the active platform instance.
  static void registerWith() {
    AppleSignInPlatform.instance = AppleSignInAndroidImpl();
  }
}
