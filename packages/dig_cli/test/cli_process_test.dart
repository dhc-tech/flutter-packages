// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// End-to-end tests that run the real CLI entry point in a child process.
//
// Child processes are the only way to observe `exit()` codes and to control
// HOME / PATH (fake `flutter` and `pod` shell scripts) without touching the
// developer's machine or the network. Nothing here changes this process's
// working directory, so it is safe to run in parallel with other suites.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class Run {
  Run(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
  String get all => '$stdout\n$stderr';
}

late Directory work;
late String kernel;
late Directory kernelDir;

const fakeFlutter = r'''#!/bin/sh
echo "$@" >> "$FAKE_LOG"
if [ "$1" = "build" ] && [ -z "$FAKE_NOOUT" ]; then
  case "$2" in
    apk) mkdir -p build/app/outputs/flutter-apk; echo apk > build/app/outputs/flutter-apk/app-release.apk;;
    appbundle) mkdir -p build/app/outputs/bundle/release; echo aab > build/app/outputs/bundle/release/app-release.aab;;
    ipa) mkdir -p build/ios/ipa; echo ipa > build/ios/ipa/Runner.ipa;;
  esac
fi
if [ "$1" = "clean" ]; then rm -rf build; fi
if [ -n "$FAKE_EXIT" ]; then echo "fake failure" >&2; exit "$FAKE_EXIT"; fi
echo "fake flutter ok"
''';

const fakePod = '#!/bin/sh\necho "pod \$@" >> "\$FAKE_LOG"\n';

