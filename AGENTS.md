# AGENTS.md

This document is the authoritative engineering standard for the `flutter-packages` monorepo.

All AI coding assistants (Antigravity, Gemini, Claude Code, Cursor, Copilot) must follow these rules.

## Core Engineering Rules

1. **Zero Proprietary Data:** Never hardcode private app IDs, customer company names, or sensitive tokens. Always use neutral placeholders (`com.example.acme`, `Acme App`).
2. **Pana Quality Score:** Every package in `packages/` must maintain maximum Pana points (160/160) on Pub.dev.
3. **Dual Flutter & Pure Dart Support:**
   - Pure Dart packages (`white_label_kit`, `dig_cli`) use `dart test` and `dart analyze`.
   - Flutter plugin packages (`apple_sign_in_plugin`) use `flutter test` and `flutter analyze`.
4. **Fatal Infos Enforcement:** Code must be free of all analysis warnings, lints, and fatal info issues (`--fatal-infos`).
5. **Atomic Versioning:** Each package maintains its own independent `pubspec.yaml` and `CHANGELOG.md`.
6. **Format Everything:** Every code change must be formatted with `melos run format:fix` (`dart format` under the hood) before commit.
7. **CHANGELOG Discipline:** Any user-facing change or bug fix in a package requires an entry in that package's `CHANGELOG.md`, alongside the version bump. In this repo that bump/changelog step is automated by Melos' conventional-commit release preparation (see `docs/release_architecture.md`), not by a manually-run `update-release-info` command as in upstream flutter/packages.

## Repository Overview

This is a monorepo containing 3 first-party packages, all in `packages/`:

- `white_label_kit` — pure Dart, multi-tenant/white-label configuration.
- `dig_cli` — pure Dart CLI tooling.
- `apple_sign_in_plugin` — a Flutter plugin (native iOS/Android/Web platform channels).

Unlike flutter/packages, none of these are **federated plugins** (no
separate `_platform_interface`/`_android`/`_ios` package split) and
there is no `third_party/packages/` directory — everything here is
first-party. The release/publish tooling is vendored under
`script/tool/` (a structural clone of flutter/packages' own
`script/tool`); see `docs/release_architecture.md` for how it's wired.

## Core Tooling and Workflows

Day-to-day development uses **Melos**, not `script/tool` directly —
`script/tool` (`dart ./script/tool/lib/src/main.dart publish ...`) is
reserved for the automated `release.yml` publish job. Local/PR-time
commands:

- **Bootstrap:** `melos bootstrap`
- **Format:** `melos run format:fix`
- **Analyze:** `melos run analyze` (`--fatal-infos`, zero warnings)
- **Test:** `melos run test`
- **Pana health check:** `melos run pana` (target: 160/160)

## Code Generators

`white_label_kit` uses `build_runner`. If you change a file that a
generator reads (e.g. anything feeding `.g.dart`/`.freezed.dart`
output), regenerate before committing:

```bash
dart run build_runner build -d
```

Generated output (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`) is
never hand-edited and never staged in commits — CI regenerates it
fresh. No package here uses Pigeon (no `pigeons/` directory) or
Mockito (no `mockito` dev-dependency), so those flutter/packages-
specific generator steps do not apply.

## Code Style

- **Dart**: standard Dart/Flutter style, formatted with `dart format`
  (via `melos run format:fix`). This repo is Dart/Flutter-only — the
  upstream per-language style list (C++/Java/Kotlin/Objective-C/Swift)
  does not apply since `apple_sign_in_plugin`'s native glue is thin
  platform-channel code, not a separately-styled implementation package.
- **Comments**: avoid redundant comments that restate what the code
  does; explain the *why* behind non-obvious logic, or serve as public
  API documentation.
