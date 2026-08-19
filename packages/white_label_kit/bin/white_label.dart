// ==============================================================================
// WHITE-LABEL CLI (Pure Dart)
// Single entry point for every white-label tenant task — devs never need to
// remember which of the three underlying tools (tenants/add_flavor.dart,
// tool/tenant_doctor.dart, tool/build_runner.dart) to call directly.
//
// This is a thin dispatcher, not a reimplementation: each subcommand just
// forwards to the existing tool with the same arguments, so behavior/output
// stays identical to running that tool directly. See docs/white_label_flavors.md
// and tenants/README.md for what each underlying tool actually does.
//
// This package is a *local* path dependency of the host app (see its
// pubspec.yaml `dev_dependencies: white_label_kit: path: packages/...`).
// It shells out to paths (`tenants/add_flavor.dart`, `tool/...`) relative to
// the current working directory, so it must be run from the host app's repo
// root — same requirement as running those tools directly. Not yet
// generalized for use outside this repo; see the package description for
// what that would take before a real pub.dev release.
//
// YAML config (like `flutter_native_splash`/`icons_launcher`): drop a
// `white_label_kit.yaml` in the repo root and every subcommand fills in
// whatever CLI args you didn't type from it — no need to retype the same
// tenant id every time. Explicit CLI args always win over the file.
//
//   # white_label_kit.yaml
//   tenant_id: acmecollege
//   display_name: Acme College
//   bundle_id: com.acmecollege.student
//   api_base_url: https://api.acmecollege.com   # optional
//
// Usage (from the app root):
//   dart run white_label_kit:white_label <command> [args...]
//
// Commands:
//   add [id] ["<Name>"] [bundleId] [apiBaseUrl]  Onboard a new tenant
//   doctor [id] [--all] [--json] [--strict]      Health-check a tenant
//   build [id] [--platform ..] [--mode ..]       Build a tenant (host-app)
//   help                                         Show this message
//
// Plus a second, repo-agnostic layer driven by `white_label.yaml`
// (WhiteLabelConfig/TenantStager — see lib/src/config, lib/src/generation):
//   init [--example] [--force] [--path <dir>]    Scaffold white_label.yaml
//   validate                                     Validate white_label.yaml
//   list                                         List tenants + default
//   build --tenant <id> [...]                    Generic build (see below)
//   run [--tenant <id>]                          Prepare a tenant to `flutter run`
// `build` is one name shared by both layers — see the routing comment
// above the `command == 'build'` check in main() for how they're told apart.
// ==============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:white_label_kit/white_label_kit.dart';
import 'package:yaml/yaml.dart';

const _commands = <String, String>{
  'doctor': 'tool/tenant_doctor.dart',
  'build': 'tool/build_runner.dart',
};

const _defaultConfigFile = 'white_label_kit.yaml';

Future<void> main(List<String> args) async => runCli(args);

/// The actual dispatcher — factored out of `main` so the top-level,
/// single-purpose executables (`bin/init.dart`, `bin/list.dart`,
/// `bin/add_tenant.dart`, `bin/validate.dart`, `bin/run.dart`,
/// `bin/build.dart` — each registered in `pubspec.yaml`'s `executables:` so
/// `dart run white_label_kit:init` etc. work directly, no `white_label`
/// subcommand prefix needed) can each just call `runCli(['init', ...args])`
/// instead of duplicating this whole dispatch table.
Future<void> runCli(List<String> args) async {
  if (args.isEmpty && File('white_label.yaml').existsSync()) {
    final int exitCode = await runInteractiveMenu();
    exit(exitCode);
  }

  if (args.isEmpty || const {'help', '-h', '--help'}.contains(args.first)) {
    _printUsage();
    exit(args.isEmpty ? 1 : 0);
  }

  final String command = args.first;

  if (command == 'menu' || command == 'runner') {
    final int exitCode = await runInteractiveMenu();
    exit(exitCode);
  }

  if (command == 'list') {
    _listTenants();
    exit(0);
  }

  // --- Generic white_label.yaml layer (WhiteLabelConfig/TenantStager) ---
  // These commands are new, repo-agnostic, and have no host-app-specific
  // script to shell out to — they operate purely on `white_label.yaml`
  // via the white_label_kit library, so they're handled directly here
  // rather than through the `_commands` script-dispatch table below.
  if (command == 'init') {
    exit(_init(args.skip(1).toList()));
  }

  if (command == 'add' || command == 'add-tenant') {
    exit(_addTenant(args.skip(1).toList()));
  }

  if (command == 'generate') {
    exit(_generate(args.skip(1).toList()));
  }

  if (command == 'update-tenant') {
    exit(_updateTenant(args.skip(1).toList()));
  }

  if (command == 'remove-tenant') {
    exit(_removeTenant(args.skip(1).toList()));
  }

  // `doctor` has the same host-app-vs-generic ambiguity as `build` (see
  // that routing comment below) — this repo's own `doctor` forwards to
  // tool/tenant_doctor.dart via the `_commands` table; a project using only
  // the generic layer has no such file, so route there instead.
  if (command == 'doctor' &&
      File('white_label.yaml').existsSync() &&
      !File('tool/tenant_doctor.dart').existsSync()) {
    exit(_doctor());
  }

  if (command == 'validate') {
    exit(_validate());
  }

  if (command == 'run') {
    exit(await _run(args.skip(1).toList()));
  }

  // `build` is ambiguous: it's both the long-standing host-app command
  // (forwards to tool/build_runner.dart, handled by the `_commands` table
  // below — DO NOT touch that path) and the new generic white_label.yaml
  // build. We disambiguate by evidence in the current directory rather than
  // renaming either one: if a `white_label.yaml` exists AND the
  // `tool/build_runner.dart` does NOT (i.e. this is a generic project), route to the
  // new generic build. Otherwise fall through unchanged to the existing
  // host-app behavior.
  if (command == 'build' &&
      File('white_label.yaml').existsSync() &&
      !File('tool/build_runner.dart').existsSync()) {
    exit(await _genericBuild(args.skip(1).toList()));
  }

  if (command == 'auto-onboard') {
    final Map<String, String> config = _loadConfig();
    final List<String> rest = args.skip(1).toList();
    final String? tenantId = rest.isNotEmpty ? rest.first : config['tenant_id'];
    if (tenantId == null) {
      stderr.writeln(
        '❌ auto-onboard needs a tenant id (arg or tenant_id: in $_defaultConfigFile)\n',
      );
      _printUsage();
      exit(1);
    }
    final bool ok = autoOnboardTenant(
      tenantId,
      root: Directory.current,
      dryRun: rest.contains('--dry-run'),
    );
    exit(ok ? 0 : 1);
  }

  if (command == 'configure') {
    exit(await _configureTenants(args.skip(1).toList()));
  }

  final String? script = _commands[command];
  if (script == null) {
    stderr.writeln("❌ Unknown command: '$command'\n");
    _printUsage();
    exit(1);
  }

  final Map<String, String> config = _loadConfig();
  final List<String> forwardedArgs = _resolveArgs(
    command,
    args.skip(1).toList(),
    config,
  );

  final Process result = await Process.start('dart', [
    'run',
    script,
    ...forwardedArgs,
  ], mode: ProcessStartMode.inheritStdio);
  exit(await result.exitCode);
}

/// Lists every tenant declared in `white_label.yaml` (the generic
/// config/isolation layer — see lib/src/config), always marking which one
/// is `default_tenant` so it's never ambiguous which tenant a bare
/// `--tenant`-less command would act on. Prints both a top-line
/// "Default tenant: `<id>`" summary AND a per-tenant `(default)` marker —
/// intentionally redundant so it's unmissable either way you're scanning.
void _listTenants() {
  final WhiteLabelConfig? config = _tryLoadWhiteLabelConfig();
  if (config == null) {
    exit(1);
  }

  stdout.writeln('Default tenant: ${config.defaultTenant}');
  stdout.writeln('Tenants (from white_label.yaml):');
  for (final String id in config.tenants.keys.toList()..sort()) {
    final marker = config.isDefault(id) ? '  (default)' : '';
    stdout.writeln('  - $id — ${config[id].name}$marker');
  }
}

