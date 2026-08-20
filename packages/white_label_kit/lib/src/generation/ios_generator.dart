// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/tenant_config.dart';

/// Generates the iOS Xcode wiring for one tenant against a standard
/// `flutter create`-generated iOS project (`<projectRoot>/ios/Runner.xcodeproj`
/// with a `Runner` target and a shared `Runner.xcscheme`).
///
/// Two things happen, both idempotent (safe to call again for the same
/// tenant — never duplicates a build configuration or scheme, and always
/// re-syncs the tenant's current [TenantConfig.ios] values into the existing
/// ones):
///
/// 1. **Xcode build configurations** — `Debug-<tenant>`/`Release-<tenant>`/
///    `Profile-<tenant>` are added to the project and to the `Runner`
///    target, each a duplicate of the corresponding base configuration with
///    `PRODUCT_BUNDLE_IDENTIFIER` set to [TenantConfig.ios]'s `bundleId` and
///    `APP_DISPLAY_NAME` set to [TenantConfig.ios]'s `appName` — a stock
///    `flutter create` project's `Info.plist` already reads
///    `CFBundleDisplayName`/`CFBundleName` from `$(APP_DISPLAY_NAME)`, so
///    setting this build setting is all a consuming app needs to do for the
///    home-screen app name to be correct per flavor (no `Info.plist` edit
///    required). Both settings are applied to the project root object and
///    the `Runner` target only — never to other native
///    targets. Every other native target (e.g. `RunnerTests`) just needs
///    matching configuration *names* to exist — no branding — so Xcode/`xcodebuild` never
///    see an inconsistent configuration set across
///    targets. This is a generic, from-scratch equivalent that edits `PRODUCT_BUNDLE_IDENTIFIER`/
///    `APP_DISPLAY_NAME` directly as build settings because a stock `flutter create` project
///    has no per-flavor `.xcconfig` scaffolding to point at).
///
///    Done via a small Ruby script (shipped here as a string, not a
///    checked-in `.rb` file, so this function stays self-contained and
///    doesn't depend on locating its own package's source tree on disk)
///    using the `xcodeproj` gem. There is no
///    battle-tested pure-Dart `.pbxproj` writer, so shelling out to the
///    Ruby ecosystem's own tool for this file format is the safe choice.
///
/// 2. **Xcode scheme** — `<tenant>.xcscheme` is (re)written from
///    `Runner.xcscheme`, replacing every `buildConfiguration="Debug"` /
///    `"Release"` / `"Profile"` attribute with the tenant-suffixed name from
///    step 1. `BuildableReference`/`Blueprint*` fields are untouched — they
///    still point at the one shared `Runner` target, same as every other
///    tenant's scheme.
///
/// Throws [IosGenerationException] if there is no
/// `<projectRoot>/ios/Runner.xcodeproj`, no `Runner` target inside it, no
/// `Runner.xcscheme` to clone, or the Ruby/`xcodeproj` step itself fails
/// (e.g. `ruby`/the gem isn't installed) — never leaves a partially-applied
/// scheme file behind in that last case, since the scheme is only written
/// after the pbxproj step has already succeeded.
void generateIosConfig(TenantConfig tenant, {required String projectRoot}) {
  final String xcodeprojPath = p.join(projectRoot, 'ios', 'Runner.xcodeproj');
  if (!Directory(xcodeprojPath).existsSync()) {
    throw IosGenerationException(
      'No ios/Runner.xcodeproj found under "$projectRoot". '
      'generateIosConfig only supports a standard `flutter create`-generated '
      'iOS project layout.',
    );
  }

  final schemesDir = Directory(
    p.join(xcodeprojPath, 'xcshareddata', 'xcschemes'),
  );
  final runnerScheme = File(p.join(schemesDir.path, 'Runner.xcscheme'));
  if (!runnerScheme.existsSync()) {
    throw IosGenerationException(
      'No Runner.xcscheme found under '
      '"${schemesDir.path}" — nothing to clone a tenant scheme from.',
    );
  }

  _runXcodeprojScript(tenant, xcodeprojPath);
  _cloneScheme(tenant.id, runnerScheme, schemesDir);
}

