# Changelog

All notable changes to this project will be documented in this file.

## [1.8.0] - 2026-04-10

### Added

- **Smart Context-Aware Dashboard:** The interactive menu now dynamically detects Flutter projects. If outside a project, it hides unrelated categories (Build, Signing, Configuration), presenting a clean "Project Creation" focus.
- **Universal Shell Automation:** Upgraded `dg setup-aliases` to be fully cross-platform. It now automatically detects and configures PowerShell (Windows), Zsh (macOS), and Bash (Linux) with a single command.
- **Deep ZIP Extraction:** Upgraded project creation logic with a recursive search engine that finds the template root regardless of GitHub's nested archive structure.

### Changed

- **Surgical Module Removal:** Completely refactored `RemoveModuleCommand` to use a **Parenthesis-Tracking Engine**. This ensures 100% syntactical integrity when deleting GetX pages from `app_page.dart`, eliminating trailing commas or dangling code fragments.
- **Template Reliability:** Fixed a critical bug where project creation failed because it incorrectly checked `pubspec.yaml` as a directory instead of a file.

### Fixed

- **Interactive Menu Stability:** Resolved a premature class closure bug that caused syntax errors in the interactive dashboard.
- **Cross-Platform Pathing:** Optimized environment variable injection for Android Studio and FVM paths on Windows and Unix systems.

## [1.7.5] - 2026-03-24

### Added

- **Interactive Build Suite:** `BuildCommand` (APK/Bundle) and `IosBuildCommand` now support a full interactive flow, prompting for output directory, custom name prefix, and timestamp preference if not provided via CLI flags.
- **Advanced Repository Automation:** Implemented a "Proper" GitHub automation suite including:
  - **PR Labeler:** Automatic categorization of Pull Requests based on file changes.
  - **Stale Bot:** Automated maintenance of inactive issues and PRs.
  - **Modern Issue Forms:** YAML-based Bug Report and Feature Request forms to ensure high-quality, structured feedback with required technical context (logs, version: 1.8.0)
- **Quality Assurance:** Added a structured **Pull Request Template** with a comprehensive quality checklist to maintain project standards.

### Changed

- **Refined Interactive Menu:** Migrated the dashboard to a centralized `CommandRunner` architecture. Updated build prompts to use a **Styled Multi-layer Response** system that clearly separates configuration from execution logs.
- **CI/CD Standardization:** Migrated all GitHub Actions to the official **`setup-dart@v1.7.2`** and modern **`checkout@v6`**, ensuring native Node 24 support and consistent environment parity.

### Removed

- **Firebase Command Suite:** Removed `dg firebase` and associated interactive menu options due to stability issues with external dependencies.


### Fixed

- **Rename Command Stability:** Resolved a "Null check operator" crash when invoking the rename command from the interactive dashboard without pre-defined arguments.
- **Build Output Visibility:** Significantly improved the post-build summary with a **boxed layout**, clear **📁 Location** paths, and **📊 Size** metrics for better user verification.
- **CI Reliability:** Narrowed down the Analyze and Format tasks to focus on the CLI source code (`lib`, `bin`), resolving package resolution errors (like `flutter_lints`) in the `sample/` directory.

## [1.7.4] - 2026-03-20

### Added

- **`dg pub-cache`:** Register and document the pub cache repair command (`flutter pub cache repair`); it was previously implemented but not wired into the CLI or interactive flow.

### Changed

- **Interactive dashboard:** Category → action navigation with a **single bordered card** per screen (same 50-column style as `dg version`), `╠` divider between header and actions, and prompts outside the box. Submenus use **0 · Back** where appropriate.
- **Logging / terminals:** `kLog` respects **`NO_COLOR`**, **`TERM=dumb`**, and non-TTY stdout via `kAnsiStdoutEnabled` so output stays readable when piped or in minimal environments.

### Removed

- Stray `lib/src/commands/asset_command.dart.bak` from the repository.

## [1.7.3] - 2026-03-19

### Added

- **Beta/Dev Update (Option 16):** New interactive menu option to check for and install pre-release (dev/beta) versions directly from the CLI dashboard.

