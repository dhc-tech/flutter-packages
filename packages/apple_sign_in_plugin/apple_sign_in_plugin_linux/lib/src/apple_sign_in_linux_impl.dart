// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'apple_sign_in_desktop_impl.dart';

export 'apple_sign_in_desktop_impl.dart'
    show AppleSignInDesktopConfig, AppleSignInDesktopImpl;

/// The Linux implementation of [AppleSignInDesktopImpl].
class AppleSignInLinuxImpl extends AppleSignInDesktopImpl {
  /// Constructs [AppleSignInLinuxImpl] using the Linux MethodChannel.
  AppleSignInLinuxImpl() : super(channelName: 'apple_sign_in_plugin_linux');
}
