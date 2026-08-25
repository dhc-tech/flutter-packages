// Pigeon schema for the attachment_engine plugin's method-call surface.
//
// This file defines every request/response-style native call (PDF, Audio,
// Video, Share, Open-externally, Office preview, Paths, Download) as
// type-safe Pigeon `@HostApi()` interfaces. Run `dart run pigeon` (see
// `tool/generate_pigeon.sh` in this package) to regenerate the Dart, Kotlin,
// and Swift bindings from this single source of truth.
//
// Deliberately NOT covered here: the audio/video/download *event streams*.
// Pigeon's `@EventChannelApi` generates one static channel per API (or per
// `NSObject`-suffixed instance with a fixed suffix string known ahead of
// time), but this plugin needs a channel name keyed by a *dynamically
// created* `playerId` chosen at runtime by the Dart side (potentially many
// concurrent audio/video players). That per-instance dynamic naming doesn't
// fit Pigeon's event-channel model cleanly, so those three streams remain
// hand-written `EventChannel`s on both the Dart and native side (see
// `audioEvents`/`videoEvents`/`downloadEvents` in each platform package).
import 'package:pigeon/pigeon.dart';

/// Result of opening a PDF document natively.
class PdfOpenResultMessage {
  PdfOpenResultMessage({required this.handle, required this.pageCount});

  /// Opaque handle identifying the open document on the native side.
  String handle;

  /// Number of pages in the document.
  int pageCount;
}

/// Result of an "open externally" request (hand the file to another app).
class NativeOpenResultMessage {
  NativeOpenResultMessage({required this.success, this.message});

  bool success;
  String? message;
}

/// PDF (open/renderPage/close). Replaces `pdfx`.
@HostApi()
abstract class PdfHostApi {
  @async
  PdfOpenResultMessage open(String path);

  @async
  Uint8List renderPage(String handle, int index, int width, int height);

  @async
  void close(String handle);
}

/// Audio playback control (load/play/pause/seek/setSpeed/setVolume/dispose).
/// Replaces `just_audio`. Playback-state events stay on a hand-written
/// per-`playerId` `EventChannel` — see the note at the top of this file.
@HostApi()
abstract class AudioHostApi {
  @async
  void load(String playerId, String? filePath, String? url);

  @async
  void play(String playerId);

  @async
  void pause(String playerId);

  @async
  void seek(String playerId, int positionMs);

  @async
  void setSpeed(String playerId, double speed);

  @async
  void setVolume(String playerId, double volume);

  @async
  void dispose(String playerId);
}

/// Video playback control (load/play/pause/seek/setSpeed/setVolume/dispose).
/// Replaces `video_player`'s control API. The platform-view factory that
/// embeds the native surface stays native/hand-registered (it isn't a
/// method call), and playback-state events stay on a hand-written
/// per-`playerId` `EventChannel` — see the note at the top of this file.
@HostApi()
abstract class VideoHostApi {
  @async
  void load(String playerId, String? filePath, String? url);

  @async
  void play(String playerId);

  @async
  void pause(String playerId);

  @async
  void seek(String playerId, int positionMs);

  @async
  void setSpeed(String playerId, double speed);

  @async
  void setVolume(String playerId, double volume);

  @async
  void dispose(String playerId);
}

/// Share (shareFile/shareText). Replaces `share_plus`.
@HostApi()
abstract class ShareHostApi {
  @async
  void shareFile(String path, String? text);

  @async
  void shareText(String text);
}

/// Open externally (hand the file to another app via the OS chooser).
/// Replaces `open_filex`.
@HostApi()
abstract class OpenHostApi {
  @async
  NativeOpenResultMessage openExternally(String path, String? mimeType);
}

/// In-app Office document preview (iOS/macOS QuickLook). Android has no
/// native in-app viewer and falls back to [OpenHostApi.openExternally] at
/// the Dart layer, so Android does not need to implement this API.
@HostApi()
abstract class OfficeHostApi {
  @async
  void openOfficePreview(String path);
}

/// App-private storage directories. Replaces `path_provider`.
@HostApi()
abstract class PathsHostApi {
  @async
  String getApplicationSupportDirectory();

  @async
  String getApplicationCacheDirectory();
}

/// Download start/resume/cancel. Replaces `dio`. Progress/completion/error
/// events stay on a hand-written shared `EventChannel` — see the note at
/// the top of this file.
@HostApi()
abstract class DownloadHostApi {
  @async
  String startDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  );

  @async
  String resumeDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  );

  @async
  void cancelDownload(String downloadId);
}