### Fixed

- **Localization Files Preserved:** Asset generation now only cleans `lib/generated/assets/` instead of the entire `lib/generated/` directory, preserving localization files and other generated code.
- **Numeric Asset Filenames:** Files starting with a number (e.g., `4.png`) now generate valid Dart constants with `ic` prefix (e.g., `ic4`) instead of producing invalid identifiers that break compilation.
- **Pubspec Stale Entry Cleanup:** Deleted asset folders are now automatically removed from the `pubspec.yaml` assets section. Only entries within the configured `assets-dir` are managed — `.env`, localization paths, and other manually-added entries are never touched.
- **Space in Filenames:** Asset filenames containing spaces (e.g., `my image.png`) are properly converted to camelCase constants (`myImage`).

## [1.7.2] - 2026-03-19

### Added

- **Categorized Developer Dashboard:** The interactive menu is organized into sections: **BUILD & RELEASE**, **CLEAN & FIX**, **SIGNING & KEYS**, **CONFIGURATION**, **PROJECT MANAGEMENT**, and **UTILITIES**.
- **Enhanced Author Branding:** Prominent author branding on the main dashboard and version command.
- **Fast Clean (Option 4):** Dedicated option for a simple `flutter clean`.
- **Full Project Reset (Option 5):** Thorough cleanup (`flutter clean`, `pub get`, `pod install` on macOS) with an optional global cache wipe.
- **One-click Update (Option 15):** Check pub.dev and run `dart pub global activate` when a newer stable version exists.
- **Firebase Command Suite:** `dg firebase` with `login`, `logout`, `configure`, and `check` subcommands.
- **Firebase Auto-Installer:** Detection and installation of `firebase-tools` and `flutterfire_cli`.
- **Hash Key Generation:** Base64-encoded SHA1 hash keys for Android (Facebook/Google login flows).
- **Firebase Account Display:** Interactive Firebase sub-menu shows the logged-in email when available.
- **Pubspec Automation:** `dg asset build` registers new asset folders and `.env` in `pubspec.yaml`.

### Fixed

- **Assets Generation:** Invalid Dart identifiers for numeric file names (e.g. `String 6`) fixed by auto-prefixing.
- **Assets Cleanup:** Deleted assets no longer leave stale generated Dart code; `lib/generated` is refreshed on each build.
- **Pubspec Formatter:** Asset generator no longer skips the end of the `assets:` section when multiple subsections exist.
- **Console UI:** Improved interactive menu readability on dark terminals (blue → cyan).
- **Ultra-Robust Firebase Detection:** Reads the official Firebase config for login status.
- **Smart iOS Cleanup:** Full reset checks for a `Podfile` before running CocoaPods.
- **Cross-Platform Watching:** Uses `package:watcher` for asset watching on Ubuntu, Windows, and macOS.
- **JKS Portability:** `create-jks` uses relative `storeFile` paths in `key.properties`.

## [1.7.0] - 2026-02-25

### Initial Release

- **Smart Scaffolding**: Bootstrap a "Proper" Flutter Project with dynamic app name injection, pre configured GetX architecture, and best practices.
- **UIScene & SceneDelegate**: Full support for the modern iOS `UIScene` lifecycle by default.
- **Firebase Robustness**: 100% crash-proof initial launch with pre-configured, commented-out Firebase initializers for easy setup.
- **Asset Generation**: Subfolder-based, type-safe asset constants generation with `dg asset build/watch`.
- **Dependency Management**: Native Swift Package Manager (SPM) integration for iOS, eliminating CocoaPods friction.
- **Module Creator**: Automated GetX scaffolding (`View`, `Controller`, `Binding`) with auto-routing.
- **Deep Rename**: One-command smart renaming for Android, iOS, macOS, Windows, Linux, and Web.
- **Security**: Automatic JKS generation and secure `.env` API key injection.
- **Deep Clean**: A "nuclear" clean command that wipes caches across all platforms.
- **Notification Services**: Pre-integrated, align with official best practices, and controllable via bindings.
- **Documentation**: Professional `README.md` and comprehensive asset generation guides.
