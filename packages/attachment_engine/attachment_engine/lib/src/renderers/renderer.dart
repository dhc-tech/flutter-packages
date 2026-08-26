// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';

import '../config/attachment_engine_config.dart';
import '../models/attachment.dart';
import '../models/attachment_type.dart';
import 'archive_renderer.dart';
import 'audio_renderer.dart';
import 'csv_renderer.dart';
import 'html_renderer.dart';
import 'image_renderer.dart';
import 'office_renderer.dart';
import 'pdf_renderer.dart';
import 'scorm_renderer.dart';
import 'text_renderer.dart';
import 'unknown_renderer.dart';
import 'video_renderer.dart';

/// Builds the full-viewer widget for a resolved, ready-to-render
/// [Attachment]. `localPath` is guaranteed non-null/existing by the time a
/// renderer is invoked (resolution happens upstream).
typedef AttachmentRendererBuilder =
    Widget Function(BuildContext context, Attachment attachment);

/// A pluggable full-view renderer for a specific [AttachmentType].
abstract class AttachmentRenderer {
  const AttachmentRenderer();

  AttachmentType get type;

  Widget build(BuildContext context, Attachment attachment);
}

/// Registry mapping [AttachmentType] to the [AttachmentRenderer] used to
/// build its full-viewer widget, falling back to [UnknownAttachmentRenderer]
/// (external-open affordance) for anything unregistered.
class RendererRegistry {
  RendererRegistry({
    List<AttachmentRenderer>? renderers,
    this.rendererConfig = const RendererConfig(),
    this.externalOpenConfig = const ExternalOpenConfig(),
  }) : _renderers = {
         for (final r in renderers ?? _defaultRenderers()) r.type: r,
       };

  final Map<AttachmentType, AttachmentRenderer> _renderers;

  /// Which types are enabled. A registered renderer whose type is disabled
  /// here is never used: [rendererFor]/[build] substitute
  /// [UnknownAttachmentRenderer] instead, they never crash and never
  /// silently use a different real renderer.
  final RendererConfig rendererConfig;

  /// Threaded into the [UnknownAttachmentRenderer] fallback so a
  /// disabled/unsupported type also honors external-open policy.
  final ExternalOpenConfig externalOpenConfig;

  static List<AttachmentRenderer> _defaultRenderers() => [
    const ImageAttachmentRenderer(),
    PdfAttachmentRenderer(),
    const VideoAttachmentRenderer(),
    const AudioAttachmentRenderer(),
    const HtmlAttachmentRenderer(),
    const CsvAttachmentRenderer(),
    const TextAttachmentRenderer(),
    const ScormAttachmentRenderer(),
    const OfficeAttachmentRenderer(),
    const ArchiveAttachmentRenderer(),
  ];

  void register(AttachmentRenderer renderer) {
    _renderers[renderer.type] = renderer;
  }

  AttachmentRenderer rendererFor(AttachmentType type) {
    final registered = _renderers[type];
    if (registered == null) {
      return UnknownAttachmentRenderer(externalOpenConfig: externalOpenConfig);
    }
    if (type != AttachmentType.unknown && !rendererConfig.isEnabled(type)) {
      return UnknownAttachmentRenderer(
        externalOpenConfig: externalOpenConfig,
        disabledByConfig: true,
      );
    }
    return registered;
  }

  Widget build(BuildContext context, Attachment attachment) {
    return rendererFor(attachment.attachmentType).build(context, attachment);
  }
}
