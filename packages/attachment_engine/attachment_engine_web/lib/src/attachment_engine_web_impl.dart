// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/widgets.dart';

/// Minimal `dart:js_interop` bindings for exactly the browser APIs this
/// implementation needs. `dart:js_interop` is a Dart SDK core library, not
/// a pub package — this avoids even the (already-official,
/// `dart.dev`-published) `package:web` dependency, so this package depends
/// on nothing but the SDK itself (plus `flutter`/`flutter_web_plugins`).
@JS('navigator')
external _Navigator get _navigator;

extension type _Navigator._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> share(_ShareData data);
  external _StorageManager get storage;
}

extension type _ShareData._(JSObject _) implements JSObject {
  external factory _ShareData({String? text});
}

@JS('window')
external _Window get _window;

extension type _Window._(JSObject _) implements JSObject {
  external JSObject? open(String url, String target, String features);
}

// ---------------------------------------------------------------------
// Origin Private File System (OPFS)
// ---------------------------------------------------------------------

extension type _StorageManager._(JSObject _) implements JSObject {
  external JSPromise<_FileSystemDirectoryHandle> getDirectory();
}

extension type _FileSystemDirectoryHandle._(JSObject _) implements JSObject {
  external JSPromise<_FileSystemDirectoryHandle> getDirectoryHandle(
    String name, [
    _GetOptions options,
  ]);
  external JSPromise<_FileSystemFileHandle> getFileHandle(
    String name, [
    _GetOptions options,
  ]);
}

extension type _GetOptions._(JSObject _) implements JSObject {
  external factory _GetOptions({bool? create});
}

extension type _FileSystemFileHandle._(JSObject _) implements JSObject {
  external JSPromise<_FileSystemWritableFileStream> createWritable([
    _CreateWritableOptions options,
  ]);
  external JSPromise<_JSFile> getFile();
}

extension type _CreateWritableOptions._(JSObject _) implements JSObject {
  external factory _CreateWritableOptions({bool? keepExistingData});
}

extension type _FileSystemWritableFileStream._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSAny data);
  external JSPromise<JSAny?> close();
}

extension type _WriteParams._(JSObject _) implements JSObject {
  external factory _WriteParams({
    required String type,
    required int position,
    required JSAny data,
  });
}

extension type _JSFile._(JSObject _) implements JSObject {
  external int get size;
}

// ---------------------------------------------------------------------
// fetch() / Fetch API (used for downloads, with progress + cancellation)
// ---------------------------------------------------------------------

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(String url, [_RequestInit init]);

extension type _RequestInit._(JSObject _) implements JSObject {
  external factory _RequestInit({JSAny? headers, JSAny? signal});
}

extension type _FetchResponse._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external _FetchHeaders get headers;
  external _ReadableStream? get body;
}

extension type _FetchHeaders._(JSObject _) implements JSObject {
  external String? get(String name);
}

extension type _ReadableStream._(JSObject _) implements JSObject {
  external _ReadableStreamDefaultReader getReader();
}

extension type _ReadableStreamDefaultReader._(JSObject _) implements JSObject {
  external JSPromise<_ReadResult> read();
  external JSPromise<JSAny?> cancel();
}

extension type _ReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external _AbortSignal get signal;
  external void abort();
}

extension type _AbortSignal._(JSObject _) implements JSObject {}

// ---------------------------------------------------------------------
// HTML <video>/<audio> elements, for embedded playback
// ---------------------------------------------------------------------

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external _MediaElement createElement(String tagName);
}

extension type _MediaElement._(JSObject _) implements JSObject {
  external set src(String value);
  external double currentTime;
  external double get duration;
  external double playbackRate;
  external double volume;
  external bool get paused;
  external bool get ended;
  external int get videoWidth;
  external int get videoHeight;
  external JSObject? style;
  external void play();
  external void pause();
  external void load();
  external void addEventListener(String type, JSFunction listener);
}