void writeIn(Directory root, String path, String content) {
  final file = File(p.join(root.path, path));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Future<Run> dg(
  List<String> args, {
  required Directory cwd,
  String stdin = '',
  Map<String, String> env = const {},
  bool fakeTools = true,
}) async {
  final String sep = Platform.isWindows ? ';' : ':';
  final environment = <String, String>{
    'HOME': p.join(work.path, 'home'),
    'USERPROFILE': p.join(work.path, 'home'),
    'FAKE_LOG': p.join(work.path, 'calls.log'),
    if (fakeTools)
      'PATH': '${p.join(work.path, 'bin')}$sep${Platform.environment['PATH']}',
    ...env,
  };
  final Process proc = await Process.start(
    Platform.resolvedExecutable,
    [kernel, ...args],
    workingDirectory: cwd.path,
    environment: environment,
  );
  proc.stdin.write(stdin);
  await proc.stdin.close();
  final results = await Future.wait([
    proc.stdout.transform(utf8.decoder).join(),
    proc.stderr.transform(utf8.decoder).join(),
    proc.exitCode,
  ]);
  return Run(results[2] as int, results[0] as String, results[1] as String);
}

Directory project({String name = 'demo'}) {
  final dir = Directory(p.join(work.path, 'proj'))..createSync(recursive: true);
  writeIn(dir, 'pubspec.yaml', 'name: $name\n');
  return dir;
}

List<String> calls() {
  final log = File(p.join(work.path, 'calls.log'));
  return log.existsSync() ? log.readAsLinesSync() : [];
}

void main() {
  final bool posix = !Platform.isWindows;
  final String? skipWin = posix ? null : 'requires POSIX shell scripts';

  setUpAll(() async {
    kernelDir = Directory.systemTemp.createTempSync('dig_cli_kernel_');
    final Uri? lib = await Isolate.resolvePackageUri(
      Uri.parse('package:dig_cli/src/version_helper.dart'),
    );
    final String packageRoot = p.dirname(
      p.dirname(p.dirname(lib!.toFilePath())),
    );
    final String entry = p.join(packageRoot, 'bin', 'dig_cli.dart');
    kernel = p.join(kernelDir.path, 'dg.dill');
    final ProcessResult compiled = await Process.run(
      Platform.resolvedExecutable,
      ['compile', 'kernel', entry, '-o', kernel],
      workingDirectory: packageRoot,
    );
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
  });

  tearDownAll(() => kernelDir.deleteSync(recursive: true));

  setUp(() {
    work = Directory.systemTemp.createTempSync('dig_cli_proc_');
    if (posix) {
      for (final entry in {'flutter': fakeFlutter, 'pod': fakePod}.entries) {
        writeIn(work, 'bin/${entry.key}', entry.value);
        Process.runSync('chmod', ['+x', p.join(work.path, 'bin', entry.key)]);
      }
    }
    Directory(p.join(work.path, 'home')).createSync();
  });

  tearDown(() => work.deleteSync(recursive: true));

  group('exit codes and error handling', () {
    test('unknown command exits 64 with usage', () async {
      final Run r = await dg(['frobnicate'], cwd: work);
      expect(r.exitCode, 64);
      expect(r.all, contains('Could not find a command named "frobnicate"'));
    });

    test('unknown option exits 64', () async {
      final Run r = await dg(['rename', '--nope'], cwd: work);
      expect(r.exitCode, 64);
      expect(r.all, contains('Could not find an option named "--nope"'));
    });

    test('--help exits 0 and lists every command', () async {
      final Run r = await dg(['--help'], cwd: work);
      expect(r.exitCode, 0);
      for (final c in [
        'create',
        'clean',
        'zip',
        'rename',
        'sha-keys',
        'hash-key',
        'create-jks',
        'create-project',
        'create-module',
        'remove-module',
        'setup-aliases',
        'ios',
        'asset',
        'pub-cache',
        'version',
      ]) {
        expect(r.stdout, contains(c), reason: c);
      }
    });

    test('unknown build type exits 64', () async {
      final Run r = await dg(['create', 'dmg'], cwd: work);
      expect(r.exitCode, 64);
      expect(r.all, contains('Unknown build type: "dmg"'));
    });

    for (final cmd in [
      ['create', 'apk', '-o', 'out'],
      ['create', 'bundle', '-o', 'out'],
      ['clean'],
      ['zip'],
    ]) {
      test('`${cmd.join(' ')}` outside a Flutter project exits 1', () async {
        final Run r = await dg(cmd, cwd: work);
        expect(r.exitCode, 1);
        expect(r.all, contains('must be run inside a Flutter project'));
      });
    }

    test('malformed dig.yaml is reported with exit code 1', () async {
      writeIn(work, 'dig.yaml', 'assets-dir: [unclosed\n');
      final Run r = await dg(['asset', 'build'], cwd: work);
      expect(r.exitCode, 1);
      expect(r.all, contains('An error occurred'));
    });

    test('invalid iOS export method exits 64', () async {
      final Run r = await dg(['ios', '-m', 'bogus'], cwd: work);
      expect(r.exitCode, 64);
      expect(r.all, contains('"bogus" is not an allowed value'));
    });

    test('rename validates the bundle id', () async {
      final Run r = await dg(['rename', '-b', 'Not Valid'], cwd: project());
      expect(r.exitCode, 0);
      expect(r.all, contains('Invalid bundle ID format'));
    });
  });

  group('interactive menu', () {
    test('exits 0 on "0" and shows non-project dashboard', () async {
      final Run r = await dg([], cwd: work, stdin: '0\n');
      expect(r.exitCode, 0);
      expect(r.stdout, contains('DIG CLI DASHBOARD'));
      expect(r.stdout, contains('No Flutter Project Found'));
      expect(r.stdout, contains('Project Management (Create)'));
    });

    test('exits instead of looping forever when stdin is closed', () async {
      final Run r = await dg([], cwd: work, stdin: '').timeout(
        const Duration(seconds: 30),
        onTimeout: () => fail('the menu spun on a closed stdin'),
      );
      expect(r.exitCode, 0);
    });

    test('shows the full menu inside a Flutter project', () async {
      final Run r = await dg([], cwd: project(), stdin: '0\n');
      expect(r.exitCode, 0);
      expect(r.stdout, contains('Flutter Project Detected'));
      for (final item in [
        'Build & Release',
        'Clean & Fix',
        'Signing & Keys',
        'Configuration',
        'Project Management',
        'Utilities',
      ]) {
        expect(r.stdout, contains(item), reason: item);
      }
    });

    test('unknown selections redraw the dashboard until exit', () async {
      final Run r = await dg([], cwd: work, stdin: '9\nabc\n\n0\n');
      expect(r.exitCode, 0);
      expect('DIG CLI DASHBOARD'.allMatches(r.stdout).length, greaterThan(2));
    });

    test('sub menus return to the dashboard on 0', () async {
      final Run r = await dg(
        [],
        cwd: project(),
        stdin: '1\n0\n2\n0\n3\n0\n6\n0\n0\n',
      );
      expect(r.exitCode, 0);
      expect(r.stdout, contains('BUILD & RELEASE'));
      expect(r.stdout, contains('CLEAN & FIX'));
      expect(r.stdout, contains('SIGNING & KEYS'));
    });
  });

  group('build (create) with a fake flutter', () {
    test('APK: copies to the output dir with a timestamped name', () async {
      final Directory proj = project();
      final out = Directory(p.join(work.path, 'out'))..createSync();
      final Run r = await dg(['create', 'apk', '-o', out.path], cwd: proj);

      expect(r.exitCode, 0, reason: r.all);
      expect(r.all, contains('APK created successfully'));
      final names = out.listSync().map((e) => p.basename(e.path)).toList();
      expect(
        names.single,
        matches(RegExp(r'^demo-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}\.apk$')),
      );
      expect(
        File(p.join(proj.path, 'build/app/outputs/flutter-apk/app-release.apk'))
            .existsSync(),
        isFalse,
        reason: 'source artifact is moved',
      );
      expect(calls(), contains('build apk --release'));
    }, skip: skipWin);

    test('custom name without timestamp, default type is apk', () async {
      final out = Directory(p.join(work.path, 'out'))..createSync();
      final Run r = await dg([
        'create',
        '-o',
        out.path,
        '-n',
        'my app',
        '--no-timestamp',
      ], cwd: project());

      expect(r.exitCode, 0, reason: r.all);
      expect(File(p.join(out.path, 'my app.apk')).existsSync(), isTrue);
    }, skip: skipWin);

    test('bundle builds an .aab named after the project', () async {
      final out = Directory(p.join(work.path, 'out'))..createSync();
      final Run r = await dg([
        'create',
        'bundle',
        '-o',
        out.path,
        '--no-timestamp',
      ], cwd: project(name: 'shop'));

      expect(r.exitCode, 0, reason: r.all);
      expect(
        File(p.join(out.path, 'shop.aab')).readAsStringSync().trim(),
        'aab',
      );
      expect(calls(), contains('build appbundle --release'));
    }, skip: skipWin);

    test('`build` is accepted as an alias for apk', () async {
      final out = Directory(p.join(work.path, 'out'))..createSync();
      final Run r = await dg([
        'create',
        'build',
        '-o',
        out.path,
        '--no-timestamp',
      ], cwd: project());
      expect(r.exitCode, 0, reason: r.all);
      expect(File(p.join(out.path, 'demo.apk')).existsSync(), isTrue);
    }, skip: skipWin);

    test('flutter failure exits 1 and shows the error', () async {
      final Run r = await dg(
        ['create', 'apk', '-o', work.path],
        cwd: project(),
        env: {'FAKE_EXIT': '2'},
      );
      expect(r.exitCode, 1);
      expect(r.all, contains('Build failed'));
      expect(r.all, contains('fake failure'));
    }, skip: skipWin);

    test('missing build output exits 1', () async {
      final Run r = await dg(
        ['create', 'apk', '-o', work.path],
        cwd: project(),
        env: {'FAKE_NOOUT': '1'},
      );
      expect(r.exitCode, 1);
      expect(r.all, contains('Output file not found'));
    }, skip: skipWin);

    test('unwritable/non-existent output directory exits 1', () async {
      final Run r = await dg([
        'create',
        'apk',
        '-o',
        p.join(work.path, 'no', 'such', 'dir'),
      ], cwd: project());
      expect(r.exitCode, 1);
      expect(r.all, contains('unexpected error'));
    }, skip: skipWin);

    test('defaults the output directory to ~/Desktop', () async {
      final Directory desktop = Directory(p.join(work.path, 'home', 'Desktop'))
        ..createSync();
      final Run r = await dg([
        'create',
        'apk',
        '--no-timestamp',
      ], cwd: project());
      expect(r.exitCode, 0, reason: r.all);
      expect(File(p.join(desktop.path, 'demo.apk')).existsSync(), isTrue);
    }, skip: skipWin);
  });

  group('ios with a fake flutter', () {
    final String? skipMac = Platform.isMacOS
        ? null
        : 'iOS builds require macOS';

    test('copies the produced ipa', () async {
      final out = Directory(p.join(work.path, 'out'))..createSync();
      final Run r = await dg([
        'ios',
        '-o',
        out.path,
        '-n',
        'app',
        '--no-timestamp',
        '-m',
        'ad-hoc',
      ], cwd: project());
      expect(r.exitCode, 0, reason: r.all);
      expect(File(p.join(out.path, 'app.ipa')).existsSync(), isTrue);
      expect(calls(), contains('build ipa --release --export-method ad-hoc'));
      expect(r.all, isNot(contains('App Store builds cannot be installed')));
    }, skip: skipMac);

    test('warns about App Store builds (default method)', () async {
      final out = Directory(p.join(work.path, 'out'))..createSync();
      final Run r = await dg([
        'ios',
        '-o',
        out.path,
        '-n',
        'a',
      ], cwd: project());
      expect(r.all, contains('Warning: App Store builds cannot be installed'));
      expect(r.all, matches(RegExp(r'Date: \d{4}-\d{2}-\d{2} @ \d{2}:\d{2}')));
    }, skip: skipMac);

    test('reports a failing flutter build without exiting non-zero', () async {
      final Run r = await dg(
        ['ios', '-o', work.path, '-n', 'a'],
        cwd: project(),
        env: {'FAKE_EXIT': '1'},
      );
      expect(r.all, contains('iOS build failed'));
      expect(r.all, contains('fake failure'));
    }, skip: skipMac);

    test('reports a missing ipa directory and missing ipa file', () async {
      Run r = await dg(
        ['ios', '-o', work.path, '-n', 'a'],
        cwd: project(),
        env: {'FAKE_NOOUT': '1'},
      );
      expect(r.all, contains('IPA output directory not found'));

      Directory(p.join(project().path, 'build/ios/ipa'))
          .createSync(recursive: true);
      r = await dg(
        ['ios', '-o', work.path, '-n', 'a'],
        cwd: project(),
        env: {'FAKE_NOOUT': '1'},
      );
      expect(r.all, contains('No IPA file found'));
    }, skip: skipMac);

    test('refuses to run outside a project', () async {
      final Run r = await dg(['ios'], cwd: work);
      expect(r.all, contains('must be run inside a Flutter project'));
    }, skip: skipMac);
  });

  group('clean with fake flutter/pod', () {
    test('runs clean + pub get, removes build and succeeds', () async {
      final Directory proj = project();
      writeIn(proj, 'build/stale.txt', 'x');
      final Run r = await dg(['clean'], cwd: proj);

      expect(r.exitCode, 0, reason: r.all);
      expect(r.all, contains('All Clean'));
      expect(Directory(p.join(proj.path, 'build')).existsSync(), isFalse);
      final List<String> c = calls();
      expect(c.indexOf('clean'), lessThan(c.indexOf('pub get')));
    }, skip: skipWin);

    test(
      'works from a nested directory (project root is discovered)',
      () async {
        final Directory proj = project();
        final nested = Directory(p.join(proj.path, 'lib', 'src'))
          ..createSync(recursive: true);
        final Run r = await dg(['clean'], cwd: nested);
        expect(r.exitCode, 0, reason: r.all);
      },
      skip: skipWin,
    );

    test('a failing flutter clean exits 1', () async {
      final Run r = await dg(
        ['clean'],
        cwd: project(),
        env: {'FAKE_EXIT': '9'},
      );
      expect(r.exitCode, 1);
      expect(r.all, contains('flutter clean failed with exit code 9'));
    }, skip: skipWin);

    test(
      'macOS: removes Pods and runs pod install; --global drops DerivedData',
      () async {
        final Directory proj = project();
        writeIn(proj, 'ios/Podfile', '');
        writeIn(proj, 'ios/Pods/x', '');
        writeIn(proj, 'ios/Podfile.lock', '');
        writeIn(proj, 'ios/.symlinks/x', '');
        final derived = Directory(
          p.join(work.path, 'home', 'Library/Developer/Xcode/DerivedData'),
        )..createSync(recursive: true);
        final Run r = await dg(['clean', '--global'], cwd: proj);

        expect(r.exitCode, 0, reason: r.all);
        expect(Directory(p.join(proj.path, 'ios/Pods')).existsSync(), isFalse);
        expect(
          File(p.join(proj.path, 'ios/Podfile.lock')).existsSync(),
          isFalse,
        );
        expect(derived.existsSync(), isFalse);
        expect(calls(), contains('pod install'));
      },
      skip: Platform.isMacOS ? null : 'macOS only',
    );
  });

  group('zip with fake flutter', () {
    test('archives non-ignored files under a project folder', () async {
      final Directory proj = project();
      writeIn(proj, '.gitignore', 'build/\n*.log\nsecret.txt\n');
      writeIn(proj, 'lib/main.dart', 'void main() {}');
      writeIn(proj, 'lib/notes.log', 'x');
      writeIn(proj, 'build/out.bin', 'x');
      writeIn(proj, 'secret.txt', 'x');
      writeIn(proj, '.env', 'x');
      final out = Directory(p.join(work.path, 'out'))..createSync();
      final Run r = await dg(['zip', '-o', out.path], cwd: proj);

      expect(r.exitCode, 0, reason: r.all);
      final File zip = out.listSync().whereType<File>().single;
      expect(
        p.basename(zip.path),
        matches(RegExp(r'^demo-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}\.zip$')),
      );
      final Archive archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
      final names = archive.files
          .where((f) => f.isFile)
          .map((f) => f.name)
          .toSet();
      expect(names, {'demo/pubspec.yaml', 'demo/lib/main.dart'});
    }, skip: skipWin);

    test('warns when there is no .gitignore', () async {
      final out = Directory(p.join(work.path, 'out'))..createSync();
      final Run r = await dg(['zip', '-o', out.path], cwd: project());
      expect(r.exitCode, 0, reason: r.all);
      expect(r.all, contains('.gitignore not found'));
    }, skip: skipWin);

    test('flutter clean failure exits 1', () async {
      final Run r = await dg(
        ['zip', '-o', work.path],
        cwd: project(),
        env: {'FAKE_EXIT': '1'},
      );
      expect(r.exitCode, 1);
      expect(r.all, contains('An error occurred while creating ZIP'));
    }, skip: skipWin);

    test('creates a missing output directory', () async {
      final missing = Directory(p.join(work.path, 'missing', 'dir'));
      final Run r = await dg(['zip', '-o', missing.path], cwd: project());
      expect(r.exitCode, 0, reason: r.all);
      expect(missing.listSync().whereType<File>(), hasLength(1));
    }, skip: skipWin);
  });

  group('pub-cache with fake flutter', () {
    test('reports success', () async {
      final Run r = await dg(['pub-cache'], cwd: work);
      expect(r.exitCode, 0);
      expect(r.all, contains('Pub cache repaired successfully'));
      expect(calls(), contains('pub cache repair'));
    }, skip: skipWin);

    test('reports failure without crashing', () async {
      final Run r = await dg(['pub-cache'], cwd: work, env: {'FAKE_EXIT': '1'});
      expect(r.exitCode, 0);
      expect(r.all, contains('Pub cache repair failed'));
    }, skip: skipWin);
  });

  group('setup-aliases', () {
    File profile(String name) => File(p.join(work.path, 'home', name));

    test(
      'installs aliases with a custom prefix into .zshrc when present',
      () async {
        profile('.zshrc').writeAsStringSync('# mine\n');
        profile('.bashrc').writeAsStringSync('# bash\n');
        final Run r = await dg(['setup-aliases'], cwd: work, stdin: 'xy\n');

        expect(r.exitCode, 0, reason: r.all);
        final String z = profile('.zshrc').readAsStringSync();
        expect(z, startsWith('# mine\n'));
        expect(z, contains('alias xyp="dg create-project"'));
        expect(z, contains('alias xya="dg asset build"'));
        expect(profile('.bashrc').readAsStringSync(), '# bash\n');
      },
      skip: Platform.isWindows ? 'POSIX profiles' : null,
    );

    test('falls back to .bashrc, then .bash_profile, in that order', () async {
      profile('.bash_profile').writeAsStringSync('');
      await dg(['setup-aliases'], cwd: work, stdin: '\n');
      expect(
        profile('.bash_profile').readAsStringSync(),
        contains('alias dgp='),
      );
    }, skip: Platform.isWindows ? 'POSIX profiles' : null);

    test(
      'creates a new profile and defaults the prefix to dg on empty input',
      () async {
        final Run r = await dg(['setup-aliases'], cwd: work, stdin: '   \n');
        expect(r.exitCode, 0, reason: r.all);
        final File created = Platform.isMacOS
            ? profile('.zshrc')
            : profile('.bashrc');
        expect(
          created.readAsStringSync(),
          contains('alias dgm="dg create-module"'),
        );
      },
      skip: Platform.isWindows ? 'POSIX profiles' : null,
    );

    test('is idempotent: a second run leaves the profile unchanged', () async {
      profile('.zshrc').writeAsStringSync('');
      await dg(['setup-aliases'], cwd: work, stdin: 'a\n');
      final String once = profile('.zshrc').readAsStringSync();
      final Run r = await dg(['setup-aliases'], cwd: work, stdin: 'b\n');

      expect(r.all, contains('already installed'));
      expect(profile('.zshrc').readAsStringSync(), once);
    }, skip: Platform.isWindows ? 'POSIX profiles' : null);

    test('handles EOF on stdin by using the default prefix', () async {
      profile('.zshrc').writeAsStringSync('');
      final Run r = await dg(['setup-aliases'], cwd: work, stdin: '');
      expect(r.exitCode, 0, reason: r.all);
      expect(profile('.zshrc').readAsStringSync(), contains('alias dgp='));
    }, skip: Platform.isWindows ? 'POSIX profiles' : null);
  });

  group('keystore commands with real keytool', () {
    final bool tools =
        posix &&
        Process.runSync('which', ['keytool']).exitCode == 0 &&
        Process.runSync('which', ['openssl']).exitCode == 0;
    final String? skip = tools ? null : 'keytool/openssl not available';

    test('hash-key --debug reports a missing debug keystore', () async {
      final Run r = await dg(
        ['hash-key', '--debug'],
        cwd: work,
        fakeTools: false,
      );
      expect(r.all, contains('Debug keystore not found'));
    }, skip: skipWin);

    test('hash-key --debug hashes ~/.android/debug.keystore', () async {
      final dir = Directory(p.join(work.path, 'home', '.android'))
        ..createSync();
      final ProcessResult made = Process.runSync('keytool', [
        '-genkeypair',
        '-keystore',
        p.join(dir.path, 'debug.keystore'),
        '-alias',
        'androiddebugkey',
        '-storepass',
        'android',
        '-keypass',
        'android',
        '-keyalg',
        'RSA',
        '-keysize',
        '2048',
        '-validity',
        '30',
        '-dname',
        'CN=Android Debug',
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');

      final Run r = await dg(
        ['hash-key', '--debug'],
        cwd: work,
        fakeTools: false,
      );
      expect(r.all, contains('DEBUG Hash Key (Base64)'));
      expect(r.stdout, matches(RegExp(r'[A-Za-z0-9+/]{27}=')));
    }, skip: skip);

    test('create-jks saves to ~/Desktop outside a project', () async {
      final Run r = await dg(
        [
          'create-jks',
          '--no-interactive',
          '--name',
          'mykey',
          '--store-pass',
          'secret1',
        ],
        cwd: work,
        fakeTools: false,
      );
      expect(r.exitCode, 0, reason: r.all);
      expect(
        File(p.join(work.path, 'home', 'Desktop', 'mykey.jks')).existsSync(),
        isTrue,
      );
      expect(r.all, contains('JKS file created'));
    }, skip: skip);

    test('create-jks enforces the password length', () async {
      final Run r = await dg(
        [
          'create-jks',
          '--no-interactive',
          '--location',
          work.path,
          '--store-pass',
          '12345',
        ],
        cwd: work,
        fakeTools: false,
      );
      expect(r.all, contains('at least 6 characters'));
    }, skip: skipWin);

    test(
      'hash-key --release with key.properties arguments missing keystore',
      () async {
        final Run r = await dg(
          [
            'hash-key',
            '--release',
            '-k',
            'nope.jks',
            '-a',
            'a',
            '--storepass',
            's',
            '--keypass',
            'k',
          ],
          cwd: work,
          fakeTools: false,
        );
        expect(r.all, contains('Keystore file not found'));
      },
      skip: skipWin,
    );
  });

  group('create-project validation (no template or network is reached)', () {
    test('requires a project name when stdin is empty', () async {
      final Run r = await dg(['create-project'], cwd: work, stdin: '');
      expect(r.all, contains('Project name is required'));
    });

    for (final bad in ['', 'com..app', '1com.app', 'com.app-x', 'has space']) {
      test('rejects bundle id "$bad"', () async {
        final Run r = await dg(
          [
            'create-project',
            '-n',
            'my_app',
            '-a',
            'My App',
            '-b',
            bad,
            '-o',
            p.join(work.path, 'x'),
          ],
          cwd: work,
          stdin: '\n',
        );
        expect(r.exitCode, 0);
        expect(r.all, contains('Valid bundle ID is required'));
        expect(Directory(p.join(work.path, 'x')).existsSync(), isFalse);
      });
    }

    test('refuses to overwrite an existing target directory', () async {
      final target = Directory(p.join(work.path, 'taken'))..createSync();
      final Run r = await dg([
        'create-project',
        '-n',
        'a',
        '-b',
        'com.a.b',
        '-o',
        target.path,
      ], cwd: work);
      expect(r.all, contains('already exists'));
    });
  });
}
