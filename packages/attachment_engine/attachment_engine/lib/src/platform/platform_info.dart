// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

/// Injectable abstraction over the running platform, so platform-branching
/// logic (e.g. "iOS gets an in-app Office viewer, Android falls back to
/// external-open") stays unit testable without depending directly on
/// `dart:io`'s `Platform` (which cannot be faked in tests). Mirrors the
/// existing injectable-dependency pattern used elsewhere in this package
/// (e.g. `ConnectivityChecker` in `attachment_resolver.dart`).
abstract class PlatformInfo {
  const PlatformInfo();

  bool get isIOS;
  bool get isAndroid;
}

/// Default [PlatformInfo] backed by `dart:io`'s `Platform`.
class DefaultPlatformInfo extends PlatformInfo {
  const DefaultPlatformInfo();

  @override
  bool get isIOS => Platform.isIOS;

  @override
  bool get isAndroid => Platform.isAndroid;
}
