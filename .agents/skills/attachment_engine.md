# Skill: attachment_engine

Federated engine to resolve, cache, download, preview and render attachments
(PDF, media, HTML, Office documents) on Android, iOS, macOS, Windows, Linux and web.

- `attachment_engine` holds the app-facing API, cache and widgets; it contains no
  platform transport code.
- `attachment_engine_platform_interface` defines the contract every
  `attachment_engine_<platform>` package implements.
- Platform interface changes need matching changes in each platform package.
- `attachment_engine_web` tests run with `--platform chrome`.