/// Loads `white_label.yaml` from the current directory, printing every
/// collected validation error (never a raw stack trace) and returning
/// `null` on failure so callers can `exit(1)` themselves.
WhiteLabelConfig? _tryLoadWhiteLabelConfig() {
  try {
    return WhiteLabelConfig.load(Directory.current.path);
  } on WhiteLabelConfigException catch (e) {
    stderr.writeln(e);
    return null;
  }
}

/// `validate` — loads + type/shape-checks `white_label.yaml` without doing
/// anything else (no staging, no asset copying). Returns the process exit
/// code (0 valid, 1 invalid).
int _validate() {
  final WhiteLabelConfig? config = _tryLoadWhiteLabelConfig();
  if (config == null) {
    return 1;
  }

  stdout.writeln('✅ white_label.yaml is valid');
  stdout.writeln('Default tenant: ${config.defaultTenant}');
  for (final String id in config.tenants.keys.toList()..sort()) {
    final marker = config.isDefault(id) ? ' (default)' : '';
    stdout.writeln('  - $id — ${config[id].name}$marker');
  }
  return 0;
}

/// `doctor` — a fuller health check than `validate`: everything `validate`
/// checks (YAML shape/field validity), PLUS whether each tenant's declared
/// asset files actually exist on disk, and whether `lib/white_label.g.dart`
/// exists and looks like it was generated for a tenant this config still
/// declares (a stale/missing generated file is a common real mistake — ran
/// `generate` once, then added/renamed tenants and forgot to re-run it).
int _doctor() {
  final WhiteLabelConfig? config = _tryLoadWhiteLabelConfig();
  if (config == null) {
    return 1;
  }

  stdout.writeln('✅ white_label.yaml is valid');
  stdout.writeln('Default tenant: ${config.defaultTenant}');
  var healthy = true;

  for (final String id in config.tenants.keys.toList()..sort()) {
    final TenantConfig tenant = config[id];
    final marker = config.isDefault(id) ? ' (default)' : '';
    stdout.writeln('  - $id — ${tenant.name}$marker');
    for (final String assetPath in tenant.assets.all) {
      final bool exists = File(assetPath).existsSync();
      stdout.writeln('      ${exists ? '✅' : '❌'} $assetPath');
      if (!exists) {
        healthy = false;
      }
    }
  }

  final generated = File('lib/white_label.g.dart');
  if (!generated.existsSync()) {
    stdout.writeln(
      '⚠️  lib/white_label.g.dart does not exist yet — run `dart run '
      'white_label_kit:generate`.',
    );
    healthy = false;
  } else {
    final String content = generated.readAsStringSync();
    final RegExpMatch? tenantIdMatch = RegExp("tenantId: '([^']+)'")
        .firstMatch(content);
    final String? generatedFor = tenantIdMatch?.group(1);
    if (generatedFor == null || !config.has(generatedFor)) {
      stdout.writeln(
        '⚠️  lib/white_label.g.dart looks stale (tenant "$generatedFor" no '
        'longer in white_label.yaml) — re-run `dart run '
        'white_label_kit:generate`.',
      );
      healthy = false;
    } else {
      stdout.writeln(
        '✅ lib/white_label.g.dart is generated for "$generatedFor".',
      );
    }
  }

  stdout.writeln();
  stdout.writeln(healthy ? '✅ TENANT VALID' : '❌ Issues found — see above.');
  return healthy ? 0 : 1;
}

/// `init [--example] [--force] [--path <dir>]` — scaffolds a starter
/// `white_label.yaml` in a Flutter project. Never overwrites an existing
/// file unless `--force` is passed. Returns the process exit code.
int _init(List<String> args) {
  String? path;
  var example = false;
  var force = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--example':
        example = true;
      case '--force':
        force = true;
      case '--path':
        if (i + 1 >= args.length) {
          stderr.writeln('❌ --path requires a directory argument.');
          return 1;
        }
        path = args[++i];
      default:
        stderr.writeln('❌ Unknown flag for `init`: ${args[i]}');
        return 1;
    }
  }

  final String targetDir = path ?? Directory.current.path;

  final pubspecFile = File(p.join(targetDir, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    stderr.writeln(
      '❌ No pubspec.yaml found at $targetDir — `init` must be run from '
      '(or pointed at, via --path) a Flutter project root.',
    );
    return 1;
  }

  Object? pubspecDoc;
  try {
    pubspecDoc = loadYaml(pubspecFile.readAsStringSync());
  } on YamlException catch (e) {
    stderr.writeln('❌ ${pubspecFile.path} is not valid YAML: ${e.message}');
    return 1;
  }
  final bool looksLikeFlutterProject =
      pubspecDoc is Map && pubspecDoc.containsKey('flutter');
  if (!looksLikeFlutterProject) {
    stderr.writeln(
      "❌ ${pubspecFile.path} has no `flutter:` key — this doesn't look "
      'like a Flutter project. `init` refuses to scaffold white_label.yaml '
      "somewhere it wouldn't make sense.",
    );
    return 1;
  }

  final whiteLabelFile = File(p.join(targetDir, 'white_label.yaml'));
  if (whiteLabelFile.existsSync() && !force) {
    stderr.writeln(
      '❌ ${whiteLabelFile.path} already exists — already initialized. '
      'Use --force to overwrite.',
    );
    return 1;
  }

  whiteLabelFile.writeAsStringSync(_starterWhiteLabelYaml);
  stdout.writeln('✅ Created ${whiteLabelFile.path}');

  // NOTE: `init` does NOT create build.yaml — the primary/recommended path
  // is `dart run white_label_kit:generate` (a plain command, no
  // build_runner involved, see bin/generate.dart), the same shape as
  // `flutter_native_splash:create`/`icons_launcher:create`. build_runner
  // integration (lib/builder.dart) is an OPTIONAL alternative for projects
  // that prefer triggering generation from `dart run build_runner build`
  // instead — see this package's README for the one-line build.yaml
  // `sources:` override that needs, if you want that path too.

  if (example) {
    final assetsDir = Directory(p.join(targetDir, 'tenants', 'acme', 'assets'))
      ..createSync(recursive: true);
    final logoFile = File(p.join(assetsDir.path, 'logo.png'));
    logoFile.writeAsBytesSync(base64Decode(_placeholderPngBase64));
    stdout.writeln(
      '✅ Created ${logoFile.path} (tiny placeholder PNG — swap for a real '
      'logo before shipping)',
    );
  }

  stdout.writeln();
  stdout.writeln('Next steps:');
  stdout.writeln(
    '  1. Edit white_label.yaml — set your real tenant id(s), '
    'android.application_id, ios.bundle_id.',
  );
  stdout.writeln(
    example
        ? '  2. Replace tenants/acme/assets/logo.png with a real logo '
              '(same path, or update the `assets.logo` path in white_label.yaml).'
        : '  2. Add real assets under tenants/<id>/assets/ — every path '
              'declared in `assets:` must exist on disk.',
  );
  stdout.writeln('  3. Run: dart run white_label_kit:validate');
  stdout.writeln('  4. Run: dart run white_label_kit:build --tenant acme');
  return 0;
}

