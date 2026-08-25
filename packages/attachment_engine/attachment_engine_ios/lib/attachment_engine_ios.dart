// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The iOS implementation of [AttachmentEnginePlatform].
///
/// Every request/response-style native call (PDF, Audio/Video control,
/// Share, Open externally, Office preview, Paths, Download start/resume/
/// cancel) goes through the Pigeon-generated `HostApi`s in
/// `attachment_engine_platform_interface/lib/src/messages.g.dart`, codegen'd
/// from `attachment_engine_platform_interface/pigeons/messages.dart` — that
/// schema is the single source of truth for the wire format, kept in
/// lockstep with the native Swift implementations of those protocols under
/// `ios/attachment_engine_ios/Sources/attachment_engine_ios/`.
///
/// The audio/video/download *event streams* remain hand-written
/// `EventChannel`s (per-`playerId` dynamic channel names don't fit Pigeon's
/// event-channel model — see the note at the top of `pigeons/messages.dart`).
class AttachmentEngineIOS extends AttachmentEnginePlatform {
  /// Registers this class as the default instance of [AttachmentEnginePlatform].
  static void registerWith() {
    AttachmentEnginePlatform.instance = AttachmentEngineIOS();
  }

  final PdfHostApi _pdf = PdfHostApi();
  final AudioHostApi _audio = AudioHostApi();
  final VideoHostApi _video = VideoHostApi();
  final ShareHostApi _share = ShareHostApi();
  final OpenHostApi _open = OpenHostApi();
  final OfficeHostApi _office = OfficeHostApi();
  final PathsHostApi _paths = PathsHostApi();
  final DownloadHostApi _download = DownloadHostApi();

  static const EventChannel _downloadEventChannel = EventChannel(
    'attachment_engine/download_events',
  );

  Stream<Map<Object?, Object?>> _eventsFor(EventChannel channel) => channel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => event as Map<Object?, Object?>);

  // ---------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------

  @override
  Future<PdfOpenResult> pdfOpen(String path) async {
    final result = await _pdf.open(path);
    return PdfOpenResult(handle: result.handle, pageCount: result.pageCount);
  }

  @override
  Future<List<int>> pdfRenderPage(
    String handle,
    int index, {
    required int width,
    required int height,
  }) => _pdf.renderPage(handle, index, width, height);

  @override
  Future<void> pdfClose(String handle) => _pdf.close(handle);

  // ---------------------------------------------------------------------
  // Audio
  // ---------------------------------------------------------------------

  @override
  Future<void> audioLoad(String playerId, {String? filePath, String? url}) =>
      _audio.load(playerId, filePath, url);

  @override
  Future<void> audioPlay(String playerId) => _audio.play(playerId);

  @override
  Future<void> audioPause(String playerId) => _audio.pause(playerId);

  @override
  Future<void> audioSeek(String playerId, Duration position) =>
      _audio.seek(playerId, position.inMilliseconds);

  @override
  Future<void> audioSetSpeed(String playerId, double speed) =>
      _audio.setSpeed(playerId, speed);

  @override
  Future<void> audioSetVolume(String playerId, double volume) =>
      _audio.setVolume(playerId, volume);

  @override
  Future<void> audioDispose(String playerId) => _audio.dispose(playerId);

  @override
  Stream<Map<Object?, Object?>> audioEvents(String playerId) =>
      _eventsFor(EventChannel('attachment_engine/audio_events/$playerId'));

  // ---------------------------------------------------------------------
  // Video
  // ---------------------------------------------------------------------

  @override
  Future<void> videoLoad(String playerId, {String? filePath, String? url}) =>
      _video.load(playerId, filePath, url);

  @override
  Future<void> videoPlay(String playerId) => _video.play(playerId);

  @override
  Future<void> videoPause(String playerId) => _video.pause(playerId);

  @override
  Future<void> videoSeek(String playerId, Duration position) =>
      _video.seek(playerId, position.inMilliseconds);

  @override
  Future<void> videoSetSpeed(String playerId, double speed) =>
      _video.setSpeed(playerId, speed);

  @override
  Future<void> videoSetVolume(String playerId, double volume) =>
      _video.setVolume(playerId, volume);

  @override
  Future<void> videoDispose(String playerId) => _video.dispose(playerId);

  @override
  Stream<Map<Object?, Object?>> videoEvents(String playerId) =>
      _eventsFor(EventChannel('attachment_engine/video_events/$playerId'));

  @override
  Widget videoBuildView(String playerId) {
    return UiKitView(
      viewType: 'attachment_engine/video_view',
      creationParams: {'playerId': playerId},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  // ---------------------------------------------------------------------
  // Share
  // ---------------------------------------------------------------------

  @override
  Future<void> shareFile(String path, {String? text}) =>
      _share.shareFile(path, text);

  @override
  Future<void> shareText(String text) => _share.shareText(text);

  // ---------------------------------------------------------------------
  // Open externally
  // ---------------------------------------------------------------------

  @override
  Future<NativeOpenResult> openExternally(
    String path, {
    String? mimeType,
  }) async {
    try {
      final result = await _open.openExternally(path, mimeType);
      return NativeOpenResult(success: result.success, message: result.message);
    } on PlatformException catch (e) {
      return NativeOpenResult(success: false, message: e.message);
    }
  }

  // ---------------------------------------------------------------------
  // Office preview
  // ---------------------------------------------------------------------

  @override
  Future<void> openOfficePreview(String path) =>
      _office.openOfficePreview(path);

  // ---------------------------------------------------------------------
  // Paths
  // ---------------------------------------------------------------------

  @override
  Future<String> getApplicationSupportDirectory() =>
      _paths.getApplicationSupportDirectory();

  @override
  Future<String> getApplicationCacheDirectory() =>
      _paths.getApplicationCacheDirectory();

  // ---------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------

  @override
  Future<String> startDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) => _download.startDownload(url, headers, destPath);

  @override
  Future<String> resumeDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) => _download.resumeDownload(url, headers, destPath);

  @override
  Future<void> cancelDownload(String downloadId) =>
      _download.cancelDownload(downloadId);

  @override
  Stream<Map<Object?, Object?>> downloadEvents() =>
      _eventsFor(_downloadEventChannel);
}
