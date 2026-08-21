// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import '../config/tenant_config.dart';

/// **This is what an app's runtime code should reach for.**
///
/// A read-only, strongly-typed view of one tenant's *resolved* white-label
/// configuration — "what tenant am I, what's my API URL, what's my theme
/// color, is feature X on" — without the app ever needing to parse
/// `white_label.yaml` itself or touch this package's generator internals
/// ([TenantConfig], `WhiteLabelConfig`, `ConfigValidator`, `TenantStager`).
/// Those stay exported for CLI/build tooling, but an app's runtime code
/// should never construct or depend on them directly — construct a
/// [WhiteLabelRuntime] instead, one of two ways:
///
///  * [WhiteLabelRuntime.fromConfig] — build it from an already-parsed
///    [TenantConfig] (e.g. a dev tool or a custom build step that calls
///    `WhiteLabelConfig.load(...)` itself and resolves a tenant).
///  * The `build_runner`-generated `lib/white_label.g.dart`'s
///    `whiteLabelRuntimes` map / `whiteLabelDefaultRuntime` constant (see
///    `lib/builder.dart`) — fully resolved, compile-time
///    [WhiteLabelRuntime] instances requiring no parsing at all, for apps
///    that already run `build_runner` (the common case).
///
/// ### Why colors are hex strings, not `Color`
///
/// This package is pure Dart (no Flutter SDK dependency), by design — it's
/// also used from CLI tooling and `build_runner`, neither of which pulls in
/// Flutter. Because of that, [WhiteLabelTheme] exposes `#RRGGBB`/`#AARRGGBB`
/// hex strings (already validated by `ConfigValidator.colorHex` upstream,
/// during YAML parsing) rather than a `dart:ui`/`package:flutter` `Color`.
/// The consuming Flutter app parses the hex string into a `Color` itself,
/// e.g.:
///
/// ```dart
/// Color _fromHex(String hex) {
///   final v = hex.replaceFirst('#', '');
///   final argb = v.length == 6 ? 'FF$v' : v; // RRGGBB -> AARRGGBB
///   return Color(int.parse(argb, radix: 16));
/// }
/// ```
class WhiteLabelRuntime {
  /// Builds a [WhiteLabelRuntime] directly from its already-known, resolved
  /// fields. Prefer [WhiteLabelRuntime.fromConfig] when you have a
  /// [TenantConfig] on hand — this constructor exists mainly so
  /// `build_runner`'s generated `lib/white_label.g.dart` can emit
  /// `const WhiteLabelRuntime(...)` literals with no parsing at runtime.
  const WhiteLabelRuntime({
    required this.tenantId,
    required this.tenantName,
    required this.theme,
    required this.environment,
    required this.features,
    required this.android,
    required this.ios,
  });

  /// Builds a [WhiteLabelRuntime] from an already-parsed/validated
  /// [TenantConfig] — e.g. `WhiteLabelConfig.load(root).resolve()`. This is
  /// construction path (a): for apps/tools that load `white_label.yaml`
  /// themselves at build/dev time rather than relying on the
  /// `build_runner`-generated constants.
  ///
  /// [envName] selects a named entry from [TenantConfig.environments]
  /// (`staging`, `production`, ...) instead of [TenantConfig.environment] —
  /// see [TenantConfig.resolveEnvironment], which this delegates to
  /// (including its "throws if [envName] isn't declared" behavior, rather
  /// than silently falling back to the default environment).
  factory WhiteLabelRuntime.fromConfig(TenantConfig config, {String? envName}) {
    final TenantVersion androidVersion = config.androidVersion;
    final TenantVersion iosVersion = config.iosVersion;
    final TenantEnvironment resolvedEnvironment = config.resolveEnvironment(
      envName,
    );
    return WhiteLabelRuntime(
      tenantId: config.id,
      tenantName: config.name,
      theme: WhiteLabelTheme(
        primaryColorHex: config.theme.primaryColor,
        secondaryColorHex: config.theme.secondaryColor,
        brandColors: config.theme.brandColors,
        featureColors: config.theme.featureColors,
        sectionColors: config.theme.sectionColors,
        gradientColors: config.theme.gradientColors,
      ),
      environment: WhiteLabelEnvironment(
        apiBaseUrl: resolvedEnvironment.apiBaseUrl,
        custom: Map.unmodifiable(resolvedEnvironment.custom),
      ),
      features: Map.unmodifiable(config.features),
      android: WhiteLabelAndroidInfo(
        applicationId: config.android.applicationId,
        appName: config.android.appName,
        version: WhiteLabelVersion(
          name: androidVersion.name,
          buildNumber: androidVersion.buildNumber,
        ),
      ),
      ios: WhiteLabelIosInfo(
        bundleId: config.ios.bundleId,
        appName: config.ios.appName,
        version: WhiteLabelVersion(
          name: iosVersion.name,
          buildNumber: iosVersion.buildNumber,
        ),
      ),
    );
  }

  /// The tenant's directory/flavor id, e.g. `acme`. Same value as
  /// `TenantConfig.id` — this is "which tenant am I" for app code that
  /// branches on it (analytics tagging, support links, etc.).
  final String tenantId;

  /// Human-readable display name, e.g. "Acme Corp".
  final String tenantName;

  /// Brand colors for this tenant, as hex strings — see this class's
  /// dartdoc for why not `Color`.
  final WhiteLabelTheme theme;

  /// Non-secret runtime configuration (currently: API base URL).
  final WhiteLabelEnvironment environment;

