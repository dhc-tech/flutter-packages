# GitHub Copilot & AI Coding Agent Instructions

This document provides instructions for GitHub Copilot, Google Gemini, and AI coding assistants working in the `dhc-tech/flutter-packages` monorepo.

## 🏛️ Architecture Overview

- **`packages/white_label_kit`**: Multi-tenant white-label CLI and runtime engine for Flutter apps. Configures Android Gradle flavors and iOS Xcode build configurations.
- **`packages/dig_cli`**: Flutter developer CLI and code generation toolkit.
- **`packages/apple_sign_in_plugin`**: Cross-platform Apple Authentication plugin (iOS, macOS, Android, Web).

## 💎 Engineering Standards

1. **Zero Proprietary Data:** NEVER hardcode private credentials, API keys, or proprietary company/brand names. Use neutral identifiers (`com.example.acme`, `Acme App`).
2. **Strict Type Safety:** All code must pass `dart analyze --fatal-infos` / `flutter analyze --fatal-infos` with zero warnings and zero info lints.
3. **Pana Health Score:** Maintain 160/160 points on pub.dev for every package.
4. **Testing:** All new features or bug fixes must include unit/widget tests under `test/`.
5. **Formatting:** Follow official Dart format (`dart format .`).
