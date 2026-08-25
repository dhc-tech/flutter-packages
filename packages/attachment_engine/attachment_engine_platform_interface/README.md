# attachment_engine_platform_interface

A common platform interface for the
[`attachment_engine`](https://pub.dev/packages/attachment_engine) plugin.

This package is the pure-Dart contract that platform implementations
(`attachment_engine_android`, `attachment_engine_ios`, and any future
implementation such as a web package) must conform to. Its API surface uses
only plain Dart/Flutter types — no `MethodChannel`, `EventChannel`, or other
transport-specific type appears in any signature — so a new platform can
satisfy it through whatever transport makes sense there (e.g.
`dart:js_interop` for web).

Users of `attachment_engine` should not need to depend on this package
directly; it exists to be depended on by platform-implementation packages.
