/// Safe internal logging/telemetry hook. A host app can implement this to
/// bridge events into Crashlytics, Sentry, or its own analytics.
///
/// Implementations MUST NOT assume any argument contains a raw URL or
/// token - the engine only ever passes ids, durations, sizes and error
/// type names, never full URLs (see [sanitizeForLog]).
abstract class AttachmentDiagnosticsSink {
  void onResolutionStart(String attachmentId);
  void onResolutionComplete(
    String attachmentId, {
    required Duration duration,
    required bool cacheHit,
  });
  void onResolutionFailed(String attachmentId, {required String failureType});
  void onDownloadStart(String attachmentId);
  void onDownloadComplete(
    String attachmentId, {
    required Duration duration,
    required int bytes,
  });
  void onDownloadFailed(String attachmentId, {required String failureType});
  void onPlaybackError(String attachmentId, {required String failureType});
}

/// No-op default sink used when a host app doesn't provide one.
class NoopAttachmentDiagnosticsSink implements AttachmentDiagnosticsSink {
  const NoopAttachmentDiagnosticsSink();

  @override
  void onResolutionStart(String attachmentId) {}
  @override
  void onResolutionComplete(
    String attachmentId, {
    required Duration duration,
    required bool cacheHit,
  }) {}
  @override
  void onResolutionFailed(String attachmentId, {required String failureType}) {}
  @override
  void onDownloadStart(String attachmentId) {}
  @override
  void onDownloadComplete(
    String attachmentId, {
    required Duration duration,
    required int bytes,
  }) {}
  @override
  void onDownloadFailed(String attachmentId, {required String failureType}) {}
  @override
  void onPlaybackError(String attachmentId, {required String failureType}) {}
}

/// Strips the query string from [url] before logging, so signed-URL
/// parameters and Authorization-style tokens embedded in query params are
/// never written to logs. Only ever call this on values that might reach a
/// log statement - the engine's core logic should prefer ids over URLs.
String sanitizeForLog(String url) {
  final queryIndex = url.indexOf('?');
  final withoutQuery = queryIndex == -1 ? url : url.substring(0, queryIndex);
  final uri = Uri.tryParse(withoutQuery);
  if (uri == null) return withoutQuery;
  return uri.replace(userInfo: '').toString();
}
