// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/attachment_engine_config.dart';
import '../models/attachment.dart';
import '../models/attachment_source.dart';
import '../models/attachment_type.dart';
import '../native/native_office_channel.dart';
import '../native/native_open_channel.dart';
import '../platform/platform_info.dart';
import '../resolver/attachment_resolver.dart'
    show ConnectivityChecker, DefaultConnectivityChecker;
import 'offline_docx_viewer.dart';
import 'offline_pptx_viewer.dart';
import 'offline_spreadsheet_viewer.dart';
import 'pdf_renderer.dart';
import 'renderer.dart';

/// Which bundled, genuinely-offline in-app renderer applies to a given
/// office document, if any.
enum _OfflineFormat { none, docx, spreadsheet, pptx }

/// Extension point for a host app to plug in server-side or on-device
/// office-to-PDF conversion (there is no server in this fresh project to
/// call). If provided, [OfficeAttachmentRenderer] will use it to obtain a
/// renderable PDF path instead of falling back to the OS document viewer.
abstract class OfficeConversionStrategy {
  /// Converts the office document at [attachment.localPath] to a PDF (or
  /// other directly-renderable format) local path, or returns null if
  /// conversion isn't possible for this attachment.
  Future<String?> convert(Attachment attachment);
}

/// Renders office documents (doc/docx/xls/xlsx/ppt/pptx/odt/...).
///
/// In-app viewing is always preferred over sending the user out to another
/// app; external-open is only a last resort when nothing else can show the
/// document in-app:
/// 1. On iOS: genuine in-app preview via [NativeOfficeChannel], backed by
///    Apple's `QLPreviewController` (QuickLook) — a zero-dependency native
///    framework that renders these formats directly and natively, so it
///    always wins on iOS (already fully offline).
/// 2. On Android, for formats with a bundled genuinely-offline renderer —
///    currently `.docx` ([OfflineDocxViewer], via `docx-preview` +
///    `JSZip`), `.xlsx`/`.xls`/`.xlsm` ([OfflineSpreadsheetViewer], via
///    SheetJS), and `.pptx` ([OfflinePptxViewer], via PPTXjs) — see
///    `assets/office_offline/README.md` for what's covered and what isn't
///    (legacy `.doc`/`.ppt`, OpenDocument formats fall through to step 3+
///    instead, for lack of a suitable dependency-free JS renderer). These
///    need no network at all, so they win over Office Online below.
/// 3. On Android otherwise (or if step 2 doesn't apply/fails): while the
///    device has a connection and the attachment has a public URL,
///    *Microsoft's own* Office Online viewer
///    (`view.officeapps.live.com`) is shown in-app via [webview_flutter]
///    — still avoiding a trip to another app, and with better fidelity
///    than a generic doc→PDF conversion.
/// 4. If none of the above applies but a [conversionStrategy] is supplied
///    and successfully converts the document to a PDF, that PDF is
///    rendered in-app using [PdfAttachmentRenderer]. This is a
///    deliberately lower-priority, fully optional extension point —
///    automated doc→PDF conversion is lossy for complex documents, so it
///    only kicks in when nothing better is available, and never on iOS
///    (QuickLook already covers it there).
/// 5. Only when none of the above apply does this fall back to
///    [NativeOpenChannel]'s external-open flow (`ACTION_VIEW` +
///    `FileProvider`) as the genuine last resort.
class OfficeAttachmentRenderer extends AttachmentRenderer {
  const OfficeAttachmentRenderer({
    this.conversionStrategy,
    this.platformInfo = const DefaultPlatformInfo(),
    this.externalOpenConfig = const ExternalOpenConfig(),
    this.connectivityChecker = const DefaultConnectivityChecker(),
  });

  final OfficeConversionStrategy? conversionStrategy;

  /// Injectable platform check so iOS-vs-Android strategy selection is
  /// unit testable without depending on `dart:io`'s `Platform` directly.
  final PlatformInfo platformInfo;

  /// On Android (no in-app Office viewer and no usable Office Online
  /// fallback), this governs whether the external-open fallback is
  /// attempted at all. When `allowExternalFallback` is false, Android
  /// reports an "external open disabled" state instead of opening
  /// externally.
  final ExternalOpenConfig externalOpenConfig;

