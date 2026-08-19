import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'validation_result.dart';

/// Every structural/field-level rule `white_label.yaml` must satisfy.
/// Deliberately static/stateless functions, not a class you instantiate —
/// there's no config to hold, and it keeps every rule independently
/// unit-testable (see test/config_validator_test.dart).
abstract final class ConfigValidator {
  /// Gradle product-flavor names (which a tenant id doubles as — it's also
  /// the Flutter `--flavor` value) can't start with a digit or contain
  /// anything but letters/digits/underscore, and Gradle reserves the `test`
  /// prefix for its own generated test variants.
  static ValidationResult tenantId(String id) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
      return Invalid(
        'Tenant id "$id" must be lowercase, start with a letter, and contain '
        'only letters/digits/underscore (it doubles as the Android/iOS '
        'flavor name).',
      );
    }
    if (id.startsWith('test')) {
      return const Invalid(
        'Tenant id must not start with "test" — reserved by Gradle for its '
        'own generated test build variants and will fail to build.',
      );
    }
    return const Valid();
  }

  /// A Java/Kotlin package name: dot-separated identifiers, each starting
  /// with a letter. This is what Android's `applicationId` actually is.
  static ValidationResult androidApplicationId(String value) {
    final List<String> segments = value.split('.');
    final bool ok =
        segments.length >= 2 &&
        segments.every((s) => RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(s));
    if (!ok) {
      return Invalid(
        'Invalid Android applicationId "$value". Expected reverse-DNS form '
        'like com.company.appname (letters/digits/underscore per segment, '
        'at least two segments).',
      );
    }
    return const Valid();
  }

  /// iOS bundle identifiers allow hyphens in addition to what Android
  /// allows — they are NOT the same grammar, this is a separate rule on
  /// purpose (a common bug in hand-rolled white-label tooling is reusing
  /// the Android regex for iOS and rejecting valid bundle ids like
  /// `com.company.app-name`).
  static ValidationResult iosBundleId(String value) {
    final List<String> segments = value.split('.');
    final bool ok =
        segments.length >= 2 &&
        segments.every((s) => RegExp(r'^[a-zA-Z][a-zA-Z0-9-]*$').hasMatch(s));
    if (!ok) {
      return Invalid(
        'Invalid iOS bundle id "$value". Expected reverse-DNS form like '
        'com.company.appname (letters/digits/hyphen per segment, at least '
        'two segments).',
      );
    }
    return const Valid();
  }

  /// `MAJOR.MINOR.PATCH` — matches what Android's `versionName` / iOS's
  /// `CFBundleShortVersionString` and Flutter's own `--build-name` expect.
  /// Deliberately doesn't accept pre-release/build-metadata suffixes
  /// (`-beta.1`, `+abc`) — those aren't meaningful to either app store's
  /// version field and Flutter's `--build-name` doesn't accept `+` either
  /// (it's reserved for separating name from build number).
  static ValidationResult semanticVersion(String value) {
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value)) {
      return Invalid(
        'Invalid version "$value". Expected MAJOR.MINOR.PATCH, e.g. "1.2.0".',
      );
    }
    return const Valid();
  }

  /// Android `versionCode` / iOS `CFBundleVersion` — both require a
  /// positive integer that a store expects to keep increasing release over
  /// release (this package validates the shape, not the monotonic-increase
  /// rule itself — it has no way to know a tenant's prior release history).
  static ValidationResult buildNumber(int value) {
    if (value <= 0) {
      return Invalid(
        'Invalid build number $value. Expected a positive integer.',
      );
    }
    return const Valid();
  }

  /// Validates that [value] is a `#RRGGBB` or `#AARRGGBB` hex color string.
  static ValidationResult colorHex(String value) {
    if (!RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(value)) {
      return Invalid('Invalid color "$value". Expected #RRGGBB or #AARRGGBB.');
    }
    return const Valid();
  }

  /// Validates that [value] is an absolute `http`/`https` URL.
  static ValidationResult url(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.isAbsolute ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return Invalid('Invalid URL "$value". Expected an absolute http(s) URL.');
    }
    return const Valid();
  }

  /// Rejects absolute paths and any `..` segment — a tenant asset path in
  /// YAML must resolve to somewhere inside that tenant's own directory, so
  /// one tenant's config can never point at (or overwrite, during staging)
  /// another tenant's files or anything outside `tenants/`. This is a
  /// security rule, not just a style rule — see README's Security section.
  ///
  /// When [projectRoot] is given, also checks the file actually exists at
  /// `tenants/<tenantId>/<path>`; omit it to validate shape only (e.g. when
  /// validating a config template before tenant directories exist).
  static ValidationResult assetPath(
    String value, {
    required String tenantId,
    String? projectRoot,
  }) {
    if (p.isAbsolute(value)) {
      return Invalid('Asset path "$value" must be relative, not absolute.');
    }
    if (p.split(value).contains('..')) {
      return Invalid(
        'Asset path "$value" must not contain ".." — tenant assets cannot '
        'reference files outside their own tenant directory.',
      );
    }
    final expectedPrefix = 'tenants/$tenantId/';
    if (!value.startsWith(expectedPrefix)) {
      return Invalid(
        'Asset path "$value" for tenant "$tenantId" must live under '
        "$expectedPrefix — pointing at another tenant's directory (or "
        'anywhere else) is not allowed.',
      );
    }
    if (projectRoot != null) {
      final file = File(p.join(projectRoot, value));
      if (!file.existsSync()) {
        return Invalid('Asset file not found: $value');
      }
      // Defense against a symlink placed INSIDE the tenant's own asset
      // directory that points OUTSIDE the tenant tree — the string checks
      // above only look at the declared path, not what it actually
      // resolves to on disk. Found by an adversarial audit: a tenant asset
      // that's a symlink escaping tenants/<id>/ was staged/validated
      // without rejection, a real bypass of "never anything outside
      // tenants/<id>/" even though it requires filesystem write access to
      // the tenant's own directory (not reachable via white_label.yaml
      // content alone).
      final String realPath = file.resolveSymbolicLinksSync();
      final String tenantRoot = Directory(p.join(projectRoot, 'tenants', tenantId))
          .resolveSymbolicLinksSync();
      if (!p.isWithin(tenantRoot, realPath) && realPath != tenantRoot) {
        return Invalid(
          'Asset path "$value" is a symlink (or contains one) that resolves '
          'outside tenant "$tenantId"\'s own directory — not allowed, even '
          'though the declared path itself looks valid.',
        );
      }
    }
    return const Valid();
  }

  /// Returns the node as a [YamlMap]/[Map], or records an error and returns
  /// `null` if it's present-but-wrong-type or the parent required it and
  /// it's missing entirely. Centralizes the "is this actually a map"
  /// dynamic-type check so parsers elsewhere don't each repeat their own
  /// `is! Map` handling with slightly different wording.
  static Map<dynamic, dynamic>? expectMap(
    dynamic node,
    String path,
    List<String> errors,
  ) {
    if (node == null) {
      return null;
    }
    if (node is YamlMap || node is Map) {
      return node as Map;
    }
    errors.add('Expected "$path" to be a map, got: $node');
    return null;
  }
}
