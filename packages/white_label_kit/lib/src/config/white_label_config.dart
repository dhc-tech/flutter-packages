// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../validation/config_validator.dart';
import '../validation/validation_result.dart';
import 'tenant_config.dart';

/// Parsed, validated top-level `white_label.yaml`. Construction always goes
/// through [WhiteLabelConfig.parse] or [WhiteLabelConfig.load] — there is no
/// public unchecked constructor, so a [WhiteLabelConfig] instance is always
/// known-valid by the time application/generator code touches it.
class WhiteLabelConfig {
  const WhiteLabelConfig._({
    required this.defaultTenant,
    required this.tenants,
  });

  /// The id of the tenant used when no explicit tenant is requested.
  final String defaultTenant;

  /// All declared tenants, keyed by tenant id.
  final Map<String, TenantConfig> tenants;

  /// Returns the [TenantConfig] for [tenantId], throwing [ArgumentError] if
  /// no such tenant is declared.
  TenantConfig operator [](String tenantId) {
    final TenantConfig? tenant = tenants[tenantId];
    if (tenant == null) {
      throw ArgumentError.value(
        tenantId,
        'tenantId',
        'No such tenant in white_label.yaml',
      );
    }
    return tenant;
  }

  /// Whether a tenant with id [tenantId] is declared in this config.
  bool has(String tenantId) => tenants.containsKey(tenantId);

  /// Whether [tenantId] is the `default_tenant` declared in
  /// `white_label.yaml`. Every CLI command that takes an optional
  /// `--tenant` flag (or, at runtime, whatever consumes an unset `--flavor`)
  /// resolves through here — the default is never silently "whichever
  /// tenant happens to be first in the map", it is always this one
  /// explicit, declared value.
  bool isDefault(String tenantId) => tenantId == defaultTenant;

  /// Resolves the tenant to act on: [tenantId] if given, otherwise the
  /// declared `default_tenant` — so `--tenant` is always optional, never a
  /// silent guess. Throws the same [ArgumentError] as `[]` if the resolved
  /// id doesn't exist.
  TenantConfig resolve([String? tenantId]) => this[tenantId ?? defaultTenant];

  /// The full resolved [TenantConfig] for `default_tenant` — convenience for
  /// `resolve(null)`.
  TenantConfig get defaultTenantConfig => this[defaultTenant];

  /// Reads and parses the config file (`<projectRoot>/white_label.yaml` by
  /// default — see [configFile]). Throws [WhiteLabelConfigException] with
  /// every validation error collected (not just the first) if the file is
  /// missing, malformed, or invalid — see [ConfigValidator] for the full
  /// rule set.
  ///
  /// [configPath] overrides the default filename/location, same idea as
  /// `flutter_native_splash --path=some_config.yaml` — a project with
  /// multiple brand configs (e.g. `white_label_dev.yaml` vs
  /// `white_label_prod.yaml`) isn't forced into one fixed name. Relative
  /// paths resolve against [projectRoot]; absolute paths are used as-is.
  static WhiteLabelConfig load(String projectRoot, {String? configPath}) {
    final File file = configFile(projectRoot, configPath: configPath);
    if (!file.existsSync()) {
      final message =
          '${p.basename(file.path)} not found at ${file.path}. Run `dart run '
          'white_label_kit:init` first (or pass --config if you meant a '
          'different file).';
      throw WhiteLabelConfigException([message]);
    }
    return parse(file.readAsStringSync(), projectRoot: projectRoot);
  }

  /// `white_label.yaml` lives at the project root by default — same place a
  /// developer already looks for `pubspec.yaml`/`analysis_options.yaml`,
  /// and the same convention `flutter_native_splash`/`icons_launcher`-style
  /// config files use. The filename/location isn't hardcoded, though —
  /// pass [configPath] (relative to [projectRoot], or absolute) to use a
  /// different one, same idea as `flutter_native_splash --path=...`.
  ///
  /// Generation (`lib/white_label.g.dart`) is triggered by a plain CLI
  /// command (`dart run white_label_kit:generate` — see `bin/generate.dart`
  /// / `bin/white_label.dart`'s `generate` subcommand), not by
  /// `build_runner` — no `build.yaml` source-scan configuration required
  /// for that path (an optional `build_runner`-based alternative exists
  /// too, see `lib/builder.dart`, for projects that prefer it — but that
  /// one is fixed to the default `white_label.yaml` location, since
  /// `build_runner` needs a static input path declared ahead of time).
  static File configFile(String projectRoot, {String? configPath}) {
    if (configPath == null) {
      return File('$projectRoot/white_label.yaml');
    }
    return File(
      p.isAbsolute(configPath) ? configPath : p.join(projectRoot, configPath),
    );
  }

