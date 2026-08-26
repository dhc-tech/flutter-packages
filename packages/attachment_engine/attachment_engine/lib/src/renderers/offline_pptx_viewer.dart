// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Fully offline PPTX renderer — no network access at any point.
///
/// Same delivery mechanism as [OfflineDocxViewer]/[OfflineSpreadsheetViewer]
/// (see their dartdoc) — a bundled HTML shell
/// (`assets/office_offline/pptx_viewer.html`) loaded via
/// [WebViewController.loadFlutterAsset], backed here by a vendored,
/// unmodified copy of PPTXjs (MIT) plus its own small dependency set
/// (jQuery, `filereader.js`, D3/NVD3 for chart rendering) — see
/// `assets/office_offline/README.md` for provenance/licenses.
///
/// Only `.pptx` (OOXML) is covered — PPTXjs, like the DOCX/XLSX renderers
/// here, has no support for the legacy binary `.ppt` format.
class OfflinePptxViewer extends StatefulWidget {
  const OfflinePptxViewer({super.key, required this.localPath, this.onFailed});

  /// Path to the already-resolved `.pptx` file to render.
  final String localPath;

  /// Called if the bundled viewer fails to load the shell or render the
  /// document, so a caller can fall through to another strategy.
  final VoidCallback? onFailed;

  @override
  State<OfflinePptxViewer> createState() => _OfflinePptxViewerState();
}

class _OfflinePptxViewerState extends State<OfflinePptxViewer> {
  late WebViewController _controller;
  bool _renderRequested = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
  }

  @override
  void didUpdateWidget(OfflinePptxViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A parent may reuse this same widget/State for a different
    // attachment; without rebuilding the controller, the previous
    // presentation would keep showing instead of the new one loading.
    if (oldWidget.localPath != widget.localPath) {
      _renderRequested = false;
      _failed = false;
      setState(() => _controller = _buildController());
    }
  }

  WebViewController _buildController() {
    return WebViewController()
      ..setJavaScriptMode(.unrestricted)
      ..addJavaScriptChannel(
        'OfflineDocViewer',
        onMessageReceived: (message) {
          if (message.message.startsWith('error:')) _reportFailure();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _renderDocument(),
          onWebResourceError: (_) => _reportFailure(),
        ),
      )
      ..loadFlutterAsset(
        'packages/attachment_engine/assets/office_offline/pptx_viewer.html',
      );
  }

  /// Idempotent and mounted-safe — see [OfflineDocxViewer]'s
  /// `_reportFailure` for why this matters.
  void _reportFailure() {
    if (!mounted || _failed) return;
    _failed = true;
    widget.onFailed?.call();
  }

  Future<void> _renderDocument() async {
    if (_renderRequested) return;
    _renderRequested = true;
    try {
      final bytes = await File(widget.localPath).readAsBytes();
      final base64Data = base64Encode(bytes);
      await _controller.runJavaScript('renderPptx("$base64Data")');
    } catch (_) {
      _reportFailure();
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