  /// Used to decide whether the Microsoft Office Online viewer fallback is
  /// worth attempting (it needs a network connection to load
  /// `view.officeapps.live.com` and fetch the document from its public
  /// URL).
  final ConnectivityChecker connectivityChecker;

  @override
  AttachmentType get type => AttachmentType.office;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    return _OfficeView(
      attachment: attachment,
      conversionStrategy: conversionStrategy,
      platformInfo: platformInfo,
      externalOpenConfig: externalOpenConfig,
      connectivityChecker: connectivityChecker,
    );
  }
}

class _OfficeView extends StatefulWidget {
  const _OfficeView({
    required this.attachment,
    required this.platformInfo,
    this.conversionStrategy,
    this.externalOpenConfig = const ExternalOpenConfig(),
    this.connectivityChecker = const DefaultConnectivityChecker(),
  });
  final Attachment attachment;
  final OfficeConversionStrategy? conversionStrategy;
  final PlatformInfo platformInfo;
  final ExternalOpenConfig externalOpenConfig;
  final ConnectivityChecker connectivityChecker;

  @override
  State<_OfficeView> createState() => _OfficeViewState();
}

class _OfficeViewState extends State<_OfficeView> {
  bool _opening = false;
  String? _error;
  bool _previewedInApp = false;
  _OfflineFormat _offlineFormat = _OfflineFormat.none;
  String? _convertedPdfPath;
  String? _officeOnlineUrl;

  @override
  void initState() {
    super.initState();
    _open();
  }

  /// The document's own public URL, if it has one — required for
  /// Microsoft's Office Online viewer, which fetches the file itself
  /// rather than accepting a local path.
  String? get _publicDocumentUrl {
    final remoteUrl = widget.attachment.remoteUrl;
    if (remoteUrl != null) return remoteUrl;
    final source = widget.attachment.source;
    return source is UrlAttachmentSource ? source.url : null;
  }

