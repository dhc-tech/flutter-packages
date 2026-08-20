// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/tenant_config.dart';
import 'yaml_merge.dart';

/// Result of [generateLauncherIcon] for one tenant.
class LauncherIconResult {
  const LauncherIconResult({required this.ran, this.error, this.skippedReason});

  /// `true` if launcher + notification icons were actually (re)generated
  /// for this tenant.
  final bool ran;

  /// Non-null only if an icon source was found but `icons_launcher` exited
  /// non-zero (e.g. it isn't a dev dependency of the host app).
  final String? error;

  /// Non-null only when [ran] is `false` and there was no [error] — i.e.
  /// the tenant simply has no icon source on disk yet, not a failure.
  final String? skippedReason;

  bool get hasError => error != null;
}

/// Auto-generates `icons_launcher-<tenant.id>.yaml` from the tenant's own
/// declared assets — [TenantConfig.assets]' `icon`, falling back to `logo`
/// if no dedicated icon was declared — and runs
/// `icons_launcher:create --flavor <tenant.id>` for it. Unlike a
/// hand-authored per-tenant config file, there is nothing else for a
/// consumer to set up: declare `assets: {icon: ...}` (or just
/// `logo: ...`) in `white_label.yaml` and this generates real launcher AND
/// notification icons on the next `configure`/`build`.
///
/// `icons_launcher` (not `flutter_launcher_icons`) is used specifically
/// because it also generates the Android **notification** icon
/// (`notification_image`) per flavor — `flutter_launcher_icons` only
/// covers the launcher icon, which would silently stop the notification
/// icon from ever updating again for any tenant whose logo changes.
///
/// The generated yaml's iOS asset catalog is named `<tenant.id>AppIcon`
/// (`icons_launcher`'s own per-flavor convention — see its
/// `flavor_helper.dart`). [generateIosConfig] separately sets
/// `ASSETCATALOG_COMPILER_APPICON_NAME` to that same name as a literal
/// build setting, so the two stay in sync without either one depending on
/// the other's internals — see that function's doc comment for why a
/// literal build setting is used here instead of relying on
/// `icons_launcher` to wire it into a project with no per-flavor
/// `.xcconfig` `baseConfigurationReference` (this package's own iOS
/// generator doesn't use one).
///
/// The generated yaml file is overwritten every call — like
/// `lib/white_label.g.dart`, it's a build artifact of `white_label.yaml`,
/// never meant to be hand-edited.
///
/// A tenant can opt out entirely with `features: { launcher_icon: false }`
/// in `white_label.yaml` — e.g. one that already has its own hand-crafted
/// icons and wants this package to leave them alone.
///
/// **Never throws.** No icon/logo file on disk yet is a silent skip
/// ([LauncherIconResult.skippedReason], not an error) — most tenants won't
/// have real brand assets checked in from day one. An `icons_launcher` run
/// that fails to execute (e.g. not a dev dependency of the host app) is
/// reported via [LauncherIconResult.error] instead of propagated, so this
/// can never abort a `configure`/`build` run over every other tenant.
LauncherIconResult generateLauncherIcon(
  TenantConfig tenant, {
  required String projectRoot,
}) {
  // Opt-out: `features: { launcher_icon: false }` in white_label.yaml for
  // this tenant — e.g. a tenant that already has its own hand-crafted
  // launcher/notification icons and wants this package to leave them
  // alone. Since a usable image source always exists (assets.logo is
  // required), this is the only way to disable icon generation.
  if (tenant.features['launcher_icon'] == false) {
    return const LauncherIconResult(
      ran: false,
      skippedReason: 'disabled via features.launcher_icon: false',
    );
  }

  // TenantConfig.assets.logo is required (always present), so this can
  // never actually be null — icon is preferred when declared.
  final String iconPath = tenant.assets.icon ?? tenant.assets.logo;

  final iconFile = File(p.join(projectRoot, iconPath));
  if (!iconFile.existsSync()) {
    return LauncherIconResult(
      ran: false,
      skippedReason: 'declared icon/logo "$iconPath" not found on disk',
    );
  }

  final Map<String, dynamic> baseConfig = {
    'image_path': iconPath,
    'platforms': {
      'android': {'enable': true, 'notification_image': iconPath},
      'ios': {'enable': true, 'image_path': iconPath},
    },
  };
  // Merge the tenant's raw `icons_launcher:` block (if declared) over the
  // auto-derived defaults above — see TenantConfig.iconsLauncherOverrides'
  // doc comment. This is how every option the real `icons_launcher`
  // package supports (adaptive icon background/foreground, macOS/web/
  // windows targets, …) stays reachable straight from `white_label.yaml`.
  final Map<String, dynamic> config = deepMergeMaps(
    baseConfig,
    tenant.iconsLauncherOverrides,
  );

  final configFile = File(
    p.join(projectRoot, 'icons_launcher-${tenant.id}.yaml'),
  );
  configFile.writeAsStringSync(
    '# GENERATED by white_label_kit — DO NOT EDIT BY HAND.\n'
    '# Derived from tenant "${tenant.id}"\'s assets.icon (or assets.logo)'
    ' and its icons_launcher: block in white_label.yaml. To change this'
    ' tenant\'s launcher/notification icon, update those in'
    ' white_label.yaml and re-run `configure`/`build`, not this file.\n'
    '${mapToYaml({'icons_launcher': config})}',
  );

  final ProcessResult result = Process.runSync('dart', [
    'run',
    'icons_launcher:create',
    '--flavor',
    tenant.id,
  ], workingDirectory: projectRoot);

  if (result.exitCode == 0) {
    return const LauncherIconResult(ran: true);
  }
  return LauncherIconResult(
    ran: false,
    error:
        'icons_launcher:create exited ${result.exitCode}: '
                '${result.stderr}'
            .trim(),
  );
}
