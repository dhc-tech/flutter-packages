// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';

import '../config/attachment_engine_config.dart';
import '../models/attachment.dart';
import '../models/attachment_type.dart';
import '../native/native_open_channel.dart';
import 'renderer.dart';

/// Fallback renderer used for [AttachmentType.unknown], any type without a
/// registered renderer, or any type disabled via `RendererConfig`: shows a
/// generic icon and offers external open / download instead of failing
/// outright, unless [externalOpenConfig] disallows the external fallback,
/// in which case it reports a disabled state instead of an open affordance.
class UnknownAttachmentRenderer extends AttachmentRenderer {
  const UnknownAttachmentRenderer({
    this.externalOpenConfig = const ExternalOpenConfig(),
    this.disabledByConfig = false,
  });

  /// Governs whether the "Open externally" affordance is shown.
  final ExternalOpenConfig externalOpenConfig;

  /// True when this widget is standing in for a type that has a real
  /// renderer that was explicitly disabled (as opposed to a genuinely
  /// unsupported format), so messaging can be more specific.
  final bool disabledByConfig;

  @override
  AttachmentType get type => AttachmentType.unknown;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    final allowExternal = externalOpenConfig.allowExternalFallback;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text(attachment.name),
          const SizedBox(height: 8),
          if (!allowExternal)
            Text(
              disabledByConfig
                  ? 'Viewing this attachment type has been disabled.'
                  : 'This attachment type is not supported.',
            )
          else if (attachment.localPath != null)
            GestureDetector(
              onTap: () =>
                  NativeOpenChannel.openExternally(attachment.localPath!),
              child: const Text('Open externally'),
            ),
        ],
      ),
    );
  }
}