  /// Parses YAML text directly — used by [load] and by tests that don't want
  /// to touch the filesystem. [projectRoot], if given, enables asset-existence
  /// checks (see [ConfigValidator.assetPath]); omit it to validate structure
  /// only (e.g. before tenant directories exist yet).
  static WhiteLabelConfig parse(String yamlText, {String? projectRoot}) {
    final YamlNode doc;
    try {
      doc = loadYamlNode(yamlText);
    } on YamlException catch (e) {
      throw WhiteLabelConfigException(['Invalid YAML syntax: ${e.message}']);
    }

    final errors = <String>[];
    final Map<dynamic, dynamic>? root = ConfigValidator.expectMap(
      doc,
      'white_label.yaml',
      errors,
    );
    final Map<dynamic, dynamic>? wl = root == null
        ? null
        : ConfigValidator.expectMap(root['white_label'], 'white_label', errors);

    if (wl == null) {
      throw WhiteLabelConfigException(
        errors.isEmpty ? ['Missing top-level `white_label:` key.'] : errors,
      );
    }

    final defaultTenant = wl['default_tenant']?.toString();
    final Map<dynamic, dynamic>? tenantsNode = ConfigValidator.expectMap(
      wl['tenants'],
      'white_label.tenants',
      errors,
    );

    final tenants = <String, TenantConfig>{};
    if (tenantsNode != null) {
      for (final MapEntry<dynamic, dynamic> entry in tenantsNode.entries) {
        final id = entry.key.toString();
        final ValidationResult result = ConfigValidator.tenantId(id);
        if (result is Invalid) {
          errors.add(result.message);
          continue;
        }
        final TenantConfig? tenant = _parseTenant(
          id,
          entry.value,
          errors,
          projectRoot,
        );
        if (tenant != null) {
          if (tenants.containsKey(id)) {
            errors.add('Duplicate tenant id "$id".');
          } else {
            tenants[id] = tenant;
          }
        }
      }
    }

    // Resolution rules for `default_tenant`:
    //  1. Explicit `default_tenant` must name a declared tenant.
    //  2. Omitted + exactly one tenant declared: that tenant is implicitly
    //     the default — no error, no need to state the obvious in YAML.
    //  3. Omitted + multiple tenants declared: ambiguous, hard error — there
    //     is no reasonable guess (e.g. "first key in the map") to fall back
    //     on, so this must be explicit.
    //  4. Omitted + zero tenants declared: falls through to the original
    //     "missing default_tenant" error below (there's nothing to infer
    //     from either).
    var resolvedDefaultTenant = defaultTenant;
    if (defaultTenant != null) {
      if (tenants.isNotEmpty && !tenants.containsKey(defaultTenant)) {
        errors.add(
          '`default_tenant: $defaultTenant` is not one of the declared tenants.',
        );
      }
    } else if (tenants.length == 1) {
      resolvedDefaultTenant = tenants.keys.single;
    } else if (tenants.length > 1) {
      errors.add(
        'Multiple tenants declared but no default_tenant set — add '
        '`default_tenant: <id>` to white_label.yaml.',
      );
    } else {
      errors.add('Missing `white_label.default_tenant`.');
    }

    if (errors.isNotEmpty) {
      throw WhiteLabelConfigException(errors);
    }

    return WhiteLabelConfig._(
      defaultTenant: resolvedDefaultTenant!,
      tenants: tenants,
    );
  }

