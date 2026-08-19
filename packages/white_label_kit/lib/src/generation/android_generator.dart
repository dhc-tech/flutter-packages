import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/tenant_config.dart';

/// Generates (idempotently) the Android Gradle `productFlavors` wiring for
/// [tenant] inside `<projectRoot>/android/app/build.gradle.kts`.
///
/// This is a generic, repo-agnostic reimplementation of the same *idea* as
/// this repo's own `tenants/add_flavor.dart` Android step (a marker-comment
/// insert into `productFlavors { }`) — read for pattern reference only, not
/// imported or depended on. Unlike that script, this function does not
/// assume a pre-existing marker comment: it inspects the actual current
/// `android { ... }` block via brace-matching and adds whatever pieces are
/// missing (`flavorDimensions`, the `productFlavors { }` block itself, and
/// finally the tenant's own `create("<id>") { ... }` entry).
///
/// Ensures, in order:
///   1. `android { flavorDimensions += listOf("tenant") ... }` — added once,
///      shared by every tenant, skipped if already present.
///   2. A `productFlavors { }` block exists inside `android { }` — created
///      empty if missing, otherwise reused as-is.
///   3. A `create("<tenant.id>") { applicationId = "..."; resValue(...) }`
///      entry exists inside that `productFlavors { }` block.
///
/// Idempotent per tenant: calling this twice for the same [tenant] is a
/// no-op the second time (detected before any part of the file is
/// touched); flavor blocks already generated for *other* tenants are never
/// modified or duplicated.
///
/// Throws [StateError] if `android/app/build.gradle.kts` doesn't exist, or
/// if it exists but has no top-level `android { ... }` block to work with —
/// this function never blindly regexes a file it can't make sense of.
void generateAndroidFlavor(TenantConfig tenant, {required String projectRoot}) {
  final gradleFile = File(
    p.join(projectRoot, 'android', 'app', 'build.gradle.kts'),
  );
  if (!gradleFile.existsSync()) {
    throw StateError(
      'No android/app/build.gradle.kts found under "$projectRoot" — is '
      'this a Flutter project with Android support generated?',
    );
  }

  String content = gradleFile.readAsStringSync();

  // Idempotency guard, checked first and against the *unmodified* file: if
  // this tenant's flavor already exists, do nothing at all — not even the
  // flavorDimensions touch-up below, so a re-run over an already-generated
  // file is byte-for-byte a no-op.
  final tenantEntryPattern = RegExp(
    'create\\("${RegExp.escape(tenant.id)}"\\)',
  );
  if (tenantEntryPattern.hasMatch(content)) {
    return;
  }

  final _Block? androidBlock = _findTopLevelBlock(content, 'android');
  if (androidBlock == null) {
    throw StateError(
      '${gradleFile.path} has no top-level `android { ... }` block — '
      'refusing to guess where to insert the tenant flavor.',
    );
  }

  // Step 1: flavorDimensions, added once and shared by all tenants.
  if (!RegExp(r'flavorDimensions').hasMatch(
    content.substring(androidBlock.openBrace, androidBlock.closeBrace),
  )) {
    final int insertAt = androidBlock.openBrace + 1;
    content = content.replaceRange(
      insertAt,
      insertAt,
      '\n    flavorDimensions += listOf("tenant")\n',
    );
  }

  // Step 1b: `resValue(...)` inside a product flavor is gated behind the
  // `resValues` build feature on modern Android Gradle Plugin versions
  // (opt-in since AGP 8; without this, a real Gradle build fails with
  // "Product Flavor <id> contains custom resource values, but the feature
  // is disabled" even though the Kotlin DSL itself is syntactically fine).
  // Added once, shared by all tenants — re-locate the android block fresh
  // since the insertion above may have shifted indices.
  {
    final _Block block = _findTopLevelBlock(content, 'android')!;
    if (!RegExp(r'buildFeatures\s*\{[^}]*resValues')
        .hasMatch(content.substring(block.openBrace, block.closeBrace))) {
      final int insertAt = block.openBrace + 1;
      content = content.replaceRange(
        insertAt,
        insertAt,
        '\n    buildFeatures {\n        resValues = true\n    }\n',
      );
    }
  }

  // Step 2 + 3: find (or create) `productFlavors { }`, then insert this
  // tenant's `create("id") { ... }` entry just before its closing brace.
  // Re-locate the android block first — the flavorDimensions insertion
  // above may have shifted every index after it.
  final _Block refreshedAndroidBlock = _findTopLevelBlock(content, 'android')!;
  final String androidBody = content.substring(
    refreshedAndroidBlock.openBrace,
    refreshedAndroidBlock.closeBrace,
  );

  final String flavorEntry = _flavorEntryBlock(tenant);

  final RegExpMatch? productFlavorsMatch = RegExp(r'productFlavors\s*\{')
      .firstMatch(androidBody);

  if (productFlavorsMatch == null) {
    // No productFlavors block at all yet: create one (with this tenant's
    // entry already inside it) just before the android block's own closing
    // brace.
    final newBlock =
        '\n    // Managed automatically by white_label_kit — DO NOT EDIT BY HAND.\n    productFlavors {\n$flavorEntry    }\n';
    content = content.replaceRange(
      refreshedAndroidBlock.closeBrace,
      refreshedAndroidBlock.closeBrace,
      newBlock,
    );
  } else {
    // productFlavors already exists (possibly with other tenants' flavors
    // already in it): insert this tenant's entry right before its closing
    // brace, leaving every existing entry untouched.
    final int openBraceAbsolute =
        refreshedAndroidBlock.openBrace +
        productFlavorsMatch.end -
        1; // index of the '{' the match ended on
    final _Block? productFlavorsBlock = _matchBraceFrom(content, openBraceAbsolute);
    if (productFlavorsBlock == null) {
      throw StateError(
        '${gradleFile.path} has an unterminated `productFlavors {` block — '
        'refusing to guess where it ends.',
      );
    }
    int insertPos = productFlavorsBlock.closeBrace;
    final int lastLineBreak = content.lastIndexOf('\n', insertPos - 1);
    if (lastLineBreak != -1 &&
        content.substring(lastLineBreak + 1, insertPos).trim().isEmpty) {
      insertPos = lastLineBreak + 1;
    }
    content = content.replaceRange(insertPos, insertPos, flavorEntry);
  }

  gradleFile.writeAsStringSync(content);
}

