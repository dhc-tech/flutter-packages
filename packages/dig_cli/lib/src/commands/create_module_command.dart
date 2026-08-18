import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';
import '../utils/project_utils.dart';
import '../utils/spinner.dart';
import '../ui/box_painter.dart';

class CreateModuleCommand extends Command {
  @override
  final name = 'create-module';
  @override
  final aliases = ['add-module'];
  @override
  final description =
      'Creates a new GetX module (View, Controller, Binding) and registers routes.';

  CreateModuleCommand() {
    argParser.addOption('name',
        abbr: 'n', help: 'The name of the new module (e.g., "auth")');
  }

  @override
  Future<void> run() async {
    if (!await isFlutterProject()) {
      kLog('❗ This command must be run inside a Flutter project.',
          type: LogType.error);
      return;
    }

    String? moduleName = argResults?['name'] as String?;
    if (moduleName == null || moduleName.isEmpty) {
      if (argResults!.rest.isNotEmpty) {
        moduleName = argResults!.rest.first;
      } else {
        stdout.write('Enter module name (e.g., auth): ');
        moduleName = stdin.readLineSync()?.trim();
      }
    }

    if (moduleName == null || moduleName.isEmpty) {
      kLog('❗ Module name is required.', type: LogType.error);
      return;
    }

    final String finalModuleName = moduleName;

    // Clean up module name (e.g., 'AuthView' -> 'Auth', 'user_module' -> 'user')
    final String cleanModuleName = finalModuleName
        .replaceAll(
            RegExp(r'_?(View|Controller|Binding|Module)$',
                caseSensitive: false),
            '')
        .trim();

    final slug = _toSnakeCase(cleanModuleName);
    final className = _toPascalCase(cleanModuleName);
    final moduleDir = Directory(p.join('lib', 'app', 'module', slug));

    if (await moduleDir.exists()) {
      kLog('❗ Module $slug already exists.', type: LogType.error);
      return;
    }

    await runWithSpinner('🏗️  Scaffolding $className module...', () async {
      await Directory(p.join(moduleDir.path, 'view')).create(recursive: true);
      await Directory(p.join(moduleDir.path, 'controller'))
          .create(recursive: true);
      await Directory(p.join(moduleDir.path, 'binding'))
          .create(recursive: true);

      await _createController(moduleDir, className, slug);
      await _createBinding(moduleDir, className, slug);
      await _createView(moduleDir, className, slug);
      await _createExport(moduleDir, slug);
    });

    await runWithSpinner('🏷️  Registering Routes...', () async {
      await _registerRoute(className, slug);
      await _registerModuleExport(slug);
      await _registerPage(className, slug);
    });

    final painter = BoxPainter();
    print('');
    painter.drawHeader('MODULE CREATED SUCCESSFULLY', width: 50);
    painter.drawRow('Module', className, width: 50);
    painter.drawRow('Route', 'AppRoute.${_toCamelCase(slug)}', width: 50);
    painter.drawRow('Files', 'Scaffolded in lib/app/module/$slug/', width: 50);
    painter.drawFooter(width: 50);

    kLog('\n✅ Module $className is ready to use!', type: LogType.success);
  }

  Future<void> _createController(
      Directory dir, String className, String slug) async {
    final file =
        File(p.join(dir.path, 'controller', '${slug}_controller.dart'));
    final content = '''
import '../../../utils/import.dart';

class ${className}Controller extends GetxController {
  RxBool isLoading = false.obs;
}
''';
    await file.writeAsString(content);
  }

  Future<void> _createBinding(
      Directory dir, String className, String slug) async {
    final file = File(p.join(dir.path, 'binding', '${slug}_binding.dart'));
    final content = '''
import '../../../utils/import.dart';
import '../controller/${slug}_controller.dart';

class ${className}Binding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<${className}Controller>(
      () => ${className}Controller(),
    );
  }
}
''';
    await file.writeAsString(content);
  }

  Future<void> _createView(Directory dir, String className, String slug) async {
    final file = File(p.join(dir.path, 'view', '${slug}_view.dart'));
    final content = '''
import '../../../utils/import.dart';
import '../controller/${slug}_controller.dart';

class ${className}View extends GetView<${className}Controller> {
  const ${className}View({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      title: CustomTextView(
        text: '$className',
        style: AppTextStyle.appBarTitle(),
      ),
      body: Center(
        child: CustomTextView(
          text: '$className View is working',
          style: AppTextStyle.medium(size: 16),
        ),
      ),
    );
  }
}
''';
    await file.writeAsString(content);
  }