  /// Which bundled offline renderer (if any) covers this attachment's
  /// extension. See `assets/office_offline/README.md` for what's covered.
  _OfflineFormat get _offlineFormatForExtension {
    switch (widget.attachment.extension?.toLowerCase()) {
      case 'docx':
        return _OfflineFormat.docx;
      case 'xlsx':
      case 'xls':
      case 'xlsm':
        return _OfflineFormat.spreadsheet;
      case 'pptx':
        return _OfflineFormat.pptx;
      default:
        return _OfflineFormat.none;
    }
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (widget.platformInfo.isIOS) {
        final path = widget.attachment.localPath;
        if (path == null) {
          setState(() => _error = 'No local file to open.');
          return;
        }
        // Genuine in-app preview via QuickLook — requires a local file URL,
        // which the resolver guarantees by the time this renderer runs.
        // Always wins on iOS; conversion isn't needed here.
        await NativeOfficeChannel.openOfficePreview(path);
        _previewedInApp = true;
        return;
      }

      // Android, a format with a bundled offline renderer: it wins over
      // Office Online below — it needs no network at all.
      final offlineFormat = _offlineFormatForExtension;
      if (offlineFormat != _OfflineFormat.none &&
          widget.attachment.localPath != null) {
        setState(() => _offlineFormat = offlineFormat);
        return;
      }

      await _tryOfficeOnlineThenConversionThenExternal();
    } catch (e) {
      setState(() => _error = 'Unable to open this document.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// The fallback chain used once neither iOS QuickLook nor the offline
  /// DOCX viewer applies (or the offline viewer failed): Office Online,
  /// then a supplied conversion, then external-open as the genuine last
  /// resort.
  Future<void> _tryOfficeOnlineThenConversionThenExternal() async {
    // Prefer Microsoft's own Office Online viewer (still in-app, via a
    // WebView) over both the conversion fallback below and sending the
    // user to an external app — it needs a public URL for the document
    // and an actual connection to reach it.
    final publicUrl = _publicDocumentUrl;
    if (publicUrl != null && await widget.connectivityChecker.hasConnection()) {
      if (mounted) {
        setState(() => _officeOnlineUrl = _officeOnlineViewerUrl(publicUrl));
      }
      return;
    }

    // Office Online isn't usable (offline / no public URL). A supplied
    // conversion is a deliberately lower-priority, fully optional
    // fallback — doc→PDF conversion is lossy for complex documents — so
    // it's only tried here, once nothing better is available.
    final converted = await widget.conversionStrategy?.convert(
      widget.attachment,
    );
    if (converted != null) {
      if (mounted) setState(() => _convertedPdfPath = converted);
      return;
    }

    await _openExternallyAsLastResort();
  }

  static String _officeOnlineViewerUrl(String documentUrl) {
    final encoded = Uri.encodeComponent(documentUrl);
    return 'https://view.officeapps.live.com/op/view.aspx?src=$encoded';
  }

  /// If the bundled offline renderer itself fails, fall through to the
  /// same chain [_open] would have used had it not applied at all.
  Future<void> _offlineRendererFailed() async {
    if (mounted) setState(() => _offlineFormat = _OfflineFormat.none);
    await _tryOfficeOnlineThenConversionThenExternal();
  }

  /// If Office Online itself fails to load in the WebView, fall through to
  /// the same lower-priority steps as above: conversion, then
  /// external-open.
  Future<void> _officeOnlineFailed() async {
    setState(() => _officeOnlineUrl = null);
    final converted = await widget.conversionStrategy?.convert(
      widget.attachment,
    );
    if (converted != null) {
      if (mounted) setState(() => _convertedPdfPath = converted);
      return;
    }
    await _openExternallyAsLastResort();
  }

  Future<void> _openExternallyAsLastResort() async {
    final path = widget.attachment.localPath;
    if (path == null) {
      if (mounted) setState(() => _error = 'No local file to open.');
      return;
    }
    if (!widget.externalOpenConfig.allowExternalFallback) {
      if (mounted) {
        setState(
          () => _error = 'Opening this attachment externally is disabled.',
        );
      }
      return;
    }
    final result = await NativeOpenChannel.openExternally(path);
    if (!result.success && mounted) {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_offlineFormat) {
      case _OfflineFormat.docx:
        return OfflineDocxViewer(
          localPath: widget.attachment.localPath!,
          onFailed: _offlineRendererFailed,
        );
      case _OfflineFormat.spreadsheet:
        return OfflineSpreadsheetViewer(
          localPath: widget.attachment.localPath!,
          onFailed: _offlineRendererFailed,
        );
      case _OfflineFormat.pptx:
        return OfflinePptxViewer(
          localPath: widget.attachment.localPath!,
          onFailed: _offlineRendererFailed,
        );
      case _OfflineFormat.none:
        break;
    }
    final convertedPdfPath = _convertedPdfPath;
    if (convertedPdfPath != null) {
      return PdfAttachmentRenderer().build(
        context,
        widget.attachment.copyWith(localPath: convertedPdfPath),
      );
    }
    final officeOnlineUrl = _officeOnlineUrl;
    if (officeOnlineUrl != null) {
      return _OfficeOnlineView(
        url: officeOnlineUrl,
        onFailed: _officeOnlineFailed,
      );
    }
    if (_opening) return const Center(child: SizedBox(width: 24, height: 24));
    if (_error != null) return Center(child: Text(_error!));
    return Center(
      child: Text(
        _previewedInApp
            ? 'Opened in the in-app document viewer.'
            : 'Opened in an external viewer.',
      ),
    );
  }
}

/// In-app WebView showing Microsoft's Office Online viewer for a
/// document's public URL. Calls [onFailed] on a load error so the caller
/// can fall through to external-open as the genuine last resort.
class _OfficeOnlineView extends StatefulWidget {
  const _OfficeOnlineView({required this.url, required this.onFailed});
  final String url;
  final VoidCallback onFailed;

  @override
  State<_OfficeOnlineView> createState() => _OfficeOnlineViewState();
}

class _OfficeOnlineViewState extends State<_OfficeOnlineView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onWebResourceError: (_) => widget.onFailed()),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
