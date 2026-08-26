// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Fully offline spreadsheet renderer (`.xlsx` and legacy `.xls`) — no
/// network access at any point.
///
/// Same delivery mechanism as [OfflineDocxViewer] — see its dartdoc — but
/// backed by a bundled, unmodified copy of SheetJS (Apache-2.0; see
/// `assets/office_offline/README.md`), which reads both OOXML (`.xlsx`)
/// and legacy binary (`.xls`) workbooks and renders each sheet as a plain
/// HTML table with tab buttons to switch between sheets.
class OfflineSpreadsheetViewer extends StatefulWidget {
  const OfflineSpreadsheetViewer({
    super.key,
    required this.localPath,
    this.onFailed,
  });

  /// Path to the already-resolved `.xlsx`/`.xls` file to render.
  final String localPath;

  /// Called if the bundled viewer fails to load the shell or render the
  /// document, so a caller can fall through to another strategy.
  final VoidCallback? onFailed;

  @override
  State<OfflineSpreadsheetViewer> createState() =>
      _OfflineSpreadsheetViewerState();
}

class _OfflineSpreadsheetViewerState extends State<OfflineSpreadsheetViewer> {
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
        'packages/attachment_engine/assets/office_offline/xlsx_viewer.html',
      );
  }

  Future<void> _renderDocument() async {
    if (_renderRequested) return;
    _renderRequested = true;
    try {
      final bytes = await File(widget.localPath).readAsBytes();
      final base64Data = base64Encode(bytes);
      await _controller.runJavaScript('renderSpreadsheet("$base64Data")');
    } catch (_) {
      widget.onFailed?.call();
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
