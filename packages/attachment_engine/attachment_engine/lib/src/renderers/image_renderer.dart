// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/attachment.dart';
import '../models/attachment_source.dart';
import '../models/attachment_type.dart';
import 'renderer.dart';
import 'renderer_error_state.dart';

/// Full-view image renderer with pinch-to-zoom / pan via [InteractiveViewer].
class ImageAttachmentRenderer extends AttachmentRenderer {
  const ImageAttachmentRenderer();

  @override
  AttachmentType get type => .image;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    final image = _resolveImage(attachment);
    if (image == null) {
      return const RendererErrorState(
        message: 'Image unavailable',
        icon: Icons.broken_image_outlined,
      );
    }
    return InteractiveViewer(
      // The default `boundaryMargin` is `EdgeInsets.zero`, which pins the
      // content's bounds tightly to the viewport at every scale — combined
      // with `constrained: true` (the default), that's what actually made
      // "zoom out" feel broken: shrinking below the content's fitted size
      // had nowhere to pan into, so the gesture had no visible effect once
      // the content already filled the viewport. Effectively-infinite
      // boundary margin is the standard fix for a proper pinch-zoom image
      // viewer — it gives the transform room to move regardless of the
      // image's own aspect ratio or pixel size.
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.1,
      maxScale: 5,
      child: Center(
        child: Image(
          image: image,
          fit: .contain,
          errorBuilder: (context, error, stackTrace) =>
              const RendererErrorState(
                message: 'Image unavailable',
                icon: Icons.broken_image_outlined,
              ),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const CircularProgressIndicator(),
        ),
      ),
    );
  }

  ImageProvider? _resolveImage(Attachment attachment) {
    final localPath = attachment.localPath;
    if (localPath != null) {
      return FileImage(File(localPath));
    }
    final url =
        attachment.remoteUrl ??
        (attachment.source is UrlAttachmentSource
            ? (attachment.source as UrlAttachmentSource).url
            : null);
    if (url != null) {
      return NetworkImage(url);
    }
    return null;
  }
}
