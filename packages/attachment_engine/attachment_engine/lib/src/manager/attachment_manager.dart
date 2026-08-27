// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import '../cache/attachment_cache_manager.dart';
import '../cache/cache_metadata_store.dart';
import '../capability/capability_engine.dart';
import '../config/attachment_engine_config.dart';
import '../download/download_manager.dart';
import '../models/attachment.dart';
import '../models/attachment_capabilities.dart';
import '../models/attachment_failure.dart';
import '../models/attachment_source.dart';
import '../models/resolved_attachment.dart';
import '../native/native_open_channel.dart';
import '../native/native_share_channel.dart';
import '../observability/attachment_diagnostics.dart';
import '../renderers/renderer.dart';
import '../resolver/attachment_resolver.dart';

/// Top-level facade for the engine. Construct via the default constructor
/// with injected collaborators (for testability), or use
/// [AttachmentManager.instance] for a ready-to-use singleton in an app.
class AttachmentManager {
  /// [config] governs renderer enablement, external-open fallback and
  /// capability derivation for [capabilitiesFor]/[rendererRegistry]. When
  /// [resolver]/[cacheManager] are constructed independently (as in tests),
  /// their own cache/download behavior is whatever they were built with —
  /// [config] does not retroactively reconfigure already-built
  /// collaborators. Use [initializeDefault] for a single config to flow
  /// through cache, download and renderer layers consistently.
  AttachmentManager({
    required AttachmentResolver resolver,
    required AttachmentCacheManager cacheManager,
    AttachmentDiagnosticsSink diagnostics =
        const NoopAttachmentDiagnosticsSink(),
    AttachmentEngineConfig config = const AttachmentEngineConfig.defaults(),
  }) : _resolver = resolver,
       _cacheManager = cacheManager,
       _diagnostics = diagnostics,
       _config = config {
    _config.validate();
  }

  final AttachmentResolver _resolver;
  final AttachmentCacheManager _cacheManager;
  final AttachmentDiagnosticsSink _diagnostics;
  final AttachmentEngineConfig _config;

  /// The configuration this manager was constructed with.
  AttachmentEngineConfig get config => _config;

  /// A [RendererRegistry] pre-wired with this manager's [config] (renderer
  /// enablement + external-open policy). Pass this to [AttachmentViewer]
  /// instead of letting it build its own default registry, so config is
  /// actually honored by the UI layer.
  late final RendererRegistry rendererRegistry = RendererRegistry(
    rendererConfig: _config.renderers,
    externalOpenConfig: _config.externalOpen,
  );

  static AttachmentManager? _instance;

  /// A ready-to-use singleton backed by file-based cache metadata storage.
  /// Call [initializeDefault] once at app startup before first use.
  static AttachmentManager get instance {
    final manager = _instance;
    if (manager == null) {
      throw StateError(
        'AttachmentManager.initializeDefault() must be called before AttachmentManager.instance is used.',
      );
    }
    return manager;
  }

  static Future<AttachmentManager> initializeDefault({
    AttachmentDiagnosticsSink? diagnostics,
    AttachmentEngineConfig config = const AttachmentEngineConfig.defaults(),
    DownloadClient? downloadClient,
    ConnectivityChecker? connectivityChecker,
  }) async {
    config.validate();
    // Calling this a second time (e.g. on logout/re-login, or a test
    // harness that doesn't reset _instance between tests) would otherwise
    // silently leak the previous instance's resources — most notably a
    // NativeDownloadClient's platform-channel event subscription, which
    // would keep running (now duplicated by the new instance's own
    // subscription) for the rest of the process's lifetime.
    await _instance?.dispose();
    final cacheManager = AttachmentCacheManager(
      metadataStore: FileBasedMetadataStore(),
      config: config.cache,
    );
    await cacheManager.init();
    final resolver = AttachmentResolver(
      cacheManager: cacheManager,
      downloadConfig: config.download,
      // A caller-supplied client lets the host app route every attachment
      // download through its own HTTP stack (e.g. a `dio`/`ApiClient`
      // instance with auth interceptors already attached), instead of the
      // package's native client which knows nothing about app-level auth.
      // Omit to keep the package's own native download path.
      downloadManager: downloadClient == null
          ? null
          : DownloadManager(client: downloadClient, config: config.download),
      connectivityChecker:
          connectivityChecker ?? const DefaultConnectivityChecker(),
      capabilityEngine: CapabilityEngine(
        rendererConfig: config.renderers,
        externalOpenConfig: config.externalOpen,
      ),
    );
    final manager = AttachmentManager(
      resolver: resolver,
      cacheManager: cacheManager,
      diagnostics: diagnostics ?? const NoopAttachmentDiagnosticsSink(),
      config: config,
    );
    _instance = manager;
    return manager;
  }

  /// Resolves and returns [attachment] ready for full viewing.
  Future<ResolvedAttachment> open(Attachment attachment) async {
    return _resolveWithDiagnostics(attachment);
  }

  /// Resolves [attachment] for lightweight preview purposes. Currently
  /// delegates to the same resolution pipeline as [open]; kept as a
  /// distinct entry point so preview vs full-view resolution can diverge
  /// later (e.g. thumbnail-only fetch).
  Future<ResolvedAttachment> preview(Attachment attachment) async {
    return _resolveWithDiagnostics(attachment);
  }

