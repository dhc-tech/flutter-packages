// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';

import 'src/apple_sign_in_windows_impl.dart';

export 'src/apple_sign_in_windows_impl.dart' show AppleSignInDesktopConfig, AppleSignInWindowsImpl;

/// The Windows implementation of `apple_sign_in_plugin`.
class AppleSignInPluginWindows {
  /// Registers the Windows implementation as the active platform instance.
  static void registerWith() {
    AppleSignInPlatform.instance = AppleSignInWindowsImpl();
  }
}
