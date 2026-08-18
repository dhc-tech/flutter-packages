## 0.0.3

 - **FIX**(ci): melos release pipeline has never actually run — pin melos 6.x (#6).
 - **FIX**: clean example and linter hints for 100% 160/160 pana score.
 - **FEAT**: initial commit for flutter-packages monorepo with white_label_kit v0.0.1.
 - **DOCS**(white_label_kit): clarify dev_dependencies installation in README.
 - **DOCS**: standardize MIT license headers and holders across all monorepo packages.
 - **DOCS**: rewrite README with clear user guide and achieve 160/160 pana score for v0.0.2.

# Changelog

All notable changes to `white_label_kit` will be documented in this file.

## 0.0.2

### 🛠️ Improvements & Fixes
- **Linter & File Naming Conventions:** Renamed binary files (`bin/add_tenant.dart`, `bin/remove_tenant.dart`, `bin/update_tenant.dart`) to conform to standard Dart lower_case_with_underscores guidelines.
- **Documentation & User Guide:** Revamped `README.md` with clear, step-by-step onboarding, simple explanations, recommended project structure, and realistic usage examples.
- **Pub.dev Pana Score:** Resolved all unresolved dartdoc references and static analysis warnings to achieve 160/160 points.

## 0.0.1 — Initial Release

### ✨ Features
- **Zero-Touch Native Flavoring**:
  - Automatically manages Kotlin DSL Gradle flavors in `android/app/build.gradle.kts` without manual edits.
  - Automatically clones and manages Xcode build configurations and schemes in `ios/Runner.xcodeproj`.
- **Pure Dart Asset & Code Isolation**:
  - Compile-time asset staging and code generation (`lib/white_label.g.dart`) ensuring zero data leakage across tenant binaries.
  - Generates immutable runtime metadata accessible via `WhiteLabelRuntime`.
- **Interactive Multi-Tenant Runner & Builder**:
  - `dart run white_label_kit` or `dart run white_label_kit:menu`: Interactive CLI prompt with strict validation for tenant selection and 1-click execution (Run, Build APK, Build AAB, Build iOS, Configure, Add, Remove).
- **IDE Run & Build Integration**:
  - Auto-generates Android Studio & IntelliJ `.run/` configurations (`Debug`, `Release`, `Build APK`, `Build AppBundle`, `Build iOS`, `Configure`).
  - Auto-generates VS Code `.vscode/launch.json` and `.vscode/tasks.json`.
- **Comprehensive CLI Tooling**:
  - `init`: Scaffolds a starter `white_label.yaml`.
  - `configure`: Patches Android Gradle, iOS Xcode, and IDE run configs.
  - `generate`: Generates `lib/white_label.g.dart` for a specific tenant or default.
  - `add-tenant`: Programmatically adds a new tenant with auto-created asset folders.
  - `update-tenant`: Programmatically updates tenant metadata.
  - `remove-tenant`: Cleanly purges tenant configurations, native flavors, and IDE configs.
  - `validate`: Strict offline configuration and asset validation.
  - `list`: Displays all configured tenants and default tenant.
  - `build`: Staged multi-platform builds for CI/CD.
  - `run`: Resolves and runs a tenant environment with proper `--flavor` and `--dart-define`.
