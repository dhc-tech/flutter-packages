// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'apple_sign_in_desktop_impl.dart';

export 'apple_sign_in_desktop_impl.dart' show AppleSignInDesktopConfig, AppleSignInDesktopImpl;

/// The Windows implementation of [AppleSignInDesktopImpl].
class AppleSignInWindowsImpl extends AppleSignInDesktopImpl {
  /// Constructs [AppleSignInWindowsImpl] using the Windows MethodChannel.
  AppleSignInWindowsImpl() : super(channelName: 'apple_sign_in_plugin_windows');
}
