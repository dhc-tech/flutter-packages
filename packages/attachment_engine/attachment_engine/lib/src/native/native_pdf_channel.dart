// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/foundation.dart';

/// Replaces `pdfx`. Talks to native PDF rendering through
/// [AttachmentEnginePlatform]:
/// iOS: PDFKit (`PDFDocument`, `PDFPage.thumbnail`).
/// Android: `android.graphics.pdf.PdfRenderer`.
class NativePdfController {
  NativePdfController._(this._handle);

  final String _handle;
  bool _closed = false;

  /// Opens the PDF at [path] natively and returns a controller plus its
  /// page count.
  static Future<NativePdfController> open(String path) async {
    final result = await AttachmentEnginePlatform.instance.pdfOpen(path);
    final controller = NativePdfController._(result.handle);
    controller.pageCount = result.pageCount;
    return controller;
  }

  late int pageCount;

  /// Renders 1-based-safe zero-indexed [index] at [width]x[height] pixels,
  /// returning PNG-encoded bytes.
  Future<Uint8List> renderPage(
    int index, {
    required int width,
    required int height,
  }) async {
    final bytes = await AttachmentEnginePlatform.instance.pdfRenderPage(
      _handle,
      index,
      width: width,
      height: height,
    );
    return Uint8List.fromList(bytes);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await AttachmentEnginePlatform.instance.pdfClose(_handle);
  }
}
