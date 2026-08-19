# white_label_kit Implementation & Usage Guide

This guide demonstrates how to integrate and use `white_label_kit` in a Flutter application.

---

## 1. Installation

Add `white_label_kit` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  white_label_kit:
    path: packages/white_label_kit # or version constraint when published
```

Run:
```bash
flutter pub get
```

---

## 2. Configuration (`white_label.yaml`)

Define your tenants and defaults in `white_label.yaml` in the root of your project:

```yaml
white_label:
  default_tenant: acme

  tenants:
    acme:
      name: "Acme Corp"
      version: "1.0.0+1"
      android:
        application_id: "com.example.acme"
        app_name: "Acme"
      ios:
        bundle_id: "com.example.acme"
        app_name: "Acme"
      assets:
        logo: "tenants/acme/assets/logo.png"
      theme:
        primary_color: "#D41414"
      environment:
        api_base_url: "https://api.acme.example.com"

    beta:
      name: "Beta Corp"
      version: "1.0.0+1"
      android:
        application_id: "com.example.beta"
        app_name: "Beta Corp"
      ios:
        bundle_id: "com.example.beta"
        app_name: "Beta Corp"
      assets:
        logo: "tenants/beta/assets/logo.png"
      theme:
        primary_color: "#1450DC"
      environment:
        api_base_url: "https://api.beta.example.com"
```

---

## 3. Native Setup: Zero-Touch `configure`

Run the `configure` command to automatically patch `android/app/build.gradle.kts` and `ios/Runner.xcodeproj` with flavor configurations for all declared tenants:

```bash
dart run white_label_kit:configure
```

You can also run a dry-run or target a specific platform:
```bash
# Preview changes without modifying files
dart run white_label_kit:configure --dry-run

# Configure Android only
dart run white_label_kit:configure --platform android
```

---

## 4. Compile-Time Dart Generation

Generate `lib/white_label.g.dart` containing strongly-typed constants for your tenant configuration:

```bash
dart run white_label_kit:generate --tenant acme
```

This ensures only the selected tenant's configuration is compiled into the binary (zero tenant data leakage).

---

## 5. Runtime Usage in Flutter

Use `WhiteLabelRuntime` in your widget tree to dynamically adapt theme, assets, and metadata:

```dart
import 'package:flutter/material.dart';
import 'package:white_label_kit/white_label_kit.dart';
import 'white_label.g.dart'; // Generated file

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Current runtime config resolved at build time
    final runtime = whiteLabelDefaultRuntime;
    final primaryColor = _parseColor(runtime.theme.primaryColorHex ?? '#1976D2');

    return MaterialApp(
      title: runtime.tenantName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text(runtime.tenantName),
          backgroundColor: primaryColor,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Tenant: ${runtime.tenantName} (${runtime.tenantId})',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text('API: ${runtime.environment.apiBaseUrl}'),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    final cleanHex = hex.replaceFirst('#', '');
    final fullHex = cleanHex.length == 6 ? 'FF$cleanHex' : cleanHex;
    return Color(int.parse(fullHex, radix: 16));
  }
}
```

---

## 6. Build & Run CLI Commands

### Validate Configuration
```bash
dart run white_label_kit:validate
```

### List Configured Tenants
```bash
dart run white_label_kit:list
```

### Add a New Tenant
```bash
dart run white_label_kit:add-tenant gamma "Gamma Inc" com.example.gamma
```

### Build a Tenant
```bash
# Build Android APK
dart run white_label_kit:build --tenant acme --platform android --mode release

# Build iOS IPA
dart run white_label_kit:build --tenant acme --platform ios --mode release

# Or standard Flutter CLI (after running configure)
flutter build apk --flavor acme --dart-define=TENANT_ID=acme
```