  static TenantConfig? _parseTenant(
    String id,
    dynamic node,
    List<String> errors,
    String? projectRoot,
  ) {
    final Map<dynamic, dynamic>? map = ConfigValidator.expectMap(
      node,
      'tenants.$id',
      errors,
    );
    if (map == null) {
      return null;
    }

    final name = map['name']?.toString();
    if (name == null || name.trim().isEmpty) {
      errors.add('Tenant "$id" is missing required field `name`.');
    }

    final Map<dynamic, dynamic>? android = ConfigValidator.expectMap(
      map['android'],
      'tenants.$id.android',
      errors,
    );
    final applicationId = android?['application_id']?.toString();
    final String? androidAppName = android?['app_name']?.toString() ?? name;
    if (applicationId == null) {
      errors.add(
        'Tenant "$id" is missing required field `android.application_id`.',
      );
    } else {
      final ValidationResult r = ConfigValidator.androidApplicationId(
        applicationId,
      );
      if (r is Invalid) {
        errors.add('Tenant "$id": ${r.message}');
      }
    }

    final Map<dynamic, dynamic>? ios = ConfigValidator.expectMap(
      map['ios'],
      'tenants.$id.ios',
      errors,
    );
    final bundleId = ios?['bundle_id']?.toString();
    final String? iosAppName = ios?['app_name']?.toString() ?? name;
    if (bundleId == null) {
      errors.add('Tenant "$id" is missing required field `ios.bundle_id`.');
    } else {
      final ValidationResult r = ConfigValidator.iosBundleId(bundleId);
      if (r is Invalid) {
        errors.add('Tenant "$id": ${r.message}');
      }
    }

    final Map<dynamic, dynamic>? assetsNode = ConfigValidator.expectMap(
      map['assets'],
      'tenants.$id.assets',
      errors,
    );
    final logo = assetsNode?['logo']?.toString();
    final icon = assetsNode?['icon']?.toString();
    final splash = assetsNode?['splash']?.toString();
    if (logo == null) {
      errors.add('Tenant "$id" is missing required field `assets.logo`.');
    }
    for (final String path in [logo, icon, splash].whereType<String>()) {
      final ValidationResult r = ConfigValidator.assetPath(
        path,
        tenantId: id,
        projectRoot: projectRoot,
      );
      if (r is Invalid) {
        errors.add('Tenant "$id": ${r.message}');
      }
    }

    final TenantVersion sharedVersion =
        _parseVersion(map['version'], 'tenants.$id.version', errors) ??
        const TenantVersion(name: '1.0.0', buildNumber: 1);
    final TenantVersion? androidVersionOverride = android?['version'] == null
        ? null
        : _parseVersion(
            android!['version'],
            'tenants.$id.android.version',
            errors,
          );
    final TenantVersion? iosVersionOverride = ios?['version'] == null
        ? null
        : _parseVersion(ios!['version'], 'tenants.$id.ios.version', errors);

    final dynamic themeNode = map['theme'];
    String? primaryColor;
    String? secondaryColor;
    var brandColors = const <String, String>{};
    var featureColors = const <String, String>{};
    var sectionColors = const <String, String>{};
    var gradientColors = const <String, String>{};
    if (themeNode != null) {
      final Map<dynamic, dynamic>? theme = ConfigValidator.expectMap(
        themeNode,
        'tenants.$id.theme',
        errors,
      );
      primaryColor = theme?['primary_color']?.toString();
      secondaryColor = theme?['secondary_color']?.toString();
      for (final String c in [
        primaryColor,
        secondaryColor,
      ].whereType<String>()) {
        final ValidationResult r = ConfigValidator.colorHex(c);
        if (r is Invalid) {
          errors.add('Tenant "$id": ${r.message}');
        }
      }
      brandColors = _parseColorMap(
        theme,
        'brand_colors',
        'tenants.$id.theme.brand_colors',
        errors,
      );
      featureColors = _parseColorMap(
        theme,
        'feature_colors',
        'tenants.$id.theme.feature_colors',
        errors,
      );
      sectionColors = _parseColorMap(
        theme,
        'section_colors',
        'tenants.$id.theme.section_colors',
        errors,
      );
      gradientColors = _parseColorMap(
        theme,
        'gradient_colors',
        'tenants.$id.theme.gradient_colors',
        errors,
      );
    }

    String? apiBaseUrl;
    var customEnv = const <String, String>{};
    final dynamic envNode = map['environment'];
    if (envNode != null) {
      final Map<dynamic, dynamic>? env = ConfigValidator.expectMap(
        envNode,
        'tenants.$id.environment',
        errors,
      );
      apiBaseUrl = env?['api_base_url']?.toString();
      if (apiBaseUrl != null) {
        final ValidationResult r = ConfigValidator.url(apiBaseUrl);
        if (r is Invalid) {
          errors.add('Tenant "$id": ${r.message}');
        }
      }
      customEnv = _parseStringMap(
        env,
        'custom',
        'tenants.$id.environment.custom',
        errors,
      );
    }

    // Named environment overrides (`environments: { staging: {...},
    // production: {...} }`) — same shape/validation as the single
    // `environment:` block above, just keyed by environment name. Optional:
    // a tenant that only ever needs one environment omits this entirely and
    // TenantConfig.resolveEnvironment(null) returns `environment` as before.
    final environments = <String, TenantEnvironment>{};
    final dynamic environmentsNode = map['environments'];
    if (environmentsNode != null) {
      final Map<dynamic, dynamic>? envsMap = ConfigValidator.expectMap(
        environmentsNode,
        'tenants.$id.environments',
        errors,
      );
      envsMap?.forEach((envKey, envValue) {
        final String envName = envKey.toString();
        final Map<dynamic, dynamic>? env = ConfigValidator.expectMap(
          envValue,
          'tenants.$id.environments.$envName',
          errors,
        );
        final String? envApiBaseUrl = env?['api_base_url']?.toString();
        if (envApiBaseUrl != null) {
          final ValidationResult r = ConfigValidator.url(envApiBaseUrl);
          if (r is Invalid) {
            errors.add('Tenant "$id": ${r.message}');
          }
        }
        final Map<String, String> envCustom = _parseStringMap(
          env,
          'custom',
          'tenants.$id.environments.$envName.custom',
          errors,
        );
        environments[envName] = TenantEnvironment(
          apiBaseUrl: envApiBaseUrl,
          custom: envCustom,
        );
      });
    }

    final dynamic featuresNode = map['features'];
    final features = <String, bool>{};
    if (featuresNode != null) {
      final Map<dynamic, dynamic>? f = ConfigValidator.expectMap(
        featuresNode,
        'tenants.$id.features',
        errors,
      );
      f?.forEach((key, value) {
        if (value is bool) {
          features[key.toString()] = value;
        } else {
          errors.add(
            'Tenant "$id": feature "$key" must be true/false, got "$value".',
          );
        }
      });
    }

    // Firebase is optional per tenant — `firebase:` block is omitted
    // entirely for tenants that don't use it. Both paths, when present, go
    // through the exact same ConfigValidator.assetPath check as
    // assets.logo/icon/splash — no separate/weaker validation for Firebase
    // files.
    TenantFirebaseConfig? firebase;
    final dynamic firebaseNode = map['firebase'];
    if (firebaseNode != null) {
      final Map<dynamic, dynamic>? fb = ConfigValidator.expectMap(
        firebaseNode,
        'tenants.$id.firebase',
        errors,
      );
      final googleServicesJson = fb?['google_services_json']?.toString();
      final googleServiceInfoPlist = fb?['google_service_info_plist']
          ?.toString();
      for (final String path in [
        googleServicesJson,
        googleServiceInfoPlist,
      ].whereType<String>()) {
        final ValidationResult r = ConfigValidator.assetPath(
          path,
          tenantId: id,
          projectRoot: projectRoot,
        );
        if (r is Invalid) {
          errors.add('Tenant "$id": ${r.message}');
        }
      }
      firebase = TenantFirebaseConfig(
        googleServicesJson: googleServicesJson,
        googleServiceInfoPlist: googleServiceInfoPlist,
      );
    }

    // Bail out of building a TenantConfig for this entry if anything above
    // was missing/invalid — errors already recorded, caller throws once all
    // tenants have been walked so a user sees every problem in one pass.
    if (name == null ||
        applicationId == null ||
        bundleId == null ||
        logo == null) {
      return null;
    }

    return TenantConfig(
      id: id,
      name: name,
      android: AndroidTenantConfig(
        applicationId: applicationId,
        appName: androidAppName!,
        version: androidVersionOverride,
      ),
      ios: IosTenantConfig(
        bundleId: bundleId,
        appName: iosAppName!,
        version: iosVersionOverride,
      ),
      assets: TenantAssets(logo: logo, icon: icon, splash: splash),
      version: sharedVersion,
      theme: TenantTheme(
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        brandColors: brandColors,
        featureColors: featureColors,
        sectionColors: sectionColors,
        gradientColors: gradientColors,
      ),
      environment: TenantEnvironment(apiBaseUrl: apiBaseUrl, custom: customEnv),
      environments: environments,
      features: features,
      firebase: firebase,
    );
  }