  /// Arbitrary boolean feature toggles declared for this tenant. Prefer
  /// [isFeatureEnabled] over reading this map directly, so the
  /// missing-flag default stays in one documented place.
  final Map<String, bool> features;

  /// Android-specific identity/version info for this tenant.
  final WhiteLabelAndroidInfo android;

  /// iOS-specific identity/version info for this tenant.
  final WhiteLabelIosInfo ios;

  /// Whether feature [key] is enabled for this tenant.
  ///
  /// **Default for a missing key is `false`, not a thrown error.** A tenant
  /// simply not declaring a flag in `white_label.yaml` is the normal,
  /// expected shape of the config (see `TenantConfig.features` — flags are
  /// opt-in per tenant, not required), and a brand-new feature flag added
  /// to the codebase will not yet exist in any tenant's YAML at all. Both
  /// are "off", not "misconfigured" — throwing here would make rolling out
  /// a new flag a breaking change for every existing tenant config.
  bool isFeatureEnabled(String key) => features[key] ?? false;

  @override
  String toString() =>
      'WhiteLabelRuntime(tenantId: $tenantId, tenantName: $tenantName)';
}

/// Brand colors for a tenant, as `#RRGGBB`/`#AARRGGBB` hex strings — see
/// [WhiteLabelRuntime]'s dartdoc for why this package doesn't expose a
/// Flutter `Color` directly.
class WhiteLabelTheme {
  /// Builds a [WhiteLabelTheme] from its resolved hex-color fields.
  const WhiteLabelTheme({
    this.primaryColorHex,
    this.secondaryColorHex,
    this.brandColors = const {},
    this.featureColors = const {},
    this.sectionColors = const {},
    this.gradientColors = const {},
  });

  /// The tenant's primary brand color, as a hex string.
  final String? primaryColorHex;

  /// The tenant's secondary brand color, as a hex string.
  final String? secondaryColorHex;

  /// See `TenantTheme`'s dartdoc — four independent, arbitrarily-keyed
  /// hex-color maps for apps whose UI needs more than one primary/secondary
  /// pair.
  final Map<String, String> brandColors;

  /// Arbitrarily-keyed hex colors for feature-specific UI.
  final Map<String, String> featureColors;

  /// Arbitrarily-keyed hex colors for section-specific UI.
  final Map<String, String> sectionColors;

  /// Arbitrarily-keyed hex colors used in gradients.
  final Map<String, String> gradientColors;

  @override
  String toString() =>
      'WhiteLabelTheme(primaryColorHex: $primaryColorHex, '
      'secondaryColorHex: $secondaryColorHex, brandColors: $brandColors, '
      'featureColors: $featureColors, sectionColors: $sectionColors, '
      'gradientColors: $gradientColors)';
}

/// Non-secret runtime configuration for a tenant. See
/// `TenantEnvironment`'s dartdoc for why only non-secret values ever belong
/// here.
class WhiteLabelEnvironment {
  /// Builds a [WhiteLabelEnvironment] from its resolved fields.
  const WhiteLabelEnvironment({this.apiBaseUrl, this.custom = const {}});

  /// The tenant's API base URL, if configured.
  final String? apiBaseUrl;

  /// Resolved `custom:` string key-values for this environment — see
  /// [TenantEnvironment.custom].
  final Map<String, String> custom;

  @override
  String toString() =>
      'WhiteLabelEnvironment(apiBaseUrl: $apiBaseUrl, custom: $custom)';
}

/// A resolved `name+buildNumber` version pair — see `TenantVersion`.
class WhiteLabelVersion {
  /// Builds a [WhiteLabelVersion] from its resolved fields.
  const WhiteLabelVersion({required this.name, required this.buildNumber});

  /// Semantic version string, e.g. `"1.2.0"`.
  final String name;

  /// Monotonically-increasing build number.
  final int buildNumber;

  /// The combined `name+buildNumber` form, e.g. `"1.2.0+7"`.
  String get combined => '$name+$buildNumber';

  @override
  String toString() => 'WhiteLabelVersion($combined)';
}

/// Android-specific identity/version info for a tenant, resolved (platform
/// override already applied — see `TenantConfig.androidVersion`).
class WhiteLabelAndroidInfo {
  /// Builds a [WhiteLabelAndroidInfo] from its resolved fields.
  const WhiteLabelAndroidInfo({
    required this.applicationId,
    required this.appName,
    required this.version,
  });

  /// The Android application id, e.g. `com.acme.app`.
  final String applicationId;

  /// The Android-visible app display name.
  final String appName;

  /// The resolved Android app version.
  final WhiteLabelVersion version;

  @override
  String toString() =>
      'WhiteLabelAndroidInfo(applicationId: $applicationId, '
      'appName: $appName, version: $version)';
}

/// iOS-specific identity/version info for a tenant, resolved (platform
/// override already applied — see `TenantConfig.iosVersion`).
class WhiteLabelIosInfo {
  /// Builds a [WhiteLabelIosInfo] from its resolved fields.
  const WhiteLabelIosInfo({
    required this.bundleId,
    required this.appName,
    required this.version,
  });

  /// The iOS bundle id, e.g. `com.acme.app`.
  final String bundleId;

  /// The iOS-visible app display name.
  final String appName;

  /// The resolved iOS app version.
  final WhiteLabelVersion version;

  @override
  String toString() =>
      'WhiteLabelIosInfo(bundleId: $bundleId, appName: $appName, '
      'version: $version)';
}
