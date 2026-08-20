// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of [generateNativeSplash] for one tenant — see its doc comment
/// for exactly what each field means and when it's populated.
///
/// Launcher icon generation used to live alongside this (as
/// `IconSplashResult`/`generateIconsAndSplash`) but has moved to its own
/// [LauncherIconGenerator]-style function, [generateLauncherIcon] — icons
/// are now auto-derived from a tenant's own `assets.icon`/`assets.logo` in
/// `white_label.yaml` (via `flutter_launcher_icons`), no separate
/// hand-authored config file needed. Splash still requires one, since
/// there is no equivalent tenant-declared "splash" field this generator
/// can safely default from without risking an unwanted, wrongly-colored
/// splash screen.
class NativeSplashResult {
  const NativeSplashResult({
    required this.ran,
    required this.launchScreenRegistered,
    this.error,
  });

  /// `true` if `flutter_native_splash-<tenant>.yaml` existed and
  /// `flutter_native_splash:create` ran successfully for this tenant.
  final bool ran;

  /// `true` if [ran] and a host-provided `tool/register_launch_screen.rb`
  /// script also ran successfully afterward to wire the generated iOS
  /// launch screen storyboard into the Xcode project. `false` whenever
  /// [ran] is `false`, and also `false` (not an error) if the host app
  /// simply has no such script — this package doesn't ship one, so its
  /// absence is expected on most consumers, not a failure.
  final bool launchScreenRegistered;

  /// Non-null only if `flutter_native_splash-<tenant>.yaml` existed but
  /// `flutter_native_splash:create` exited non-zero.
  final String? error;

  bool get hasError => error != null;
}

/// Runs `flutter_native_splash:create --flavor <tenantId>` for [tenantId]
/// — **only if** its own per-tenant config file
/// (`flutter_native_splash-<tenantId>.yaml`) already exists at
/// [projectRoot]. `flutter_native_splash` is not a dependency of this
/// package, and is not required: a tenant/consumer that hasn't created
/// this config file is assumed not to be using it, and is silently
/// skipped — never treated as an error, never forces a dependency a
/// consumer doesn't want. (Unlike [generateLauncherIcon], this can't be
/// auto-derived from a plain declared asset path — a splash screen also
/// needs a background color choice, which this package has no safe
/// tenant-declared default for.)
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
/// dev dependency of the host app) is reported via
/// [NativeSplashResult.error] instead of propagated, so one tenant's
/// optional splash step can never abort a `configure`/`add-tenant` run for
/// every other tenant. Callers should surface [NativeSplashResult.hasError]
/// as a warning, not fail the overall command on it.
NativeSplashResult generateNativeSplash(
  String tenantId, {
  required String projectRoot,
}) {
  final splashConfig = File(
    p.join(projectRoot, 'flutter_native_splash-$tenantId.yaml'),
  );
  if (!splashConfig.existsSync()) {
    return const NativeSplashResult(ran: false, launchScreenRegistered: false);
  }

  final ProcessResult result = Process.runSync('dart', [
    'run',
    'flutter_native_splash:create',
    '--flavor',
    tenantId,
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
      tenantId,
    ], workingDirectory: projectRoot);
    launchScreenRegistered = registerResult.exitCode == 0;
  }

  return NativeSplashResult(
    ran: true,
    launchScreenRegistered: launchScreenRegistered,
  );
}
