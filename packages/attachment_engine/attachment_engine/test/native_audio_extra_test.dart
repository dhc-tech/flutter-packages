// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class _Platform extends AttachmentEnginePlatform {
  final List<String> calls = [];
  final events = <String, StreamController<Map<Object?, Object?>>>{};
  Object? failLoad;
  Object? failVolume;

  StreamController<Map<Object?, Object?>> _ctl(String id) => events.putIfAbsent(
    id,
    () => StreamController<Map<Object?, Object?>>.broadcast(),
  );

  void emit(String id, Map<Object?, Object?> e) => _ctl(id).add(e);

  @override
  Stream<Map<Object?, Object?>> audioEvents(String id) => _ctl(id).stream;

  @override
  Future<void> audioLoad(String id, {String? filePath, String? url}) async {
    calls.add('load:$id:${filePath ?? url}');
    if (failLoad != null) throw failLoad!;
  }

  @override
  Future<void> audioPlay(String id) async => calls.add('play:$id');
  @override
  Future<void> audioPause(String id) async => calls.add('pause:$id');
  @override
  Future<void> audioSeek(String id, Duration p) async =>
      calls.add('seek:$id:${p.inMilliseconds}');
  @override
  Future<void> audioSetSpeed(String id, double s) async =>
      calls.add('speed:$id:$s');
  @override
  Future<void> audioSetVolume(String id, double v) async {
    calls.add('volume:$id:$v');
    if (failVolume != null) throw failVolume!;
  }

  @override
  Future<void> audioDispose(String id) async => calls.add('dispose:$id');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Platform platform;
  late NativeAudioController controller;
  var disposed = false;

  setUp(() {
    platform = _Platform();
    AttachmentEnginePlatform.instance = platform;
    controller = NativeAudioController();
    disposed = false;
  });

  tearDown(() async {
    if (!disposed) await controller.dispose();
    for (final c in platform.events.values) {
      await c.close();
    }
  });

  test('starts idle with full volume and unknown duration', () {
    expect(controller.status.state, NativePlaybackState.idle);
    expect(controller.duration, isNull);
    expect(controller.volume.value, 1);
  });

  test('dispose can be called twice without throwing or disposing the player twice', () async {
    await controller.dispose();
    disposed = true;
    await controller.dispose();
    expect(
      platform.calls.where((c) => c == 'dispose:${controller.playerId}'),
      hasLength(1),
    );
  });

  test('ids are unique', () async {
    final other = NativeAudioController();
    addTearDown(other.dispose);
    expect(other.playerId, isNot(controller.playerId));
  });

  test('setFilePath and setUrl load the right source', () async {
    await controller.setFilePath('/a.mp3');
    expect(platform.calls.last, 'load:${controller.playerId}:/a.mp3');
    await controller.setUrl('https://x/a.mp3');
    expect(platform.calls.last, 'load:${controller.playerId}:https://x/a.mp3');
  });

  test('a failed load rethrows but still subscribes to events', () async {
    platform.failLoad = StateError('bad file');
    await expectLater(controller.setFilePath('/bad'), throwsStateError);
    platform.emit(controller.playerId, {'state': 'error'});
    await pumpEventQueue();
    expect(controller.status.state, NativePlaybackState.error);
  });

  test(
    'events update state, position and duration; absent fields are kept',
    () async {
      await controller.setUrl('https://x');
      final seen = <NativePlaybackStatus>[];
      final sub = controller.statusStream.listen(seen.add);
      addTearDown(sub.cancel);
      platform.emit(controller.playerId, {
        'state': 'playing',
        'positionMs': 1000,
        'durationMs': 5000,
      });
      platform.emit(controller.playerId, {'positionMs': 2000});
      platform.emit(controller.playerId, {'state': 'bogus'});
      platform.emit(controller.playerId, {});
      await pumpEventQueue();
      expect(seen, hasLength(4));
      expect(controller.status.state, NativePlaybackState.playing);
      expect(controller.status.position, const Duration(seconds: 2));
      expect(controller.duration, const Duration(seconds: 5));
    },
  );

  test('every playback state name is understood', () async {
    await controller.setUrl('https://x');
    for (final s in NativePlaybackState.values) {
      platform.emit(controller.playerId, {'state': s.name});
      await pumpEventQueue();
      expect(controller.status.state, s);
    }
  });

  test('events from a stream error do not break the subscription', () async {
    await controller.setUrl('https://x');
    platform.events[controller.playerId]!.addError(StateError('x'));
    platform.emit(controller.playerId, {'state': 'ready'});
    await pumpEventQueue();
    expect(controller.status.state, NativePlaybackState.ready);
  });

  test('transport controls forward with the player id', () async {
    final id = controller.playerId;
    await controller.play();
    await controller.pause();
    await controller.seek(const Duration(milliseconds: 1234));
    await controller.setSpeed(0.5);
    expect(platform.calls, [
      'play:$id',
      'pause:$id',
      'seek:$id:1234',
      'speed:$id:0.5',
    ]);
  });

  test(
    'setVolume updates the notifier immediately and calls the platform',
    () async {
      final seen = <double>[];
      controller.volume.addListener(() => seen.add(controller.volume.value));
      final f = controller.setVolume(0.25);
      expect(controller.volume.value, 0.25);
      await f;
      expect(seen, [0.25]);
      expect(platform.calls.last, 'volume:${controller.playerId}:0.25');
    },
  );

  test('setVolume reverts when the platform rejects it', () async {
    await controller.setVolume(0.5);
    platform.failVolume = StateError('nope');
    await controller.setVolume(0.9);
    expect(controller.volume.value, 0.5);
  });

  test(
    'dispose closes the status stream, notifier and native player',
    () async {
      await controller.setUrl('https://x');
      var done = false;
      controller.statusStream.listen((_) {}, onDone: () => done = true);
      await controller.dispose();
      disposed = true;
      await pumpEventQueue();
      expect(done, isTrue);
      expect(platform.calls.last, 'dispose:${controller.playerId}');
      expect(() => controller.volume.addListener(() {}), throwsFlutterError);
    },
  );

  test('dispose without ever loading is safe', () async {
    await controller.dispose();
    disposed = true;
    expect(platform.calls, ['dispose:${controller.playerId}']);
  });
}
