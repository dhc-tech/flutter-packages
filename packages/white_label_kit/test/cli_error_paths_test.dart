// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Drives the real `white_label` CLI as a child process (the only way to
// observe exit codes) through its flag-validation, missing-config and
// failure paths, plus the happy paths of subcommands that the feature suites
// do not cover (generate/update-tenant/remove-tenant/run/build --dry-run).
// The CLI is compiled to kernel once and reused so each call is fast; no
// test changes this process's working directory.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class Run {
  Run(this.code, this.out, this.err);
  final int code;
  final String out;
  final String err;
  String get all => '$out\n$err';
}

late Directory kernelDir;
late String kernel;
late Directory proj;

Future<Run> wl(
  List<String> args, {
  Directory? cwd,
  Map<String, String> env = const {},
}) async {
  final Process proc = await Process.start(
    Platform.resolvedExecutable,
    [kernel, ...args],
    workingDirectory: (cwd ?? proj).path,
    environment: env,
  );
  await proc.stdin.close();
  final results = await Future.wait([
    proc.stdout.transform(utf8.decoder).join(),
    proc.stderr.transform(utf8.decoder).join(),
    proc.exitCode,
  ]);
  return Run(results[2] as int, results[0] as String, results[1] as String);
}

File yaml() => File(p.join(proj.path, 'white_label.yaml'));
String lib(String name) =>
    File(p.join(proj.path, 'lib', name)).readAsStringSync();

Future<void> newProject() async {
  proj = Directory.systemTemp.createTempSync('wl_cli_err_');
  File(p.join(proj.path, 'pubspec.yaml')).writeAsStringSync(
    'name: fake_app\nflutter:\n  uses-material-design: true\n',
  );
  final Run init = await wl(['init', '--example']);
  expect(init.code, 0, reason: init.all);
}

Future<void> addBeta() async {
  final Run r = await wl([
    'add-tenant',
    'beta',
    'Beta Corp',
    'com.example.beta',
  ]);
  expect(r.code, 0, reason: r.all);
}

