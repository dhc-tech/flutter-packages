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
import 'pdf_renderer.dart';
import 'renderer.dart';

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
///    always wins on iOS.
/// 2. On Android (no native in-app Office viewer): while the device has a
///    connection and the attachment has a public URL, *Microsoft's own*
///    Office Online viewer (`view.officeapps.live.com`) is shown in-app via
///    [webview_flutter] — still avoiding a trip to another app, and with
///    better fidelity than a generic doc→PDF conversion.
/// 3. If neither of the above applies (Android, offline or no public URL)
///    but a [conversionStrategy] is supplied and successfully converts the
///    document to a PDF, that PDF is rendered in-app using
///    [PdfAttachmentRenderer]. This is a deliberately lower-priority,
///    fully optional extension point — automated doc→PDF conversion is
///    lossy for complex documents, so it only kicks in when nothing better
///    is available, and never on iOS (QuickLook already covers it there).
/// 4. Only when none of the above apply does this fall back to
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

      // Android has no native in-app Office viewer. Prefer Microsoft's own
      // Office Online viewer (still in-app, via a WebView) over both the
      // conversion fallback below and sending the user to an external
      // app — it needs a public URL for the document and an actual
      // connection to reach it.
      final publicUrl = _publicDocumentUrl;
      if (publicUrl != null &&
          await widget.connectivityChecker.hasConnection()) {
        setState(() => _officeOnlineUrl = _officeOnlineViewerUrl(publicUrl));
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
        setState(() => _convertedPdfPath = converted);
        return;
      }

      final path = widget.attachment.localPath;
      if (path == null) {
        setState(() => _error = 'No local file to open.');
      } else if (!widget.externalOpenConfig.allowExternalFallback) {
        setState(
          () => _error = 'Opening this attachment externally is disabled.',
        );
      } else {
        // Genuine last resort: no in-app viewer on this platform, Office
        // Online unusable, and no (or failed) conversion, so hand off to
        // an external app.
        final result = await NativeOpenChannel.openExternally(path);
        if (!result.success) {
          setState(() => _error = result.message);
        }
      }
    } catch (e) {
      setState(() => _error = 'Unable to open this document.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  static String _officeOnlineViewerUrl(String documentUrl) {
    final encoded = Uri.encodeComponent(documentUrl);
    return 'https://view.officeapps.live.com/op/view.aspx?src=$encoded';
  }

  /// If Office Online itself fails to load in the WebView, fall through to
  /// the same lower-priority steps [_open] would have used had Office
  /// Online not been available at all: conversion, then external-open.
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
