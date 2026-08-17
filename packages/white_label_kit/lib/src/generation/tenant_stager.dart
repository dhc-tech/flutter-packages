import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/tenant_config.dart';
import '../validation/config_validator.dart';
import '../validation/validation_result.dart';

/// Build-time tenant isolation: copies ONLY the selected tenant's declared
/// files into a deterministic staging directory
/// (`<projectRoot>/.generated/<tenantId>/...`) — never the whole `tenants/`
/// tree, never another tenant's files. Two independent groups of declared
/// files are staged this way, each into its own subdirectory: the required
/// [TenantConfig.assets] (`assets/`) and the optional
/// [TenantConfig.firebase] config files (`firebase/`), if the tenant
/// declared any.
///
/// This is the actual isolation mechanism (not a runtime `if`/asset-manifest
/// trick): whatever consumes the staging directory afterwards (icon
/// generators, `flutter build`'s asset bundling, Firebase's own config
/// loading, etc.) can only ever see one tenant's files on disk at a time.
///
/// Three properties [stage] guarantees for every staged group — each one
/// found broken by an adversarial audit before being fixed here, kept as
/// explicit contracts so a future change can't silently regress them. There
/// is deliberately only one code path that provides these guarantees
/// ([_StageGroup] + the loop in [stage]) — Firebase files go through the
/// exact same validate/collision/atomic-swap logic as assets, not a second,
/// weaker copy of it:
///
/// 1. **Path safety is enforced here too, not just at parse time.**
///    [TenantConfig] has a public constructor — nothing stops a caller
///    (including this package's own `example/` scripts) from building one
///    directly instead of going through [ConfigValidator]/`WhiteLabelConfig`.
///    `stage()` re-validates every declared path itself (assets AND
///    Firebase files), so it is safe to call on any [TenantConfig]
///    regardless of how it was constructed. Relying solely on the parser was
///    the bug: it made "paths can't escape the tenant directory" true only
///    for configs loaded from YAML, not true of the library.
/// 2. **Atomic**: staging happens in a sibling temp directory and is moved
///    into place only after every declared file (across all groups) has
///    been confirmed to exist and copied successfully. A failure partway
///    through never touches the previous, last-known-good staged output —
///    the old bug was deleting the old output *before* confirming the new
///    one would succeed, which could leave a half-written,
///    silently-incomplete result if a later file was missing.
/// 3. **No silent basename collisions**: two declared files in the same
///    group (e.g. `logo` and `icon`, or the two Firebase files) that would
///    resolve to the same destination filename is a hard error, not a
///    silent overwrite — this used to lose one of the two files with no
///    warning and exit code 0.
class TenantStager {
  TenantStager(this.projectRoot);

  final String projectRoot;

  String stagingDirFor(String tenantId) =>
      p.join(projectRoot, '.generated', tenantId);