/// `add-tenant` — the part of the workflow that used to require hand-editing
/// `white_label.yaml` (a real YAML-writing library, indentation, remembering
/// the exact schema) and manually creating `tenants/<id>/assets/`. This
/// generates both from one command; a developer is never expected to write
/// YAML by hand or `mkdir` a tenant folder themselves.
///
/// Usage: `add-tenant <id> "<Name>" <bundleId> [--logo <path>] [--default]`
///
/// Rolls back everything it wrote (the yaml edit AND the created folder) if
/// the resulting config fails to validate — never leaves the project in a
/// half-added, invalid state.
/// `generate [--tenant <id>] [--config <path>]` — the primary, recommended
/// way to (re)create `lib/white_label.g.dart`: one direct command, no
/// `build_runner` involved, the same shape as `flutter_native_splash:create`
/// / `icons_launcher:create`. See `lib/builder.dart` for the OPTIONAL
/// `build_runner`-based alternative — both call the exact same generation
/// logic (`lib/src/generation/dart_config_generator.dart`).
///
/// `--config <path>` overrides the default `white_label.yaml` name/location
/// (relative to cwd, or absolute) — same idea as `flutter_native_splash
/// --path=...`, for a project that names its config file differently or
/// keeps more than one (e.g. `white_label_dev.yaml`).
int _generate(List<String> args) {
  String? tenantId;
  String? configPath;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tenant':
        if (i + 1 >= args.length) {
          stderr.writeln('❌ --tenant requires a value.');
          return 1;
        }
        tenantId = args[++i];
      case '--config':
        if (i + 1 >= args.length) {
          stderr.writeln('❌ --config requires a file path.');
          return 1;
        }
        configPath = args[++i];
      default:
        stderr.writeln('❌ Unknown flag for `generate`: ${args[i]}');
        return 1;
    }
  }

  final File configFile = WhiteLabelConfig.configFile(
    Directory.current.path,
    configPath: configPath,
  );
  if (!configFile.existsSync()) {
    stderr.writeln(
      '❌ ${configFile.path} not found. Run `dart run white_label_kit:init` '
      'first (or pass --config if you meant a different file).',
    );
    return 1;
  }

  final WhiteLabelConfig config;
  try {
    config = WhiteLabelConfig.parse(
      configFile.readAsStringSync(),
      projectRoot: Directory.current.path,
    );
  } on WhiteLabelConfigException catch (e) {
    stderr.writeln(e);
    return 1;
  }

  final String resolvedTenantId;
  try {
    resolvedTenantId = resolveGeneratorTenantId(
      config,
      explicitTenantId: tenantId,
    );
  } on ArgumentError catch (e) {
    stderr.writeln('❌ ${e.message}');
    return 1;
  }

  writeGeneratedFile(Directory.current.path, config, resolvedTenantId);
  stdout.writeln(
    '✅ Generated lib/white_label.g.dart for tenant "$resolvedTenantId" '
    '(from ${p.relative(configFile.path)}).',
  );
  return 0;
}

/// Finds the `tenantId:` block for tenant [id] inside raw
/// `white_label.yaml` [text] — from its own line up to (but not including)
/// the next line at the same 4-space tenant-key indent, or end of file.
/// Shared by `update-tenant`/`remove-tenant` so both edit exactly the same
/// span add-tenant would have inserted. Returns `null` if [id] isn't found.
(int start, int end)? _findTenantBlock(String text, String id) {
  final RegExpMatch? startMatch = RegExp(
    '^    $id:\r?\n',
    multiLine: true,
  ).firstMatch(text);
  if (startMatch == null) {
    return null;
  }
  final RegExpMatch? nextMatch = RegExp(
    r'^    [a-z][a-z0-9_]*:',
    multiLine: true,
  ).allMatches(text).where((m) => m.start > startMatch.start).firstOrNull;
  return (startMatch.start, nextMatch?.start ?? text.length);
}

/// `update-tenant <id> [--name <n>] [--android-id <id>] [--ios-id <id>] [--api-url <url>] [--logo <path>] [--default]`
/// — changes an existing tenant's fields WITHOUT hand-editing
/// `white_label.yaml`. Any flag you omit keeps that field's current value
/// (read from the tenant's current, already-valid config) — you only pass
/// what's actually changing. Rolls back to the original file if the result
/// doesn't validate.
int _updateTenant(List<String> args) {
  final positional = <String>[];
  String? name;
  String? androidId;
  String? iosId;
  String? apiUrl;
  String? logoPath;
  var makeDefault = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--name':
        name = args[++i];
      case '--android-id':
        androidId = args[++i];
      case '--ios-id':
        iosId = args[++i];
      case '--api-url':
        apiUrl = args[++i];
      case '--logo':
        logoPath = args[++i];
      case '--default':
        makeDefault = true;
      default:
        positional.add(args[i]);
    }
  }

  if (positional.length != 1) {
    stderr.writeln(
      '❌ Usage: update-tenant <id> [--name <n>] [--android-id <id>] '
      '[--ios-id <id>] [--api-url <url>] [--logo <path>] [--default]',
    );
    return 1;
  }
  final String id = positional[0];

  final WhiteLabelConfig? config = _tryLoadWhiteLabelConfig();
  if (config == null) {
    return 1;
  }
  if (!config.has(id)) {
    stderr.writeln('❌ No such tenant "$id" in white_label.yaml.');
    return 1;
  }
  final TenantConfig current = config[id];

  if (androidId != null) {
    final ValidationResult r = ConfigValidator.androidApplicationId(androidId);
    if (r is Invalid) {
      stderr.writeln('❌ ${r.message}');
      return 1;
    }
  }
  if (iosId != null) {
    final ValidationResult r = ConfigValidator.iosBundleId(iosId);
    if (r is Invalid) {
      stderr.writeln('❌ ${r.message}');
      return 1;
    }
  }
  if (apiUrl != null) {
    final ValidationResult r = ConfigValidator.url(apiUrl);
    if (r is Invalid) {
      stderr.writeln('❌ ${r.message}');
      return 1;
    }
  }

  final whiteLabelFile = File('white_label.yaml');
  final String originalYaml = whiteLabelFile.readAsStringSync();
  final (int, int)? range = _findTenantBlock(originalYaml, id);
  if (range == null) {
    stderr.writeln(
      '❌ Could not locate tenant "$id"\'s block in white_label.yaml.',
    );
    return 1;
  }

  final String resolvedName = name ?? current.name;
  final String resolvedAndroidId = androidId ?? current.android.applicationId;
  final String resolvedIosId = iosId ?? current.ios.bundleId;
  final String? resolvedApiUrl = apiUrl ?? current.environment.apiBaseUrl;
  final String resolvedLogo = logoPath != null
      ? 'tenants/$id/assets/logo.png'
      : current.assets.logo;

  if (logoPath != null) {
    final source = File(logoPath);
    if (!source.existsSync()) {
      stderr.writeln('❌ --logo file not found: $logoPath');
      return 1;
    }
    final dest = File(p.join('tenants', id, 'assets', 'logo.png'))
      ..parent.createSync(recursive: true);
    source.copySync(dest.path);
  }

  final buffer = StringBuffer()
    ..writeln('    $id:')
    ..writeln('      name: "$resolvedName"')
    ..writeln()
    ..writeln('      android:')
    ..writeln('        application_id: "$resolvedAndroidId"')
    ..writeln('        app_name: "$resolvedName"')
    ..writeln()
    ..writeln('      ios:')
    ..writeln('        bundle_id: "$resolvedIosId"')
    ..writeln('        app_name: "$resolvedName"')
    ..writeln()
    ..writeln('      assets:')
    ..writeln('        logo: "$resolvedLogo"');
  if (resolvedApiUrl != null) {
    buffer
      ..writeln()
      ..writeln('      environment:')
      ..writeln('        api_base_url: "$resolvedApiUrl"');
  }
  buffer.writeln();

  String updatedYaml = originalYaml.replaceRange(
    range.$1,
    range.$2,
    buffer.toString(),
  );
  if (makeDefault) {
    updatedYaml = updatedYaml.replaceFirstMapped(
      RegExp(r'^  default_tenant:.*$', multiLine: true),
      (_) => '  default_tenant: $id',
    );
  }

  whiteLabelFile.writeAsStringSync(updatedYaml);
  try {
    WhiteLabelConfig.load(Directory.current.path);
  } on WhiteLabelConfigException catch (e) {
    whiteLabelFile.writeAsStringSync(originalYaml);
    stderr.writeln(
      '❌ Updating tenant "$id" produced an invalid config — rolled back.',
    );
    stderr.writeln(e);
    return 1;
  }

  stdout.writeln('✅ Updated tenant "$id" in white_label.yaml');
  if (makeDefault) {
    stdout.writeln('✅ Set "$id" as default_tenant');
  }
  stdout.writeln();
  stdout.writeln('Next: dart run white_label_kit:generate --tenant $id');
  return 0;
}

