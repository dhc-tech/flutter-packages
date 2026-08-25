import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';

/// Replaces `share_plus`. iOS: `UIActivityViewController`. Android:
/// `Intent.ACTION_SEND` with a `FileProvider` content URI.
class NativeShareChannel {
  NativeShareChannel._();

  static Future<void> shareFile(String path, {String? text}) =>
      AttachmentEnginePlatform.instance.shareFile(path, text: text);

  static Future<void> shareText(String text) =>
      AttachmentEnginePlatform.instance.shareText(text);
}
