// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/apple_sign_in_web_impl.dart';

export 'src/apple_sign_in_web_impl.dart' show AppleSignInWebConfig, AppleSignInWebImpl;

/// The Flutter Web implementation of `apple_sign_in_plugin`.
class AppleSignInPluginWeb {
  /// Creates a new [AppleSignInPluginWeb]. Stateless; only [registerWith]
  /// is actually used, by Flutter's web plugin registrant.
  const AppleSignInPluginWeb();

  /// Registers the web implementation as the active platform instance.
  static void registerWith([Registrar? registrar]) {
    AppleSignInPlatform.instance = AppleSignInWebImpl();
  }
}
