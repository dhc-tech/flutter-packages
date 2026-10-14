// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:dig_cli/src/commands/zip_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Only the rule evaluation is tested here (no cwd access), so this file is
/// safe to run in parallel with the cwd-dependent suite.
void main() {
  group('IgnoreRules.shouldIgnore', () {
    final rules = IgnoreRules(
      {'build', 'node_modules'},
      {'pubspec.lock', 'secrets.json'},
      {'.log', '.iml'},
    );
    final entity = File('unused');

    test('ignores hidden files and anything under hidden directories', () {
      expect(rules.shouldIgnore('.gitignore', entity), isTrue);
      expect(
        rules.shouldIgnore(p.join('.dart_tool', 'a', 'b.dart'), entity),
        isTrue,
      );
      expect(rules.shouldIgnore(p.join('lib', '.hidden.dart'), entity), isTrue);
    });

    test('ignores files located anywhere below an ignored directory', () {
      expect(rules.shouldIgnore(p.join('build', 'app.apk'), entity), isTrue);
      expect(
        rules.shouldIgnore(p.join('web', 'node_modules', 'x', 'y.js'), entity),
        isTrue,
      );
    });

    test('ignores exact file names but not partial matches', () {
      expect(rules.shouldIgnore('pubspec.lock', entity), isTrue);
      expect(rules.shouldIgnore(p.join('a', 'secrets.json'), entity), isTrue);
      expect(rules.shouldIgnore('pubspec.lock.bak', entity), isFalse);
    });

    test('ignores by extension', () {
      expect(rules.shouldIgnore(p.join('logs', 'run.log'), entity), isTrue);
      expect(rules.shouldIgnore('app.iml', entity), isTrue);
      expect(rules.shouldIgnore('catalog', entity), isFalse);
    });

    test('keeps ordinary source files', () {
      expect(rules.shouldIgnore(p.join('lib', 'main.dart'), entity), isFalse);
      expect(rules.shouldIgnore('pubspec.yaml', entity), isFalse);
      expect(rules.shouldIgnore(p.join('builder', 'x.dart'), entity), isFalse);
    });

    test('empty rules only ignore hidden paths', () {
      final empty = IgnoreRules({}, {}, {});
      expect(empty.shouldIgnore(p.join('build', 'a.txt'), entity), isFalse);
      expect(empty.shouldIgnore('.env', entity), isTrue);
    });
  });
}
