import '../util/value_equatable.dart';

/// Hook allowing a host app to override the default English failure
/// messages, e.g. by wiring in `flutter_localizations` / `intl`.
///
/// ```dart
/// AttachmentLocalizations.messageOverride = (failure) => myIntlLookup(failure);
/// ```
class AttachmentLocalizations {
  AttachmentLocalizations._();

  /// If set, called first by [AttachmentFailure.localizedMessage]. Return
  /// null to fall back to the built-in English default for that failure.
  static String? Function(AttachmentFailure failure)? messageOverride;
}

/// Typed, exhaustive set of failures the engine can surface. Each failure
/// carries a simple default English message via [localizedMessage] which a
/// host app can override globally through [AttachmentLocalizations].
sealed class AttachmentFailure extends ValueEquatable {
  const AttachmentFailure({this.cause});

  /// Optional lower-level cause (exception, error string) for diagnostics.
  /// Never put raw URLs or tokens here in user-facing surfaces.
  final Object? cause;

  String get _defaultMessage;

  /// User-facing message, honoring [AttachmentLocalizations.messageOverride].
  String get localizedMessage =>
      AttachmentLocalizations.messageOverride?.call(this) ?? _defaultMessage;

  @override
  List<Object?> get props => [runtimeType, cause];
}

class AttachmentNotFound extends AttachmentFailure {
  const AttachmentNotFound({super.cause});
  @override
  String get _defaultMessage => 'This attachment could not be found.';
}

class UnsupportedAttachment extends AttachmentFailure {
  const UnsupportedAttachment({super.cause});
  @override
  String get _defaultMessage => 'This attachment type is not supported.';
}

class InvalidSource extends AttachmentFailure {
  const InvalidSource({super.cause});
  @override
  String get _defaultMessage => 'This attachment has an invalid source.';
}

class NetworkUnavailable extends AttachmentFailure {
  const NetworkUnavailable({super.cause});
  @override
  String get _defaultMessage => 'No network connection is available.';
}

class DownloadFailed extends AttachmentFailure {
  const DownloadFailed({super.cause});
  @override
  String get _defaultMessage => 'The attachment failed to download.';
}

class CacheFailed extends AttachmentFailure {
  const CacheFailed({super.cause});
  @override
  String get _defaultMessage => 'The attachment could not be cached.';
}

class ExpiredUrl extends AttachmentFailure {
  const ExpiredUrl({super.cause});
  @override
  String get _defaultMessage => 'This attachment link has expired.';
}

class Unauthorized extends AttachmentFailure {
  const Unauthorized({super.cause});
  @override
  String get _defaultMessage =>
      'You are not authorized to access this attachment.';
}

class PermissionDenied extends AttachmentFailure {
  const PermissionDenied({super.cause});
  @override
  String get _defaultMessage => 'Permission was denied for this action.';
}

class CorruptedFile extends AttachmentFailure {
  const CorruptedFile({super.cause});
  @override
  String get _defaultMessage => 'This attachment appears to be corrupted.';
}

class InsufficientStorage extends AttachmentFailure {
  const InsufficientStorage({super.cause});
  @override
  String get _defaultMessage => 'Not enough storage space is available.';
}

class RendererFailed extends AttachmentFailure {
  const RendererFailed({super.cause});
  @override
  String get _defaultMessage => 'This attachment could not be displayed.';
}

class PlaybackFailed extends AttachmentFailure {
  const PlaybackFailed({super.cause});
  @override
  String get _defaultMessage => 'Playback failed for this attachment.';
}

class ConversionFailed extends AttachmentFailure {
  const ConversionFailed({super.cause});
  @override
  String get _defaultMessage => 'This attachment could not be converted.';
}

class UnknownFailure extends AttachmentFailure {
  const UnknownFailure({super.cause});
  @override
  String get _defaultMessage => 'Something went wrong with this attachment.';
}

/// The renderer for this attachment's type has been disabled via
/// `RendererConfig`. Distinct from [UnsupportedAttachment], which means the
/// format simply has no renderer at all — this means a renderer exists but
/// the host explicitly turned it off.
class RendererDisabledByConfig extends AttachmentFailure {
  const RendererDisabledByConfig({super.cause});
  @override
  String get _defaultMessage =>
      'Viewing this attachment type has been disabled.';
}

/// Falling back to an external, OS-provided viewer was required (renderer
/// disabled/unsupported, or Office-on-Android) but
/// `ExternalOpenConfig.allowExternalFallback` is false, so no fallback was
/// attempted.
class ExternalOpenDisabled extends AttachmentFailure {
  const ExternalOpenDisabled({super.cause});
  @override
  String get _defaultMessage =>
      'Opening this attachment externally is disabled.';
}