  /// Parses a `version:` block (`{name: "1.2.0", build_number: 5}`) shared by
  /// the tenant-level and per-platform (`android.version`/`ios.version`)
  /// shapes. Returns `null` if [node] is absent (caller decides the
  /// default/fallback) or if it's present but invalid (errors already
  /// recorded into [errors]).
  /// Parses one of the four named color-map fields under `theme:`
  /// (`brand_colors`/`feature_colors`/`section_colors`/`gradient_colors`) —
  /// every value goes through the exact same [ConfigValidator.colorHex]
  /// check as `primary_color`/`secondary_color`. Returns an empty map
  /// (never null) if the field is absent — these are all optional.
  static Map<String, String> _parseColorMap(
    Map<dynamic, dynamic>? theme,
    String key,
    String path,
    List<String> errors,
  ) {
    final dynamic node = theme?[key];
    if (node == null) {
      return const {};
    }
    final Map<dynamic, dynamic>? map = ConfigValidator.expectMap(
      node,
      path,
      errors,
    );
    if (map == null) {
      return const {};
    }

    final result = <String, String>{};
    map.forEach((k, v) {
      final colorKey = k.toString();
      final colorValue = v.toString();
      final ValidationResult r = ConfigValidator.colorHex(colorValue);
      if (r is Invalid) {
        errors.add('$path.$colorKey: ${r.message}');
      } else {
        result[colorKey] = colorValue;
      }
    });
    return result;
  }

