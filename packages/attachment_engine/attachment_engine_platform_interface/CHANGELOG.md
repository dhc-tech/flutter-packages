## 0.0.1-dev.0

* Initial release: the pure-Dart platform interface extracted from
  `attachment_engine` 0.1.0 as part of the federated-plugin split. Defines
  `AttachmentEnginePlatform`, the `PlatformInterface`-based contract that
  `attachment_engine_android` and `attachment_engine_ios` implement.
* Adds `pigeons/messages.dart`, the [pigeon](https://pub.dev/packages/pigeon)
  schema (dev-only codegen input) that now generates the type-safe
  Dart/Kotlin/Swift bindings (`lib/src/messages.g.dart` plus the native
  `Messages.g.kt`/`Messages.g.swift` in each platform package) backing every
  request/response native call, replacing hand-written `MethodChannel`
  string dispatch. The audio/video/download event streams are unaffected —
  they stay on hand-written `EventChannel`s (see the note at the top of
  `pigeons/messages.dart`).
