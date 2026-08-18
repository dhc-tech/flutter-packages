# Flutter Packages

[![CI Matrix Pipeline](https://github.com/dhc-tech/flutter-packages/actions/workflows/ci.yml/badge.svg)](https://github.com/dhc-tech/flutter-packages/actions/workflows/ci.yml)
[![Pub.dev Publisher](https://img.shields.io/badge/pub.dev-dhc--tech-0175C2.svg?logo=dart)](https://pub.dev/publishers/dhc.tech/packages)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

This repo is a companion repository containing the source code for Flutter plugins, developer CLI utilities, and multi-tenant tooling developed and maintained by **[DHC Tech](https://github.com/dhc-tech)**. Check the [`packages`](./packages) directory to see all packages.

These packages are also available on [pub.dev](https://pub.dev/publishers/dhc.tech/packages).

## Issues

Please file any issues, bugs, or feature requests in this repository's [Issue Tracker](https://github.com/dhc-tech/flutter-packages/issues/new/choose).
Issues are automatically triaged by package labels:
- [`p: white_label_kit`](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20white_label_kit)
- [`p: dig_cli`](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20dig_cli)
- [`p: apple_sign_in_plugin`](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20apple_sign_in_plugin)

## Contributing

If you wish to contribute a change to any of the existing packages in this repo or submit a new package, please review our [Contribution Guide](CONTRIBUTING.md) and send a [Pull Request](https://github.com/dhc-tech/flutter-packages/pulls).

## Packages

These are the packages hosted in this repository:

| Package | Pub | Points | Platform | Issues | Pull requests |
|---|---|---|---|---|---|
| [white_label_kit](./packages/white_label_kit/) | [![pub package](https://img.shields.io/pub/v/white_label_kit.svg)](https://pub.dev/packages/white_label_kit) | [![pub points](https://img.shields.io/pub/points/white_label_kit)](https://pub.dev/packages/white_label_kit/score) | [![Dart/Flutter](https://img.shields.io/badge/platform-Dart%20%7C%20Flutter-blue.svg)](https://pub.dev/packages/white_label_kit) | [![GitHub issues by-label](https://img.shields.io/github/issues/dhc-tech/flutter-packages/p%3A%20white_label_kit?label=)](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20white_label_kit) | [![GitHub PRs by-label](https://img.shields.io/github/issues-pr/dhc-tech/flutter-packages/p%3A%20white_label_kit?label=)](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20white_label_kit) |
| [dig_cli](./packages/dig_cli/) | [![pub package](https://img.shields.io/pub/v/dig_cli.svg)](https://pub.dev/packages/dig_cli) | [![pub points](https://img.shields.io/pub/points/dig_cli)](https://pub.dev/packages/dig_cli/score) | [![Dart CLI](https://img.shields.io/badge/platform-Dart%20CLI-blue.svg)](https://pub.dev/packages/dig_cli) | [![GitHub issues by-label](https://img.shields.io/github/issues/dhc-tech/flutter-packages/p%3A%20dig_cli?label=)](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20dig_cli) | [![GitHub PRs by-label](https://img.shields.io/github/issues-pr/dhc-tech/flutter-packages/p%3A%20dig_cli?label=)](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20dig_cli) |
| [apple_sign_in_plugin](./packages/apple_sign_in_plugin/) | [![pub package](https://img.shields.io/pub/v/apple_sign_in_plugin.svg)](https://pub.dev/packages/apple_sign_in_plugin) | [![pub points](https://img.shields.io/pub/points/apple_sign_in_plugin)](https://pub.dev/packages/apple_sign_in_plugin/score) | [![Flutter Plugin](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20Android%20%7C%20Web-blue.svg)](https://pub.dev/packages/apple_sign_in_plugin) | [![GitHub issues by-label](https://img.shields.io/github/issues/dhc-tech/flutter-packages/p%3A%20apple_sign_in_plugin?label=)](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20apple_sign_in_plugin) | [![GitHub PRs by-label](https://img.shields.io/github/issues-pr/dhc-tech/flutter-packages/p%3A%20apple_sign_in_plugin?label=)](https://github.com/dhc-tech/flutter-packages/labels/p%3A%20apple_sign_in_plugin) |

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
├── AUTHORS                            # 👥 List of contributors
├── CONTRIBUTING.md                    # 🤝 Contribution & development guide
├── AGENTS.md                          # 🤖 Authoritative AI engineering standards
├── GEMINI.md                          # ♊ Gemini assistant instructions
├── LICENSE                            # ⚖️ MIT Open Source License
└── README.md                          # 📖 Monorepo documentation
```

---

## 🛠️ Local Development & Testing

### Using Melos (Recommended)
```bash
# Bootstrap all package dependencies and links
melos bootstrap

# Run formatting check across all packages
melos run format

# Run static analysis with fatal-infos enforced
melos run analyze

# Execute all test suites
melos run test

# Run Pana health score check on all packages
melos run pana
```

### Using Standard CLI
```bash
# Analyze all packages
for pkg in packages/*; do
  echo "🔍 Analyzing $pkg..."
  if grep -q "sdk: flutter" "$pkg/pubspec.yaml"; then
    (cd "$pkg" && flutter analyze --fatal-infos)
  else
    (cd "$pkg" && dart analyze --fatal-infos)
  fi
done

# Run test suites
for pkg in packages/*; do
  if [ -d "$pkg/test" ]; then
    echo "🧪 Testing $pkg..."
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

Packages are deployed automatically via GitHub Actions:

1. **Tag-based Release:**
   ```bash
   git tag white_label_kit-v0.0.3
   git push origin white_label_kit-v0.0.3
   ```
2. **Manual Dispatch:** Run the **🚀 Publish to Pub.dev** GitHub Actions workflow with `dry_run: false`.
