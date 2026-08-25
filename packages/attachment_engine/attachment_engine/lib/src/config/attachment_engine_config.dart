import '../util/value_equatable.dart';
import 'package:meta/meta.dart';

import '../models/attachment_type.dart';

/// Thrown when an [AttachmentEngineConfig] (or one of its sub-configs) is
/// constructed with an invalid combination of values.
///
/// This is a plain [ArgumentError] subtype so existing `catch (ArgumentError)`
/// call sites keep working, while callers who want to be specific can catch
/// [AttachmentConfigValidationError] directly.
class AttachmentConfigValidationError extends ArgumentError {
  AttachmentConfigValidationError(super.message);
}

void _requireNonNegative(int? value, String name) {
  if (value != null && value < 0) {
    throw AttachmentConfigValidationError(
      '$name must not be negative (was $value).',
    );
  }
}

void _requirePositive(int value, String name) {
  if (value <= 0) {
    throw AttachmentConfigValidationError(
      '$name must be greater than zero (was $value).',
    );
  }
}

void _requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw AttachmentConfigValidationError(
      '$name must be a positive duration (was $value).',
    );
  }
}

void _requireNonNegativeDuration(Duration? value, String name) {
  if (value != null && value < Duration.zero) {
    throw AttachmentConfigValidationError(
      '$name must not be negative (was $value).',
    );
  }
}

/// Backoff strategy applied between retried download attempts.
enum DownloadRetryBackoff {
  /// Retry immediately with no delay between attempts.
  none,

  /// Delay increases linearly with the attempt number
  /// (`baseDelay * attemptNumber`).
  linear,

  /// Delay doubles with each attempt (`baseDelay * 2^(attemptNumber - 1)`).
  exponential,
}

/// How aggressively adjacent/related previews are warmed ahead of time.
///
/// Kept intentionally minimal: the current preview pipeline
/// (`AttachmentManager.preview`) resolves one attachment at a time and has
/// no batch/adjacency-aware preloading implemented, so this enum only
/// records host intent for callers that implement their own preloading loop
/// on top of [AttachmentManager.preview]; the engine itself does not (yet)
/// walk lists automatically.
enum PreviewPreloadPolicy {
  /// Do not preload anything ahead of time.
  none,

  /// Preload immediate neighbors of the item currently being viewed.
  adjacent,

  /// Preload every item eagerly.
  all,
}

/// Controls whether, and how, attachment content is cached on disk.
///
/// Reuses the existing LRU-by-total-size eviction model from
/// [CachePolicy] (`lib/src/cache/cache_policy.dart`) rather than
/// introducing a second, parallel eviction concept.
@immutable
class CacheConfig extends ValueEquatable {
  /// Creates a cache configuration.
  ///
  /// [maxTotalSizeBytes] defaults to `500 * 1024 * 1024` (500 MB), matching
  /// `CachePolicy`'s pre-existing default so [AttachmentEngineConfig.defaults]
  /// reproduces current behavior exactly.
  ///
  /// Throws [AttachmentConfigValidationError] if [maxTotalSizeBytes] or
  /// [maxFileSizeBytes] is negative, if [maxFileSizeBytes] exceeds
  /// [maxTotalSizeBytes] (a single file could never fit), or if [retention]
  /// is negative.
  const CacheConfig({
    this.enabled = true,
    this.maxTotalSizeBytes = 500 * 1024 * 1024,
    this.maxFileSizeBytes,
    this.retention,
    this.thumbnailCachingEnabled = true,
    this.previewCachingEnabled = true,
  });

  /// When false, the cache manager creates no cache directory, writes no
  /// files, persists no metadata, and runs no eviction. Remote content is
  /// fetched fresh on every resolution instead of being reused.
  final bool enabled;

  /// Maximum total bytes the on-disk cache may occupy before LRU eviction
  /// runs. Mirrors `CachePolicy.maxTotalSizeBytes`.
  final int maxTotalSizeBytes;

  /// Optional per-file size cap. Files larger than this are not written to
  /// the persistent cache (they are still resolved/rendered, just not
  /// retained for reuse). Null means no per-file cap beyond
  /// [maxTotalSizeBytes] itself.
  final int? maxFileSizeBytes;

  /// Optional time-to-live for cache entries, independent of size-based
  /// eviction. Entries older than this (by `createdAt`) are treated as
  /// expired the same way `CacheEntry.isExpired`/`expiresAt` already is.
  /// Null means entries only expire via their own `expiresAt` (if any) or
  /// size-based LRU eviction.
  final Duration? retention;

