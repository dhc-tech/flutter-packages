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
  NativeVideoController() : playerId = (_nextId++).toString();

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

  /// Awaits the native `load` call *before* subscribing to this player's
  /// event stream. The iOS/Android implementations create and register the
  /// `video_events/{playerId}` `EventChannel` handler *inside* their
  /// native `load` handler, not eagerly — so the handler is only
  /// guaranteed to exist once that call has actually completed.
  ///
  /// An earlier version of this fired the `listen()` request right after
  /// (not awaiting) the `load` call, reasoning that two platform-channel
  /// sends issued in the same synchronous Dart tick would arrive in order.
  /// That held for a plain synchronous native handler, but this host API is
  /// Pigeon-generated as `async throws` on `@MainActor` on iOS — invoking
  /// it hops through a Swift `Task`/continuation rather than running
  /// synchronously inline, so the `listen` message (dispatched immediately,
  /// no such hop) could still reach the engine and get routed to the
  /// EventChannel *before* the load handler had run far enough to register
  /// its stream handler, throwing `MissingPluginException` and starving
  /// this controller of every future status event. Awaiting removes the
  /// race entirely — the tradeoff is that any event the native side emits
  /// synchronously *during* `load` itself (e.g. an initial "buffering"
  /// state) fires before anything is subscribed and is lost; harmless here
  /// since [status] already reports "idle"/"buffering" until the first
  /// event received after subscribing updates it.
  Future<void> load({String? filePath, String? url}) async {
    try {
      await AttachmentEnginePlatform.instance.videoLoad(
        playerId,
        filePath: filePath,
        url: url,
      );
    } finally {
      _eventSub ??= AttachmentEnginePlatform.instance
          .videoEvents(playerId)
          .listen(_onEvent, onError: (_) {});
    }
  }

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
