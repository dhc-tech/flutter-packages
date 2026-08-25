# attachment_engine_ios

The iOS implementation of
[`attachment_engine`](https://pub.dev/packages/attachment_engine).

This package is endorsed by `attachment_engine` and you should not need to
depend on it directly — add `attachment_engine` to your `pubspec.yaml` and
this package is pulled in automatically for iOS builds.

Every request/response native call (PDF, audio/video control, share,
open-externally, office preview, paths, download start/resume/cancel) is
dispatched through [pigeon](https://pub.dev/packages/pigeon)-generated
`HostApi` protocols — see
`attachment_engine_platform_interface/pigeons/messages.dart` for the
schema. The audio/video/download event streams remain hand-written
`FlutterEventChannel`s (per-`playerId` dynamic channel names don't fit
Pigeon's event-channel model).

## Office document preview (QuickLook)

Office documents (doc/docx/xls/xlsx/ppt/pptx/rtf/...) get a genuine in-app
preview on iOS via `QLPreviewController` from Apple's QuickLook framework —
a system framework, so this adds zero third-party dependency. `OfficePreviewChannel`
(`ios/attachment_engine/Sources/attachment_engine/OfficePreviewChannel.swift`)
presents it modally from the root Flutter view controller, mirroring the
modal-presentation pattern already used by `ShareChannel`
(`UIActivityViewController`) and `OpenChannel`
(`UIDocumentInteractionController`).

QuickLook requires a local file URL — it cannot preview a remote URL or
in-memory bytes directly. `AttachmentResolver` in the app-facing package
guarantees a local path is available before `OfficeAttachmentRenderer`
invokes this channel, so this is not a caller-visible constraint.

This is intentionally asymmetric with Android, which has no equivalent
in-app Office viewer and falls back to external-open
(`Intent.ACTION_VIEW` + `FileProvider`) — see
`packages/attachment_engine/README.md` for the full rationale.