  /// Stages [tenant]. See the class doc for the atomicity/path-safety/
  /// collision guarantees — they apply identically to
  /// [TenantConfig.assets] and, when the tenant declares one,
  /// [TenantConfig.firebase]. Returns the absolute path to the staged
  /// `assets/` directory. Throws [StateError] (validation failure, missing
  /// file, or basename collision) without touching any previously-staged
  /// output for this tenant.
  String stage(TenantConfig tenant) {
    final groups = <_StageGroup>[
      _StageGroup('assets', tenant.assets.all.toList()),
      if (tenant.firebase != null)
        _StageGroup('firebase', tenant.firebase!.all.toList()),
    ];

    // Guarantee 1: re-validate here, don't trust the caller went through
    // WhiteLabelConfig's parser. Every group is validated up front, before
    // touching disk at all — Firebase paths go through the identical
    // ConfigValidator.assetPath check as asset paths.
    for (final group in groups) {
      for (final relativePath in group.paths) {
        final result = ConfigValidator.assetPath(
          relativePath,
          tenantId: tenant.id,
          projectRoot: projectRoot,
        );
        if (result is Invalid) {
          throw StateError(
            'Refusing to stage tenant "${tenant.id}": ${result.message}',
          );
        }
      }
      // Guarantee 3: reject basename collisions within this group before
      // touching disk at all.
      _checkBasenameCollisions(tenant.id, group);
    }

    // Guarantee 2: build the new staged output in a sibling temp directory
    // first; only swap it into place once every declared file (across all
    // groups) has copied successfully. The previous staging output (if any)
    // is untouched until that swap.
    final finalDir = Directory(stagingDirFor(tenant.id));
    final tempDir = Directory('${finalDir.path}.tmp-${tenant.id}');
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    tempDir.createSync(recursive: true);

    try {
      for (final group in groups) {
        final destDir = Directory(p.join(tempDir.path, group.name))
          ..createSync(recursive: true);
        for (final relativePath in group.paths) {
          final source = File(p.join(projectRoot, relativePath));
          if (!source.existsSync()) {
            throw StateError(
              'Declared ${group.name} file not found for tenant '
              '"${tenant.id}": $relativePath',
            );
          }
          final dest = File(p.join(destDir.path, p.basename(relativePath)));
          source.copySync(dest.path);
        }
      }
    } catch (_) {
      tempDir.deleteSync(recursive: true);
      rethrow;
    }

    if (finalDir.existsSync()) finalDir.deleteSync(recursive: true);
    tempDir.renameSync(finalDir.path);

    return p.join(finalDir.path, 'assets');
  }

  /// Guarantee 3, shared by every [_StageGroup]: two different declared
  /// files within the same group that would resolve to the same destination
  /// basename is a hard error, not a silent overwrite.
  void _checkBasenameCollisions(String tenantId, _StageGroup group) {
    final destinationsByBasename = <String, String>{}; // basename -> source
    for (final relativePath in group.paths) {
      final basename = p.basename(relativePath);
      final existing = destinationsByBasename[basename];
      if (existing != null && existing != relativePath) {
        throw StateError(
          'Tenant "$tenantId" declares two different ${group.name} files '
          'that would collide as "$basename" in the staged output: '
          '"$existing" and "$relativePath". Rename one of the source files '
          "so they don't share a basename.",
        );
      }
      destinationsByBasename[basename] = relativePath;
    }
  }

  /// Removes tenant's staging output entirely. Safe to call even if nothing
  /// was ever staged.
  void clean(String tenantId) {
    final dir = Directory(stagingDirFor(tenantId));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    final tempDir = Directory('${dir.path}.tmp-$tenantId');
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }

  /// Lists the basenames present in a tenant's staged `assets/` dir — the
  /// primitive the mandatory isolation test is built on
  /// (`stagedAssetNames('acme')` must never contain a beta-only filename).
  List<String> stagedAssetNames(String tenantId) =>
      _listStagedBasenames(tenantId, 'assets');

  /// Lists the basenames present in a tenant's staged `firebase/` dir —
  /// empty if the tenant declared no `firebase:` config (or nothing has
  /// been staged yet for it). Same cross-tenant-isolation guarantee as
  /// [stagedAssetNames], for Firebase config files.
  List<String> stagedFirebaseFileNames(String tenantId) =>
      _listStagedBasenames(tenantId, 'firebase');

  List<String> _listStagedBasenames(String tenantId, String subdir) {
    final dir = Directory(p.join(stagingDirFor(tenantId), subdir));
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList()
      ..sort();
  }
}

/// One group of declared files staged together into their own subdirectory
/// of the tenant's staging output (e.g. `assets/`, `firebase/`) — see
/// [TenantStager.stage]. Purely an internal grouping so assets and Firebase
/// files share one validate/collision/copy code path instead of two.
class _StageGroup {
  const _StageGroup(this.name, this.paths);

  /// Destination subdirectory name under the tenant's staging dir.
  final String name;

  /// Declared source paths (relative to `projectRoot`) for this group.
  final List<String> paths;
}
