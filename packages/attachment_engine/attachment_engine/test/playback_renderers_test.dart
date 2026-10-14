// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/widget_harness.dart';

class _Platform extends AttachmentEnginePlatform {
  final List<String> calls = [];
  final _controllers = <String, StreamController<Map<Object?, Object?>>>{};
  Object? failAudioLoad;
  Object? failVideoLoad;

  StreamController<Map<Object?, Object?>> _ctl(String key) =>
      _controllers.putIfAbsent(
        key,
        () => StreamController<Map<Object?, Object?>>.broadcast(),
      );

  void emitAudio(String id, Map<Object?, Object?> e) => _ctl('a$id').add(e);
  void emitVideo(String id, Map<Object?, Object?> e) => _ctl('v$id').add(e);

  String idOf(String prefix, [int nth = 0]) => calls
      .where((c) => c.startsWith('${prefix}Load:'))
      .elementAt(nth)
      .split(':')[1];

  int count(String prefix) => calls.where((c) => c.startsWith(prefix)).length;

  @override
  Stream<Map<Object?, Object?>> audioEvents(String id) => _ctl('a$id').stream;
  @override
  Stream<Map<Object?, Object?>> videoEvents(String id) => _ctl('v$id').stream;

  @override
  Future<void> audioLoad(String id, {String? filePath, String? url}) async {
    calls.add('audioLoad:$id:${filePath ?? url}');
    if (failAudioLoad != null) throw failAudioLoad!;
  }

  @override
  Future<void> videoLoad(String id, {String? filePath, String? url}) async {
    calls.add('videoLoad:$id:${filePath ?? url}');
    if (failVideoLoad != null) throw failVideoLoad!;
  }

  @override
  Future<void> audioPlay(String id) async => calls.add('audioPlay:$id');
  @override
  Future<void> audioPause(String id) async => calls.add('audioPause:$id');
  @override
  Future<void> audioSeek(String id, Duration p) async =>
      calls.add('audioSeek:$id:${p.inMilliseconds}');
  @override
  Future<void> audioSetVolume(String id, double v) async =>
      calls.add('audioVolume:$id:$v');
  @override
  Future<void> audioDispose(String id) async => calls.add('audioDispose:$id');
  @override
  Future<void> videoPlay(String id) async => calls.add('videoPlay:$id');
  @override
  Future<void> videoPause(String id) async => calls.add('videoPause:$id');
  @override
  Future<void> videoDispose(String id) async => calls.add('videoDispose:$id');
  @override
  Widget videoBuildView(String id) =>
      const SizedBox(key: Key('native_video_surface'));
}