  /// Parses an arbitrary string-keyed, string-valued map field (e.g.
  /// `custom:` under `environment:`/`environments.<name>:`) — same
  /// optional/never-null-return contract as [_parseColorMap], but without
  /// the color-hex validation (any string value is accepted).
  static Map<String, String> _parseStringMap(
    Map<dynamic, dynamic>? parent,
    String key,
    String path,
    List<String> errors,
  ) {
    final dynamic node = parent?[key];
    if (node == null) {
      return const {};
    }
    final Map<dynamic, dynamic>? map = ConfigValidator.expectMap(
      node,
      path,
      errors,
    );
    if (map == null) {
      return const {};
    }
    return {
      for (final entry in map.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }

  static TenantVersion? _parseVersion(
    dynamic node,
    String path,
    List<String> errors,
  ) {
    if (node == null) {
      return null;
    }
    final Map<dynamic, dynamic>? map = ConfigValidator.expectMap(
      node,
      path,
      errors,
    );
    if (map == null) {
      return null;
    }

    final name = map['name']?.toString();
    if (name == null) {
      errors.add('Expected "$path.name" to be set (e.g. "1.2.0").');
      return null;
    }
    final ValidationResult nameResult = ConfigValidator.semanticVersion(name);
    if (nameResult is Invalid) {
      errors.add('$path: ${nameResult.message}');
    }

    final dynamic buildNumberRaw = map['build_number'];
    final int? buildNumber = buildNumberRaw is int
        ? buildNumberRaw
        : int.tryParse(buildNumberRaw?.toString() ?? '');
    if (buildNumber == null) {
      errors.add('Expected "$path.build_number" to be a positive integer.');
      return null;
    }
    final ValidationResult buildNumberResult = ConfigValidator.buildNumber(
      buildNumber,
    );
    if (buildNumberResult is Invalid) {
      errors.add('$path: ${buildNumberResult.message}');
    }

    if (nameResult is Invalid || buildNumberResult is Invalid) {
      return null;
    }
    return TenantVersion(name: name, buildNumber: buildNumber);
  }
}

/// Thrown by [WhiteLabelConfig.load]/[WhiteLabelConfig.parse]. Carries every validation error
/// found (not just the first), so a CLI can print them all at once instead
/// of forcing a fix-one-rerun-fix-next loop.
class WhiteLabelConfigException implements Exception {
  /// Creates an exception carrying the given list of validation [errors].
  WhiteLabelConfigException(this.errors);

  /// All validation error messages collected while parsing the config.
  final List<String> errors;

  @override
  String toString() => errors.map((e) => 'ERROR: $e').join('\n');
}
