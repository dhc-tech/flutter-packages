import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../renderers/renderer.dart';

/// Full-screen(-capable) attachment viewer. Routes to the appropriate
/// [AttachmentRenderer] via [RendererRegistry] based on the attachment's
/// detected type.
class AttachmentViewer extends StatelessWidget {
  AttachmentViewer({
    super.key,
    required this.attachment,
    RendererRegistry? registry,
  }) : registry = registry ?? RendererRegistry();

  final Attachment attachment;
  final RendererRegistry registry;

  @override
  Widget build(BuildContext context) {
    return registry.build(context, attachment);
  }
}