/// The web implementation of [AttachmentEnginePlatform], backed by raw
/// `dart:js_interop` (a Dart SDK core library, not a pub package) — no
/// third-party plugin dependencies, not even `package:web`.
///
/// Implements:
/// - Share (`shareText`) via the browser's native
///   [Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API)
///   (`navigator.share`).
/// - Open externally (`openExternally`, and `openOfficePreview` falling
///   back to it) via `window.open`.
/// - Paths (`getApplicationSupportDirectory`/`getApplicationCacheDirectory`)
///   via the browser's real
///   [Origin Private File System](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API/Origin_private_file_system)
///   (`navigator.storage.getDirectory()`). See the "Paths on web" note
///   below — the returned strings are stable logical keys, not real OS
///   paths.
/// - Download (`startDownload`/`resumeDownload`/`cancelDownload`/
///   `downloadEvents`) via `fetch()` streamed into OPFS, with an
///   `AbortController` backing cancellation.
/// - Video/audio playback (`video*`/`audio*`) via real `<video>`/`<audio>`
///   elements, embedded through `dart:ui_web`'s platform-view registry.
///
/// ### Paths on web
///
/// The browser sandbox has no real absolute filesystem path the way native
/// platforms do. [getApplicationSupportDirectory] and
/// [getApplicationCacheDirectory] instead return a **stable logical key**
/// (`/attachment_engine/support`, `/attachment_engine/cache`) — NOT a real
/// OS path. This implementation's own [startDownload]/[resumeDownload]
/// understand these keys (and any path built by joining them with `/` and
/// a filename) as a slash-separated chain of OPFS directory names, and
/// will create the directory chain on demand. Any caller that treats the
/// returned string as an opaque path to hand back into this same
/// implementation's methods will work correctly; treating it as a real OS
/// path (e.g. showing it to a user, or handing it to another API) is not
/// supported.
///
/// Does NOT implement (throws [UnimplementedError]):
/// - `shareFile` — the Web Share API needs an in-memory `File`/`Blob`, not
///   a filesystem path.
/// - `pdfOpen`/`pdfRenderPage`/`pdfClose` — see the README for why PDF.js
///   integration was left as a documented follow-up rather than forced in.
class AttachmentEngineWebImpl extends AttachmentEnginePlatform {
  /// Registers this class as the default instance of [AttachmentEnginePlatform].
  static void registerWith(dynamic registrar) {
    AttachmentEnginePlatform.instance = AttachmentEngineWebImpl();
  }

  // ---------------------------------------------------------------------
  // Share
  // ---------------------------------------------------------------------

  @override
  Future<void> shareFile(String path, {String? text}) async {
    // The browser sandbox has no filesystem path to hand to the Web Share
    // API — only in-memory File/Blob objects, which this platform
    // interface's path-based contract doesn't carry. shareText covers the
    // text-only case; sharing an actual file needs a byte-based contract
    // addition, tracked as a follow-up.
    throw UnimplementedError(
      'shareFile() is not supported on web — the Web Share API requires an '
      'in-memory File/Blob, not a filesystem path. Use shareText() for '
      'text/links, or share raw bytes once a byte-based contract exists.',
    );
  }

  @override
  Future<void> shareText(String text) async {
    await _navigator.share(_ShareData(text: text)).toDart;
  }

  // ---------------------------------------------------------------------
  // Open externally
  // ---------------------------------------------------------------------

  @override
  Future<NativeOpenResult> openExternally(
    String path, {
    String? mimeType,
  }) async {
    try {
      final opened = _window.open(path, '_blank', '');
      return NativeOpenResult(
        success: opened != null,
        message: opened != null
            ? null
            : 'The browser blocked opening this URL (popup blocker or '
                  'invalid URL).',
      );
    } catch (e) {
      return NativeOpenResult(success: false, message: e.toString());
    }
  }

  @override
  Future<void> openOfficePreview(String path) async {
    await openExternally(path);
  }

  // ---------------------------------------------------------------------
  // Paths (Origin Private File System)
  // ---------------------------------------------------------------------

