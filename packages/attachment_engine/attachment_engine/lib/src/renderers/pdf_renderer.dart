// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import '../native/native_pdf_channel.dart';
import 'renderer.dart';

/// Remembers the last-viewed page per attachment so reopening a PDF resumes
/// where the reader left off, instead of always restarting at page one.
///
/// The default [InMemoryPdfPageMemory] only lives for the app session (lost
/// on restart) and needs no setup. Pass a different implementation to
/// [PdfAttachmentRenderer] (e.g. one backed by `shared_preferences` or your
/// own storage) to persist it across restarts — nothing else about the
/// renderer needs to change.
abstract class PdfPageMemory {
  /// The last page (0-indexed) viewed for the attachment identified by
  /// [key], or null if none is recorded.
  int? lastPage(String key);

  /// Records [page] (0-indexed) as the last-viewed page for [key].
  void savePage(String key, int page);
}

/// Session-only [PdfPageMemory]: fast, dependency-free, and the default for
/// [PdfAttachmentRenderer]. Cleared when the app process restarts.
class InMemoryPdfPageMemory implements PdfPageMemory {
  final Map<String, int> _pages = {};

  @override
  int? lastPage(String key) => _pages[key];

  @override
  void savePage(String key, int page) => _pages[key] = page;
}

/// A single, shared [InMemoryPdfPageMemory] so page position survives
/// across renderer instances (e.g. leaving and reopening the same
/// attachment) within one app session, without callers having to thread one
/// through themselves.
final defaultPdfPageMemory = InMemoryPdfPageMemory();

/// Full-view PDF renderer backed by [NativePdfController], which wraps
/// native PDFKit (iOS) / `PdfRenderer` (Android) rendering — see README
/// for justification. Zoom/scroll stays purely in Dart via
/// [InteractiveViewer] around the rendered page image; paging is handled
/// with a [PageView] of per-page rendered bitmaps.
///
/// Resumes on the last-viewed page (see [pageMemory]) and shows a retry
/// affordance instead of a dead end when opening or rendering fails.
class PdfAttachmentRenderer extends AttachmentRenderer {
  PdfAttachmentRenderer({PdfPageMemory? pageMemory})
    : pageMemory = pageMemory ?? defaultPdfPageMemory;

  final PdfPageMemory pageMemory;

  @override
  AttachmentType get type => AttachmentType.pdf;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    final path = attachment.localPath;
    if (path == null) {
      return const Center(child: Text('PDF unavailable'));
    }
    return _PdfView(
      path: path,
      pageMemoryKey: attachment.id,
      pageMemory: pageMemory,
    );
  }
}

class _PdfView extends StatefulWidget {
  const _PdfView({
    required this.path,
    required this.pageMemoryKey,
    required this.pageMemory,
  });
  final String path;
  final String pageMemoryKey;
  final PdfPageMemory pageMemory;

  @override
  State<_PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<_PdfView> {
  NativePdfController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => _error = null);
    try {
      final controller = await NativePdfController.open(widget.path);
      if (!mounted) {
        await controller.close();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Unable to render PDF'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _open, child: const Text('Retry')),
          ],
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final lastPage = widget.pageMemory.lastPage(widget.pageMemoryKey);
    final startPage = (lastPage != null && lastPage < controller.pageCount)
        ? lastPage
        : 0;
    return PageView.builder(
      controller: PageController(initialPage: startPage),
      itemCount: controller.pageCount,
      onPageChanged: (page) =>
          widget.pageMemory.savePage(widget.pageMemoryKey, page),
      itemBuilder: (context, index) =>
          _PdfPage(controller: controller, index: index),
    );
  }
}

class _PdfPage extends StatefulWidget {
  const _PdfPage({required this.controller, required this.index});
  final NativePdfController controller;
  final int index;

  @override
  State<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<_PdfPage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _render();
  }

  Future<void> _render() async {
    if (_bytes != null) return;
    setState(() => _failed = false);
    final size = MediaQuery.of(context).size;
    final width = (size.width * MediaQuery.of(context).devicePixelRatio)
        .round();
    final height = (size.height * MediaQuery.of(context).devicePixelRatio)
        .round();
    try {
      final bytes = await widget.controller.renderPage(
        widget.index,
        width: width,
        height: height,
      );
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Unable to render this page'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _render, child: const Text('Retry')),
          ],
        ),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Center(child: Image.memory(bytes)),
    );
  }
}
