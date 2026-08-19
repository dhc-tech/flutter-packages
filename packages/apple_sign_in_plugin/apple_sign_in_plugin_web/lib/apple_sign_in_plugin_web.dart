// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/apple_sign_in_web_impl.dart';

export 'src/apple_sign_in_web_impl.dart' show AppleSignInWebConfig, AppleSignInWebImpl;

/// The Flutter Web implementation of `apple_sign_in_plugin`.
class AppleSignInPluginWeb {
  /// Registers the web implementation as the active platform instance.
  static void registerWith([Registrar? registrar]) {
    AppleSignInPlatform.instance = AppleSignInWebImpl();
  }
}