/// Removes the iOS Xcode wiring (build configurations and scheme) for [tenantId]
/// from `<projectRoot>/ios/Runner.xcodeproj`.
///
/// Idempotent: safe to call even if the configuration or scheme was already deleted.
void removeIosConfig(String tenantId, {required String projectRoot}) {
  final String xcodeprojPath = p.join(projectRoot, 'ios', 'Runner.xcodeproj');
  if (!Directory(xcodeprojPath).existsSync()) {
    return;
  }

  // 1. Delete scheme file if present.
  final schemeFile = File(
    p.join(xcodeprojPath, 'xcshareddata', 'xcschemes', '$tenantId.xcscheme'),
  );
  if (schemeFile.existsSync()) {
    try {
      schemeFile.deleteSync();
    } catch (_) {}
  }

  // 2. Remove Xcode build configurations via Ruby xcodeproj.
  final tempScript = File(
    p.join(
      Directory.systemTemp.path,
      'white_label_kit_ios_xcode_remove_'
      '${tenantId}_${DateTime.now().microsecondsSinceEpoch}.rb',
    ),
  );
  tempScript.writeAsStringSync(_xcodeprojRemoveRubyScript);
  try {
    Process.runSync('ruby', [tempScript.path, xcodeprojPath, tenantId]);
  } catch (_) {
    // Best-effort removal: if Ruby is unavailable, file removal above is sufficient.
  } finally {
    if (tempScript.existsSync()) {
      tempScript.deleteSync();
    }
  }
}

/// Thrown by [generateIosConfig] for any environment/project-shape problem
/// (missing Xcode project, missing `Runner` target, the Ruby `xcodeproj`
/// step failing) — always carries the underlying tool's stdout/stderr when
/// available so a failure is actionable, not a bare stack trace.
class IosGenerationException implements Exception {
  /// Creates an [IosGenerationException] with the given [message].
  IosGenerationException(this.message);

  /// Description of what went wrong, including tool output when available.
  final String message;

  @override
  String toString() => 'IosGenerationException: $message';
}

void _runXcodeprojScript(TenantConfig tenant, String xcodeprojPath) {
  final tempScript = File(
    p.join(
      Directory.systemTemp.path,
      'white_label_kit_ios_xcode_generate_'
      '${tenant.id}_${DateTime.now().microsecondsSinceEpoch}.rb',
    ),
  );
  tempScript.writeAsStringSync(_xcodeprojRubyScript);
  try {
    final ProcessResult result = Process.runSync('ruby', [
      tempScript.path,
      xcodeprojPath,
      tenant.id,
      tenant.ios.bundleId,
      tenant.ios.appName,
    ]);
    if (result.exitCode != 0) {
      throw IosGenerationException(
        'Xcode project generation failed for tenant "${tenant.id}" '
        '(ruby exit code ${result.exitCode}):\n'
        '${result.stdout}\n${result.stderr}',
      );
    }
  } on ProcessException catch (e) {
    throw IosGenerationException(
      'Could not run `ruby` to generate the Xcode configuration for tenant '
      '"${tenant.id}": $e\n'
      'Install Ruby and the `xcodeproj` gem (`gem install xcodeproj`) to use '
      'generateIosConfig.',
    );
  } finally {
    if (tempScript.existsSync()) {
      tempScript.deleteSync();
    }
  }
}

void _cloneScheme(String tenantId, File runnerScheme, Directory schemesDir) {
  String content = runnerScheme.readAsStringSync();
  for (final base in ['Debug', 'Release', 'Profile']) {
    content = content.replaceAll(
      'buildConfiguration = "$base"',
      'buildConfiguration = "$base-$tenantId"',
    );
  }
  final dest = File(p.join(schemesDir.path, '$tenantId.xcscheme'));
  // Deterministic full-overwrite, not append/patch: re-running for the same
  // tenant id always produces byte-identical output from the same
  // Runner.xcscheme, so this can never duplicate anything inside the file —
  // there is nothing to duplicate, only ever one <tenant>.xcscheme file on
  // disk per tenant.
  dest.writeAsStringSync(content);
}

