// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../ui/box_painter.dart';
import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';

/// Removes an existing GetX module and unregisters its routes.
class RemoveModuleCommand extends Command<dynamic> {
  /// Registers the `--name` option for the module to remove.
  RemoveModuleCommand() {
    argParser.addOption(
      'name',
      abbr: 'n',
      help: 'The name of the module to remove (e.g., "auth")',
    );
  }
  @override
  final name = 'remove-module';
  @override
  final description =
      'Removes an existing GetX module and unregisters its routes.';

  @override
  Future<void> run() async {
    if (!await isFlutterProject()) {
      kLog(
        '❗ This command must be run inside a Flutter project.',
        type: LogType.error,
      );
      return;
    }

    var moduleName = argResults?['name'] as String?;
    if (moduleName == null || moduleName.isEmpty) {
      if (argResults!.rest.isNotEmpty) {
        moduleName = argResults!.rest.first;
      } else {
        stdout.write('Enter module name to remove (e.g., auth): ');
        moduleName = stdin.readLineSync()?.trim();
      }
    }

    if (moduleName == null || moduleName.isEmpty) {
      kLog('❗ Module name is required.', type: LogType.error);
      return;
    }

    final String cleanModuleName = moduleName
        .replaceAll(
          RegExp(r'_?(View|Controller|Binding|Module)$', caseSensitive: false),
          '',
        )
        .trim();

    final String slug = _toSnakeCase(cleanModuleName);
    final String className = _toPascalCase(cleanModuleName);
    final moduleDir = Directory(p.join('lib', 'app', 'module', slug));

    if (!moduleDir.existsSync()) {
      kLog('❗ Module $slug does not exist.', type: LogType.error);
      return;
    }

    await runWithSpinner(
      '🗑️  Removing $className module components...',
      () async {
        // 1. Delete Module Directory
        if (moduleDir.existsSync()) {
          moduleDir.deleteSync(recursive: true);
          kLog(
            '  - Deleted module directory: ${moduleDir.path}',
            type: LogType.success,
          );
        } else {
          kLog(
            '  - Module directory already gone: ${moduleDir.path}',
            type: LogType.warning,
          );
        }

        // 2. Unregister Module Export
        await _unregisterModuleExport(slug);

        // 3. Unregister Route
        await _unregisterRoute(className, slug);

        // 4. Unregister Page
        await _unregisterPage(className, slug);
      },
    );

    final painter = BoxPainter();
    // ignore: avoid_print
    print('');
    painter.drawHeader('MODULE REMOVAL SUMMARY');
    painter.drawRow('Module', className);
    painter.drawRow('Slug', slug);
    painter.drawRow('Route', 'AppRoute.${_toCamelCase(slug)}');
    painter.drawFooter();

    kLog(
      '\n✅ Module $className has been completely removed!',
      type: LogType.success,
    );
    kLog(
      '💡 Note: You may need to run "flutter pub get" if imports are lingering.',
    );
  }

  Future<void> _unregisterModuleExport(String slug) async {
    final exportFile = File(
      p.join('lib', 'app', 'module', 'module_export.dart'),
    );
    if (!exportFile.existsSync()) {
      return;
    }

    final String content = await exportFile.readAsString();
    final exportLine = "export '$slug/${slug}_export.dart';";

    if (!content.contains(exportLine)) {
      kLog(
        '  - Export line not found in module_export.dart',
        type: LogType.warning,
      );
      return;
    }

    final List<String> lines = content.split('\n');
    lines.removeWhere((l) => l.trim() == exportLine);
    await exportFile.writeAsString(lines.join('\n'));
    kLog('  - Removed export from module_export.dart', type: LogType.success);
  }

  Future<void> _unregisterRoute(String className, String slug) async {
    final file = File(p.join('lib', 'app', 'routes', 'app_route.dart'));
    if (!file.existsSync()) {
      return;
    }

    final String content = await file.readAsString();
    final String routeName = _toCamelCase(slug);

    if (!content.contains(routeName)) {
      kLog(
        '  - Route definition not found in app_route.dart',
        type: LogType.warning,
      );
      return;
    }

    final List<String> lines = content.split('\n');
    lines.removeWhere((l) => l.contains('static const String $routeName ='));
    await file.writeAsString(lines.join('\n'));
    kLog('  - Removed static route from app_route.dart', type: LogType.success);
  }

  Future<void> _unregisterPage(String className, String slug) async {
    final file = File(p.join('lib', 'app', 'routes', 'app_page.dart'));
    if (!file.existsSync()) {
      return;
    }

    String content = await file.readAsString();
    final String routeName = _toCamelCase(slug);
    final blockId = 'AppRoute.$routeName';

    if (!content.contains(blockId)) {
      kLog(
        '  - GetPage block not found in app_page.dart',
        type: LogType.warning,
      );
      return;
    }

    // 1. Find the occurrence of the route name
    final int nameIndex = content.indexOf(blockId);
    if (nameIndex == -1) {
      return;
    }

    // 2. Find the start of this specific GetPage block (the closest 'GetPage(' before the name)
    int startIndex = content.lastIndexOf('GetPage(', nameIndex);
    if (startIndex == -1) {
      return;
    }

    // Move startIndex back to include potential leading whitespace/indentation on that line
    while (startIndex > 0 &&
        (content[startIndex - 1] == ' ' || content[startIndex - 1] == '\t')) {
      startIndex--;
    }

    // Also include a leading newline if it exists to prevent empty lines
    if (startIndex > 0 && content[startIndex - 1] == '\n') {
      startIndex--;
    }

    // 3. Find the end of this GetPage block by counting parentheses
    var endIndex = -1;
    var counter = 0;
    var foundStart = false;

    for (var i = startIndex; i < content.length; i++) {
      if (content[i] == '(') {
        counter++;
        foundStart = true;
      } else if (content[i] == ')') {
        counter--;
      }

      // When counter returns to 0 after we've seen at least one '(', we've found the end
      if (foundStart && counter == 0) {
        endIndex = i;
        // Include trailing comma if present
        if (i + 1 < content.length && content[i + 1] == ',') {
          endIndex++;
        }
        break;
      }
    }

    if (endIndex != -1 && endIndex > startIndex) {
      final String removedBlock = content.substring(startIndex, endIndex + 1);
      content = content.replaceFirst(removedBlock, '');

      // Clean up multiple newlines or leading spaces left behind
      content = content.replaceAll(RegExp(r'\n\s*\n'), '\n');

      await file.writeAsString(content);
      kLog(
        '  - Surgically removed GetPage block from app_page.dart',
        type: LogType.success,
      );
    } else {
      kLog(
        '  - Could not safely calculate block bounds for $routeName',
        type: LogType.warning,
      );
    }
  }

  String _toSnakeCase(String input) {
    return input
        .replaceAllMapped(
          RegExp(r'([A-Z])'),
          (match) => '_${match.group(1)!.toLowerCase()}',
        )
        .replaceAll(RegExp(r'^\_'), '')
        .toLowerCase();
  }

  String _toPascalCase(String input) {
    if (input.isEmpty) {
      return '';
    }
    final String snake = _toSnakeCase(input);
    return snake
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join();
  }

  String _toCamelCase(String input) {
    if (input.isEmpty) {
      return '';
    }
    final String pascal = _toPascalCase(input);
    if (pascal.isEmpty) {
      return '';
    }
    return pascal[0].toLowerCase() + pascal.substring(1);
  }
}
