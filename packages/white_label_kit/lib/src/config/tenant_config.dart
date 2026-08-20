// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// Strongly-typed, immutable representation of one tenant's configuration —
/// the parsed/validated form of one entry under `white_label.tenants.*` in
/// `white_label.yaml`. Never constructed from partially-validated data:
/// [ConfigValidator] must accept the raw parse before a [TenantConfig] is
/// built from it (see `WhiteLabelConfig.parse`).
class TenantConfig {
  /// Creates a tenant config. See [ConfigValidator] and `WhiteLabelConfig.parse`.
  const TenantConfig({
    required this.id,
    required this.name,
    required this.android,
    required this.ios,
    required this.assets,
    this.version = const TenantVersion(name: '1.0.0', buildNumber: 1),
    this.theme = const TenantTheme(),
    this.environment = const TenantEnvironment(),
    this.features = const {},
    this.firebase,
    this.iconsLauncherOverrides = const {},
    this.nativeSplashOverrides = const {},
  });

  /// The tenant's directory/config key, e.g. `acme` — also used as the
  /// Flutter `--flavor` name and the isolated staging directory name, so it
  /// carries the same constraints as a Gradle product flavor name (see
  /// [ConfigValidator.tenantId]).
  final String id;

  /// Human-readable display name, e.g. "Acme Corp".
  final String name;

  /// Android-specific tenant configuration.
  final AndroidTenantConfig android;

  /// iOS-specific tenant configuration.
  final IosTenantConfig ios;

  /// This tenant's logo/icon/splash asset paths.
  final TenantAssets assets;

  /// The shared version used for both platforms unless [AndroidTenantConfig]
  /// or [IosTenantConfig] declares its own override — each tenant is a
  /// separate app store listing with its own independent release history,
  /// so its version is never derived from the shared Flutter codebase's own
  /// `pubspec.yaml` version. See [androidVersion]/[iosVersion] for the
  /// actually-resolved-per-platform value.
  final TenantVersion version;

  /// This tenant's color/theming overrides.
  final TenantTheme theme;

  /// This tenant's public runtime environment configuration.
  final TenantEnvironment environment;

  /// Arbitrary boolean feature toggles. Deliberately `bool`-only (not
  /// arbitrary JSON) — richer per-tenant runtime content belongs in
  /// [TenantEnvironment], not here; see README "What this does NOT do".
  final Map<String, bool> features;

  /// Optional per-tenant Firebase config file paths. Firebase is optional —
  /// a tenant that doesn't use it simply omits `firebase:` in
  /// `white_label.yaml` and this stays `null`. When set, both declared paths
  /// go through the exact same [ConfigValidator.assetPath] check as
  /// [assets] — there is no separate, weaker validation path for Firebase
  /// files (see `TenantStager.stage`).
  final TenantFirebaseConfig? firebase;

  /// Raw passthrough of this tenant's `icons_launcher:` block in
  /// `white_label.yaml`, if declared — merged over
  /// [generateLauncherIcon]'s own auto-derived defaults (`image_path`,
  /// `platforms.android.notification_image`, etc.) when writing
  /// `icons_launcher-<id>.yaml`, so every option the real
  /// `icons_launcher` package supports (adaptive icon background/
  /// foreground, per-platform enable/disable, macOS/web/windows targets,
  /// …) is reachable straight from `white_label.yaml` without this
  /// package needing to model each one individually. A key this map
  /// shares with the auto-derived defaults wins over the default; nested
  /// maps (e.g. `platforms.android`) are merged one level deep, not
  /// wholesale replaced. See <https://pub.dev/packages/icons_launcher> for
  /// the full option reference.
  final Map<String, dynamic> iconsLauncherOverrides;