/// A small, self-contained Ruby script using the `xcodeproj` gem
/// to add/sync per-tenant build configurations. Shipped as a string
/// (written to a temp file at call time) rather than a checked-in `.rb`
/// file so [generateIosConfig] doesn't need to locate its own package's
/// installed location on disk to find a sibling asset.
const String _xcodeprojRubyScript = r'''
require 'xcodeproj'

xcodeproj_path, tenant_id, bundle_id, app_name = ARGV
if [xcodeproj_path, tenant_id, bundle_id].any? { |a| a.nil? || a.empty? }
  abort 'Usage: ios_xcode_generate.rb <xcodeproj_path> <tenant_id> <bundle_id> [app_name]'
end

project = Xcodeproj::Project.open(xcodeproj_path)

runner_target = project.targets.find { |t| t.name == 'Runner' }
abort "Runner target not found in #{xcodeproj_path}" unless runner_target

# Finds (or creates) build configuration `new_name` in `config_list`, cloned
# from `base_name` the first time it's created. Always re-syncs
# PRODUCT_BUNDLE_IDENTIFIER/APP_DISPLAY_NAME (when given) on every call,
# whether the configuration is new or already existed — so re-running this
# script after a tenant's bundle id/app name changes actually applies the
# change instead of being a no-op past the first run. Never appends a
# second configuration with the same name: `build_configurations <<` only
# ever runs on the branch where none was found.
def sync_config(config_list, base_name, new_name, bundle_id, app_name = nil)
  config = config_list.build_configurations.find { |c| c.name == new_name }
  if config.nil?
    base = config_list.build_configurations.find { |c| c.name == base_name }
    return nil unless base

    config = config_list.project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
    config.name = new_name
    config.build_settings = base.build_settings.dup
    config_list.build_configurations << config
  end
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id if bundle_id
  # A stock `flutter create` Info.plist already reads CFBundleDisplayName/
  # CFBundleName from $(APP_DISPLAY_NAME) — setting this build setting is
  # enough for the home-screen app name to be correct per flavor, no
  # Info.plist edit needed. Without this, a tenant build shows "Runner" on
  # the home screen instead of its real brand name.
  config.build_settings['APP_DISPLAY_NAME'] = app_name if app_name && !app_name.empty?
  config
end

# Project + Runner target get the real branding (PRODUCT_BUNDLE_IDENTIFIER,
# APP_DISPLAY_NAME).
[project.root_object, runner_target].each do |scope|
  list = scope.build_configuration_list
  sync_config(list, 'Debug', "Debug-#{tenant_id}", bundle_id, app_name)
  sync_config(list, 'Release', "Release-#{tenant_id}", bundle_id, app_name)
  sync_config(list, 'Profile', "Profile-#{tenant_id}", bundle_id, app_name)
end

# Every other native target (e.g. RunnerTests) just needs matching
# configuration *names* to exist — no branding — so Xcode/xcodebuild never
# see an inconsistent configuration set across targets in the same project.
project.targets.each do |target|
  next if target == runner_target

  list = target.build_configuration_list
  next unless list

  %w[Debug Release Profile].each do |base_name|
    sync_config(list, base_name, "#{base_name}-#{tenant_id}", nil)
  end
end

project.save
puts "iOS Xcode config generated for tenant '#{tenant_id}' (bundle id #{bundle_id})."
''';

const String _xcodeprojRemoveRubyScript = r'''
require 'xcodeproj'

xcodeproj_path, tenant_id = ARGV
if [xcodeproj_path, tenant_id].any? { |a| a.nil? || a.empty? }
  abort 'Usage: ios_xcode_remove.rb <xcodeproj_path> <tenant_id>'
end

project = Xcodeproj::Project.open(xcodeproj_path)
config_names = ["Debug-#{tenant_id}", "Release-#{tenant_id}", "Profile-#{tenant_id}"]

([project.root_object] + project.targets).each do |scope|
  list = scope.build_configuration_list
  next unless list
  # `delete_if` unlinks from `build_configurations` in place (the list is a
  # live association, not a plain array — reassigning it via `-=` silently
  # doesn't stick). That alone still leaves the actual XCBuildConfiguration
  # object sitting in the project's objects table forever (dead weight the
  # .pbxproj never sheds on its own), so also call `remove_from_project` on
  # each one removed, so re-running add/remove/add for the same tenant id
  # doesn't accumulate orphaned objects over time.
  removed = []
  list.build_configurations.delete_if do |c|
    match = config_names.include?(c.name)
    removed << c if match
    match
  end
  removed.each(&:remove_from_project)
end

project.save
puts "iOS Xcode configs removed for tenant '#{tenant_id}'."
''';
