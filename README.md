# 📦 Flutter Packages Monorepo

[![CI Pipeline](https://github.com/dhc-tech/flutter-packages/actions/workflows/ci.yml/badge.svg)](https://github.com/dhc-tech/flutter-packages/actions/workflows/ci.yml)
[![Pub.dev Publisher](https://img.shields.io/badge/pub.dev-dhc--tech-0175C2.svg?logo=dart)](https://pub.dev/publishers/dhc.tech/packages)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

A centralized, production-grade monorepo containing official Flutter plugins, Dart developer CLI tools, and multi-tenant application kits maintained by **[dhc-tech](https://github.com/dhc-tech)**.

---

## 📚 Available Packages

| Package | Version | Type | Description | Pub.dev Score |
|---|---|---|---|---|
| **[`white_label_kit`](packages/white_label_kit)** | [![white_label_kit](https://img.shields.io/badge/version-0.0.2-green.svg)](packages/white_label_kit/CHANGELOG.md) | Multi-Tenant Tool | Flavor management, Gradle/Xcode automation, and compile-time asset isolation. | [![Pana Points](https://img.shields.io/badge/pana-160%2F160-brightgreen.svg)](https://pub.dev/packages/white_label_kit/score) |
| **[`dig_cli`](packages/dig_cli)** | [![dig_cli](https://img.shields.io/badge/version-1.8.0-green.svg)](packages/dig_cli/CHANGELOG.md) | Developer CLI | Interactive CLI for Flutter code generation, asset indexing, keystores, and scaffolding. | [![Pana Points](https://img.shields.io/badge/pana-160%2F160-brightgreen.svg)](https://pub.dev/packages/dig_cli/score) |
| **[`apple_sign_in_plugin`](packages/apple_sign_in_plugin)** | [![apple_sign_in_plugin](https://img.shields.io/badge/version-1.2.6-green.svg)](packages/apple_sign_in_plugin/CHANGELOG.md) | Flutter Plugin | Native Sign in with Apple integration with JWT decoding, token validation, and state management. | [![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20macOS%20%7C%20Web-blue.svg)](https://pub.dev/packages/apple_sign_in_plugin) |

---

## 🏛️ Monorepo Architecture

```text
flutter-packages/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml             # 🐛 Standardized bug reporting form
│   │   └── feature_request.yml        # 💡 Feature request submission form
│   ├── workflows/
│   │   ├── ci.yml                     # 🔍 Formatting, static analysis & test matrix
│   │   ├── pull_request_label.yml     # 🏷️ Automatic package path PR labeler
│   │   ├── auto_submit.yml            # 🤖 Automated PR merge & submit pipeline
│   │   ├── ai_pr_review.yml           # 🧠 Free Gemini 2.0 Flash AI code reviewer
│   │   ├── ai_issue_triage.yml        # 🤖 Free Gemini 2.0 Flash AI issue assistant
│   │   └── publish.yml                # 🚀 Pub.dev automated publishing workflow
│   ├── dependabot.yml                 # 🔄 Automated weekly dependency maintenance
│   ├── labeler.yml                    # 🏷️ Package-to-label mapping configuration
│   └── pull_request_template.md       # 📋 PR quality & zero-bug checklist
│
├── packages/                          # 📦 Published Dart & Flutter packages
│   ├── white_label_kit/               # 🏷️ Multi-tenant white-label CLI & runtime engine
│   ├── dig_cli/                       # 🛠️ Flutter developer CLI & code generation engine
│   └── apple_sign_in_plugin/          # 🍎 Cross-platform Apple authentication plugin
│
├── melos.yaml                         # ⚡ Multi-package workspace orchestration
├── LICENSE                            # ⚖️ MIT Open Source License
└── README.md                          # 📖 Monorepo documentation
```

---

## 🎯 Why a Monorepo?

Instead of maintaining 10 separate GitHub repositories with duplicated CI configs, issues, and releases, this monorepo provides:

1. **Single Source of Truth:** All DHC Tech plugins live in one organized repository with atomic versioning.
2. **Unified CI/CD Matrix:** A single GitHub Actions pipeline runs static analysis, formatting checks, and tests across all packages simultaneously.
3. **Automated Maintenance:** Dependabot, automated path-based PR labeling (`actions/labeler`), and auto-merging (`autosubmit`) manage overhead automatically.
4. **Free AI-Powered Reviews:** Google Gemini 2.0 Flash automatically reviews PR diffs and triages user issues with zero recurring cost.
5. **Instant Local Development (Melos):** Run tests, analysis, and formatting across all packages with single commands.

---

## 🛠️ Local Development & Testing

### 1. Resolve All Dependencies
```bash
for pkg in packages/*; do
  if [ -d "$pkg" ] && [ -f "$pkg/pubspec.yaml" ]; then
    echo "📦 Resolving dependencies for $pkg..."
    if grep -q "sdk: flutter" "$pkg/pubspec.yaml"; then
      (cd "$pkg" && flutter pub get)
    else
      (cd "$pkg" && dart pub get)
    fi
  fi
done
```

### 2. Verify Code Formatting
```bash
dart format --output=none --set-exit-if-changed packages/
```

### 3. Run Static Analysis (Zero Warnings / Fatal Infos)
```bash
for pkg in packages/*; do
  if [ -d "$pkg" ] && [ -f "$pkg/pubspec.yaml" ]; then
    echo "🔍 Analyzing $pkg..."
    if grep -q "sdk: flutter" "$pkg/pubspec.yaml"; then
      (cd "$pkg" && flutter analyze --fatal-infos)
    else
      (cd "$pkg" && dart analyze --fatal-infos)
    fi
  fi
done
```

### 4. Run Automated Test Suites
Runs `flutter test` for Flutter plugins and `dart test` for pure Dart packages:
```bash
for pkg in packages/*; do
  if [ -d "$pkg/test" ]; then
    echo "🧪 Running tests for $pkg..."
    if grep -q "sdk: flutter" "$pkg/pubspec.yaml"; then
      (cd "$pkg" && flutter test)
    else
      (cd "$pkg" && dart test)
    fi
  fi
done
```

---

## 🚀 Publishing to Pub.dev

Packages are published to [pub.dev](https://pub.dev) using the automated GitHub Actions workflow [`.github/workflows/publish.yml`](.github/workflows/publish.yml).

### Publishing via Git Tag
To release a package version, push a corresponding tag:
```bash
# Format: <package_name>-v<version>
git tag white_label_kit-v0.0.2
git push origin white_label_kit-v0.0.2
```

### Publishing via Workflow Dispatch
You can also trigger manual publishing with optional dry-run validation directly from GitHub Actions:
1. Navigate to **Actions** → **Publish to Pub.dev**.
2. Select the target package (`white_label_kit`, `dig_cli`, `apple_sign_in_plugin`).
3. Toggle dry-run mode or proceed with live publishing.

---

## 🤝 Quality Guidelines & Pull Requests

Every pull request must pass the automated CI pipeline:
- **0 Analysis Errors / Warnings**: Enforced via `--fatal-infos`.
- **Formatting**: Strictly adheres to standard `dart format`.
- **Tests**: 100% test pass rate across all packages.
- **Pana Health**: Maintained at maximum score without deprecated APIs.

---

## 📄 License

This monorepo and all individual packages are licensed under the **[MIT License](LICENSE)**.