  /// Whether thumbnail-category cache entries may be written/reused.
  final bool thumbnailCachingEnabled;

  /// Whether preview-category cache entries may be written/reused.
  final bool previewCachingEnabled;

  CacheConfig copyWith({
    bool? enabled,
    int? maxTotalSizeBytes,
    int? Function()? maxFileSizeBytes,
    Duration? Function()? retention,
    bool? thumbnailCachingEnabled,
    bool? previewCachingEnabled,
  }) {
    return CacheConfig(
      enabled: enabled ?? this.enabled,
      maxTotalSizeBytes: maxTotalSizeBytes ?? this.maxTotalSizeBytes,
      maxFileSizeBytes: maxFileSizeBytes != null
          ? maxFileSizeBytes()
          : this.maxFileSizeBytes,
      retention: retention != null ? retention() : this.retention,
      thumbnailCachingEnabled:
          thumbnailCachingEnabled ?? this.thumbnailCachingEnabled,
      previewCachingEnabled:
          previewCachingEnabled ?? this.previewCachingEnabled,
    );
  }

  void _validate() {
    _requireNonNegative(maxTotalSizeBytes, 'maxTotalSizeBytes');
    _requireNonNegative(maxFileSizeBytes, 'maxFileSizeBytes');
    if (maxFileSizeBytes != null && maxFileSizeBytes! > maxTotalSizeBytes) {
      throw AttachmentConfigValidationError(
        'maxFileSizeBytes ($maxFileSizeBytes) must not exceed '
        'maxTotalSizeBytes ($maxTotalSizeBytes): a file larger than the '
        'total cache budget could never be cached.',
      );
    }
    _requireNonNegativeDuration(retention, 'retention');
  }

  @override
  List<Object?> get props => [
    enabled,
    maxTotalSizeBytes,
    maxFileSizeBytes,
    retention,
    thumbnailCachingEnabled,
    previewCachingEnabled,
  ];
}

/// Enables/disables full-view rendering per [AttachmentType].
///
/// HLS/adaptive streaming is a capability of [AttachmentType.video]
/// handled inside `VideoAttachmentRenderer`/the native video channel, not a
/// distinct [AttachmentType] — there is no separate `hlsEnabled` flag;
/// disabling [video] disables it along with all other video playback.
@immutable
class RendererConfig extends ValueEquatable {
  /// All renderers default to enabled, matching current behavior (every
  /// type registered in `RendererRegistry` today).
  const RendererConfig({
    this.image = true,
    this.pdf = true,
    this.document = true,
    this.office = true,
    this.text = true,
    this.html = true,
    this.scorm = true,
    this.h5p = true,
    this.video = true,
    this.audio = true,
    this.archive = true,
  });

  final bool image;
  final bool pdf;
  final bool document;
  final bool office;
  final bool text;
  final bool html;
  final bool scorm;
  final bool h5p;
  final bool video;
  final bool audio;
  final bool archive;

  /// Whether [type] is enabled by this config. [AttachmentType.unknown] is
  /// never independently toggleable: it has no dedicated renderer to begin
  /// with (it always falls back to `UnknownAttachmentRenderer`), so it is
  /// reported as always enabled here.
  bool isEnabled(AttachmentType type) {
    switch (type) {
      case AttachmentType.image:
        return image;
      case AttachmentType.pdf:
        return pdf;
      case AttachmentType.document:
        return document;
      case AttachmentType.office:
        return office;
      case AttachmentType.text:
        return text;
      case AttachmentType.html:
        return html;
      case AttachmentType.scorm:
        return scorm;
      case AttachmentType.h5p:
        return h5p;
      case AttachmentType.video:
        return video;
      case AttachmentType.audio:
        return audio;
      case AttachmentType.archive:
        return archive;
      case AttachmentType.unknown:
        return true;
    }
  }

  RendererConfig copyWith({
    bool? image,
    bool? pdf,
    bool? document,
    bool? office,
    bool? text,
    bool? html,
    bool? scorm,
    bool? h5p,
    bool? video,
    bool? audio,
    bool? archive,
  }) {
    return RendererConfig(
      image: image ?? this.image,
      pdf: pdf ?? this.pdf,
      document: document ?? this.document,
      office: office ?? this.office,
      text: text ?? this.text,
      html: html ?? this.html,
      scorm: scorm ?? this.scorm,
      h5p: h5p ?? this.h5p,
      video: video ?? this.video,
      audio: audio ?? this.audio,
      archive: archive ?? this.archive,
    );
  }

