// ==============================================================================
// AUTO-ONBOARD — wired into tool/build_runner.dart's real build path
// (called unconditionally at the top of every build there) AND runnable
// standalone via `dart run white_label_kit:white_label auto-onboard <id>`.
//
// Zero-touch onboarding, as promised by docs/white_label_flavors.md but never
// actually implemented in the host app: if someone dropped
// `tenants/<id>/tenant.yaml` + `logo.png` (the documented "just add a
// folder" flow) without ever running `tenants/add_flavor.dart` by hand, this
// does it for them — chaining every step that currently has to be run by
// hand, in the right order:
//
//   1. tenants/add_flavor.dart          (config.json, VERSION, Android
//                                        flavor, iOS xcconfig, Firebase
//                                        placeholders)
//   2. tool/xcode_add_flavor.rb         (Xcode build configurations)
//   3. clone an existing .xcscheme      (only tenant-specific bit is the
//                                        buildConfiguration="...-<tenant>"
//                                        suffix — see _cloneXcodeScheme)
//   4. icons_launcher:create --flavor   (launcher + notification icons)
//   5. flutter_native_splash:create     (native launch screen)
//   6. tool/register_launch_screen.rb   (wires the storyboard from step 5
//                                        into the Xcode Resources build
//                                        phase — it exists on disk either
//                                        way, but silently never ships
//                                        without this)
//
// Still manual after this runs (can't be automated, see
// docs/white_label_flavors.md): real Firebase credentials (placeholders are
// written by add_flavor.dart) and signing/store listing.
// ==============================================================================

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'config/tenant_config.dart';
import 'generation/android_generator.dart';
import 'generation/ios_generator.dart';

typedef Logger = void Function(String message, [String level]);

void defaultLogger(String message, [String level = 'INFO']) {
  final prefix =
      {
        'INFO': '💡',
        'WARN': '⚠️',
        'ERROR': '❌',
        'SUCCESS': '✅',
        'STEP': '➜',
      }[level] ??
      '•';
  stdout.writeln('$prefix $message');
}

