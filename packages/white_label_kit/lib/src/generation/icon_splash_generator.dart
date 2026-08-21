// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
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
/// The auto-created config also declares an **adaptive icon** (Android
/// 8.0+/API 26 — see
/// https://developer.android.com/develop/ui/views/launch/icon_design_adaptive),
/// not just the legacy flat `mipmap/ic_launcher.png`: `adaptive_foreground_
/// image` reuses the same icon asset, and `adaptive_background_color`
/// uses the tenant's `theme.primary_color` (falling back to white). This
/// is a reasonable automatic default, not a substitute for a real,
/// properly-padded (transparent background, ~66% safe zone) foreground
/// asset — a tenant that wants a polished adaptive icon should still
/// hand-author `icons_launcher-<id>.yaml`'s `adaptive_foreground_image`
/// with a dedicated asset (see the "Manual" path in README §5).
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
    final String backgroundColor = tenant.theme.primaryColor ?? '#ffffff';
    configFile.writeAsStringSync('''
icons_launcher:
  image_path: "$iconPath"
  platforms:
    android:
      enable: true
      notification_image: "$iconPath"
      adaptive_background_color: "$backgroundColor"
      adaptive_foreground_image: "$iconPath"
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
///
/// `flutter_native_splash:create` only writes the generated
/// `LaunchScreen<Tenant>.storyboard` file to disk — it does **not** add it
/// to `Runner.xcodeproj`'s Resources build phase, so it silently never
/// ships in the app bundle unless something registers it there too. This
/// function does that registration itself right after a successful
/// `--ios`-capable run, via the same `xcodeproj` gem used by
/// [generateIosConfig]. Best-effort and never fatal: if no
/// `ios/Runner/Base.lproj/LaunchScreen<tenant.id>.storyboard` is found (no
/// iOS platform, or splash targeted Android only) or `ruby`/`xcodeproj`
/// isn't available, the splash generation itself still reports success —
/// only a warning is appended to [IconSplashGenerateResult.error] path via
/// a non-fatal side note, matching [generateIosConfig]'s "best effort,
/// never fatal" stance on Ruby unavailability.
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

  if (result.exitCode != 0) {
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

  final String? registerError = registerLaunchScreenStoryboard(
    tenant.id,
    projectRoot: projectRoot,
  );
  if (registerError != null) {
    // The generate step itself succeeded — only surface the registration
    // problem as a non-fatal warning, don't turn `ran: true` into a
    // reported failure over it.
    return IconSplashGenerateResult(ran: true, error: registerError);
  }
  return const IconSplashGenerateResult(ran: true);
}

/// Registers `ios/Runner/Base.lproj/LaunchScreen<tenantId>.storyboard`
/// (case-insensitive match against what `flutter_native_splash` actually
/// wrote) in `Runner.xcodeproj`'s Resources build phase, if not already
/// registered. Returns `null` on success or when there's nothing to do (no
/// iOS storyboard for this tenant — e.g. splash targeted Android only);
/// returns a human-readable warning string otherwise. Never throws.
///
/// Exposed with [visibleForTesting] so the registration step can be
/// exercised directly against a fixture Xcode project, the same way
/// `ios_generator_test.dart` exercises `generateIosConfig`'s Ruby step —
/// [maybeGenerateNativeSplash] itself can't be driven end-to-end in tests
/// without a real `flutter_native_splash` dependency to shell out to.
@visibleForTesting
String? registerLaunchScreenStoryboard(
  String tenantId, {
  required String projectRoot,
}) {
  final xcodeprojPath = p.join(projectRoot, 'ios', 'Runner.xcodeproj');
  if (!Directory(xcodeprojPath).existsSync()) return null;

  final lprojDir = Directory(
    p.join(projectRoot, 'ios', 'Runner', 'Base.lproj'),
  );
  if (!lprojDir.existsSync()) return null;

  final String wantedName = 'launchscreen${tenantId.toLowerCase()}.storyboard';
  File? match;
  for (final entity in lprojDir.listSync()) {
    if (entity is File && p.basename(entity.path).toLowerCase() == wantedName) {
      match = entity;
      break;
    }
  }
  if (match == null) return null;

  final storyboardRelPath = 'Base.lproj/${p.basename(match.path)}';
  final tempScript = File(
    p.join(
      Directory.systemTemp.path,
      'white_label_kit_register_launch_screen_'
      '${tenantId}_${DateTime.now().microsecondsSinceEpoch}.rb',
    ),
  );
  tempScript.writeAsStringSync(_registerLaunchScreenRubyScript);
  try {
    final result = Process.runSync('ruby', [
      tempScript.path,
      xcodeprojPath,
      storyboardRelPath,
    ]);
    if (result.exitCode != 0) {
      return 'Generated $storyboardRelPath but could not register it in '
          "Runner.xcodeproj's Resources build phase (ruby exit code "
          '${result.exitCode}): ${result.stdout}\n${result.stderr}';
    }
    return null;
  } on ProcessException catch (e) {
    return 'Generated $storyboardRelPath but could not run `ruby` to '
        "register it in Runner.xcodeproj's Resources build phase: $e\n"
        'Install Ruby and the `xcodeproj` gem (`gem install xcodeproj`), or '
        'register it manually, before the app bundle will include the '
        'splash screen for this tenant.';
  } finally {
    if (tempScript.existsSync()) {
      tempScript.deleteSync();
    }
  }
}

/// A small, self-contained Ruby script using the `xcodeproj` gem to add one
/// storyboard file reference to `Runner`'s Resources build phase, if it
/// isn't already there. Shipped as a string (written to a temp file at call
/// time), same rationale as [_xcodeprojRubyScript] in `ios_generator.dart`.
/// Idempotent: skips if the file reference is already registered.
const String _registerLaunchScreenRubyScript = r'''
require 'xcodeproj'

xcodeproj_path, storyboard_rel_path = ARGV
if [xcodeproj_path, storyboard_rel_path].any? { |a| a.nil? || a.empty? }
  abort 'Usage: register_launch_screen.rb <xcodeproj_path> <storyboard_rel_path>'
end

project = Xcodeproj::Project.open(xcodeproj_path)
# Found by product type, not the literal name "Runner" — see the matching
# comment in ios_generator.dart's _xcodeprojRubyScript for why.
runner_target = project.targets.find { |t| t.product_type == 'com.apple.product-type.application' } ||
                project.targets.find { |t| t.name == 'Runner' }
abort "No application target found in #{xcodeproj_path}" unless runner_target

existing_file_ref = project.files.find { |f| f.path.to_s == storyboard_rel_path }
already_in_resources = existing_file_ref != nil &&
  runner_target.resources_build_phase.files.any? { |bf| bf.file_ref == existing_file_ref }
unless already_in_resources
  # The main group is conventionally named after the target — falls back
  # to the project's own main group if a consumer renamed the group
  # independently of the target (rare, but never worse than before).
  runner_group = project.main_group[runner_target.name] || project.main_group
  file_ref = existing_file_ref || runner_group.new_file(storyboard_rel_path)
  runner_target.resources_build_phase.add_file_reference(file_ref)
  project.save
end
''';
