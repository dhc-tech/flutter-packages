// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import '../manager/attachment_manager.dart';
import '../models/attachment.dart';
import '../models/resolved_attachment.dart';
import '../renderers/renderer.dart';

/// Signature for a caller-supplied resolve step. Defaults to
/// `AttachmentManager.instance.open`.
typedef AttachmentResolveCallback = Future<ResolvedAttachment> Function(
  Attachment attachment,
);

/// Full-screen(-capable) attachment viewer. Routes to the appropriate
/// [AttachmentRenderer] via [RendererRegistry] based on the attachment's
/// detected type.
///
/// If [attachment] does not already carry a `localPath`, the viewer
/// resolves it itself (via [resolve], defaulting to
/// `AttachmentManager.instance.open`) and shows [loadingBuilder] /
/// [errorBuilder] while that happens — callers no longer have to pre-resolve
/// before constructing this widget. Passing an already-resolved
/// [attachment] (`localPath` set) skips this step entirely, preserving the
/// previous synchronous behavior.
class AttachmentViewer extends StatefulWidget {
  AttachmentViewer({
    super.key,
    required this.attachment,
    RendererRegistry? registry,
    AttachmentResolveCallback? resolve,
    this.loadingBuilder,
    this.errorBuilder,
  }) : registry = registry ?? RendererRegistry(),
       resolve = resolve ?? _defaultResolve;

  final Attachment attachment;
  final RendererRegistry registry;

  /// Resolves [attachment] to a local, renderable file. Defaults to
  /// `AttachmentManager.instance.open`.
  final AttachmentResolveCallback resolve;

  /// Shown while an unresolved [attachment] is being resolved. Defaults to a
  /// centered [CircularProgressIndicator].
  final WidgetBuilder? loadingBuilder;

  /// Shown when resolution fails. Defaults to a centered error message.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  static Future<ResolvedAttachment> _defaultResolve(Attachment attachment) {
    return AttachmentManager.instance.open(attachment);
  }

  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  late Future<Attachment>? _resolution;

  @override
  void initState() {
    super.initState();
    _resolution = _needsResolution(widget.attachment) ? _resolve() : null;
  }

  @override
  void didUpdateWidget(AttachmentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment != widget.attachment) {
      _resolution = _needsResolution(widget.attachment) ? _resolve() : null;
    }
  }

  bool _needsResolution(Attachment attachment) => attachment.localPath == null;

  Future<Attachment> _resolve() async {
    final resolved = await widget.resolve(widget.attachment);
    return resolved.attachment.copyWith(localPath: resolved.localPath);
  }

  @override
  Widget build(BuildContext context) {
    final resolution = _resolution;
    if (resolution == null) {
      return widget.registry.build(context, widget.attachment);
    }
    return FutureBuilder<Attachment>(
      future: resolution,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(context, snapshot.error!) ??
              Center(
                child: Text('Failed to open attachment: ${snapshot.error}'),
              );
        }
        if (!snapshot.hasData) {
          return widget.loadingBuilder?.call(context) ??
              const Center(child: CircularProgressIndicator());
        }
        return widget.registry.build(context, snapshot.data!);
      },
    );
  }
}