  /// Raw passthrough of this tenant's `native_splash:` block in
  /// `white_label.yaml`, if declared — merged over
  /// [generateNativeSplash]'s own auto-derived defaults (`color`, `image`,
  /// `android_12`) the same way [iconsLauncherOverrides] merges over
  /// [generateLauncherIcon]'s, so every option the real
  /// `flutter_native_splash` package supports (`color_dark`, `fullscreen`,
  /// `android_gravity`, per-platform image/color overrides, …) is
  /// reachable straight from `white_label.yaml`. See
  /// <https://pub.dev/packages/flutter_native_splash> for the full option
  /// reference.
  final Map<String, dynamic> nativeSplashOverrides;

  /// The version to use for this tenant's Android build: [AndroidTenantConfig.version]
  /// if the tenant declared a platform-specific override, otherwise the
  /// shared [version]. A tenant whose Android and iOS release cadences have
  /// diverged (e.g. an iOS review delay) sets `android.version` /
  /// `ios.version` independently instead of forcing them to match.
  TenantVersion get androidVersion => android.version ?? version;

  /// The version to use for this tenant's iOS build — see [androidVersion].
  TenantVersion get iosVersion => ios.version ?? version;
}

/// Android-specific tenant configuration (application ID, app name, and an
/// optional Android-only version override).
class AndroidTenantConfig {
  /// Creates an Android tenant config.
  const AndroidTenantConfig({
    required this.applicationId,
    required this.appName,
    this.version,
  });

  /// Must be a valid Java package name — see [ConfigValidator.androidApplicationId].
  final String applicationId;

  /// The app's display name shown on the Android home screen.
  final String appName;

  /// Overrides [TenantConfig.version] for Android only, if set. Use
  /// [TenantConfig.androidVersion] to get the actually-resolved value —
  /// don't read this field directly unless you specifically need to know
  /// whether an override was declared.
  final TenantVersion? version;
}

/// iOS-specific tenant configuration (bundle ID, app name, and an optional
/// iOS-only version override).
class IosTenantConfig {
  /// Creates an iOS tenant config.
  const IosTenantConfig({
    required this.bundleId,
    required this.appName,
    this.version,
  });

  /// Must be a valid reverse-DNS bundle identifier — see [ConfigValidator.iosBundleId].
  final String bundleId;

  /// The app's display name shown on the iOS home screen.
  final String appName;

  /// Overrides [TenantConfig.version] for iOS only, if set. Use
  /// [TenantConfig.iosVersion] to get the actually-resolved value.
  final TenantVersion? version;
}

/// A tenant's version, independent of the shared Flutter codebase's own
/// `pubspec.yaml` version — each tenant is a separate store listing with its
/// own release history (see `AndroidTenantConfig.version`/`IosTenantConfig.version`
/// for per-platform overrides when Android and iOS releases diverge).
class TenantVersion {
  /// Creates a tenant version from a semantic version [name] and [buildNumber].
  const TenantVersion({required this.name, required this.buildNumber});

  /// Semantic version string, e.g. `"1.2.0"` — maps to Android's
  /// `versionName` / iOS's `CFBundleShortVersionString`. See
  /// [ConfigValidator.semanticVersion].
  final String name;

  /// Monotonically-increasing build number — maps to Android's
  /// `versionCode` / iOS's `CFBundleVersion`. Store rules require this to
  /// keep increasing across releases for a given tenant/platform; this
  /// package does not enforce that itself (it can't know a tenant's release
  /// history), only that it's a positive integer — see
  /// [ConfigValidator.buildNumber].
  final int buildNumber;

  /// The combined `name+buildNumber` form Flutter's `--build-name`/
  /// `--build-number` flags and `pubspec.yaml`'s `version:` field both use.
  String get combined => '$name+$buildNumber';
}

/// Paths are relative to the tenant's own directory (`tenants/<id>/`), never
/// absolute and never allowed to escape it — enforced by
/// [ConfigValidator.assetPath], not just convention.
class TenantAssets {
  /// Creates a tenant's asset paths.
  const TenantAssets({required this.logo, this.icon, this.splash});

  /// Path to the tenant's logo asset.
  final String logo;

