// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/widgets.dart';

import 'native_audio_channel.dart'
    show NativePlaybackState, NativePlaybackStatus;

/// Replaces `video_player`. Rendering happens via a native
/// `FlutterPlatformView`, built by [AttachmentEnginePlatform.videoBuildView]:
/// iOS embeds an `AVPlayerViewController`'s view through a `UiKitView`
/// (tradeoff: pulls in the system playback chrome unless customized further
/// — acceptable for this pass, see README); Android embeds a Media3
/// `PlayerView` through an `AndroidView`.
///
/// Playback control (play/pause/seek/speed/volume) and position/buffering
/// events go through [AttachmentEnginePlatform], keyed by [playerId] — the
/// same id used as the platform view's creation parameter, so the platform
/// view and the control channel address the same native player instance.
/// The actual channel transport is owned by the platform implementation
/// package (`attachment_engine_android` / `attachment_engine_ios`).
class NativeVideoController {
  NativeVideoController() : playerId = (_nextId++).toString() {
    _eventSub = AttachmentEnginePlatform.instance
        .videoEvents(playerId)
        .listen(_onEvent, onError: (_) {});
  }

  static int _nextId = 0;

  final String playerId;
  StreamSubscription<Object?>? _eventSub;

  final StreamController<NativePlaybackStatus> _statusController =
      StreamController<NativePlaybackStatus>.broadcast();
  NativePlaybackStatus _status = NativePlaybackStatus.initial();
  double aspectRatio = 16 / 9;

  Stream<NativePlaybackStatus> get statusStream => _statusController.stream;
  NativePlaybackStatus get status => _status;
  bool get isPlaying => _status.state == NativePlaybackState.playing;

  void _onEvent(Object? event) {
    if (event is! Map) return;
    final stateName = event['state'] as String?;
    final state = NativePlaybackState.values.firstWhere(
      (s) => s.name == stateName,
      orElse: () => _status.state,
    );
    final positionMs = (event['positionMs'] as num?)?.toInt();
    final durationMs = (event['durationMs'] as num?)?.toInt();
    final width = (event['width'] as num?)?.toDouble();
    final height = (event['height'] as num?)?.toDouble();
    if (width != null && height != null && height > 0) {
      aspectRatio = width / height;
    }
    _status = NativePlaybackStatus(
      state: state,
      position: Duration(
        milliseconds: positionMs ?? _status.position.inMilliseconds,
      ),
      duration: durationMs == null
          ? _status.duration
          : Duration(milliseconds: durationMs),
    );
    _statusController.add(_status);
  }

  Future<void> load({String? filePath, String? url}) => AttachmentEnginePlatform
      .instance
      .videoLoad(playerId, filePath: filePath, url: url);

  Future<void> play() => AttachmentEnginePlatform.instance.videoPlay(playerId);

  Future<void> pause() =>
      AttachmentEnginePlatform.instance.videoPause(playerId);

  Future<void> seek(Duration position) =>
      AttachmentEnginePlatform.instance.videoSeek(playerId, position);

  Future<void> setSpeed(double speed) =>
      AttachmentEnginePlatform.instance.videoSetSpeed(playerId, speed);

  Future<void> setVolume(double volume) =>
      AttachmentEnginePlatform.instance.videoSetVolume(playerId, volume);

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _statusController.close();
    await AttachmentEnginePlatform.instance.videoDispose(playerId);
  }

  /// The embedded native player surface. Must be built after [load] has
  /// been invoked at least once so the native side has a player ready to
  /// attach to.
  Widget buildView() =>
      AttachmentEnginePlatform.instance.videoBuildView(playerId);
}
