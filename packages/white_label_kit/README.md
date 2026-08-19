# white_label_kit

[![pub package](https://img.shields.io/pub/v/white_label_kit.svg)](https://pub.dev/packages/white_label_kit)
[![Dart](https://img.shields.io/badge/Dart-3.13+-blue.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.22+-02569B.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**The modern, automated flavor & multi-tenant white-label toolkit for Flutter.**

Easily manage multiple branded apps, flavors, and client tenants from a single Flutter codebase. Define all your tenants in `white_label.yaml`, and let `white_label_kit` automate Android Gradle flavors, iOS Xcode build schemes, IDE configurations, and compile-time asset isolation.

---

## 💡 Why white_label_kit?

Managing multiple flavors or white-label client apps in Flutter usually means:
- Hand-editing complex `android/app/build.gradle.kts` product flavors.
- Manually creating and wiring iOS Xcode build configurations, schemes, and bundle identifiers.
- Risking asset leakage where one tenant's logos or credentials accidentally get bundled into another tenant's app.
- Manually configuring IDE debug and build tasks for every new flavor.

**`white_label_kit` automates all of this:**
- 📄 **Single Source of Truth:** Declare all tenants, bundle IDs, colors, API endpoints, and feature flags in one `white_label.yaml`.
- 🤖 **Native File Automation:** Patches Android Gradle and iOS Xcode schemes automatically with `dart run white_label_kit:configure`.
- 🛡️ **Asset Isolation:** Guarantees only the active tenant's assets and configs are compiled into the binary.
- ⚡ **Interactive CLI Runner:** Launch `dart run white_label_kit` to easily run or build APK, AAB, and iOS apps without memorizing long commands.
- 💻 **1-Click IDE Configurations:** Generates ready-to-use Run/Build configurations for **Android Studio**, **IntelliJ**, and **VS Code**.
- 🔒 **Type-Safe Runtime API:** Access tenant metadata cleanly in your Flutter widgets and services using `WhiteLabelRuntime`.

---

## 🚀 Getting Started

### 1. Add Dev Dependency
Add `white_label_kit` to your Flutter project's `dev_dependencies`:

```bash
flutter pub add --dev white_label_kit
```

Or manually in `pubspec.yaml`:

```yaml
dev_dependencies:
  white_label_kit: ^0.0.2
```

> **Note:** `white_label_kit` generates self-contained, typed code (`lib/white_label.g.dart`) and manages native Gradle/Xcode files at build time, keeping your production app binary lightweight with zero runtime overhead.

### 2. Initialize Configuration
Generate a starter `white_label.yaml` in your project root:

```bash
dart run white_label_kit:init
```

### 3. Add Your Tenants / Brands
Add a new brand with a single command:

```bash
dart run white_label_kit:add-tenant acme "Acme App" com.example.acme
```

This automatically creates the configuration entry in `white_label.yaml` and prepares the asset folder `tenants/acme/`.

### 4. Configure Android & iOS Native Files
Sync all native Gradle flavors, Xcode schemes, and IDE run configurations:

```bash
dart run white_label_kit:configure
```

---

## 🖥️ Running & Building Your App

### Option A: Interactive Terminal Menu (Recommended)
Launch the interactive runner:

```bash
dart run white_label_kit
```

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

### Option B: Flutter CLI Commands
You can also run or build directly with standard Flutter commands:

```bash
# Run tenant in debug mode
flutter run --flavor acme --dart-define=TENANT_ID=acme

# Build Android Release APK
flutter build apk --release --flavor acme --dart-define=TENANT_ID=acme

# Build Android Release AppBundle (Google Play)
flutter build appbundle --release --flavor acme --dart-define=TENANT_ID=acme

# Build iOS Release App
flutter build ios --release --flavor acme --dart-define=TENANT_ID=acme
```

---

## 📁 Recommended Folder Structure

Group tenant-specific logos and platform credentials under the root `tenants/` folder:

```text
my_flutter_app/
├── white_label.yaml                # 🌟 Central configuration for all tenants
├── tenants/                        # 📂 Assets grouped per tenant
│   ├── acme/
│   │   ├── logo.png                # 🎨 App logo / icon asset
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
│   └── white_label.g.dart          # ⚡ Generated typed tenant constants
└── pubspec.yaml
```

---

## ⚙️ Configuration File (`white_label.yaml`)

Define all tenant properties in `white_label.yaml`:

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

## 📱 Accessing Tenant Data in Flutter (Dart)

Access your active tenant's branding, API endpoints, and feature flags anywhere in your Dart code:

```dart
import 'package:flutter/material.dart';
import 'package:white_label_kit/white_label_kit.dart';
import 'white_label.g.dart';

void main() {
  final runtime = whiteLabelRuntime;

  print('Tenant ID: ${runtime.id}');
  print('App Name: ${runtime.name}');
  print('API URL: ${runtime.apiBaseUrl}');
  print('Primary Color: ${runtime.primaryColor}');

  final hasPush = runtime.featureEnabled('enable_push_notifications');
  print('Push Notifications: $hasPush');

  runApp(MyApp(runtime: runtime));
}
```

---

## 📖 CLI Commands Reference

| Command | Description |
|---|---|
| `dart run white_label_kit` | Opens the interactive terminal runner & builder menu |
| `dart run white_label_kit:init` | Creates a starter `white_label.yaml` file |
| `dart run white_label_kit:configure` | Automatically patches Android Gradle, iOS Xcode schemes, and IDE configurations |
| `dart run white_label_kit:add-tenant <id> "<Name>" <pkg>` | Adds a new tenant and creates its asset directory |
| `dart run white_label_kit:update-tenant <id> [options]` | Updates tenant configuration fields |
| `dart run white_label_kit:remove-tenant <id>` | Removes tenant from YAML, deletes asset folder, and removes native schemes |
| `dart run white_label_kit:generate [--tenant <id>]` | Generates `lib/white_label.g.dart` |
| `dart run white_label_kit:validate` | Validates `white_label.yaml` syntax and asset paths |
| `dart run white_label_kit:list` | Lists all declared tenants and the default tenant |
| `dart run white_label_kit:doctor` | Performs a multi-tenant health check |

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/dhc-tech/flutter-packages/issues).

---

## 👤 Author

Maintained by **DHC Tech**.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
