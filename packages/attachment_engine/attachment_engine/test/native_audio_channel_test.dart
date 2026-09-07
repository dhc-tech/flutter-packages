// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine/src/native/native_audio_channel.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// A platform whose [audioSetVolume] doesn't resolve until [completeVolume]
/// is called — lets a test dispose the controller while a volume call is
/// still in flight.
class _DelayedVolumeFailurePlatform extends AttachmentEnginePlatform {
  final _pending = <Completer<void>>[];

  void completeAllWithError() {
    for (final c in _pending) {
      if (!c.isCompleted) c.completeError(StateError('player disposed'));
    }
  }

  @override
  Stream<Map<Object?, Object?>> audioEvents(String playerId) =>
      const Stream.empty();

  @override
  Future<void> audioLoad(String playerId, {String? filePath, String? url}) =>
      Future.value();

  @override
  Future<void> audioPlay(String playerId) => Future.value();

  @override
  Future<void> audioPause(String playerId) => Future.value();

  @override
  Future<void> audioSeek(String playerId, Duration position) => Future.value();

  @override
  Future<void> audioSetVolume(String playerId, double volume) {
    final completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  Future<void> audioDispose(String playerId) => Future.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setVolume does not throw when the controller is disposed before a '
      'failed platform call resolves', () async {
    final platform = _DelayedVolumeFailurePlatform();
    AttachmentEnginePlatform.instance = platform;

    final controller = NativeAudioController();
    final setVolumeFuture = controller.setVolume(0.4);

    // Dispose while setVolume is still in flight — this is what disposes
    // `volume` (a ValueNotifier) before the pending call's catch block
    // tries to write to it.
    await controller.dispose();

    // Now let the pending platform call fail; setVolume's catch block
    // runs post-disposal. Without the disposed-guard, ValueNotifier
    // throws "A ChangeNotifier was used after being disposed" here,
    // which — since nothing awaits setVolumeFuture — would surface as an
    // unhandled async error and fail this test.
    platform.completeAllWithError();
    await setVolumeFuture;
  });
}
