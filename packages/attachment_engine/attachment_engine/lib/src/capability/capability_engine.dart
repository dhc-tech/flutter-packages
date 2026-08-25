import '../config/attachment_engine_config.dart';
import '../models/attachment.dart';
import '../models/attachment_capabilities.dart';
import '../models/attachment_source.dart';
import '../models/attachment_status.dart';
import '../models/attachment_type.dart';
import '../platform/platform_info.dart';

/// Derives the set of available actions ([AttachmentCapabilities]) for an
/// attachment given its type, current status and source.
class CapabilityEngine {
  const CapabilityEngine({
    this.platformInfo = const DefaultPlatformInfo(),
    this.rendererConfig = const RendererConfig(),
    this.externalOpenConfig = const ExternalOpenConfig(),
  });

  /// Injectable platform check, used to reflect the intentional iOS-vs-
  /// Android asymmetry for office documents: iOS has a genuine in-app
  /// QuickLook preview (`canPreview: true`), Android only supports
  /// external-open (`canPreview: false`, `canOpenExternally: true`).
  final PlatformInfo platformInfo;

  /// Which renderer types the host has enabled. A disabled type never
  /// reports `canPreview`/`canPlay`/`canOpen`, and instead reports
  /// `rendererDisabledByConfig: true`.
  final RendererConfig rendererConfig;

  /// Whether unsupported/disabled types (and Office-on-Android) may still
  /// report `canOpenExternally`.
  final ExternalOpenConfig externalOpenConfig;

  AttachmentCapabilities derive(Attachment attachment) {
    final status = attachment.status;
    final type = attachment.attachmentType;
    final source = attachment.source;
    final rendererDisabledByConfig =
        type != AttachmentType.unknown && !rendererConfig.isEnabled(type);

    if (status == AttachmentStatus.cleaned) {
      return AttachmentCapabilities.none.copyWith(
        canDownload: source is! BytesAttachmentSource,
      );
    }

    final isTerminalFailure = status == AttachmentStatus.failed;
    final hasLocalContent =
        status == AttachmentStatus.ready ||
        status == AttachmentStatus.cached ||
        status == AttachmentStatus.rendering;

    // Office documents only have a genuine in-app preview on iOS
    // (QuickLook). Android has no in-app Office viewer, so it must not
    // claim `canPreview` — it can only offer external-open.
    final isOfficeWithoutInAppPreview =
        type == AttachmentType.office && !platformInfo.isIOS;

    final canPreview =
        !isTerminalFailure &&
        type != AttachmentType.unknown &&
        !isOfficeWithoutInAppPreview &&
        !rendererDisabledByConfig &&
        (hasLocalContent || status == AttachmentStatus.discovered);

    final canPlay =
        hasLocalContent &&
        !rendererDisabledByConfig &&
        (type == AttachmentType.video || type == AttachmentType.audio);

    final canOpen =
        hasLocalContent &&
        type != AttachmentType.unknown &&
        !rendererDisabledByConfig;

    final canDownload =
        !isTerminalFailure &&
        status != AttachmentStatus.cleaned &&
        source is! BytesAttachmentSource &&
        (attachment.remoteUrl != null ||
            source is UrlAttachmentSource ||
            source is ServerAttachmentSource);

    final canShare = hasLocalContent;

    final canCache = !isTerminalFailure && source is! CacheAttachmentSource;

    final canOpenExternally =
        hasLocalContent && externalOpenConfig.allowExternalFallback;

    final canDeleteCache =
        status == AttachmentStatus.cached || status == AttachmentStatus.ready;

    return AttachmentCapabilities(
      canPreview: canPreview,
      canOpen: canOpen,
      canPlay: canPlay,
      canDownload: canDownload,
      canShare: canShare,
      canCache: canCache,
      canOpenExternally: canOpenExternally,
      canDeleteCache: canDeleteCache,
      rendererDisabledByConfig: rendererDisabledByConfig,
    );
  }
}
