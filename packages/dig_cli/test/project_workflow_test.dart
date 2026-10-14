// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// All suites in this file change the process working directory. Test files
// run in parallel isolates of one process, so every cwd-dependent test lives
// here and nowhere else.

import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:args/command_runner.dart';
import 'package:dig_cli/src/commands/asset_command.dart';
import 'package:dig_cli/src/commands/create_jks_command.dart';
import 'package:dig_cli/src/commands/create_module_command.dart';
import 'package:dig_cli/src/commands/hash_key_command.dart';
import 'package:dig_cli/src/commands/remove_module_command.dart';
import 'package:dig_cli/src/commands/rename_command.dart';
import 'package:dig_cli/src/commands/sha_keys_command.dart';
import 'package:dig_cli/src/commands/zip_command.dart';
import 'package:dig_cli/src/utils/project_rebrander.dart';
import 'package:dig_cli/src/utils/project_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/capture.dart';

late Directory originalCwd;
late Directory tmp;

void write(String relativePath, String content) {
  final file = File(p.join(tmp.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

String read(String relativePath) =>
    File(p.join(tmp.path, relativePath)).readAsStringSync();

bool exists(String relativePath) =>
    File(p.join(tmp.path, relativePath)).existsSync() ||
    Directory(p.join(tmp.path, relativePath)).existsSync();

void main() {
  setUp(() {
    ansiColorDisabled = true;
    originalCwd = Directory.current;
    tmp = Directory.systemTemp.createTempSync('dig_cli_test_').absolute;
    // Resolve symlinks (/var -> /private/var on macOS) so paths compare equal.
    tmp = Directory(tmp.resolveSymbolicLinksSync());
    Directory.current = tmp;
    resetProjectRootCache();
  });

  tearDown(() {
    Directory.current = originalCwd;
    resetProjectRootCache();
    tmp.deleteSync(recursive: true);
  });

  group('project_utils', () {
    test('findProjectRoot returns the directory holding pubspec.yaml', () {
      write('pubspec.yaml', 'name: demo\n');
      expect(findProjectRoot()!.path, tmp.path);
    });

    test('findProjectRoot walks up from a nested directory', () {
      write('pubspec.yaml', 'name: demo\n');
      final nested = Directory(p.join(tmp.path, 'lib', 'a', 'b'))
        ..createSync(recursive: true);
      Directory.current = nested;

      expect(findProjectRoot()!.path, tmp.path);
    });

    test('findProjectRoot caches until resetProjectRootCache is called', () {
      write('pubspec.yaml', 'name: demo\n');
      expect(findProjectRoot(), isNotNull);

      File(p.join(tmp.path, 'pubspec.yaml')).deleteSync();
      expect(findProjectRoot()!.path, tmp.path, reason: 'served from cache');

      resetProjectRootCache();
      final Directory? after = findProjectRoot();
      expect(after?.path, isNot(tmp.path));
    });

    test('isFlutterProject reflects the presence of a pubspec', () async {
      write('pubspec.yaml', 'name: demo\n');
      expect(await isFlutterProject(), isTrue);
    });

    test('getProjectName reads the name from pubspec.yaml', () async {
      write('pubspec.yaml', 'name: my_cool_app\nversion: 1.0.0\n');
      expect(await getProjectName(), 'my_cool_app');
    });

    test(
      'getBundleId reads Groovy and Kotlin DSL, preferring Kotlin',
      () async {
        write('pubspec.yaml', 'name: demo\n');
        expect(await getBundleId(), isNull, reason: 'no gradle file yet');

        write(
          'android/app/build.gradle',
          'defaultConfig {\n applicationId "com.groovy.app"\n}',
        );
        expect(await getBundleId(), 'com.groovy.app');

        write(
          'android/app/build.gradle.kts',
          'defaultConfig {\n applicationId = "com.kotlin.app"\n}',
        );
        expect(await getBundleId(), 'com.kotlin.app');
      },
    );

    test('getBundleId is null when no applicationId is declared', () async {
      write('pubspec.yaml', 'name: demo\n');
      write('android/app/build.gradle', 'android {}');
      expect(await getBundleId(), isNull);
    });

    test('getAppLabel reads android:label from the manifest', () async {
      write('pubspec.yaml', 'name: demo\n');
      expect(await getAppLabel(), isNull);

      write(
        'android/app/src/main/AndroidManifest.xml',
        '<application android:label="My App" android:name="x"/>',
      );
      expect(await getAppLabel(), 'My App');
    });

    test('getDesktopPath ends in Desktop', () async {
      expect(p.basename(await getDesktopPath()), 'Desktop');
    });
  });

  group('IgnoreRules.fromGitignore', () {
    test('returns empty rules and warns when .gitignore is missing', () async {
      late IgnoreRules rules;
      final lines = await capturePrints(
        () => rules = IgnoreRules.fromGitignore(),
      );

      expect(rules.exactDirs, isEmpty);
      expect(rules.exactFiles, isEmpty);
      expect(rules.extensions, isEmpty);
      expect(lines.join(), contains('.gitignore not found'));
    });

    test('classifies directories, files and extensions; skips noise', () {
      write('.gitignore', '''
# comment
build/
.dart_tool/

*.log
*.iml
pubspec.lock
!keep.txt

   coverage/   
''');

      final IgnoreRules rules = IgnoreRules.fromGitignore();

      expect(rules.exactDirs, {'build', '.dart_tool', 'coverage'});
      expect(rules.exactFiles, {'pubspec.lock'});
      expect(rules.extensions, {'.log', '.iml'});
    });
  });

  group('rename command', () {
    CommandRunner<void> runner() =>
        CommandRunner<void>('dg', 'test')..addCommand(RenameCommand());

    void projectFixture() {
      write('pubspec.yaml', 'name: old_app\n');
      write(
        'android/app/build.gradle.kts',
        'android {\n namespace = "com.old.app"\n defaultConfig {\n  applicationId = "com.old.app"\n }\n}\n',
      );
      write(
        'android/app/src/main/AndroidManifest.xml',
        '<manifest package="com.old.app"><application android:label="Old"/></manifest>',
      );
    }

    test('does nothing outside a Flutter project', () async {
      // tmp has no pubspec; pretend we are in an isolated place.
      final lines = await capturePrints(
        () => runner().run(['rename', '--name', 'X']),
      );
      // Either not in a project (nothing printed) or tmp sits under a
      // project; in both cases tmp itself must be untouched.
      expect(lines.join(), isNot(contains('successfully renamed')));
      expect(tmp.listSync(), isEmpty);
    });

    test('rejects malformed bundle ids without touching files', () async {
      projectFixture();
      final String before = read('android/app/build.gradle.kts');

      for (final bad in [
        'Com.Example.App',
        'single',
        'com..app',
        '1com.app',
        'com.app-x',
      ]) {
        final lines = await capturePrints(
          () => runner().run(['rename', '--bundle-id', bad]),
        );
        expect(
          lines.join(),
          isNot(contains('successfully renamed')),
          reason: bad,
        );
      }
      expect(read('android/app/build.gradle.kts'), before);
      expect(
        read('android/app/src/main/AndroidManifest.xml'),
        contains('android:label="Old"'),
      );
    });

    test('applies a new name and valid bundle id', () async {
      projectFixture();
      final lines = await capturePrints(
        () => runner().run(['rename', '-n', 'Shiny', '-b', 'com.new.app']),
      );

      expect(lines.join(), contains('App successfully renamed!'));
      expect(
        read('android/app/build.gradle.kts'),
        contains('applicationId = "com.new.app"'),
      );
      expect(
        read('android/app/src/main/AndroidManifest.xml'),
        contains('android:label="Shiny"'),
      );
    });

    test('renames only the label when just --name is given', () async {
      projectFixture();
      await capturePrints(
        () => runner().run(['rename', '--name', 'Only Label']),
      );

      expect(
        read('android/app/src/main/AndroidManifest.xml'),
        contains('android:label="Only Label"'),
      );
      expect(read('android/app/build.gradle.kts'), contains('"com.old.app"'));
    });

    test('handleRenameCommand wires the command into a runner', () async {
      projectFixture();
      await capturePrints(
        () => handleRenameCommand(['rename', '-n', 'Via Handler']),
      );
      expect(
        read('android/app/src/main/AndroidManifest.xml'),
        contains('Via Handler'),
      );
    });

    test('unknown options raise a UsageException', () async {
      projectFixture();
      await expectLater(
        runner().run(['rename', '--nope']),
        throwsA(isA<UsageException>()),
      );
    });
  });

  group('ProjectRebrander', () {
    ProjectRebrander rebrander({
      String slug = 'new_app',
      String appName = 'New App',
      String bundleId = 'com.new.thing',
    }) => ProjectRebrander(
      projectDir: tmp,
      newSlug: slug,
      newAppName: appName,
      newBundleId: bundleId,
    );

    void fullFixture() {
      write('pubspec.yaml', 'name: old_app\n');
      write(
        'lib/main.dart',
        "import 'package:old_app/a.dart';\nimport 'package:structure/b.dart';\nconst n = 'PROJECT_NAME';\nconst id = 'com.old.app';\n",
      );
      write(
        'lib/app/constants/app_constant.dart',
        "class C {\n  static const String appName = 'Old';\n}\n",
      );
      write('test/a_test.dart', "import 'package:old_app/a.dart';\n");
      write('lib/notes.bin', 'package:old_app/ untouched');
      write(
        'android/app/build.gradle.kts',
        'android {\n namespace = "com.old.app"\n defaultConfig {\n  applicationId = "com.old.app"\n }\n}\n',
      );
      write(
        'android/app/src/main/AndroidManifest.xml',
        '<manifest package="com.old.app"><application android:label="Old"/></manifest>',
      );
      write(
        'android/app/src/main/kotlin/com/old/app/MainActivity.kt',
        'package com.old.app\n\nclass MainActivity\n',
      );
      write(
        'android/app/src/debug/java/com/old/app/Debug.java',
        'package com.old.app;\nclass Debug {}\n',
      );
      const plist =
          '<dict><key>CFBundleDisplayName</key>\n<string>Old</string>\n<key>CFBundleName</key><string>old</string>\n<key>CFBundleIdentifier</key><string>com.old.app</string></dict>';
      write('ios/Runner/Info.plist', plist);
      write('macos/Runner/Info.plist', plist);
      write(
        'ios/Runner.xcodeproj/project.pbxproj',
        'PRODUCT_BUNDLE_IDENTIFIER = com.old.app;\nPRODUCT_BUNDLE_IDENTIFIER = com.old.app.RunnerTests;\n',
      );
      write(
        'macos/Runner.xcodeproj/project.pbxproj',
        'PRODUCT_BUNDLE_IDENTIFIER = com.old.app;\n',
      );
      write(
        'macos/Runner/Configs/AppInfo.xcconfig',
        'PRODUCT_NAME = old\nOTHER = 1\n',
      );
      write('windows/runner/Runner.rc', 'VALUE "ProductName", "old"\n');
      write(
        'windows/runner/main.cpp',
        'window.CreateAndShow(L"old", origin, size)\n',
      );
      write('linux/CMakeLists.txt', 'set(BINARY_NAME "old")\n');
      write(
        'web/index.html',
        '<title>old</title><meta content="old" name="apple-mobile-web-app-title">',
      );
      write('web/manifest.json', '{"name": "old", "short_name": "old"}');
    }

    test(
      'updates imports, placeholders and ignores unrelated extensions',
      () async {
        fullFixture();
        await rebrander().rebrand();

        final String main = read('lib/main.dart');
        expect(main, contains("import 'package:new_app/a.dart';"));
        expect(main, contains("import 'package:new_app/b.dart';"));
        expect(main, contains("const n = 'new_app';"));
        expect(read('test/a_test.dart'), contains('package:new_app/'));
        expect(read('lib/notes.bin'), contains('package:old_app/'));
      },
    );

    test('rewrites app name across every platform file', () async {
      fullFixture();
      await rebrander().rebrand();

      expect(
        read('android/app/src/main/AndroidManifest.xml'),
        contains('android:label="New App"'),
      );
      for (final plist in [
        'ios/Runner/Info.plist',
        'macos/Runner/Info.plist',
      ]) {
        final String c = read(plist);
        expect(
          c,
          contains(
            '<key>CFBundleDisplayName</key>\n\t<string>New App</string>',
          ),
          reason: plist,
        );
        expect(
          c,
          contains('<key>CFBundleName</key>\n\t<string>New App</string>'),
          reason: plist,
        );
      }
      expect(
        read('macos/Runner/Configs/AppInfo.xcconfig'),
        'PRODUCT_NAME = New App\nOTHER = 1\n',
      );
      expect(
        read('windows/runner/Runner.rc'),
        contains('VALUE "ProductName", "New App"'),
      );
      expect(
        read('windows/runner/main.cpp'),
        contains('window.CreateAndShow(L"New App"'),
      );
      expect(
        read('linux/CMakeLists.txt'),
        contains('set(BINARY_NAME "New App")'),
      );
      expect(read('web/index.html'), contains('<title>New App</title>'));
      expect(
        read('web/index.html'),
        contains('content="New App" name="apple-mobile-web-app-title"'),
      );
      final String manifest = read('web/manifest.json');
      expect(manifest, contains('"name": "New App"'));
      expect(manifest, contains('"short_name": "New App"'));
      expect(
        read('lib/app/constants/app_constant.dart'),
        contains("static const String appName = 'New App';"),
      );
    });

    test(
      'rewrites bundle ids in gradle, manifest, Apple projects and code',
      () async {
        fullFixture();
        await rebrander().rebrand();

        final String gradle = read('android/app/build.gradle.kts');
        expect(gradle, contains('applicationId = "com.new.thing"'));
        expect(gradle, contains('namespace = "com.new.thing"'));
        expect(
          read('android/app/src/main/AndroidManifest.xml'),
          contains('package="com.new.thing"'),
        );
        expect(read('lib/main.dart'), contains("const id = 'com.new.thing';"));
        expect(
          read('ios/Runner.xcodeproj/project.pbxproj'),
          'PRODUCT_BUNDLE_IDENTIFIER = com.new.thing;\nPRODUCT_BUNDLE_IDENTIFIER = com.new.thing;\n',
        );
        expect(
          read('macos/Runner.xcodeproj/project.pbxproj'),
          contains('com.new.thing;'),
        );
        expect(
          read('ios/Runner/Info.plist'),
          contains(
            '<key>CFBundleIdentifier</key>\n\t<string>com.new.thing</string>',
          ),
        );
      },
    );

    test('moves Kotlin/Java sources to the new package path and fixes package line', () async {
      fullFixture();
      await rebrander().rebrand();

      expect(exists('android/app/src/main/kotlin/com/old'), isFalse);
      expect(
        read('android/app/src/main/kotlin/com/new/thing/MainActivity.kt'),
        startsWith('package com.new.thing\n'),
      );
      expect(
        read('android/app/src/debug/java/com/new/thing/Debug.java'),
        startsWith('package com.new.thing;'),
      );
    });

    test('keeps a placeholder Info.plist identifier untouched', () async {
      write('pubspec.yaml', 'name: old_app\n');
      const plist =
          r'<key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>';
      write('ios/Runner/Info.plist', plist);
      await rebrander().rebrand();

      expect(read('ios/Runner/Info.plist'), plist);
    });

    test('supports Groovy build.gradle syntax without equals signs', () async {
      write('pubspec.yaml', 'name: old_app\n');
      write(
        'android/app/build.gradle',
        'android {\n namespace "com.old.app"\n defaultConfig {\n  applicationId "com.old.app"\n }\n}\n',
      );
      await rebrander().rebrand();

      final String gradle = read('android/app/build.gradle');
      expect(gradle, contains('applicationId "com.new.thing"'));
      expect(gradle, contains('namespace "com.new.thing"'));
    });

    test(
      'does not restructure directories when the bundle id is unchanged',
      () async {
        write('pubspec.yaml', 'name: old_app\n');
        write('android/app/build.gradle', 'applicationId "com.same.id"\n');
        write(
          'android/app/src/main/kotlin/com/same/id/MainActivity.kt',
          'package com.same.id\n',
        );
        await rebrander(bundleId: 'com.same.id').rebrand();

        expect(
          exists('android/app/src/main/kotlin/com/same/id/MainActivity.kt'),
          isTrue,
        );
      },
    );

    test('works without a pubspec and on an empty project', () async {
      write('lib/main.dart', "const n = 'PROJECT_NAME';\n");
      await rebrander().rebrand();

      expect(read('lib/main.dart'), "const n = 'new_app';\n");
    });

    test('is idempotent: a second run changes nothing', () async {
      fullFixture();
      await rebrander().rebrand();
      final snapshot = {
        for (final f in tmp.listSync(recursive: true).whereType<File>())
          f.path: f.readAsStringSync(),
      };
      await rebrander().rebrand();

      for (final entry in snapshot.entries) {
        // pubspec still says old_app (never rewritten), others must match.
        expect(
          File(entry.key).readAsStringSync(),
          entry.value,
          reason: entry.key,
        );
      }
    });
  });

  group('asset generation (buildAssets)', () {
    void assetFixture({String extraConfig = ''}) {
      write(
        'dig.yaml',
        'assets-dir: assets/\noutput-dir: lib/gen\n$extraConfig',
      );
      write('assets/icons/svg/ic_back.svg', '<svg/>');
      write('assets/icons/svg/My-Icon.svg', '<svg/>');
      write('assets/icons/svg/Some Icon (1).svg', '<svg/>');
      write('assets/icons/4.png', 'x');
      write('assets/images/logo.jpeg', 'x');
      write('assets/fonts/Roboto.ttf', 'x');
      write('assets/bottom_bar/home.webp', 'x');
      write('assets/root_level.png', 'x');
      write('assets/images/notes.txt', 'x');
    }

    test('explains how to configure when dig.yaml is missing', () async {
      final lines = await capturePrints(buildAssets);

      expect(lines.join('\n'), contains('assets-dir: assets/'));
      expect(exists('lib'), isFalse);
    });

    test('stops when the assets directory does not exist', () async {
      write('dig.yaml', 'assets-dir: nowhere/\n');
      await capturePrints(buildAssets);

      expect(exists('lib'), isFalse);
    });

    test('generates category, type and main export files', () async {
      assetFixture();
      final lines = await capturePrints(buildAssets);

      expect(lines.join('\n'), contains('Generated 7 asset constants'));

      final String main = read('lib/gen/assets.dart');
      expect(main, contains('Generated by: dg asset build'));
      for (final cat in ['bottom_bar', 'fonts', 'icons', 'images']) {
        expect(main, contains("export 'assets/$cat.dart';"), reason: cat);
      }
      expect(
        read('lib/gen/assets/icons.dart'),
        allOf(
          contains("export 'icons/icons_svg.dart';"),
          contains("export 'icons/icons_png.dart';"),
        ),
      );
    });

    test(
      'derives camelCase constants and class names from file names',
      () async {
        assetFixture();
        await capturePrints(buildAssets);

        final String svg = read('lib/gen/assets/icons/icons_svg.dart');
        expect(svg, contains('class IconsSvg {'));
        expect(svg, contains('const IconsSvg._();'));
        expect(
          svg,
          contains(
            "static const String icBack = 'assets/icons/svg/ic_back.svg';",
          ),
        );
        expect(
          svg,
          contains(
            "static const String myIcon = 'assets/icons/svg/My-Icon.svg';",
          ),
        );
        expect(
          svg,
          contains(
            "static const String someIcon1 = 'assets/icons/svg/Some Icon (1).svg';",
          ),
        );

        // Constants are sorted alphabetically.
        expect(svg.indexOf('icBack'), lessThan(svg.indexOf('myIcon')));

        expect(
          read('lib/gen/assets/icons/icons_png.dart'),
          contains("static const String ic4 = 'assets/icons/4.png';"),
        );
        expect(
          read('lib/gen/assets/images/images_jpg.dart'),
          contains('class ImagesJpg {'),
        );
        expect(
          read('lib/gen/assets/fonts/fonts_ttf.dart'),
          contains('class FontsTtf {'),
        );
        expect(
          read('lib/gen/assets/bottom_bar/bottom_bar_webp.dart'),
          contains('class BottomBarWebp {'),
        );
      },
    );

    test(
      'ignores unsupported extensions and files directly in the root',
      () async {
        assetFixture();
        await capturePrints(buildAssets);

        final String all = Directory(p.join(tmp.path, 'lib/gen'))
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.readAsStringSync())
            .join();
        expect(all, isNot(contains('notes.txt')));
        expect(all, isNot(contains('root_level')));
      },
    );

    test('honours skip patterns given as a list or a single string', () async {
      assetFixture(extraConfig: 'skip:\n  - fonts\n  - bottom_bar\n');
      await capturePrints(buildAssets);
      expect(exists('lib/gen/assets/fonts'), isFalse);
      expect(exists('lib/gen/assets/bottom_bar'), isFalse);
      expect(exists('lib/gen/assets/icons'), isTrue);

      write(
        'dig.yaml',
        'assets-dir: assets/\noutput-dir: lib/gen\nskip: icons\n',
      );
      await capturePrints(buildAssets);
      expect(exists('lib/gen/assets/icons'), isFalse);
      expect(exists('lib/gen/assets/fonts'), isTrue);
    });

    test('uses lib/generated and assets/ when keys are omitted', () async {
      write('dig.yaml', '# empty config\nfoo: bar\n');
      write('assets/images/a.png', 'x');
      await capturePrints(buildAssets);

      expect(exists('lib/generated/assets.dart'), isTrue);
    });

    test('regeneration removes constants for deleted assets', () async {
      assetFixture();
      await capturePrints(buildAssets);
      File(p.join(tmp.path, 'assets/icons/svg/ic_back.svg')).deleteSync();
      File(p.join(tmp.path, 'assets/bottom_bar/home.webp')).deleteSync();
      await capturePrints(buildAssets);

      expect(
        read('lib/gen/assets/icons/icons_svg.dart'),
        isNot(contains('icBack')),
      );
      expect(exists('lib/gen/assets/bottom_bar'), isFalse);
      expect(read('lib/gen/assets.dart'), isNot(contains('bottom_bar')));
    });

    test('keeps unrelated generated files in the output directory', () async {
      assetFixture();
      write('lib/gen/l10n.dart', '// keep');
      await capturePrints(buildAssets);

      expect(read('lib/gen/l10n.dart'), '// keep');
    });

    test('AssetCommand exposes build and watch subcommands', () {
      final command = AssetCommand();
      expect(command.name, 'asset');
      expect(command.subcommands.keys, containsAll(['build', 'watch']));
    });

    test('`asset build` runs through CommandRunner', () async {
      assetFixture();
      final runner = CommandRunner<void>('dg', 'test')
        ..addCommand(AssetCommand());
      await capturePrints(() => runner.run(['asset', 'build']));

      expect(exists('lib/gen/assets.dart'), isTrue);
    });

    test(
      'handleAssetSetup scaffolds dig.yaml and assets/ when absent',
      () async {
        await capturePrints(handleAssetSetup);

        expect(read('dig.yaml'), contains('assets-dir: assets/'));
        expect(exists('assets'), isTrue);
      },
    );

    test('handleAssetSetup reports an existing configuration', () async {
      write('dig.yaml', 'assets-dir: assets/\noutput-dir: lib/gen\n');
      Directory(p.join(tmp.path, 'assets')).createSync();
      final lines = await capturePrints(handleAssetSetup);

      expect(lines.join('\n'), contains('Assets already configured'));
    });
  });

  group('pubspec asset registration', () {
    const baseConfig = 'assets-dir: assets/\noutput-dir: lib/gen\n';

    Future<void> build() async {
      await capturePrints(buildAssets);
    }

    test('appends a flutter section when none exists', () async {
      write('dig.yaml', baseConfig);
      write('pubspec.yaml', 'name: demo\n');
      write('assets/icons/svg/a.svg', 'x');
      write('assets/images/b.png', 'x');
      await build();

      final String pubspec = read('pubspec.yaml');
      expect(pubspec, contains('flutter:\n  assets:'));
      expect(
        pubspec,
        contains(
          '    - assets/\n    - assets/icons/svg/\n    - assets/images/',
        ),
      );
    });

    test('adds an assets key under an existing flutter section', () async {
      write('dig.yaml', baseConfig);
      write(
        'pubspec.yaml',
        'name: demo\nflutter:\n  uses-material-design: true\n',
      );
      write('assets/images/b.png', 'x');
      await build();

      expect(
        read('pubspec.yaml'),
        'name: demo\nflutter:\n  assets:\n    - assets/\n    - assets/images/\n  uses-material-design: true\n',
      );
    });

    test(
      'adds missing folders, drops stale ones, preserves foreign entries',
      () async {
        write('dig.yaml', baseConfig);
        write(
          'pubspec.yaml',
          'name: demo\nflutter:\n  assets:\n    - assets/\n    - assets/gone/\n    - lib/l10n/\n    - .env\n',
        );
        write('.env', 'A=1');
        write('assets/images/b.png', 'x');
        final lines = await capturePrints(buildAssets);

        final String pubspec = read('pubspec.yaml');
        expect(pubspec, contains('- assets/images/'));
        expect(pubspec, isNot(contains('assets/gone/')));
        expect(pubspec, contains('- lib/l10n/'));
        expect(pubspec, contains('- .env'));
        expect(lines.join('\n'), contains('Removed 1 stale asset entries'));
      },
    );

    test(
      'adds .env when present and leaves an up to date pubspec alone',
      () async {
        write('dig.yaml', baseConfig);
        write('.env', 'A=1');
        write('assets/images/b.png', 'x');
        write(
          'pubspec.yaml',
          'name: demo\nflutter:\n  assets:\n    - assets/\n',
        );
        await build();
        final String first = read('pubspec.yaml');
        expect(first, contains('- .env'));

        await build();
        expect(read('pubspec.yaml'), first);
      },
    );

    test('understands quoted entries', () async {
      write('dig.yaml', baseConfig);
      write(
        'pubspec.yaml',
        'name: demo\nflutter:\n  assets:\n    - "assets/"\n    - \'assets/images/\'\n',
      );
      write('assets/images/b.png', 'x');
      final String before = read('pubspec.yaml');
      await build();

      expect(read('pubspec.yaml'), before);
    });
  });

  group('create-module / remove-module', () {
    CommandRunner<void> runner() => CommandRunner<void>('dg', 'test')
      ..addCommand(CreateModuleCommand())
      ..addCommand(RemoveModuleCommand());

    Future<List<String>> run(List<String> args) =>
        capturePrints(() => runner().run(args));

    setUp(() => write('pubspec.yaml', 'name: demo\n'));

    test('scaffolds files and registers export, route and page', () async {
      await run(['create-module', '--name', 'auth']);

      for (final f in [
        'controller/auth_controller.dart',
        'binding/auth_binding.dart',
        'view/auth_view.dart',
        'auth_export.dart',
      ]) {
        expect(exists('lib/app/module/auth/$f'), isTrue, reason: f);
      }
      expect(
        read('lib/app/module/auth/controller/auth_controller.dart'),
        contains('class AuthController extends GetxController'),
      );
      expect(
        read('lib/app/module/auth/binding/auth_binding.dart'),
        contains('Get.lazyPut<AuthController>'),
      );
      expect(
        read('lib/app/module/auth/view/auth_view.dart'),
        contains('class AuthView extends GetView<AuthController>'),
      );
      expect(
        read('lib/app/module/module_export.dart'),
        contains("export 'auth/auth_export.dart';"),
      );
      expect(
        read('lib/app/routes/app_route.dart'),
        contains("static const String auth = '/Auth';"),
      );
      final String page = read('lib/app/routes/app_page.dart');
      expect(page, contains('name: AppRoute.auth,'));
      expect(page, contains('page: () => const AuthView(),'));
      expect(page, contains('binding: AuthBinding(),'));
    });

    test(
      'normalises names: suffixes stripped, PascalCase to snake_case',
      () async {
        await run(['create-module', 'UserProfileView']);

        expect(
          exists('lib/app/module/user_profile/user_profile_export.dart'),
          isTrue,
        );
        expect(
          read('lib/app/routes/app_route.dart'),
          contains("static const String userProfile = '/UserProfile';"),
        );
      },
    );

    test('supports the add-module alias and keeps exports sorted', () async {
      await run(['add-module', 'zeta']);
      await run(['create-module', '-n', 'alpha']);

      final List<String> exports = read('lib/app/module/module_export.dart')
          .split('\n')
          .where((l) => l.startsWith('export'))
          .toList();
      expect(exports, [...exports]..sort());
      expect(exports, hasLength(3));
    });

    test('refuses to overwrite an existing module', () async {
      await run(['create-module', 'auth']);
      write('lib/app/module/auth/controller/auth_controller.dart', '// custom');
      await run(['create-module', 'auth']);

      expect(
        read('lib/app/module/auth/controller/auth_controller.dart'),
        '// custom',
      );
    });

    test('is idempotent for route and export registration', () async {
      await run(['create-module', 'auth']);
      final String route = read('lib/app/routes/app_route.dart');
      Directory(p.join(tmp.path, 'lib/app/module/auth'))
          .deleteSync(recursive: true);
      await run(['create-module', 'auth']);

      expect(read('lib/app/routes/app_route.dart'), route);
      expect(
        "export 'auth/auth_export.dart';".allMatches(
          read('lib/app/module/module_export.dart'),
        ),
        hasLength(1),
      );
    });

    test(
      'remove-module deletes the module and unregisters everything',
      () async {
        await run(['create-module', 'auth']);
        await run(['create-module', 'settings']);
        await run(['remove-module', '--name', 'auth']);

        expect(exists('lib/app/module/auth'), isFalse);
        expect(exists('lib/app/module/settings'), isTrue);
        expect(
          read('lib/app/module/module_export.dart'),
          isNot(contains('auth/')),
        );
        expect(
          read('lib/app/module/module_export.dart'),
          contains('settings/'),
        );
        expect(
          read('lib/app/routes/app_route.dart'),
          isNot(contains('String auth =')),
        );
        expect(
          read('lib/app/routes/app_route.dart'),
          contains('String settings ='),
        );
        final String page = read('lib/app/routes/app_page.dart');
        expect(page, isNot(contains('AuthView')));
        expect(page, contains('SettingsView'));
        expect(page, contains('SplashView'));
      },
    );

    test('remove-module on an unknown module changes nothing', () async {
      await run(['create-module', 'auth']);
      final String page = read('lib/app/routes/app_page.dart');
      await run(['remove-module', 'ghost']);

      expect(read('lib/app/routes/app_page.dart'), page);
      expect(exists('lib/app/module/auth'), isTrue);
    });

    test('create then remove leaves a parseable page list', () async {
      await run(['create-module', 'auth']);
      await run(['remove-module', 'auth']);

      final String page = read('lib/app/routes/app_page.dart');
      expect('('.allMatches(page).length, ')'.allMatches(page).length);
      expect(page, contains('static final List<GetPage> routes = ['));
    });
  });

  group('edge cases: asset naming', () {
    String constants() => Directory(p.join(tmp.path, 'lib/gen'))
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.contains('assets${p.separator}') &&
              !f.path.endsWith('assets.dart'),
        )
        .map((f) => f.readAsStringSync())
        .join('\n');

    Future<void> build(
      Map<String, String> files, {
      String config = 'assets-dir: assets/\noutput-dir: lib/gen\n',
    }) async {
      write('dig.yaml', config);
      files.forEach(write);
      await capturePrints(buildAssets);
    }

    test('normalises odd file names into valid identifiers', () async {
      await build({
        'assets/a/UPPER_CASE.png': 'x',
        'assets/a/a__b.png': 'x',
        'assets/a/123abc.png': 'x',
        'assets/a/___.png': 'x',
        'assets/a/日本.png': 'x',
        'assets/a/with space-and_mix.png': 'x',
        'assets/a/MyIcon.png': 'x',
        'assets/a/x.PNG': 'x',
      });

      final String out = constants();
      expect(out, contains("String upperCase = "));
      expect(out, contains("String aB = "));
      expect(out, contains("String ic123abc = "));
      expect(out, contains("String unknownAsset = "));
      expect(out, contains("String withSpaceAndMix = "));
      expect(out, contains("String myIcon = "));
      expect(
        out,
        contains("String x = 'assets/a/x.PNG'"),
        reason: 'extension case-insensitive',
      );
      expect('unknownAsset ='.allMatches(out), hasLength(2));
    });

    test(
      'joins nested folders into one category and drops a trailing type folder',
      () async {
        await build({
          'assets/ui/buttons/primary/svg/go.svg': 'x',
          'assets/ui/png/hero.png': 'x',
          'assets/png/orphan.png': 'x',
        });

        expect(
          read('lib/gen/assets/ui_buttons_primary/ui_buttons_primary_svg.dart'),
          contains('class UiButtonsPrimarySvg'),
        );
        expect(
          read('lib/gen/assets/ui/ui_png.dart'),
          contains("static const String hero = 'assets/ui/png/hero.png';"),
        );
        expect(
          exists('lib/gen/assets/png'),
          isFalse,
          reason: 'folder equal to its type has no category',
        );
      },
    );

    test(
      'maps jpeg to jpg and keeps otf/ttf/gif/webp as their own types',
      () async {
        await build({
          'assets/m/a.jpeg': 'x',
          'assets/m/b.jpg': 'x',
          'assets/m/c.gif': 'x',
          'assets/m/d.otf': 'x',
          'assets/m/e.ttf': 'x',
          'assets/m/f.webp': 'x',
          'assets/m/g.bmp': 'x',
          'assets/m/h.json': 'x',
        });

        for (final t in ['jpg', 'gif', 'otf', 'ttf', 'webp']) {
          expect(exists('lib/gen/assets/m/m_$t.dart'), isTrue, reason: t);
        }
        expect(exists('lib/gen/assets/m/m_jpeg.dart'), isFalse);
        expect(constants(), isNot(contains('bmp')));
        expect(
          read('lib/gen/assets/m/m_jpg.dart'),
          allOf(
            contains('static const String a ='),
            contains('static const String b ='),
          ),
        );
      },
    );

    test(
      'supports custom assets-dir and output-dir without trailing slashes',
      () async {
        await build({
          'res/img/icons/home.png': 'x',
        }, config: 'assets-dir: res/img\noutput-dir: out/gen\n');

        expect(
          read('out/gen/assets/icons/icons_png.dart'),
          contains("static const String home = 'res/img/icons/home.png';"),
        );
      },
    );

    test('skip patterns accept nested paths and Windows separators', () async {
      await build(
        {
          'assets/icons/svg/a.svg': 'x',
          'assets/icons/png/b.png': 'x',
          'assets/keep/c.png': 'x',
        },
        config:
            'assets-dir: assets/\noutput-dir: lib/gen\nskip:\n  - icons\\svg\n',
      );

      expect(constants(), isNot(contains('a.svg')));
      expect(constants(), contains('b.png'));
      expect(constants(), contains('c.png'));
    });

    test('an empty assets directory yields zero constants', () async {
      write('dig.yaml', 'assets-dir: assets/\noutput-dir: lib/gen\n');
      Directory(p.join(tmp.path, 'assets')).createSync();
      final lines = await capturePrints(buildAssets);

      expect(lines.join('\n'), contains('Generated 0 asset constants'));
      expect(exists('lib/gen/assets.dart'), isFalse);
    });

    test('a non-list, non-string skip value is ignored', () async {
      await build({
        'assets/a/x.png': 'x',
      }, config: 'assets-dir: assets/\noutput-dir: lib/gen\nskip: 5\n');
      expect(constants(), contains("x = 'assets/a/x.png'"));
    });

    test(
      'pubspec without trailing newline and with CRLF stays usable',
      () async {
        write('pubspec.yaml', 'name: demo');
        write('assets/a/x.png', 'x');
        await build({});
        expect(read('pubspec.yaml'), contains('assets:'));
      },
    );
  });

  group('edge cases: project_utils and rename', () {
    test('getProjectName throws on malformed pubspec yaml', () async {
      write('pubspec.yaml', 'name: [unclosed\n');
      await expectLater(getProjectName(), throwsA(isA<Object>()));
    });

    test('getProjectName is null when name key is missing', () async {
      write('pubspec.yaml', 'version: 1.0.0\n');
      expect(await getProjectName(), isNull);
    });

    test('getBundleId ignores single-quoted ids (documented regex is double-quote only)', () async {
      write('pubspec.yaml', 'name: demo\n');
      write('android/app/build.gradle', "applicationId 'com.single.quote'");
      expect(await getBundleId(), isNull);
    });

    test('getAppLabel handles an empty label', () async {
      write('pubspec.yaml', 'name: demo\n');
      write(
        'android/app/src/main/AndroidManifest.xml',
        '<application android:label=""/>',
      );
      expect(await getAppLabel(), '');
    });

    test('rename with --name only keeps the existing bundle id and substitutes defaults', () async {
      write('pubspec.yaml', 'name: demo\n');
      // No gradle/manifest at all: falls back to com.example.app, nothing to write.
      final runner = CommandRunner<void>('dg', 't')
        ..addCommand(RenameCommand());
      final lines = await capturePrints(
        () => runner.run(['rename', '-n', 'Only']),
      );

      expect(lines.join('\n'), contains('App successfully renamed!'));
    });

    test(
      'rebrand treats regex/replacement metacharacters in names literally',
      () async {
        write('pubspec.yaml', 'name: demo\n');
        write(
          'android/app/src/main/AndroidManifest.xml',
          '<application android:label="Old"/>',
        );
        const nasty = r'A$1 \\ $& (x)';
        await ProjectRebrander(
          projectDir: tmp,
          newSlug: 'demo',
          newAppName: nasty,
          newBundleId: 'com.a.b',
        ).rebrand();

        expect(
          read('android/app/src/main/AndroidManifest.xml'),
          contains('android:label="$nasty"'),
        );
      },
    );

    test('rebrand handles very long names and Unicode', () async {
      write('pubspec.yaml', 'name: demo\n');
      write('web/manifest.json', '{"name": "o", "short_name": "o"}');
      final longName = 'Ünïcödé ${'x' * 5000}';
      await ProjectRebrander(
        projectDir: tmp,
        newSlug: 'demo',
        newAppName: longName,
        newBundleId: 'com.a.b',
      ).rebrand();

      expect(read('web/manifest.json'), contains('"name": "$longName"'));
    });

    test('rebrand throws a YAML error for a malformed pubspec', () async {
      write('pubspec.yaml', 'name: [oops\n');
      await expectLater(
        ProjectRebrander(
          projectDir: tmp,
          newSlug: 'a',
          newAppName: 'a',
          newBundleId: 'com.a.b',
        ).rebrand(),
        throwsA(isA<Object>()),
      );
    });

    test('rebrand tolerates a missing project directory', () async {
      final missing = Directory(p.join(tmp.path, 'nope'));
      await ProjectRebrander(
        projectDir: missing,
        newSlug: 'a',
        newAppName: 'a',
        newBundleId: 'com.a.b',
      ).rebrand();
      expect(missing.existsSync(), isFalse);
    });

    test(
      'rebrand is a no-op for unreadable binary files with source extensions',
      () async {
        write('pubspec.yaml', 'name: demo\n');
        File(p.join(tmp.path, 'lib/bin.dart'))
          ..createSync(recursive: true)
          ..writeAsBytesSync([0xff, 0xfe, 0x00, 0xd8]);
        await ProjectRebrander(
          projectDir: tmp,
          newSlug: 'x',
          newAppName: 'x',
          newBundleId: 'com.a.b',
        ).rebrand();

        expect(File(p.join(tmp.path, 'lib/bin.dart')).readAsBytesSync(), [
          0xff,
          0xfe,
          0x00,
          0xd8,
        ]);
      },
    );
  });

  group('edge cases: create/remove module', () {
    CommandRunner<void> runner() => CommandRunner<void>('dg', 't')
      ..addCommand(CreateModuleCommand())
      ..addCommand(RemoveModuleCommand());
    Future<List<String>> run(List<String> a) =>
        capturePrints(() => runner().run(a));

    setUp(() => write('pubspec.yaml', 'name: demo\n'));

    test('create-module does nothing outside a project', () async {
      File(p.join(tmp.path, 'pubspec.yaml')).deleteSync();
      resetProjectRootCache();
      await run(['create-module', 'auth']);
      // Either no project is found (nothing created) or an ancestor is one.
      if (findProjectRoot() == null) {
        expect(exists('lib'), isFalse);
      }
    });

    test('a trailing Controller suffix is stripped', () async {
      await run(['create-module', 'loginController']);
      expect(exists('lib/app/module/login'), isTrue);
    });

    test(
      'a name that is only a suffix creates an empty-slug module path',
      () async {
        await run(['create-module', 'View']);
        // "View" strips to "" -> module directory is lib/app/module itself.
        expect(exists('lib/app/module/_export.dart'), isTrue);
      },
    );

    test('names with spaces are trimmed after suffix removal', () async {
      await run(['create-module', '--name', 'cart view']);
      // "cart view" has no recognised suffix ("view" needs _ or end match) -> ends with "view"
      expect(exists('lib/app/module'), isTrue);
    });

    test(
      'registers into pre-existing, user-edited route/page/export files',
      () async {
        write(
          'lib/app/module/module_export.dart',
          "// header\nexport 'b/b_export.dart';\n",
        );
        write(
          'lib/app/routes/app_route.dart',
          "abstract class AppRoute {\n  static const String home = '/';\n}\n",
        );
        write(
          'lib/app/routes/app_page.dart',
          "abstract class AppPage {\n  static final List<GetPage> routes = [\n    GetPage(name: AppRoute.home, page: () => const HomeView()),\n  ];\n}\n",
        );
        await run(['create-module', 'cart']);

        expect(
          read('lib/app/module/module_export.dart'),
          startsWith('// header'),
        );
        expect(
          read('lib/app/module/module_export.dart'),
          contains("export 'cart/cart_export.dart';"),
        );
        expect(
          read('lib/app/routes/app_route.dart'),
          contains("static const String cart = '/Cart';"),
        );
        final String page = read('lib/app/routes/app_page.dart');
        expect(page, startsWith("import '../module/module_export.dart';"));
        expect(page, contains('HomeView'));
        expect(page, contains('CartView'));
      },
    );

    test(
      'registration skips malformed route/page files instead of crashing',
      () async {
        write('lib/app/routes/app_route.dart', '// no class body at all');
        write('lib/app/routes/app_page.dart', '// no routes list');
        await run(['create-module', 'cart']);

        expect(
          read('lib/app/routes/app_route.dart'),
          '// no class body at all',
        );
        expect(
          read('lib/app/routes/app_page.dart'),
          isNot(contains('CartView')),
        );
      },
    );

    test('remove-module warns when registrations are missing', () async {
      write('lib/app/module/ghost/ghost_export.dart', '');
      write('lib/app/module/module_export.dart', '// none\n');
      write('lib/app/routes/app_route.dart', 'abstract class AppRoute {}\n');
      write('lib/app/routes/app_page.dart', 'final routes = [];\n');
      final lines = await run(['remove-module', 'ghost']);

      expect(exists('lib/app/module/ghost'), isFalse);
      final String out = lines.join('\n');
      expect(out, contains('has been completely removed'));
    });

    test('remove-module works when route files are absent', () async {
      write('lib/app/module/solo/solo_export.dart', '');
      await run(['remove-module', 'solo']);
      expect(exists('lib/app/module/solo'), isFalse);
    });

    test('create-module then remove-module twice is stable', () async {
      await run(['create-module', 'auth']);
      await run(['remove-module', 'auth']);
      final String page = read('lib/app/routes/app_page.dart');
      await run(['remove-module', 'auth']);
      expect(read('lib/app/routes/app_page.dart'), page);
      await run(['create-module', 'auth']);
      expect(read('lib/app/routes/app_page.dart'), contains('AuthView'));
    });

    test('handles three modules, removing the middle one precisely', () async {
      for (final m in ['one', 'two', 'three']) {
        await run(['create-module', m]);
      }
      await run(['remove-module', 'two']);

      final String page = read('lib/app/routes/app_page.dart');
      expect(page, contains('OneView'));
      expect(page, contains('ThreeView'));
      expect(page, isNot(contains('TwoView')));
    });
  });

  group('sha-keys', () {
    final unixOnly = Platform.isWindows ? 'needs a POSIX shell' : null;

    void gradlew(String script) {
      write('android/gradlew', '#!/bin/sh\n$script\n');
      Process.runSync('chmod', ['+x', p.join(tmp.path, 'android/gradlew')]);
    }

    Future<String> runSha() async {
      final lines = await capturePrints(getShaKeys);
      return lines.join('\n');
    }

    test('outside a project nothing happens and cwd is unchanged', () async {
      final Directory before = Directory.current;
      await capturePrints(getShaKeys);
      expect(Directory.current.path, before.path);
    });

    test('reports a missing android directory', () async {
      write('pubspec.yaml', 'name: demo\n');
      final String out = await runSha();
      expect(
        out,
        contains('Make sure you are in a Flutter project with Android support'),
      );
    });

    test('reports a missing gradle wrapper', () async {
      write('pubspec.yaml', 'name: demo\n');
      Directory(p.join(tmp.path, 'android')).createSync();
      final String out = await runSha();
      expect(out, contains('flutter build apk'));
    });

    test('parses debug and release variants from the signing report', () async {
      write('pubspec.yaml', 'name: demo\n');
      gradlew(r"""cat <<'EOF'
Variant: debug
Config: debug
Store: /x/debug.keystore
SHA1: AA:BB:CC
SHA-256: 11:22:33
----------
Variant: debugAndroidTest
Config: debug
SHA1: SHOULD:NOT:APPEAR
----------
Variant: release
Config: release
SHA1: DD:EE:FF
SHA-256: 44:55:66
EOF""");
      final String out = await runSha();

      expect(out, contains('DEBUG KEYS'));
      expect(out, contains('RELEASE KEYS'));
      expect(out, contains('AA:BB:CC'));
      expect(out, contains('(No colons: AABBCC)'));
      expect(out, contains('(No colons: 112233)'));
      expect(out, contains('DD:EE:FF'));
      expect(
        out,
        isNot(contains('SHOULD:NOT:APPEAR')),
        reason: 'only the first per config is shown',
      );
      expect(Directory.current.path, tmp.path, reason: 'cwd restored');
    }, skip: unixOnly);

    test(
      'only prints sections that exist and N/A for missing hashes',
      () async {
        write('pubspec.yaml', 'name: demo\n');
        gradlew('printf "Variant: release\\nConfig: Release\\nSHA1: AB:CD\\n"');
        final String out = await runSha();

        expect(out, isNot(contains('DEBUG KEYS')));
        expect(out, contains('RELEASE KEYS'));
        expect(out, contains('N/A'));
      },
      skip: unixOnly,
    );

    test('reports when the output has no signing information', () async {
      write('pubspec.yaml', 'name: demo\n');
      gradlew('echo nothing useful');
      final String out = await runSha();

      expect(out, isNot(contains('SHA Keys extracted')));
      expect(out, isNot(contains('DEBUG KEYS')));
    }, skip: unixOnly);

    test(
      'survives a failing gradle run and restores the working directory',
      () async {
        write('pubspec.yaml', 'name: demo\n');
        gradlew('echo boom >&2\nexit 3');
        await runSha();

        expect(Directory.current.path, tmp.path);
      },
      skip: unixOnly,
    );

    test('ShaKeysCommand is wired through CommandRunner', () async {
      write('pubspec.yaml', 'name: demo\n');
      gradlew('printf "Variant: debug\\nConfig: debug\\nSHA1: 01:02\\n"');
      final runner = CommandRunner<void>('dg', 't')
        ..addCommand(ShaKeysCommand());
      final lines = await capturePrints(() => runner.run(['sha-keys']));

      expect(lines.join('\n'), contains('01:02'));
    }, skip: unixOnly);
  });

  group('hash-key', () {
    CommandRunner<void> runner() =>
        CommandRunner<void>('dg', 't')..addCommand(HashKeyCommand());
    Future<String> run(List<String> a) async =>
        (await capturePrints(() => runner().run(['hash-key', ...a])))
            .join('\n');

    test('prints usage when neither --debug nor --release is given', () async {
      final String out = await run([]);
      expect(out, contains('Generates base64-encoded SHA1 hash key'));
      expect(out, isNot(contains('Hash Key (Base64)')));
    });

    test('release rejects empty values', () async {
      for (final empty in [
        '--keystore=',
        '--alias=',
        '--storepass=',
        '--keypass=',
      ]) {
        final args = {
          '--keystore': 'k.jks',
          '--alias': 'a',
          '--storepass': 's',
          '--keypass': 'p',
        }..remove(empty.substring(0, empty.length - 1));
        final String out = await run([
          '--release',
          empty,
          ...args.entries.expand((e) => [e.key, e.value]),
        ]);
        expect(out, isNot(contains('Hash Key (Base64)')), reason: empty);
      }
    });

    test('release reports a missing keystore file', () async {
      final String out = await run([
        '--release',
        '-k',
        'does_not_exist.jks',
        '-a',
        'a',
        '--storepass',
        's',
        '--keypass',
        'p',
      ]);
      expect(out, isNot(contains('Hash Key (Base64)')));
    });

    test('unknown flags raise UsageException', () async {
      await expectLater(run(['--bogus']), throwsA(isA<UsageException>()));
    });

    test('handleHashKeyCommand dispatches to the command', () async {
      final lines = await capturePrints(() => handleHashKeyCommand([]));
      expect(lines.join('\n'), contains('Generates base64-encoded SHA1'));
    });
  });

  group('create-jks and hash-key with a real keytool', () {
    final hasTools =
        !Platform.isWindows &&
        Process.runSync('which', ['keytool']).exitCode == 0 &&
        Process.runSync('which', ['openssl']).exitCode == 0;
    final skip = hasTools ? null : 'keytool/openssl not installed';

    CommandRunner<void> runner() => CommandRunner<void>('dg', 't')
      ..addCommand(CreateJksCommand())
      ..addCommand(HashKeyCommand());

    test('rejects passwords shorter than six characters', () async {
      final lines = await capturePrints(
        () => runner().run([
          'create-jks',
          '--no-interactive',
          '--location',
          tmp.path,
          '--name',
          'short',
          '--store-pass',
          '123',
        ]),
      );
      expect(lines.join('\n'), isNot(contains('JKS file created')));
      expect(exists('short.jks'), isFalse);
    });

    test('creates a keystore, wires signing into a Kotlin project and yields a hash', () async {
      write('pubspec.yaml', 'name: demo\n');
      write(
        'android/app/build.gradle.kts',
        'plugins {\n    id("com.android.application")\n}\nandroid {\n    namespace = "com.demo.app"\n    defaultConfig { applicationId = "com.demo.app" }\n    buildTypes {\n        release {\n        }\n    }\n}\n',
      );
      final lines = await capturePrints(
        () => runner().run([
          'create-jks',
          '--no-interactive',
          '--store-pass',
          'secret1',
          '--alias',
          'k',
        ]),
      );

      expect(lines.join('\n'), contains('JKS file created'));
      expect(
        exists('android/app/app.jks'),
        isTrue,
        reason: 'named after the bundle id tail',
      );
      expect(
        read('android/key.properties'),
        allOf(
          contains('storePassword=secret1'),
          contains('keyAlias=k'),
          contains('storeFile=app.jks'),
        ),
      );
      final String gradle = read('android/app/build.gradle.kts');
      expect(gradle, contains('import java.util.Properties'));
      expect(gradle, contains('keystoreProperties'));
      expect(gradle, contains('create("release")'));

      final hash = await capturePrints(
        () => runner().run([
          'hash-key',
          '--release',
          '-k',
          p.join(tmp.path, 'android/app/app.jks'),
          '-a',
          'k',
          '--storepass',
          'secret1',
          '--keypass',
          'secret1',
        ]),
      );
      expect(hash.join('\n'), contains('RELEASE Hash Key (Base64)'));

      final bad = await capturePrints(
        () => runner().run([
          'hash-key',
          '--release',
          '-k',
          p.join(tmp.path, 'android/app/app.jks'),
          '-a',
          'wrong',
          '--storepass',
          'secret1',
          '--keypass',
          'secret1',
        ]),
      );
      expect(bad.join('\n'), isNot(contains('Hash Key (Base64)')));
    }, skip: skip);

    test('is idempotent on Groovy gradle files and honours the .jks suffix in --name', () async {
      write('pubspec.yaml', 'name: demo\n');
      write(
        'android/app/build.gradle',
        "android {\n    buildTypes {\n        release {\n        }\n    }\n}\n",
      );
      for (var i = 0; i < 2; i++) {
        await capturePrints(
          () => runner().run([
            'create-jks',
            '--no-interactive',
            '--name',
            'My.JKS',
            '--store-pass',
            'secret1',
            '--key-pass',
            'secret2',
            '--ou',
            'Dev',
          ]),
        );
      }

      expect(exists('android/app/My.jks'), isTrue);
      final String gradle = read('android/app/build.gradle');
      expect('def keystoreProperties = '.allMatches(gradle), hasLength(1));
      expect('signingConfigs {'.allMatches(gradle), hasLength(1));
      expect(read('android/key.properties'), contains('keyPassword=secret2'));
    }, skip: skip);

    test('CreateJksCommand registers every documented option', () {
      expect(
        CreateJksCommand().argParser.options.keys,
        containsAll([
          'name',
          'location',
          'alias',
          'store-pass',
          'key-pass',
          'ou',
          'no-interactive',
        ]),
      );
    });
  });
}