/// `remove-tenant <id> [--keep-assets]` — deletes a tenant's block from
/// `white_label.yaml` WITHOUT hand-editing the file, and (unless
/// `--keep-assets`) deletes its `tenants/<id>/` folder too. Refuses to
/// remove the last remaining tenant, or the `default_tenant` unless another
/// tenant exists to auto-promote (announced, never silent). Rolls back if
/// the result doesn't validate.
int _removeTenant(List<String> args) {
  final positional = <String>[];
  var keepAssets = false;
  for (final arg in args) {
    if (arg == '--keep-assets') {
      keepAssets = true;
    } else {
      positional.add(arg);
    }
  }
  if (positional.length != 1) {
    stderr.writeln('❌ Usage: remove-tenant <id> [--keep-assets]');
    return 1;
  }
  final String id = positional[0];

  final WhiteLabelConfig? config = _tryLoadWhiteLabelConfig();
  if (config == null) {
    return 1;
  }
  if (!config.has(id)) {
    stderr.writeln('❌ No such tenant "$id" in white_label.yaml.');
    return 1;
  }
  if (config.tenants.length == 1) {
    stderr.writeln('❌ Cannot remove "$id" — it\'s the only tenant declared.');
    return 1;
  }

  final whiteLabelFile = File('white_label.yaml');
  final String originalYaml = whiteLabelFile.readAsStringSync();
  final (int, int)? range = _findTenantBlock(originalYaml, id);
  if (range == null) {
    stderr.writeln(
      '❌ Could not locate tenant "$id"\'s block in white_label.yaml.',
    );
    return 1;
  }

  String updatedYaml = originalYaml.replaceRange(range.$1, range.$2, '');

  String? newDefault;
  if (config.isDefault(id)) {
    newDefault = (config.tenants.keys.toList()..sort()).firstWhere(
      (t) => t != id,
    );
    updatedYaml = updatedYaml.replaceFirstMapped(
      RegExp(r'^  default_tenant:.*$', multiLine: true),
      (_) => '  default_tenant: $newDefault',
    );
  }

  whiteLabelFile.writeAsStringSync(updatedYaml);
  try {
    WhiteLabelConfig.load(Directory.current.path);
  } on WhiteLabelConfigException catch (e) {
    whiteLabelFile.writeAsStringSync(originalYaml);
    stderr.writeln(
      '❌ Removing tenant "$id" produced an invalid config — rolled back.',
    );
    stderr.writeln(e);
    return 1;
  }

  if (!keepAssets) {
    final dir = Directory(p.join('tenants', id));
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  // Native & IDE cleanup: remove Android flavor, iOS Xcode configs/schemes, and IDE run configs
  final String projectRoot = Directory.current.path;
  try {
    removeAndroidFlavor(id, projectRoot: projectRoot);
    removeIosConfig(id, projectRoot: projectRoot);
    IdeGenerator.remove(id, projectRoot: projectRoot);
  } catch (e) {
    stderr.writeln('⚠️  Native/IDE file cleanup encountered an error: $e');
  }

  // Regenerate white_label.g.dart for the active default tenant
  final String effectiveDefault = newDefault ?? config.defaultTenant;
  _generate(['--tenant', effectiveDefault]);

  stdout.writeln('✅ Removed tenant "$id" from white_label.yaml');
  if (newDefault != null) {
    stdout.writeln(
      '⚠️  "$id" was default_tenant — auto-promoted "$newDefault" instead.',
    );
  }
  if (!keepAssets) {
    stdout.writeln('✅ Deleted tenants/$id/');
  }
  stdout.writeln(
    '✅ Cleaned native Android flavors and iOS Xcode configs for "$id"',
  );
  return 0;
}

int _addTenant(List<String> args) {
  final positional = <String>[];
  String? logoPath;
  var makeDefault = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--logo':
        if (i + 1 >= args.length) {
          stderr.writeln('❌ --logo requires a file path argument.');
          return 1;
        }
        logoPath = args[++i];
      case '--default':
        makeDefault = true;
      default:
        positional.add(args[i]);
    }
  }

  if (positional.length < 3) {
    stderr.writeln(
      '❌ Usage: add-tenant <id> "<Name>" <bundleId> [--logo <path>] [--default]',
    );
    return 1;
  }
  final String id = positional[0];
  final String name = positional[1];
  final String bundleId = positional[2];

  final ValidationResult idResult = ConfigValidator.tenantId(id);
  if (idResult is Invalid) {
    stderr.writeln('❌ ${idResult.message}');
    return 1;
  }
  final ValidationResult appIdResult = ConfigValidator.androidApplicationId(
    bundleId,
  );
  if (appIdResult is Invalid) {
    stderr.writeln('❌ ${appIdResult.message}');
    return 1;
  }
  final ValidationResult bundleIdResult = ConfigValidator.iosBundleId(bundleId);
  if (bundleIdResult is Invalid) {
    stderr.writeln('❌ ${bundleIdResult.message}');
    return 1;
  }

  final whiteLabelFile = File('white_label.yaml');
  if (!whiteLabelFile.existsSync()) {
    stderr.writeln(
      '❌ No white_label.yaml here — run `dart run white_label_kit:white_label '
      'init` first.',
    );
    return 1;
  }
  final String originalYaml = whiteLabelFile.readAsStringSync();
  if (RegExp('^    $id:', multiLine: true).hasMatch(originalYaml)) {
    stderr.writeln('❌ Tenant "$id" already exists in white_label.yaml.');
    return 1;
  }

  // Auto-generate tenants/<id>/assets/ — the manual `mkdir` step this
  // command exists to remove.
  final assetsDir = Directory(p.join('tenants', id, 'assets'))
    ..createSync(recursive: true);
  final logoFile = File(p.join(assetsDir.path, 'logo.png'));
  var logoIsPlaceholder = false;
  if (logoPath != null) {
    final source = File(logoPath);
    if (!source.existsSync()) {
      assetsDir.parent.deleteSync(recursive: true);
      stderr.writeln('❌ --logo file not found: $logoPath');
      return 1;
    }
    source.copySync(logoFile.path);
  } else {
    logoFile.writeAsBytesSync(base64Decode(_placeholderPngBase64));
    logoIsPlaceholder = true;
  }

  final tenantBlock =
      '''
    $id:
      name: "$name"

      android:
        application_id: "$bundleId"
        app_name: "$name"

      ios:
        bundle_id: "$bundleId"
        app_name: "$name"

      assets:
        logo: "tenants/$id/assets/logo.png"

''';

  final tenantsMarker = RegExp(r'^  tenants:\r?\n', multiLine: true);
  final RegExpMatch? match = tenantsMarker.firstMatch(originalYaml);
  if (match == null) {
    Directory(p.join('tenants', id)).deleteSync(recursive: true);
    stderr.writeln(
      '❌ white_label.yaml has no `  tenants:` key — malformed file, refusing to guess where to insert.',
    );
    return 1;
  }
  String updatedYaml = originalYaml.replaceRange(
    match.end,
    match.end,
    tenantBlock,
  );

  if (makeDefault) {
    updatedYaml = updatedYaml.replaceFirstMapped(
      RegExp(r'^  default_tenant:.*$', multiLine: true),
      (_) => '  default_tenant: $id',
    );
  }

  whiteLabelFile.writeAsStringSync(updatedYaml);

  // Validate before declaring success — roll back both the yaml edit and
  // the created folder if the result is somehow invalid, rather than
  // leaving a half-added tenant behind.
  try {
    WhiteLabelConfig.load(Directory.current.path);
  } on WhiteLabelConfigException catch (e) {
    whiteLabelFile.writeAsStringSync(originalYaml);
    Directory(p.join('tenants', id)).deleteSync(recursive: true);
    stderr.writeln(
      '❌ Adding tenant "$id" produced an invalid config — rolled back.',
    );
    stderr.writeln(e);
    return 1;
  }

  stdout.writeln('✅ Added tenant "$id" ($name) to white_label.yaml');
  stdout.writeln(
    '✅ Created ${logoFile.path}${logoIsPlaceholder ? ' (placeholder — replace with the real logo)' : ''}',
  );
  if (makeDefault) {
    stdout.writeln('✅ Set "$id" as default_tenant');
  }
  stdout.writeln();
  stdout.writeln('Next: dart run white_label_kit:build --tenant $id');
  return 0;
}

