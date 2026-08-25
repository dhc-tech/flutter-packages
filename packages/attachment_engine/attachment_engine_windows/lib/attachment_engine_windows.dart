// Copyright 2026 DHC
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/attachment_engine_desktop_impl.dart';

export 'src/attachment_engine_desktop_impl.dart'
    show AttachmentEngineDesktopImpl;

/// The Windows implementation of `attachment_engine`.
///
/// Paths/open-externally/download come from [AttachmentEngineDesktopImpl]
/// (pure Dart, shared with Linux). Share and audio/video playback are
/// implemented natively in C++ (see `windows/share_channel.cpp`,
/// `windows/audio_channel.cpp`, `windows/video_channel.cpp` — NOT yet
/// build-verified on this machine, see those files' header comments) and
/// wired up here via the exact same `MethodChannel`/`EventChannel` names
/// used by the Android (Kotlin) and iOS (Swift) implementations of this
/// plugin, so app-facing Dart code behaves identically across platforms.
class AttachmentEngineWindows extends AttachmentEngineDesktopImpl {
  /// Registers this class as the default instance of [AttachmentEnginePlatform].
  static void registerWith() {
    AttachmentEnginePlatform.instance = AttachmentEngineWindows();
  }

  static const MethodChannel _shareChannel = MethodChannel(
    'attachment_engine/share',
  );
  static const MethodChannel _audioChannel = MethodChannel(
    'attachment_engine/audio',
  );
  static const MethodChannel _videoChannel = MethodChannel(
    'attachment_engine/video',
  );

  Stream<Map<Object?, Object?>> _eventsFor(EventChannel channel) => channel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => event as Map<Object?, Object?>);

  // ---------------------------------------------------------------------
  // Share (native: IDataTransferManagerInterop / DataTransferManager —
  // see windows/share_channel.h for the documented API).
  // ---------------------------------------------------------------------

  @override
  Future<void> shareFile(String path, {String? text}) =>
      _shareChannel.invokeMethod('shareFile', {'path': path, 'text': ?text});

  @override
  Future<void> shareText(String text) =>
      _shareChannel.invokeMethod('shareText', {'text': text});

  // ---------------------------------------------------------------------
  // Audio (native: Media Foundation IMFMediaEngine — see
  // windows/audio_channel.h for the documented API).
  // ---------------------------------------------------------------------

  @override
  Future<void> audioLoad(String playerId, {String? filePath, String? url}) =>
      _audioChannel.invokeMethod('load', {
        'playerId': playerId,
        'path': ?filePath,
        'url': ?url,
      });

  @override
  Future<void> audioPlay(String playerId) =>
      _audioChannel.invokeMethod('play', {'playerId': playerId});

  @override
  Future<void> audioPause(String playerId) =>
      _audioChannel.invokeMethod('pause', {'playerId': playerId});

  @override
  Future<void> audioSeek(String playerId, Duration position) =>
      _audioChannel.invokeMethod('seek', {
        'playerId': playerId,
        'positionMs': position.inMilliseconds,
      });

  @override
  Future<void> audioSetSpeed(String playerId, double speed) => _audioChannel
      .invokeMethod('setSpeed', {'playerId': playerId, 'speed': speed});

  @override
  Future<void> audioSetVolume(String playerId, double volume) => _audioChannel
      .invokeMethod('setVolume', {'playerId': playerId, 'volume': volume});

  @override
  Future<void> audioDispose(String playerId) =>
      _audioChannel.invokeMethod('dispose', {'playerId': playerId});

  @override
  Stream<Map<Object?, Object?>> audioEvents(String playerId) =>
      _eventsFor(EventChannel('attachment_engine/audio_events/$playerId'));

  // ---------------------------------------------------------------------
  // Video (native: Media Foundation IMFMediaEngine rendering to a child
  // HWND — see windows/video_channel.h for the documented API and the
  // embedding tradeoff).
  // ---------------------------------------------------------------------

  @override
  Future<void> videoLoad(String playerId, {String? filePath, String? url}) =>
      _videoChannel.invokeMethod('load', {
        'playerId': playerId,
        'path': ?filePath,
        'url': ?url,
      });

  @override
  Future<void> videoPlay(String playerId) =>
      _videoChannel.invokeMethod('play', {'playerId': playerId});

  @override
  Future<void> videoPause(String playerId) =>
      _videoChannel.invokeMethod('pause', {'playerId': playerId});

  @override
  Future<void> videoSeek(String playerId, Duration position) =>
      _videoChannel.invokeMethod('seek', {
        'playerId': playerId,
        'positionMs': position.inMilliseconds,
      });

  @override
  Future<void> videoSetSpeed(String playerId, double speed) => _videoChannel
      .invokeMethod('setSpeed', {'playerId': playerId, 'speed': speed});

  @override
  Future<void> videoSetVolume(String playerId, double volume) => _videoChannel
      .invokeMethod('setVolume', {'playerId': playerId, 'volume': volume});

  @override
  Future<void> videoDispose(String playerId) =>
      _videoChannel.invokeMethod('dispose', {'playerId': playerId});

  @override
  Stream<Map<Object?, Object?>> videoEvents(String playerId) =>
      _eventsFor(EventChannel('attachment_engine/video_events/$playerId'));

  /// Unlike Android/iOS (which embed video through a real
  /// `PlatformView`/`FlutterPlatformView` that Flutter positions
  /// automatically), the native Windows implementation renders to a
  /// separate child HWND that has to be told its bounds explicitly (see
  /// `windows/video_channel.h`'s "Embedding tradeoff"). [_VideoSurface]
  /// reports its `RenderBox` bounds over `setLayout` on every layout pass
  /// so the native HWND tracks the widget.
  @override
  Widget videoBuildView(String playerId) {
    return _VideoSurface(playerId: playerId, videoChannel: _videoChannel);
  }
}

class _VideoSurface extends StatefulWidget {
  const _VideoSurface({required this.playerId, required this.videoChannel});

  final String playerId;
  final MethodChannel videoChannel;

  @override
  State<_VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<_VideoSurface> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final renderObject = context.findRenderObject();
          if (renderObject is! RenderBox || !renderObject.hasSize) return;
          final topLeft = renderObject.localToGlobal(Offset.zero);
          final size = renderObject.size;
          widget.videoChannel.invokeMethod('setLayout', {
            'playerId': widget.playerId,
            'left': topLeft.dx.round(),
            'top': topLeft.dy.round(),
            'width': size.width.round(),
            'height': size.height.round(),
          });
        });
        // The actual video pixels are drawn by the native child HWND
        // layered on top of this widget's bounds, not by Flutter itself —
        // this is a transparent placeholder that only exists to report
        // layout.
        return const SizedBox.expand();
      },
    );
  }
}
