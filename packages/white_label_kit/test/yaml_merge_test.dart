// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Verifies deepMergeMaps/mapToYaml (lib/src/generation/yaml_merge.dart)
// directly, including the List-value code path (e.g.
// flutter_native_splash's info_plist_files) that the icon/splash
// generator tests don't happen to exercise.

import 'package:test/test.dart';
import 'package:white_label_kit/src/generation/yaml_merge.dart';

void main() {
  group('deepMergeMaps', () {
    test('override wins for a plain scalar key', () {
      final result = deepMergeMaps({'color': '#ffffff'}, {'color': '#000000'});
      expect(result, {'color': '#000000'});
    });

    test('nested maps merge instead of replacing wholesale', () {
      final result = deepMergeMaps(
        {
          'android_12': {'color': '#ffffff', 'image': 'a.png'},
        },
        {
          'android_12': {'icon_background_color': '#111111'},
        },
      );
      expect(result['android_12'], {
        'color': '#ffffff',
        'image': 'a.png',
        'icon_background_color': '#111111',
      });
    });

    test('a list value in overrides replaces wholesale (not merged)', () {
      final result = deepMergeMaps(
        {'info_plist_files': const <String>[]},
        {
          'info_plist_files': [
            'ios/Runner/Info-Debug.plist',
            'ios/Runner/Info-Release.plist',
          ],
        },
      );
      expect(result['info_plist_files'], [
        'ios/Runner/Info-Debug.plist',
        'ios/Runner/Info-Release.plist',
      ]);
    });

    test('neither input map is mutated', () {
      final base = {'a': '1'};
      final overrides = {'b': '2'};
      deepMergeMaps(base, overrides);
      expect(base, {'a': '1'});
      expect(overrides, {'b': '2'});
    });
  });

  group('mapToYaml', () {
    test('serializes a top-level list value as a YAML list', () {
      final yaml = mapToYaml({
        'flutter_native_splash': {
          'info_plist_files': [
            'ios/Runner/Info-Debug.plist',
            'ios/Runner/Info-Release.plist',
          ],
        },
      });
      expect(yaml, contains('info_plist_files:'));
      expect(yaml, contains('- "ios/Runner/Info-Debug.plist"'));
      expect(yaml, contains('- "ios/Runner/Info-Release.plist"'));
    });

    test('serializes nested maps with correct indentation', () {
      final yaml = mapToYaml({
        'icons_launcher': {
          'platforms': {
            'android': {'adaptive_background_color': '#ffffff'},
          },
        },
      });
      expect(yaml, contains('icons_launcher:\n'));
      expect(yaml, contains('  platforms:\n'));
      expect(yaml, contains('    android:\n'));
      expect(yaml, contains('      adaptive_background_color: "#ffffff"'));
    });

    test('bools and numbers are written bare, not quoted', () {
      final yaml = mapToYaml({
        'flutter_native_splash': {'fullscreen': true, 'android_min_sdk': 24},
      });
      expect(yaml, contains('fullscreen: true'));
      expect(yaml, contains('android_min_sdk: 24'));
      expect(yaml, isNot(contains('"true"')));
      expect(yaml, isNot(contains('"24"')));
    });
  });
}