const _starterWhiteLabelYaml = '''
# Generic white-label config — see docs/white_label_flavors.md.
# Run `dart run white_label_kit:validate` after editing this file.
white_label:
  default_tenant: acme

  tenants:
    acme:
      name: "Acme"

      android:
        application_id: "com.example.acme"
        app_name: "Acme"

      ios:
        bundle_id: "com.example.acme"
        app_name: "Acme"

      assets:
        logo: "tenants/acme/assets/logo.png"
        # icon: "tenants/acme/assets/icon.png"
        # splash: "tenants/acme/assets/splash.png"

      # theme:
      #   primary_color: "#3366FF"
      #   secondary_color: "#00C2A8"

      # environment:
      #   api_base_url: "https://api.example.com"

      # features:
      #   some_feature_flag: true
''';

/// A minimal-but-genuinely-valid 1x1 PNG (base64), used by `init --example`
/// so `validate`/`build` have a real image file to find — not a fake
/// "looks like an image" text file that would confuse an actual asset
/// pipeline (icon generators, image codecs) if someone forgot to replace it.
const _placeholderPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

/// The generic white_label.yaml build path.
///
/// Usage: `build --tenant <id> [--platform ..] [--mode ..] [--dry-run] [--verbose] [--clean]`
///
/// Stages the resolved tenant's assets into an isolated `.generated/<tenant>` directory.
Future<int> _genericBuild(List<String> args) async {
  String? tenantId;
  var platform = 'android';
  var mode = 'debug';
  var dryRun = false;
  var verbose = false;
  var clean = false;
  var stageOnly = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tenant':
        if (i + 1 >= args.length) {
          stderr.writeln('❌ --tenant requires a value.');
          return 1;
        }
        tenantId = args[++i];
      case '--platform':
        if (i + 1 >= args.length) {
          stderr.writeln('❌ --platform requires a value.');
          return 1;
        }
        platform = args[++i];
      case '--mode':
        if (i + 1 >= args.length) {
          stderr.writeln('❌ --mode requires a value.');
          return 1;
        }
        mode = args[++i];
      case '--dry-run':
        dryRun = true;
      case '--verbose':
        verbose = true;
      case '--clean':
        clean = true;
      case '--stage-only':
        stageOnly = true;
      default:
        stderr.writeln('❌ Unknown flag for `build`: ${args[i]}');
        return 1;
    }
  }

  const validPlatforms = {'android', 'android-aab', 'ios', 'all'};
  if (!validPlatforms.contains(platform)) {
    stderr.writeln(
      '❌ --platform must be one of ${validPlatforms.join('|')}, got "$platform".',
    );
    return 1;
  }
  const validModes = {'debug', 'release'};
  if (!validModes.contains(mode)) {
    stderr.writeln(
      '❌ --mode must be one of ${validModes.join('|')}, got "$mode".',
    );
    return 1;
  }

  final stager = TenantStager(Directory.current.path);

  if (clean) {
    if (tenantId == null) {
      stderr.writeln('❌ --clean requires --tenant <id>.');
      return 1;
    }
    stager.clean(tenantId);
    stdout.writeln('🧹 Cleaned staging output for tenant "$tenantId".');
    return 0;
  }

  final WhiteLabelConfig? config = _tryLoadWhiteLabelConfig();
  if (config == null) {
    return 1;
  }

  final TenantConfig tenant;
  try {
    tenant = config.resolve(tenantId);
  } on ArgumentError catch (e) {
    stderr.writeln('❌ ${e.message}');
    // Failure safety: never leave stale staging output behind, even though
    // nothing was staged yet in this particular failure — cheap and
    // consistent with every other failure path below.
    if (tenantId != null) {
      stager.clean(tenantId);
    }
    return 1;
  }

  stdout.writeln('Building tenant: ${tenant.id} (${tenant.name})');
  stdout.writeln('Platform: $platform');
  stdout.writeln('Mode: $mode');
  if (verbose) {
    stdout.writeln('  Android application id: ${tenant.android.applicationId}');
    stdout.writeln('  iOS bundle id: ${tenant.ios.bundleId}');
    stdout.writeln('  Declared assets: ${tenant.assets.all.join(', ')}');
  }

  if (dryRun) {
    stdout.writeln(
      '(dry run — config resolved and printed above, no staging performed)',
    );
    return 0;
  }

  try {
    final String stagedPath = stager.stage(tenant);
    stdout.writeln('Staged assets at: $stagedPath');
  } catch (e) {
    stderr.writeln('❌ Build failed while staging tenant "${tenant.id}": $e');
    stager.clean(tenant.id);
    stdout.writeln(
      '🧹 Cleaned partial staging output for tenant "${tenant.id}".',
    );
    return 1;
  }

  if (stageOnly) {
    stdout.writeln(
      '(--stage-only — staged assets only, no real `flutter build` invoked. '
      'Use this from a pre-build hook, e.g. tool/select_tenant.sh, that '
      'still needs to copy the staged files into a pubspec-declared asset '
      'path before invoking `flutter build` itself.)',
    );
    return 0;
  }

  // Build Android, iOS, or both — all fully wired as of v0.2.0.
  // Version flags (--build-name / --build-number) always come from the
  // tenant's white_label.yaml version declaration, not pubspec.yaml — each
  // tenant is an independent store listing with its own release history.
  // iOS device builds still need code-signing set up externally; this layer
  // handles the Xcode project configuration (generateIosConfig) but cannot
  // and should not manage provisioning profiles or signing certificates.
  var overallExitCode = 0;
  final String projectRoot = Directory.current.path;

  if (platform == 'android' || platform == 'android-aab' || platform == 'all') {
    // ── Android ─────────────────────────────────────────────────────────────
    try {
      generateAndroidFlavor(tenant, projectRoot: projectRoot);
      stdout.writeln(
        '✅ Android: Gradle flavor "${tenant.id}" ensured in '
        'android/app/build.gradle.kts.',
      );
    } on StateError catch (e) {
      stderr.writeln('❌ Android config failed for "${tenant.id}": $e');
      return 1;
    }

    final buildCommand = platform == 'android-aab' ? 'appbundle' : 'apk';
    final TenantVersion androidVersion = tenant.androidVersion;
    final List<String> androidArgs = [
      'build',
      buildCommand,
      '--flavor',
      tenant.id,
      '--dart-define=TENANT_ID=${tenant.id}',
      '--build-name',
      androidVersion.name,
      '--build-number',
      '${androidVersion.buildNumber}',
      if (mode == 'release') '--release' else '--debug',
    ];

    stdout.writeln('➜ flutter ${androidArgs.join(' ')}');
    final Process androidProcess = await Process.start(
      'flutter',
      androidArgs,
      workingDirectory: projectRoot,
      mode: ProcessStartMode.inheritStdio,
    );
    final int androidExitCode = await androidProcess.exitCode;
    if (androidExitCode != 0) {
      stderr.writeln(
        '❌ flutter build android failed for "${tenant.id}" '
        '(exit code $androidExitCode).',
      );
      if (platform != 'all') {
        return androidExitCode;
      }
      overallExitCode = androidExitCode;
    } else {
      final String? artifactPath = _findBuiltArtifact(
        tenantId: tenant.id,
        buildCommand: buildCommand,
        mode: mode,
      );
      if (artifactPath == null) {
        stderr.writeln(
          '❌ flutter build reported success but no '
          'build/app/outputs artifact '
          '"app-${tenant.id}-$mode.${buildCommand == 'appbundle' ? 'aab' : 'apk'}" '
          'found for "${tenant.id}".',
        );
        if (platform != 'all') {
          return 1;
        }
        overallExitCode = 1;
      } else {
        final int sizeBytes = File(artifactPath).lengthSync();
        final String sizeMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(2);
        stdout.writeln('✅ Android artifact: $artifactPath ($sizeMb MB)');
      }
    }
  }

  if (platform == 'ios' || platform == 'all') {
    // ── iOS ──────────────────────────────────────────────────────────────────
    // Xcode project configuration first — idempotent, safe to re-run.
    final xcodeprojDir = Directory(
      p.join(projectRoot, 'ios', 'Runner.xcodeproj'),
    );
    if (!xcodeprojDir.existsSync()) {
      stderr.writeln(
        '❌ iOS: No ios/Runner.xcodeproj found — iOS platform is not '
        'set up in this project. Run `flutter create --platforms=ios .` first.',
      );
      if (platform != 'all') {
        return 1;
      }
      overallExitCode = 1;
    } else {
      try {
        generateIosConfig(tenant, projectRoot: projectRoot);
        stdout.writeln(
          '✅ iOS: Xcode build configs + scheme ensured for "${tenant.id}".',
        );
      } on IosGenerationException catch (e) {
        stderr.writeln('❌ iOS config failed for "${tenant.id}": ${e.message}');
        stderr.writeln(
          '   Install Ruby + xcodeproj gem: gem install xcodeproj',
        );
        if (platform != 'all') {
          return 1;
        }
        overallExitCode = 1;
      }

      if (overallExitCode == 0 || platform == 'all') {
        final TenantVersion iosVersion = tenant.iosVersion;
        final List<String> iosArgs = [
          'build',
          'ipa',
          '--flavor', tenant.id,
          '--dart-define=TENANT_ID=${tenant.id}',
          '--build-name', iosVersion.name,
          '--build-number', '${iosVersion.buildNumber}',
          if (mode == 'release') '--release' else '--debug',
          // Signing: no-codesign for debug / CI; release signing is the
          // developer's responsibility — this package never touches certs.
          if (mode != 'release') '--no-codesign',
        ];

        stdout.writeln('➜ flutter ${iosArgs.join(' ')}');
        final Process iosProcess = await Process.start(
          'flutter',
          iosArgs,
          workingDirectory: projectRoot,
          mode: ProcessStartMode.inheritStdio,
        );
        final int iosExitCode = await iosProcess.exitCode;
        if (iosExitCode != 0) {
          stderr.writeln(
            '❌ flutter build ios failed for "${tenant.id}" '
            '(exit code $iosExitCode).',
          );
          overallExitCode = iosExitCode;
        } else {
          stdout.writeln(
            '✅ iOS build complete for "${tenant.id}" '
            '(see build/ios/ipa/).',
          );
        }
      }
    }
  }

  return overallExitCode;
}