  @override
  List<Object?> get props => [
    image,
    pdf,
    document,
    office,
    text,
    html,
    scorm,
    h5p,
    video,
    audio,
    archive,
  ];
}

/// Controls download timeouts, retry/backoff, concurrency and resume.
@immutable
class DownloadConfig extends ValueEquatable {
  /// [maxRetries] defaults to `3`, matching `DownloadManager`'s pre-existing
  /// hardcoded default. [resumeEnabled] defaults to `true`, matching current
  /// behavior (every retry after the first already passes `resume: true`).
  ///
  /// [connectTimeout] and [receiveTimeout] have no prior hardcoded
  /// equivalent (the engine previously had no timeout at all and would wait
  /// indefinitely) — defaults of 15s/30s are new, conservative values.
  /// Because the native transport does not expose a distinct
  /// connect-vs-receive phase, both are enforced together as a single
  /// per-attempt wall-clock timeout (`connectTimeout + receiveTimeout`)
  /// wrapped around each attempt in [DownloadManager]; see its dartdoc.
  ///
  /// [maxConcurrentDownloads] also has no prior equivalent — previously
  /// concurrency was unbounded. Default `3` is a new, sane cap; this is a
  /// deliberate, documented behavior change from "unlimited" to "capped".
  const DownloadConfig({
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.retryBackoff = DownloadRetryBackoff.exponential,
    this.retryBaseDelay = const Duration(milliseconds: 500),
    this.maxConcurrentDownloads = 3,
    this.resumeEnabled = true,
  });

  final Duration connectTimeout;
  final Duration receiveTimeout;

  /// Maximum number of attempts is `maxRetries` (i.e. `maxRetries == 3`
  /// means up to 3 total attempts), matching `DownloadManager`'s existing
  /// `attempt < maxRetries` loop condition exactly.
  final int maxRetries;

  /// Delay strategy applied between failed attempts.
  final DownloadRetryBackoff retryBackoff;

  /// Base delay used by [retryBackoff]'s linear/exponential calculation.
  /// Unused when [retryBackoff] is [DownloadRetryBackoff.none].
  final Duration retryBaseDelay;

  /// Maximum number of downloads [DownloadManager] runs concurrently;
  /// additional requests wait for a slot to free up.
  final int maxConcurrentDownloads;

  /// When true (default, matching current behavior), retries after the
  /// first attempt pass `resume: true` to the underlying [DownloadClient]
  /// so a native HTTP-range/resume-data transport can continue a partial
  /// download. When false, every attempt — including retries — passes
  /// `resume: false`, forcing a clean restart each time.
  final bool resumeEnabled;

  DownloadConfig copyWith({
    Duration? connectTimeout,
    Duration? receiveTimeout,
    int? maxRetries,
    DownloadRetryBackoff? retryBackoff,
    Duration? retryBaseDelay,
    int? maxConcurrentDownloads,
    bool? resumeEnabled,
  }) {
    return DownloadConfig(
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      maxRetries: maxRetries ?? this.maxRetries,
      retryBackoff: retryBackoff ?? this.retryBackoff,
      retryBaseDelay: retryBaseDelay ?? this.retryBaseDelay,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      resumeEnabled: resumeEnabled ?? this.resumeEnabled,
    );
  }

  void _validate() {
    _requirePositiveDuration(connectTimeout, 'connectTimeout');
    _requirePositiveDuration(receiveTimeout, 'receiveTimeout');
    if (maxRetries < 0) {
      throw AttachmentConfigValidationError(
        'maxRetries must not be negative (was $maxRetries).',
      );
    }
    _requirePositive(maxConcurrentDownloads, 'maxConcurrentDownloads');
    _requireNonNegativeDuration(retryBaseDelay, 'retryBaseDelay');
  }

  @override
  List<Object?> get props => [
    connectTimeout,
    receiveTimeout,
    maxRetries,
    retryBackoff,
    retryBaseDelay,
    maxConcurrentDownloads,
    resumeEnabled,
  ];
}

/// Controls thumbnail/preview behavior surfaced to preview widgets.
@immutable
class PreviewConfig extends ValueEquatable {
  const PreviewConfig({
    this.thumbnailsEnabled = true,
    this.lazyLoading = true,
    this.preloadPolicy = PreviewPreloadPolicy.none,
  });