  Future<void> _createExport(Directory dir, String slug) async {
    final file = File(p.join(dir.path, '${slug}_export.dart'));
    final content = '''
export 'binding/${slug}_binding.dart';
export 'controller/${slug}_controller.dart';
export 'view/${slug}_view.dart';
''';
    await file.writeAsString(content);
  }

  Future<void> _registerModuleExport(String slug) async {
    final exportFile =
        File(p.join('lib', 'app', 'module', 'module_export.dart'));
    if (!await exportFile.exists()) {
      await exportFile.parent.create(recursive: true);
      await exportFile.writeAsString('''
// ignore_for_file: directives_ordering

/// This file exports all modular components (Views, Controllers, Bindings).
/// It is automatically updated by the DIG CLI.

export 'splash/splash_export.dart';
''');
    }

    final content = await exportFile.readAsString();
    final exportLine = "export '$slug/${slug}_export.dart';";
    if (content.contains(exportLine)) return;

    final lines = content.split('\n');
    lines.add(exportLine);

    // Header and non-export lines
    final headerLines =
        lines.where((l) => !l.trim().startsWith('export')).toList();
    final exportLines =
        lines.where((l) => l.trim().startsWith('export')).toList();
    exportLines.sort();

    final newContent =
        "${[...headerLines, ...exportLines].join('\n').trim()}\n";
    await exportFile.writeAsString(newContent);
  }

  Future<void> _registerRoute(String className, String slug) async {
    final file = File(p.join('lib', 'app', 'routes', 'app_route.dart'));
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsString('''
abstract class AppRoute {
  AppRoute._();
  static const String splash = '/';
}
''');
    }

    final content = await file.readAsString();
    final routeName = _toCamelCase(slug);
    if (content.contains('$routeName =')) return;

    // Find the last closing brace of the AppRoute class
    final lastBraceIndex = content.lastIndexOf('}');
    if (lastBraceIndex == -1) return;

    final updatedContent = "${content.substring(0, lastBraceIndex)}"
        "  static const String $routeName = '/$className';\n"
        "${content.substring(lastBraceIndex)}";

    await file.writeAsString(updatedContent);
  }

  Future<void> _registerPage(String className, String slug) async {
    final file = File(p.join('lib', 'app', 'routes', 'app_page.dart'));
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsString('''
import '../module/module_export.dart';
import '../utils/import.dart';

abstract class AppPage {
  AppPage._();
  static const String initial = AppRoute.splash;
  static final List<GetPage> routes = [
    GetPage(
      name: AppRoute.splash,
      page: () => const SplashView(),
      binding: SplashBinding(),
    ),
  ];
}
''');
    }

    String content = await file.readAsString();
    final routeName = _toCamelCase(slug);

    // Ensure module_export.dart is imported
    if (!content.contains("import '../module/module_export.dart';")) {
      content = "import '../module/module_export.dart';\n$content";
    }

    if (!content.contains('AppRoute.$routeName')) {
      final newPage = '''
    GetPage(
      name: AppRoute.$routeName,
      page: () => const ${className}View(),
      binding: ${className}Binding(),
    ),''';

      // Look for the end of the static final List<GetPage> routes
      final listEndIndex = content.lastIndexOf('];');
      if (listEndIndex == -1) return;

      final updatedContent = "${content.substring(0, listEndIndex)}"
          "$newPage"
          "${content.substring(listEndIndex)}";

      await file.writeAsString(updatedContent);
    }
  }

  String _toSnakeCase(String input) {
    return input
        .replaceAllMapped(
            RegExp(r'([A-Z])'), (match) => '_${match.group(1)!.toLowerCase()}')
        .replaceAll(RegExp(r'^\_'), '')
        .toLowerCase();
  }

  String _toPascalCase(String input) {
    if (input.isEmpty) return '';
    final snake = _toSnakeCase(input);
    return snake
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join();
  }

  String _toCamelCase(String input) {
    if (input.isEmpty) return '';
    final pascal = _toPascalCase(input);
    if (pascal.isEmpty) return '';
    return pascal[0].toLowerCase() + pascal.substring(1);
  }
}