/// Searches `build/app/outputs/` (recursively — the exact subdirectory
/// depends on the Android Gradle Plugin version and whether it's an APK or
/// App Bundle output) for the artifact `flutter build` should have just
/// produced for [tenantId]/[mode]. Returns `null` if not found, so the
/// caller can report a real "no artifact on disk" failure instead of
/// trusting `flutter build`'s exit code alone.
String? _findBuiltArtifact({
  required String tenantId,
  required String buildCommand,
  required String mode,
}) {
  final ext = buildCommand == 'appbundle' ? 'aab' : 'apk';
  final expectedName = 'app-$tenantId-$mode.$ext';
  final outputsDir = Directory(
    p.join(Directory.current.path, 'build', 'app', 'outputs'),
  );
  if (!outputsDir.existsSync()) {
    return null;
  }
  for (final FileSystemEntity entity in outputsDir.listSync(recursive: true)) {
    if (entity is File && p.basename(entity.path) == expectedName) {
      return entity.path;
    }
  }
  return null;
}

/// Resolves and stages a tenant in debug mode.
///
/// Usage: `run [--tenant <id>]`
Future<int> _run(List<String> args) async {
  String? tenantId;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tenant':
        if (i + 1 >= args.length) {
          stderr.writeln('❌ --tenant requires a value.');
          return 1;
        }
        tenantId = args[++i];
      default:
        stderr.writeln('❌ Unknown flag for `run`: ${args[i]}');
        return 1;
    }
  }

  final WhiteLabelConfig? config = _tryLoadWhiteLabelConfig();
  if (config == null) {
    return 1;
  }

  final stager = TenantStager(Directory.current.path);

  final TenantConfig tenant;
  try {
    tenant = config.resolve(tenantId);
  } on ArgumentError catch (e) {
    stderr.writeln('❌ ${e.message}');
    if (tenantId != null) {
      stager.clean(tenantId);
    }
    return 1;
  }

  stdout.writeln(
    'Would launch `flutter run` for tenant: ${tenant.id} (${tenant.name})',
  );

  try {
    final String stagedPath = stager.stage(tenant);
    stdout.writeln('Staged assets at: $stagedPath');
  } catch (e) {
    stderr.writeln('❌ Failed to stage tenant "${tenant.id}": $e');
    stager.clean(tenant.id);
    return 1;
  }

  stdout.writeln();
  stdout.writeln(
    'This command only PREPARES the tenant — it does not invoke `flutter '
    'run` itself (interactive/long-running; the wrong thing for a script '
    'to launch on your behalf). Run this yourself:',
  );
  stdout.writeln();
  stdout.writeln(
    '  flutter run --flavor ${tenant.id} --dart-define=TENANT_ID=${tenant.id}',
  );
  stdout.writeln();
  return 0;
}

