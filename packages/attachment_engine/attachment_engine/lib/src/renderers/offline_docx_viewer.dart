// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Fully offline DOCX renderer — no network access at any point.
///
/// Loads a bundled HTML shell (`assets/office_offline/docx_viewer.html`)
/// containing vendored, unmodified copies of `docx-preview` (Apache-2.0)
/// and `JSZip` (MIT) — see `assets/office_offline/README.md` for
/// provenance/licenses — via [WebViewController.loadFlutterAsset], then
/// hands the document's bytes to it as base64 through a JavaScript call
/// once the shell has finished loading its scripts.
///
/// This is the genuine offline alternative to the Microsoft Office Online
/// WebView fallback in `OfficeAttachmentRenderer` (which needs a
/// connection): same in-app-WebView delivery mechanism, but the rendering
/// itself happens entirely on-device against bundled code, not a remote
/// document server.
class OfflineDocxViewer extends StatefulWidget {
  const OfflineDocxViewer({super.key, required this.localPath, this.onFailed});

  /// Path to the already-resolved `.docx` file to render.
  final String localPath;

  /// Called if the bundled viewer fails to load the shell or render the
  /// document, so a caller can fall through to another strategy.
  final VoidCallback? onFailed;

  @override
  State<OfflineDocxViewer> createState() => _OfflineDocxViewerState();
}

class _OfflineDocxViewerState extends State<OfflineDocxViewer> {
  late final WebViewController _controller;
  bool _renderRequested = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(.unrestricted)
      ..addJavaScriptChannel(
        'OfflineDocViewer',
        onMessageReceived: (message) {
          if (message.message.startsWith('error:')) widget.onFailed?.call();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _renderDocument(),
          onWebResourceError: (_) => widget.onFailed?.call(),
        ),
      )
      ..loadFlutterAsset(
        'packages/attachment_engine/assets/office_offline/docx_viewer.html',
      );
  }

  Future<void> _renderDocument() async {
    // onPageFinished can fire more than once (e.g. in-page navigation);
    // only kick off the render once per widget lifetime.
    if (_renderRequested) return;
    _renderRequested = true;
    try {
      final bytes = await File(widget.localPath).readAsBytes();
      final base64Data = base64Encode(bytes);
      await _controller.runJavaScript('renderDocx("$base64Data")');
    } catch (_) {
      widget.onFailed?.call();
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