  /// Path to the tenant's app icon asset, if provided.
  final String? icon;

  /// Path to the tenant's splash screen asset, if provided.
  final String? splash;

  /// All non-null asset paths declared for this tenant.
  Iterable<String> get all => [logo, ?icon, ?splash];
}

/// Optional per-tenant Firebase config files. Both paths are nullable
/// independently (a tenant might ship `google-services.json` for Android
/// without `GoogleService-Info.plist` for iOS, or neither at all — see
/// [TenantConfig.firebase]). Paths are relative to the tenant's own
/// directory (`tenants/<id>/`), exactly like [TenantAssets] — enforced by
/// the same [ConfigValidator.assetPath], not a separate/weaker rule.
class TenantFirebaseConfig {
  /// Creates a tenant's optional Firebase config file paths.
  const TenantFirebaseConfig({
    this.googleServicesJson,
    this.googleServiceInfoPlist,
  });

  /// Path to Android's `google-services.json`, if this tenant uses Firebase
  /// on Android.
  final String? googleServicesJson;

  /// Path to iOS's `GoogleService-Info.plist`, if this tenant uses Firebase
  /// on iOS.
  final String? googleServiceInfoPlist;

  /// All non-null Firebase config file paths declared for this tenant.
  Iterable<String> get all => [?googleServicesJson, ?googleServiceInfoPlist];
}

/// A tenant's color/theming overrides.
class TenantTheme {
  /// Creates a tenant's theme configuration.
  const TenantTheme({
    this.primaryColor,
    this.secondaryColor,
    this.splashColor,
    this.brandColors = const {},
    this.featureColors = const {},
    this.sectionColors = const {},
    this.gradientColors = const {},
  });

  /// `#RRGGBB` or `#AARRGGBB` — see [ConfigValidator.colorHex].
  final String? primaryColor;

  /// `#RRGGBB` or `#AARRGGBB` — see [ConfigValidator.colorHex]. The
  /// background color `generateNativeSplash` uses for this tenant's native
  /// splash screen, if different from [primaryColor]. A brand's `primary`
  /// color is often too vivid/saturated for a full-screen splash
  /// background (a real, previously-hit bug — a vivid primary color
  /// caused a jarring flash against a lighter custom Dart splash screen) —
  /// declare this separately rather than assuming [primaryColor] is always
  /// splash-appropriate. Falls back to [primaryColor], then white
  /// (`#ffffff`), if not declared.
  final String? splashColor;

  /// `#RRGGBB` or `#AARRGGBB` — see [ConfigValidator.colorHex].
  final String? secondaryColor;

  /// Four independent, arbitrarily-keyed hex-color maps for apps whose UI
  /// needs more than one primary/secondary pair — e.g. a set of named brand
  /// accents, per-feature-area colors, per-section colors, or gradient stop
  /// colors. Every value goes through the same [ConfigValidator.colorHex]
  /// check as [primaryColor]/[secondaryColor] — no separate/weaker
  /// validation path for these maps. Empty by default; a tenant that only
  /// needs primary/secondary declares nothing here.
  final Map<String, String> brandColors;

  /// Arbitrarily-keyed hex colors for per-feature-area theming.
  final Map<String, String> featureColors;

  /// Arbitrarily-keyed hex colors for per-section theming.
  final Map<String, String> sectionColors;

  /// Arbitrarily-keyed hex colors for gradient stops.
  final Map<String, String> gradientColors;
}

/// Public, non-secret runtime configuration only. Signing credentials,
/// private keys, and API secrets must never go here — see README's Security
/// section. This is baked into the built app and readable by anyone who
/// unzips the APK/IPA, same as any other Flutter asset.
class TenantEnvironment {
  /// Creates a tenant's public runtime environment configuration.
  const TenantEnvironment({this.apiBaseUrl});

  /// Must be a valid absolute URL — see [ConfigValidator.url].
  final String? apiBaseUrl;
}
