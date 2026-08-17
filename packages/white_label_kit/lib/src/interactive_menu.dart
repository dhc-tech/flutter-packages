import 'dart:io';

import 'package:path/path.dart' as p;

import 'config/white_label_config.dart';

/// Interactive terminal runner & builder for `white_label_kit`.
///
/// Guides the developer step-by-step through selecting a tenant and running
/// or building for that tenant without remembering long CLI flags.
Future<int> runInteractiveMenu({String? projectRoot}) async {
  final root = projectRoot ?? Directory.current.path;
  final whiteLabelFile = File(p.join(root, 'white_label.yaml'));

  if (!whiteLabelFile.existsSync()) {
    stderr.writeln('❌ white_label.yaml not found in $root');
    return 1;
  }

  WhiteLabelConfig config;
  try {
    config = WhiteLabelConfig.load(root);
  } catch (e) {
    stderr.writeln('❌ Could not parse white_label.yaml: $e');
    return 1;
  }

  final defaultTenant = config.defaultTenant;
  final tenantIds = config.tenants.keys.toList();

  while (true) {
    stdout.writeln();
    stdout.writeln(
      '╔══════════════════════════════════════════════════════════════════╗',
    );
    stdout.writeln(
      '║              ✨ WHITE_LABEL_KIT RUNNER & BUILDER                 ║',
    );
    stdout.writeln(
      '║          Automated Multi-Tenant Flutter CLI & Launcher           ║',
    );
    stdout.writeln(
      '╚══════════════════════════════════════════════════════════════════╝',
    );
    stdout.writeln();

    // --- 1. Tenant Selection with Validation Loop ---
    String? selectedTenant;
    while (selectedTenant == null) {
      stdout.writeln('📌 SELECT TENANT:');
      for (var i = 0; i < tenantIds.length; i++) {
        final id = tenantIds[i];
        final name = config.tenants[id]?.name ?? id;
        final isDef = id == defaultTenant ? ' (Default)' : '';
        stdout.writeln('   [$i] $name [$id]$isDef');
      }
      stdout.write(
        '\nEnter tenant number [0-${tenantIds.length - 1}, or Enter for "$defaultTenant"]: ',
      );

      final input = stdin.readLineSync()?.trim();
      if (input == null || input.isEmpty) {
        selectedTenant = defaultTenant;
      } else {
        final index = int.tryParse(input);
        if (index != null && index >= 0 && index < tenantIds.length) {
          selectedTenant = tenantIds[index];
        } else {
          stdout.writeln(
            '❌ Invalid selection "$input". Please enter a number from 0 to ${tenantIds.length - 1}.\n',
          );
        }
      }
    }

    final tenantObj = config.tenants[selectedTenant]!;
    stdout.writeln(
      '\n🎯 Selected Tenant: ${tenantObj.name} ($selectedTenant)\n',
    );

    // --- 2. Action Selection with Validation Loop ---
    String? selectedAction;
    while (selectedAction == null) {
      stdout.writeln('⚡ SELECT ACTION:');
      stdout.writeln(
        '   [1] ▶️  Run in Debug Mode (Simulator / Connected Device)',
      );
      stdout.writeln('   [2] ⚡  Run in Release Mode (Device)');
      stdout.writeln('   [3] 🚀  Build Release APK (Android)');
      stdout.writeln(
        '   [4] 📦  Build Release AppBundle / AAB (Google Play Store)',
      );
      stdout.writeln('   [5] 🍎  Build Release iOS (Simulator / Archive)');
      stdout.writeln(
        '   [6] 🔧  Configure All Tenants (white_label_kit:configure)',
      );
      stdout.writeln('   [7] ➕  Add New Tenant (white_label_kit:add-tenant)');
      stdout.writeln('   [8] ❌  Remove Tenant (white_label_kit:remove-tenant)');
      stdout.writeln(
        '   [9] 🔍  Analyze & Health Check (Flutter Analyze + Tests)',
      );
      stdout.writeln('   [0] 🚪  Exit');
      stdout.write('\nEnter action number [1-9, 0 to exit]: ');

      final input = stdin.readLineSync()?.trim();
      if (input != null && RegExp(r'^[0-9]$').hasMatch(input)) {
        selectedAction = input;
      } else {
        stdout.writeln(
          '❌ Invalid action "$input". Please enter a number from 0 to 9.\n',
        );
      }
    }

    stdout.writeln();
    switch (selectedAction) {
      case '0':
        stdout.writeln('👋 Exiting. Happy coding!');
        return 0;
      case '1':
        await _execute('dart', [
          'run',
          'white_label_kit:generate',
          '--tenant',
          selectedTenant,
        ]);
        await _execute('flutter', [
          'run',
          '--flavor',
          selectedTenant,
          '--dart-define=TENANT_ID=$selectedTenant',
        ]);
        break;
      case '2':
        await _execute('dart', [
          'run',
          'white_label_kit:generate',
          '--tenant',
          selectedTenant,
        ]);
        await _execute('flutter', [
          'run',
          '--release',
          '--flavor',
          selectedTenant,
          '--dart-define=TENANT_ID=$selectedTenant',
        ]);
        break;
      case '3':
        await _execute('dart', [
          'run',
          'white_label_kit:generate',
          '--tenant',
          selectedTenant,
        ]);
        await _execute('flutter', [
          'build',
          'apk',
          '--release',
          '--flavor',
          selectedTenant,
          '--dart-define=TENANT_ID=$selectedTenant',
        ]);
        break;
      case '4':
        await _execute('dart', [
          'run',
          'white_label_kit:generate',
          '--tenant',
          selectedTenant,
        ]);
        await _execute('flutter', [
          'build',
          'appbundle',
          '--release',
          '--flavor',
          selectedTenant,
          '--dart-define=TENANT_ID=$selectedTenant',
        ]);
        break;
      case '5':
        await _execute('dart', [
          'run',
          'white_label_kit:generate',
          '--tenant',
          selectedTenant,
        ]);
        await _execute('flutter', [
          'build',
          'ios',
          '--release',
          '--flavor',
          selectedTenant,
          '--dart-define=TENANT_ID=$selectedTenant',
        ]);
        break;
      case '6':
        await _execute('dart', ['run', 'white_label_kit:configure']);
        break;
      case '7':
        stdout.write('\nEnter new tenant ID (e.g. acme): ');
        final id = stdin.readLineSync()?.trim();
        stdout.write('Enter display name (e.g. Acme College): ');
        final name = stdin.readLineSync()?.trim();
        stdout.write('Enter bundle ID (e.g. com.acme.student): ');
        final bundleId = stdin.readLineSync()?.trim();

        if (id != null &&
            id.isNotEmpty &&
            name != null &&
            name.isNotEmpty &&
            bundleId != null &&
            bundleId.isNotEmpty) {
          await _execute('dart', [
            'run',
            'white_label_kit:add-tenant',
            id,
            name,
            bundleId,
          ]);
          await _execute('dart', ['run', 'white_label_kit:configure']);
          // Reload config
          try {
            config = WhiteLabelConfig.load(root);
            tenantIds.clear();
            tenantIds.addAll(config.tenants.keys);
          } catch (_) {}
        } else {
          stderr.writeln('❌ Invalid input. Tenant not created.');
        }
        break;
      case '8':
        stdout.write('\nEnter tenant ID to remove: ');
        final id = stdin.readLineSync()?.trim();
        if (id != null && id.isNotEmpty) {
          await _execute('dart', ['run', 'white_label_kit:remove-tenant', id]);
          try {
            config = WhiteLabelConfig.load(root);
            tenantIds.clear();
            tenantIds.addAll(config.tenants.keys);
          } catch (_) {}
        }
        break;
      case '9':
        await _execute('flutter', ['analyze', '--no-fatal-infos']);
        await _execute('flutter', ['test', 'test/core/tenant/']);
        break;
    }

    stdout.write('\nPress [Enter] to return to menu...');
    stdin.readLineSync();
  }
}

Future<void> _execute(String executable, List<String> args) async {
  stdout.writeln(
    '\n➜ [white_label_kit] Executing: $executable ${args.join(" ")}',
  );
  final process = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    stderr.writeln('❌ [white_label_kit] Failed with exit code $exitCode');
  } else {
    stdout.writeln('✅ [white_label_kit] Done successfully!');
  }
}