/// The configuration setup command.
///
/// Usage: `configure [--tenant <id>] [--platform android|ios|all] [--dry-run] [--skip-generate] [--verbose]`
///
/// Patches Android `build.gradle.kts` and the iOS Xcode project for every declared tenant
/// so that `flutter build --flavor <id>` just works without any manual file editing.
///
/// What it does, in order, for each tenant:
///  1. [generateAndroidFlavor] — idempotent productFlavors block in
///     `android/app/build.gradle.kts`.
///  2. [generateIosConfig] — idempotent Xcode build configurations + scheme
///     in `ios/Runner.xcodeproj` (skipped silently when no xcodeproj exists;
///     requires Ruby + the `xcodeproj` gem).
///  3. Regenerates `lib/white_label.g.dart` for `default_tenant` — same as
///     `dart run white_label_kit:generate` with no flags.
///
/// All steps are fully idempotent: running `configure` a second time
/// over an already-configured project is always a no-op (or a re-sync that
/// applies any value changes), never a duplicate or a conflict.
Future<int> _configureTenants(List<String> args) async {
  String? tenantId;
  var platform = 'all';
  var dryRun = false;
  var skipGenerate = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tenant':
        if (i + 1 >= args.length) {
          stderr.writeln('❌ --tenant requires a value.');
          return 1;
        }
        tenantId = args[++i];
      case '--platform':
        if (i + 1 >= args.length) {
          stderr.writeln('❌ --platform requires a value.');
          return 1;
        }
        platform = args[++i];
      case '--dry-run':
        dryRun = true;
      case '--skip-generate':
        skipGenerate = true;
      case '--verbose':
        // Accepted for compatibility
        break;
      default:
        stderr.writeln('❌ Unknown flag for `configure`: ${args[i]}');
        return 1;
    }
  }

  const validPlatforms = {'android', 'ios', 'all'};
  if (!validPlatforms.contains(platform)) {
    stderr.writeln(
      '❌ --platform must be one of ${validPlatforms.join('|')}, '
      'got "$platform".',
    );
    return 1;
  }

  final WhiteLabelConfig? config = _tryLoadWhiteLabelConfig();
  if (config == null) {
    return 1;
  }

  final List<TenantConfig> tenants;
  if (tenantId != null) {
    if (!config.has(tenantId)) {
      stderr.writeln('❌ No such tenant "$tenantId" in white_label.yaml.');
      return 1;
    }
    tenants = [config[tenantId]];
  } else {
    tenants = [
      for (final id in config.tenants.keys.toList()..sort()) config[id],
    ];
  }

  final String projectRoot = Directory.current.path;
  stdout.writeln(
    '🔧 Configuring ${tenants.length} tenant(s): '
    '${tenants.map((t) => t.id).join(', ')}',
  );
  stdout.writeln('   Platform: $platform');
  if (dryRun) {
    stdout.writeln('   (dry run — no changes will be made)');
  }
  stdout.writeln();

  var overallSuccess = true;

  for (final tenant in tenants) {
    stdout.writeln('📦 ${tenant.id} — ${tenant.name}');

    // ── Android ─────────────────────────────────────────────────────────────
    if (platform == 'android' || platform == 'all') {
      if (dryRun) {
        stdout.writeln(
          '   [dry-run] Would patch android/app/build.gradle.kts '
          'with flavor "${tenant.id}"',
        );
      } else {
        try {
          generateAndroidFlavor(tenant, projectRoot: projectRoot);
          stdout.writeln(
            '   ✅ Android: Gradle flavor "${tenant.id}" configured '
            'in android/app/build.gradle.kts',
          );
        } on StateError catch (e) {
          stderr.writeln('   ❌ Android config failed for "${tenant.id}": $e');
          overallSuccess = false;
        }
      }
    }

    // ── iOS ──────────────────────────────────────────────────────────────────
    if (platform == 'ios' || platform == 'all') {
      final xcodeprojDir = Directory(
        p.join(projectRoot, 'ios', 'Runner.xcodeproj'),
      );
      if (!xcodeprojDir.existsSync()) {
        if (platform == 'ios') {
          stderr.writeln(
            '   ❌ iOS: No ios/Runner.xcodeproj found. '
            'Run `flutter create --platforms=ios .` first.',
          );
          overallSuccess = false;
        } else {
          stdout.writeln(
            '   ℹ️  iOS: No ios/Runner.xcodeproj — skipping '
            '(Android-only project or not yet created).',
          );
        }
      } else if (dryRun) {
        stdout.writeln(
          '   [dry-run] Would add Xcode build configs + scheme '
          'for "${tenant.id}"',
        );
      } else {
        try {
          generateIosConfig(tenant, projectRoot: projectRoot);
          stdout.writeln(
            '   ✅ iOS: Xcode build configs + scheme configured '
            'for "${tenant.id}"',
          );
        } on IosGenerationException catch (e) {
          stderr.writeln(
            '   ❌ iOS config failed for "${tenant.id}": ${e.message}',
          );
          stderr.writeln('      Fix: gem install xcodeproj  (requires Ruby)');
          overallSuccess = false;
        }
      }
    }

    // ── IDE (VS Code + Android Studio / IntelliJ) ───────────────────────────
    if (!dryRun) {
      try {
        IdeGenerator.generate(tenant, projectRoot: projectRoot);
        stdout.writeln(
          '   ✅ IDE: Android Studio & VS Code run configurations '
          'configured for "${tenant.id}"',
        );
      } catch (e) {
        stderr.writeln('   ⚠️  IDE config generation encountered an error: $e');
      }
    }

    stdout.writeln();
  }

  // ── Dart generate ────────────────────────────────────────────────────────
  if (!skipGenerate && !dryRun) {
    stdout.writeln(
      '🔄 Regenerating lib/white_label.g.dart '
      'for tenant "${config.defaultTenant}"...',
    );
    final int generateExitCode = _generate(['--tenant', config.defaultTenant]);
    if (generateExitCode != 0) {
      stderr.writeln('❌ Failed to regenerate lib/white_label.g.dart');
      overallSuccess = false;
    }
    stdout.writeln();
  }

  if (overallSuccess) {
    stdout.writeln('✅ Configuration complete!');
    stdout.writeln();
    stdout.writeln('You can now build without any manual native-file editing:');
    for (final tenant in tenants) {
      stdout.writeln(
        '  dart run white_label_kit:build --tenant ${tenant.id} '
        '--platform android --mode release',
      );
    }
    stdout.writeln();
    stdout.writeln(
      'Or call flutter directly — white_label_kit already patched the '
      'native files for you:',
    );
    for (final tenant in tenants) {
      stdout.writeln(
        '  flutter build apk --flavor ${tenant.id} '
        '--dart-define=TENANT_ID=${tenant.id}',
      );
    }
  } else {
    stdout.writeln(
      '⚠️  Configuration completed with errors — see above for details.',
    );
  }
  return overallSuccess ? 0 : 1;
}

/// Reads `white_label_kit.yaml` from the current directory, if present.
/// Missing file is fine — every command still works with plain CLI args,
/// same as before this existed.
Map<String, String> _loadConfig() {
  final file = File(_defaultConfigFile);
  if (!file.existsSync()) {
    return const {};
  }

  final dynamic doc = loadYaml(file.readAsStringSync());
  if (doc is! Map) {
    stderr.writeln(
      "⚠️  $_defaultConfigFile doesn't look like a map at the top level — ignoring it.",
    );
    return const {};
  }

  return {
    for (final entry in doc.entries)
      entry.key.toString(): entry.value.toString(),
  };
}

/// Fills in whatever positional args the user didn't type from the YAML
/// config, for the subcommands that need a tenant id/display name/bundle id.
/// Anything the user *did* type on the command line is left untouched —
/// explicit CLI args always win.
List<String> _resolveArgs(
  String command,
  List<String> rest,
  Map<String, String> config,
) {
  if (config.isEmpty) {
    return rest;
  }

  switch (command) {
    case 'add':
      final resolved = [...rest];
      final fields = ['tenant_id', 'display_name', 'bundle_id', 'api_base_url'];
      for (int i = resolved.length; i < fields.length; i++) {
        final String? value = config[fields[i]];
        if (value == null) {
          break; // stop at the first missing field, don't leave gaps
        }
        resolved.add(value);
      }
      return resolved;
    case 'doctor':
    case 'build':
      // First positional arg is the tenant id for both; only fill it in if
      // the user didn't pass one (flags like --strict/--json/--platform
      // don't count as the tenant id).
      final bool hasTenantId = rest.isNotEmpty && !rest.first.startsWith('-');
      if (hasTenantId) {
        return rest;
      }
      final String? tenantId = config['tenant_id'];
      if (tenantId == null) {
        return rest;
      }
      return [tenantId, ...rest];
    default:
      return rest;
  }
}