  static const String supportDirKey = '/attachment_engine/support';
  static const String cacheDirKey = '/attachment_engine/cache';

  _FileSystemDirectoryHandle? _root;

  Future<_FileSystemDirectoryHandle> _rootDir() async {
    return _root ??= await _navigator.storage.getDirectory().toDart;
  }

  List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  /// Walks/creates the directory chain for [path] (all segments treated as
  /// directory names) and returns the final directory handle.
  Future<_FileSystemDirectoryHandle> _ensureDir(String path) async {
    var dir = await _rootDir();
    for (final segment in _segments(path)) {
      dir = await dir
          .getDirectoryHandle(segment, _GetOptions(create: true))
          .toDart;
    }
    return dir;
  }

  /// Resolves [path] to a file handle: all but the last segment are
  /// directories (created on demand when [create] is true), and the last
  /// segment is the file name.
  Future<_FileSystemFileHandle> _resolveFile(
    String path, {
    required bool create,
  }) async {
    final segments = _segments(path);
    if (segments.isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
    var dir = await _rootDir();
    for (final segment in segments.sublist(0, segments.length - 1)) {
      dir = await dir
          .getDirectoryHandle(segment, _GetOptions(create: create))
          .toDart;
    }
    return dir.getFileHandle(segments.last, _GetOptions(create: create)).toDart;
  }

  @override
  Future<String> getApplicationSupportDirectory() async {
    await _ensureDir(supportDirKey);
    return supportDirKey;
  }

  @override
  Future<String> getApplicationCacheDirectory() async {
    await _ensureDir(cacheDirKey);
    return cacheDirKey;
  }

  // ---------------------------------------------------------------------
  // Download (fetch() streamed into OPFS)
  // ---------------------------------------------------------------------

  final StreamController<Map<Object?, Object?>> _downloadEvents =
      StreamController<Map<Object?, Object?>>.broadcast();
  final Map<String, _AbortController> _abortControllers = {};
  int _downloadCounter = 0;

  @override
  Future<String> startDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) => _download(url, headers, destPath, resume: false);

  @override
  Future<String> resumeDownload(
    String url,
    Map<String, String> headers,
    String destPath,
  ) => _download(url, headers, destPath, resume: true);

  Future<String> _download(
    String url,
    Map<String, String> headers,
    String destPath, {
    required bool resume,
  }) async {
    final id = 'attachment_engine_web_download_${_downloadCounter++}';
    final controller = _AbortController();
    _abortControllers[id] = controller;
    unawaited(_runDownload(id, url, headers, destPath, resume: resume));
    return id;
  }

