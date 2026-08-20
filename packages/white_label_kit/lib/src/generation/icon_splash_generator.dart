// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/tenant_config.dart';
import 'yaml_merge.dart';

/// Result of [generateNativeSplash] for one tenant — see its doc comment
/// for exactly what each field means and when it's populated.
class NativeSplashResult {
  const NativeSplashResult({
    required this.ran,
    required this.launchScreenRegistered,
    this.error,
    this.skippedReason,
  });

  /// `true` if `flutter_native_splash:create` ran successfully for this
  /// tenant.
  final bool ran;

  /// `true` if [ran] and a host-provided `tool/register_launch_screen.rb`
  /// script also ran successfully afterward to wire the generated iOS
  /// launch screen storyboard into the Xcode project. `false` whenever
  /// [ran] is `false`, and also `false` (not an error) if the host app
  /// simply has no such script — this package doesn't ship one, so its
  /// absence is expected on most consumers, not a failure.
  final bool launchScreenRegistered;

  /// Non-null only if an image source was found but
  /// `flutter_native_splash:create` exited non-zero.
  final String? error;

  /// Non-null only when [ran] is `false` and there was no [error] — i.e.
  /// the tenant simply has no image source on disk yet, not a failure.
  final String? skippedReason;

  bool get hasError => error != null;
}

/// Auto-generates `flutter_native_splash-<tenant.id>.yaml` from the
/// tenant's own declared config — [TenantConfig.assets]' `splash`, falling
/// back to `icon` then `logo` if no dedicated splash image was declared,
/// and [TenantConfig.theme]'s `splashColor` as the background color,
/// falling back to `primaryColor`, then white (`#ffffff`), if neither was
/// declared — and runs `flutter_native_splash:create --flavor <tenant.id>`
/// for it. Like [generateLauncherIcon], there is nothing else for a
/// consumer to set up: `white_label.yaml` alone is enough — including for
/// a tenant whose splash color needs to differ from its brand
/// `primaryColor` (declare `theme.splash_color` explicitly; see
/// [TenantTheme.splashColor]'s doc comment for why that's a separate
/// field, not just always `primaryColor`).
///
/// If the splash step ran and a `tool/register_launch_screen.rb` script
/// exists at [projectRoot] (a host-app-provided script — this package does
/// not ship one), it's run too: `flutter_native_splash:create` alone
/// writes the iOS launch screen storyboard to disk but does not register
/// it in the Xcode project's Resources build phase, so without this it
/// silently never ships.
///
/// The generated yaml file is overwritten every call — like
/// `lib/white_label.g.dart`, it's a build artifact of `white_label.yaml`,
/// never meant to be hand-edited. A tenant that wants a different splash
/// image than its icon/logo should declare `assets.splash` explicitly
/// rather than relying on the fallback.
///
/// A tenant can opt out entirely with `features: { native_splash: false }`
/// in `white_label.yaml` — e.g. one that already has its own hand-crafted
/// native splash setup and wants this package to leave it alone.
///
/// **Never throws.** No image source on disk yet is a silent skip
/// ([NativeSplashResult.skippedReason], not an error). A
/// `flutter_native_splash:create` run that fails to execute (e.g. the
/// package isn't actually resolved for the host app, or `--flavor` naming
/// conflicts with something in the project) is reported via
/// [NativeSplashResult.error] instead of propagated, so one tenant's
/// splash step can never abort a `configure`/`build` run for every other
/// tenant. Callers should surface [NativeSplashResult.hasError] as a
/// warning, not fail the overall command on it.
NativeSplashResult generateNativeSplash(
  TenantConfig tenant, {
  required String projectRoot,
}) {
  // Opt-out: `features: { native_splash: false }` in white_label.yaml for
  // this tenant. Since a usable image source always exists (assets.logo
  // is required), this is the only way to disable native splash
  // generation for a tenant that doesn't want it — e.g. a tenant that
  // already has its own hand-crafted native splash setup and wants this
  // package to leave it alone.
  if (tenant.features['native_splash'] == false) {
    return const NativeSplashResult(
      ran: false,
      launchScreenRegistered: false,
      skippedReason: 'disabled via features.native_splash: false',
    );
  }

  // TenantConfig.assets.logo is required (always present), so this can
  // never actually be null — splash, then icon, are preferred when
  // declared (a dedicated splash image usually looks better full-bleed
  // than a square icon, which in turn is usually cleaner than a wordmark
  // logo).
  final String imagePath =
      tenant.assets.splash ?? tenant.assets.icon ?? tenant.assets.logo;

  final imageFile = File(p.join(projectRoot, imagePath));
  if (!imageFile.existsSync()) {
    return NativeSplashResult(
      ran: false,
      launchScreenRegistered: false,
      skippedReason: 'declared splash/icon/logo "$imagePath" not found on disk',
    );
  }

  final String color =
      tenant.theme.splashColor ?? tenant.theme.primaryColor ?? '#ffffff';

  final Map<String, dynamic> baseConfig = {
    'color': color,
    'image': imagePath,
    'android_12': {'color': color, 'image': imagePath},
  };
  // Merge the tenant's raw `native_splash:` block (if declared) over the
  // auto-derived defaults above — see TenantConfig.nativeSplashOverrides'
  // doc comment. This is how every option the real `flutter_native_splash`
  // package supports (`color_dark`, `fullscreen`, `android_gravity`,
  // per-platform image/color overrides, …) stays reachable straight from
  // `white_label.yaml`.
  final Map<String, dynamic> config = deepMergeMaps(
    baseConfig,
    tenant.nativeSplashOverrides,
  );

  final configFile = File(
    p.join(projectRoot, 'flutter_native_splash-${tenant.id}.yaml'),
  );
  configFile.writeAsStringSync(
    '# GENERATED by white_label_kit — DO NOT EDIT BY HAND.\n'
    '# Derived from tenant "${tenant.id}"\'s assets.splash (or assets.icon'
    ' / assets.logo), theme.splashColor/primaryColor, and its'
    ' native_splash: block in white_label.yaml. To change this tenant\'s'
    ' splash image/color, update those in white_label.yaml and re-run'
    ' `configure`/`build`, not this file.\n'
    '${mapToYaml({'flutter_native_splash': config})}',
  );

  final ProcessResult result = Process.runSync('dart', [
    'run',
    'flutter_native_splash:create',
    '--flavor',
    tenant.id,
  ], workingDirectory: projectRoot);

  if (result.exitCode != 0) {
    return NativeSplashResult(
      ran: false,
      launchScreenRegistered: false,
      error:
          'flutter_native_splash:create exited ${result.exitCode}: '
                  '${result.stderr}'
              .trim(),
    );
  }

  var launchScreenRegistered = false;
  final registerScript = File(
    p.join(projectRoot, 'tool', 'register_launch_screen.rb'),
  );
  if (registerScript.existsSync()) {
    final ProcessResult registerResult = Process.runSync('ruby', [
      registerScript.path,
      tenant.id,
    ], workingDirectory: projectRoot);
    launchScreenRegistered = registerResult.exitCode == 0;
  }

  return NativeSplashResult(
    ran: true,
    launchScreenRegistered: launchScreenRegistered,
  );
}