void _printUsage() {
  stdout.writeln('''
white_label_kit CLI — unified entry point for multi-tenant white-label management.
Run from the app's repo root. Exit code: 0 on success, 1 on any failure
(missing/invalid config, unknown tenant, unknown flag, etc.) — plain
deterministic text only, no ANSI spinners, safe to parse in CI.

Usage: dart run white_label_kit:white_label <command> [args...]
   or, once activated globally: tenant <command> [args...]

LEGACY COMMANDS (wrapped for backward compatibility):

  add [id] ["<Name>"] [bundleId] [apiBaseUrl]  Onboard a new tenant.
                                                Exit 1 if the forwarded
                                                script fails.
  doctor [id] [--all] [--json] [--strict]      Health-check a tenant.
                                                Exit 1 on any failed check
                                                (with --strict) or script
                                                failure.
  build [id] [--platform android|ios] [--mode debug|profile|release]
                                                Build a tenant. Exit 1 on
                                                build failure.
                                                (See GENERIC BUILD below —
                                                same command name, routed
                                                by which files exist in the
                                                current directory.)
  auto-onboard [id] [--dry-run]                Chain add + Xcode wiring +
                                                scheme clone + icons + splash
                                                for a tenant that only has
                                                tenant.yaml + logo.png so far.
                                                Standalone for now — not
                                                called from `build` yet.
                                                Exit 1 on any step failure.

GENERIC white_label.yaml COMMANDS (repo-agnostic — no dependency on this
repo's tenants/ + tool/ folder layout; see lib/src/config, lib/src/generation):

  init [--example] [--force] [--path <dir>]    Scaffold a starter
                                                white_label.yaml (one
                                                example tenant "acme").
                                                --path <dir>   Target
                                                  directory (default: cwd).
                                                  Must contain a
                                                  pubspec.yaml with a
                                                  `flutter:` key.
                                                --example      Also write a
                                                  placeholder
                                                  tenants/acme/assets/logo.png
                                                  so validate/build work
                                                  immediately.
                                                --force        Overwrite an
                                                  existing white_label.yaml.
                                                  Without it: exit 1, file
                                                  is NEVER silently
                                                  overwritten.
                                                Exit 1 if not a Flutter
                                                project, or if
                                                white_label.yaml already
                                                exists without --force.

  configure [--tenant <id>] [--platform android|ios|all]
            [--dry-run] [--skip-generate] [--verbose]
                                                THE zero-touch setup command —
                                                equivalent to
                                                `dart run flutter_flavorizr`
                                                for white_label.yaml. Patches
                                                Android build.gradle.kts and
                                                the iOS Xcode project for
                                                every declared tenant (or one
                                                named tenant) so that
                                                `flutter build --flavor <id>`
                                                works immediately without any
                                                manual native-file editing.
                                                Re-generates
                                                lib/white_label.g.dart at the
                                                end. All steps are idempotent.
                                                --tenant <id>  Configure only
                                                  this tenant (default: all).
                                                --platform     android|ios|all
                                                  (default: all).
                                                --dry-run      Print what
                                                  would happen, change
                                                  nothing.
                                                --skip-generate
                                                  Skip the final
                                                  `generate` step.
                                                Exit 1 on any Android
                                                Gradle or iOS Xcode config
                                                failure.

  add-tenant <id> "<Name>" <bundleId>           Add a tenant WITHOUT hand-
    [--logo <path>] [--default]                 editing white_label.yaml or
                                                mkdir-ing a tenants/<id>/
                                                folder yourself — both are
                                                generated. --logo copies a
                                                real file in; omitted, a
                                                placeholder PNG is written
                                                (replace before shipping).
                                                --default also updates
                                                default_tenant. Rolls back
                                                the yaml edit AND the
                                                created folder if the result
                                                doesn't validate. Exit 1 on
                                                invalid id/bundleId, missing
                                                white_label.yaml, duplicate
                                                tenant id, or --logo file
                                                not found.

  remove-tenant <id> [--keep-assets]            Remove a tenant from
                                                white_label.yaml, clean its
                                                tenants/<id>/ folder, remove
                                                its Android Gradle flavor and
                                                iOS Xcode configs/schemes, and
                                                regenerate lib/white_label.g.dart.

  validate                                     Load + validate
                                                white_label.yaml. Prints
                                                every collected error (not
                                                just the first) on failure
                                                — never a raw stack trace.
                                                Exit 0 if valid, 1 if not
                                                (including "file not
                                                found").

  list                                         List every tenant declared
                                                in white_label.yaml, with a
                                                top "Default tenant: <id>"
                                                line plus a per-tenant
                                                "(default)" marker.
                                                Exit 1 if config invalid.

  build --tenant <id> [--platform android|ios|all] [--mode debug|release]
        [--dry-run] [--verbose] [--clean]      GENERIC build: resolves the
                                                tenant (--tenant, else the
                                                declared default_tenant —
                                                never an arbitrary guess)
                                                and stages its assets into
                                                an isolated
                                                .generated/<tenant>/
                                                directory, patches native
                                                project files (Android
                                                build.gradle.kts; iOS Xcode
                                                project if present), then
                                                invokes `flutter build`.
                                                Version (--build-name,
                                                --build-number) is read from
                                                white_label.yaml — pubspec
                                                version is not touched.
                                                --tenant <id>  Which tenant
                                                  to build (default: the
                                                  configured default).
                                                --platform     android|
                                                  android-aab|ios|all
                                                  (default: android). ios
                                                  and all are fully wired
                                                  as of v0.2.0.
                                                --mode         debug|release
                                                  (default: debug).
                                                --dry-run      Resolve +
                                                  print, skip staging.
                                                --verbose      Print
                                                  applicationId, bundle id,
                                                  and declared asset list.
                                                --clean        Remove
                                                  .generated/<tenant> and
                                                  exit — no staging.
                                                  Requires --tenant.
                                                On ANY failure, staging
                                                output for the tenant is
                                                cleaned up before exiting
                                                non-zero — never leaves a
                                                stale .generated/<tenant>
                                                behind. Exit 1 on invalid
                                                config, unknown tenant, or
                                                a staging failure (e.g. a
                                                declared asset file missing
                                                on disk).
                                                NOTE: this is the SAME
                                                command name as the
                                                host-app `build` above —
                                                see the routing comment in
                                                bin/white_label.dart's main().
                                                It only runs when
                                                white_label.yaml exists AND
                                                tool/build_runner.dart does
                                                not; otherwise the host-app
                                                `build` above runs as
                                                always.

  run [--tenant <id>]                          Resolves + stages a tenant
                                                (same resolution + staging
                                                as `build`, debug mode) but
                                                does NOT invoke `flutter
                                                run` itself — that's
                                                interactive/long-running,
                                                the wrong thing for a
                                                script to launch for you.
                                                Prints the exact
                                                `flutter run --flavor <id> ...`
                                                command to copy-paste.
                                                Exit 1 on invalid config or
                                                unknown tenant.

  help                                         Show this message. Exit 0
                                                (exit 1 if no command was
                                                given at all).

Examples:
  # Multi-tenant management
  dart run white_label_kit:white_label add acmecorp "Acme Corp" com.example.acmecorp
  dart run white_label_kit:white_label doctor acme
  dart run white_label_kit:build acme --platform android --mode release
  dart run white_label_kit:white_label auto-onboard acmecorp

  # Generic white_label.yaml layer — zero-touch (any Flutter project)
  dart run white_label_kit:init --example
  dart run white_label_kit:add-tenant acme "Acme Corp" com.acme.student
  dart run white_label_kit:configure           # ← patches Gradle + Xcode + icons + splash
  dart run white_label_kit:build --tenant acme --platform android --mode release
  dart run white_label_kit:build --tenant acme --platform ios --mode debug
  dart run white_label_kit:build --tenant acme --platform all --mode release

  # Or call flutter directly after configure — native files already patched
  flutter build apk --flavor acme --dart-define=TENANT_ID=acme
  flutter build ipa --flavor acme --dart-define=TENANT_ID=acme --no-codesign

  # Dry-run to see what configure would change without touching files
  dart run white_label_kit:configure --dry-run --verbose

YAML config (optional, like flutter_native_splash/icons_launcher): drop a
white_label_kit.yaml in the repo root and omit matching CLI args —
  tenant_id: acmecollege
  display_name: Acme College
  bundle_id: com.acmecollege.student
  api_base_url: https://api.acmecollege.com   # optional
then just: dart run white_label_kit:white_label add
       or: dart run white_label_kit:white_label doctor
(This applies to the host-app `add`/`doctor`/`build` commands only — the
generic white_label.yaml layer's own config lives in white_label.yaml
itself and doesn't read white_label_kit.yaml.)

Day-to-day Android release builds: keep using ./build.sh — it's a thin
wrapper around the same host-app "build" command for one-click use.
''');
}