  Future<void> _runDownload(
    String id,
    String url,
    Map<String, String> headers,
    String destPath, {
    required bool resume,
  }) async {
    _FileSystemWritableFileStream? writable;
    try {
      final controller = _abortControllers[id]!;
      var receivedSoFar = 0;

      final fileHandle = await _resolveFile(destPath, create: true);
      if (resume) {
        final existing = await fileHandle.getFile().toDart;
        receivedSoFar = existing.size;
      }

      final requestHeaders = <String, String>{...headers};
      if (resume && receivedSoFar > 0) {
        requestHeaders['Range'] = 'bytes=$receivedSoFar-';
      }

      final response = await _fetch(
        url,
        _RequestInit(
          headers: requestHeaders.jsify(),
          signal: controller.signal,
        ),
      ).toDart;

      if (response.status >= 400) {
        _downloadEvents.add({
          'downloadId': id,
          'type': 'error',
          'path': destPath,
          'message': 'HTTP ${response.status}',
        });
        return;
      }

      // A server that ignores Range restarts from byte 0.
      final partial = response.status == 206;
      if (resume && receivedSoFar > 0 && !partial) {
        receivedSoFar = 0;
      }

      final contentLengthHeader = response.headers.get('content-length');
      final contentLength = contentLengthHeader != null
          ? int.tryParse(contentLengthHeader)
          : null;
      final total = contentLength != null ? receivedSoFar + contentLength : -1;

      writable = await fileHandle
          .createWritable(
            _CreateWritableOptions(
              keepExistingData: resume && receivedSoFar > 0,
            ),
          )
          .toDart;

      final body = response.body;
      if (body == null) {
        await writable.close().toDart;
        _downloadEvents.add({
          'downloadId': id,
          'type': 'complete',
          'path': destPath,
        });
        return;
      }

      final reader = body.getReader();
      var received = receivedSoFar;
      while (true) {
        final result = await reader.read().toDart;
        if (result.done) break;
        final chunk = result.value;
        if (chunk == null) continue;
        final bytes = chunk.toDart;
        await writable
            .write(_WriteParams(type: 'write', position: received, data: chunk))
            .toDart;
        received += bytes.length;
        _downloadEvents.add({
          'downloadId': id,
          'type': 'progress',
          'received': received,
          'total': total,
          'path': destPath,
        });
      }

      await writable.close().toDart;
      writable = null;
      _downloadEvents.add({
        'downloadId': id,
        'type': 'complete',
        'path': destPath,
      });
    } catch (e) {
      final wasCancelled = _abortControllers[id] == null;
      _downloadEvents.add(
        wasCancelled
            ? {'downloadId': id, 'type': 'cancelled', 'path': destPath}
            : {
                'downloadId': id,
                'type': 'error',
                'path': destPath,
                'message': e.toString(),
              },
      );
    } finally {
      try {
        await writable?.close().toDart;
      } catch (_) {
        // Already closed/aborted — nothing further to do.
      }
      _abortControllers.remove(id);
    }
  }

  @override
  Future<void> cancelDownload(String downloadId) async {
    final controller = _abortControllers.remove(downloadId);
    controller?.abort();
    if (controller != null) {
      _downloadEvents.add({'downloadId': downloadId, 'type': 'cancelled'});
    }
  }

  @override
  Stream<Map<Object?, Object?>> downloadEvents() => _downloadEvents.stream;

  // ---------------------------------------------------------------------
  // Video / audio playback (real <video>/<audio> elements)
  // ---------------------------------------------------------------------

  final Map<String, _MediaElement> _videoElements = {};
  final Map<String, _MediaElement> _audioElements = {};
  final Map<String, StreamController<Map<Object?, Object?>>>
  _videoEventControllers = {};
  final Map<String, StreamController<Map<Object?, Object?>>>
  _audioEventControllers = {};
  final Set<String> _registeredVideoViews = {};

  StreamController<Map<Object?, Object?>> _eventsFor(
    Map<String, StreamController<Map<Object?, Object?>>> registry,
    String playerId,
  ) => registry.putIfAbsent(
    playerId,
    () => StreamController<Map<Object?, Object?>>.broadcast(),
  );

  _MediaElement _ensureVideoElement(String playerId) {
    return _videoElements.putIfAbsent(playerId, () {
      final element = _document.createElement('video');
      final events = _eventsFor(_videoEventControllers, playerId);
      _wireMediaEvents(element, events, isVideo: true);

      final viewType = 'attachment_engine_web/video/$playerId';
      if (_registeredVideoViews.add(viewType)) {
        ui_web.platformViewRegistry.registerViewFactory(
          viewType,
          (int viewId) => element,
        );
      }
      return element;
    });
  }

  _MediaElement _ensureAudioElement(String playerId) {
    return _audioElements.putIfAbsent(playerId, () {
      final element = _document.createElement('audio');
      final events = _eventsFor(_audioEventControllers, playerId);
      _wireMediaEvents(element, events, isVideo: false);
      return element;
    });
  }

