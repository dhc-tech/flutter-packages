// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// Unified white-label build platform for Flutter apps.
///
/// Two layers live in this one package:
///
/// 1. **Generic CLI + config/isolation layer** (`bin/white_label.dart` +
///    this library's exports): a `white_label.yaml`-driven
///    [WhiteLabelConfig]/[TenantConfig] model with real validation
///    ([ConfigValidator]) and real build-time asset isolation
///    ([TenantStager]), plus the `init`/`add-tenant`/`update-tenant`/
///    `remove-tenant`/`configure`/`generate`/`build`/`run`/`doctor`/
///    `validate`/`list` commands — all repo-agnostic, usable from any
///    Flutter project. **This layer is generator/CLI-facing, not
///    app-runtime-facing** — an app's own runtime code should not
///    construct or depend on [WhiteLabelConfig]/[TenantConfig]/
///    [ConfigValidator]/[TenantStager] directly; see layer 2.
/// 2. **Public runtime API** ([WhiteLabelRuntime]): the one thing an app's
///    *own* runtime code (widgets, services, DI setup) should reach for to
///    answer "what tenant am I, what's my API URL, what's my theme color,
///    is feature X on" — without ever parsing `white_label.yaml` itself or
///    touching layer 1's generator internals. See [WhiteLabelRuntime]'s own
///    dartdoc for its two construction paths.
library;

export 'src/config/tenant_config.dart';
export 'src/config/white_label_config.dart';
export 'src/generation/android_generator.dart';
export 'src/generation/dart_config_generator.dart';
export 'src/generation/icon_splash_generator.dart';
export 'src/generation/ide_generator.dart';
export 'src/generation/ios_generator.dart';
export 'src/generation/tenant_stager.dart';
export 'src/interactive_menu.dart';
export 'src/runtime/white_label_runtime.dart';
export 'src/validation/config_validator.dart';
export 'src/validation/validation_result.dart';