/// Runs the full onboarding chain for [tenantId] against [root] (the host
/// app's repo root). No-ops if `tenants/<tenantId>/config.json` already
/// exists — never re-runs or overwrites an already-onboarded tenant.
///
/// Returns `true` if onboarding ran (or was already done), `false` if it
/// failed partway (details already printed via [log]).
bool autoOnboardTenant(
  String tenantId, {
  required Directory root,
  Logger log = defaultLogger,
  bool dryRun = false,

  /// The existing tenant whose `.xcscheme` gets cloned as the template for
  /// [tenantId]'s new scheme. Defaults to `'Runner'`.
  String templateFlavor = 'Runner',
}) {
  final tenantDir = Directory('${root.path}/tenants/$tenantId');
  final configJson = File('${tenantDir.path}/config.json');
  final manifest = File('${tenantDir.path}/tenant.yaml');

  if (configJson.existsSync()) {
    log(
      "Tenant '$tenantId' already onboarded (config.json exists) — nothing to do.",
    );
    return true;
  }
  if (!manifest.existsSync()) {
    log(
      'No tenants/$tenantId/tenant.yaml found — nothing to auto-onboard.',
      'ERROR',
    );
    return false;
  }

  log(
    "New tenant '$tenantId' detected (tenant.yaml, no config.json yet) — auto-onboarding...",
    'STEP',
  );

  final doc = loadYaml(manifest.readAsStringSync()) as YamlMap;
  final displayName = doc['displayName']?.toString();
  final applicationId = doc['applicationId']?.toString();
  final apiBaseUrl = doc['apiBaseUrl']?.toString();
  // Optional — tenant.yaml is meant to be the one file a human edits, so a
  // tenant that isn't starting at 1.0.0+1 (e.g. migrating an existing app
  // into this pipeline) can say so here instead of hand-editing VERSION
  // after the fact.
  final version = doc['version']?.toString();
  if (displayName == null || applicationId == null) {
    log(
      "tenants/$tenantId/tenant.yaml is missing displayName/applicationId — can't auto-onboard.",
      'ERROR',
    );
    return false;
  }

  if (dryRun) {
    log(
      '(Dry run: would configure Android flavors, Xcode configs, clone scheme for $tenantId)',
    );
    return true;
  }

  final tenantConfig = TenantConfig(
    id: tenantId,
    name: displayName,
    android: AndroidTenantConfig(
      applicationId: applicationId,
      appName: displayName,
    ),
    ios: IosTenantConfig(bundleId: applicationId, appName: displayName),
    assets: TenantAssets(logo: 'tenants/$tenantId/logo.png'),
    environment: TenantEnvironment(apiBaseUrl: apiBaseUrl),
  );

  try {
    generateAndroidFlavor(tenantConfig, projectRoot: root.path);
    log("Configured Android Gradle flavor for '$tenantId'.");
  } catch (e) {
    log('Failed to configure Android Gradle flavor: $e', 'ERROR');
    return false;
  }

  try {
    generateIosConfig(tenantConfig, projectRoot: root.path);
    log("Configured iOS Xcode build configs for '$tenantId'.");
  } catch (e) {
    log('iOS Xcode generation skipped or failed: $e', 'WARN');
  }

  if (version != null) {
    final versionFile = File('${tenantDir.path}/VERSION');
    versionFile.writeAsStringSync('$version\n');
    log("Set tenants/$tenantId/VERSION to '$version' from tenant.yaml.");
  }

  _cloneXcodeScheme(tenantId, root, log, templateFlavor);

  final generatorSteps = <_Step>[
    _Step('dart', [
      'run',
      'icons_launcher:create',
      '--flavor',
      tenantId,
    ], "icons_launcher for '$tenantId'"),
    _Step('dart', [
      'run',
      'flutter_native_splash:create',
      '--flavor',
      tenantId,
    ], "flutter_native_splash for '$tenantId'"),
    _Step('ruby', [
      'tool/register_launch_screen.rb',
      tenantId,
    ], "register_launch_screen.rb for '$tenantId'"),
  ];

  for (final step in generatorSteps) {
    if (!_run(step, root, log)) return false;
  }

  log(
    "Auto-onboarded '$tenantId' end-to-end: config, Android flavor, iOS Xcode "
        'configs+scheme, icons, splash screen. Still manual: real Firebase '
        'credentials (placeholders written to tenants/$tenantId/firebase/) and '
        'signing/store listing.',
    'SUCCESS',
  );
  return true;
}

class _Step {
  const _Step(this.executable, this.args, this.label);
  final String executable;
  final List<String> args;
  final String label;
}

bool _run(_Step step, Directory root, Logger log) {
  log('Running ${step.label}...', 'STEP');
  final result = Process.runSync(
    step.executable,
    step.args,
    workingDirectory: root.path,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    log('Auto-onboarding failed at ${step.label}', 'ERROR');
    return false;
  }
  return true;
}

/// Clones an existing tenant's `.xcscheme` rather than hand-authoring XML:
/// the only tenant-specific bits are the five `buildConfiguration="...-
/// <tenant>"` attributes (BuildableReference/Blueprint fields all point at
/// the shared Runner target, identical across every tenant), so a straight
/// string substitution is correct and safe.
void _cloneXcodeScheme(
  String tenantId,
  Directory root,
  Logger log,
  String templateFlavor,
) {
  final schemesDir = Directory(
    '${root.path}/ios/Runner.xcodeproj/xcshareddata/xcschemes',
  );
  final dest = File('${schemesDir.path}/$tenantId.xcscheme');
  if (dest.existsSync()) return;

  final template = File('${schemesDir.path}/$templateFlavor.xcscheme');
  if (!template.existsSync()) {
    log(
      'No $templateFlavor.xcscheme template found — skipping scheme clone for $tenantId.',
      'WARN',
    );
    return;
  }

  dest.writeAsStringSync(
    template.readAsStringSync().replaceAll('-$templateFlavor', '-$tenantId'),
  );
  log("Cloned Xcode scheme for '$tenantId' from $templateFlavor.xcscheme.");
}
