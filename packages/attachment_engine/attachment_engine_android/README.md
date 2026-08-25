# attachment_engine_android

The Android implementation of
[`attachment_engine`](https://pub.dev/packages/attachment_engine).

This package is endorsed by `attachment_engine` and you should not need to
depend on it directly — add `attachment_engine` to your `pubspec.yaml` and
this package is pulled in automatically for Android builds.

Every request/response native call (PDF, audio/video control, share,
open-externally, paths, download start/resume/cancel) is dispatched through
[pigeon](https://pub.dev/packages/pigeon)-generated `HostApi`s — see
`attachment_engine_platform_interface/pigeons/messages.dart` for the schema.
The audio/video/download event streams remain hand-written `EventChannel`s
(per-`playerId` dynamic channel names don't fit Pigeon's event-channel
model).
