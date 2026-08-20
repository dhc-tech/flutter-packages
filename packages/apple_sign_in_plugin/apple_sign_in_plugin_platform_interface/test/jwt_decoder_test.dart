// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:apple_sign_in_plugin_platform_interface/apple_sign_in_plugin_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

String _createTestJwt({
  required Map<String, dynamic> payload,
  Map<String, dynamic> header = const {'alg': 'HS256', 'typ': 'JWT'},
}) {
  String toBase64Url(Map<String, dynamic> jsonMap) {
    return base64Url
        .encode(utf8.encode(jsonEncode(jsonMap)))
        .replaceAll('=', '');
  }

  final String h = toBase64Url(header);
  final String p = toBase64Url(payload);
  final String s =
      base64Url.encode(utf8.encode('mock_signature')).replaceAll('=', '');
  return '$h.$p.$s';
}

void main() {
  group('JwtDecoder Tests', () {
    test('decode decodes valid JWT token correctly', () {
      final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final String token = _createTestJwt(
        payload: {
          'sub': 'user_12345',
          'email': 'user@example.com',
          'exp': nowSec + 3600,
          'iat': nowSec,
        },
      );

      final Map<String, dynamic> decoded = JwtDecoder.decode(token);
      expect(decoded['sub'], equals('user_12345'));
      expect(decoded['email'], equals('user@example.com'));
      expect(decoded['exp'], equals(nowSec + 3600));
    });

    test('decode throws FormatException for invalid tokens', () {
      expect(() => JwtDecoder.decode('invalid_token'), throwsFormatException);
      expect(() => JwtDecoder.decode('a.b'), throwsFormatException);
      expect(() => JwtDecoder.decode('a.b.c.d'), throwsFormatException);
    });

    test(
      'tryDecode returns Map for valid token and null for invalid token',
      () {
        final String token = _createTestJwt(payload: {'name': 'Test User'});
        expect(JwtDecoder.tryDecode(token), isNotNull);
        expect(JwtDecoder.tryDecode('bad.token.signature'), isNull);
        expect(JwtDecoder.tryDecode(''), isNull);
      },
    );

    test('isExpired detects active vs expired tokens', () {
      final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final String expiredToken = _createTestJwt(
        payload: {
          'sub': 'user_expired',
          'exp': nowSec - 300, // 5 minutes in the past
        },
      );

      final String activeToken = _createTestJwt(
        payload: {
          'sub': 'user_active',
          'exp': nowSec + 3600, // 1 hour in the future
        },
      );

      expect(JwtDecoder.isExpired(expiredToken), isTrue);
      expect(JwtDecoder.isExpired(activeToken), isFalse);
    });

    test('getExpirationDate and getRemainingTime calculate correctly', () {
      final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final int targetExp = nowSec + 1000;
      final String token = _createTestJwt(
        payload: {'exp': targetExp, 'iat': nowSec - 50},
      );

      final DateTime? expDate = JwtDecoder.getExpirationDate(token);
      expect(expDate, isNotNull);
      expect(expDate!.millisecondsSinceEpoch, equals(targetExp * 1000));

      final Duration? remaining = JwtDecoder.getRemainingTime(token);
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, greaterThan(0));

      final Duration? tokenTime = JwtDecoder.getTokenTime(token);
      expect(tokenTime, isNotNull);
      expect(tokenTime!.inSeconds, greaterThanOrEqualTo(0));
    });
  });
}
