## 0.0.2-dev.0

* Added native (C++) Share via `IDataTransferManagerInterop`/
  `DataTransferManager`, and native audio/video playback + video embedding
  via Media Foundation's `IMFMediaEngine` (`windows/share_channel.cpp`,
  `windows/audio_channel.cpp`, `windows/video_channel.cpp`), wired to Dart
  through the same `MethodChannel`/`EventChannel` names as the Android and
  iOS implementations. **Not yet build-verified** — no Windows toolchain
  available in this environment; see the README "Status" section.
* Added `windows/CMakeLists.txt` and the plugin registrant
  (`attachment_engine_windows_plugin.h`/`.cpp`); `pubspec.yaml` now
  declares `pluginClass`/`cmakeFile` for Windows.

## 0.0.1-dev.1

* Initial development release: paths (`path_provider`) and open-externally
  (`url_launcher`) — both published by `flutter.dev`, the Flutter team's
  own verified publisher (not community/third-party plugins); download via
  `dart:io`'s built-in `HttpClient`.
* Share is not yet implemented — there is no standard OS command-line
  share mechanism, and no `flutter.dev`-published package covers it
  either; a real implementation needs native platform channel code
  (Windows `DataTransferManager`, no standard equivalent on Linux).
* PDF native rendering, embedded native video/audio playback, and embedded
  native webview surfaces are not yet implemented — `flutter.dev`'s own
  `video_player` does not support Windows/Linux either, so these still
  need a genuine native-view integration that has not been wired up yet.
