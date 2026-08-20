// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of [generateIconsAndSplash] for one tenant — see its doc comment
/// for exactly what each field means and when it's populated.
class IconSplashResult {
  const IconSplashResult({
    required this.iconsRan,
    required this.splashRan,
    required this.launchScreenRegistered,
    this.iconsError,
    this.splashError,
  });

  /// `true` if `icons_launcher-<tenant>.yaml` existed and
  /// `icons_launcher:create` ran successfully for this tenant.
  final bool iconsRan;

  /// `true` if `flutter_native_splash-<tenant>.yaml` existed and
  /// `flutter_native_splash:create` ran successfully for this tenant.
  final bool splashRan;

  /// `true` if [splashRan] and a host-provided
  /// `tool/register_launch_screen.rb` script also ran successfully
  /// afterward to wire the generated iOS launch screen storyboard into the
  /// Xcode project. `false` whenever [splashRan] is `false`, and also
  /// `false` (not an error) if the host app simply has no such script —
  /// this package doesn't ship one, so its absence is expected on most
  /// consumers, not a failure.
  final bool launchScreenRegistered;

  /// Non-null only if `icons_launcher-<tenant>.yaml` existed but
  /// `icons_launcher:create` exited non-zero (e.g. `icons_launcher` isn't a
  /// dev dependency of the host app, or the config file is malformed).
  final String? iconsError;

  /// Non-null only if `flutter_native_splash-<tenant>.yaml` existed but
  /// `flutter_native_splash:create` exited non-zero.
  final String? splashError;

  /// `true` if either step was attempted (its config file existed) and
  /// failed. Callers should treat this as a warning, not a hard failure —
  /// see [generateIconsAndSplash]'s doc comment on why.
  bool get hasError => iconsError != null || splashError != null;
}

/// Runs `icons_launcher:create --flavor <tenantId>` and
/// `flutter_native_splash:create --flavor <tenantId>` for [tenantId] —
/// **each one only if its own per-tenant config file already exists** at
/// [projectRoot] (`icons_launcher-<tenantId>.yaml` /
/// `flutter_native_splash-<tenantId>.yaml`). Neither `icons_launcher` nor
/// `flutter_native_splash` is a dependency of this package, and neither is
/// required: a tenant/consumer that hasn't created one of these config
/// files is assumed not to be using that generator, and is silently
/// skipped — never treated as an error, never forces a dependency a
/// consumer doesn't want.
///
/// If the splash step ran and a `tool/register_launch_screen.rb` script
/// exists at [projectRoot] (a host-app-provided script — this package does
/// not ship one), it's run too: `flutter_native_splash:create` alone
/// writes the iOS launch screen storyboard to disk but does not register
/// it in the Xcode project's Resources build phase, so without this it
/// silently never ships.
///
/// **Never throws.** A missing config file is a silent skip (not an
/// error); a command that fails to run (e.g. the package isn't actually a
/// dev dependency of the host app, so `dart run icons_launcher:create`
/// itself fails to resolve) is reported via [IconSplashResult]'s error
/// fields instead of propagated, so one tenant's optional icon/splash step
/// can never abort a `configure`/`add-tenant` run for every other tenant.
/// Callers should surface [IconSplashResult.hasError] as a warning, not
/// fail the overall command on it.
IconSplashResult generateIconsAndSplash(
  String tenantId, {
  required String projectRoot,
}) {
  bool iconsRan = false;
  bool splashRan = false;
  bool launchScreenRegistered = false;
  String? iconsError;
  String? splashError;

  final iconsConfig = File(
    p.join(projectRoot, 'icons_launcher-$tenantId.yaml'),
  );
  if (iconsConfig.existsSync()) {
    final ProcessResult result = Process.runSync('dart', [
      'run',
      'icons_launcher:create',
      '--flavor',
      tenantId,
    ], workingDirectory: projectRoot);
    if (result.exitCode == 0) {
      iconsRan = true;
    } else {
      iconsError =
          'icons_launcher:create exited ${result.exitCode}: '
                  '${result.stderr}'
              .trim();
    }
  }

  final splashConfig = File(
    p.join(projectRoot, 'flutter_native_splash-$tenantId.yaml'),
  );
  if (splashConfig.existsSync()) {
    final ProcessResult result = Process.runSync('dart', [
      'run',
      'flutter_native_splash:create',
      '--flavor',
      tenantId,
    ], workingDirectory: projectRoot);
    if (result.exitCode == 0) {
      splashRan = true;

      final registerScript = File(
        p.join(projectRoot, 'tool', 'register_launch_screen.rb'),
      );
      if (registerScript.existsSync()) {
        final ProcessResult registerResult = Process.runSync('ruby', [
          registerScript.path,
          tenantId,
        ], workingDirectory: projectRoot);
        launchScreenRegistered = registerResult.exitCode == 0;
      }
    } else {
      splashError =
          'flutter_native_splash:create exited ${result.exitCode}: '
                  '${result.stderr}'
              .trim();
    }
  }

  return IconSplashResult(
    iconsRan: iconsRan,
    splashRan: splashRan,
    launchScreenRegistered: launchScreenRegistered,
    iconsError: iconsError,
    splashError: splashError,
  );
}
