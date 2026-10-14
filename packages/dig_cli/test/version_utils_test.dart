// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'dart:io';
import 'dart:isolate';

import 'package:dig_cli/src/utils/version_utils.dart';
import 'package:dig_cli/src/version_helper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

/// Runs [body] with every `http.get` answered by [handler].
Future<T> withMockHttp<T>(
  Future<T> Function() body,
  Future<http.Response> Function(http.Request request) handler,
) {
  return http.runWithClient(body, () => MockClient(handler));
}

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  kDigCliVersionTests();
  group('VersionUtils Tests', () {
    test('isNewer returns true when latest is greater than current', () {
      expect(VersionUtils.isNewer('1.8.1', '1.8.0'), isTrue);
      expect(VersionUtils.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(VersionUtils.isNewer('1.8.0-beta.2', '1.8.0-beta.1'), isTrue);
    });

    test('isNewer returns false when latest is equal or less than current', () {
      expect(VersionUtils.isNewer('1.8.0', '1.8.0'), isFalse);
      expect(VersionUtils.isNewer('1.7.9', '1.8.0'), isFalse);
      expect(VersionUtils.isNewer('1.0.0', '2.0.0'), isFalse);
    });

    test(
      'isNewer gracefully handles invalid semver strings without crashing',
      () {
        expect(VersionUtils.isNewer('invalid', '1.8.0'), isFalse);
        expect(VersionUtils.isNewer('1.8.0', 'invalid'), isFalse);
        expect(VersionUtils.isNewer('', ''), isFalse);
      },
    );

    test('isNewer follows semver precedence for pre-releases and build', () {
      expect(VersionUtils.isNewer('1.8.0', '1.8.0-beta.1'), isTrue);
      expect(VersionUtils.isNewer('1.8.0-beta.1', '1.8.0'), isFalse);
      expect(VersionUtils.isNewer('1.10.0', '1.9.0'), isTrue);
      expect(VersionUtils.isNewer('1.8.0+1', '1.8.0+2'), isFalse);
    });
  });

  group('kDigCliVersion', () {
    test('is a valid semantic version', () {
      expect(() => Version.parse(kDigCliVersion), returnsNormally);
    });
  });

  group('getLatestStableVersion', () {
    test('queries the dig_cli package endpoint and returns latest', () async {
      Uri? requested;
      final String? version = await withMockHttp(
        VersionUtils.getLatestStableVersion,
        (request) async {
          requested = request.url;
          return jsonResponse({
            'latest': {'version': '3.2.1'},
          });
        },
      );

      expect(version, '3.2.1');
      expect(requested, Uri.parse('https://pub.dev/api/packages/dig_cli'));
    });

    test('returns null on a non-200 status', () async {
      final String? version = await withMockHttp(
        VersionUtils.getLatestStableVersion,
        (_) async => jsonResponse({'error': 'x'}, 500),
      );
      expect(version, isNull);
    });

    test('returns null on malformed JSON', () async {
      final String? version = await withMockHttp(
        VersionUtils.getLatestStableVersion,
        (_) async => http.Response('<html>', 200),
      );
      expect(version, isNull);
    });

    test('returns null when the expected fields are missing', () async {
      final String? version = await withMockHttp(
        VersionUtils.getLatestStableVersion,
        (_) async => jsonResponse({'unexpected': true}),
      );
      expect(version, isNull);
    });

    test('returns null when the network call fails', () async {
      final String? version = await withMockHttp(
        VersionUtils.getLatestStableVersion,
        (_) async => throw http.ClientException('offline'),
      );
      expect(version, isNull);
    });
  });

  group('getLatestPreReleaseVersion', () {
    Map<String, Object> versions(List<String> list) => {
      'versions': [
        for (final v in list) {'version': v},
      ],
    };

    test('picks the highest pre-release, ignoring stable versions', () async {
      final String? version = await withMockHttp(
        VersionUtils.getLatestPreReleaseVersion,
        (_) async => jsonResponse(
          versions([
            '1.0.0',
            '2.0.0-beta.1',
            '2.0.0-beta.10',
            '2.0.0-beta.2',
            '1.9.0',
            '3.0.0',
          ]),
        ),
      );
      expect(version, '2.0.0-beta.10');
    });

    test('returns null when only stable versions exist', () async {
      final String? version = await withMockHttp(
        VersionUtils.getLatestPreReleaseVersion,
        (_) async => jsonResponse(versions(['1.0.0', '1.1.0'])),
      );
      expect(version, isNull);
    });

    test('returns null on non-200, bad payload and network errors', () async {
      expect(
        await withMockHttp(
          VersionUtils.getLatestPreReleaseVersion,
          (_) async => http.Response('', 404),
        ),
        isNull,
      );
      expect(
        await withMockHttp(
          VersionUtils.getLatestPreReleaseVersion,
          (_) async => jsonResponse(versions(['not-a-version'])),
        ),
        isNull,
      );
      expect(
        await withMockHttp(
          VersionUtils.getLatestPreReleaseVersion,
          (_) async => throw http.ClientException('offline'),
        ),
        isNull,
      );
    });
  });

  group('update availability', () {
    Future<http.Response> stable(String v) async => jsonResponse({
      'latest': {'version': v},
    });

    test('isUpdateAvailable is true only for a newer stable release', () async {
      expect(
        await withMockHttp(
          VersionUtils.isUpdateAvailable,
          (_) => stable('999.0.0'),
        ),
        isTrue,
      );
      expect(
        await withMockHttp(
          VersionUtils.isUpdateAvailable,
          (_) => stable(kDigCliVersion),
        ),
        isFalse,
      );
      expect(
        await withMockHttp(
          VersionUtils.isUpdateAvailable,
          (_) => stable('0.0.1'),
        ),
        isFalse,
      );
    });

    test('isUpdateAvailable is false when the lookup fails', () async {
      expect(
        await withMockHttp(
          VersionUtils.isUpdateAvailable,
          (_) async => http.Response('', 503),
        ),
        isFalse,
      );
    });

    test(
      'isBetaUpdateAvailable compares against the installed version',
      () async {
        Future<http.Response> pre(String v) async => jsonResponse({
          'versions': [
            {'version': v},
          ],
        });

        expect(
          await withMockHttp(
            VersionUtils.isBetaUpdateAvailable,
            (_) => pre('999.0.0-beta.1'),
          ),
          isTrue,
        );
        expect(
          await withMockHttp(
            VersionUtils.isBetaUpdateAvailable,
            (_) => pre('0.0.1-beta.1'),
          ),
          isFalse,
        );
        expect(
          await withMockHttp(
            VersionUtils.isBetaUpdateAvailable,
            (_) async => http.Response('', 500),
          ),
          isFalse,
        );
      },
    );
  });
}

void kDigCliVersionTests() {
  test('kDigCliVersion matches the version in pubspec.yaml', () async {
    // Resolved from the package, not the working directory, which other test
    // files may have changed.
    final Uri? helper = await Isolate.resolvePackageUri(
      Uri.parse('package:dig_cli/src/version_helper.dart'),
    );
    final String pubspec = File.fromUri(helper!.resolve('../../pubspec.yaml'))
        .readAsStringSync();
    final String version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    expect(kDigCliVersion, version);
  });
}
