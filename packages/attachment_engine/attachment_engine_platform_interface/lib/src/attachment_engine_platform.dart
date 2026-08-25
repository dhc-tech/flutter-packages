// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart' show Widget;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'types.dart';

/// The interface that platform-specific implementations of `attachment_engine`
/// must implement.
///
/// Platform implementations (`attachment_engine_android`,
/// `attachment_engine_ios`, and any future implementation such as a web
/// package) should extend this class rather than implement it, so that new
/// methods added here don't break existing implementations at compile time
/// (`extends` gives them the default `UnimplementedError`-throwing bodies
/// automatically; `implements` would not).
///
/// Every method here uses only plain Dart types (`String`, `int`, `double`,
/// `bool`, `Duration`, `Uint8List`, `Map`, `Stream`, `Future`) plus Flutter's
/// framework-level `Widget` for the one capability (video) that embeds a
/// native view — webview embedding is handled by the official
/// `webview_flutter` package instead, at the app-facing layer, not through
/// this contract. No `MethodChannel`, `EventChannel`, or other transport-specific type
/// appears in any signature — the transport is entirely an implementation
/// detail owned by each platform package.
abstract class AttachmentEnginePlatform extends PlatformInterface {
  /// Constructs an [AttachmentEnginePlatform].
  AttachmentEnginePlatform() : super(token: _token);

  static final Object _token = Object();

  static AttachmentEnginePlatform _instance = _UnimplementedPlatform();

