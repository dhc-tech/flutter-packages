// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

/// Playback/buffering state mirrored from the native side.
enum NativePlaybackState {
  idle,
  buffering,
  ready,
  playing,
  paused,
  completed,
  error,
}

class NativePlaybackStatus {
  const NativePlaybackStatus({
    required this.state,
    required this.position,
    required this.duration,
  });

  final NativePlaybackState state;
  final Duration position;
  final Duration? duration;

  factory NativePlaybackStatus.initial() => const NativePlaybackStatus(
    state: NativePlaybackState.idle,
    position: Duration.zero,
    duration: null,
  );
}

/// Replaces `just_audio`. iOS: AVFoundation (`AVAudioPlayer` for local
/// files, `AVPlayer` for streaming remote URLs). Android: Media3/ExoPlayer
/// (falls back to `MediaMediaPlayer` API-shape) for local/streaming audio.
///
/// Each controller owns one native player instance, identified by
/// [playerId], and talks to it exclusively through
/// [AttachmentEnginePlatform] — the actual channel transport is owned by
/// the platform implementation package (`attachment_engine_android` /
/// `attachment_engine_ios`).
class NativeAudioController {
  NativeAudioController() : playerId = (_nextId++).toString() {
    _eventSub = AttachmentEnginePlatform.instance
        .audioEvents(playerId)
        .listen(_onEvent, onError: (_) {});
  }

  static int _nextId = 0;

  final String playerId;
  StreamSubscription<Object?>? _eventSub;

  final StreamController<NativePlaybackStatus> _statusController =
      StreamController<NativePlaybackStatus>.broadcast();
  NativePlaybackStatus _status = NativePlaybackStatus.initial();

  Stream<NativePlaybackStatus> get statusStream => _statusController.stream;
  NativePlaybackStatus get status => _status;
  Duration? get duration => _status.duration;

  /// Lives on the controller (not the widget) because [NativeAudioController]
  /// is pool-shared by [playerId]/stable-identity — if two renderers show
  /// the same attachment concurrently, changing volume in one must be
  /// reflected in the other rather than leaving its slider showing a stale
  /// value while the underlying native player's volume actually changed.
  final ValueNotifier<double> volume = ValueNotifier<double>(1);

  void _onEvent(Object? event) {
    if (event is! Map) return;
    final stateName = event['state'] as String?;
    final state = NativePlaybackState.values.firstWhere(
      (s) => s.name == stateName,
      orElse: () => _status.state,
    );
    final positionMs = (event['positionMs'] as num?)?.toInt();
    final durationMs = (event['durationMs'] as num?)?.toInt();
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

  Future<void> setFilePath(String path) =>
      AttachmentEnginePlatform.instance.audioLoad(playerId, filePath: path);

  Future<void> setUrl(String url) =>
      AttachmentEnginePlatform.instance.audioLoad(playerId, url: url);

  Future<void> play() => AttachmentEnginePlatform.instance.audioPlay(playerId);

  Future<void> pause() =>
      AttachmentEnginePlatform.instance.audioPause(playerId);

  Future<void> seek(Duration position) =>
      AttachmentEnginePlatform.instance.audioSeek(playerId, position);

  Future<void> setSpeed(double speed) =>
      AttachmentEnginePlatform.instance.audioSetSpeed(playerId, speed);

  /// Updates [volume] optimistically (so the slider tracks the drag
  /// immediately), then reverts it if the platform call actually fails —
  /// e.g. the player was disposed mid-drag, or the platform implementation
  /// rejects the request. Never throws: `Slider.onChanged` is a
  /// fire-and-forget `void Function(double)`, so an unhandled rejection
  /// here would otherwise become an unhandled async error with no way for
  /// the UI to react to it.
  Future<void> setVolume(double newVolume) async {
    final previousVolume = volume.value;
    volume.value = newVolume;
    try {
      await AttachmentEnginePlatform.instance.audioSetVolume(
        playerId,
        newVolume,
      );
    } catch (_) {
      volume.value = previousVolume;
    }
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _statusController.close();
    volume.dispose();
    await AttachmentEnginePlatform.instance.audioDispose(playerId);
  }
}
