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
