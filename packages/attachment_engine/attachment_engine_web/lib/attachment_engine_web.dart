import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';

import 'src/attachment_engine_web_impl.dart';

export 'src/attachment_engine_web_impl.dart' show AttachmentEngineWebImpl;

/// The Flutter Web implementation of `attachment_engine`.
class AttachmentEngineWeb {
  /// Creates a new [AttachmentEngineWeb]. Stateless; only [registerWith]
  /// is actually used, by Flutter's web plugin registrant.
  const AttachmentEngineWeb();

  /// Registers the web implementation as the active platform instance.
  static void registerWith([dynamic registrar]) {
    AttachmentEnginePlatform.instance = AttachmentEngineWebImpl();
  }
}
