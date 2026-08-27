// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/attachment.dart';
import '../models/attachment_source.dart';
import '../models/attachment_type.dart';
import 'renderer.dart';

/// Full-view image renderer with pinch-to-zoom / pan via [InteractiveViewer].
class ImageAttachmentRenderer extends AttachmentRenderer {
  const ImageAttachmentRenderer();

  @override
  AttachmentType get type => .image;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    final image = _resolveImage(attachment);
    if (image == null) {
      return const Center(child: Text('Image unavailable'));
    }
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5,
      child: Center(child: image),
    );
  }

  Widget? _resolveImage(Attachment attachment) {
    final localPath = attachment.localPath;
    if (localPath != null) {
      return Image.file(File(localPath), fit: BoxFit.contain);
    }
    final url =
        attachment.remoteUrl ??
        (attachment.source is UrlAttachmentSource
            ? (attachment.source as UrlAttachmentSource).url
            : null);
    if (url != null) {
      return Image.network(url, fit: BoxFit.contain);
    }
    return null;
  }
}