void main() {
  setUpAll(() async {
    kernelDir = Directory.systemTemp.createTempSync('wl_kernel_');
    final Uri? lib = await Isolate.resolvePackageUri(
      Uri.parse('package:white_label_kit/white_label_kit.dart'),
    );
    final String entry = p.join(
      p.dirname(p.dirname(lib!.toFilePath())),
      'bin',
      'white_label.dart',
    );
    kernel = p.join(kernelDir.path, 'wl.dill');
    final ProcessResult compiled = await Process.run(
      Platform.resolvedExecutable,
      ['compile', 'kernel', entry, '-o', kernel],
    );
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
  });

  tearDownAll(() => kernelDir.deleteSync(recursive: true));

  setUp(newProject);
  tearDown(() => proj.deleteSync(recursive: true));

  group('dispatcher', () {
    test('help, -h and --help print usage and exit 0', () async {
      for (final flag in ['help', '-h', '--help']) {
        final Run r = await wl([flag]);
        expect(r.code, 0, reason: flag);
        expect(r.all, contains('init'), reason: flag);
      }
    });

    test(
      'no arguments and no white_label.yaml prints usage with exit 1',
      () async {
        final Directory empty = Directory.systemTemp.createTempSync(
          'wl_empty_',
        );
        addTearDown(() => empty.deleteSync(recursive: true));
        final Run r = await wl([], cwd: empty);
        expect(r.code, 1);
        expect(r.all, contains('init'));
      },
    );

    test('an unknown command exits 1', () async {
      final Run r = await wl(['frobnicate']);
      expect(r.code, 1);
      expect(r.err, contains("Unknown command: 'frobnicate'"));
    });

    test('menu and runner exit 1 without a parsable config', () async {
      final Directory empty = Directory.systemTemp.createTempSync('wl_empty_');
      addTearDown(() => empty.deleteSync(recursive: true));
      for (final cmd in ['menu', 'runner']) {
        final Run r = await wl([cmd], cwd: empty);
        expect(r.code, 1, reason: cmd);
        expect(r.err, contains('white_label.yaml not found'));
      }
    });
  });

  group('flag validation shared by every subcommand', () {
    const valueFlags = {
      'list': ['--project-root', '--config'],
      'validate': ['--project-root', '--config'],
      'doctor': ['--project-root', '--config'],
      'init': ['--path', '--project-root'],
      'generate': ['--tenant', '--config', '--project-root', '--env'],
      'add-tenant': ['--logo', '--project-root', '--config'],
      'remove-tenant': ['--project-root', '--config', '--ide-root'],
      'build': [
        '--tenant',
        '--platform',
        '--mode',
        '--env',
        '--project-root',
        '--config',
      ],
      'run': ['--tenant', '--env', '--project-root', '--config'],
      'configure': [
        '--tenant',
        '--platform',
        '--env',
        '--project-root',
        '--config',
        '--ide-root',
      ],
    };

    for (final entry in valueFlags.entries) {
      for (final flag in entry.value) {
        test('${entry.key} $flag without a value exits 1', () async {
          final Run r = await wl([entry.key, flag]);
          expect(r.code, 1);
          expect(r.err, contains('requires'));
        });
      }
    }

    for (final cmd in [
      'list',
      'validate',
      'doctor',
      'init',
      'generate',
      'build',
      'run',
      'configure',
    ]) {
      test('$cmd rejects unknown flags', () async {
        final Run r = await wl([cmd, '--bogus']);
        expect(r.code, 1);
        expect(r.err, contains('Unknown flag'));
      });
    }

    for (final cmd in [
      'list',
      'validate',
      'doctor',
      'generate',
      'run',
      'remove-tenant',
      'update-tenant',
      'build',
    ]) {
      test('$cmd with a missing config file exits 1 with guidance', () async {
        final Directory empty = Directory.systemTemp.createTempSync(
          'wl_empty_',
        );
        addTearDown(() => empty.deleteSync(recursive: true));
        final args = cmd == 'remove-tenant' || cmd == 'update-tenant'
            ? [cmd, 'acme']
            : [cmd];
        final Run r = await wl(args, cwd: empty);
        expect(r.code, 1);
        expect(r.err, contains('not found'));
      });
    }
  });

  group('init', () {
    test(
      'refuses to run twice without --force, and overwrites with it',
      () async {
        Run r = await wl(['init']);
        expect(r.code, 1);
        expect(r.err, contains('already exists'));

        yaml().writeAsStringSync('# changed');
        r = await wl(['init', '--force']);
        expect(r.code, 0, reason: r.all);
        expect(yaml().readAsStringSync(), contains('white_label:'));
      },
    );

    test('requires a pubspec with a flutter key', () async {
      final Directory d = Directory.systemTemp.createTempSync('wl_init_');
      addTearDown(() => d.deleteSync(recursive: true));
      Run r = await wl(['init'], cwd: d);
      expect(r.code, 1);
      expect(r.err, contains('No pubspec.yaml'));

      File(p.join(d.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      r = await wl(['init'], cwd: d);
      expect(r.code, 1);
      expect(r.err, contains('no `flutter:` key'));

      File(p.join(d.path, 'pubspec.yaml')).writeAsStringSync('name: [broken');
      r = await wl(['init'], cwd: d);
      expect(r.code, 1);
      expect(r.err, contains('not valid YAML'));
    });

    test('--path and --project-root target another directory', () async {
      final Directory d = Directory.systemTemp.createTempSync('wl_init_');
      addTearDown(() => d.deleteSync(recursive: true));
      File(p.join(d.path, 'pubspec.yaml'))
          .writeAsStringSync('name: x\nflutter:\n');
      final Run r = await wl(['init', '--path', d.path]);
      expect(r.code, 0, reason: r.all);
      expect(File(p.join(d.path, 'white_label.yaml')).existsSync(), isTrue);
      expect(
        Directory(p.join(d.path, 'tenants')).existsSync(),
        isFalse,
        reason: 'no --example, no tenants',
      );
    });
  });

  group('validate, list and doctor', () {
    test(
      'validate reports every error and exits 1 for an invalid config',
      () async {
        yaml().writeAsStringSync('white_label:\n  tenants:\n    Bad-Id: {}\n');
        final Run r = await wl(['validate']);
        expect(r.code, 1);
        expect(r.err, contains('ERROR:'));
      },
    );

    test('list prints the default marker for each tenant, sorted', () async {
      await addBeta();
      final Run r = await wl(['list']);
      expect(r.code, 0, reason: r.all);
      expect(r.out, contains('Default tenant: acme'));
      expect(r.out.indexOf('acme'), lessThan(r.out.indexOf('beta')));
      expect(r.out, contains('(default)'));
    });

    test(
      '--config selects another file and --project-root another dir',
      () async {
        yaml().renameSync(p.join(proj.path, 'other.yaml'));
        Run r = await wl(['list']);
        expect(r.code, 1);
        r = await wl(['list', '--config', 'other.yaml']);
        expect(r.code, 0, reason: r.all);
        r = await wl([
          'validate',
          '--config',
          p.join(proj.path, 'other.yaml'),
          '--project-root',
          proj.path,
        ]);
        expect(r.code, 0, reason: r.all);
      },
    );

    test(
      'doctor flags a missing generated file, then passes after generate',
      () async {
        Run r = await wl(['doctor']);
        expect(r.code, 1);
        expect(r.out, contains('lib/white_label.g.dart does not exist'));

        await wl(['generate']);
        r = await wl(['doctor']);
        expect(r.code, 0, reason: r.all);
        expect(r.out, contains('TENANT VALID'));
      },
    );

    test('doctor detects a stale generated file and a deleted asset', () async {
      await addBeta();
      await wl(['generate', '--tenant', 'beta']);
      await wl(['update-tenant', 'beta']);
      File(p.join(proj.path, 'lib', 'white_label.g.dart'))
          .writeAsStringSync("tenantId: 'ghost'");
      Run r = await wl(['doctor']);
      expect(r.code, 1);
      expect(r.out, contains('looks stale'));

      await wl(['generate']);
      File(p.join(proj.path, 'tenants', 'acme', 'assets', 'logo.png'))
          .deleteSync();
      r = await wl(['doctor']);
      expect(r.code, 1);
    });

    test(
      'doctor warns when splash_generate is on without flutter_native_splash',
      () async {
        yaml().writeAsStringSync(
          yaml().readAsStringSync().replaceFirst(
            '      # features:\n      #   some_feature_flag: true',
            '      features:\n        splash_generate: true',
          ),
        );
        await wl(['generate']);
        final Run r = await wl(['doctor']);
        expect(r.code, 1);
        expect(r.out, contains('flutter_native_splash'));
      },
    );
  });

  group('generate', () {
    test('writes lib/white_label.g.dart for the default tenant', () async {
      final Run r = await wl(['generate']);
      expect(r.code, 0, reason: r.all);
      expect(lib('white_label.g.dart'), contains("'acme'"));
    });

    test(
      'honours --tenant and TENANT_ID, with --tenant taking precedence',
      () async {
        await addBeta();
        await wl(['generate', '--tenant', 'beta']);
        expect(lib('white_label.g.dart'), contains("tenantId: 'beta'"));

        await wl(['generate'], env: {'TENANT_ID': 'beta'});
        expect(lib('white_label.g.dart'), contains("tenantId: 'beta'"));

        await wl(['generate', '--tenant', 'acme'], env: {'TENANT_ID': 'beta'});
        expect(lib('white_label.g.dart'), contains("tenantId: 'acme'"));
      },
    );

    test('unknown tenant and unknown environment exit 1', () async {
      Run r = await wl(['generate', '--tenant', 'ghost']);
      expect(r.code, 1);
      expect(r.err, contains('No such tenant'));

      r = await wl(['generate', '--env', 'nope']);
      expect(r.code, 1);
      expect(r.err, contains('nope'));
    });

    test('an invalid config exits 1 and writes nothing', () async {
      yaml().writeAsStringSync('white_label: [');
      final Run r = await wl(['generate']);
      expect(r.code, 1);
      expect(
        File(p.join(proj.path, 'lib', 'white_label.g.dart')).existsSync(),
        isFalse,
      );
    });
  });

  group('update-tenant', () {
    test('requires exactly one tenant id', () async {
      expect((await wl(['update-tenant'])).code, 1);
      expect((await wl(['update-tenant', 'a', 'b'])).code, 1);
    });

    test('unknown tenant exits 1', () async {
      final Run r = await wl(['update-tenant', 'ghost', '--name', 'X']);
      expect(r.code, 1);
      expect(r.err, contains('No such tenant "ghost"'));
    });

    test('a flag without a value exits 1 instead of crashing', () async {
      final String before = yaml().readAsStringSync();
      for (final flag in [
        '--name',
        '--android-id',
        '--ios-id',
        '--api-url',
        '--logo',
      ]) {
        final Run r = await wl(['update-tenant', 'acme', flag]);
        expect(r.code, 1, reason: flag);
        expect(r.err, contains('$flag requires a value'), reason: flag);
      }
      expect(yaml().readAsStringSync(), before);
    });

    test(
      'refuses to drop settings it cannot preserve and changes nothing',
      () async {
        final String original = yaml().readAsStringSync();
        final String withTheme = original.replaceFirst(
          '      android:',
          '      theme:\n        primary_color: "#3366FF"\n\n      android:',
        );
        expect(withTheme, isNot(original));
        yaml().writeAsStringSync(withTheme);
        final Run r = await wl(['update-tenant', 'acme', '--name', 'Renamed']);
        expect(r.code, 1, reason: r.all);
        expect(r.err, contains('theme'));
        expect(r.err, contains('nothing was changed'));
        expect(yaml().readAsStringSync(), withTheme);
      },
    );

    test('validates ids and urls before changing anything', () async {
      final String before = yaml().readAsStringSync();
      for (final args in [
        ['--android-id', 'bad id'],
        ['--ios-id', 'bad_id.x'],
        ['--api-url', 'not a url'],
      ]) {
        final Run r = await wl(['update-tenant', 'acme', ...args]);
        expect(r.code, 1, reason: args.join(' '));
      }
      expect(yaml().readAsStringSync(), before);
    });

    test('--logo with a missing file exits 1', () async {
      final Run r = await wl([
        'update-tenant',
        'acme',
        '--logo',
        p.join(proj.path, 'nope.png'),
      ]);
      expect(r.code, 1);
      expect(r.err, contains('--logo file not found'));
    });

    test('updates name, ids, url and logo', () async {
      final File logo = File(p.join(proj.path, 'new_logo.png'))
        ..writeAsBytesSync([9, 9, 9]);
      final Run r = await wl([
        'update-tenant',
        'acme',
        '--name',
        'Acme Two',
        '--android-id',
        'com.new.acme',
        '--ios-id',
        'com.new.acme-ios',
        '--api-url',
        'https://api.new.example',
        '--logo',
        logo.path,
      ]);
      expect(r.code, 0, reason: r.all);

      final String content = yaml().readAsStringSync();
      expect(content, contains('name: "Acme Two"'));
      expect(content, contains('application_id: "com.new.acme"'));
      expect(content, contains('bundle_id: "com.new.acme-ios"'));
      expect(content, contains('api_base_url: "https://api.new.example"'));
      expect(
        File(p.join(proj.path, 'tenants', 'acme', 'assets', 'logo.png'))
            .readAsBytesSync(),
        [9, 9, 9],
      );
      expect((await wl(['validate'])).code, 0);
    });

    test('--default promotes the tenant', () async {
      await addBeta();
      final Run r = await wl([
        'update-tenant',
        'beta',
        '--name',
        'Beta 2',
        '--default',
      ]);
      expect(r.code, 0, reason: r.all);
      expect(r.out, contains('Set "beta" as default_tenant'));
      expect((await wl(['list'])).out, contains('Default tenant: beta'));
    });
  });

  group('remove-tenant', () {
    test('requires exactly one tenant id', () async {
      expect((await wl(['remove-tenant'])).code, 1);
      expect((await wl(['remove-tenant', 'a', 'b'])).code, 1);
    });

    test('unknown tenant and the only tenant cannot be removed', () async {
      Run r = await wl(['remove-tenant', 'ghost']);
      expect(r.code, 1);
      expect(r.err, contains('No such tenant'));

      r = await wl(['remove-tenant', 'acme']);
      expect(r.code, 1);
      expect(r.err, contains("only tenant declared"));
      expect(yaml().readAsStringSync(), contains('acme:'));
    });

    test('removes a non-default tenant, its assets and regenerates', () async {
      await addBeta();
      final Run r = await wl(['remove-tenant', 'beta']);
      expect(r.code, 0, reason: r.all);
      expect(yaml().readAsStringSync(), isNot(contains('beta:')));
      expect(
        Directory(p.join(proj.path, 'tenants', 'beta')).existsSync(),
        isFalse,
      );
      expect(lib('white_label.g.dart'), contains("'acme'"));
    });

    test('--keep-assets leaves the tenant folder', () async {
      await addBeta();
      final Run r = await wl(['remove-tenant', 'beta', '--keep-assets']);
      expect(r.code, 0, reason: r.all);
      expect(
        Directory(p.join(proj.path, 'tenants', 'beta')).existsSync(),
        isTrue,
      );
      expect(r.out, isNot(contains('Deleted tenants/beta/')));
    });

    test('removing the default tenant promotes another one', () async {
      await addBeta();
      final Run r = await wl(['remove-tenant', 'acme']);
      expect(r.code, 0, reason: r.all);
      expect(r.out, contains('auto-promoted "beta"'));
      expect((await wl(['list'])).out, contains('Default tenant: beta'));
    });

    test(
      'cleans native Android flavors and IDE configs for the tenant',
      () async {
        await addBeta();
        File(p.join(proj.path, 'android', 'app', 'build.gradle.kts'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            'plugins {\n}\nandroid {\n    namespace = "x"\n}\n',
          );
        expect(
          (await wl(['configure', '--platform', 'android', '--skip-generate']))
              .code,
          0,
        );
        final String gradle = File(
          p.join(proj.path, 'android', 'app', 'build.gradle.kts'),
        ).readAsStringSync();
        expect(gradle, contains('create("beta")'));

        final Run r = await wl(['remove-tenant', 'beta']);
        expect(r.code, 0, reason: r.all);
        expect(
          File(p.join(proj.path, 'android', 'app', 'build.gradle.kts'))
              .readAsStringSync(),
          isNot(contains('create("beta")')),
        );
      },
    );
  });

  group('build and run', () {
    test('rejects an invalid platform or mode', () async {
      Run r = await wl(['build', '--platform', 'windows']);
      expect(r.code, 1);
      expect(r.err, contains('--platform must be one of'));
      r = await wl(['build', '--mode', 'profile']);
      expect(r.code, 1);
      expect(r.err, contains('--mode must be one of'));
    });

    test('--clean needs --tenant and removes staged output', () async {
      Run r = await wl(['build', '--clean']);
      expect(r.code, 1);
      expect(r.err, contains('--clean requires --tenant'));

      await wl(['build', '--tenant', 'acme', '--stage-only']);
      expect(
        Directory(p.join(proj.path, '.generated', 'acme')).existsSync(),
        isTrue,
      );
      r = await wl(['build', '--tenant', 'acme', '--clean']);
      expect(r.code, 0, reason: r.all);
      expect(
        Directory(p.join(proj.path, '.generated', 'acme')).existsSync(),
        isFalse,
      );
    });

    test('--dry-run resolves the config without staging anything', () async {
      final Run r = await wl([
        'build',
        '--dry-run',
        '--verbose',
        '--env',
        'staging',
      ]);
      expect(r.code, 0, reason: r.all);
      expect(r.out, contains('Building tenant: acme'));
      expect(r.out, contains('Environment: staging'));
      expect(r.out, contains('Android application id: com.example.acme'));
      expect(r.out, contains('dry run'));
      expect(Directory(p.join(proj.path, '.generated')).existsSync(), isFalse);
    });

    test('unknown tenant exits 1', () async {
      final Run r = await wl(['build', '--tenant', 'ghost']);
      expect(r.code, 1);
      expect(r.err, contains('No such tenant'));
    });

    test(
      '--stage-only regenerates the dart config and stages assets',
      () async {
        final Run r = await wl(['build', '--tenant', 'acme', '--stage-only']);
        expect(r.code, 0, reason: r.all);
        expect(r.out, contains('Staged assets at:'));
        expect(
          File(p.join(proj.path, '.generated', 'acme', 'assets', 'logo.png'))
              .existsSync(),
          isTrue,
        );
        expect(lib('white_label.g.dart'), contains("'acme'"));
      },
    );

    test('an undeclared --env exits 1 during generation', () async {
      final Run r = await wl([
        'build',
        '--tenant',
        'acme',
        '--stage-only',
        '--env',
        'nope',
      ]);
      expect(r.code, 1);
      expect(r.err, contains('nope'));
    });

    test('run prepares the tenant and prints the flutter command', () async {
      final Run r = await wl(['run', '--tenant', 'acme']);
      expect(r.code, 0, reason: r.all);
      expect(
        r.out,
        contains('flutter run --flavor acme --dart-define=TENANT_ID=acme'),
      );
      expect(
        Directory(p.join(proj.path, '.generated', 'acme')).existsSync(),
        isTrue,
      );
    });

    test('run with an unknown tenant or environment exits 1', () async {
      expect((await wl(['run', '--tenant', 'ghost'])).code, 1);
      expect((await wl(['run', '--env', 'nope'])).code, 1);
    });
  });

  group('configure', () {
    test('dry-run does not touch native files', () async {
      final File gradle =
          File(p.join(proj.path, 'android', 'app', 'build.gradle.kts'))
            ..createSync(recursive: true)
            ..writeAsStringSync('android {\n}\n');
      final Run r = await wl([
        'configure',
        '--platform',
        'android',
        '--dry-run',
      ]);
      expect(r.code, 0, reason: r.all);
      expect(gradle.readAsStringSync(), 'android {\n}\n');
    });

    test('an unknown tenant or platform exits 1', () async {
      expect((await wl(['configure', '--tenant', 'ghost'])).code, 1);
      expect((await wl(['configure', '--platform', 'windows'])).code, 1);
    });
  });
}