  /// Whether thumbnail widgets (`AttachmentThumbnail`) should attempt to
  /// render/cache thumbnails at all.
  final bool thumbnailsEnabled;

  /// Whether preview resolution is deferred until actually requested
  /// (current default behavior) rather than eagerly on attachment load.
  final bool lazyLoading;

  /// See [PreviewPreloadPolicy]. Defaults to `none`, matching current
  /// behavior (nothing is preloaded automatically today).
  final PreviewPreloadPolicy preloadPolicy;

  PreviewConfig copyWith({
    bool? thumbnailsEnabled,
    bool? lazyLoading,
    PreviewPreloadPolicy? preloadPolicy,
  }) {
    return PreviewConfig(
      thumbnailsEnabled: thumbnailsEnabled ?? this.thumbnailsEnabled,
      lazyLoading: lazyLoading ?? this.lazyLoading,
      preloadPolicy: preloadPolicy ?? this.preloadPolicy,
    );
  }

  @override
  List<Object?> get props => [thumbnailsEnabled, lazyLoading, preloadPolicy];
}

/// Controls whether unsupported/disabled attachments may fall back to an
/// OS-provided external viewer.
@immutable
class ExternalOpenConfig extends ValueEquatable {
  /// Defaults to `true`, matching current behavior (unsupported/disabled
  /// renderers, and Office on Android, both fall back to external-open
  /// today).
  const ExternalOpenConfig({this.allowExternalFallback = true});

  /// When false, attachments that would otherwise fall back to an external
  /// viewer (unknown/disabled renderer types, and Office on Android) must
  /// instead report a typed "external open disabled" failure/capability
  /// state rather than opening externally.
  final bool allowExternalFallback;

  ExternalOpenConfig copyWith({bool? allowExternalFallback}) {
    return ExternalOpenConfig(
      allowExternalFallback:
          allowExternalFallback ?? this.allowExternalFallback,
    );
  }

  @override
  List<Object?> get props => [allowExternalFallback];
}

/// Immutable, composable configuration for the whole attachment engine.
///
/// Construct with [AttachmentEngineConfig.defaults] to reproduce current
/// (pre-config) engine behavior exactly, or with the main constructor to
/// override individual areas.
///
/// Deliberately does not include a `MediaConfig`: the native
/// video/audio channels (`NativeVideoController`, `NativeAudioController`
/// and their Swift/Kotlin counterparts) do not currently expose autoplay,
/// loop, controls-visibility or fullscreen toggles, so no such config was
/// added — adding one would be a non-functional, decorative flag. If the
/// native layer grows that support, a `MediaConfig` should be added then.
@immutable
class AttachmentEngineConfig extends ValueEquatable {
  const AttachmentEngineConfig({
    this.cache = const CacheConfig(),
    this.renderers = const RendererConfig(),
    this.download = const DownloadConfig(),
    this.preview = const PreviewConfig(),
    this.externalOpen = const ExternalOpenConfig(),
  });

  /// Reproduces the engine's behavior exactly as it was before this
  /// configuration surface existed: caching on with a 500MB LRU cap, every
  /// renderer enabled, 3 retries with exponential backoff, resume enabled,
  /// external-open fallback enabled.
  const AttachmentEngineConfig.defaults() : this();

  final CacheConfig cache;
  final RendererConfig renderers;
  final DownloadConfig download;
  final PreviewConfig preview;
  final ExternalOpenConfig externalOpen;

  /// Validates this configuration, throwing [AttachmentConfigValidationError]
  /// (an [ArgumentError]) on the first violation found. Called automatically
  /// by [AttachmentManager]'s constructor; exposed publicly so callers can
  /// validate a config before using it.
  void validate() {
    cache._validate();
    download._validate();
  }

  AttachmentEngineConfig copyWith({
    CacheConfig? cache,
    RendererConfig? renderers,
    DownloadConfig? download,
    PreviewConfig? preview,
    ExternalOpenConfig? externalOpen,
  }) {
    return AttachmentEngineConfig(
      cache: cache ?? this.cache,
      renderers: renderers ?? this.renderers,
      download: download ?? this.download,
      preview: preview ?? this.preview,
      externalOpen: externalOpen ?? this.externalOpen,
    );
  }

  @override
  List<Object?> get props => [
    cache,
    renderers,
    download,
    preview,
    externalOpen,
  ];
}