  /// The default instance of [AttachmentEnginePlatform] to use.
  ///
  /// Defaults to a stub that throws [UnimplementedError] on every call.
  /// Platform packages (`attachment_engine_android`, `attachment_engine_ios`)
  /// set this to their own implementation when they register themselves.
  static AttachmentEnginePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AttachmentEnginePlatform] when
  /// they register themselves.
  static set instance(AttachmentEnginePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // ---------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------

  /// Opens the PDF at [path] natively, returning a handle and page count.
  Future<PdfOpenResult> pdfOpen(String path) {
    throw UnimplementedError('pdfOpen() has not been implemented.');
  }

  /// Renders page [index] (zero-based) of the document identified by
  /// [handle] at [width]x[height] pixels, returning PNG-encoded bytes.
  Future<List<int>> pdfRenderPage(
    String handle,
    int index, {
    required int width,
    required int height,
  }) {
    throw UnimplementedError('pdfRenderPage() has not been implemented.');
  }

  /// Releases native resources associated with [handle].
  Future<void> pdfClose(String handle) {
    throw UnimplementedError('pdfClose() has not been implemented.');
  }

  // ---------------------------------------------------------------------
  // Audio
  // ---------------------------------------------------------------------

  /// Loads a local file or remote URL for the audio player identified by
  /// [playerId]. Exactly one of [filePath]/[url] should be provided.
  Future<void> audioLoad(String playerId, {String? filePath, String? url}) {
    throw UnimplementedError('audioLoad() has not been implemented.');
  }

  Future<void> audioPlay(String playerId) {
    throw UnimplementedError('audioPlay() has not been implemented.');
  }

  Future<void> audioPause(String playerId) {
    throw UnimplementedError('audioPause() has not been implemented.');
  }

  Future<void> audioSeek(String playerId, Duration position) {
    throw UnimplementedError('audioSeek() has not been implemented.');
  }

  Future<void> audioSetSpeed(String playerId, double speed) {
    throw UnimplementedError('audioSetSpeed() has not been implemented.');
  }

  Future<void> audioSetVolume(String playerId, double volume) {
    throw UnimplementedError('audioSetVolume() has not been implemented.');
  }

  Future<void> audioDispose(String playerId) {
    throw UnimplementedError('audioDispose() has not been implemented.');
  }

  /// Broadcast stream of raw playback-state event maps
  /// (`{state, positionMs, durationMs}`) for the player identified by
  /// [playerId].
  Stream<Map<Object?, Object?>> audioEvents(String playerId) {
    throw UnimplementedError('audioEvents() has not been implemented.');
  }

  // ---------------------------------------------------------------------
  // Video
  // ---------------------------------------------------------------------

  Future<void> videoLoad(String playerId, {String? filePath, String? url}) {
    throw UnimplementedError('videoLoad() has not been implemented.');
  }

  Future<void> videoPlay(String playerId) {
    throw UnimplementedError('videoPlay() has not been implemented.');
  }

  Future<void> videoPause(String playerId) {
    throw UnimplementedError('videoPause() has not been implemented.');
  }

  Future<void> videoSeek(String playerId, Duration position) {
    throw UnimplementedError('videoSeek() has not been implemented.');
  }

  Future<void> videoSetSpeed(String playerId, double speed) {
    throw UnimplementedError('videoSetSpeed() has not been implemented.');
  }

  Future<void> videoSetVolume(String playerId, double volume) {
    throw UnimplementedError('videoSetVolume() has not been implemented.');
  }

  Future<void> videoDispose(String playerId) {
    throw UnimplementedError('videoDispose() has not been implemented.');
  }

  /// Broadcast stream of raw playback-state event maps
  /// (`{state, positionMs, durationMs, width, height}`) for the player
  /// identified by [playerId].
  Stream<Map<Object?, Object?>> videoEvents(String playerId) {
    throw UnimplementedError('videoEvents() has not been implemented.');
  }

  /// Builds the embedded native video surface for the player identified by
  /// [playerId]. Must be called after [videoLoad] has been invoked at least
  /// once so the native side has a player ready to attach to.
  Widget videoBuildView(String playerId) {
    throw UnimplementedError('videoBuildView() has not been implemented.');
  }

  // ---------------------------------------------------------------------
  // Share
  // ---------------------------------------------------------------------

  Future<void> shareFile(String path, {String? text}) {
    throw UnimplementedError('shareFile() has not been implemented.');
  }

  Future<void> shareText(String text) {
    throw UnimplementedError('shareText() has not been implemented.');
  }

  // ---------------------------------------------------------------------
  // Open externally
  // ---------------------------------------------------------------------

  Future<NativeOpenResult> openExternally(String path, {String? mimeType}) {
    throw UnimplementedError('openExternally() has not been implemented.');
  }

  // ---------------------------------------------------------------------
  // Office preview
  // ---------------------------------------------------------------------

  /// Presents an in-app preview of the office document at [path], if the
  /// platform has a native in-app viewer available (iOS: `QLPreviewController`
  /// via QuickLook). Platforms without an in-app office viewer (Android)
  /// should implement this by falling back to [openExternally] rather than
  /// throwing, so callers can invoke it unconditionally.
  Future<void> openOfficePreview(String path) {
    throw UnimplementedError('openOfficePreview() has not been implemented.');
  }

  // ---------------------------------------------------------------------
  // Paths
  // ---------------------------------------------------------------------

  /// App-private, persistent storage directory path (survives app restarts,
  /// excluded from user-visible file browsing).
  Future<String> getApplicationSupportDirectory() {
    throw UnimplementedError(
      'getApplicationSupportDirectory() has not been implemented.',
    );
  }

  /// App-private cache directory path (OS may purge it under storage
  /// pressure).
  Future<String> getApplicationCacheDirectory() {
    throw UnimplementedError(
      'getApplicationCacheDirectory() has not been implemented.',
    );
  }

  // ---------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------

  /// Starts a fresh download of [url] to [destPath], returning a
  /// platform-generated download id.
  Future<String> startDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) {
    throw UnimplementedError('startDownload() has not been implemented.');
  }

  /// Resumes (or starts, if no partial data exists) a download of [url] to
  /// [destPath], returning a platform-generated download id.
  Future<String> resumeDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) {
    throw UnimplementedError('resumeDownload() has not been implemented.');
  }

  Future<void> cancelDownload(String downloadId) {
    throw UnimplementedError('cancelDownload() has not been implemented.');
  }

  /// Broadcast stream of download event maps
  /// (`{downloadId, type, received, total, path, message}`) covering every
  /// download started via [startDownload]/[resumeDownload].
  Stream<Map<Object?, Object?>> downloadEvents() {
    throw UnimplementedError('downloadEvents() has not been implemented.');
  }
}

class _UnimplementedPlatform extends AttachmentEnginePlatform {}
