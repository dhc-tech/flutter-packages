import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import '../native/native_pdf_channel.dart';
import 'renderer.dart';

/// Full-view PDF renderer backed by [NativePdfController], which wraps
/// native PDFKit (iOS) / `PdfRenderer` (Android) rendering — see README
/// for justification. Zoom/scroll stays purely in Dart via
/// [InteractiveViewer] around the rendered page image; paging is handled
/// with a [PageView] of per-page rendered bitmaps.
class PdfAttachmentRenderer extends AttachmentRenderer {
  const PdfAttachmentRenderer();

  @override
  AttachmentType get type => AttachmentType.pdf;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    final path = attachment.localPath;
    if (path == null) {
      return const Center(child: Text('PDF unavailable'));
    }
    return _PdfView(path: path);
  }
}

class _PdfView extends StatefulWidget {
  const _PdfView({required this.path});
  final String path;

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
      return const Center(child: Text('Unable to render PDF'));
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PageView.builder(
      itemCount: controller.pageCount,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= null;
    _render();
  }

  Future<void> _render() async {
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
      // Leave as loading indicator; a transient render failure shouldn't
      // crash the whole viewer.
    }
  }

  @override
  Widget build(BuildContext context) {
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
