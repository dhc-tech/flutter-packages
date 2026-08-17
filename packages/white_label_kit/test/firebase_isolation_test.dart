// Regression tests proving optional per-tenant Firebase config files
// (`google-services.json` / `GoogleService-Info.plist`) get the exact same
// isolation guarantees as regular tenant assets — see TenantStager's class
// doc. Mirrors the mandated scenario in tenant_isolation_test.dart /
// isolation_contract_test.dart, but for the `firebase:` config block:
//
//   Stage tenant A => only A's Firebase files are present, B's are absent.
//   Stage tenant B => only B's Firebase files are present, A's are absent.
//   Stage A -> B -> A => no stale B Firebase file survives.
//   A Firebase path pointing at another tenant's directory is rejected.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'firebase_isolation_test_',
    );

    _writeTenantFirebaseFiles(
      projectRoot,
      id: 'acme',
      googleServicesContent: 'ACME_GOOGLE_SERVICES',
      googleServiceInfoContent: 'ACME_GOOGLE_SERVICE_INFO',
    );
    _writeTenantFirebaseFiles(
      projectRoot,
      id: 'beta',
      googleServicesContent: 'BETA_GOOGLE_SERVICES',
      googleServiceInfoContent: 'BETA_GOOGLE_SERVICE_INFO',
    );
    _writeTenantAsset(projectRoot, 'acme', 'logo.png', 'ACME_LOGO');
    _writeTenantAsset(projectRoot, 'beta', 'logo.png', 'BETA_LOGO');

    File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync('''
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
      firebase:
        google_services_json: "tenants/acme/config/google-services.json"
        google_service_info_plist: "tenants/acme/config/GoogleService-Info.plist"
    beta:
      name: "Beta"
      android:
        application_id: "com.example.beta"
        app_name: "Beta"
      ios:
        bundle_id: "com.example.beta"
        app_name: "Beta"
      assets:
        logo: "tenants/beta/assets/logo.png"
      firebase:
        google_services_json: "tenants/beta/config/google-services.json"
        google_service_info_plist: "tenants/beta/config/GoogleService-Info.plist"
''');
  });

  tearDown(() {
    projectRoot.deleteSync(recursive: true);
  });

  test('config parses optional firebase block per tenant', () {
    final config = WhiteLabelConfig.load(projectRoot.path);

    expect(
      config['acme'].firebase?.googleServicesJson,
      'tenants/acme/config/google-services.json',
    );
    expect(
      config['acme'].firebase?.googleServiceInfoPlist,
      'tenants/acme/config/GoogleService-Info.plist',
    );
    expect(
      config['beta'].firebase?.googleServicesJson,
      'tenants/beta/config/google-services.json',
    );
  });

  test('firebase block is optional: a tenant without it parses with a null firebase', () {
    File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync('''
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
''');

    final config = WhiteLabelConfig.load(projectRoot.path);
    expect(config['acme'].firebase, isNull);

    // And staging still works fine with no firebase/ group at all.
    final stager = TenantStager(projectRoot.path);
    stager.stage(config['acme']);
    expect(stager.stagedFirebaseFileNames('acme'), isEmpty);
    expect(stager.stagedAssetNames('acme'), ['logo.png']);
  });

  test('staging tenant A stages only A Firebase files, never B', () {
    final config = WhiteLabelConfig.load(projectRoot.path);
    final stager = TenantStager(projectRoot.path);

    stager.stage(config['acme']);

    final acmeFirebase = stager.stagedFirebaseFileNames('acme');
    expect(
      acmeFirebase,
      unorderedEquals(['GoogleService-Info.plist', 'google-services.json']),
    );

    final acmeGoogleServices = File(
      p.join(stager.stagingDirFor('acme'), 'firebase', 'google-services.json'),
    ).readAsStringSync();
    expect(acmeGoogleServices, 'ACME_GOOGLE_SERVICES');
    final acmeGoogleServiceInfo = File(
      p.join(
        stager.stagingDirFor('acme'),
        'firebase',
        'GoogleService-Info.plist',
      ),
    ).readAsStringSync();
    expect(acmeGoogleServiceInfo, 'ACME_GOOGLE_SERVICE_INFO');

    // Hard requirement: nothing beta-flavored anywhere in A's staged
    // firebase output, and B's staging directory doesn't even exist yet.
    expect(
      acmeFirebase.any((name) => name.toLowerCase().contains('beta')),
      isFalse,
    );
    expect(Directory(stager.stagingDirFor('beta')).existsSync(), isFalse);
  });

  test('staging tenant B stages only B Firebase files, never A', () {
    final config = WhiteLabelConfig.load(projectRoot.path);
    final stager = TenantStager(projectRoot.path);

    stager.stage(config['beta']);

    final betaGoogleServices = File(
      p.join(stager.stagingDirFor('beta'), 'firebase', 'google-services.json'),
    ).readAsStringSync();
    expect(betaGoogleServices, 'BETA_GOOGLE_SERVICES');
    expect(Directory(stager.stagingDirFor('acme')).existsSync(), isFalse);
  });

  test(
    'A -> B -> A: no stale Firebase file survives across repeated staging',
    () {
      final config = WhiteLabelConfig.load(projectRoot.path);
      final stager = TenantStager(projectRoot.path);

      stager.stage(config['acme']);
      stager.stage(config['beta']);
      stager.stage(config['acme']);

      // Prove A's re-stage is genuinely A again, byte-for-byte — not a
      // stale leftover from the B stage that happened in between.
      final acmeGoogleServices = File(
        p.join(
          stager.stagingDirFor('acme'),
          'firebase',
          'google-services.json',
        ),
      ).readAsStringSync();
      expect(acmeGoogleServices, 'ACME_GOOGLE_SERVICES');
      expect(
        stager.stagedFirebaseFileNames('acme'),
        unorderedEquals(['GoogleService-Info.plist', 'google-services.json']),
      );

      // B's staging output from the middle step is untouched by the final
      // A stage — each tenant's staging output is independent.
      final betaGoogleServices = File(
        p.join(
          stager.stagingDirFor('beta'),
          'firebase',
          'google-services.json',
        ),
      ).readAsStringSync();
      expect(betaGoogleServices, 'BETA_GOOGLE_SERVICES');
    },
  );

  test(
    'validation rejects a firebase path that escapes its own tenant directory',
    () {
      File(p.join(projectRoot.path, 'white_label.yaml')).writeAsStringSync('''
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
      firebase:
        google_services_json: "tenants/beta/config/google-services.json"
    beta:
      name: "Beta"
      android:
        application_id: "com.example.beta"
        app_name: "Beta"
      ios:
        bundle_id: "com.example.beta"
        app_name: "Beta"
      assets:
        logo: "tenants/beta/assets/logo.png"
''');

      expect(
        () => WhiteLabelConfig.load(projectRoot.path),
        throwsA(
          isA<WhiteLabelConfigException>().having(
            (e) => e.errors.join('\n'),
            'errors',
            contains('must live under tenants/acme/'),
          ),
        ),
      );
    },
  );

  test('stage() re-validates a hand-built TenantConfig with a cross-tenant firebase path', () {
    // Simulates a consumer bypassing WhiteLabelConfig/ConfigValidator
    // entirely by constructing TenantConfig directly — stage() must still
    // refuse to copy the file, same as it does for TenantAssets.
    const evil = TenantConfig(
      id: 'acme',
      name: 'Acme',
      android: AndroidTenantConfig(
        applicationId: 'com.example.acme',
        appName: 'Acme',
      ),
      ios: IosTenantConfig(bundleId: 'com.example.acme', appName: 'Acme'),
      assets: TenantAssets(logo: 'tenants/acme/assets/logo.png'),
      firebase: TenantFirebaseConfig(
        googleServicesJson: 'tenants/beta/config/google-services.json',
      ),
    );

    expect(
      () => TenantStager(projectRoot.path).stage(evil),
      throwsA(isA<StateError>()),
    );
    // Nothing should have been staged at all — reject before writing.
    expect(TenantStager(projectRoot.path).stagedAssetNames('acme'), isEmpty);
    expect(
      TenantStager(projectRoot.path).stagedFirebaseFileNames('acme'),
      isEmpty,
    );
  });
}

void _writeTenantFirebaseFiles(
  Directory projectRoot, {
  required String id,
  required String googleServicesContent,
  required String googleServiceInfoContent,
}) {
  final dir = Directory(p.join(projectRoot.path, 'tenants', id, 'config'))
    ..createSync(recursive: true);
  File(p.join(dir.path, 'google-services.json'))
      .writeAsStringSync(googleServicesContent);
  File(p.join(dir.path, 'GoogleService-Info.plist'))
      .writeAsStringSync(googleServiceInfoContent);
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
