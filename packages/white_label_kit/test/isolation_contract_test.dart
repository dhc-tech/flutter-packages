// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// ARCHITECTURE LOCK — TenantStager's isolation mechanism is a core
// security/build contract (see class doc on TenantStager). This file is the
// single canonical regression test for all 10 mandatory invariants, run as
// one A→B→A→failure sequence, so a future change that breaks any of them
// fails loudly right here instead of being caught piecemeal across other
// test files (which also cover these individually — this file exists to
// prove the FULL sequence together, matching the exact mandated scenario).
//
// Do not weaken or bypass TenantStager to make integration work "easier" —
// if a real defect is found here, add the failing case to this file BEFORE
// changing TenantStager, so the fix is provably a fix and not a regression
// in disguise.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'isolation_contract_test_',
    );

    _writeTenantAsset(projectRoot, 'a', 'logo.png', 'A_LOGO');
    _writeTenantAsset(projectRoot, 'b', 'logo.png', 'B_LOGO');

    File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync('''
white_label:
  default_tenant: a
  tenants:
    a:
      name: "Tenant A"
      android:
        application_id: "com.example.a"
        app_name: "Tenant A"
      ios:
        bundle_id: "com.example.a"
        app_name: "Tenant A"
      assets:
        logo: "tenants/a/assets/logo.png"
    b:
      name: "Tenant B"
      android:
        application_id: "com.example.b"
        app_name: "Tenant B"
      ios:
        bundle_id: "com.example.b"
        app_name: "Tenant B"
      assets:
        logo: "tenants/b/assets/logo.png"
''');
  });

  tearDown(() => projectRoot.deleteSync(recursive: true));

  test('mandatory scenario: build A -> build B -> build A -> failed generation stays safe', () {
    final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);
    final stager = TenantStager(projectRoot.path);

    // --- Build A: only A resources enter the build (invariant 1) ---
    stager.stage(config['a']);
    expect(stager.stagedAssetNames('a'), ['logo.png']);
    expect(
      File(p.join(stager.stagingDirFor('a'), 'assets', 'logo.png'))
          .readAsStringSync(),
      'A_LOGO',
    );
    // B's staging output doesn't exist yet at all.
    expect(Directory(stager.stagingDirFor('b')).existsSync(), isFalse);

    // --- Build B: only B resources enter the build ---
    stager.stage(config['b']);
    expect(stager.stagedAssetNames('b'), ['logo.png']);
    expect(
      File(p.join(stager.stagingDirFor('b'), 'assets', 'logo.png'))
          .readAsStringSync(),
      'B_LOGO',
    );
    // A's previously-staged output is untouched by building B.
    expect(
      File(p.join(stager.stagingDirFor('a'), 'assets', 'logo.png'))
          .readAsStringSync(),
      'A_LOGO',
      reason: "invariant 2/3: tenants/ tree and other tenants' staging are never touched",
    );

    // --- Build A again: no staleness from the intervening B build ---
    stager.stage(config['a']);
    expect(
      File(p.join(stager.stagingDirFor('a'), 'assets', 'logo.png'))
          .readAsStringSync(),
      'A_LOGO',
      reason: 'invariant 3: existing staging removed before each build, not merged with stale output',
    );
    expect(stager.stagedAssetNames('a'), ['logo.png']);

    // --- Intentional failure: delete A's source asset, re-stage must fail
    // safely (invariant 4/5: temp-then-swap, failure never corrupts the
    // last-known-good staged output) ---
    File(p.join(projectRoot.path, 'tenants', 'a', 'assets', 'logo.png'))
        .deleteSync();
    expect(() => stager.stage(config['a']), throwsA(isA<StateError>()));

    // Staging must still contain the LAST GOOD state, not be empty, not be
    // half-written, and absolutely not contain B's content under A's id.
    expect(stager.stagedAssetNames('a'), ['logo.png']);
    expect(
      File(p.join(stager.stagingDirFor('a'), 'assets', 'logo.png'))
          .readAsStringSync(),
      'A_LOGO',
      reason: 'invariant 5: a failed generation must not corrupt the previous valid staging state',
    );
    // And B's staging is completely unaffected by A's failed re-stage.
    expect(
      File(p.join(stager.stagingDirFor('b'), 'assets', 'logo.png'))
          .readAsStringSync(),
      'B_LOGO',
    );
  });

  test('invariant 6: cross-tenant asset reference is rejected, not silently allowed', () {
    File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync('''
white_label:
  default_tenant: a
  tenants:
    a:
      name: "Tenant A"
      android:
        application_id: "com.example.a"
        app_name: "Tenant A"
      ios:
        bundle_id: "com.example.a"
        app_name: "Tenant A"
      assets:
        logo: "tenants/b/assets/logo.png"
    b:
      name: "Tenant B"
      android:
        application_id: "com.example.b"
        app_name: "Tenant B"
      ios:
        bundle_id: "com.example.b"
        app_name: "Tenant B"
      assets:
        logo: "tenants/b/assets/logo.png"
''');

    expect(
      () => WhiteLabelConfig.load(projectRoot.path),
      throwsA(isA<WhiteLabelConfigException>()),
    );
  });

  test(
    'invariant 7: a declared-but-missing asset is rejected at stage time',
    () {
      final WhiteLabelConfig config = WhiteLabelConfig.load(projectRoot.path);
      File(p.join(projectRoot.path, 'tenants', 'a', 'assets', 'logo.png'))
          .deleteSync();

      expect(
        () => TenantStager(projectRoot.path).stage(config['a']),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('invariant 8: invalid bundle ids are rejected non-silently', () {
    expect(
      ConfigValidator.androidApplicationId('Not A Package'),
      isA<Invalid>(),
    );
    expect(ConfigValidator.iosBundleId('not_valid_for_ios'), isA<Invalid>());
  });

  test('invariant 9: invalid color values are rejected non-silently', () {
    expect(ConfigValidator.colorHex('blue'), isA<Invalid>());
    expect(ConfigValidator.colorHex('#GGGGGG'), isA<Invalid>());
  });

  test('invariant 10: validation errors are explicit, actionable, and collected (not just the first)', () {
    File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync('''
white_label:
  default_tenant: a
  tenants:
    a:
      name: "Tenant A"
      android:
        application_id: "Not A Package"
        app_name: "Tenant A"
      ios:
        bundle_id: "not_valid"
        app_name: "Tenant A"
      assets:
        logo: "tenants/a/assets/logo.png"
      theme:
        primary_color: "blue"
''');

    try {
      WhiteLabelConfig.load(projectRoot.path);
      fail('expected WhiteLabelConfigException');
    } on WhiteLabelConfigException catch (e) {
      // All three independent problems are reported together, not just
      // whichever was found first.
      expect(e.errors.length, greaterThanOrEqualTo(3));
      expect(e.errors.join('\n'), contains('applicationId'));
      expect(e.errors.join('\n'), contains('bundle id'));
      expect(e.errors.join('\n'), contains('color'));
    }
  });
}

void _writeTenantAsset(
  Directory projectRoot,
  String tenantId,
  String filename,
  String content,
) {
  final dir = Directory(p.join(projectRoot.path, 'tenants', tenantId, 'assets'))
    ..createSync(recursive: true);
  File(p.join(dir.path, filename)).writeAsStringSync(content);
}