  void _wireMediaEvents(
    _MediaElement element,
    StreamController<Map<Object?, Object?>> events, {
    required bool isVideo,
  }) {
    Map<Object?, Object?> snapshot(String state) {
      final positionMs = (element.currentTime * 1000).round();
      final durationMs = element.duration.isFinite
          ? (element.duration * 1000).round()
          : null;
      final map = <Object?, Object?>{
        'state': state,
        'positionMs': positionMs,
        'durationMs': ?durationMs,
      };
      if (isVideo) {
        map['width'] = element.videoWidth;
        map['height'] = element.videoHeight;
      }
      return map;
    }

    void listen(String type, String state) {
      element.addEventListener(
        type,
        ((JSAny? _) {
          events.add(snapshot(state));
        }).toJS,
      );
    }

    listen('loadedmetadata', 'ready');
    listen('playing', 'playing');
    listen('pause', 'paused');
    listen('timeupdate', 'playing');
    listen('waiting', 'buffering');
    listen('ended', 'completed');
    element.addEventListener(
      'error',
      ((JSAny? _) {
        events.add({'state': 'error'});
      }).toJS,
    );
  }

  Future<void> _loadMedia(
    _MediaElement element,
    StreamController<Map<Object?, Object?>> events, {
    String? filePath,
    String? url,
  }) async {
    final source = url ?? filePath;
    if (source == null) {
      events.add({'state': 'error'});
      return;
    }
    events.add({'state': 'buffering'});
    element.src = source;
    element.load();
  }

  @override
  Future<void> videoLoad(
    String playerId, {
    String? filePath,
    String? url,
  }) async {
    final element = _ensureVideoElement(playerId);
    await _loadMedia(
      element,
      _eventsFor(_videoEventControllers, playerId),
      filePath: filePath,
      url: url,
    );
  }

  @override
  Future<void> videoPlay(String playerId) async {
    _ensureVideoElement(playerId).play();
  }

  @override
  Future<void> videoPause(String playerId) async {
    _ensureVideoElement(playerId).pause();
  }

  @override
  Future<void> videoSeek(String playerId, Duration position) async {
    _ensureVideoElement(playerId).currentTime =
        position.inMilliseconds / 1000.0;
  }

  @override
  Future<void> videoSetSpeed(String playerId, double speed) async {
    _ensureVideoElement(playerId).playbackRate = speed;
  }

  @override
  Future<void> videoSetVolume(String playerId, double volume) async {
    _ensureVideoElement(playerId).volume = volume;
  }

  @override
  Future<void> videoDispose(String playerId) async {
    final element = _videoElements.remove(playerId);
    element?.pause();
    await _videoEventControllers.remove(playerId)?.close();
  }

  @override
  Stream<Map<Object?, Object?>> videoEvents(String playerId) =>
      _eventsFor(_videoEventControllers, playerId).stream;

  @override
  Widget videoBuildView(String playerId) {
    _ensureVideoElement(playerId);
    return HtmlElementView(viewType: 'attachment_engine_web/video/$playerId');
  }

  @override
  Future<void> audioLoad(
    String playerId, {
    String? filePath,
    String? url,
  }) async {
    final element = _ensureAudioElement(playerId);
    await _loadMedia(
      element,
      _eventsFor(_audioEventControllers, playerId),
      filePath: filePath,
      url: url,
    );
  }

  @override
  Future<void> audioPlay(String playerId) async {
    _ensureAudioElement(playerId).play();
  }

  @override
  Future<void> audioPause(String playerId) async {
    _ensureAudioElement(playerId).pause();
  }

  @override
  Future<void> audioSeek(String playerId, Duration position) async {
    _ensureAudioElement(playerId).currentTime =
        position.inMilliseconds / 1000.0;
  }

  @override
  Future<void> audioSetSpeed(String playerId, double speed) async {
    _ensureAudioElement(playerId).playbackRate = speed;
  }

  @override
  Future<void> audioSetVolume(String playerId, double volume) async {
    _ensureAudioElement(playerId).volume = volume;
  }

  @override
  Future<void> audioDispose(String playerId) async {
    final element = _audioElements.remove(playerId);
    element?.pause();
    await _audioEventControllers.remove(playerId)?.close();
  }

  @override
  Stream<Map<Object?, Object?>> audioEvents(String playerId) =>
      _eventsFor(_audioEventControllers, playerId).stream;
}
