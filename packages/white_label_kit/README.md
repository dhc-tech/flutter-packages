# white_label_kit

[![Dart](https://img.shields.io/badge/Dart-3.13+-blue.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.22+-02569B.svg)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.0.1-brightgreen.svg)](CHANGELOG.md)

**Zero-touch multi-tenant white-labeling & build-time asset isolation for Flutter applications.**

Define all your tenants in a single `white_label.yaml` file, and let `white_label_kit` automatically manage your Android Gradle product flavors, iOS Xcode build configurations and schemes, IDE run configurations, and compile-time asset isolation.

---

## 🚀 Key Features

- **⚡ Zero-Touch Native Flavoring**:
  - Automatically manages Kotlin DSL Gradle flavors in `android/app/build.gradle.kts`.
  - Automatically manages Xcode configurations and schemes in `ios/Runner.xcodeproj`.
- **🔒 Build-Time Data & Asset Isolation**:
  - No data leakage: only the selected tenant's configuration and assets are compiled into the binary.
  - Generates typed, immutable constants via `lib/white_label.g.dart`.
- **🎯 Interactive CLI Runner & Builder**:
  - Run `dart run white_label_kit` for an interactive terminal menu with strict input validation for 1-click Run, Debug, and Release Builds (APK, AAB, iOS).
- **💻 Full IDE Integration**:
  - Generates `.run/` configurations for **Android Studio / IntelliJ**.
  - Generates `.vscode/launch.json` and `.vscode/tasks.json` for **VS Code**.
- **🛠️ Production-Ready CLI**:
  - Automated tenant onboarding, updating, removing, and validation.

---

## 📦 Installation

Add `white_label_kit` to your `pubspec.yaml`:

```yaml
dependencies:
  # Or path dependency if developing locally:
  white_label_kit:
    path: packages/white_label_kit
```

---

## ⚡ Quick Start

### 1. Initialize Configuration
Scaffold a starter `white_label.yaml` in your project root:

```bash
dart run white_label_kit:init
```

### 2. Add Your Tenants
Add your first tenant:

```bash
dart run white_label_kit:add-tenant acme "Acme College" com.acme.student
```

### 3. Configure Native Files & IDEs
Automatically wire Android Gradle flavors, iOS Xcode schemes, and IDE configurations:

```bash
dart run white_label_kit:configure
```

### 4. Run or Build
Launch the interactive runner:

```bash
dart run white_label_kit
```

Or build directly using Flutter:

```bash
flutter run --flavor acme --dart-define=TENANT_ID=acme
flutter build apk --release --flavor acme --dart-define=TENANT_ID=acme
flutter build appbundle --release --flavor acme --dart-define=TENANT_ID=acme
flutter build ios --release --flavor acme --dart-define=TENANT_ID=acme
```

---

## ⚙️ Configuration Schema (`white_label.yaml`)

All tenant configurations live in a single, version-controlled file:

```yaml
white_label:
  default_tenant: acme

  tenants:
    acme:
      name: "Acme App"
      version: "1.0.0+1"

      android:
        application_id: "com.example.acme"
        app_name: "Acme App"

      ios:
        bundle_id: "com.example.acme"
        app_name: "Acme App"

      theme:
        primary_color: "#1E88E5"
        secondary_color: "#FFC107"
        background_color: "#FFFFFF"
        surface_color: "#F5F5F5"

      environment:
        api_base_url: "https://api.example.com"
        sentry_dsn: "https://example@sentry.io/123"

      features:
        enable_push_notifications: true
        enable_downloads: true

      assets:
        logo: "tenants/acme/logo.png"

      firebase:
        google_services_json: "tenants/acme/firebase/google-services.json"
        google_service_info_plist: "tenants/acme/firebase/GoogleService-Info.plist"
```

---

## 📁 Recommended Folder Structure

Keep all tenant-specific static assets and platform configuration files cleanly grouped under the root `tenants/` folder:

```text
my_flutter_app/
├── white_label.yaml                # 🌟 Single source of truth for all tenants
├── tenants/                        # 📂 Per-tenant asset directory
│   ├── acme/
│   │   ├── logo.png                # 🎨 App logo / icon source (PNG)
│   │   └── firebase/               # 🔒 Firebase credentials (optional)
│   │       ├── google-services.json
│   │       └── GoogleService-Info.plist
│   │
│   └── beta/
│       ├── logo.png
│       └── firebase/
│           ├── google-services.json
│           └── GoogleService-Info.plist
│
├── lib/
│   ├── main.dart
│   └── white_label.g.dart          # ⚡ Auto-generated typed tenant constants
└── pubspec.yaml
```

> **💡 Best Practices:**
> - **Only Assets in `tenants/<id>/`:** Do not place JSON/YAML config files inside `tenants/<id>/`. All configuration belongs in `white_label.yaml`.
> - **Build-Time Isolation:** When building for `acme`, only `tenants/acme/` assets are bundled into the binary. `beta` files are strictly excluded.

---

## 🖥️ Interactive Runner (`dart run white_label_kit`)

Launch the interactive launcher at any time:

```text
╔══════════════════════════════════════════════════════════════════╗
║              ✨ WHITE_LABEL_KIT RUNNER & BUILDER                 ║
║          Automated Multi-Tenant Flutter CLI & Launcher           ║
╚══════════════════════════════════════════════════════════════════╝

📌 SELECT TENANT:
   [0] Acme App [acme] (Default)

Enter tenant number (default: acme): 0

⚡ SELECT ACTION:
   [1] ▶️  Run in Debug Mode (Simulator / Connected Device)
   [2] ⚡  Run in Release Mode (Device)
   [3] 🚀  Build Release APK (Android)
   [4] 📦  Build Release AppBundle / AAB (Google Play Store)
   [5] 🍎  Build Release iOS (Simulator / Archive)
   [6] 🔧  Configure All Tenants (white_label_kit:configure)
   [7] ➕  Add New Tenant (white_label_kit:add-tenant)
   [8] ❌  Remove Tenant (white_label_kit:remove-tenant)
   [9] 🔍  Analyze & Health Check (Flutter Analyze + Tests)
   [0] 🚪  Exit
```

---

## 📖 CLI Commands Reference

| Command | Description |
|---|---|
| `dart run white_label_kit` | Opens the interactive runner and builder |
| `dart run white_label_kit:configure` | Configures Android Gradle, iOS Xcode, and IDE run configs |
| `dart run white_label_kit:add-tenant <id> "<Name>" <pkg>` | Adds a new tenant and scaffolds its assets directory |
| `dart run white_label_kit:update-tenant <id> [options]` | Updates tenant configuration fields |
| `dart run white_label_kit:remove-tenant <id>` | Removes tenant from YAML, deletes asset folder, and purges native configs |
| `dart run white_label_kit:generate [--tenant <id>]` | Generates `lib/white_label.g.dart` |
| `dart run white_label_kit:validate` | Validates `white_label.yaml` syntax and asset paths |
| `dart run white_label_kit:list` | Lists all declared tenants and default tenant |
| `dart run white_label_kit:doctor` | Performs a multi-tenant health check |

---

## 📱 Typed Runtime Access (`WhiteLabelRuntime`)

Access tenant configurations safely at runtime without parsing YAML:

```dart
import 'package:white_label_kit/white_label_kit.dart';
import 'white_label.g.dart';

void main() {
  final runtime = whiteLabelRuntime;

  print('Tenant ID: ${runtime.id}');
  print('App Name: ${runtime.name}');
  print('API Base URL: ${runtime.apiBaseUrl}');
  print('Primary Color: ${runtime.primaryColor}');
  print('Feature Push Notifications: ${runtime.featureEnabled("enable_push_notifications")}');
}
```

---

## 🛡️ License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