/// Removes the `create("<tenantId>") { ... }` productFlavors block from
/// `<projectRoot>/android/app/build.gradle.kts`.
///
/// Idempotent: if the flavor is not present or the file does not exist,
/// does nothing.
void removeAndroidFlavor(String tenantId, {required String projectRoot}) {
  final gradleFile = File(
    p.join(projectRoot, 'android', 'app', 'build.gradle.kts'),
  );
  if (!gradleFile.existsSync()) {
    return;
  }

  String content = gradleFile.readAsStringSync();

  final pattern = RegExp(
    r'(?:[ \t]*(?://[^\r\n]*)?\r?\n)?[ \t]*create\("' +
        RegExp.escape(tenantId) +
        r'"\)\s*\{',
  );
  final RegExpMatch? match = pattern.firstMatch(content);
  if (match == null) {
    return;
  }

  final int lineStart = content.lastIndexOf('\n', match.start);
  final int start = (lineStart != -1) ? lineStart + 1 : match.start;

  final int openBrace = content.indexOf('{', match.start);
  final _Block? block = _matchBraceFrom(content, openBrace);
  if (block == null) {
    return;
  }

  int end = block.closeBrace + 1;
  if (end < content.length && content[end] == '\n') {
    end++;
  } else if (end + 1 < content.length &&
      content.substring(end, end + 2) == '\r\n') {
    end += 2;
  }

  content = content.replaceRange(start, end, '');
  gradleFile.writeAsStringSync(content);
}

/// The `create("<id>") { ... }` entry text for [tenant], indented as if it
/// sits directly inside a `productFlavors { }` block.
String _flavorEntryBlock(TenantConfig tenant) {
  final String id = tenant.id;
  final String applicationId = _escapeKotlinString(tenant.android.applicationId);
  final String appName = _escapeKotlinString(tenant.android.appName);
  return '''
        create("$id") {
            dimension = "tenant"
            applicationId = "$applicationId"
            resValue("string", "app_name", "$appName")
        }
'''
      .substring(1);
}

String _escapeKotlinString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

class _Block {
  const _Block(this.openBrace, this.closeBrace);

  /// Index of the block's opening `{`.
  final int openBrace;

  /// Index of the block's matching closing `}`.
  final int closeBrace;
}

/// Finds the first top-level `<name> { ... }` block (e.g. `android { ... }`)
/// via brace-counting from its opening brace — not a single regex over the
/// whole file, so nested braces inside the block never confuse where it
/// actually ends.
_Block? _findTopLevelBlock(String content, String name) {
  final RegExpMatch? headerMatch = RegExp('(?:^|\\n)\\s*$name\\s*\\{').firstMatch(content);
  if (headerMatch == null) {
    return null;
  }
  final int openBrace = content.lastIndexOf('{', headerMatch.end - 1);
  return _matchBraceFrom(content, openBrace);
}

/// Given the index of an opening `{`, returns the [_Block] spanning it and
/// its matching closing `}`, found by counting nested braces. Returns
/// `null` if the file is malformed (unterminated block).
_Block? _matchBraceFrom(String content, int openBrace) {
  var depth = 0;
  for (var i = openBrace; i < content.length; i++) {
    if (content[i] == '{') {
      depth++;
    }
    if (content[i] == '}') {
      depth--;
      if (depth == 0) {
        return _Block(openBrace, i);
      }
    }
  }
  return null;
}
