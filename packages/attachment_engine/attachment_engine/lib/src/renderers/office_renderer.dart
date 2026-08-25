import 'package:flutter/widgets.dart';

import '../config/attachment_engine_config.dart';
import '../models/attachment.dart';
import '../models/attachment_type.dart';
import '../native/native_office_channel.dart';
import '../native/native_open_channel.dart';
import '../platform/platform_info.dart';
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
/// Platform strategy is intentionally asymmetric:
/// - iOS: genuine in-app preview via [NativeOfficeChannel], backed by
///   Apple's `QLPreviewController` (QuickLook) — a zero-dependency native
///   framework that renders these formats directly.
/// - Android: no in-app Office viewer exists, so this falls back to
///   [NativeOpenChannel]'s external-open flow (`ACTION_VIEW` +
///   `FileProvider`). This is a documented platform limitation, not a bug.
///
/// [OfficeConversionStrategy] remains available as an extension point for a
/// host app with server-side or on-device conversion, used on either
/// platform when supplied.
class OfficeAttachmentRenderer extends AttachmentRenderer {
  const OfficeAttachmentRenderer({
    this.conversionStrategy,
    this.platformInfo = const DefaultPlatformInfo(),
    this.externalOpenConfig = const ExternalOpenConfig(),
  });

  final OfficeConversionStrategy? conversionStrategy;

  /// Injectable platform check so iOS-vs-Android strategy selection is
  /// unit testable without depending on `dart:io`'s `Platform` directly.
  final PlatformInfo platformInfo;

  /// On Android (no in-app Office viewer), this governs whether the
  /// external-open fallback is attempted at all. When
  /// `allowExternalFallback` is false, Android reports an "external open
  /// disabled" state instead of opening externally.
  final ExternalOpenConfig externalOpenConfig;

  @override
  AttachmentType get type => AttachmentType.office;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    return _OfficeView(
      attachment: attachment,
      conversionStrategy: conversionStrategy,
      platformInfo: platformInfo,
      externalOpenConfig: externalOpenConfig,
    );
  }
}

class _OfficeView extends StatefulWidget {
  const _OfficeView({
    required this.attachment,
    required this.platformInfo,
    this.conversionStrategy,
    this.externalOpenConfig = const ExternalOpenConfig(),
  });
  final Attachment attachment;
  final OfficeConversionStrategy? conversionStrategy;
  final PlatformInfo platformInfo;
  final ExternalOpenConfig externalOpenConfig;

  @override
  State<_OfficeView> createState() => _OfficeViewState();
}

class _OfficeViewState extends State<_OfficeView> {
  bool _opening = false;
  String? _error;
  bool _previewedInApp = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => _opening = true);
    try {
      final converted = await widget.conversionStrategy?.convert(
        widget.attachment,
      );
      final path = converted ?? widget.attachment.localPath;
      if (path == null) {
        setState(() => _error = 'No local file to open.');
        return;
      }
      if (widget.platformInfo.isIOS) {
        // Genuine in-app preview via QuickLook — requires a local file URL,
        // which the resolver guarantees by the time this renderer runs.
        await NativeOfficeChannel.openOfficePreview(path);
        _previewedInApp = true;
      } else if (!widget.externalOpenConfig.allowExternalFallback) {
        // Android has no in-app Office viewer; normally it falls back to
        // an external app, but that fallback is disabled here.
        setState(
          () => _error = 'Opening this attachment externally is disabled.',
        );
      } else {
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

  @override
  Widget build(BuildContext context) {
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
