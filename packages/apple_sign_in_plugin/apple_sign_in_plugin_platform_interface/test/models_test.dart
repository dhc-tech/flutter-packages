// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

AppleCredential _credential({
  String userIdentifier = 'user',
  String? email,
  ApplePersonName? name,
  String? identityToken,
  String? authorizationCode,
  String state = 's',
  Set<AppleAuthorizationScope> scopes = const {AppleAuthorizationScope.email},
  AppleRealUserStatus status = AppleRealUserStatus.unknown,
}) => AppleCredential(
  userIdentifier: userIdentifier,
  email: email,
  name: name,
  identityToken: identityToken,
  authorizationCode: authorizationCode,
  state: state,
  authorizedScopes: scopes,
  realUserStatus: status,
);

void main() {
  group('AppleCredential', () {
    test('equal credentials share hashCode', () {
      final AppleCredential a = _credential(
        email: 'a@b.c',
        name: const ApplePersonName(givenName: 'A'),
        identityToken: 't',
        authorizationCode: 'c',
      );
      final AppleCredential b = _credential(
        email: 'a@b.c',
        name: const ApplePersonName(givenName: 'A'),
        identityToken: 't',
        authorizationCode: 'c',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, a);
    });

    test('each field participates in equality', () {
      final AppleCredential base = _credential();
      expect(base, isNot(_credential(userIdentifier: 'other')));
      expect(base, isNot(_credential(email: 'x@y.z')));
      expect(base, isNot(_credential(name: const ApplePersonName(givenName: 'A'))));
      expect(base, isNot(_credential(identityToken: 't')));
      expect(base, isNot(_credential(authorizationCode: 'c')));
      expect(base, isNot(_credential(state: 'other')));
      expect(base, isNot(_credential(scopes: const {AppleAuthorizationScope.fullName})));
      expect(base, isNot(_credential(status: AppleRealUserStatus.likelyReal)));
      expect(base == Object(), isFalse);
    });

    test('scope set equality ignores insertion order', () {
      final AppleCredential a = _credential(
        scopes: {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
      );
      final AppleCredential b = _credential(
        scopes: {AppleAuthorizationScope.fullName, AppleAuthorizationScope.email},
      );
      expect(a, b);
    });

    test('name and email flags reflect presence', () {
      final AppleCredential none = _credential();
      expect(none.receivedName, isFalse);
      expect(none.isFirstAuthorization, isFalse);
      expect(none.receivedEmail, isFalse);

      final AppleCredential emptyEmail = _credential(email: '');
      expect(emptyEmail.receivedEmail, isFalse);

      final AppleCredential full = _credential(
        email: 'a@b.c',
        name: const ApplePersonName(givenName: 'A'),
      );
      expect(full.receivedName, isTrue);
      expect(full.isFirstAuthorization, isTrue);
      expect(full.receivedEmail, isTrue);
    });

    test('an empty ApplePersonName is not treated as a received name', () {
      final AppleCredential c = _credential(name: const ApplePersonName());
      expect(c.receivedName, isFalse);
      expect(c.isFirstAuthorization, isFalse);
    });

    test('toString does not leak tokens', () {
      final text = _credential(
        identityToken: 'SECRET_TOKEN',
        authorizationCode: 'SECRET_CODE',
      ).toString();
      expect(text, contains('AppleCredential(userIdentifier: user'));
      expect(text, isNot(contains('SECRET_TOKEN')));
      expect(text, isNot(contains('SECRET_CODE')));
    });
  });

  group('ApplePersonName', () {
    test('every component participates in equality and hashCode', () {
      const full = ApplePersonName(
        namePrefix: 'Dr',
        givenName: 'G',
        middleName: 'M',
        familyName: 'F',
        nameSuffix: 'Jr',
        nickname: 'N',
      );
      expect(
        full,
        const ApplePersonName(
          namePrefix: 'Dr',
          givenName: 'G',
          middleName: 'M',
          familyName: 'F',
          nameSuffix: 'Jr',
          nickname: 'N',
        ),
      );
      expect(
        full.hashCode,
        const ApplePersonName(
          namePrefix: 'Dr',
          givenName: 'G',
          middleName: 'M',
          familyName: 'F',
          nameSuffix: 'Jr',
          nickname: 'N',
        ).hashCode,
      );
      expect(full, isNot(const ApplePersonName(namePrefix: 'Mr')));
      expect(full == Object(), isFalse);
    });

    test('isEmpty is false when any single component is set', () {
      expect(const ApplePersonName(namePrefix: 'a').isEmpty, isFalse);
      expect(const ApplePersonName(middleName: 'a').isEmpty, isFalse);
      expect(const ApplePersonName(familyName: 'a').isEmpty, isFalse);
      expect(const ApplePersonName(nameSuffix: 'a').isEmpty, isFalse);
      expect(const ApplePersonName(nickname: 'a').isEmpty, isFalse);
    });

    test('toString lists all components', () {
      expect(
        const ApplePersonName(givenName: 'G', familyName: 'F').toString(),
        'ApplePersonName(namePrefix: null, givenName: G, middleName: null, '
        'familyName: F, nameSuffix: null, nickname: null)',
      );
    });
  });

  group('enums', () {
    test('AppleAuthorizationScope.restApiValue maps to REST scope names', () {
      expect(AppleAuthorizationScope.email.restApiValue, 'email');
      expect(AppleAuthorizationScope.fullName.restApiValue, 'name');
    });

    test('AppleCredentialState.fromWireValue falls back to notFound', () {
      expect(AppleCredentialState.fromWireValue(-1), AppleCredentialState.notFound);
      expect(AppleCredentialState.fromWireValue(99), AppleCredentialState.notFound);
    });

    test('AppleRealUserStatus.fromWireValue falls back to unsupported', () {
      expect(AppleRealUserStatus.fromWireValue(3), AppleRealUserStatus.unsupported);
      expect(AppleRealUserStatus.fromWireValue(-1), AppleRealUserStatus.unsupported);
    });
  });

  group('AppleDisconnectResult', () {
    test('only revoked and alreadyRevoked are successful', () {
      for (final AppleDisconnectStatus status in AppleDisconnectStatus.values) {
        final bool expected =
            status == AppleDisconnectStatus.revoked ||
            status == AppleDisconnectStatus.alreadyRevoked;
        expect(AppleDisconnectResult(status: status).isSuccessful, expected, reason: '$status');
      }
    });

    test('toString includes status and message', () {
      expect(
        const AppleDisconnectResult(
          status: AppleDisconnectStatus.failed,
          message: 'boom',
        ).toString(),
        'AppleDisconnectResult(status: AppleDisconnectStatus.failed, message: boom)',
      );
    });
  });

  group('AppleSignInException', () {
    test('keeps code, message and details', () {
      const e = AppleSignInException(AppleSignInErrorCode.networkFailed, 'offline', {'k': 1});
      expect(e.code, AppleSignInErrorCode.networkFailed);
      expect(e.message, 'offline');
      expect(e.details, {'k': 1});
      expect(e.toString(), 'AppleSignInException(networkFailed): offline');
      expect(const AppleSignInException(AppleSignInErrorCode.unknown, 'm').details, isNull);
    });
  });

  group('AppleAuthEvent', () {
    test('defaults timestamp to now and keeps optional fields null', () {
      final before = DateTime.now();
      const event = AppleAuthEvent(type: AppleAuthEventType.signedOut);
      expect(event.credential, isNull);
      expect(event.userIdentifier, isNull);
      expect(event.message, isNull);
      expect(event.timestamp.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(event.timestamp.isBefore(DateTime.now().add(const Duration(seconds: 1))), isTrue);
    });

    test('default timestamp delegates the DateTime API to the current time', () {
      const event = AppleAuthEvent(type: AppleAuthEventType.signedIn);
      final DateTime t = event.timestamp;
      final now = DateTime.now();
      expect((t.millisecondsSinceEpoch - now.millisecondsSinceEpoch).abs(), lessThan(5000));
      expect((t.microsecondsSinceEpoch - now.microsecondsSinceEpoch).abs(), lessThan(5000000));
      expect(t.isAtSameMomentAs(now.add(const Duration(days: 1))), isFalse);
      expect(t.compareTo(now.add(const Duration(minutes: 1))), lessThan(0));
      expect(t.difference(now).abs(), lessThan(const Duration(seconds: 5)));
      expect(t.add(const Duration(days: 1)).isAfter(now), isTrue);
      expect(t.subtract(const Duration(days: 1)).isBefore(now), isTrue);
      expect(t.toIso8601String(), isNotEmpty);
      expect(t.toLocal().isUtc, isFalse);
      expect(t.toUtc().isUtc, isTrue);
      expect(t.timeZoneName, isNotNull);
      expect(t.timeZoneOffset, now.timeZoneOffset);
      expect((t.year - now.year).abs(), lessThanOrEqualTo(1));
      expect(t.month, inInclusiveRange(1, 12));
      expect(t.day, inInclusiveRange(1, 31));
      expect(t.hour, inInclusiveRange(0, 23));
      expect(t.minute, inInclusiveRange(0, 59));
      expect(t.second, inInclusiveRange(0, 59));
      expect(t.millisecond, inInclusiveRange(0, 999));
      expect(t.microsecond, inInclusiveRange(0, 999));
      expect(t.weekday, inInclusiveRange(1, 7));
      expect(t.isUtc, now.isUtc);
    });

    test('keeps an explicit timestamp and toString omits the credential', () {
      final ts = DateTime.utc(2024, 1, 2);
      final event = AppleAuthEvent(
        type: AppleAuthEventType.credentialRevoked,
        credential: _credential(identityToken: 'SECRET'),
        userIdentifier: 'u',
        message: 'm',
        timestamp: ts,
      );
      expect(event.timestamp, ts);
      expect(
        event.toString(),
        'AppleAuthEvent(type: AppleAuthEventType.credentialRevoked, '
        'userIdentifier: u, message: m)',
      );
    });
  });

  group('AppleSignInCapabilities and diagnostics', () {
    const caps = AppleSignInCapabilities(
      platformName: 'Web',
      isSupported: true,
      nativeCredentialState: false,
      revocationEvents: true,
      browserAuthorization: true,
      webAppleJs: true,
      wasmWeb: true,
      backendRevocation: false,
      supportedScopes: {AppleAuthorizationScope.email},
    );

    test('capabilities toString summarizes key flags', () {
      expect(
        caps.toString(),
        'AppleSignInCapabilities(platform: Web, nativeState: false, '
        'revocationEvents: true, wasm: true)',
      );
    });

    test('diagnostics toSafeString lists flags and no configuration values', () {
      const diagnostics = AppleSignInDiagnostics(
        platformName: 'Web',
        isAvailable: true,
        capabilities: caps,
        isConfigured: false,
        configurationDetails: {'clientId': 'SECRET_CLIENT'},
        hasBackendAdapter: true,
      );
      final String text = diagnostics.toSafeString();
      expect(text, contains('Platform: Web'));
      expect(text, contains('Available: true'));
      expect(text, contains('Configured: false'));
      expect(text, contains('Native Credential State Supported: false'));
      expect(text, contains('Revocation Stream Supported: true'));
      expect(text, contains('WebAssembly Supported: true'));
      expect(text, contains('Backend Adapter Registered: true'));
      expect(text, isNot(contains('SECRET_CLIENT')));
      expect(diagnostics.toString(), text);
    });
  });
}
