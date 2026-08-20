// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/tenant_config.dart';

/// Result of [maybeGenerateLauncherIcon]/[maybeGenerateNativeSplash] for one
/// tenant.
class IconSplashGenerateResult {
  const IconSplashGenerateResult({required this.ran, this.error});

  /// `true` if the underlying `icons_launcher:create` /
  /// `flutter_native_splash:create` command ran successfully.
  final bool ran;

  /// Non-null only if the command ran but exited non-zero.
  final String? error;

  bool get hasError => error != null;
}

/// Opt-in launcher/notification icon generation for [tenant] —
/// **only runs at all if `features: { icon_generate: true }` is declared**
/// for this tenant in `white_label.yaml`. Returns `null` (not a
/// [IconSplashGenerateResult]) when not opted in, so callers can tell "not
/// requested" apart from "requested and ran".
///
/// If opted in and `icons_launcher-<tenant.id>.yaml` does **not** already
/// exist, one is auto-created from the tenant's `assets.icon` (falling
/// back to `assets.logo`) so there's nothing to hand-author for a tenant
/// that just wants the default behavior. If the file already exists (hand
/// -authored or from a previous run), it is left exactly as-is — this
/// never overwrites a tenant's own icon config, unlike `configure`'s other
/// generated files.
///
/// **Never throws.** A command that fails to run (e.g. `icons_launcher`
/// isn't a dev dependency of the host app) is reported via
/// [IconSplashGenerateResult.error] instead of propagated.
IconSplashGenerateResult? maybeGenerateLauncherIcon(
  TenantConfig tenant, {
  required String projectRoot,
}) {
  if (tenant.features['icon_generate'] != true) return null;

  final configFile = File(
    p.join(projectRoot, 'icons_launcher-${tenant.id}.yaml'),
  );
  if (!configFile.existsSync()) {
    // TenantConfig.assets.logo is required (non-nullable) — the compiler
    // itself proves iconPath can never be null (and so never end up as the
    // literal string "null" here), not just convention.
    final String iconPath = tenant.assets.icon ?? tenant.assets.logo;
    configFile.writeAsStringSync('''
icons_launcher:
  image_path: "$iconPath"
  platforms:
    android:
      enable: true
      notification_image: "$iconPath"
    ios:
      enable: true
      image_path: "$iconPath"
''');
  }

  final ProcessResult result;
  try {
    result = Process.runSync('dart', [
      'run',
      'icons_launcher:create',
      '--flavor',
      tenant.id,
    ], workingDirectory: projectRoot);
  } on ProcessException catch (e) {
    return IconSplashGenerateResult(
      ran: false,
      error: 'Could not run `dart run icons_launcher:create`: $e',
    );
  }

  if (result.exitCode == 0) {
    return const IconSplashGenerateResult(ran: true);
  }
  return IconSplashGenerateResult(
    ran: false,
    error:
        'icons_launcher:create exited ${result.exitCode}: '
                '${result.stderr}'
            .trim(),
  );
}

/// Opt-in native splash screen generation for [tenant] — same contract as
/// [maybeGenerateLauncherIcon]: **only runs if
/// `features: { splash_generate: true }`** is declared, returns `null`
/// when not opted in, auto-creates `flutter_native_splash-<tenant.id>.yaml`
/// only if it doesn't already exist (never overwrites a hand-authored
/// one), and never throws (failures are reported via
/// [IconSplashGenerateResult.error]).
///
/// Unlike [maybeGenerateLauncherIcon]'s `icons_launcher` (a pure-Dart
/// package, safe as a real dependency of this one), `flutter_native_splash`
/// itself requires the Flutter SDK to resolve — depending on it directly
/// here would make this package impossible to `dart pub publish` (it would
/// force every consumer, including non-Flutter tooling contexts, through
/// Flutter-SDK-only resolution). So the host app must add
/// `flutter_native_splash` to its own `pubspec.yaml` for this to actually
/// run — `dart run flutter_native_splash:create` fails to resolve
/// otherwise, reported the same way as any other failure (via
/// [IconSplashGenerateResult.error]), not a special case. A native splash
/// screen is a Flutter-app concept in the first place, so this function is
/// only meaningful when [projectRoot] is a Flutter app — calling it from a
/// pure-Dart CLI/tooling context will just fail the same way (no `ios`/
/// `android` platform directories for `flutter_native_splash` to target),
/// not silently no-op.
///
/// The auto-created config uses `assets.splash` (falling back to
/// `assets.icon`, then `assets.logo`) as the image and
/// `theme.primary_color` (falling back to white, `#ffffff`) as the
/// background color.
IconSplashGenerateResult? maybeGenerateNativeSplash(
  TenantConfig tenant, {
  required String projectRoot,
}) {
  if (tenant.features['splash_generate'] != true) return null;

  final configFile = File(
    p.join(projectRoot, 'flutter_native_splash-${tenant.id}.yaml'),
  );
  if (!configFile.existsSync()) {
    // Same non-nullable-logo guarantee as maybeGenerateLauncherIcon — this
    // can never resolve to the literal string "null".
    final String imagePath =
        tenant.assets.splash ?? tenant.assets.icon ?? tenant.assets.logo;
    final String color = tenant.theme.primaryColor ?? '#ffffff';
    configFile.writeAsStringSync('''
flutter_native_splash:
  color: "$color"
  image: "$imagePath"
  android_12:
    color: "$color"
    image: "$imagePath"
''');
  }

  final ProcessResult result;
  try {
    result = Process.runSync('dart', [
      'run',
      'flutter_native_splash:create',
      '--flavor',
      tenant.id,
    ], workingDirectory: projectRoot);
  } on ProcessException catch (e) {
    return IconSplashGenerateResult(
      ran: false,
      error: 'Could not run `dart run flutter_native_splash:create`: $e',
    );
  }

  if (result.exitCode == 0) {
    return const IconSplashGenerateResult(ran: true);
  }
  return IconSplashGenerateResult(
    ran: false,
    error:
        'flutter_native_splash:create exited ${result.exitCode}: '
                '${result.stderr}\n'
                'Hint: run `flutter pub add flutter_native_splash` in your '
                'app first — it is not a dependency of white_label_kit.'
            .trim(),
  );
}