Attachment _media(
  String id,
  AttachmentType type, {
  String? localPath,
  String? remoteUrl,
  String name = 'clip',
}) => Attachment(
  id: id,
  name: name,
  source: AttachmentSource.url('https://e.com/$id'),
  attachmentType: type,
  localPath: localPath,
  remoteUrl: remoteUrl,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Platform platform;
  var n = 0;
  String uid(String base) => '$base-${n++}';

  setUp(() {
    platform = _Platform();
    AttachmentEnginePlatform.instance = platform;
  });

  tearDown(() async {
    for (final c in platform._controllers.values) {
      await c.close();
    }
  });

  group('VideoControllerPool', () {
    test(
      'reuses one controller per key and disposes it on the last release',
      () async {
        final key = uid('pool');
        final a = VideoControllerPool.instance.acquire(key, url: 'https://x/v');
        final b = VideoControllerPool.instance.acquire(key, url: 'https://x/v');
        expect(identical(a, b), isTrue);
        expect(platform.count('videoLoad'), 1);
        VideoControllerPool.instance.release(key);
        await pumpEventQueue();
        expect(platform.count('videoDispose'), 0);
        VideoControllerPool.instance.release(key);
        await pumpEventQueue();
        expect(platform.count('videoDispose'), 1);
      },
    );

    test('a local file wins over the url, and releasing an unknown key is '
        'harmless', () async {
      final key = uid('pool');
      VideoControllerPool.instance.acquire(
        key,
        filePath: '/v.mp4',
        url: 'https://x/v',
      );
      expect(platform.calls.single, endsWith(':/v.mp4'));
      VideoControllerPool.instance.release('never-acquired');
      VideoControllerPool.instance.release(key);
    });
  });

  group('VideoAttachmentRenderer', () {
    const renderer = VideoAttachmentRenderer();

    Future<void> mount(
      WidgetTester tester,
      Attachment a, {
      TextDirection dir = TextDirection.ltr,
      Brightness brightness = Brightness.light,
    }) async {
      await tester.pumpWidget(
        harness(
          Builder(builder: (context) => renderer.build(context, a)),
          textDirection: dir,
          brightness: brightness,
        ),
      );
      await tester.pump();
    }

    test('type is video', () => expect(renderer.type, AttachmentType.video));

    testWidgets('loading: native surface plus a spinner', (tester) async {
      await mount(
        tester,
        _media(
          uid('v'),
          AttachmentType.video,
          remoteUrl: 'https://e.com/v.mp4',
        ),
      );
      expect(find.byKey(const Key('native_video_surface')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(platform.calls.single, endsWith(':https://e.com/v.mp4'));
    });

    testWidgets('a local file is preferred over the remote url', (
      tester,
    ) async {
      await mount(
        tester,
        _media(
          uid('v'),
          AttachmentType.video,
          localPath: '/v.mp4',
          remoteUrl: 'https://e.com/v.mp4',
        ),
      );
      expect(platform.calls.single, endsWith(':/v.mp4'));
    });

    testWidgets('buffering keeps the spinner', (tester) async {
      final a = _media(
        uid('v'),
        AttachmentType.video,
        remoteUrl: 'https://e.com/v',
      );
      await mount(tester, a);
      platform.emitVideo(platform.idOf('video'), {'state': 'buffering'});
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('ready shows the player with a working play/pause toggle and '
        'the reported aspect ratio', (tester) async {
      final a = _media(
        uid('v'),
        AttachmentType.video,
        remoteUrl: 'https://e.com/v',
      );
      await mount(tester, a);
      final id = platform.idOf('video');
      platform.emitVideo(id, {'state': 'ready', 'width': 400, 'height': 200});
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        2,
      );
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(platform.calls, contains('videoPlay:$id'));

      platform.emitVideo(id, {'state': 'playing'});
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      expect(platform.calls, contains('videoPause:$id'));
    });

    testWidgets('completed and paused states show the play button', (
      tester,
    ) async {
      final a = _media(
        uid('v'),
        AttachmentType.video,
        remoteUrl: 'https://e.com/v',
      );
      await mount(tester, a);
      final id = platform.idOf('video');
      for (final state in ['paused', 'completed']) {
        platform.emitVideo(id, {'state': state});
        await tester.pump();
        await tester.pump();
        expect(find.byIcon(Icons.play_arrow), findsOneWidget, reason: state);
      }
    });

    testWidgets('error shows the message and retry reloads the same source', (
      tester,
    ) async {
      final a = _media(uid('v'), AttachmentType.video, localPath: '/v.mp4');
      await mount(tester, a);
      final id = platform.idOf('video');
      platform.emitVideo(id, {'state': 'error'});
      await tester.pump();
      await tester.pump();
      expect(find.text('This video could not be played.'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(
        platform.calls.where((c) => c.startsWith('videoLoad')).last,
        'videoLoad:$id:/v.mp4',
      );
    });

    testWidgets('retry through the remote url when there is no local file', (
      tester,
    ) async {
      final a = _media(
        uid('v'),
        AttachmentType.video,
        remoteUrl: 'https://e.com/r',
      );
      await mount(tester, a);
      final id = platform.idOf('video');
      platform.emitVideo(id, {'state': 'error'});
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(platform.calls.last, 'videoLoad:$id:https://e.com/r');
    });

    testWidgets('a failing retry is swallowed', (tester) async {
      final a = _media(uid('v'), AttachmentType.video, localPath: '/v.mp4');
      await mount(tester, a);
      platform.emitVideo(platform.idOf('video'), {'state': 'error'});
      await tester.pump();
      await tester.pump();
      platform.failVideoLoad = StateError('still broken');
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('This video could not be played.'), findsOneWidget);
    });

    testWidgets('the pooled controller is disposed only after the last '
        'renderer unmounts', (tester) async {
      final a = _media(
        uid('v'),
        AttachmentType.video,
        remoteUrl: 'https://e.com/v',
      );
      final showSecond = ValueNotifier(true);
      await tester.pumpWidget(
        harness(
          Column(
            children: [
              Builder(builder: (c) => renderer.build(c, a)),
              ValueListenableBuilder<bool>(
                valueListenable: showSecond,
                builder: (c, v, _) => v
                    ? Builder(builder: (c) => renderer.build(c, a))
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(platform.count('videoLoad'), 1);
      showSecond.value = false;
      await tester.pump();
      expect(platform.count('videoDispose'), 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump();
      await pumpUntil(
        tester,
        () => platform.count('videoDispose') == 1,
        reason: 'pooled controller disposal',
      );
    });

    testWidgets('events after the renderer is gone are ignored', (
      tester,
    ) async {
      final a = _media(
        uid('v'),
        AttachmentType.video,
        remoteUrl: 'https://e.com/v',
      );
      await mount(tester, a);
      final id = platform.idOf('video');
      await tester.pumpWidget(const SizedBox());
      platform.emitVideo(id, {'state': 'ready'});
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in RTL and dark mode on a small screen', (
      tester,
    ) async {
      setScreenSize(tester, const Size(160, 160));
      await mount(
        tester,
        _media(uid('v'), AttachmentType.video, remoteUrl: 'https://e.com/v'),
        dir: TextDirection.rtl,
        brightness: Brightness.dark,
      );
      platform.emitVideo(platform.idOf('video'), {'state': 'ready'});
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('AudioPlayerPool', () {
    test('ref-counts a shared player and disposes it exactly once', () async {
      final key = uid('apool');
      final a = AudioPlayerPool.instance.acquire(key);
      final b = AudioPlayerPool.instance.acquire(key);
      expect(identical(a, b), isTrue);
      AudioPlayerPool.instance.release(key);
      await pumpEventQueue();
      expect(platform.count('audioDispose'), 0);
      AudioPlayerPool.instance.release(key);
      await pumpEventQueue();
      expect(platform.count('audioDispose'), 1);
      AudioPlayerPool.instance.release('never-acquired');
      final again = AudioPlayerPool.instance.acquire(key);
      expect(identical(a, again), isFalse);
      AudioPlayerPool.instance.release(key);
    });
  });

  group('AudioAttachmentRenderer', () {
    const renderer = AudioAttachmentRenderer();

    Future<void> mount(
      WidgetTester tester,
      Attachment a, {
      TextDirection dir = TextDirection.ltr,
      Brightness brightness = Brightness.light,
      double textScale = 1,
    }) async {
      await tester.pumpWidget(
        harness(
          Builder(builder: (context) => renderer.build(context, a)),
          textDirection: dir,
          brightness: brightness,
          textScale: textScale,
        ),
      );
      await tester.pump();
    }

    test('type is audio', () => expect(renderer.type, AttachmentType.audio));

    testWidgets('loads a local file in preference to the url', (tester) async {
      await mount(
        tester,
        _media(
          uid('a'),
          AttachmentType.audio,
          localPath: '/a.mp3',
          remoteUrl: 'https://e.com/a',
        ),
      );
      expect(platform.calls.single, endsWith(':/a.mp3'));
    });

    testWidgets('with neither a path nor a url nothing is loaded and the idle '
        'card renders', (tester) async {
      await mount(tester, _media(uid('a'), AttachmentType.audio, name: 'Note'));
      expect(platform.count('audioLoad'), 0);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('00:00'), findsNWidgets(2));
    });

    testWidgets('a failing initial load is swallowed', (tester) async {
      platform.failAudioLoad = StateError('nope');
      await mount(
        tester,
        _media(uid('a'), AttachmentType.audio, remoteUrl: 'https://e.com/a'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('play and pause toggle with the playback state', (
      tester,
    ) async {
      await mount(
        tester,
        _media(uid('a'), AttachmentType.audio, remoteUrl: 'https://e.com/a'),
      );
      final id = platform.idOf('audio');
      expect(find.byIcon(Icons.play_circle), findsOneWidget);
      expect(find.byIcon(Icons.music_off), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_circle));
      await tester.pump();
      expect(platform.calls, contains('audioPlay:$id'));

      platform.emitAudio(id, {
        'state': 'playing',
        'durationMs': 10000,
        'positionMs': 2000,
      });
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.pause_circle), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.text('00:02'), findsOneWidget);
      expect(find.text('00:10'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause_circle));
      await tester.pump();
      expect(platform.calls, contains('audioPause:$id'));
    });

    testWidgets('dragging the seek slider seeks within the duration', (
      tester,
    ) async {
      await mount(
        tester,
        _media(uid('a'), AttachmentType.audio, remoteUrl: 'https://e.com/a'),
      );
      final id = platform.idOf('audio');
      platform.emitAudio(id, {
        'state': 'paused',
        'durationMs': 10000,
        'positionMs': 0,
      });
      await tester.pump();
      await tester.pump();
      await tester.drag(find.byType(Slider).first, const Offset(100, 0));
      await tester.pump();
      final seeks = platform.calls
          .where((c) => c.startsWith('audioSeek:$id:'))
          .toList();
      expect(seeks, isNotEmpty);
      final last = int.parse(seeks.last.split(':').last);
      expect(last, inInclusiveRange(1, 10000));
    });

    testWidgets('a position past the end or an unknown duration does not '
        'break the slider', (tester) async {
      await mount(
        tester,
        _media(uid('a'), AttachmentType.audio, remoteUrl: 'https://e.com/a'),
      );
      final id = platform.idOf('audio');
      platform.emitAudio(id, {
        'state': 'playing',
        'durationMs': 1000,
        'positionMs': 99999,
      });
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.widget<Slider>(find.byType(Slider).first).value, 1000);
      platform.emitAudio(id, {'durationMs': 0, 'positionMs': 0});
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the volume slider updates optimistically and shows the muted '
        'icon at zero', (tester) async {
      await mount(
        tester,
        _media(uid('a'), AttachmentType.audio, remoteUrl: 'https://e.com/a'),
      );
      final id = platform.idOf('audio');
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      await tester.drag(find.byType(Slider).last, const Offset(-2000, 0));
      await tester.pump();
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      expect(
        platform.calls.where((c) => c.startsWith('audioVolume:$id:')),
        isNotEmpty,
      );
    });

    testWidgets('error shows the message; retry reloads the local file or '
        'the url', (tester) async {
      await mount(
        tester,
        _media(uid('a'), AttachmentType.audio, localPath: '/a.mp3'),
      );
      final id = platform.idOf('audio');
      platform.emitAudio(id, {'state': 'error'});
      await tester.pump();
      await tester.pump();
      expect(find.text('This audio could not be played.'), findsOneWidget);
      expect(find.byIcon(Icons.music_off_outlined), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(platform.calls.last, 'audioLoad:$id:/a.mp3');
    });

    testWidgets('retry for a url-only attachment, for none, and a failing '
        'retry', (tester) async {
      await mount(
        tester,
        _media(uid('a'), AttachmentType.audio, remoteUrl: 'https://e.com/r'),
      );
      final id = platform.idOf('audio');
      platform.emitAudio(id, {'state': 'error'});
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(platform.calls.last, 'audioLoad:$id:https://e.com/r');
      platform.failAudioLoad = StateError('still bad');
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long title is clamped to two lines; RTL and dark '
        'render on a small screen', (tester) async {
      setScreenSize(tester, const Size(320, 700));
      await mount(
        tester,
        _media(
          uid('a'),
          AttachmentType.audio,
          remoteUrl: 'https://e.com/a',
          name: 'title ' * 80,
        ),
        dir: TextDirection.rtl,
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      final title = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere((t) => (t.data ?? '').startsWith('title'));
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('unmounting releases the pooled player', (tester) async {
      await mount(
        tester,
        _media(uid('a'), AttachmentType.audio, remoteUrl: 'https://e.com/a'),
      );
      await tester.pumpWidget(const SizedBox());
      await pumpUntil(
        tester,
        () => platform.count('audioDispose') == 1,
        reason: 'pooled player disposal',
      );
    });
  });
}