  /// Forces (re)download of [attachment], bypassing any cache hit check by
  /// clearing its cache entry first.
  Future<ResolvedAttachment> download(Attachment attachment) async {
    await _cacheManager.clearAttachment(attachment);
    return _resolveWithDiagnostics(attachment);
  }

  /// Alias for [open], used when the caller intends immediate playback of
  /// audio/video content.
  Future<ResolvedAttachment> play(Attachment attachment) => open(attachment);

  /// Retries a previously failed resolution.
  Future<ResolvedAttachment> retry(Attachment attachment) =>
      _resolveWithDiagnostics(attachment);

  /// Warms the cache for [url] in the background — the caller supplies
  /// only a URL (and optionally [id]/[name]); no pre-built [Attachment],
  /// no UI needs to open it. Already-cached content is a fast no-op (the
  /// normal resolve() cache-hit check). Concurrent calls for the same
  /// [id] are deduplicated, same as [open].
  ///
  /// [id] should be a stable identifier for the underlying content,
  /// distinct from [url] itself whenever [url] is a short-lived signed
  /// URL — otherwise a later call (whether [prefetch] or [open]) for the
  /// same logical file but a freshly-rotated URL won't be recognized as
  /// the same cache entry, and this download happens again for nothing.
  /// When omitted, [url] itself is used as the identity, which is only
  /// correct for URLs that don't rotate.
  ///
  /// This is genuinely best-effort: a failed prefetch (network error, 404,
  /// etc.) does not throw. It's still reported through the configured
  /// [AttachmentDiagnosticsSink], same as a failed [open], so failures
  /// remain observable without forcing every caller to handle them.
  Future<void> prefetch(String url, {String? id, String? name}) async {
    final attachment = Attachment(
      id: id ?? url,
      name: name ?? url,
      source: AttachmentSource.url(url),
      remoteUrl: url,
    );
    try {
      await _resolveWithDiagnostics(attachment);
    } catch (_) {
      // Swallowed deliberately — see dartdoc. _resolveWithDiagnostics
      // already reported the failure to diagnostics before rethrowing.
    }
  }

  Future<ResolvedAttachment> _resolveWithDiagnostics(
    Attachment attachment,
  ) async {
    final stopwatch = Stopwatch()..start();
    _diagnostics.onResolutionStart(attachment.id);
    try {
      final result = await _resolver.resolve(attachment);
      _diagnostics.onResolutionComplete(
        attachment.id,
        duration: stopwatch.elapsed,
        cacheHit: result.fromCache,
      );
      return result;
    } on AttachmentResolutionException catch (e) {
      _diagnostics.onResolutionFailed(
        attachment.id,
        failureType: e.failure.runtimeType.toString(),
      );
      rethrow;
    } catch (e) {
      _diagnostics.onResolutionFailed(
        attachment.id,
        failureType: const UnknownFailure().runtimeType.toString(),
      );
      throw AttachmentResolutionException(UnknownFailure(cause: e));
    }
  }

  /// Shares [attachment] via the native share sheet. Requires it to already
  /// be resolved to a local file (call [open] first).
  Future<void> share(Attachment attachment) async {
    final path = attachment.localPath;
    if (path == null) {
      throw AttachmentResolutionException(const InvalidSource());
    }
    await NativeShareChannel.shareFile(path, text: attachment.name);
  }

  /// Opens [attachment] in an external, OS-provided viewer/app. Throws
  /// [ExternalOpenDisabled] when `config.externalOpen.allowExternalFallback`
  /// is false.
  Future<void> openExternally(Attachment attachment) async {
    if (!_config.externalOpen.allowExternalFallback) {
      throw AttachmentResolutionException(const ExternalOpenDisabled());
    }
    final path = attachment.localPath;
    if (path == null) {
      throw AttachmentResolutionException(const InvalidSource());
    }
    final result = await NativeOpenChannel.openExternally(path);
    if (!result.success) {
      throw AttachmentResolutionException(const RendererFailed());
    }
  }

  /// Removes any cached copy of [attachment].
  Future<void> deleteCache(Attachment attachment) =>
      _cacheManager.clearAttachment(attachment);

  /// Recomputes capabilities for [attachment] in its current state.
  AttachmentCapabilities capabilitiesFor(Attachment attachment) {
    return CapabilityEngine(
      rendererConfig: _config.renderers,
      externalOpenConfig: _config.externalOpen,
    ).derive(attachment);
  }

  /// Releases resources held by this manager's collaborators: flushes any
  /// pending (debounced) cache metadata write via
  /// [AttachmentCacheManager.dispose], and disposes the resolver's download
  /// resources via [AttachmentResolver.dispose] (progress controllers, and
  /// a `NativeDownloadClient`'s platform-channel event subscription, if
  /// that's the download client in use). Call this when the manager is no
  /// longer needed — e.g. on app teardown, or automatically via
  /// [initializeDefault] when replacing an existing singleton.
  Future<void> dispose() async {
    _resolver.dispose();
    await _cacheManager.dispose();
  }
}
