/// Unified white-label build platform for Flutter apps.
///
/// Three layers live in this one package (deliberately not split into
/// separate packages — see README "Why one package, not two"):
///
/// 1. **Host-app CLI** (`bin/white_label.dart`): thin dispatcher over
///    `tenants/add_flavor.dart`, `tool/tenant_doctor.dart`,
///    `tool/build_runner.dart` in this repo specifically. Not generic yet.
/// 2. **Generic config/isolation layer** (this library's exports): a
///    `white_label.yaml`-driven [WhiteLabelConfig]/[TenantConfig] model with
///    real validation ([ConfigValidator]) and real build-time asset
///    isolation ([TenantStager]) that has no dependency on this repo's
///    folder names — usable from any Flutter project. This is the part
///    intended to generalize into a public pub.dev release; see README's
///    "Remaining work before v1.0.0". **This layer is generator/CLI-facing,
///    not app-runtime-facing** — an app's own runtime code should not
///    construct or depend on [WhiteLabelConfig]/[TenantConfig]/
///    [ConfigValidator]/[TenantStager] directly; see layer 3.
/// 3. **Public runtime API** ([WhiteLabelRuntime]): the one thing an app's
///    *own* runtime code (widgets, services, DI setup) should reach for to
///    answer "what tenant am I, what's my API URL, what's my theme color,
///    is feature X on" — without ever parsing `white_label.yaml` itself or
///    touching layer 2's generator internals. See [WhiteLabelRuntime]'s own
///    dartdoc for its two construction paths.
///
/// [autoOnboardTenant] chains every manual onboarding step for *this* repo's
/// tenants (add_flavor, Xcode wiring, scheme clone, icons, splash) — wired
/// into `tool/build_runner.dart`'s actual build path, and also runnable
/// standalone via `dart run white_label_kit:white_label auto-onboard <id>`.
library;

export 'src/auto_onboard.dart' show autoOnboardTenant, defaultLogger;
export 'src/config/tenant_config.dart';
export 'src/config/white_label_config.dart';
export 'src/generation/android_generator.dart';
export 'src/generation/dart_config_generator.dart';
export 'src/generation/ide_generator.dart';
export 'src/generation/ios_generator.dart';
export 'src/generation/tenant_stager.dart';
export 'src/interactive_menu.dart';
export 'src/runtime/white_label_runtime.dart';
export 'src/validation/config_validator.dart';
export 'src/validation/validation_result.dart';
