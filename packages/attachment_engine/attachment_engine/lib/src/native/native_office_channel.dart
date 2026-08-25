// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart'
    show AttachmentEnginePlatform;

/// In-app Office document preview. iOS: presents a native `QLPreviewController`
/// (QuickLook) modally over the Flutter view. Android: no in-app Office
/// viewer exists, so the platform implementation gracefully degrades to the
/// existing external-open flow (`ACTION_VIEW` + `FileProvider`) — this is a
/// documented platform limitation, not a bug.
class NativeOfficeChannel {
  NativeOfficeChannel._();

  static Future<void> openOfficePreview(String path) =>
      AttachmentEnginePlatform.instance.openOfficePreview(path);
}
