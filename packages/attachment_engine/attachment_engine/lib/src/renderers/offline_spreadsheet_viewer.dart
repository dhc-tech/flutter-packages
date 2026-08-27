// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../util/chunked_file_reader.dart';

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
  late WebViewController _controller;
  bool _renderRequested = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
  }

  @override
  void didUpdateWidget(OfflineSpreadsheetViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A parent may reuse this same widget/State for a different
    // attachment; without rebuilding the controller, the previous
    // spreadsheet would keep showing instead of the new one loading.
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
        'packages/attachment_engine/assets/office_offline/xlsx_viewer.html',
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
      // See OfflineDocxViewer._renderDocument for why this is chunked
      // rather than base64Encode(await file.readAsBytes()).
      final base64Data = await readFileAsBase64Chunked(widget.localPath);
      await _controller.runJavaScript('renderSpreadsheet("$base64Data")');
    } catch (_) {
      _reportFailure();
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
