import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart'
    show AttachmentEnginePlatform, NativeOpenResult;

export 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart'
    show NativeOpenResult;

/// Replaces `open_filex`. iOS: `UIDocumentInteractionController` (falls
/// back to `QLPreviewController`-style presentation). Android:
/// `Intent.ACTION_VIEW` with a `FileProvider` content URI, inferred MIME
/// type, and `grantUriPermission`.
class NativeOpenChannel {
  NativeOpenChannel._();

  static Future<NativeOpenResult> openExternally(
    String path, {
    String? mimeType,
  }) => AttachmentEnginePlatform.instance.openExternally(
    path,
    mimeType: mimeType,
  );
}
