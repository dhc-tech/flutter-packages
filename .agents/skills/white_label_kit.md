# Skill: white_label_kit Engineering

## Overview
`white_label_kit` is a build-time and runtime multi-tenant white-label solution for Flutter.

## Key Principles
- Single source of truth: `white_label.yaml` in project root.
- Pure Dart CLI runner: does not depend on `flutter` at build-time.
- Code generation: Emits `lib/white_label.g.dart` containing tenant constants and configuration.
- Native build config generation:
  - iOS: Xcode scheme & build configurations per tenant.
  - Android: `app/build.gradle` product flavors.
